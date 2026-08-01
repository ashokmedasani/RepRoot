from datetime import timedelta

from django.conf import settings
from django.utils import timezone
from rest_framework.authentication import TokenAuthentication
from rest_framework.authtoken.models import Token
from rest_framework.exceptions import AuthenticationFailed


class ExpiringTokenAuthentication(TokenAuthentication):
  """DRF token authentication with a bounded server-side lifetime."""

  def authenticate_credentials(self, key):
    user, token = super().authenticate_credentials(key)
    ttl_hours = max(1, int(settings.REPROOT_AUTH_TOKEN_TTL_HOURS))
    if token.created < timezone.now() - timedelta(hours=ttl_hours):
      token.delete()
      raise AuthenticationFailed('Session expired. Please log in again.')
    return user, token


def issue_professional_token(user):
  """Return a usable token, rotating an expired token during sign-in."""
  token, created = Token.objects.get_or_create(user=user)
  cutoff = timezone.now() - timedelta(hours=max(1, int(settings.REPROOT_AUTH_TOKEN_TTL_HOURS)))
  if not created and token.created < cutoff:
    token.delete()
    token = Token.objects.create(user=user)
  return token
