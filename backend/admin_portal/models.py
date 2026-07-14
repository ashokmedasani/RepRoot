import uuid

from django.conf import settings
from django.db import models


def staff_reference():
  return f'STF-{uuid.uuid4().hex[:10].upper()}'


def finance_reference():
  return f'FIN-{uuid.uuid4().hex[:12].upper()}'


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

  user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='admin_staff_profile')
  staff_id = models.CharField(max_length=24, unique=True, default=staff_reference, editable=False, db_index=True)
  role = models.ForeignKey(AdminRole, on_delete=models.PROTECT, related_name='staff_members')
  status = models.CharField(max_length=12, choices=STATUS_CHOICES, default=STATUS_ACTIVE, db_index=True)
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


class AdminAuditLog(models.Model):
  staff = models.ForeignKey(AdminStaffProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
  staff_reference_snapshot = models.CharField(max_length=120, blank=True)
  role_snapshot = models.CharField(max_length=80, blank=True)
  permission_used = models.CharField(max_length=100, blank=True, db_index=True)
  action = models.CharField(max_length=100, db_index=True)
  target_type = models.CharField(max_length=60, blank=True, db_index=True)
  target_id = models.CharField(max_length=80, blank=True)
  target_display = models.CharField(max_length=180, blank=True, db_index=True)
  trainer_username_snapshot = models.CharField(max_length=150, blank=True)
  trainer_reference_snapshot = models.CharField(max_length=24, blank=True)
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
  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='finance_entries')
  description = models.CharField(max_length=240, blank=True)
  external_reference = models.CharField(max_length=100, blank=True)
  occurred_at = models.DateTimeField(db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'finance_ledger_entries'
    ordering = ['-occurred_at']
