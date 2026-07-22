from datetime import timedelta
from decimal import Decimal

from django.conf import settings
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

from accounts import account_lifecycle
from accounts.models import ActivityNotification, ClientAccess, LeadSubmission, ReferenceCategory, SupportIncident, SupportIncidentMessage, TrackingTemplate, ProfessionalGroup, ProfessionalLeadForm, ProfessionalProfile, ProfessionalReference, ClientReminder
from accounts.serializers import SupportIncidentSerializer

from .audit import record_admin_action
from .models import AdminAuditLog, AdminStaffProfile, ErrorLog, FinanceLedgerEntry
from .permissions import HasAdminPermission, active_staff_for
from .serializers import (
  AdminAuditLogSerializer, AdminLoginSerializer, ErrorLogListSerializer, ErrorLogSerializer,
  FinanceLedgerEntrySerializer, staff_payload,
)

User = get_user_model()


class AdminNotificationsView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.dashboard.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    rows = ActivityNotification.objects.filter(recipient_type='admin')
    scope = request.query_params.get('scope')
    if scope:
      rows = rows.filter(admin_scope=scope)
    limit = min(max(int(request.query_params.get('limit', 50)), 1), 100)
    unread = rows.filter(is_read=False)
    return Response({'unread_count': unread.count(), 'notifications': [{
      'id': row.id, 'scope': row.admin_scope, 'category': row.category, 'event_type': row.event_type,
      'title': row.title, 'body': row.body, 'payload': row.payload, 'priority': row.priority,
      'requires_action': row.requires_action, 'is_read': row.is_read, 'created_at': row.created_at,
    } for row in rows[:limit]]})

  def patch(self, request):
    rows = ActivityNotification.objects.filter(recipient_type='admin')
    if request.data.get('notification_id'):
      rows = rows.filter(id=request.data['notification_id'])
    elif not request.data.get('mark_all_read'):
      return Response({'message': 'Provide notification_id or mark_all_read.'}, status=400)
    now = timezone.now()
    rows.filter(is_read=False).update(is_read=True, read_at=now, updated_at=now)
    return Response({'unread_count': ActivityNotification.objects.filter(recipient_type='admin', is_read=False).count()})


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
    professionals = User.objects.filter(professional_profile__isnull=False)
    clients = ClientAccess.objects.all()
    payload = {
      'range_start': start,
      'accounts': {
        'total_professionals': professionals.count(), 'active_professionals': professionals.filter(is_active=True).count(),
        'suspended_professionals': professionals.filter(is_active=False).count(),
        'pending_deletion': professionals.filter(professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_RECYCLED).count(),
        'new_professionals': professionals.filter(date_joined__gte=start).count(),
      },
      'clients': {
        'total_clients': clients.count(), 'active_clients': clients.filter(is_active=True).count(),
        'inactive_clients': clients.filter(is_active=False).count(), 'new_clients': clients.filter(created_at__gte=start).count(),
      },
      'users': {
        'total_accounts': professionals.count() + clients.count() + AdminStaffProfile.objects.count(),
        'professional_accounts': professionals.count(), 'client_accounts': clients.count(), 'internal_accounts': AdminStaffProfile.objects.count(),
      },
      'usage': {
        'lead_forms': ProfessionalLeadForm.objects.count(), 'active_lead_forms': ProfessionalLeadForm.objects.filter(is_active=True).count(),
        'form_submissions': LeadSubmission.objects.count(), 'groups': ProfessionalGroup.objects.count(),
        'templates': TrackingTemplate.objects.count(), 'references': ProfessionalReference.objects.count(),
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
    entries = FinanceLedgerEntry.objects.select_related('professional', 'professional__professional_profile')
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


class AdminAccountLifecycleListView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.lifecycle.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    profiles = ProfessionalProfile.objects.exclude(
      lifecycle_status=ProfessionalProfile.LIFECYCLE_ACTIVE
    ).select_related('user').order_by('recycle_expires_at', 'grace_period_ends_at', 'locked_at')
    results = []
    now = timezone.now()
    for profile in profiles:
      deadline = profile.recycle_expires_at or profile.grace_period_ends_at
      if profile.lifecycle_status == ProfessionalProfile.LIFECYCLE_FROZEN and profile.locked_at:
        deadline = profile.locked_at + timedelta(days=settings.REPROOT_DATA_DELETION_DAYS)
      results.append({
        'professional_reference': profile.internal_reference_code,
        'username': profile.user.username,
        'name': profile.user.get_full_name(),
        'email': profile.user.email,
        'plan': profile.get_plan_tier_display(),
        'status': profile.lifecycle_status,
        'status_label': profile.get_lifecycle_status_display(),
        'reason': profile.lifecycle_reason,
        'grace_period_ends_at': profile.grace_period_ends_at,
        'locked_at': profile.locked_at,
        'recycled_at': profile.recycled_at,
        'recycle_expires_at': profile.recycle_expires_at,
        'days_remaining': max(0, (deadline - now).days) if deadline else None,
      })
    deletion_requests = SupportIncident.objects.filter(
      reporter_role=SupportIncident.ROLE_PROFESSIONAL,
      category=SupportIncident.CATEGORY_ACCOUNT,
      subject='Professional account deletion request',
      status__in=SupportIncident.ACTIVE_STATUSES,
    ).select_related('reporter_professional__professional_profile')
    deletion_request_payload = [{
      'incident_id': incident.incident_id,
      'professional_reference': incident.reporter_professional.professional_profile.internal_reference_code,
      'reporter_email': incident.reporter_email,
      'reporter_name': incident.reporter_name,
      'status': incident.status,
      'created_at': incident.created_at,
    } for incident in deletion_requests if incident.reporter_professional_id]
    record_admin_action(request, permission=self.required_permission, action='VIEW_ACCOUNT_LIFECYCLE', target_type='account_lifecycle')
    return Response({'results': results, 'deletion_requests': deletion_request_payload})


class AdminAccountLifecycleActionView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.lifecycle.manage'
  permission_classes = [HasAdminPermission]

  def post(self, request, professional_reference):
    profile = ProfessionalProfile.objects.select_related('user').filter(
      internal_reference_code=professional_reference
    ).first()
    if profile is None:
      return Response({'message': 'Professional account not found.'}, status=status.HTTP_404_NOT_FOUND)
    action = str(request.data.get('action') or '').strip()
    reason = str(request.data.get('reason') or '').strip()
    if not reason:
      return Response({'message': 'A support reason is required.'}, status=status.HTTP_400_BAD_REQUEST)

    professional = profile.user
    if action == 'move_to_recycle':
      if not request.data.get('confirmed_identity') or not request.data.get('confirmed_consent'):
        return Response({'message': 'Identity and deletion consent must both be confirmed.'}, status=status.HTTP_400_BAD_REQUEST)
      account_lifecycle.move_professional_to_recycle(
        profile,
        reason=ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED,
        recycled_by_reference=request.admin_staff.staff_id,
      )
      SupportIncident.objects.filter(
        reporter_professional=professional,
        category=SupportIncident.CATEGORY_ACCOUNT,
        subject='Professional account deletion request',
        status__in=SupportIncident.ACTIVE_STATUSES,
      ).update(
        status=SupportIncident.STATUS_RESOLVED,
        resolution_note=reason[:5000],
        closed_at=timezone.now(),
      )
      message = 'Professional account moved to the 14-day Recycle Bin.'
    elif action == 'restore':
      try:
        account_lifecycle.restore_professional_from_recycle(profile)
      except ValueError as exc:
        return Response({'message': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
      message = 'Professional account restored. The trainer must sign in again.'
    elif action == 'delete_permanently':
      if profile.lifecycle_status != ProfessionalProfile.LIFECYCLE_RECYCLED:
        return Response({'message': 'Only recycled accounts can be permanently deleted.'}, status=status.HTTP_400_BAD_REQUEST)
      record_admin_action(
        request, permission=self.required_permission, action='PERMANENTLY_DELETE_PROFESSIONAL',
        target_type='professional', professional=professional, reason=reason,
      )
      account_lifecycle.delete_professional_data(profile)
      return Response({'message': 'Professional account permanently deleted.'})
    else:
      return Response({'message': 'Unsupported lifecycle action.'}, status=status.HTTP_400_BAD_REQUEST)

    record_admin_action(
      request, permission=self.required_permission, action=f'ACCOUNT_LIFECYCLE_{action.upper()}',
      target_type='professional', professional=professional, reason=reason,
    )
    return Response({'message': message})


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


class AdminErrorLogListView(APIView):
  """Two admin sections read from here — Web (?platform_group=web) and
  Mobile (?platform_group=mobile, every non-web platform) — via the same
  queue, just filtered differently. Default ordering (ErrorLog.Meta.ordering)
  is professional_username then most-recently-seen, so the list always reads
  grouped by professional without the caller asking for it.
  """
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.errors.list'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    logs = ErrorLog.objects.all()
    platform_group = request.query_params.get('platform_group', '').strip().lower()
    if platform_group == 'web':
      logs = logs.filter(platform=ErrorLog.PLATFORM_WEB)
    elif platform_group == 'mobile':
      logs = logs.filter(platform__in=ErrorLog.MOBILE_PLATFORMS)

    search = request.query_params.get('search', '').strip()
    if search:
      logs = logs.filter(
        Q(error_id__icontains=search) | Q(professional_username__icontains=search)
        | Q(client_username__icontains=search) | Q(message__icontains=search)
      )
    for field in ('status', 'level', 'source', 'reporter_role', 'platform'):
      value = request.query_params.get(field, '').strip()
      if value:
        logs = logs.filter(**{field: value})

    record_admin_action(
      request, permission=self.required_permission, action='LIST_ERROR_LOGS',
      target_type='errors', target_display=f'Error log queue ({platform_group or "all"})'
    )
    return Response({
      'results': ErrorLogListSerializer(logs[:200], many=True).data,
      'count': logs.count(),
      'open_count': logs.filter(status__in=ErrorLog.OPEN_STATUSES).count(),
    })


class AdminErrorLogDetailView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.errors.view'
  permission_classes = [HasAdminPermission]

  def get(self, request, error_id):
    log = ErrorLog.objects.filter(error_id=error_id).first()
    if log is None:
      return Response({'message': 'Error log not found.'}, status=status.HTTP_404_NOT_FOUND)
    record_admin_action(
      request, permission=self.required_permission, action='VIEW_ERROR_LOG',
      target_type='errors', target_id=log.error_id, target_display=log.message[:180],
      professional=log.reporter_professional, client=log.reporter_client,
    )
    return Response({'error': ErrorLogSerializer(log).data})


class AdminErrorLogActionView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.errors.manage'
  permission_classes = [HasAdminPermission]

  def post(self, request, error_id):
    log = ErrorLog.objects.filter(error_id=error_id).first()
    if log is None:
      return Response({'message': 'Error log not found.'}, status=status.HTTP_404_NOT_FOUND)

    requested_status = str(request.data.get('status', '')).strip()
    resolution_note = str(request.data.get('resolution_note', '')).strip()
    if requested_status and requested_status not in dict(ErrorLog.STATUS_CHOICES):
      return Response({'message': 'Invalid error log status.'}, status=status.HTTP_400_BAD_REQUEST)

    changed_fields = []
    if resolution_note:
      log.resolution_note = resolution_note[:5000]
      changed_fields.append('resolution_note')
    if requested_status:
      log.status = requested_status
      changed_fields.append('status')
      if requested_status == ErrorLog.STATUS_RESOLVED:
        log.resolved_by = request.user
        log.resolved_at = timezone.now()
      else:
        log.resolved_by = None
        log.resolved_at = None
      changed_fields.extend(['resolved_by', 'resolved_at'])
    if changed_fields:
      log.save(update_fields=list(dict.fromkeys(changed_fields)))

    record_admin_action(
      request, permission=self.required_permission, action='UPDATE_ERROR_LOG',
      target_type='errors', target_id=log.error_id, target_display=log.message[:180],
      professional=log.reporter_professional, client=log.reporter_client,
      reason=resolution_note, metadata={'status': log.status},
    )
    log.refresh_from_db()
    return Response({'error': ErrorLogSerializer(log).data, 'message': 'Error log updated.'})
