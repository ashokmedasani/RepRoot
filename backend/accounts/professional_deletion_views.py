"""API for self-service professional account deletion.

Kept out of views.py, which is already ~4,500 lines, following the same pattern
as public_contact.py and group_import.py.

The typed confirmations are enforced here rather than only in the browser: a
destructive action must not be reachable by anyone who skips the UI.
"""

from django.conf import settings
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .models import ProfessionalProfile
from .access_permissions import ProfessionalAccessPermission
from .professional_deletion import (
  DeletionError, cancel_deletion, count_deletion_impact, request_deletion,
)

# What the professional must type, exactly. Compared case-insensitively after
# trimming -- the point is deliberate intent, not typing accuracy.
CONFIRM_INTENT = 'YES'
CONFIRM_IMMEDIATE = 'delete my professional account immediately'


def _state(profile: ProfessionalProfile) -> dict:
  return {
    'lifecycle_status': profile.lifecycle_status,
    'is_deletion_pending': profile.lifecycle_status == ProfessionalProfile.LIFECYCLE_PENDING_DELETION,
    'deletion_requested_at': profile.deletion_requested_at,
    'deletion_hold_ends_at': profile.deletion_hold_ends_at,
    'hold_days': settings.REPROOT_DELETION_HOLD_DAYS,
    'recycle_days': settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS,
  }


class ProfessionalDeletionOverviewView(APIView):
  """Everything the confirmation dialog needs: live counts and current state."""

  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def get(self, request):
    profile = request.user.professional_profile
    payload = _state(profile)
    payload['impact'] = (
      profile.deletion_impact_snapshot
      if payload['is_deletion_pending'] and profile.deletion_impact_snapshot
      else count_deletion_impact(request.user)
    )
    return Response(payload)


class ProfessionalDeletionRequestView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    profile = request.user.professional_profile
    mode = str(request.data.get('mode', '')).strip().lower()
    intent = str(request.data.get('confirm_intent', '')).strip()
    acknowledged = bool(request.data.get('acknowledged_impact'))

    if intent.upper() != CONFIRM_INTENT:
      return Response(
        {'detail': f'Type {CONFIRM_INTENT} to confirm you want to delete this account.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    if not acknowledged:
      return Response(
        {'detail': 'Confirm you understand what will be deleted before continuing.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    if mode == 'immediate':
      typed = str(request.data.get('confirm_immediate', '')).strip().lower()
      if typed != CONFIRM_IMMEDIATE:
        return Response(
          {'detail': f'Type "{CONFIRM_IMMEDIATE}" to delete without the hold period.'},
          status=status.HTTP_400_BAD_REQUEST,
        )

    try:
      request_deletion(profile, mode=mode)
    except DeletionError as error:
      return Response({'detail': str(error)}, status=status.HTTP_400_BAD_REQUEST)

    profile.refresh_from_db()
    payload = _state(profile)
    payload['message'] = (
      'Your account is scheduled for deletion. Sign in any time before the hold '
      'ends to cancel it.'
      if mode == 'hold'
      else 'Your account has been deleted. Contact support if this was a mistake.'
    )
    return Response(payload, status=status.HTTP_200_OK)


class ProfessionalDeletionCancelView(APIView):
  """Undo a pending deletion from Settings.

  Signing in cancels it too, but someone already signed in when they change
  their mind needs a way that does not involve signing out first.
  """

  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def post(self, request):
    profile = request.user.professional_profile
    cancelled = cancel_deletion(profile, reason='you cancelled it from Settings')
    if not cancelled:
      return Response(
        {'detail': 'There is no scheduled deletion to cancel.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    profile.refresh_from_db()
    payload = _state(profile)
    payload['message'] = 'Deletion cancelled. Your account and your clients are active again.'
    return Response(payload)
