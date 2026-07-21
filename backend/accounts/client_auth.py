"""Token authentication for client portal users.

Clients are ClientAccess records, not Django users, so DRF's built-in
TokenAuthentication cannot be used. This module issues opaque tokens for
clients and authenticates requests carrying `Authorization: ClientToken <key>`.
The authenticated ClientAccess record is exposed as `request.auth`.
"""

import binascii
import os

from rest_framework import authentication, exceptions, permissions

from .models import ClientAccess, ClientAuthToken


def generate_client_token_key() -> str:
  return binascii.hexlify(os.urandom(20)).decode()


def issue_client_token(client_access: ClientAccess) -> ClientAuthToken:
  token, created = ClientAuthToken.objects.get_or_create(
    client=client_access,
    defaults={'key': generate_client_token_key()},
  )

  if not created and not token.key:
    token.key = generate_client_token_key()
    token.save(update_fields=['key'])

  return token


class ClientTokenAuthentication(authentication.BaseAuthentication):
  keyword = 'ClientToken'

  def authenticate(self, request):
    auth_header = authentication.get_authorization_header(request).split()

    if not auth_header or auth_header[0].lower() != self.keyword.lower().encode():
      return None

    if len(auth_header) != 2:
      raise exceptions.AuthenticationFailed('Invalid client token header.')

    try:
      key = auth_header[1].decode()
    except UnicodeError:
      raise exceptions.AuthenticationFailed('Invalid client token header.')

    token = ClientAuthToken.objects.select_related('client__professional', 'client__group', 'client__lead_submission').filter(key=key).first()

    if token is None or not token.client.is_active:
      raise exceptions.AuthenticationFailed('Invalid or expired client token.')

    return (None, token.client)

  def authenticate_header(self, request):
    return self.keyword


class IsAuthenticatedClient(permissions.BasePermission):
  message = 'Client authentication required.'

  def has_permission(self, request, view):
    return isinstance(request.auth, ClientAccess)
