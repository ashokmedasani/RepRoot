"""Self-service deletion of a professional account.

Replaces the old "contact Support to delete your account" note in Settings.

Two paths, both reversible for a window:

  hold      The account enters a cooling-off period. The professional can still
            sign in, and signing in cancels the deletion outright. Their clients
            lose access for the whole period and get it back untouched if the
            professional returns. Silence for the full period moves the account
            on to the recycle stage.

  immediate No further access for the professional, straight to the recycle
            stage. Deliberately NOT an instant unrecoverable wipe -- Support can
            still restore it, which is what makes a mis-click survivable.

Everything after the recycle stage is existing machinery:
`purge_expired_professional_accounts()` performs the final deletion, and
`restore_professional_from_recycle()` brings an account back with its password
cleared so the owner must reset it.

Why the hold state can log in but its clients cannot, with no extra checks:
`ClientLoginSerializer` already requires the professional to be
LIFECYCLE_ACTIVE, so any non-active status locks clients out on its own. Meanwhile
`_reject_login_if_locked` only refuses `is_locked` or `LIFECYCLE_RECYCLED`
accounts -- which is exactly why this state must never set `is_locked`.
"""

import logging
from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token

from .account_lifecycle import move_professional_to_recycle
from .email_utils import send_mail_background
from .models import (
  ChatMessage, ClientAccess, ClientAuthToken, ProfessionalGroup,
  ProfessionalLeadForm, ProfessionalProfile, ProfessionalResource,
  TrackingEntry, TrackingTemplate,
)

logger = logging.getLogger(__name__)


class DeletionError(Exception):
  """Raised with a user-safe message when a deletion request cannot proceed."""


def count_deletion_impact(user) -> dict:
  """What this professional stands to lose, counted live.

  Shown before they confirm and stored on the profile afterwards, so the record
  reflects what they were actually told rather than a recount taken later.
  """
  return {
    'clients': ClientAccess.objects.filter(professional=user).count(),
    'client_groups': ProfessionalGroup.objects.filter(professional=user).count(),
    'lead_forms': ProfessionalLeadForm.objects.filter(professional=user).count(),
    'resources': ProfessionalResource.objects.filter(professional=user).count(),
    'templates': TrackingTemplate.objects.filter(professional=user).count(),
    'tracking_entries': TrackingEntry.objects.filter(template__professional=user).count(),
    'messages': ChatMessage.objects.filter(professional=user).count(),
  }


def _revoke_client_access(user) -> None:
  """End every client session for this professional.

  Their ClientAccess rows are left untouched: access is refused by the
  professional's lifecycle status, so nothing has to be undone client-by-client
  if the deletion is cancelled.
  """
  ClientAuthToken.objects.filter(client__professional=user).delete()


def request_deletion(profile: ProfessionalProfile, *, mode: str, impact: dict | None = None) -> ProfessionalProfile:
  """Begin deletion. `mode` is 'hold' or 'immediate'."""
  if mode not in ('hold', 'immediate'):
    raise DeletionError('Choose whether to keep the account on hold or delete it immediately.')

  if profile.lifecycle_status == ProfessionalProfile.LIFECYCLE_RECYCLED:
    raise DeletionError('This account has already been deleted.')

  if profile.lifecycle_status == ProfessionalProfile.LIFECYCLE_PENDING_DELETION:
    raise DeletionError('Deletion is already scheduled for this account.')

  snapshot = impact if impact is not None else count_deletion_impact(profile.user)
  now = timezone.now()

  if mode == 'immediate':
    profile.deletion_requested_at = now
    profile.deletion_hold_ends_at = None
    profile.deletion_impact_snapshot = snapshot
    profile.save(update_fields=['deletion_requested_at', 'deletion_hold_ends_at', 'deletion_impact_snapshot'])
    # Sends its own confirmation, drops the account to the recycle stage, and
    # clears both professional and client tokens.
    move_professional_to_recycle(
      profile,
      reason=ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED,
      retention_days=settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS,
    )
    _send_deletion_email(profile, mode='immediate')
    return profile

  hold_days = settings.REPROOT_DELETION_HOLD_DAYS
  with transaction.atomic():
    profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_PENDING_DELETION
    profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED
    profile.deletion_requested_at = now
    profile.deletion_hold_ends_at = now + timedelta(days=hold_days)
    profile.deletion_impact_snapshot = snapshot
    profile.save(update_fields=[
      'lifecycle_status', 'lifecycle_reason', 'deletion_requested_at',
      'deletion_hold_ends_at', 'deletion_impact_snapshot',
    ])
    # The professional keeps their own session -- they are meant to be able to
    # come back. Only client sessions end.
    _revoke_client_access(profile.user)

  _send_deletion_email(profile, mode='hold')
  return profile


def cancel_deletion(profile: ProfessionalProfile, *, reason: str = 'signed in') -> bool:
  """Undo a pending deletion. Returns True if there was one to undo.

  Called both from Settings and automatically when the professional signs in,
  which is the promise made to them when they chose the hold.
  """
  if profile.lifecycle_status != ProfessionalProfile.LIFECYCLE_PENDING_DELETION:
    return False

  profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
  profile.lifecycle_reason = ''
  profile.deletion_requested_at = None
  profile.deletion_hold_ends_at = None
  profile.deletion_impact_snapshot = {}
  profile.save(update_fields=[
    'lifecycle_status', 'lifecycle_reason', 'deletion_requested_at',
    'deletion_hold_ends_at', 'deletion_impact_snapshot',
  ])
  # Client access resumes on its own: ClientLoginSerializer only ever checked
  # the professional's lifecycle status, and that is active again.
  _send_cancellation_email(profile, reason=reason)
  return True


def process_expired_deletion_holds() -> int:
  """Daily sweep: holds that ran their course become recycled accounts."""
  due = ProfessionalProfile.objects.select_related('user').filter(
    lifecycle_status=ProfessionalProfile.LIFECYCLE_PENDING_DELETION,
    deletion_hold_ends_at__lte=timezone.now(),
  )
  moved = 0
  for profile in due.iterator():
    try:
      move_professional_to_recycle(
        profile,
        reason=ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED,
        retention_days=settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS,
      )
      moved += 1
    except Exception:  # noqa: BLE001 - one bad row must not stop the sweep
      logger.exception('Could not recycle professional %s after deletion hold', profile.pk)
  return moved


# --------------------------------------------------------------------------- email

def _send_deletion_email(profile: ProfessionalProfile, *, mode: str) -> None:
  hold_days = settings.REPROOT_DELETION_HOLD_DAYS
  recycle_days = settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS
  counts = profile.deletion_impact_snapshot or {}
  itemised = '\n'.join(
    f'  {label:<18}{counts.get(key, 0)}'
    for key, label in (
      ('clients', 'Client accounts'), ('client_groups', 'Client groups'),
      ('lead_forms', 'Lead forms'), ('resources', 'Resources'),
      ('templates', 'Templates'), ('tracking_entries', 'Tracking entries'),
      ('messages', 'Messages'),
    )
  )

  if mode == 'hold':
    subject = 'Your RepRoot account is scheduled for deletion'
    body = (
      f'You asked us to delete your RepRoot professional account.\n\n'
      f'Nothing has been removed yet. You have {hold_days} days to change your mind — '
      f'just sign in and the deletion is cancelled automatically.\n\n'
      f'What happens now:\n'
      f'  - Your clients cannot sign in during this period.\n'
      f'  - If you sign in within {hold_days} days, everything returns exactly as it was.\n'
      f'  - If you do not, the account moves to our recycle stage and only our '
      f'support team can restore it, for {recycle_days} days.\n\n'
      f'What this account holds:\n{itemised}\n\n'
      f'If you did not request this, sign in now to cancel it.'
    )
  else:
    subject = 'Your RepRoot account has been deleted'
    body = (
      f'Your RepRoot professional account has been deleted at your request.\n\n'
      f'You and your clients no longer have access. The data is retained for '
      f'{recycle_days} days, during which our support team can restore the '
      f'account if this was a mistake. After that it is removed permanently.\n\n'
      f'What was deleted:\n{itemised}\n\n'
      f'If this was not you, contact support immediately.'
    )

  _send(profile, subject, body)


def _send_cancellation_email(profile: ProfessionalProfile, *, reason: str) -> None:
  _send(
    profile,
    'Your RepRoot account deletion was cancelled',
    (
      f'The scheduled deletion of your RepRoot professional account has been '
      f'cancelled ({reason}).\n\n'
      f'Your account is active again and your clients can sign in as before. '
      f'Nothing was lost.\n\n'
      f'If you did not do this, change your password and contact support.'
    ),
  )


def _send(profile: ProfessionalProfile, subject: str, body: str) -> None:
  email = (profile.user.email or '').strip()
  if not email:
    return
  try:
    send_mail_background(subject, body, settings.DEFAULT_FROM_EMAIL, [email])
  except Exception:  # noqa: BLE001 - never let a notification break a deletion
    logger.exception('Could not queue deletion email for professional %s', profile.pk)
