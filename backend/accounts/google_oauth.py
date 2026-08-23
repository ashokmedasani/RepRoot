"""Google "Continue with Google" sign-in/signup for professional accounts.

This intentionally reuses the plain `requests` dependency already used by
`google_calendar.py` instead of adding `google-auth` to requirements.txt, by
verifying the ID token against Google's tokeninfo endpoint. That endpoint is
rate-limited and meant for debugging by Google's own docs, but it is a
commonly used lightweight verification path and is adequate here because:

  - the token itself was already produced by Google Identity Services running
    in the user's browser (we never accept a token we mint ourselves), and
  - we still independently check `aud`, `iss`, and `email_verified` below.

If Google sign-in volume grows meaningfully, swap this for
`google.oauth2.id_token.verify_oauth2_token` (the `google-auth` package),
which verifies the JWT signature locally instead of round-tripping to Google.

This is a separate Google Cloud OAuth client from the Calendar/Meet
integration (`GOOGLE_CALENDAR_CLIENT_ID`) -- see `GOOGLE_OAUTH_CLIENT_ID` in
settings.py. It is a public client ID, safe to embed in frontend code, unlike
the calendar client's secret.
"""

import random
import re

import requests
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone

from .email_policy import SignupEmailDomainError, validate_signup_email_domain
from .models import LegalAcceptanceRecord, ProfessionalProfile

User = get_user_model()

GOOGLE_TOKENINFO_URL = 'https://oauth2.googleapis.com/tokeninfo'
USERNAME_ALLOWED_PATTERN = re.compile(r'^[A-Za-z0-9.\-]+$')


class GoogleAuthError(Exception):
  """Raised with a user-safe message whenever Google sign-in cannot proceed."""


def verify_google_id_token(id_token: str, timeout: int = 10) -> dict:
  """Verify a Google Identity Services ID token and return its claims."""
  if not settings.GOOGLE_OAUTH_ENABLED:
    raise GoogleAuthError('Google sign-in is not available right now.')

  if not id_token or not id_token.strip():
    raise GoogleAuthError('Missing Google credential.')

  try:
    response = requests.get(GOOGLE_TOKENINFO_URL, params={'id_token': id_token.strip()}, timeout=timeout)
  except requests.RequestException:
    raise GoogleAuthError('Could not reach Google to verify sign-in. Please try again.')

  if response.status_code != 200:
    raise GoogleAuthError('Google sign-in could not be verified. Please try again.')

  try:
    claims = response.json()
  except ValueError:
    raise GoogleAuthError('Google sign-in could not be verified. Please try again.')

  if claims.get('aud') != settings.GOOGLE_OAUTH_CLIENT_ID:
    raise GoogleAuthError('Google sign-in could not be verified for this application.')

  if claims.get('iss') not in ('accounts.google.com', 'https://accounts.google.com'):
    raise GoogleAuthError('Google sign-in could not be verified.')

  if str(claims.get('email_verified')).lower() != 'true':
    raise GoogleAuthError('This Google account’s email is not verified with Google.')

  if not claims.get('email') or not claims.get('sub'):
    raise GoogleAuthError('Google did not return an email address and identifier.')

  return claims


def _base_username_from_email(email: str) -> str:
  local_part = email.split('@', 1)[0].lower()
  cleaned = re.sub(r'[^a-z0-9.\-]', '', local_part) or 'trainer'
  cleaned = cleaned[:24]

  if len(cleaned) < 5:
    cleaned = f'{cleaned}{random.randint(100, 999)}'

  return cleaned


def _generate_unique_username(email: str) -> str:
  base = _base_username_from_email(email)

  if not User.objects.filter(username__iexact=base).exists():
    return base

  for suffix in random.sample(range(1, 10000), 25):
    candidate = f'{base[:24]}{suffix}'
    if not USERNAME_ALLOWED_PATTERN.match(candidate):
      continue
    if not User.objects.filter(username__iexact=candidate).exists():
      return candidate

  # Astronomically unlikely fallback: timestamp-based suffix is always unique.
  return f'{base[:16]}{int(timezone.now().timestamp())}'


def get_or_create_professional_for_google(claims: dict, allow_create: bool = False) -> tuple:
  """Resolve Google claims to a professional User, creating one if needed.

  Returns (user, created). Raises GoogleAuthError for account-linking
  conflicts that must not be resolved silently (e.g. the Google email already
  belongs to a client-only account).
  """
  email = claims['email'].strip().lower()
  google_sub = claims['sub']

  linked_profile = ProfessionalProfile.objects.select_related('user').filter(google_sub=google_sub).first()
  if linked_profile:
    return linked_profile.user, False

  existing_user = User.objects.filter(email__iexact=email).first()

  if existing_user:
    if not hasattr(existing_user, 'professional_profile'):
      raise GoogleAuthError(
        'An account already exists with this email and is not a professional account.'
      )

    # Existing email/password professional account signing in with Google for
    # the first time: link it rather than creating a duplicate account.
    profile = existing_user.professional_profile
    if not profile.google_sub:
      profile.google_sub = google_sub
      profile.google_linked_at = timezone.now()
      profile.save(update_fields=['google_sub', 'google_linked_at', 'updated_at'])
    return existing_user, False

  if not allow_create:
    raise GoogleAuthError(
      'No professional account exists for this Google address. Use the sign-up page and accept the legal terms first.'
    )

  try:
    email = validate_signup_email_domain(email)
  except SignupEmailDomainError as error:
    raise GoogleAuthError(str(error)) from error

  with transaction.atomic():
    username = _generate_unique_username(email)
    given_name = (claims.get('given_name') or '').strip()
    family_name = (claims.get('family_name') or '').strip()

    user = User.objects.create_user(
      username=username,
      email=email,
      password=None,  # Unusable password: this account can only sign in via Google
      first_name=given_name[:150],
      last_name=family_name[:150],
    )
    user.set_unusable_password()
    user.save(update_fields=['password'])

    accepted_at = timezone.now()
    profile = ProfessionalProfile.objects.create(
      user=user,
      google_sub=google_sub,
      google_linked_at=timezone.now(),
      terms_accepted=True,
      privacy_policy_accepted=True,
      terms_accepted_at=accepted_at,
      privacy_policy_accepted_at=accepted_at,
      legal_document_version=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
    )
    LegalAcceptanceRecord.objects.create(
      actor_type=LegalAcceptanceRecord.ACTOR_PROFESSIONAL,
      professional_profile=profile,
      actor_reference=profile.professional_id or str(user.id),
      legal_document_version=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
      accepted_at=accepted_at,
    )

  return user, True
