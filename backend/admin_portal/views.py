from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import connection
from django.db.models import Avg, Count, Q, Sum
from django.utils import timezone
from django.utils.dateparse import parse_date
from rest_framework import status
from rest_framework.authtoken.models import Token
from accounts.authentication import ExpiringTokenAuthentication as TokenAuthentication
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from accounts import account_lifecycle
from accounts.data_usage import calculate_professional_data_usage
from accounts.models import ActivityNotification, ChatMessage, ClientAccess, LeadSubmission, NotificationDeliveryAttempt, ProfessionalGroup, ProfessionalLeadForm, ProfessionalProfile, ProfessionalResource, RecycleBinItem, ScheduledMeeting, SupportIncident, SupportIncidentMessage, TemplateAssignment, TrackingEntry, TrackingTemplate, ClientReminder
from accounts.serializers import SupportIncidentSerializer

from .audit import record_admin_action
from .models import AdminAuditLog, AdminPermission, AdminRole, AdminStaffPermissionOverride, AdminStaffProfile, ErrorLog, FinanceLedgerEntry, OperationEvent, PlatformExpense, SupportAccessGrant
from .permissions import HasAdminPermission, active_staff_for, permission_codes_for
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
  if key == 'lifetime':
    return None
  if key == 'custom':
    value = parse_date(request.query_params.get('start_date', ''))
    if value:
      return timezone.make_aware(timezone.datetime.combine(value, timezone.datetime.min.time()))
  days = {'today': 0, '7d': 7, '30d': 30, '90d': 90, '180d': 180, '365d': 365}.get(key, 30)
  return now.replace(hour=0, minute=0, second=0, microsecond=0) if days == 0 else now - timedelta(days=days)


def range_end(request):
  if request.query_params.get('range') != 'custom':
    return None
  value = parse_date(request.query_params.get('end_date', ''))
  return timezone.make_aware(timezone.datetime.combine(value, timezone.datetime.max.time())) if value else None


def ranged(queryset, field, start, end=None):
  filters = {}
  if start:
    filters[f'{field}__gte'] = start
  if end:
    filters[f'{field}__lte'] = end
  return queryset.filter(**filters)


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
    staff.last_admin_login_at = timezone.now()
    staff.save(update_fields=['last_admin_login_at', 'updated_at'])
    request.admin_staff = staff
    record_admin_action(request, permission='admin.auth.login', action='ADMIN_LOGIN', target_type='staff', target_id=staff.staff_id, target_display=f'{staff.staff_id} · {user.username}')
    return Response({'token': token.key, 'staff': staff_payload(staff)})


class AdminPasswordChangeView(APIView):
  authentication_classes = [TokenAuthentication]

  def post(self, request):
    staff = active_staff_for(request.user)
    if not staff:
      return Response({'message': 'Active staff account required.'}, status=403)
    current_password = str(request.data.get('current_password', ''))
    password = str(request.data.get('password', ''))
    confirm = str(request.data.get('confirm_password', ''))
    if not request.user.check_password(current_password):
      return Response({'message': 'Current password is incorrect.'}, status=400)
    if password != confirm or len(password) < 10 or password == current_password:
      return Response({'message': 'Use a new matching password of at least 10 characters.'}, status=400)
    request.user.set_password(password)
    request.user.save(update_fields=['password'])
    staff.must_change_password = False
    staff.save(update_fields=['must_change_password', 'updated_at'])
    request.admin_staff = staff
    Token.objects.filter(user=request.user).delete()
    record_admin_action(request, permission='admin.auth.password_change', action='ADMIN_PASSWORD_CHANGED', target_type='staff', target_id=staff.staff_id, target_display=request.user.username)
    return Response({'message': 'Password changed. Sign in again with your new password.'})


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
    end = range_end(request)
    professionals = User.objects.filter(professional_profile__isnull=False)
    clients = ClientAccess.objects.all()
    payload = {
      'range_start': start,
      'accounts': {
        'total_professionals': professionals.count(), 'active_professionals': professionals.filter(is_active=True).count(),
        'suspended_professionals': professionals.filter(is_active=False).count(),
        'pending_deletion': professionals.filter(professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_RECYCLED).count(),
        'new_professionals': ranged(professionals, 'date_joined', start, end).count(),
      },
      'clients': {
        'total_clients': clients.count(), 'active_clients': clients.filter(is_active=True).count(),
        'inactive_clients': clients.filter(is_active=False).count(), 'new_clients': ranged(clients, 'created_at', start, end).count(),
      },
      'users': {
        'total_accounts': professionals.count() + clients.count() + AdminStaffProfile.objects.count(),
        'professional_accounts': professionals.count(), 'client_accounts': clients.count(), 'internal_accounts': AdminStaffProfile.objects.count(),
      },
      'usage': {
        'lead_forms': ProfessionalLeadForm.objects.count(), 'active_lead_forms': ProfessionalLeadForm.objects.filter(is_active=True).count(),
        'form_submissions': LeadSubmission.objects.count(), 'groups': ProfessionalGroup.objects.count(),
        'templates': TrackingTemplate.objects.count(), 'resources': ProfessionalResource.objects.count(),
        'scheduled_followups': ClientReminder.objects.filter(status='pending').count(),
      },
    }
    storage_bytes = 0
    for professional in professionals.iterator():
      usage = calculate_professional_data_usage(professional)
      storage_bytes += round((usage['usage_percent'] / 100) * usage['included_quota_bytes'])
    payload['storage'] = {'total_bytes': storage_bytes, 'total_mb': round(storage_bytes / 1048576, 2), 'average_mb_per_professional': round(storage_bytes / max(1, professionals.count()) / 1048576, 2)}
    payload['subscriptions'] = {row['plan_tier']: row['total'] for row in ProfessionalProfile.objects.values('plan_tier').annotate(total=Count('id')).order_by('plan_tier')}
    payload['range_end'] = end
    record_admin_action(request, permission=self.required_permission, action='VIEW_ADMIN_DASHBOARD', target_type='platform', target_display='Aggregate platform dashboard')
    return Response(payload)


class AdminFinanceView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.finance.view'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    start = range_start(request)
    end = range_end(request)
    entries = FinanceLedgerEntry.objects.select_related('professional', 'professional__professional_profile').filter(source__in=['subscription', 'platform_commission', 'manual_business'])
    period_entries = ranged(entries, 'occurred_at', start, end)
    completed = period_entries.filter(status=FinanceLedgerEntry.STATUS_COMPLETED)
    refunds = period_entries.filter(entry_type=FinanceLedgerEntry.TYPE_REFUND)
    expenses = ranged(PlatformExpense.objects.select_related('recorded_by__user'), 'expense_date', start.date() if start else None, end.date() if end else None)
    payload = {
      'billing_provider': 'Not configured',
      'finance_tracking_status': 'RepRoot business ledger',
      'summary': {
        'revenue_by_currency': {row['currency']: row['total'] for row in completed.values('currency').annotate(total=Sum('amount'))},
        'expense_by_currency': {row['currency']: row['total'] for row in expenses.values('currency').annotate(total=Sum('amount'))},
        'completed_transactions': completed.count(), 'pending_transactions': entries.filter(status='PENDING').count(),
        'failed_transactions': period_entries.filter(status='FAILED').count(),
        'refund_by_currency': {row['currency']: row['total'] for row in refunds.values('currency').annotate(total=Sum('amount'))},
      },
      'subscriptions': FinanceLedgerEntrySerializer(period_entries.filter(source='subscription')[:50], many=True).data,
      'commissions': FinanceLedgerEntrySerializer(period_entries.filter(source='platform_commission')[:50], many=True).data,
      'expenses': [{'expense_id': item.expense_id, 'category': item.category, 'category_label': item.get_category_display(), 'amount': item.amount, 'currency': item.currency, 'vendor': item.vendor, 'description': item.description, 'expense_date': item.expense_date, 'recorded_by': item.recorded_by.user.get_full_name() or item.recorded_by.user.username} for item in expenses[:100]],
    }
    record_admin_action(request, permission=self.required_permission, action='VIEW_FINANCE_SUMMARY', target_type='finance', target_display='Aggregate finance summary')
    return Response(payload)

  def post(self, request):
    if 'admin.finance.edit' not in permission_codes_for(request.admin_staff):
      return Response({'message': 'You do not have permission to record expenses.'}, status=403)
    try:
      amount = Decimal(str(request.data.get('amount', '')))
    except Exception:
      return Response({'message': 'Enter a valid amount.'}, status=400)
    currency = str(request.data.get('currency', '')).upper().strip()
    expense_date = parse_date(str(request.data.get('expense_date', '')))
    category = str(request.data.get('category', '')).upper()
    description = str(request.data.get('description', '')).strip()
    if amount <= 0 or len(currency) != 3 or not expense_date or not description or category not in dict(PlatformExpense.CATEGORY_CHOICES):
      return Response({'message': 'Amount, currency, category, date and description are required.'}, status=400)
    expense = PlatformExpense.objects.create(category=category, amount=amount, currency=currency, vendor=str(request.data.get('vendor', ''))[:160], description=description[:300], expense_date=expense_date, external_reference=str(request.data.get('external_reference', ''))[:120], recorded_by=request.admin_staff)
    record_admin_action(request, permission='admin.finance.edit', action='CREATE_PLATFORM_EXPENSE', target_type='expense', target_id=expense.expense_id, target_display=expense.description, metadata={'amount': str(amount), 'currency': currency})
    return Response({'expense_id': expense.expense_id, 'message': 'Expense recorded.'}, status=201)


class AdminOperationsView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.operations.view'; permission_classes=[HasAdminPermission]
  def get(self, request):
    start,end=range_start(request),range_end(request)
    modules={
      'Forms':ProfessionalLeadForm.objects.all(),'Submissions':LeadSubmission.objects.all(),'Groups':ProfessionalGroup.objects.all(),
      'Clients':ClientAccess.objects.all(),'Templates':TrackingTemplate.objects.all(),'Assignments':TemplateAssignment.objects.all(),
      'Entries':TrackingEntry.objects.all(),'Resources':ProfessionalResource.objects.all(),'Schedules':ScheduledMeeting.objects.all(),
      'Reminders':ClientReminder.objects.all(),'Chat':ChatMessage.objects.all(),'Notifications':ActivityNotification.objects.all(),
    }
    events=ranged(OperationEvent.objects.all(),'occurred_at',start,end)
    usage=[]
    for name,qs in modules.items():
      usage.append({'module':name,'total_records':qs.count(),'period_events':events.filter(module__iexact=name).count(),'active_professionals':events.filter(module__iexact=name).exclude(professional_reference='').values('professional_reference').distinct().count(),'failures':events.filter(module__iexact=name,success=False).count()})
    professionals=User.objects.filter(professional_profile__isnull=False)
    funnel=[
      {'stage':'Registered','count':professionals.count()},
      {'stage':'Profile completed','count':professionals.filter(professional_profile__profile_setup_completed=True).count()},
      {'stage':'Created form','count':professionals.filter(lead_forms__isnull=False).distinct().count()},
      {'stage':'Created group','count':professionals.filter(professional_groups__isnull=False).distinct().count()},
      {'stage':'Added client','count':professionals.filter(client_access_records__isnull=False).distinct().count()},
      {'stage':'Created template','count':professionals.filter(tracking_templates__isnull=False).distinct().count()},
    ]
    recycle_count=RecycleBinItem.objects.count()
    payload={'modules':usage,'trainer_funnel':funnel,'events':{'total':events.count(),'failed':events.filter(success=False).count(),'average_duration_ms':events.aggregate(value=Avg('duration_ms'))['value']},'storage':{'recycle_items':recycle_count,'database_measurement':'Application-record estimate','file_measurement':'Tracked by professional storage calculator'},'range_start':start,'range_end':end}
    record_admin_action(request,permission=self.required_permission,action='VIEW_OPERATIONS_ANALYTICS',target_type='operations')
    return Response(payload)


def directory_professional_payload(user):
  profile=user.professional_profile
  usage=calculate_professional_data_usage(user)
  return {'type':'professional','reference':profile.internal_reference_code,'username':user.username,'name':user.get_full_name(),'email':user.email,'active':user.is_active,'plan':profile.plan_tier,'profile_complete':profile.profile_setup_completed,'clients':ClientAccess.objects.filter(professional=user).count(),'groups':ProfessionalGroup.objects.filter(professional=user).count(),'forms':ProfessionalLeadForm.objects.filter(professional=user).count(),'templates':TrackingTemplate.objects.filter(professional=user).count(),'storage_percent':usage['usage_percent'],'last_login':user.last_login,'open_tickets':SupportIncident.objects.filter(reporter_professional=user,status__in=SupportIncident.ACTIVE_STATUSES).count(),'recent_errors':ErrorLog.objects.filter(reporter_professional=user,status__in=ErrorLog.OPEN_STATUSES).count()}


class AdminUserDirectoryView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.users.view'; permission_classes=[HasAdminPermission]
  def get(self,request):
    search=str(request.query_params.get('search','')).strip(); kind=str(request.query_params.get('type','')).strip()
    professionals=User.objects.filter(professional_profile__isnull=False).select_related('professional_profile')
    clients=ClientAccess.objects.select_related('professional','group')
    if search:
      professionals=professionals.filter(Q(username__icontains=search)|Q(email__icontains=search)|Q(first_name__icontains=search)|Q(last_name__icontains=search)|Q(professional_profile__internal_reference_code__icontains=search))
      clients=clients.filter(Q(username__icontains=search)|Q(email__icontains=search)|Q(first_name__icontains=search)|Q(last_name__icontains=search)|Q(reference_id__icontains=search))
    results=[]
    if kind!='client': results.extend(directory_professional_payload(user) for user in professionals[:50])
    if kind!='professional': results.extend({'type':'client','reference':c.reference_id,'username':c.username,'name':f'{c.first_name} {c.last_name}'.strip(),'email':c.email,'active':c.is_active,'professional':c.professional.username,'group':c.group.name if c.group else '','last_login':None,'assignments':c.template_assignments.count(),'open_tickets':SupportIncident.objects.filter(reporter_client=c,status__in=SupportIncident.ACTIVE_STATUSES).count()} for c in clients[:50])
    record_admin_action(request,permission=self.required_permission,action='SEARCH_USER_DIRECTORY',target_type='directory',target_display=search or 'Recent accounts')
    return Response({'results':results,'count':len(results)})


class AdminCommunicationsView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.communications.view'; permission_classes=[HasAdminPermission]
  def get(self,request):
    attempts=NotificationDeliveryAttempt.objects.all(); notifications=ActivityNotification.objects.all()
    by_channel={row['channel']:{'total':row['total'],'failed':attempts.filter(channel=row['channel'],status='failed').count()} for row in attempts.values('channel').annotate(total=Count('id'))}
    return Response({'providers':{'smtp':{'configured':bool(getattr(settings,'EMAIL_HOST','')),'status':'ready' if getattr(settings,'EMAIL_HOST','') else 'awaiting_configuration'},'push':{'configured':False,'status':'mobile_provider_not_configured'}},'notifications':{'total':notifications.count(),'unread':notifications.filter(is_read=False).count(),'email_queued':notifications.filter(email_status='queued').count(),'email_failed':notifications.filter(email_status='failed').count(),'push_queued':notifications.filter(push_status='queued').count(),'push_failed':notifications.filter(push_status='failed').count()},'delivery_by_channel':by_channel,'recent_failures':[{'channel':a.channel,'status':a.status,'error':a.error,'attempted_at':a.attempted_at} for a in attempts.filter(status='failed')[:50]]})


class AdminSystemHealthView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.health.view'; permission_classes=[HasAdminPermission]
  def get(self,request):
    db_ok=True
    try:
      with connection.cursor() as cursor: cursor.execute('SELECT 1'); cursor.fetchone()
    except Exception: db_ok=False
    open_errors=ErrorLog.objects.filter(status__in=ErrorLog.OPEN_STATUSES)
    return Response({'services':[{'name':'API','status':'healthy'},{'name':'Database','status':'healthy' if db_ok else 'unavailable'},{'name':'SMTP','status':'configured' if getattr(settings,'EMAIL_HOST','') else 'awaiting_configuration'},{'name':'Payment provider','status':'awaiting_provider'},{'name':'Background queue','status':'not_configured'}],'errors':{'open':open_errors.count(),'fatal':open_errors.filter(level='fatal').count(),'web':open_errors.filter(platform='web').count(),'android':open_errors.filter(platform='android').count(),'ios':open_errors.filter(platform='ios').count()},'events':{'failed_last_24h':OperationEvent.objects.filter(success=False,occurred_at__gte=timezone.now()-timedelta(days=1)).count()},'note':'Host CPU, memory and uptime require deployment monitoring integration.'})


class AdminGlobalSearchView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.search.use'; permission_classes=[HasAdminPermission]
  def get(self,request):
    term=str(request.query_params.get('q','')).strip()
    if len(term)<2:return Response({'results':[]})
    results=[]
    for u in User.objects.filter(professional_profile__isnull=False).filter(Q(username__icontains=term)|Q(email__icontains=term)|Q(professional_profile__internal_reference_code__icontains=term)).select_related('professional_profile')[:10]: results.append({'type':'Professional','id':u.professional_profile.internal_reference_code,'title':u.get_full_name() or u.username,'subtitle':u.email,'url':'/admin-portal/users'})
    for c in ClientAccess.objects.filter(Q(username__icontains=term)|Q(email__icontains=term)|Q(reference_id__icontains=term))[:10]: results.append({'type':'Client','id':c.reference_id,'title':f'{c.first_name} {c.last_name}'.strip() or c.username,'subtitle':c.email,'url':'/admin-portal/users'})
    for i in SupportIncident.objects.filter(Q(incident_id__icontains=term)|Q(subject__icontains=term)|Q(reporter_email__icontains=term))[:10]: results.append({'type':'Support','id':i.incident_id,'title':i.subject,'subtitle':i.status,'url':'/admin-portal/support'})
    for e in ErrorLog.objects.filter(Q(error_id__icontains=term)|Q(message__icontains=term))[:10]: results.append({'type':'Error','id':e.error_id,'title':e.message[:120],'subtitle':e.status,'url':f'/admin-portal/errors/{e.platform if e.platform in ("web","android","ios") else "web"}'})
    return Response({'results':results[:30]})


class AdminSupportAccessView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.support.access_request'; permission_classes=[HasAdminPermission]
  def post(self,request,incident_id):
    incident=SupportIncident.objects.filter(incident_id=incident_id).first()
    if not incident:return Response({'message':'Support incident not found.'},status=404)
    scope=str(request.data.get('scope','metadata')); module=str(request.data.get('module','')).strip(); reason=str(request.data.get('reason','')).strip(); consent=str(request.data.get('consent_reference','')).strip()
    if scope not in dict(SupportAccessGrant.SCOPE_CHOICES) or not reason:return Response({'message':'Valid scope and investigation reason are required.'},status=400)
    grant=SupportAccessGrant.objects.create(incident=incident,requested_by=request.admin_staff,scope=scope,module=module,reason=reason,consent_reference=consent,status='approved' if consent else 'requested',approved_at=timezone.now() if consent else None,expires_at=timezone.now()+timedelta(hours=1) if consent else None)
    record_admin_action(request,permission=self.required_permission,action='REQUEST_SUPPORT_ACCESS',target_type='support_access',target_id=grant.access_id,target_display=incident.incident_id,reason=reason,metadata={'scope':scope,'module':module,'consent_reference':consent})
    return Response({'access_id':grant.access_id,'status':grant.status,'expires_at':grant.expires_at,'message':'Consent recorded and temporary access activated.' if consent else 'Access request recorded; user consent is still required.'},status=201)


class AdminSupportControlledActionView(APIView):
  authentication_classes=[TokenAuthentication]; required_permission='admin.support.actions'; permission_classes=[HasAdminPermission]
  def post(self,request,incident_id):
    incident=SupportIncident.objects.select_related('reporter_professional','reporter_client').filter(incident_id=incident_id).first()
    if not incident:return Response({'message':'Support incident not found.'},status=404)
    action=str(request.data.get('action','')); reason=str(request.data.get('reason','')).strip(); access_id=str(request.data.get('access_id',''))
    grant=SupportAccessGrant.objects.filter(access_id=access_id,incident=incident,status='approved',expires_at__gt=timezone.now()).first()
    if not grant or not reason:return Response({'message':'An active consent grant and action reason are required.'},status=403)
    target_user=incident.reporter_professional or (incident.reporter_client.professional if incident.reporter_client_id else None)
    if action=='end_sessions':
      if incident.reporter_professional_id: Token.objects.filter(user=incident.reporter_professional).delete()
      elif incident.reporter_client_id and hasattr(incident.reporter_client,'auth_token'): incident.reporter_client.auth_token.delete()
      message='Active application sessions ended.'
    elif action=='unlock_account':
      if incident.reporter_professional_id: User.objects.filter(pk=incident.reporter_professional_id).update(is_active=True)
      elif incident.reporter_client_id: ClientAccess.objects.filter(pk=incident.reporter_client_id).update(is_active=True)
      message='Account access restored.'
    else:return Response({'message':'Unsupported controlled action.'},status=400)
    record_admin_action(request,permission=self.required_permission,action=f'SUPPORT_{action.upper()}',target_type='support',target_id=incident.incident_id,target_display=incident.reporter_email,reason=reason,professional=target_user,client=incident.reporter_client,metadata={'access_id':grant.access_id,'consent_reference':grant.consent_reference})
    return Response({'message':message})


class AdminTeamView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.staff.list'
  permission_classes = [HasAdminPermission]

  def get(self, request):
    visible_staff = AdminStaffProfile.objects.select_related('user', 'role')
    if not request.admin_staff.is_owner:
      visible_staff = visible_staff.filter(department=request.admin_staff.department, authority_level__lt=request.admin_staff.authority_level)
    allowed_codes = set(permission_codes_for(request.admin_staff))
    permissions = list(AdminPermission.objects.filter(code__in=allowed_codes).values('code', 'name', 'section', 'description'))
    roles_qs = AdminRole.objects.all() if request.admin_staff.is_owner else AdminRole.objects.exclude(slug='super-admin')
    roles = [{'slug': role.slug, 'name': role.name, 'description': role.description} for role in roles_qs]
    staff = [{'staff_id': member.staff_id, 'username': member.user.username, 'email': member.user.email,
      'full_name': member.user.get_full_name(), 'role': member.role.name, 'role_slug': member.role.slug,
      'status': member.status, 'department': member.department, 'department_label': member.get_department_display(),
      'authority_level': member.authority_level, 'is_owner': member.is_owner, 'must_change_password': member.must_change_password,
      'last_admin_login_at': member.last_admin_login_at, 'permissions': permission_codes_for(member), 'created_at': member.created_at}
      for member in visible_staff]
    return Response({'staff': staff, 'roles': roles, 'permissions': permissions, 'departments': [{'code': code, 'name': name} for code, name in AdminStaffProfile.DEPARTMENT_CHOICES], 'viewer': staff_payload(request.admin_staff)})

  def post(self, request):
    if 'admin.staff.create' not in permission_codes_for(request.admin_staff):
      return Response({'message': 'You do not have permission to create team members.'}, status=403)
    username, email, password = (str(request.data.get(key, '')).strip() for key in ('username', 'email', 'password'))
    role = AdminRole.objects.filter(slug=request.data.get('role_slug')).first()
    department = str(request.data.get('department', request.admin_staff.department)).upper()
    authority_level = int(request.data.get('authority_level', AdminStaffProfile.LEVEL_STAFF))
    if not request.admin_staff.is_owner:
      department = request.admin_staff.department
      authority_level = min(authority_level, request.admin_staff.authority_level - 1)
      if role and role.slug == 'super-admin':
        return Response({'message': 'Only the Owner can create Super Admin access.'}, status=403)
      if role:
        role_permissions = set(role.permission_links.filter(allowed=True).values_list('permission__code', flat=True))
        actor_permissions = set(permission_codes_for(request.admin_staff))
        if not role_permissions.issubset(actor_permissions):
          return Response(
            {'message': 'You cannot assign a role that has permissions beyond your own.'}, status=403
          )
    if not username or not email or len(password) < 10 or not role or User.objects.filter(Q(username__iexact=username) | Q(email__iexact=email)).exists():
      return Response({'message': 'Unique username/email, role and a password of at least 10 characters are required.'}, status=400)
    user = User.objects.create_user(username=username.lower(), email=email.lower(), password=password, first_name=str(request.data.get('first_name', ''))[:150], last_name=str(request.data.get('last_name', ''))[:150], is_staff=True)
    if department not in dict(AdminStaffProfile.DEPARTMENT_CHOICES) or authority_level < AdminStaffProfile.LEVEL_STAFF or authority_level >= request.admin_staff.authority_level:
      user.delete()
      return Response({'message': 'Invalid department or authority level.'}, status=400)
    member = AdminStaffProfile.objects.create(user=user, role=role, department=department, authority_level=authority_level, must_change_password=True, created_by=request.user)
    self.save_overrides(member, request.data.get('permissions'), request.admin_staff)
    record_admin_action(request, permission='admin.staff.create', action='CREATE_ADMIN_STAFF', target_type='staff', target_id=member.staff_id, target_display=username)
    return Response({'staff_id': member.staff_id, 'message': 'Team member created.'}, status=201)

  @staticmethod
  def save_overrides(member, selected, actor):
    role_permissions = set(member.role.permission_links.filter(allowed=True).values_list('permission__code', flat=True))
    actor_permissions = None if actor.is_owner else set(permission_codes_for(actor))

    if selected is not None:
      selected = set(selected)
      if actor_permissions is not None:
        selected &= actor_permissions
    elif actor_permissions is not None:
      # No explicit override selection was supplied. A non-owner actor must
      # never be able to hand out permissions - via the role alone - that
      # they don't hold themselves, so cap the effective set here too rather
      # than relying solely on the upfront role-assignment check above.
      selected = role_permissions & actor_permissions
    else:
      return

    member.permission_overrides.all().delete()
    for permission in AdminPermission.objects.all():
      allowed = permission.code in selected
      if allowed != (permission.code in role_permissions):
        AdminStaffPermissionOverride.objects.create(staff=member, permission=permission, allowed=allowed)


class AdminTeamMemberView(APIView):
  authentication_classes = [TokenAuthentication]
  required_permission = 'admin.staff.create'
  permission_classes = [HasAdminPermission]

  def put(self, request, staff_id):
    member = AdminStaffProfile.objects.select_related('user', 'role').filter(staff_id=staff_id).first()
    if not member:
      return Response({'message': 'Team member not found.'}, status=404)
    if member.is_owner:
      return Response({'message': 'The protected Owner account cannot be modified from staff management.'}, status=403)
    if not request.admin_staff.is_owner and (member.department != request.admin_staff.department or member.authority_level >= request.admin_staff.authority_level):
      return Response({'message': 'You can manage only lower-authority staff in your own department.'}, status=403)
    if member.pk == request.admin_staff.pk and request.data.get('status') == AdminStaffProfile.STATUS_DISABLED:
      return Response({'message': 'You cannot disable your own account.'}, status=400)
    role = AdminRole.objects.filter(slug=request.data.get('role_slug', member.role.slug)).first()
    if not request.admin_staff.is_owner and role:
      if role.slug == 'super-admin':
        return Response({'message': 'Only the Owner can assign Super Admin access.'}, status=403)
      role_permissions = set(role.permission_links.filter(allowed=True).values_list('permission__code', flat=True))
      actor_permissions = set(permission_codes_for(request.admin_staff))
      if not role_permissions.issubset(actor_permissions):
        return Response(
          {'message': 'You cannot assign a role that has permissions beyond your own.'}, status=403
        )
    if role:
      member.role = role
    if request.data.get('status') in dict(AdminStaffProfile.STATUS_CHOICES):
      member.status = request.data['status']
      member.disabled_at = timezone.now() if member.status == AdminStaffProfile.STATUS_DISABLED else None
    member.save(update_fields=['role', 'status', 'disabled_at', 'updated_at'])
    AdminTeamView.save_overrides(member, request.data.get('permissions'), request.admin_staff)
    record_admin_action(request, permission=self.required_permission, action='UPDATE_ADMIN_STAFF_ACCESS', target_type='staff', target_id=member.staff_id, target_display=member.user.username)
    return Response({'message': 'Team access updated.', 'permissions': permission_codes_for(member)})


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
        # Self-service deletion detail. Null for accounts that reached a
        # non-active state some other way (billing freeze, admin action).
        'deletion_requested_at': profile.deletion_requested_at,
        'deletion_hold_ends_at': profile.deletion_hold_ends_at,
        'deletion_impact': profile.deletion_impact_snapshot or {},
        'is_self_requested': profile.lifecycle_reason == ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED,
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
        retention_days=settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS,
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
      message = f'Professional account moved to the {settings.REPROOT_PROFESSIONAL_RECYCLE_DAYS}-day Recycle Bin.'
    elif action == 'cancel_deletion':
      from accounts.professional_deletion import cancel_deletion
      if not cancel_deletion(profile, reason='our support team cancelled it'):
        return Response(
          {'message': 'This account does not have a pending deletion to cancel.'},
          status=status.HTTP_400_BAD_REQUEST,
        )
      message = 'Scheduled deletion cancelled. The account and its clients are active again.'
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
    elif platform_group in ('android', 'ios'):
      logs = logs.filter(platform=platform_group)
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
