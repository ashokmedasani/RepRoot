"""
Account lifecycle management service for the 3-tier billing system.

Handles:
- Downgrade grace periods (7 days)
- Account freezing when over quota + grace expired
- Data deletion after 30 days frozen
- Overage notifications during grace period
"""

from datetime import timedelta
from django.utils import timezone
from django.conf import settings
from django.core.mail import send_mail
from accounts.models import ProfessionalProfile
from accounts.data_usage import calculate_professional_data_usage


def process_downgrade(professional_profile):
    """
    Initialize grace period when user downgrades from Pro/Premium to Starter Free.
    Call this when subscription is cancelled or plan_tier is downgraded.
    """
    professional_profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
    professional_profile.downgraded_at = timezone.now()
    professional_profile.grace_period_ends_at = timezone.now() + timedelta(
        days=settings.REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS
    )
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.save(update_fields=[
        'plan_tier', 'downgraded_at', 'grace_period_ends_at',
        'is_locked', 'locked_at', 'lock_reason'
    ])

    # Send downgrade notification email
    send_downgrade_email(professional_profile)


def reactivate_on_upgrade(professional_profile):
    """
    Clear lock flags when user upgrades to a paid tier or comes below quota.
    """
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.downgraded_at = None
    professional_profile.grace_period_ends_at = None
    professional_profile.save(update_fields=[
        'is_locked', 'locked_at', 'lock_reason', 'downgraded_at', 'grace_period_ends_at'
    ])


def check_and_lock_overages():
    """
    Daily task: Lock accounts that are:
    1. Over 100% quota
    2. Past their 7-day grace period
    3. Not already locked
    """
    now = timezone.now()
    profiles_to_lock = ProfessionalProfile.objects.filter(
        is_locked=False,
        grace_period_ends_at__lt=now,
        plan_tier=ProfessionalProfile.PLAN_STARTER_FREE,
    )

    for profile in profiles_to_lock:
        # Check if actually over quota
        usage = calculate_professional_data_usage(profile)
        if usage.get('is_over_quota'):
            profile.is_locked = True
            profile.locked_at = now
            profile.lock_reason = 'overage_grace_expired'
            profile.save(update_fields=['is_locked', 'locked_at', 'lock_reason'])

            # Send account frozen email
            send_account_frozen_email(profile)


def check_and_delete_data():
    """
    Daily task: Permanently delete data for accounts that have been locked for 30+ days.
    CAUTION: This is irreversible.
    """
    now = timezone.now()
    deletion_threshold = now - timedelta(days=settings.REPROOT_DATA_DELETION_DAYS)

    profiles_to_delete = ProfessionalProfile.objects.filter(
        is_locked=True,
        locked_at__lt=deletion_threshold,
    )

    for profile in profiles_to_delete:
        # Send final warning email before deletion
        send_data_deletion_email(profile)

        # Delete associated data (clients, templates, entries, references, etc.)
        delete_professional_data(profile)

        # Mark account as data-deleted
        profile.save(update_fields=['updated_at'])


def send_overage_notifications():
    """
    Daily task: Send reminder emails to accounts in grace period that are over quota.
    """
    now = timezone.now()

    profiles_in_grace = ProfessionalProfile.objects.filter(
        is_locked=False,
        grace_period_ends_at__gt=now,
        grace_period_ends_at__isnull=False,
        plan_tier=ProfessionalProfile.PLAN_STARTER_FREE,
    )

    for profile in profiles_in_grace:
        usage = calculate_professional_data_usage(profile)
        if usage.get('is_over_quota'):
            # Send overage notification (max once per day)
            last_sent = profile.last_overage_notification_sent_at
            if not last_sent or (now - last_sent).days >= 1:
                send_overage_notification_email(profile, usage)
                profile.last_overage_notification_sent_at = now
                profile.save(update_fields=['last_overage_notification_sent_at'])


def delete_professional_data(professional_profile):
    """
    Permanently delete all data associated with a professional account.
    This is called after 30 days of being locked (non-recoverable).
    """
    from accounts.models import ClientAccess
    from templates.models import TrackingTemplate, TrackingEntry
    from references.models import ReferenceCategory, Reference
    from forms_groups.models import LeadForm, ClientGroup

    # Delete all client-related data
    ClientAccess.objects.filter(professional=professional_profile.user).delete()

    # Delete templates and entries
    TrackingTemplate.objects.filter(professional=professional_profile.user).delete()
    TrackingEntry.objects.filter(professional=professional_profile.user).delete()

    # Delete references
    ReferenceCategory.objects.filter(professional=professional_profile.user).delete()
    Reference.objects.filter(professional=professional_profile.user).delete()

    # Delete forms and groups
    LeadForm.objects.filter(professional=professional_profile.user).delete()
    ClientGroup.objects.filter(professional=professional_profile.user).delete()


# Email notification functions

def send_downgrade_email(professional_profile):
    """Send email when account is downgraded."""
    subject = 'Your RepRoot Account Has Been Downgraded'
    message = f"""
Hello {professional_profile.user.first_name},

Your RepRoot subscription has been downgraded to Starter Free tier.

**What happens next:**
- You have 7 days (grace period) to either:
  1. Upgrade to Pro or Premium Unlimited tier
  2. Delete data to bring your usage below 100%

- After 7 days, if you haven't upgraded or reduced your data, your account will be **FROZEN**.
- All premium features (Templates, Forms, Client Management) are now locked.

**Grace period ends:** {professional_profile.grace_period_ends_at.strftime('%B %d, %Y at %I:%M %p')}

To upgrade or manage your data, log in to your account at {settings.REPROOT_FRONTEND_URL}/professional/account-settings

If you have questions, please contact our support team.

Best regards,
RepRoot Team
"""
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [professional_profile.user.email])


def send_account_frozen_email(professional_profile):
    """Send email when account is frozen due to overage."""
    subject = '🔒 Your RepRoot Account Has Been Frozen'
    message = f"""
Hello {professional_profile.user.first_name},

Your RepRoot account has been **FROZEN** because you exceeded your storage quota and the 7-day grace period has expired.

**What this means:**
- You cannot log in or access your account
- All data remains stored but is inaccessible
- Premium features remain locked

**To unlock your account:**
1. Upgrade to Pro or Premium Unlimited tier
2. Contact our support team to request account reactivation
3. We will reactivate your account within 24 hours of upgrade confirmation

**IMPORTANT:** If your account remains frozen for 30 days, all data will be permanently deleted (non-recoverable).

To upgrade or request support, email us at support@reproot.com or visit {settings.REPROOT_FRONTEND_URL}

Best regards,
RepRoot Team
"""
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [professional_profile.user.email])


def send_overage_notification_email(professional_profile, usage_data):
    """Send daily reminder email during grace period when over quota."""
    grace_ends = professional_profile.grace_period_ends_at
    days_left = (grace_ends - timezone.now()).days if grace_ends else 0
    usage_percent = usage_data.get('usage_percent', 0)

    subject = f'⚠️ Your RepRoot Storage Is Over Quota ({usage_percent:.0f}%)'
    message = f"""
Hello {professional_profile.user.first_name},

Your RepRoot account is using {usage_percent:.1f}% of your Starter Free storage quota.

**Time is running out:** Your grace period ends in {days_left} day(s) ({grace_ends.strftime('%B %d, %Y')}).

**What you need to do:**
1. **Upgrade to Pro** ($4.99/month) or **Premium Unlimited** ($14.99/month) to unlock all features
2. **Delete unused data** (entries, clients, references, templates) to bring usage below 100%

After your grace period expires, your account will be **frozen** and you won't be able to log in.

To upgrade or manage your data now, log in to {settings.REPROOT_FRONTEND_URL}/professional/account-settings

Don't let your account freeze! Act now.

Best regards,
RepRoot Team
"""
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [professional_profile.user.email])


def send_data_deletion_email(professional_profile):
    """Send final warning email before permanent data deletion."""
    subject = '⛔ FINAL WARNING: Your RepRoot Account Data Will Be Deleted'
    message = f"""
Hello {professional_profile.user.first_name},

Your RepRoot account has been frozen for 30 days without resolution.

**YOUR DATA WILL BE PERMANENTLY DELETED IN 24 HOURS.**

This is not reversible. Once deleted, all your client data, templates, entries, references, and account history cannot be recovered.

**To prevent deletion, you must:**
1. Upgrade to Pro or Premium Unlimited tier immediately
2. Contact support@reproot.com to request emergency account recovery

After 24 hours, your data will be erased automatically.

Take action now: {settings.REPROOT_FRONTEND_URL}/professional/account-settings

Best regards,
RepRoot Team
"""
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [professional_profile.user.email])
