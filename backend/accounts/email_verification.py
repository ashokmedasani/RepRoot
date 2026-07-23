import secrets
import time
from dataclasses import dataclass

from django.core.cache import cache

from .email_utils import send_mail_background as send_mail


OTP_TTL_SECONDS = 600
VERIFIED_EMAIL_TTL_SECONDS = 1800
OTP_RESEND_COOLDOWN_SECONDS = 30
OTP_MAX_VERIFY_ATTEMPTS = 5


@dataclass(frozen=True)
class EmailVerificationResult:
  token: str


class OtpCooldownError(Exception):
  def __init__(self, remaining_seconds: int):
    self.remaining_seconds = remaining_seconds
    super().__init__(f'Please wait {remaining_seconds} seconds before requesting another OTP.')


def _otp_cache_key(email: str, purpose: str) -> str:
  return f'professional-email-otp:{purpose}:{email}'


def _otp_attempts_cache_key(email: str, purpose: str) -> str:
  return f'professional-email-otp-attempts:{purpose}:{email}'


def _otp_cooldown_cache_key(email: str, purpose: str) -> str:
  return f'professional-email-otp-cooldown:{purpose}:{email}'


def _verified_cache_key(token: str, purpose: str) -> str:
  return f'professional-email-verified:{purpose}:{token}'


def send_email_otp(email: str, purpose: str = 'signup') -> str:
  cooldown_key = _otp_cooldown_cache_key(email, purpose)
  cooldown_until = cache.get(cooldown_key)
  current_time = time.time()

  if cooldown_until and cooldown_until > current_time:
    raise OtpCooldownError(int(cooldown_until - current_time) + 1)

  otp = f'{secrets.randbelow(1_000_000):06d}'
  cache.set(_otp_cache_key(email, purpose), otp, OTP_TTL_SECONDS)
  cache.set(_otp_attempts_cache_key(email, purpose), 0, OTP_TTL_SECONDS)
  cache.set(cooldown_key, current_time + OTP_RESEND_COOLDOWN_SECONDS, OTP_RESEND_COOLDOWN_SECONDS)

  send_mail(
    subject='Your RepRoot verification code',
    message=f'Your RepRoot verification code is {otp}. It expires in 10 minutes.',
    from_email=None,
    recipient_list=[email],
    fail_silently=False,
  )

  return otp


def verify_email_otp(email: str, otp: str, purpose: str = 'signup') -> EmailVerificationResult | None:
  otp_key = _otp_cache_key(email, purpose)
  attempts_key = _otp_attempts_cache_key(email, purpose)
  expected_otp = cache.get(otp_key)

  if expected_otp is None:
    return None

  if str(expected_otp) != otp.strip():
    attempts = int(cache.get(attempts_key, 0)) + 1

    if attempts >= OTP_MAX_VERIFY_ATTEMPTS:
      cache.delete(otp_key)
      cache.delete(attempts_key)
      return None

    cache.set(attempts_key, attempts, OTP_TTL_SECONDS)
    return None

  token = secrets.token_urlsafe(32)
  cache.delete(otp_key)
  cache.delete(attempts_key)
  cache.set(_verified_cache_key(token, purpose), email, VERIFIED_EMAIL_TTL_SECONDS)
  return EmailVerificationResult(token=token)


def consume_verified_email_token(email: str, token: str, purpose: str = 'signup') -> bool:
  cache_key = _verified_cache_key(token, purpose)
  verified_email = cache.get(cache_key)

  if verified_email != email:
    return False

  cache.delete(cache_key)
  return True
