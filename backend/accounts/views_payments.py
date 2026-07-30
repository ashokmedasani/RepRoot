"""Client Payments views.

Money professionals collect FROM their clients — completely separate from
RepRoot Studio Billing (professionals paying RepRoot, see billing.py).
Kept in its own module so the main views.py doesn't keep growing.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.conf import settings
from django.db.models import Sum
from django.http import FileResponse
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient
from .access_permissions import ProfessionalAccessPermission
from .data_retention import visible_client_data_cutoff
from .models import (
  ActivityNotification,
  ClientAccess,
  ClientPaymentMethodAccess,
  ManualPaymentProfile,
  PaymentNotification,
  PaymentProof,
  PaymentRecord,
  PaymentRequest,
  PaymentRequestAllowedMethod,
  ProfessionalPaymentSettings,
)
from .payment_audit import record_payment_action
from . import payment_notifications
from . import web_routes
from .payment_constants import FEATURED_CURRENCIES, ISO_4217_CODES
from .serializers import (
  PaymentConfirmationSerializer,
  ClientPaymentRecordSerializer,
  ClientPaymentRequestSerializer,
  ManualPaymentProfileClientSerializer,
  ManualPaymentProfileSerializer,
  PaymentProofSerializer,
  PaymentProofSubmitSerializer,
  PaymentRecordSerializer,
  PaymentRequestSerializer,
  ProfessionalPaymentSettingsSerializer,
  detect_upload_content_type,
)


def _currency_options():
  featured = list(FEATURED_CURRENCIES)
  rest = sorted(ISO_4217_CODES - set(featured))
  return featured + rest


def _serialize_payment_notification(row):
  return {
    'id': row.id, 'notif_type': row.notif_type, 'title': row.title,
    'body': row.body, 'payload': row.payload, 'is_read': row.is_read,
    'created_at': row.created_at,
  }


def _mark_payment_notifications_read(recipient_filter, *, request_id=None):
  """Marks PaymentNotification rows read for one recipient. Scoping to a single
  request_id lets a "view this request" action clear just that item's unread
  state, instead of the previous all-or-nothing mark-all behavior.

  Also mirrors the same mark-read onto ActivityNotification (category=
  'payments') for the same recipient/request, since payment_notifications.py
  dual-writes every payment event into both tables. Without this, the
  general notification bell and the payments-specific unread count could
  disagree about the same event - exactly the "separate conflicting
  counters" the client reported."""
  qs = PaymentNotification.objects.filter(is_read=False, **recipient_filter)
  activity_filter = {key: value for key, value in recipient_filter.items() if key != 'created_at__gte'}
  activity_qs = ActivityNotification.objects.filter(is_read=False, category='payments', **activity_filter)
  if request_id:
    qs = qs.filter(payload__request_id=request_id)
    activity_qs = activity_qs.filter(payload__request_id=request_id)
  qs.update(is_read=True)
  activity_qs.update(is_read=True, read_at=timezone.now())


class ProfessionalPaymentSettingsView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    settings_row, _ = ProfessionalPaymentSettings.objects.get_or_create(professional=request.user)
    payload = ProfessionalPaymentSettingsSerializer(settings_row).data
    if not settings.REPROOT_PAYMENTS_ENABLED:
      payload['payment_tracking_enabled'] = False
      payload['client_payment_history_enabled'] = False
    return Response(
      {
        'settings': payload,
        'currency_options': _currency_options(),
      }
    )

  def put(self, request):
    if not settings.REPROOT_PAYMENTS_ENABLED:
      return Response(
        {'message': 'Payments are not available yet.'},
        status=status.HTTP_503_SERVICE_UNAVAILABLE,
      )
    settings_row, _ = ProfessionalPaymentSettings.objects.get_or_create(professional=request.user)
    serializer = ProfessionalPaymentSettingsSerializer(settings_row, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    if request.data.get('confirm_reporting_currency') is True and not settings_row.reporting_currency_locked:
      settings_row.reporting_currency_locked = True
      settings_row.reporting_currency_locked_at = timezone.now()
      settings_row.save(update_fields=['reporting_currency_locked', 'reporting_currency_locked_at', 'updated_at'])
    return Response(
      {
        'settings': ProfessionalPaymentSettingsSerializer(settings_row).data,
        'currency_options': _currency_options(),
        'message': 'Payment settings saved.',
      }
    )


class ManualPaymentProfileListView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [JSONParser, FormParser, MultiPartParser]

  def get(self, request):
    profiles = ManualPaymentProfile.objects.filter(professional=request.user)
    return Response(
      {
        'methods': ManualPaymentProfileSerializer(profiles, many=True).data,
        'max_active': ManualPaymentProfile.MAX_ACTIVE_PROFILES,
      }
    )

  def post(self, request):
    active_count = ManualPaymentProfile.objects.filter(
      professional=request.user, status=ManualPaymentProfile.STATUS_ACTIVE
    ).count()
    if active_count >= ManualPaymentProfile.MAX_ACTIVE_PROFILES:
      return Response(
        {'message': "You've reached the limit of 5 active payment methods. Deactivate one before adding another."},
        status=status.HTTP_400_BAD_REQUEST,
      )

    serializer = ManualPaymentProfileSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    profile = serializer.save(professional=request.user)

    record_payment_action(
      action='method_created',
      professional=request.user,
      changed_by=request.user.username,
      new_values={'id': profile.id, 'category': profile.category, 'display_label': profile.display_label},
    )

    return Response(
      {'method': ManualPaymentProfileSerializer(profile).data, 'message': 'Payment method saved.'},
      status=status.HTTP_201_CREATED,
    )


class ManualPaymentProfileDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [JSONParser, FormParser, MultiPartParser]

  def get_profile(self, request, method_id):
    return ManualPaymentProfile.objects.filter(id=method_id, professional=request.user).first()

  def get(self, request, method_id):
    profile = self.get_profile(request, method_id)
    if profile is None:
      return Response({'message': 'Payment method not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'method': ManualPaymentProfileSerializer(profile).data})

  def put(self, request, method_id):
    profile = self.get_profile(request, method_id)
    if profile is None:
      return Response({'message': 'Payment method not found.'}, status=status.HTTP_404_NOT_FOUND)

    if request.data.get('status') == ManualPaymentProfile.STATUS_ACTIVE and profile.status != ManualPaymentProfile.STATUS_ACTIVE:
      active_count = ManualPaymentProfile.objects.filter(
        professional=request.user, status=ManualPaymentProfile.STATUS_ACTIVE
      ).count()
      if active_count >= ManualPaymentProfile.MAX_ACTIVE_PROFILES:
        return Response(
          {'message': "You've reached the limit of 5 active payment methods. Deactivate one before reactivating this."},
          status=status.HTTP_400_BAD_REQUEST,
        )

    previous = {
      'category': profile.category,
      'display_label': profile.display_label,
      'status': profile.status,
    }

    serializer = ManualPaymentProfileSerializer(profile, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    profile = serializer.save()

    record_payment_action(
      action='method_updated',
      professional=request.user,
      changed_by=request.user.username,
      previous_values=previous,
      new_values={'category': profile.category, 'display_label': profile.display_label, 'status': profile.status},
    )

    return Response({'method': ManualPaymentProfileSerializer(profile).data, 'message': 'Payment method updated.'})

  def delete(self, request, method_id):
    profile = self.get_profile(request, method_id)
    if profile is None:
      return Response({'message': 'Payment method not found.'}, status=status.HTTP_404_NOT_FOUND)

    record_payment_action(
      action='method_updated',
      professional=request.user,
      changed_by=request.user.username,
      previous_values={'id': profile.id, 'display_label': profile.display_label, 'status': profile.status},
      new_values={'status': 'deleted'},
      reason=str(request.data.get('reason') or ''),
    )
    profile.delete()
    return Response({'message': 'Payment method deleted.'})


class ManualPaymentProfilePreviewView(APIView):
  """Exactly what a client sees for this method - rendered from the same
  redacted serializer the real client endpoints use, so the preview can never
  drift from reality."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, method_id):
    profile = ManualPaymentProfile.objects.filter(id=method_id, professional=request.user).first()
    if profile is None:
      return Response({'message': 'Payment method not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'preview': ManualPaymentProfileClientSerializer(profile).data})


class ClientPaymentMethodAccessView(APIView):
  """Which of the professional's manual payment methods a specific client can
  see. Methods are private by default - nothing is visible until shared here."""

  permission_classes = [ProfessionalAccessPermission]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    shared_ids = set(
      ClientPaymentMethodAccess.objects.filter(client=client, is_visible=True).values_list('payment_profile_id', flat=True)
    )
    methods = ManualPaymentProfile.objects.filter(professional=request.user)
    rows = []
    for method in methods:
      row = ManualPaymentProfileSerializer(method).data
      row['shared'] = method.id in shared_ids
      rows.append(row)

    return Response({'methods': rows})

  def put(self, request, client_id):
    client = self._client(request, client_id)
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    method_ids = request.data.get('method_ids')
    if not isinstance(method_ids, list):
      return Response({'message': 'method_ids must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

    owned_active = {
      profile.id: profile
      for profile in ManualPaymentProfile.objects.filter(
        professional=request.user, status=ManualPaymentProfile.STATUS_ACTIVE
      )
    }
    invalid = [method_id for method_id in method_ids if method_id not in owned_active]
    if invalid:
      return Response(
        {'message': 'Only your own active payment methods can be shared.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    desired = set(method_ids)
    existing = {
      grant.payment_profile_id: grant
      for grant in ClientPaymentMethodAccess.objects.filter(client=client)
    }

    for method_id, profile in owned_active.items():
      grant = existing.get(method_id)
      should_share = method_id in desired

      if should_share and (grant is None or not grant.is_visible):
        if grant is None:
          ClientPaymentMethodAccess.objects.create(client=client, payment_profile=profile, is_visible=True)
        else:
          grant.is_visible = True
          grant.disabled_at = None
          grant.save(update_fields=['is_visible', 'disabled_at'])
        record_payment_action(
          action='method_shared',
          professional=request.user,
          client=client,
          changed_by=request.user.username,
          new_values={'method_id': method_id, 'display_label': profile.display_label},
        )
      elif not should_share and grant is not None and grant.is_visible:
        grant.is_visible = False
        grant.disabled_at = timezone.now()
        grant.save(update_fields=['is_visible', 'disabled_at'])
        record_payment_action(
          action='method_unshared',
          professional=request.user,
          client=client,
          changed_by=request.user.username,
          previous_values={'method_id': method_id, 'display_label': profile.display_label},
        )

    return Response({'message': f'Updated payment methods visible to {client.first_name or client.username}.'})


class PaymentRequestListView(APIView):
  """Professional's payment requests for one client: list + create."""

  permission_classes = [ProfessionalAccessPermission]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    requests = PaymentRequest.objects.filter(professional=request.user, client=client)
    return Response({'requests': PaymentRequestSerializer(requests, many=True).data})

  def post(self, request, client_id):
    client = self._client(request, client_id)
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = PaymentRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    payment_type = serializer.validated_data.get('payment_type', 'manual')
    method_ids = request.data.get('allowed_method_ids') or []
    if not isinstance(method_ids, list):
      return Response({'message': 'allowed_method_ids must be a list.'}, status=status.HTTP_400_BAD_REQUEST)

    allowed_profiles = []
    if payment_type in ('manual', 'both'):
      if not method_ids:
        return Response(
          {'message': 'Choose at least one payment method the client can use.'},
          status=status.HTTP_400_BAD_REQUEST,
        )
      shared_ids = set(
        ClientPaymentMethodAccess.objects.filter(
          client=client, is_visible=True, payment_profile__status=ManualPaymentProfile.STATUS_ACTIVE
        ).values_list('payment_profile_id', flat=True)
      )
      unshared = [method_id for method_id in method_ids if method_id not in shared_ids]
      if unshared:
        return Response(
          {'message': "One or more selected payment methods aren't shared with this client yet."},
          status=status.HTTP_400_BAD_REQUEST,
        )
      allowed_profiles = list(ManualPaymentProfile.objects.filter(id__in=method_ids, professional=request.user))

    payment_request = serializer.save(
      professional=request.user,
      client=client,
      status=PaymentRequest.STATUS_SENT,
      sent_at=timezone.now(),
    )

    for profile in allowed_profiles:
      PaymentRequestAllowedMethod.objects.create(payment_request=payment_request, manual_payment_profile=profile)

    record_payment_action(
      action='request_created',
      professional=request.user,
      client=client,
      payment_request=payment_request,
      changed_by=request.user.username,
      new_values={
        'request_id': payment_request.request_id,
        'amount': str(payment_request.requested_amount),
        'currency': payment_request.requested_currency,
      },
    )

    if payment_request.client_visibility == 'visible':
      due_text = f', due {payment_request.due_date:%b %d, %Y}' if payment_request.due_date else ''
      payment_notifications.notify_client(
        client,
        'new_payment_request',
        f'New payment request from {request.user.first_name or request.user.username}',
        (
          f'Hi {client.first_name or client.username}, '
          f'{request.user.first_name or request.user.username} sent you a payment request for '
          f'"{payment_request.title}" - {payment_request.requested_amount} {payment_request.requested_currency}{due_text}. '
          f'View details: {payment_notifications.request_link_for_client(payment_request.request_id)}'
        ),
        payload={'request_id': payment_request.request_id, 'action_url': web_routes.client_payment_request(payment_request.request_id)},
      )

    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'message': f'Payment request {payment_request.request_id} was sent to {client.first_name or client.username}.',
      },
      status=status.HTTP_201_CREATED,
    )


class PaymentRequestDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, request_id):
    payment_request = PaymentRequest.objects.filter(request_id=request_id, professional=request.user).first()
    if payment_request is None:
      return Response({'message': 'Payment request not found.'}, status=status.HTTP_404_NOT_FOUND)
    # Viewing a request's detail is the moment the professional has actually
    # reviewed it, so this is where its unread payment notifications clear -
    # not an implicit "mark everything read" the instant the tab opens.
    _mark_payment_notifications_read({'recipient_professional': request.user}, request_id=request_id)
    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'proofs': PaymentProofSerializer(payment_request.proofs.all(), many=True).data,
        'records': PaymentRecordSerializer(payment_request.records.all(), many=True).data,
      }
    )


class PaymentRequestCancelView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, request_id):
    payment_request = PaymentRequest.objects.filter(request_id=request_id, professional=request.user).first()
    if payment_request is None:
      return Response({'message': 'Payment request not found.'}, status=status.HTTP_404_NOT_FOUND)

    cancellable = PaymentRequest.OPEN_STATUSES + (PaymentRequest.STATUS_DRAFT,)
    if payment_request.status not in cancellable:
      return Response(
        {'message': f'A {payment_request.get_status_display()} request cannot be cancelled.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    previous_status = payment_request.status
    payment_request.status = PaymentRequest.STATUS_CANCELLED
    payment_request.save(update_fields=['status', 'updated_at'])

    record_payment_action(
      action='request_cancelled',
      professional=request.user,
      client=payment_request.client,
      payment_request=payment_request,
      changed_by=request.user.username,
      previous_values={'status': previous_status},
      new_values={'status': PaymentRequest.STATUS_CANCELLED},
      reason=str(request.data.get('reason') or ''),
    )

    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'message': f'Payment request {payment_request.request_id} was cancelled.',
      }
    )


class ClientPaymentRequestListView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    requests = PaymentRequest.objects.filter(
      client=request.auth, client_visibility='visible'
    ).exclude(status=PaymentRequest.STATUS_DRAFT)
    return Response({'requests': ClientPaymentRequestSerializer(requests, many=True).data})


class ClientPaymentRequestDetailView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request, request_id):
    payment_request = PaymentRequest.objects.filter(
      request_id=request_id, client=request.auth, client_visibility='visible'
    ).exclude(status=PaymentRequest.STATUS_DRAFT).first()
    if payment_request is None:
      return Response({'message': 'Payment request not found.'}, status=status.HTTP_404_NOT_FOUND)

    if payment_request.status == PaymentRequest.STATUS_SENT:
      payment_request.status = PaymentRequest.STATUS_VIEWED
      payment_request.viewed_at = timezone.now()
      payment_request.save(update_fields=['status', 'viewed_at', 'updated_at'])
      client = request.auth
      payment_notifications.notify_professional(
        payment_request.professional,
        'request_viewed',
        f'{client.first_name or client.username} viewed payment request {payment_request.request_id}',
        (
          f'{client.first_name or client.username} opened the payment request "{payment_request.title}". '
          f'Track it here: {payment_notifications.request_link_for_professional(payment_request.request_id)}'
        ),
        payload={
          'request_id': payment_request.request_id,
          'action_url': f'{web_routes.professional_client(payment_request.client_id)}?tab=payments',
        },
        email=False,
      )

    # Same rule as the professional side: opening this specific request's
    # detail page is what clears its unread notifications for this client.
    _mark_payment_notifications_read({'recipient_client': request.auth}, request_id=request_id)

    return Response({'request': ClientPaymentRequestSerializer(payment_request).data})


class ProfessionalPaymentNotificationsView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    cutoff = visible_client_data_cutoff(request.user)
    qs = PaymentNotification.objects.filter(recipient_professional=request.user, created_at__gte=cutoff)
    unread_qs = qs.filter(is_read=False)
    return Response({
      'unread_count': unread_qs.count(),
      'items': [_serialize_payment_notification(row) for row in unread_qs[:20]],
    })

  def post(self, request):
    recipient_filter = {'recipient_professional': request.user, 'created_at__gte': visible_client_data_cutoff(request.user)}
    request_id = request.data.get('request_id')
    if not request_id and not request.data.get('mark_all'):
      return Response({'message': 'Provide request_id or mark_all.'}, status=status.HTTP_400_BAD_REQUEST)
    _mark_payment_notifications_read(recipient_filter, request_id=request_id)
    unread = PaymentNotification.objects.filter(is_read=False, **recipient_filter).count()
    return Response({'unread_count': unread})


class ClientPaymentNotificationsView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    cutoff = visible_client_data_cutoff(request.auth.professional)
    qs = PaymentNotification.objects.filter(recipient_client=request.auth, created_at__gte=cutoff)
    unread_qs = qs.filter(is_read=False)
    return Response({
      'unread_count': unread_qs.count(),
      'items': [_serialize_payment_notification(row) for row in unread_qs[:20]],
    })

  def post(self, request):
    recipient_filter = {'recipient_client': request.auth, 'created_at__gte': visible_client_data_cutoff(request.auth.professional)}
    request_id = request.data.get('request_id')
    if not request_id and not request.data.get('mark_all'):
      return Response({'message': 'Provide request_id or mark_all.'}, status=status.HTTP_400_BAD_REQUEST)
    _mark_payment_notifications_read(recipient_filter, request_id=request_id)
    unread = PaymentNotification.objects.filter(is_read=False, **recipient_filter).count()
    return Response({'unread_count': unread})


def _sync_request_status_from_records(payment_request):
  """Auto-complete a request once same-currency completed installments cover
  the requested amount. Mixed-currency partials never auto-complete (summing
  across currencies isn't meaningful without conversion)."""

  records = payment_request.records.filter(
    status__in=[PaymentRecord.STATUS_COMPLETED, PaymentRecord.STATUS_PARTIALLY_PAID]
  )
  same_currency = [r for r in records if r.original_currency == payment_request.requested_currency]
  if len(same_currency) != records.count():
    return  # mixed currencies - leave status to the professional

  total = sum((record.original_amount for record in same_currency), Decimal('0'))
  if total >= payment_request.requested_amount:
    payment_request.status = PaymentRequest.STATUS_COMPLETED
    payment_request.completed_at = timezone.now()
    payment_request.save(update_fields=['status', 'completed_at', 'updated_at'])
  elif total > 0:
    payment_request.status = PaymentRequest.STATUS_PARTIALLY_PAID
    payment_request.save(update_fields=['status', 'updated_at'])


def _write_finance_ledger_entry(payment_record):
  """Secondary write so completed client payments appear in the existing
  admin finance dashboard. The PaymentRecord itself stays the source of truth."""

  try:
    from admin_portal.models import FinanceLedgerEntry
    FinanceLedgerEntry.objects.create(
      entry_type=FinanceLedgerEntry.TYPE_PAYMENT,
      status=FinanceLedgerEntry.STATUS_COMPLETED,
      amount=payment_record.reporting_amount,
      currency=payment_record.reporting_currency,
      professional=payment_record.professional,
      description=f'Client payment {payment_record.payment_record_id}',
      external_reference=payment_record.transaction_reference or payment_record.payment_record_id,
      source='client_payment',
      professional_reference=payment_record.professional.professional_profile.internal_reference_code,
      client_reference=payment_record.client.reference_id,
      payment_request_reference=payment_record.payment_request.request_id if payment_record.payment_request else '',
      payment_record_reference=payment_record.payment_record_id,
      original_amount=payment_record.original_amount,
      original_currency=payment_record.original_currency,
      reporting_amount=payment_record.reporting_amount,
      reporting_currency=payment_record.reporting_currency,
      provider='manual',
      occurred_at=timezone.now(),
    )
  except Exception:  # noqa: BLE001 - admin reporting must never block the payment flow
    import logging
    logging.getLogger(__name__).exception('Finance ledger write failed for %s', payment_record.payment_record_id)


class PaymentProofSubmitView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  parser_classes = [JSONParser, FormParser, MultiPartParser]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'payments'

  def post(self, request, request_id):
    payment_request = PaymentRequest.objects.filter(
      request_id=request_id, client=request.auth, client_visibility='visible'
    ).first()
    if payment_request is None:
      return Response({'message': 'Payment request not found.'}, status=status.HTTP_404_NOT_FOUND)

    submittable = (
      PaymentRequest.STATUS_SENT,
      PaymentRequest.STATUS_VIEWED,
      PaymentRequest.STATUS_OVERDUE,
      PaymentRequest.STATUS_UNDER_REVIEW,
      PaymentRequest.STATUS_PARTIALLY_PAID,
    )
    if payment_request.status not in submittable:
      return Response(
        {'message': 'This payment request is not accepting proof submissions right now.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    serializer = PaymentProofSubmitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    method = serializer.validated_data.get('payment_method')
    if method is not None:
      allowed = payment_request.allowed_methods.filter(manual_payment_profile=method).exists()
      if not allowed:
        return Response(
          {'message': 'Choose one of the payment methods listed on this request.'},
          status=status.HTTP_400_BAD_REQUEST,
        )

    client = request.auth
    proof = serializer.save(payment_request=payment_request, submitted_by=client.username)

    payment_request.status = PaymentRequest.STATUS_PROOF_SUBMITTED
    payment_request.save(update_fields=['status', 'updated_at'])

    record_payment_action(
      action='proof_submitted',
      professional=payment_request.professional,
      client=client,
      payment_request=payment_request,
      changed_by=client.username,
      new_values={
        'proof_id': proof.id,
        'reported_amount': str(proof.reported_amount),
        'reported_currency': proof.reported_currency,
      },
    )

    payment_notifications.notify_professional(
      payment_request.professional,
      'proof_submitted',
      f'New payment proof submitted - {payment_request.request_id}',
      (
        f'Hi {payment_request.professional.first_name or payment_request.professional.username}, '
        f'{client.first_name or client.username} submitted payment proof for "{payment_request.title}" '
        f'({proof.reported_amount} {proof.reported_currency}). Review it here: '
        f'{payment_notifications.request_link_for_professional(payment_request.request_id)}'
      ),
      payload={
        'request_id': payment_request.request_id,
        'proof_id': proof.id,
        'action_url': f'{web_routes.professional_client(payment_request.client_id)}?tab=payments',
      },
    )

    return Response(
      {
        'proof': PaymentProofSerializer(proof).data,
        'request': ClientPaymentRequestSerializer(payment_request).data,
        'message': 'Your payment proof was submitted. Your professional will review it shortly.',
      },
      status=status.HTTP_201_CREATED,
    )


class PaymentProofAcknowledgeView(APIView):
  """Confirms the client's payment was received - nothing more. Acknowledging
  is deliberately separate from logging it to the revenue ledger
  (PaymentRecordListView): a trainer might acknowledge a payment the moment
  it lands but only log it later (or never - logging stays optional), so
  this view never asks for amount/currency/date and never creates a
  PaymentRecord itself."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, proof_id):
    proof = PaymentProof.objects.filter(
      id=proof_id, payment_request__professional=request.user
    ).select_related('payment_request', 'payment_request__client').first()
    if proof is None:
      return Response({'message': 'Payment proof not found.'}, status=status.HTTP_404_NOT_FOUND)
    if proof.status == PaymentProof.STATUS_ACCEPTED:
      return Response({'message': 'This proof was already acknowledged.'}, status=status.HTTP_400_BAD_REQUEST)

    payment_request = proof.payment_request

    proof.status = PaymentProof.STATUS_ACCEPTED
    proof.reviewed_at = timezone.now()
    proof.review_note = str(request.data.get('acknowledgement_note') or '')
    proof.save(update_fields=['status', 'reviewed_at', 'review_note'])

    payment_request.status = PaymentRequest.STATUS_ACKNOWLEDGED
    payment_request.save(update_fields=['status', 'updated_at'])

    record_payment_action(
      action='payment_acknowledged',
      professional=request.user,
      client=payment_request.client,
      payment_request=payment_request,
      changed_by=request.user.username,
      previous_values={'proof_id': proof.id},
      new_values={
        'reported_amount': str(proof.reported_amount),
        'reported_currency': proof.reported_currency,
      },
      reason=proof.review_note,
    )

    client = payment_request.client
    payment_notifications.notify_client(
      client,
      'proof_accepted',
      f'Payment acknowledged - {payment_request.title}',
      (
        f'Your payment of {proof.reported_amount} {proof.reported_currency} for '
        f'"{payment_request.title}" was acknowledged by '
        f'{request.user.first_name or request.user.username}. View details: '
        f'{payment_notifications.request_link_for_client(payment_request.request_id)}'
      ),
      payload={'request_id': payment_request.request_id, 'action_url': web_routes.client_payment_request(payment_request.request_id)},
    )

    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'message': (
          f'Payment of {proof.reported_amount} {proof.reported_currency} acknowledged. '
          'Log it in your Payment History to track your revenue.'
        ),
        'needs_logging': True,
      },
      status=status.HTTP_200_OK,
    )


class PaymentReconciliationView(APIView):
  """How many payments has the professional acknowledged vs. actually logged
  to the revenue ledger. Logging stays optional - this just makes the gap
  visible instead of silently losing untracked revenue."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    acknowledged_requests = PaymentRequest.objects.filter(
      professional=request.user, proofs__status=PaymentProof.STATUS_ACCEPTED
    ).distinct()
    acknowledged_count = acknowledged_requests.count()

    unlogged = acknowledged_requests.filter(records__isnull=True).select_related('client').order_by('-updated_at')
    unlogged_count = unlogged.count()

    unlogged_items = [
      {
        'request_id': pr.request_id,
        'client_id': pr.client_id,
        'client_name': f'{pr.client.first_name} {pr.client.last_name}'.strip() or pr.client.username,
        'title': pr.title,
        'requested_amount': str(pr.requested_amount),
        'requested_currency': pr.requested_currency,
        'updated_at': pr.updated_at.isoformat(),
      }
      for pr in unlogged[:50]
    ]

    return Response(
      {
        'acknowledged_count': acknowledged_count,
        'logged_count': acknowledged_count - unlogged_count,
        'unlogged_count': unlogged_count,
        'unlogged_requests': unlogged_items,
      }
    )


class PaymentProofRejectView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, proof_id):
    proof = PaymentProof.objects.filter(
      id=proof_id, payment_request__professional=request.user
    ).select_related('payment_request', 'payment_request__client').first()
    if proof is None:
      return Response({'message': 'Payment proof not found.'}, status=status.HTTP_404_NOT_FOUND)
    if proof.status in (PaymentProof.STATUS_ACCEPTED, PaymentProof.STATUS_REJECTED):
      return Response({'message': 'This proof was already reviewed.'}, status=status.HTTP_400_BAD_REQUEST)

    reason = str(request.data.get('reason') or '').strip()
    if not reason:
      return Response({'message': 'Add a short reason so the client knows what to fix.'}, status=status.HTTP_400_BAD_REQUEST)

    payment_request = proof.payment_request
    proof.status = PaymentProof.STATUS_REJECTED
    proof.reviewed_at = timezone.now()
    proof.review_note = reason
    proof.save(update_fields=['status', 'reviewed_at', 'review_note'])

    # Reopen the request so the client can resubmit corrected proof.
    payment_request.status = PaymentRequest.STATUS_VIEWED
    payment_request.save(update_fields=['status', 'updated_at'])

    record_payment_action(
      action='proof_rejected',
      professional=request.user,
      client=payment_request.client,
      payment_request=payment_request,
      changed_by=request.user.username,
      previous_values={'proof_id': proof.id},
      reason=reason,
    )

    client = payment_request.client
    payment_notifications.notify_client(
      client,
      'proof_rejected',
      f'Payment proof rejected - {payment_request.title}',
      (
        f'{request.user.first_name or request.user.username} rejected your submitted proof for '
        f'"{payment_request.title}". Reason: {reason}. Please resubmit: '
        f'{payment_notifications.request_link_for_client(payment_request.request_id)}'
      ),
      payload={'request_id': payment_request.request_id, 'action_url': web_routes.client_payment_request(payment_request.request_id)},
    )

    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'message': f'Proof rejected. {client.first_name or client.username} has been notified and can resubmit.',
      }
    )


class PaymentProofRequestInfoView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, proof_id):
    proof = PaymentProof.objects.filter(
      id=proof_id, payment_request__professional=request.user
    ).select_related('payment_request', 'payment_request__client').first()
    if proof is None:
      return Response({'message': 'Payment proof not found.'}, status=status.HTTP_404_NOT_FOUND)
    if proof.status in (PaymentProof.STATUS_ACCEPTED, PaymentProof.STATUS_REJECTED):
      return Response({'message': 'This proof was already reviewed.'}, status=status.HTTP_400_BAD_REQUEST)

    note = str(request.data.get('note') or '').strip()
    if not note:
      return Response({'message': 'Describe what additional information you need.'}, status=status.HTTP_400_BAD_REQUEST)

    payment_request = proof.payment_request
    proof.status = PaymentProof.STATUS_UNDER_REVIEW
    proof.review_note = note
    proof.save(update_fields=['status', 'review_note'])

    payment_request.status = PaymentRequest.STATUS_UNDER_REVIEW
    payment_request.save(update_fields=['status', 'updated_at'])

    record_payment_action(
      action='info_requested',
      professional=request.user,
      client=payment_request.client,
      payment_request=payment_request,
      changed_by=request.user.username,
      reason=note,
    )

    client = payment_request.client
    payment_notifications.notify_client(
      client,
      'info_requested',
      f'More information needed - {payment_request.title}',
      (
        f'{request.user.first_name or request.user.username} needs more details on your payment for '
        f'"{payment_request.title}": "{note}". Respond here: '
        f'{payment_notifications.request_link_for_client(payment_request.request_id)}'
      ),
      payload={'request_id': payment_request.request_id, 'action_url': web_routes.client_payment_request(payment_request.request_id)},
    )

    return Response(
      {
        'request': PaymentRequestSerializer(payment_request).data,
        'message': 'The client has been asked for more information.',
      }
    )


def _serve_proof_file(proof):
  """Stream a proof file with a content type derived from its actual bytes,
  never from the stored filename, and always as a download.

  Upload-time validation (see `PaymentProofSubmitSerializer.validate_proof_file`)
  already rejects files whose content doesn't match a known-good signature, but
  this is defense-in-depth: even a mislabeled/legacy file gets served either as
  a safe, explicitly-typed download, or - if its bytes don't match any format
  we recognise - as a generic opaque download that browsers will never render
  inline (and therefore can't execute as HTML/SVG/script in the app's origin).
  """
  handle = proof.proof_file.open('rb')
  detected_type = detect_upload_content_type(handle)
  content_type = detected_type or 'application/octet-stream'
  extension = {
    'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp', 'application/pdf': '.pdf',
  }.get(detected_type, '')
  filename = f'payment-proof-{proof.id}{extension}'
  return FileResponse(handle, as_attachment=True, filename=filename, content_type=content_type)


class PaymentProofFileView(APIView):
  """Streams a proof file only to the owning professional. There is no public
  media URL for payment proofs - this view is the only way to fetch them."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, proof_id):
    proof = PaymentProof.objects.filter(id=proof_id, payment_request__professional=request.user).first()
    if proof is None or not proof.proof_file:
      return Response({'message': 'Proof file not found.'}, status=status.HTTP_404_NOT_FOUND)
    return _serve_proof_file(proof)


class ClientPaymentProofFileView(APIView):
  """Streams a proof file back to the client who submitted it."""

  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request, proof_id):
    proof = PaymentProof.objects.filter(
      id=proof_id, payment_request__client=request.auth, payment_request__client_visibility='visible'
    ).first()
    if proof is None or not proof.proof_file:
      return Response({'message': 'Proof file not found.'}, status=status.HTTP_404_NOT_FOUND)
    return _serve_proof_file(proof)


class ProfessionalPaymentActionsView(APIView):
  """Cross-client feed of payments needing the professional's attention:
  proofs awaiting review + overdue requests. Powers the dashboard Payments
  tab and its badge. Sorted most-recently-updated first."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    needs_review = PaymentRequest.objects.filter(
      professional=request.user,
      status__in=[PaymentRequest.STATUS_PROOF_SUBMITTED, PaymentRequest.STATUS_UNDER_REVIEW],
    ).select_related('client')
    overdue = PaymentRequest.objects.filter(
      professional=request.user, status=PaymentRequest.STATUS_OVERDUE
    ).select_related('client')

    items = list(needs_review) + list(overdue)
    items.sort(key=lambda pr: pr.updated_at, reverse=True)

    data = [
      {
        'request_id': pr.request_id,
        'client_id': pr.client_id,
        'client_name': f'{pr.client.first_name} {pr.client.last_name}'.strip() or pr.client.username,
        'title': pr.title,
        'requested_amount': str(pr.requested_amount),
        'requested_currency': pr.requested_currency,
        'due_date': pr.due_date.isoformat() if pr.due_date else None,
        'status': pr.status,
        'updated_at': pr.updated_at.isoformat(),
      }
      for pr in items
    ]

    return Response(
      {
        'items': data,
        'review_count': needs_review.count(),
        'overdue_count': overdue.count(),
        'action_count': len(data),
      }
    )


class ProfessionalTransactionLedgerView(APIView):
  """Read-only unified history for client payments and RepRoot billing.

  Ledger rows are append-only. A refund or correction is represented by a new
  row, never by rewriting or deleting the original transaction.
  """

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    from admin_portal.models import FinanceLedgerEntry

    rows = FinanceLedgerEntry.objects.filter(professional=request.user).order_by('-occurred_at')[:500]
    return Response({'transactions': [{
      'entry_id': row.entry_id,
      'entry_type': row.entry_type,
      'source': row.source,
      'status': row.status,
      'amount': str(row.amount),
      'currency': row.currency,
      'original_amount': str(row.original_amount) if row.original_amount is not None else None,
      'original_currency': row.original_currency,
      'reporting_amount': str(row.reporting_amount) if row.reporting_amount is not None else None,
      'reporting_currency': row.reporting_currency,
      'client_reference': row.client_reference,
      'payment_request_reference': row.payment_request_reference,
      'payment_record_reference': row.payment_record_reference,
      'external_reference': row.external_reference,
      'provider': row.provider,
      'description': row.description,
      'occurred_at': row.occurred_at,
    } for row in rows]})


class PaymentRecordListView(APIView):
  """Professional payment records. POST records a received payment - either a
  standalone one (no prior request) or an installment against an existing
  request (pass payment_request_id)."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    records = PaymentRecord.objects.filter(professional=request.user).select_related('client', 'payment_request')
    client_id = request.query_params.get('client_id')
    if client_id:
      records = records.filter(client_id=client_id)
    return Response({'records': PaymentRecordSerializer(records, many=True).data})

  def post(self, request):
    client = ClientAccess.objects.filter(
      id=request.data.get('client'), professional=request.user, is_active=True
    ).first()
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    payment_request = None
    request_ref = request.data.get('payment_request_id') or request.data.get('payment_request')
    if request_ref:
      payment_request = PaymentRequest.objects.filter(
        request_id=request_ref, professional=request.user, client=client
      ).first()
      if payment_request is None:
        return Response({'message': 'Linked payment request not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = PaymentRecordSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)

    outcome = request.data.get('status', PaymentRecord.STATUS_COMPLETED)
    if outcome not in (PaymentRecord.STATUS_COMPLETED, PaymentRecord.STATUS_PARTIALLY_PAID):
      outcome = PaymentRecord.STATUS_COMPLETED

    payment_record = serializer.save(
      professional=request.user,
      client=client,
      payment_request=payment_request,
      status=outcome,
      verified_by=request.user,
      verified_at=timezone.now(),
    )

    record_payment_action(
      action='payment_recorded',
      professional=request.user,
      client=client,
      payment_request=payment_request,
      payment_record=payment_record,
      changed_by=request.user.username,
      new_values={
        'record_id': payment_record.payment_record_id,
        'original_amount': str(payment_record.original_amount),
        'original_currency': payment_record.original_currency,
        'reporting_amount': str(payment_record.reporting_amount),
        'reporting_currency': payment_record.reporting_currency,
        'linked_request': payment_request.request_id if payment_request else None,
      },
    )

    if payment_request is not None:
      _sync_request_status_from_records(payment_request)

    _write_finance_ledger_entry(payment_record)

    return Response(
      {
        'record': PaymentRecordSerializer(payment_record).data,
        'message': f'Payment of {payment_record.original_amount} {payment_record.original_currency} recorded for {client.first_name or client.username}.',
      },
      status=status.HTTP_201_CREATED,
    )


class PaymentRecordDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def _record(self, request, record_id):
    return PaymentRecord.objects.filter(payment_record_id=record_id, professional=request.user).first()

  def get(self, request, record_id):
    record = self._record(request, record_id)
    if record is None:
      return Response({'message': 'Payment record not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'record': PaymentRecordSerializer(record).data})

  def put(self, request, record_id):
    record = self._record(request, record_id)
    if record is None:
      return Response({'message': 'Payment record not found.'}, status=status.HTTP_404_NOT_FOUND)

    reason = str(request.data.get('reason') or '').strip()
    if not reason:
      return Response(
        {'message': 'Add a short reason for this change before saving - it will be recorded in the payment activity log.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    before = {
      'original_amount': str(record.original_amount),
      'original_currency': record.original_currency,
      'reporting_amount': str(record.reporting_amount),
      'reporting_currency': record.reporting_currency,
      'received_date': record.received_date.isoformat(),
      'status': record.status,
      'client_visibility': record.client_visibility,
    }

    serializer = PaymentRecordSerializer(record, data=request.data, partial=True, context={'request': request})
    serializer.is_valid(raise_exception=True)
    record = serializer.save()

    after = {
      'original_amount': str(record.original_amount),
      'original_currency': record.original_currency,
      'reporting_amount': str(record.reporting_amount),
      'reporting_currency': record.reporting_currency,
      'received_date': record.received_date.isoformat(),
      'status': record.status,
      'client_visibility': record.client_visibility,
    }

    record_payment_action(
      action='payment_edited',
      professional=request.user,
      client=record.client,
      payment_request=record.payment_request,
      payment_record=record,
      changed_by=request.user.username,
      previous_values=before,
      new_values=after,
      reason=reason,
    )

    if record.payment_request is not None:
      _sync_request_status_from_records(record.payment_request)

    return Response({'record': PaymentRecordSerializer(record).data, 'message': 'Payment record updated.'})

  def delete(self, request, record_id):
    record = self._record(request, record_id)
    if record is None:
      return Response({'message': 'Payment record not found.'}, status=status.HTTP_404_NOT_FOUND)

    reason = str(request.data.get('reason') or '').strip()
    record_payment_action(
      action='payment_deleted',
      professional=request.user,
      client=record.client,
      payment_request=record.payment_request,
      changed_by=request.user.username,
      previous_values={
        'record_id': record.payment_record_id,
        'original_amount': str(record.original_amount),
        'original_currency': record.original_currency,
      },
      reason=reason,
    )
    linked_request = record.payment_request
    record.delete()
    if linked_request is not None:
      _sync_request_status_from_records(linked_request)
    return Response({'message': 'Payment record deleted.'})


class PaymentReportingEstimateView(APIView):
  """Rough reporting-currency estimate to pre-fill the verify/record forms.
  Non-authoritative - the professional always confirms or overrides it."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    from decimal import Decimal, InvalidOperation

    from .payment_constants import estimate_reporting_amount

    settings_row, _ = ProfessionalPaymentSettings.objects.get_or_create(professional=request.user)
    to_currency = (request.query_params.get('to') or settings_row.reporting_currency).upper()
    from_currency = (request.query_params.get('from') or '').upper()
    try:
      amount = Decimal(str(request.query_params.get('amount') or '0'))
    except InvalidOperation:
      amount = Decimal('0')

    estimate = estimate_reporting_amount(amount, from_currency, to_currency) if amount > 0 else None
    return Response(
      {
        'reporting_currency': to_currency,
        'estimate': str(estimate) if estimate is not None else None,
        'is_estimate': estimate is not None and from_currency != to_currency,
      }
    )


def _month_add(d, months):
  month_index = d.month - 1 + months
  year = d.year + month_index // 12
  month = month_index % 12 + 1
  return d.replace(year=year, month=month, day=1)


def _build_revenue_series(records_qs, start_date, end_date):
  """
  Buckets records between start_date and end_date (inclusive) and picks a
  chart shape to match: <=30 days spans by day as a bar chart (fine-grained,
  still readable); longer spans switch to a line chart — weekly buckets up
  to 6 months, monthly beyond that, since a bar per day would be unreadable
  noise at that range.
  """
  span_days = (end_date - start_date).days + 1
  buckets = []

  if span_days <= 30:
    chart_kind = 'bar'
    cur = start_date
    while cur <= end_date:
      buckets.append((cur, cur, cur.strftime('%b %d')))
      cur += timedelta(days=1)
  elif span_days <= 180:
    chart_kind = 'line'
    cur = start_date
    while cur <= end_date:
      bucket_end = min(cur + timedelta(days=6), end_date)
      buckets.append((cur, bucket_end, cur.strftime('%b %d')))
      cur = bucket_end + timedelta(days=1)
  else:
    chart_kind = 'line'
    cur = start_date.replace(day=1)
    while cur <= end_date:
      next_month = _month_add(cur, 1)
      bucket_end = min(next_month - timedelta(days=1), end_date)
      bucket_start = max(cur, start_date)
      buckets.append((bucket_start, bucket_end, cur.strftime('%b %Y')))
      cur = next_month

  series = []
  for bucket_start, bucket_end, label in buckets:
    total = records_qs.filter(
      received_date__gte=bucket_start, received_date__lte=bucket_end
    ).aggregate(total=Sum('reporting_amount'))['total']
    series.append({'label': label, 'total': str(total or Decimal('0'))})

  return chart_kind, series


class ProfessionalRevenueSummaryView(APIView):
  """
  Account-wide revenue rollup across every client, in the professional's
  chosen reporting currency only — records in any other currency are
  excluded rather than converted (same no-auto-FX rule as everywhere else
  in payments). Powers the revenue dashboard, which the frontend keeps
  hidden until reporting_currency_locked is off in Settings -> Payments.

  Money is counted on the date it was actually received (PaymentRecord.
  received_date), not when it was requested. "This month" is always
  calendar month-to-date and resets on the 1st, independent of whatever
  period is selected below it.

  ?period=7|30|90|lifetime|custom (default 7)
  ?start=YYYY-MM-DD&end=YYYY-MM-DD (required when period=custom)
  """

  permission_classes = [ProfessionalAccessPermission]

  PERIOD_DAYS = {'7': 7, '30': 30, '90': 90}

  def get(self, request):
    settings_row, _ = ProfessionalPaymentSettings.objects.get_or_create(professional=request.user)
    currency = settings_row.reporting_currency

    records = PaymentRecord.objects.filter(
      professional=request.user,
      reporting_currency=currency,
      status__in=[PaymentRecord.STATUS_COMPLETED, PaymentRecord.STATUS_PARTIALLY_PAID],
    )

    today = timezone.localdate()
    month_start = today.replace(day=1)
    this_month_total = records.filter(received_date__gte=month_start).aggregate(total=Sum('reporting_amount'))['total']

    period = str(request.query_params.get('period') or '7').strip().lower()

    if period == 'custom':
      try:
        period_start = date.fromisoformat(request.query_params.get('start', ''))
        period_end = date.fromisoformat(request.query_params.get('end', ''))
      except ValueError:
        return Response({'message': 'start and end must be valid dates (YYYY-MM-DD).'}, status=status.HTTP_400_BAD_REQUEST)
      if period_start > period_end:
        period_start, period_end = period_end, period_start
    elif period == 'lifetime':
      earliest = records.order_by('received_date').first()
      period_start = earliest.received_date if earliest else today
      period_end = today
    elif period in self.PERIOD_DAYS:
      period_end = today
      period_start = today - timedelta(days=self.PERIOD_DAYS[period] - 1)
    else:
      return Response(
        {'message': 'period must be one of: 7, 30, 90, lifetime, custom.'}, status=status.HTTP_400_BAD_REQUEST
      )

    total_revenue = records.filter(
      received_date__gte=period_start, received_date__lte=period_end
    ).aggregate(total=Sum('reporting_amount'))['total']

    chart_kind, series = _build_revenue_series(records, period_start, period_end)

    # Most recent first, across every client — capped well above the 5-row
    # visible window so the scrollable list actually has something to scroll.
    recent = records.select_related('client').order_by('-received_date', '-created_at')[:20]
    recent_transactions = [
      {
        'payment_record_id': r.payment_record_id,
        'client_id': r.client_id,
        'client_name': f'{r.client.first_name} {r.client.last_name}'.strip() or r.client.username,
        'amount': str(r.reporting_amount),
        'currency': r.reporting_currency,
        'status': r.status,
        'received_date': r.received_date.isoformat(),
      }
      for r in recent
    ]

    return Response(
      {
        'reporting_currency': currency,
        'this_month_total': str(this_month_total or Decimal('0')),
        'period': period,
        'period_start': period_start.isoformat(),
        'period_end': period_end.isoformat(),
        'total_revenue': str(total_revenue or Decimal('0')),
        'chart_kind': chart_kind,
        'series': series,
        'recent_transactions': recent_transactions,
      }
    )


class ClientPaymentRecordListView(APIView):
  """A client's own payment history - only records the professional made
  visible to them."""

  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    records = PaymentRecord.objects.filter(
      client=request.auth, client_visibility='visible'
    ).select_related('payment_request')
    return Response({'records': ClientPaymentRecordSerializer(records, many=True).data})


def _confirmation_payload(record):
  professional = record.professional
  client = record.client
  return {
    'payment_record_id': record.payment_record_id,
    'request_reference': record.payment_request.request_id if record.payment_request else 'Recorded Payment',
    'professional_name': f'{professional.first_name} {professional.last_name}'.strip() or professional.username,
    'client_name': f'{client.first_name} {client.last_name}'.strip() or client.username,
    'original_amount': record.original_amount,
    'original_currency': record.original_currency,
    'reporting_amount': record.reporting_amount,
    'reporting_currency': record.reporting_currency,
    'payment_method_label': record.payment_method.display_label if record.payment_method else 'Not specified',
    'transaction_reference': record.transaction_reference or 'Not provided',
    'received_date': record.received_date,
    'verified_at': record.verified_at or record.created_at,
    'status': record.status,
    'client_note': record.client_note,
  }


class PaymentConfirmationView(APIView):
  """The 'Payment Confirmation' document - explicitly not a bank/provider
  receipt. Professional's own view of one of their records."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, record_id):
    record = PaymentRecord.objects.filter(
      payment_record_id=record_id, professional=request.user
    ).select_related('professional', 'client', 'payment_method', 'payment_request').first()
    if record is None:
      return Response({'message': 'Payment record not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'confirmation': PaymentConfirmationSerializer(_confirmation_payload(record)).data})


class ClientPaymentConfirmationView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request, record_id):
    record = PaymentRecord.objects.filter(
      payment_record_id=record_id, client=request.auth, client_visibility='visible'
    ).select_related('professional', 'client', 'payment_method', 'payment_request').first()
    if record is None:
      return Response({'message': 'Payment record not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'confirmation': PaymentConfirmationSerializer(_confirmation_payload(record)).data})
