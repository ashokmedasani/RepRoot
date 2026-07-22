"""
Feature access control for the 3-tier billing system.

Features that are locked when account is:
1. Downgraded to Starter Free (grace period)
2. Frozen due to overage
3. Over quota on current tier

Locked features:
- Templates (cannot create/edit, cannot submit entries)
- Forms (cannot access lead forms, client registration blocked)
- Client Management (cannot add clients, cannot edit client profiles)
- References (limited access)
- Chat (disabled)
"""

from django.conf import settings
from accounts.data_usage import calculate_professional_data_usage


class FeatureAccessError(Exception):
    """Raised when a feature is locked or not available."""
    pass


class FeatureLockReason:
    """Reason codes for feature locks."""
    ACCOUNT_LOCKED = 'account_locked'
    OVER_QUOTA = 'over_quota'
    PLAN_LIMIT = 'plan_limit'


def get_feature_access_status(professional_profile):
    """
    Get comprehensive feature access status for a professional account.

    Returns: {
        'can_manage_templates': bool,
        'can_manage_forms': bool,
        'can_add_clients': bool,
        'can_manage_references': bool,
        'can_use_chat': bool,
        'is_locked': bool,
        'lock_reason': str or None,
        'usage_percent': int,
        'is_over_quota': bool,
    }
    """
    usage = calculate_professional_data_usage(professional_profile.user)
    is_locked = professional_profile.is_locked
    is_over_quota = usage.get('is_over_quota', False)
    is_storage_blocked = usage.get('is_storage_blocked', False)

    return {
        'can_manage_templates': not is_locked,
        'can_manage_forms': not is_locked,
        'can_add_clients': not is_locked,
        'can_manage_references': not is_locked,
        'can_use_chat': not is_locked,
        'can_add_storage': not is_locked and not is_storage_blocked,
        'is_locked': is_locked,
        'lock_reason': professional_profile.lock_reason or None,
        'usage_percent': usage.get('usage_percent', 0),
        'is_over_quota': is_over_quota,
    }


def can_manage_templates(professional_profile) -> bool:
    """Check if professional can create/edit templates."""
    if professional_profile.is_locked:
        return False
    return True


def can_manage_forms(professional_profile) -> bool:
    """Check if professional can manage lead forms and client registration."""
    if professional_profile.is_locked:
        return False
    return True


def can_add_clients(professional_profile) -> bool:
    """Check if professional can add new clients."""
    if professional_profile.is_locked:
        return False
    return True


def can_edit_client(professional_profile) -> bool:
    """Check if professional can edit existing client profiles."""
    if professional_profile.is_locked:
        return False
    return True


def can_manage_references(professional_profile) -> bool:
    """Check if professional can upload/manage references."""
    if professional_profile.is_locked:
        return False
    return True


def can_use_chat(professional_profile) -> bool:
    """Check if professional can send messages in chat."""
    if professional_profile.is_locked:
        return False
    return True


def can_add_storage(professional_profile) -> bool:
    """Storage-heavy writes pause at 120%; text and cleanup remain available."""
    if professional_profile.is_locked:
        return False
    usage = calculate_professional_data_usage(professional_profile.user)
    return not usage.get('is_storage_blocked', False)


def assert_can_add_storage(professional_profile):
    if not can_add_storage(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'New uploads are paused: {reason}')


def assert_can_manage_templates(professional_profile):
    """Raise FeatureAccessError if templates cannot be managed."""
    if not can_manage_templates(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'Templates feature is locked: {reason}')


def assert_can_manage_forms(professional_profile):
    """Raise FeatureAccessError if forms cannot be managed."""
    if not can_manage_forms(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'Forms feature is locked: {reason}')


def assert_can_add_clients(professional_profile):
    """Raise FeatureAccessError if clients cannot be added."""
    if not can_add_clients(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'Client management feature is locked: {reason}')


def assert_can_edit_client(professional_profile):
    """Raise FeatureAccessError if client cannot be edited."""
    if not can_edit_client(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'Client management feature is locked: {reason}')


def assert_can_manage_references(professional_profile):
    """Raise FeatureAccessError if references cannot be managed."""
    if not can_manage_references(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'References feature is locked: {reason}')


def assert_can_use_chat(professional_profile):
    """Raise FeatureAccessError if chat cannot be used."""
    if not can_use_chat(professional_profile):
        reason = FeatureLockReason.ACCOUNT_LOCKED if professional_profile.is_locked else FeatureLockReason.OVER_QUOTA
        raise FeatureAccessError(f'Chat feature is locked: {reason}')


def check_feature_limits(professional_profile, feature_name: str, current_count: int) -> bool:
    """
    Check if professional has reached their plan's limit for a feature.

    Returns: True if allowed, False if limit reached.
    """
    from accounts.plan_limits import professional_plan

    plan_config = professional_plan(professional_profile)
    limit = plan_config.get(feature_name)

    if limit is None:
        return True  # No limit defined

    return current_count < limit
