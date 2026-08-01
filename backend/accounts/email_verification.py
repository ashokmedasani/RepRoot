import secrets
import time
from dataclasses import dataclass
from html import escape

from django.conf import settings
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


def _otp_email_content(otp: str, purpose: str) -> tuple[str, str, str]:
  is_password_reset = purpose == 'password-reset'
  action = 'reset your password' if is_password_reset else 'verify your email address'
  heading = 'Password reset verification' if is_password_reset else 'Verify your email address'
  subject = f'{otp} is your RepRoot Studio verification code'
  support_email = settings.STUDIO_SUPPORT_EMAIL

  plain_text = (
    f'RepRoot Studio\n\n{heading}\n\n'
    f'Use this verification code to {action}:\n\n{otp}\n\n'
    'This code expires in 10 minutes and can be used only once.\n\n'
    'Never share this code. RepRoot Studio support will never ask for it. '
    'If you did not request this code, you can safely ignore this email.\n\n'
    f'Need help? Contact {support_email}.\n\n'
    'RepRoot Studio · A product of RepRoot'
  )

  html_message = f'''<!doctype html>
<html lang="en">
  <body style="margin:0;padding:0;background:#f4f7fc;color:#101828;font-family:Arial,Helvetica,sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f7fc;padding:32px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border:1px solid #dbe5f5;border-radius:16px;overflow:hidden;">
          <tr><td style="padding:24px 32px;background:#155eef;color:#ffffff;font-size:20px;font-weight:700;">RepRoot Studio</td></tr>
          <tr><td style="padding:32px;">
            <p style="margin:0 0 8px;color:#155eef;font-size:12px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;">Secure verification</p>
            <h1 style="margin:0 0 14px;font-size:26px;line-height:1.25;">{heading}</h1>
            <p style="margin:0 0 24px;color:#475467;font-size:15px;line-height:1.6;">Use the code below to {action}.</p>
            <div style="margin:0 0 24px;padding:18px;border:1px solid #b9cef8;border-radius:12px;background:#eef4ff;color:#123fb7;font-size:32px;font-weight:700;letter-spacing:8px;text-align:center;">{escape(otp)}</div>
            <p style="margin:0 0 8px;color:#344054;font-size:14px;line-height:1.6;"><strong>Expires in 10 minutes.</strong> This code can be used only once.</p>
            <p style="margin:0;color:#667085;font-size:13px;line-height:1.6;">Never share this code. RepRoot Studio support will never ask for it. If you did not request this email, no action is required.</p>
          </td></tr>
          <tr><td style="padding:20px 32px;border-top:1px solid #e4e7ec;background:#f9fafb;color:#667085;font-size:12px;line-height:1.6;">Need help? <a href="mailto:{support_email}" style="color:#155eef;">{support_email}</a><br>RepRoot Studio · A product of RepRoot</td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>'''
  return subject, plain_text, html_message


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

  subject, plain_text, html_message = _otp_email_content(otp, purpose)
  send_mail(
    subject=subject,
    message=plain_text,
    from_email=None,
    recipient_list=[email],
    fail_silently=False,
    html_message=html_message,
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
