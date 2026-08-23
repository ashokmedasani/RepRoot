"""
Account lifecycle management service for the 3-tier billing system.

Handles:
- Downgrade grace periods (14 days)
- Account freezing when over quota + grace expired
- Data deletion after 30 days frozen
- Overage notifications during grace period
"""

from datetime import timedelta
from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.files.storage import default_storage
from django.db import transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token

from accounts.models import ClientAuthToken, ProfessionalProfile, RecycledProfessionalAccount
from accounts.data_usage import calculate_professional_data_usage
from accounts.email_utils import send_mail_background as send_mail
from accounts.plan_lock_cascade import sync_group_lock_cascade
from accounts.plan_lock_status import bust_lock_status_cache
from accounts.resource_cold_storage import sync_resource_cold_storage

User = get_user_model()


def process_downgrade(professional_profile):
    """
    Initialize grace period when user downgrades from Pro/Premium to Starter Free.
    Call this when subscription is cancelled or plan_tier is downgraded.
    """
    professional_profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
    professional_profile.downgraded_at = timezone.now()
    professional_profile.grace_period_ends_at = None
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    professional_profile.lifecycle_reason = ''
    professional_profile.save(update_fields=[
        'plan_tier', 'downgraded_at', 'grace_period_ends_at',
        'is_locked', 'locked_at', 'lock_reason', 'lifecycle_status', 'lifecycle_reason'
    ])

    cache.delete(f'professional-data-usage:v5:{professional_profile.user_id}')
    if calculate_professional_data_usage(professional_profile.user)['is_over_quota']:
        professional_profile.grace_period_ends_at = timezone.now() + timedelta(
            days=settings.REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS
        )
        professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_OVER_QUOTA_GRACE
        professional_profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE
        professional_profile.save(update_fields=['grace_period_ends_at', 'lifecycle_status', 'lifecycle_reason'])
        send_downgrade_email(professional_profile)

    bust_lock_status_cache(professional_profile.user_id)
    sync_group_lock_cascade(professional_profile.user)
    sync_resource_cold_storage(professional_profile.user)


def downgrade_to_starter_free_voluntarily(professional_profile):
    """
    Self-serve "cancel plan" / "back to Starter Free" — the professional chose
    this, so it should not look or behave like the involuntary-lapse path in
    process_downgrade(): no grace-period banner, no lock, unless their current
    usage genuinely doesn't fit in Starter Free's quota. In that case they get
    the same 14-day grace period an involuntary downgrade would give them, since
    the problem (too much data for the new quota) is identical either way.
    """
    professional_profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
    professional_profile.stripe_subscription_id = ''
    professional_profile.plan_renews_at = None
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.downgraded_at = None
    professional_profile.grace_period_ends_at = None
    professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    professional_profile.lifecycle_reason = ''
    professional_profile.save(update_fields=[
        'plan_tier', 'stripe_subscription_id', 'plan_renews_at',
        'is_locked', 'locked_at', 'lock_reason', 'downgraded_at', 'grace_period_ends_at',
        'lifecycle_status', 'lifecycle_reason',
    ])

    from django.core.cache import cache
    cache.delete(f'professional-data-usage:v5:{professional_profile.user_id}')

    usage = calculate_professional_data_usage(professional_profile.user)
    if usage['is_over_quota']:
        professional_profile.downgraded_at = timezone.now()
        professional_profile.grace_period_ends_at = timezone.now() + timedelta(
            days=settings.REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS
        )
        professional_profile.save(update_fields=['downgraded_at', 'grace_period_ends_at'])
        professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_OVER_QUOTA_GRACE
        professional_profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE
        professional_profile.save(update_fields=['lifecycle_status', 'lifecycle_reason'])
        send_downgrade_email(professional_profile)

    bust_lock_status_cache(professional_profile.user_id)
    sync_group_lock_cascade(professional_profile.user)
    sync_resource_cold_storage(professional_profile.user)


def downgrade_to_pro_voluntarily(professional_profile):
    """
    Self-serve "step down to Pro" -- lets a Premium professional choose a
    softer landing than going all the way to Free. Same self-serve
    guarantees as downgrade_to_starter_free_voluntarily(): no grace-period
    banner, no lock, unless usage genuinely doesn't fit Pro's quota, in
    which case the same 14-day grace period applies.
    """
    professional_profile.plan_tier = ProfessionalProfile.PLAN_PRO
    professional_profile.stripe_subscription_id = ''
    professional_profile.plan_renews_at = None
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.downgraded_at = None
    professional_profile.grace_period_ends_at = None
    professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    professional_profile.lifecycle_reason = ''
    professional_profile.save(update_fields=[
        'plan_tier', 'stripe_subscription_id', 'plan_renews_at',
        'is_locked', 'locked_at', 'lock_reason', 'downgraded_at', 'grace_period_ends_at',
        'lifecycle_status', 'lifecycle_reason',
    ])

    from django.core.cache import cache
    cache.delete(f'professional-data-usage:v5:{professional_profile.user_id}')

    usage = calculate_professional_data_usage(professional_profile.user)
    if usage['is_over_quota']:
        professional_profile.downgraded_at = timezone.now()
        professional_profile.grace_period_ends_at = timezone.now() + timedelta(
            days=settings.REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS
        )
        professional_profile.save(update_fields=['downgraded_at', 'grace_period_ends_at'])
        professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_OVER_QUOTA_GRACE
        professional_profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE
        professional_profile.save(update_fields=['lifecycle_status', 'lifecycle_reason'])
        send_downgrade_email(professional_profile)

    bust_lock_status_cache(professional_profile.user_id)
    sync_group_lock_cascade(professional_profile.user)
    sync_resource_cold_storage(professional_profile.user)


def reactivate_on_upgrade(professional_profile):
    """
    Clear lock flags when user upgrades to a paid tier or comes below quota.
    """
    professional_profile.is_locked = False
    professional_profile.locked_at = None
    professional_profile.lock_reason = ''
    professional_profile.downgraded_at = None
    professional_profile.grace_period_ends_at = None
    professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    professional_profile.lifecycle_reason = ''
    professional_profile.recycled_at = None
    professional_profile.recycle_expires_at = None
    professional_profile.recycled_by_reference = ''
    professional_profile.save(update_fields=[
        'is_locked', 'locked_at', 'lock_reason', 'downgraded_at', 'grace_period_ends_at',
        'lifecycle_status', 'lifecycle_reason', 'recycled_at', 'recycle_expires_at', 'recycled_by_reference'
    ])
    if not professional_profile.user.is_active:
        professional_profile.user.is_active = True
        professional_profile.user.save(update_fields=['is_active'])

    # Every plan_tier upgrade write (test-mode checkout, Stripe/Razorpay
    # webhooks) calls this right after saving the new tier, but the Settings >
    # Data Usage response is cached for REPROOT_DATA_USAGE_CACHE_SECONDS and
    # was never being invalidated here (unlike process_downgrade, which
    # already does this below) -- so a professional who just upgraded could
    # see their new plan badge immediately while the usage widget kept
    # showing their old plan's limits for up to that TTL.
    cache.delete(f'professional-data-usage:v5:{professional_profile.user_id}')
    bust_lock_status_cache(professional_profile.user_id)
    sync_group_lock_cascade(professional_profile.user)
    sync_resource_cold_storage(professional_profile.user)


def check_and_lock_overages():
    """
    Daily task: Lock accounts that are:
    1. Over 100% quota
    2. Past their 14-day grace period
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
        usage = calculate_professional_data_usage(profile.user)
        if usage.get('is_over_quota'):
            profile.is_locked = True
            profile.locked_at = now
            profile.lock_reason = 'overage_grace_expired'
            profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_FROZEN
            profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE
            profile.save(update_fields=['is_locked', 'locked_at', 'lock_reason', 'lifecycle_status', 'lifecycle_reason'])
            Token.objects.filter(user=profile.user).delete()
            ClientAuthToken.objects.filter(client__professional=profile.user).delete()

            # Send account frozen email
            send_account_frozen_email(profile)
        else:
            reactivate_on_upgrade(profile)


def check_and_delete_data():
    """
    Move unresolved accounts frozen for 30 days into a restorable 14-day
    professional Recycle Bin, then purge accounts whose recycle window expired.
    """
    now = timezone.now()
    deletion_threshold = now - timedelta(days=settings.REPROOT_DATA_DELETION_DAYS)

    profiles_to_delete = ProfessionalProfile.objects.filter(
        is_locked=True,
        locked_at__lt=deletion_threshold,
    )

    for profile in profiles_to_delete:
        move_professional_to_recycle(
            profile,
            reason=ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE,
            recycled_by_reference='SYSTEM',
        )

    purge_expired_professional_accounts()


def move_professional_to_recycle(professional_profile, *, reason, recycled_by_reference='', retention_days=None):
    """Soft-delete a complete professional graph without a lossy JSON copy.

    Callers that are recycling an ACCOUNT pass retention_days explicitly; the
    default keeps the historical per-item behaviour for any existing caller.
    """
    if retention_days is None:
        retention_days = settings.REPROOT_RECYCLE_BIN_DAYS
    now = timezone.now()
    with transaction.atomic():
        professional_profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_RECYCLED
        professional_profile.lifecycle_reason = reason
        professional_profile.recycled_at = now
        professional_profile.recycle_expires_at = now + timedelta(days=retention_days)
        professional_profile.recycled_by_reference = recycled_by_reference
        professional_profile.is_locked = True
        professional_profile.locked_at = professional_profile.locked_at or now
        professional_profile.lock_reason = reason
        professional_profile.save(update_fields=[
            'lifecycle_status', 'lifecycle_reason', 'recycled_at', 'recycle_expires_at',
            'recycled_by_reference', 'is_locked', 'locked_at', 'lock_reason',
        ])
        professional_profile.user.is_active = False
        professional_profile.user.save(update_fields=['is_active'])
        Token.objects.filter(user=professional_profile.user).delete()
        ClientAuthToken.objects.filter(client__professional=professional_profile.user).delete()
    cache.delete(f'professional-data-usage:v5:{professional_profile.user_id}')
    send_data_deletion_email(professional_profile)


def restore_professional_from_recycle(professional_profile):
    if professional_profile.lifecycle_status != ProfessionalProfile.LIFECYCLE_RECYCLED:
        raise ValueError('Professional account is not in the Recycle Bin.')
    if professional_profile.recycle_expires_at and professional_profile.recycle_expires_at <= timezone.now():
        raise ValueError('The restore window for this account has expired.')
    reactivate_on_upgrade(professional_profile)
    professional_profile.user.set_unusable_password()
    professional_profile.user.save(update_fields=['password'])
    send_mail(
        'Your RepRoot professional account was restored',
        (
            'Your complete professional workspace was restored during the 14-day recycle period. '
            f'For security, use Forgot Password to create a new password: {settings.REPROOT_FRONTEND_URL}/professional/forgot-password'
        ),
        settings.DEFAULT_FROM_EMAIL,
        [professional_profile.user.email],
    )


def purge_expired_professional_accounts():
    expired = ProfessionalProfile.objects.select_related('user').filter(
        lifecycle_status=ProfessionalProfile.LIFECYCLE_RECYCLED,
        recycle_expires_at__lte=timezone.now(),
    )
    for profile in expired.iterator():
        delete_professional_data(profile)
    RecycledProfessionalAccount.objects.filter(expires_at__lte=timezone.now()).delete()


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
        usage = calculate_professional_data_usage(profile.user)
        if usage.get('is_over_quota'):
            # Send overage notification (max once per day)
            last_sent = profile.last_overage_notification_sent_at
            if not last_sent or (now - last_sent).days >= 1:
                send_overage_notification_email(profile, usage)
                profile.last_overage_notification_sent_at = now
                profile.save(update_fields=['last_overage_notification_sent_at'])
        else:
            reactivate_on_upgrade(profile)


def delete_professional_data(professional_profile):
    """
    Permanently delete all data associated with a professional account.
    This is called after 30 days of being locked (non-recoverable).
    """
    from accounts.models import ClientAccess, ChatMessage, ManualPaymentProfile, PaymentProof, PaymentRecord, ProfessionalResource, SupportIncident

    user_id = professional_profile.user_id
    file_names = [
        professional_profile.profile_photo.name,
        professional_profile.certification_file.name,
        professional_profile.transformation_photo.name,
        professional_profile.training_photo.name,
    ]
    file_names += list(ProfessionalResource.objects.filter(professional_id=user_id).exclude(file='').values_list('file', flat=True))
    file_names += list(ChatMessage.objects.filter(professional_id=user_id).exclude(image='').values_list('image', flat=True))
    file_names += list(ManualPaymentProfile.objects.filter(professional_id=user_id).exclude(qr_code='').values_list('qr_code', flat=True))
    file_names += list(PaymentProof.objects.filter(payment_request__professional_id=user_id).exclude(proof_file='').values_list('proof_file', flat=True))
    file_names += list(PaymentRecord.objects.filter(professional_id=user_id).exclude(proof_file='').values_list('proof_file', flat=True))
    file_names += list(SupportIncident.objects.filter(reporter_professional_id=user_id).exclude(screenshot='').values_list('screenshot', flat=True))
    for file_name in {name for name in file_names if name}:
        if default_storage.exists(file_name):
            default_storage.delete(file_name)
    with transaction.atomic():
        # ClientAccess protects its group/submission parents. Remove clients
        # explicitly at final purge; their dependent rows cascade first.
        ClientAccess.objects.filter(professional_id=user_id).delete()
        User.objects.filter(pk=user_id).delete()
    cache.delete(f'professional-data-usage:v5:{user_id}')


# Email notification functions

def send_downgrade_email(professional_profile):
    """Send email when account is downgraded."""
    subject = 'Your RepRoot Account Has Been Downgraded'
    message = f"""
Hello {professional_profile.user.first_name},

Your RepRoot subscription has been downgraded to the Free tier.

**What happens next:**
- You have 14 days (grace period) to either:
  1. Upgrade to Pro or Premium Unlimited tier
  2. Delete data to bring your usage below 100%

- After 14 days, if you haven't upgraded or reduced your data, your account will be **FROZEN**.
- Your workspace remains available during the grace period so you can review, export, or reduce storage.

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

Your RepRoot account has been **FROZEN** because you exceeded your Starter storage quota and the 14-day grace period has expired.

**What this means:**
- You cannot log in or access your account
- All data remains stored but is inaccessible
- Premium features remain locked

**To unlock your account:**
1. Upgrade to Pro or Premium Unlimited tier
2. Contact our support team to request account reactivation
3. We will reactivate your account within 24 hours of upgrade confirmation

**IMPORTANT:** After 30 frozen days, the account enters a final 14-day Recycle Bin. Support can restore it during that window; deletion after expiry is permanent.

To upgrade or request support, email us at {settings.SUPPORT_EMAIL or settings.DEFAULT_FROM_EMAIL} or visit {settings.REPROOT_FRONTEND_URL}

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

Your RepRoot account is using {usage_percent:.1f}% of your Free storage quota.

**Time is running out:** Your grace period ends in {days_left} day(s) ({grace_ends.strftime('%B %d, %Y')}).

**What you need to do:**
1. **Upgrade your storage plan** (pricing will be shown in the application when finalized)
2. **Delete unused files or data** to bring usage below 100%

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

**YOUR DATA IS NOW IN A 14-DAY RECYCLE PERIOD.**

Support can restore the complete account during these 14 days. After the recycle period expires, all client data, templates, entries, resources, files, and account history will be permanently deleted.

**To prevent deletion, you must:**
1. Upgrade to Pro or Premium Unlimited tier immediately
2. Contact {settings.SUPPORT_EMAIL or settings.DEFAULT_FROM_EMAIL} to request emergency account recovery

After 14 days, your data will be erased automatically.

Take action now: {settings.REPROOT_FRONTEND_URL}/professional/account-settings

Best regards,
RepRoot Team
"""
    send_mail(subject, message, settings.DEFAULT_FROM_EMAIL, [professional_profile.user.email])
