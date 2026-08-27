from django.conf import settings


class SignupEmailDomainError(ValueError):
  pass


def validate_signup_email_domain(value: str) -> str:
  """Normalize and validate an address against the new-account policy."""
  email = value.strip().lower()
  domain = email.rsplit('@', 1)[-1].rstrip('.')
  blocked_domains = getattr(settings, 'REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS', set())
  allowed_domains = getattr(settings, 'REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS', set())

  def matches(configured_domain: str) -> bool:
    return domain == configured_domain or domain.endswith(f'.{configured_domain}')

  if any(matches(blocked_domain) for blocked_domain in blocked_domains):
    raise SignupEmailDomainError(
      'Please use a permanent email address from an approved provider.'
    )

  if allowed_domains and not any(matches(allowed_domain) for allowed_domain in allowed_domains):
    raise SignupEmailDomainError(
      'Please use an email address from one of the approved providers.'
    )

  return email
