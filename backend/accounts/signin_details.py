"""Changing the username and email a professional signs in with.

Neither was changeable before: Settings showed no field for either, and no
endpoint existed. A typo at signup meant contacting support.

Two rules shape everything here:

**Changes are rate limited.** One change per cooldown window per field. The
FIRST change is always allowed, whatever the account's age -- someone who
mistyped their username during signup notices in the first hour, and making
them wait a month to fix it is a worse outcome than the churn the limit exists
to prevent.

**A new email must prove itself first.** The address is not applied until a code
sent to it is entered. Taking a typed address on trust would let one hijacked
session move an account permanently out of its owner's reach, and it would also
silently strand anyone who fat-fingers their own address. The old address is
told either way, so a change the owner did not make is visible to them.
"""

import logging
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone

from .email_utils import send_mail_background
from .email_verification import send_email_otp, verify_email_otp
from .models import ProfessionalProfile

logger = logging.getLogger(__name__)

User = get_user_model()

EMAIL_CHANGE_PURPOSE = 'email-change'
# How long an unconfirmed address stays parked before it is treated as abandoned.
PENDING_EMAIL_TTL = timedelta(hours=1)


class SigninDetailError(Exception):
  """Raised with a user-safe message when a change cannot be made."""


def _cooldown_days() -> int:
  return int(getattr(settings, 'REPROOT_SIGNIN_CHANGE_COOLDOWN_DAYS', 30))


def _next_allowed(changed_at):
  if changed_at is None:
    return None
  return changed_at + timedelta(days=_cooldown_days())


def _assert_within_cooldown(changed_at, field_label: str) -> None:
  next_allowed = _next_allowed(changed_at)
  if next_allowed and next_allowed > timezone.now():
    days = max(1, (next_allowed - timezone.now()).days + 1)
    raise SigninDetailError(
      f'Your {field_label} was changed recently. You can change it again in {days} day(s).'
    )


def get_signin_details(user) -> dict:
  profile = user.professional_profile
  now = timezone.now()
  username_next = _next_allowed(profile.username_changed_at)
  email_next = _next_allowed(profile.email_changed_at)

  pending = profile.pending_email
  if pending and profile.pending_email_requested_at:
    if profile.pending_email_requested_at + PENDING_EMAIL_TTL <= now:
      pending = ''

  return {
    'username': user.username,
    'email': user.email,
    'cooldown_days': _cooldown_days(),
    'username_changed_at': profile.username_changed_at,
    'email_changed_at': profile.email_changed_at,
    'can_change_username': not username_next or username_next <= now,
    'can_change_email': not email_next or email_next <= now,
    'username_available_at': username_next,
    'email_available_at': email_next,
    'pending_email': pending,
  }


# --------------------------------------------------------------------------- username

def change_username(user, new_username: str) -> dict:
  from .serializers import USERNAME_CHARSET_MESSAGE, USERNAME_ALLOWED_PATTERN

  profile = user.professional_profile
  candidate = (new_username or '').strip()

  if not candidate:
    raise SigninDetailError('Enter a new username.')
  if candidate.lower() == user.username.lower():
    raise SigninDetailError('That is already your username.')
  if len(candidate) < 5 or len(candidate) > 30:
    raise SigninDetailError('Usernames must be between 5 and 30 characters.')
  if not USERNAME_ALLOWED_PATTERN.match(candidate):
    raise SigninDetailError(USERNAME_CHARSET_MESSAGE)
  if User.objects.filter(username__iexact=candidate).exclude(pk=user.pk).exists():
    raise SigninDetailError('That username is already taken.')

  _assert_within_cooldown(profile.username_changed_at, 'username')

  previous = user.username
  with transaction.atomic():
    user.username = candidate
    user.save(update_fields=['username'])
    profile.username_changed_at = timezone.now()
    profile.save(update_fields=['username_changed_at'])

  _notify(
    user.email,
    'Your RepRoot username was changed',
    (
      f'The username on your RepRoot professional account was changed from '
      f'"{previous}" to "{candidate}".\n\n'
      f'If you did not do this, change your password immediately and contact support.'
    ),
  )
  return get_signin_details(user)


# --------------------------------------------------------------------------- email

def request_email_change(user, new_email: str) -> dict:
  profile = user.professional_profile
  candidate = (new_email or '').strip().lower()

  if not candidate or '@' not in candidate:
    raise SigninDetailError('Enter a valid email address.')
  if candidate == (user.email or '').strip().lower():
    raise SigninDetailError('That is already your email address.')
  if User.objects.filter(email__iexact=candidate).exclude(pk=user.pk).exists():
    raise SigninDetailError('An account already exists with that email address.')

  _assert_within_cooldown(profile.email_changed_at, 'email address')

  # Reuse the signup/reset OTP machinery under its own purpose, so a code
  # issued for one flow can never be replayed into another.
  send_email_otp(candidate, purpose=EMAIL_CHANGE_PURPOSE)

  profile.pending_email = candidate
  profile.pending_email_requested_at = timezone.now()
  profile.save(update_fields=['pending_email', 'pending_email_requested_at'])

  # The current address is told a change was started, which is what makes an
  # unauthorised attempt visible to the real owner while it can still be stopped.
  _notify(
    user.email,
    'A change of email was requested on your RepRoot account',
    (
      f'Someone asked to move your RepRoot professional account to {candidate}.\n\n'
      f'The change only takes effect once a code sent to that address is entered. '
      f'Nothing has changed yet.\n\n'
      f'If this was not you, change your password immediately and contact support.'
    ),
  )
  return get_signin_details(user)


def confirm_email_change(user, code: str) -> dict:
  profile = user.professional_profile
  pending = (profile.pending_email or '').strip().lower()

  if not pending:
    raise SigninDetailError('There is no email change waiting to be confirmed.')

  if profile.pending_email_requested_at and \
     profile.pending_email_requested_at + PENDING_EMAIL_TTL <= timezone.now():
    profile.pending_email = ''
    profile.pending_email_requested_at = None
    profile.save(update_fields=['pending_email', 'pending_email_requested_at'])
    raise SigninDetailError('That request expired. Start the change again.')

  if not verify_email_otp(pending, (code or '').strip(), purpose=EMAIL_CHANGE_PURPOSE):
    raise SigninDetailError('That code is not correct or has expired.')

  # Re-check at the moment of application: the address could have been claimed
  # by another signup while this code was in flight.
  if User.objects.filter(email__iexact=pending).exclude(pk=user.pk).exists():
    raise SigninDetailError('An account already exists with that email address.')

  previous = user.email
  with transaction.atomic():
    user.email = pending
    user.save(update_fields=['email'])
    profile.email_changed_at = timezone.now()
    profile.pending_email = ''
    profile.pending_email_requested_at = None
    profile.save(update_fields=['email_changed_at', 'pending_email', 'pending_email_requested_at'])

  _notify(
    previous,
    'Your RepRoot email address was changed',
    (
      f'The email address on your RepRoot professional account was changed to {pending}.\n\n'
      f'This address will no longer receive account mail.\n\n'
      f'If you did not do this, contact support immediately.'
    ),
  )
  _notify(
    pending,
    'This is now your RepRoot email address',
    'Your RepRoot professional account now uses this address. Sign in with it from now on.',
  )
  return get_signin_details(user)


def cancel_email_change(user) -> dict:
  profile = user.professional_profile
  if not profile.pending_email:
    raise SigninDetailError('There is no email change to cancel.')
  profile.pending_email = ''
  profile.pending_email_requested_at = None
  profile.save(update_fields=['pending_email', 'pending_email_requested_at'])
  return get_signin_details(user)


def _notify(email: str, subject: str, body: str) -> None:
  address = (email or '').strip()
  if not address:
    return
  try:
    send_mail_background(subject, body, settings.DEFAULT_FROM_EMAIL, [address])
  except Exception:  # noqa: BLE001 - a notification must never break the change
    logger.exception('Could not queue sign-in details notification to %s', address)
