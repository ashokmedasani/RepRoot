"""API for the professional's sign-in details (username and email address)."""

from rest_framework import status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .access_permissions import ProfessionalAccessPermission
from .email_verification import OtpCooldownError
from .signin_details import (
  SigninDetailError, cancel_email_change, change_username, confirm_email_change,
  get_signin_details, request_email_change,
)


class _SigninDetailBase(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def _run(self, action, *args):
    try:
      return Response(action(*args))
    except SigninDetailError as error:
      return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)
    except OtpCooldownError as error:
      return Response({'detail': str(error)}, status=status.HTTP_429_TOO_MANY_REQUESTS)


class ProfessionalSigninDetailsView(_SigninDetailBase):
  def get(self, request):
    return Response(get_signin_details(request.user))


class ProfessionalUsernameChangeView(_SigninDetailBase):
  def post(self, request):
    return self._run(change_username, request.user, str(request.data.get('username', '')))


class ProfessionalEmailChangeRequestView(_SigninDetailBase):
  def post(self, request):
    return self._run(request_email_change, request.user, str(request.data.get('email', '')))


class ProfessionalEmailChangeConfirmView(_SigninDetailBase):
  def post(self, request):
    return self._run(confirm_email_change, request.user, str(request.data.get('code', '')))


class ProfessionalEmailChangeCancelView(_SigninDetailBase):
  def post(self, request):
    return self._run(cancel_email_change, request.user)
