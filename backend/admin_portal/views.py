from datetime import timedelta
from decimal import Decimal

from django.contrib.auth import get_user_model
from django.db.models import Count, Q, Sum
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from accounts.models import ClientAccess, LeadSubmission, ReferenceCategory, SupportIncident, SupportIncidentMessage, TrackingTemplate, TrainerGroup, TrainerLeadForm, TrainerProfile, TrainerReference, ClientReminder
from accounts.serializers import SupportIncidentSerializer

from .audit import record_admin_action
from .models import AdminAuditLog, AdminStaffProfile, FinanceLedgerEntry
from .permissions import HasAdminPermission, active_staff_for
from .serializers import AdminAuditLogSerializer, AdminLoginSerializer, FinanceLedgerEntrySerializer, staff_payload

User = get_user_model()


def range_start(request):
  key = request.query_params.get('range', '30d')
  now = timezone.now()
  days = {'today': 0, '7d': 7, '30d': 30, '90d': 90}.get(key, 30)
  return now.replace(hour=0, minute=0, second=0, microsecond=0) if days == 0 else now - timedelta(days=days)


class AdminLoginView(APIView):
  permission_classes = [AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = AdminLoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']
    staff = serializer.validated_data['staff']
    Token.objects.filter(user=user).delete()
    token = Token.objects.create(user=user)
    request.admin_staff = staff
    record_admin_action(request, permission='admin.auth.login', action='ADMIN_LOGIN', target_type='staff', target_id=staff.staff_id, target_display=f'{staff.staff_id} · {user.username}')
    return Response({'token': token.key, 'staff': staff_payload(staff)})


class AdminLogoutView(APIView):
  authentication_classes = [TokenAuthentication]

  def post(self, request):
    staff = active_staff_for(request.user)
    if staff:
      request.admin_staff = staff
      record_admin_action(request, permission='admin.auth.logout', action='ADMIN_LOGOUT', target_type='staff', target_id=staff.staff_id)
    Token.objects.filter(user=request.user).delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


class AdminMeView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.dashboard.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    return Response(staff_payload(request.admin_staff))


class AdminDashboardView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.dashboard.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    start = range_start(request)
    trainers = User.objects.filter(trainer_profile__isnull=False)
    clients = ClientAccess.objects.all()
    payload = {
      'range_start': start,
      'accounts': {
        'total_trainers': trainers.count(), 'active_trainers': trainers.filter(is_active=True).count(),
        'suspended_trainers': trainers.filter(is_active=False).count(), 'pending_deletion': 0,
        'new_trainers': trainers.filter(date_joined__gte=start).count(),
      },
      'clients': {
        'total_clients': clients.count(), 'active_clients': clients.filter(is_active=True).count(),
        'inactive_clients': clients.filter(is_active=False).count(), 'new_clients': clients.filter(created_at__gte=start).count(),
      },
      'users': {
        'total_accounts': trainers.count() + clients.count() + AdminStaffProfile.objects.count(),
        'trainer_accounts': trainers.count(), 'client_accounts': clients.count(), 'internal_accounts': AdminStaffProfile.objects.count(),
      },
      'usage': {
        'lead_forms': TrainerLeadForm.objects.count(), 'active_lead_forms': TrainerLeadForm.objects.filter(is_active=True).count(),
        'form_submissions': LeadSubmission.objects.count(), 'groups': TrainerGroup.objects.count(),
        'templates': TrackingTemplate.objects.count(), 'references': TrainerReference.objects.count(),
        'scheduled_followups': ClientReminder.objects.filter(status='pending').count(),
      },
    }
    record_admin_action(request, permission=self.required_permission, action='VIEW_ADMIN_DASHBOARD', target_type='platform', target_display='Aggregate platform dashboard')
    return Response(payload)


class AdminFinanceView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.finance.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    start = range_start(request)
    entries = FinanceLedgerEntry.objects.select_related('trainer', 'trainer__trainer_profile')
    completed = entries.filter(status=FinanceLedgerEntry.STATUS_COMPLETED, occurred_at__gte=start)
    refunds = entries.filter(entry_type=FinanceLedgerEntry.TYPE_REFUND, occurred_at__gte=start)
    payload = {
      'currency': 'USD',
      'billing_provider': 'Not configured',
      'finance_tracking_status': 'Ready for integration',
      'summary': {
        'gross_revenue': completed.aggregate(value=Sum('amount'))['value'] or Decimal('0.00'),
        'completed_transactions': completed.count(), 'pending_transactions': entries.filter(status='PENDING').count(),
        'failed_transactions': entries.filter(status='FAILED', occurred_at__gte=start).count(),
        'refund_total': refunds.aggregate(value=Sum('amount'))['value'] or Decimal('0.00'),
      },
      'recent_entries': FinanceLedgerEntrySerializer(entries[:10], many=True).data,
    }
    record_admin_action(request, permission=self.required_permission, action='VIEW_FINANCE_SUMMARY', target_type='finance', target_display='Aggregate finance summary')
    return Response(payload)


class AdminAuditLogListView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.audit.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    logs = AdminAuditLog.objects.all()
    search = request.query_params.get('search', '').strip()
    if search:
      logs = logs.filter(Q(correlation_id__icontains=search) | Q(target_display__icontains=search) | Q(staff_reference_snapshot__icontains=search))
    payload = AdminAuditLogSerializer(logs[:100], many=True).data
    record_admin_action(request, permission=self.required_permission, action='VIEW_AUDIT_LOGS', target_type='audit', target_display='Administrative audit log')
    return Response({'results': payload, 'count': logs.count()})


class AdminSupportIncidentListView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.support.list'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    incidents = SupportIncident.objects.select_related('assigned_support').prefetch_related('messages')
    search = request.query_params.get('search', '').strip()
    if search:
      incidents = incidents.filter(
        Q(incident_id__icontains=search)
        | Q(reporter_name__icontains=search)
        | Q(reporter_email__icontains=search)
        | Q(subject__icontains=search)
      )
    for field in ('reporter_role', 'category', 'status', 'priority'):
      value = request.query_params.get(field, '').strip()
      if value:
        incidents = incidents.filter(**{field: value})
    created_from = request.query_params.get('created_from', '').strip()
    created_to = request.query_params.get('created_to', '').strip()
    if created_from:
      incidents = incidents.filter(created_at__date__gte=created_from)
    if created_to:
      incidents = incidents.filter(created_at__date__lte=created_to)
    record_admin_action(
      request, permission=self.required_permission, action='LIST_SUPPORT_INCIDENTS',
      target_type='support', target_display='Support incident queue'
    )
    return Response({
      'results': SupportIncidentSerializer(
        incidents[:200], many=True, context={'request': request, 'include_internal': True}
      ).data,
      'count': incidents.count(),
      'active_count': incidents.filter(status__in=SupportIncident.ACTIVE_STATUSES).count(),
    })


class AdminSupportIncidentDetailView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.support.view'
  permission_classes = [HasAdminPermission]

  def get(self, request, incident_id):
    incident = SupportIncident.objects.select_related('assigned_support').prefetch_related('messages').filter(
      incident_id=incident_id
    ).first()
    if incident is None:
      return Response({'message': 'Support incident not found.'}, status=status.HTTP_404_NOT_FOUND)
    record_admin_action(
      request, permission=self.required_permission, action='VIEW_SUPPORT_INCIDENT',
      target_type='support', target_id=incident.incident_id, target_display=incident.subject
    )
    return Response({
      'incident': SupportIncidentSerializer(
        incident, context={'request': request, 'include_internal': True}
      ).data
    })


class AdminSupportIncidentActionView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.support.manage'
  permission_classes = [HasAdminPermission]

  def post(self, request, incident_id):
    incident = SupportIncident.objects.filter(incident_id=incident_id).first()
    if incident is None:
      return Response({'message': 'Support incident not found.'}, status=status.HTTP_404_NOT_FOUND)

    staff = request.admin_staff
    reply = str(request.data.get('reply', '')).strip()
    internal_note = str(request.data.get('internal_note', '')).strip()
    requested_status = str(request.data.get('status', '')).strip()
    requested_priority = str(request.data.get('priority', '')).strip()
    resolution_note = str(request.data.get('resolution_note', '')).strip()
    assign_to_me = bool(request.data.get('assign_to_me', False))

    if requested_status and requested_status not in dict(SupportIncident.STATUS_CHOICES):
      return Response({'message': 'Invalid incident status.'}, status=status.HTTP_400_BAD_REQUEST)
    if requested_priority and requested_priority not in dict(SupportIncident.PRIORITY_CHOICES):
      return Response({'message': 'Invalid incident priority.'}, status=status.HTTP_400_BAD_REQUEST)

    changed_fields = []
    if assign_to_me:
      incident.assigned_support = request.user
      changed_fields.append('assigned_support')
    if requested_priority:
      incident.priority = requested_priority
      changed_fields.append('priority')
    if reply:
      SupportIncidentMessage.objects.create(
        incident=incident,
        author_type=SupportIncidentMessage.AUTHOR_SUPPORT,
        author_name=request.user.get_full_name() or request.user.username,
        author_staff=request.user,
        body=reply[:5000],
      )
      if not requested_status:
        requested_status = SupportIncident.STATUS_WAITING
    if internal_note:
      SupportIncidentMessage.objects.create(
        incident=incident,
        author_type=SupportIncidentMessage.AUTHOR_INTERNAL,
        author_name=request.user.get_full_name() or request.user.username,
        author_staff=request.user,
        body=internal_note[:5000],
      )
    if resolution_note:
      incident.resolution_note = resolution_note[:5000]
      changed_fields.append('resolution_note')
    if requested_status:
      incident.status = requested_status
      incident.closed_at = timezone.now() if requested_status == SupportIncident.STATUS_CLOSED else None
      changed_fields.extend(['status', 'closed_at'])
    if changed_fields:
      incident.save(update_fields=list(dict.fromkeys([*changed_fields, 'updated_at'])))

    record_admin_action(
      request, permission=self.required_permission, action='UPDATE_SUPPORT_INCIDENT',
      target_type='support', target_id=incident.incident_id, target_display=incident.subject,
      reason=internal_note, metadata={'status': incident.status, 'priority': incident.priority, 'reply_added': bool(reply)}
    )
    incident.refresh_from_db()
    return Response({
      'incident': SupportIncidentSerializer(
        incident, context={'request': request, 'include_internal': True}
      ).data,
      'message': 'Support incident updated.',
    })
