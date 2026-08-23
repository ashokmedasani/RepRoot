import uuid
import re
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.db.models import F
from django.utils import timezone


def staff_reference():
  return f'STF-{uuid.uuid4().hex[:10].upper()}'


def finance_reference():
  return f'FIN-{uuid.uuid4().hex[:12].upper()}'


def expense_reference():
  return f'EXP-{uuid.uuid4().hex[:12].upper()}'


def error_log_reference():
  return f'ERR-{uuid.uuid4().hex[:10].upper()}'


def support_access_reference():
  return f'ACC-{uuid.uuid4().hex[:10].upper()}'


class AdminPermission(models.Model):
  code = models.CharField(max_length=100, unique=True, db_index=True)
  name = models.CharField(max_length=140)
  section = models.CharField(max_length=60, db_index=True)
  description = models.TextField(blank=True)

  class Meta:
    db_table = 'admin_permissions'
    ordering = ['section', 'code']


class AdminRole(models.Model):
  name = models.CharField(max_length=80, unique=True)
  slug = models.SlugField(max_length=80, unique=True)
  description = models.TextField(blank=True)
  is_system = models.BooleanField(default=True)
  permissions = models.ManyToManyField(AdminPermission, through='AdminRolePermission', related_name='roles')
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'admin_roles'
    ordering = ['name']


class AdminRolePermission(models.Model):
  role = models.ForeignKey(AdminRole, on_delete=models.CASCADE, related_name='permission_links')
  permission = models.ForeignKey(AdminPermission, on_delete=models.CASCADE, related_name='role_links')
  allowed = models.BooleanField(default=True)

  class Meta:
    db_table = 'admin_role_permissions'
    constraints = [models.UniqueConstraint(fields=['role', 'permission'], name='unique_admin_role_permission')]


class AdminStaffProfile(models.Model):
  STATUS_ACTIVE = 'ACTIVE'
  STATUS_DISABLED = 'DISABLED'
  STATUS_CHOICES = [(STATUS_ACTIVE, 'Active'), (STATUS_DISABLED, 'Disabled')]
  DEPARTMENT_CHOICES = [
    ('OWNER', 'Owner'), ('OPERATIONS', 'Operations'), ('SUPPORT', 'Customer Support'),
    ('FINANCE', 'Finance'), ('TECHNICAL', 'Technical Operations'),
    ('SECURITY', 'Security'), ('ANALYTICS', 'Analytics'),
  ]
  LEVEL_STAFF = 10
  LEVEL_MANAGER = 50
  LEVEL_OWNER = 100

  user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='admin_staff_profile')
  staff_id = models.CharField(max_length=24, unique=True, default=staff_reference, editable=False, db_index=True)
  role = models.ForeignKey(AdminRole, on_delete=models.PROTECT, related_name='staff_members')
  status = models.CharField(max_length=12, choices=STATUS_CHOICES, default=STATUS_ACTIVE, db_index=True)
  department = models.CharField(max_length=20, choices=DEPARTMENT_CHOICES, default='OPERATIONS', db_index=True)
  authority_level = models.PositiveSmallIntegerField(default=LEVEL_STAFF, db_index=True)
  is_owner = models.BooleanField(default=False, db_index=True)
  must_change_password = models.BooleanField(default=True)
  last_admin_login_at = models.DateTimeField(null=True, blank=True)
  created_by = models.ForeignKey(
    settings.AUTH_USER_MODEL,
    on_delete=models.SET_NULL,
    null=True,
    blank=True,
    related_name='created_admin_staff_profiles',
  )
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)
  disabled_at = models.DateTimeField(null=True, blank=True)

  class Meta:
    db_table = 'admin_staff_profiles'


class AdminStaffPermissionOverride(models.Model):
  staff = models.ForeignKey(AdminStaffProfile, on_delete=models.CASCADE, related_name='permission_overrides')
  permission = models.ForeignKey(AdminPermission, on_delete=models.CASCADE, related_name='staff_overrides')
  allowed = models.BooleanField(default=True)

  class Meta:
    db_table = 'admin_staff_permission_overrides'
    constraints = [models.UniqueConstraint(fields=['staff', 'permission'], name='unique_admin_staff_override')]


class OperationEvent(models.Model):
  """Privacy-minimized product event. Never stores message, health, form-answer, or payment content."""
  event_type = models.CharField(max_length=100, db_index=True)
  module = models.CharField(max_length=40, db_index=True)
  actor_type = models.CharField(max_length=20, choices=[('professional','Professional'),('client','Client'),('system','System')], db_index=True)
  professional_reference = models.CharField(max_length=24, blank=True, db_index=True)
  client_reference = models.CharField(max_length=32, blank=True, db_index=True)
  plan_tier = models.CharField(max_length=20, blank=True, db_index=True)
  platform = models.CharField(max_length=20, blank=True, db_index=True)
  success = models.BooleanField(default=True, db_index=True)
  duration_ms = models.PositiveIntegerField(null=True, blank=True)
  metadata = models.JSONField(default=dict, blank=True)
  occurred_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'operation_events'
    ordering = ['-occurred_at']
    indexes = [models.Index(fields=['module','occurred_at'], name='operation_module_time_idx')]


class SupportAccessGrant(models.Model):
  SCOPE_CHOICES = [('metadata','Account metadata'),('module','Specific module'),('readonly','Read-only account view')]
  STATUS_CHOICES = [('requested','Requested'),('approved','Approved'),('revoked','Revoked'),('expired','Expired')]
  access_id = models.CharField(max_length=24, default=support_access_reference, unique=True, editable=False)
  incident = models.ForeignKey('accounts.SupportIncident', on_delete=models.CASCADE, related_name='access_grants')
  requested_by = models.ForeignKey(AdminStaffProfile, on_delete=models.PROTECT, related_name='requested_support_access')
  scope = models.CharField(max_length=16, choices=SCOPE_CHOICES, default='metadata')
  module = models.CharField(max_length=40, blank=True)
  reason = models.TextField()
  status = models.CharField(max_length=12, choices=STATUS_CHOICES, default='requested', db_index=True)
  consent_reference = models.CharField(max_length=120, blank=True)
  approved_at = models.DateTimeField(null=True, blank=True)
  expires_at = models.DateTimeField(null=True, blank=True, db_index=True)
  revoked_at = models.DateTimeField(null=True, blank=True)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'support_access_grants'
    ordering = ['-created_at']


class AdminAuditLog(models.Model):
  staff = models.ForeignKey(AdminStaffProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
  staff_reference_snapshot = models.CharField(max_length=120, blank=True)
  role_snapshot = models.CharField(max_length=80, blank=True)
  permission_used = models.CharField(max_length=100, blank=True, db_index=True)
  action = models.CharField(max_length=100, db_index=True)
  target_type = models.CharField(max_length=60, blank=True, db_index=True)
  target_id = models.CharField(max_length=80, blank=True)
  target_display = models.CharField(max_length=180, blank=True, db_index=True)
  professional_username_snapshot = models.CharField(max_length=150, blank=True)
  professional_reference_snapshot = models.CharField(max_length=24, blank=True)
  client_reference_snapshot = models.CharField(max_length=32, blank=True)
  reason = models.TextField(blank=True)
  ip_address = models.GenericIPAddressField(null=True, blank=True)
  user_agent = models.CharField(max_length=300, blank=True)
  correlation_id = models.CharField(max_length=40, db_index=True)
  success = models.BooleanField(default=True, db_index=True)
  metadata = models.JSONField(default=dict, blank=True)
  created_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'admin_audit_logs'
    ordering = ['-created_at']
    indexes = [models.Index(fields=['target_type', 'target_display'], name='admin_audit_target_idx')]

  def save(self, *args, **kwargs):
    if self.pk:
      raise ValueError('Administrative audit logs are immutable.')
    return super().save(*args, **kwargs)


class FinanceLedgerEntry(models.Model):
  TYPE_SUBSCRIPTION = 'SUBSCRIPTION'
  TYPE_PAYMENT = 'PAYMENT'
  TYPE_REFUND = 'REFUND'
  TYPE_ADJUSTMENT = 'ADJUSTMENT'
  TYPE_CHOICES = [(value, value.title()) for value in (TYPE_SUBSCRIPTION, TYPE_PAYMENT, TYPE_REFUND, TYPE_ADJUSTMENT)]
  STATUS_PENDING = 'PENDING'
  STATUS_COMPLETED = 'COMPLETED'
  STATUS_FAILED = 'FAILED'
  STATUS_REFUNDED = 'REFUNDED'
  STATUS_CHOICES = [(value, value.title()) for value in (STATUS_PENDING, STATUS_COMPLETED, STATUS_FAILED, STATUS_REFUNDED)]

  entry_id = models.CharField(max_length=24, unique=True, default=finance_reference, editable=False, db_index=True)
  entry_type = models.CharField(max_length=20, choices=TYPE_CHOICES, db_index=True)
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
  amount = models.DecimalField(max_digits=12, decimal_places=2)
  currency = models.CharField(max_length=3, default='USD')
  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='finance_entries')
  description = models.CharField(max_length=240, blank=True)
  external_reference = models.CharField(max_length=100, blank=True)
  source = models.CharField(max_length=24, default='platform', db_index=True)
  professional_reference = models.CharField(max_length=24, blank=True)
  client_reference = models.CharField(max_length=32, blank=True)
  payment_request_reference = models.CharField(max_length=32, blank=True)
  payment_record_reference = models.CharField(max_length=32, blank=True)
  original_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
  original_currency = models.CharField(max_length=3, blank=True)
  reporting_amount = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
  reporting_currency = models.CharField(max_length=3, blank=True)
  provider = models.CharField(max_length=32, blank=True)
  metadata = models.JSONField(default=dict, blank=True)
  occurred_at = models.DateTimeField(db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'finance_ledger_entries'
    ordering = ['-occurred_at']

  def save(self, *args, **kwargs):
    if self.pk:
      raise ValueError('Finance ledger entries are immutable; append a reversal or adjustment instead.')
    return super().save(*args, **kwargs)


class PlatformExpense(models.Model):
  CATEGORY_CHOICES = [
    ('INFRASTRUCTURE', 'Infrastructure'), ('SOFTWARE', 'Software'),
    ('MARKETING', 'Marketing'), ('PAYROLL', 'Payroll / contractors'),
    ('PROFESSIONAL_SERVICES', 'Professional services'), ('OTHER', 'Other'),
  ]
  expense_id = models.CharField(max_length=24, unique=True, default=expense_reference, editable=False, db_index=True)
  category = models.CharField(max_length=32, choices=CATEGORY_CHOICES, db_index=True)
  amount = models.DecimalField(max_digits=12, decimal_places=2)
  currency = models.CharField(max_length=3, db_index=True)
  vendor = models.CharField(max_length=160, blank=True)
  description = models.CharField(max_length=300)
  expense_date = models.DateField(db_index=True)
  external_reference = models.CharField(max_length=120, blank=True)
  recorded_by = models.ForeignKey(AdminStaffProfile, on_delete=models.PROTECT, related_name='recorded_expenses')
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'platform_expenses'
    ordering = ['-expense_date', '-created_at']


class ErrorLog(models.Model):
  """Automatic error/crash capture — distinct from SupportIncident (a human
  filing a ticket). Reported by the running web/mobile app, or caught
  server-side by ErrorCaptureMiddleware, and reviewed here in the Admin
  Portal grouped by platform and professional.
  """

  SOURCE_CLIENT_APP = 'client_app'
  SOURCE_BACKEND = 'backend'
  SOURCE_CHOICES = [(SOURCE_CLIENT_APP, 'Client app'), (SOURCE_BACKEND, 'Backend')]

  PLATFORM_WEB = 'web'
  PLATFORM_ANDROID = 'android'
  PLATFORM_IOS = 'ios'
  PLATFORM_UNKNOWN = 'unknown'
  PLATFORM_CHOICES = [
    (PLATFORM_WEB, 'Web'), (PLATFORM_ANDROID, 'Android'), (PLATFORM_IOS, 'iOS'), (PLATFORM_UNKNOWN, 'Unknown'),
  ]
  # The Admin Portal shows two sections — Web and Mobile — Mobile covers every
  # non-web platform so a future iOS build slots in without a UI change.
  MOBILE_PLATFORMS = (PLATFORM_ANDROID, PLATFORM_IOS)

  LEVEL_WARNING = 'warning'
  LEVEL_ERROR = 'error'
  LEVEL_FATAL = 'fatal'
  LEVEL_CHOICES = [(LEVEL_WARNING, 'Warning'), (LEVEL_ERROR, 'Error'), (LEVEL_FATAL, 'Fatal')]

  ROLE_PROFESSIONAL = 'professional'
  ROLE_CLIENT = 'client'
  ROLE_CHOICES = [(ROLE_PROFESSIONAL, 'Professional'), (ROLE_CLIENT, 'Client')]

  STATUS_NEW = 'new'
  STATUS_ACKNOWLEDGED = 'acknowledged'
  STATUS_RESOLVED = 'resolved'
  STATUS_IGNORED = 'ignored'
  STATUS_CHOICES = [
    (STATUS_NEW, 'New'), (STATUS_ACKNOWLEDGED, 'Acknowledged'),
    (STATUS_RESOLVED, 'Resolved'), (STATUS_IGNORED, 'Ignored'),
  ]
  OPEN_STATUSES = (STATUS_NEW, STATUS_ACKNOWLEDGED)

  error_id = models.CharField(max_length=24, unique=True, default=error_log_reference, editable=False, db_index=True)
  platform = models.CharField(max_length=12, choices=PLATFORM_CHOICES, default=PLATFORM_UNKNOWN, db_index=True)
  source = models.CharField(max_length=12, choices=SOURCE_CHOICES, default=SOURCE_CLIENT_APP, db_index=True)
  level = models.CharField(max_length=10, choices=LEVEL_CHOICES, default=LEVEL_ERROR, db_index=True)

  reporter_role = models.CharField(max_length=12, choices=ROLE_CHOICES, blank=True, db_index=True)
  reporter_professional = models.ForeignKey(
    settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='error_logs'
  )
  reporter_client = models.ForeignKey(
    'accounts.ClientAccess', on_delete=models.SET_NULL, null=True, blank=True, related_name='error_logs'
  )
  # Denormalized so the row still reads correctly if the account is later
  # deleted — same pattern as AdminAuditLog's *_snapshot fields. professional_username
  # is always populated (a client error carries their professional's username too),
  # which is what lets the admin list default-sort/group by professional.
  professional_username = models.CharField(max_length=150, blank=True, db_index=True)
  client_username = models.CharField(max_length=150, blank=True)
  client_reference = models.CharField(max_length=32, blank=True)

  message = models.CharField(max_length=500)
  stack_trace = models.TextField(blank=True)
  context = models.JSONField(default=dict, blank=True)
  app_version = models.CharField(max_length=40, blank=True)
  device_info = models.CharField(max_length=300, blank=True)
  request_path = models.CharField(max_length=300, blank=True)
  # Identical errors within the dedupe window bump this instead of adding a
  # new row, so the queue stays a list of distinct problems, not a flood.
  occurrence_count = models.PositiveIntegerField(default=1)

  status = models.CharField(max_length=14, choices=STATUS_CHOICES, default=STATUS_NEW, db_index=True)
  resolved_by = models.ForeignKey(
    settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='resolved_error_logs'
  )
  resolution_note = models.TextField(blank=True)
  resolved_at = models.DateTimeField(null=True, blank=True)

  first_seen_at = models.DateTimeField(auto_now_add=True, db_index=True)
  last_seen_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'error_logs'
    ordering = ['professional_username', '-last_seen_at']
    indexes = [
      models.Index(fields=['platform', 'status'], name='error_platform_status_idx'),
      models.Index(fields=['professional_username'], name='error_prof_username_idx'),
    ]

  def __str__(self) -> str:
    return f'{self.error_id} · {self.message[:60]}'


def record_error(
  *, platform, message, source=ErrorLog.SOURCE_CLIENT_APP, level=ErrorLog.LEVEL_ERROR,
  professional=None, client=None, stack_trace='', context=None, app_version='', device_info='', request_path='',
):
  """Single entry point for logging an error, used by both the client-report
  endpoint (accounts.views.ErrorReportView) and the backend crash middleware
  — so the dedupe rule lives in exactly one place.

  A client is always attached to its professional, so passing `client` alone is
  enough; `professional` is only needed for a professional-side error.
  """
  reporter_role = ''
  if client is not None:
    professional = client.professional
    reporter_role = ErrorLog.ROLE_CLIENT
  elif professional is not None:
    reporter_role = ErrorLog.ROLE_PROFESSIONAL

  def scrub(value):
    text = str(value or '')
    patterns = (
      (r'(?i)(authorization|token|password|secret|api[_-]?key|otp)(\s*[:=]\s*)([^\s,;&]+)', r'\1\2[REDACTED]'),
      (r'(?i)(bearer|token|clienttoken)\s+[A-Za-z0-9._~+/=-]+', r'\1 [REDACTED]'),
      (r'(?i)(id_token|access_token|refresh_token)=([^&\s]+)', r'\1=[REDACTED]'),
    )
    for pattern, replacement in patterns:
      text = re.sub(pattern, replacement, text)
    return text

  def scrub_context(value, depth=0):
    if depth > 4:
      return '[TRUNCATED]'
    if isinstance(value, dict):
      return {
        str(key)[:100]: (
          '[REDACTED]' if re.search(r'(?i)password|secret|token|authorization|otp|api[_-]?key', str(key))
          else scrub_context(item, depth + 1)
        )
        for key, item in list(value.items())[:50]
      }
    if isinstance(value, list):
      return [scrub_context(item, depth + 1) for item in value[:50]]
    return scrub(value)[:1000]

  message = scrub(message).strip()[:500] or 'Unknown error'
  stack_trace = scrub(stack_trace)[:20000]
  request_path = scrub(request_path).split('?', 1)[0][:300]
  context = scrub_context(context or {})
  professional_username = professional.username if professional else ''
  client_username = client.username if client else ''

  # Same problem reported again while still open just bumps the count, so
  # the queue stays a list of distinct problems rather than a flood.
  dedup_since = timezone.now() - timedelta(hours=24)
  existing = ErrorLog.objects.filter(
    platform=platform, message=message, professional_username=professional_username, client_username=client_username,
    status__in=ErrorLog.OPEN_STATUSES, last_seen_at__gte=dedup_since,
  ).first()
  if existing:
    existing.occurrence_count = F('occurrence_count') + 1
    existing.last_seen_at = timezone.now()
    existing.save(update_fields=['occurrence_count', 'last_seen_at'])
    return existing, True

  log = ErrorLog.objects.create(
    platform=platform,
    source=source,
    level=level,
    reporter_role=reporter_role,
    reporter_professional=professional,
    reporter_client=client,
    professional_username=professional_username,
    client_username=client_username,
    client_reference=client.reference_id if client else '',
    message=message,
    stack_trace=stack_trace,
    context=context,
    app_version=app_version,
    device_info=device_info,
    request_path=request_path,
  )

  # Only new problems are worth an email -- repeats above just bump the
  # counter and return early, so the operations mailbox gets one alert per
  # distinct problem rather than one per occurrence. Sending is backgrounded
  # and fully swallowed inside send_error_alert; it can never fail the caller.
  from .error_alerts import send_error_alert
  send_error_alert(log)

  return log, False
