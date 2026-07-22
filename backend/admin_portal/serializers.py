from django.contrib.auth import authenticate, get_user_model
from rest_framework import serializers

from .models import AdminAuditLog, AdminStaffProfile, ErrorLog, FinanceLedgerEntry
from .permissions import permission_codes_for

User = get_user_model()


class AdminLoginSerializer(serializers.Serializer):
  identifier = serializers.CharField()
  password = serializers.CharField(write_only=True)

  def validate(self, attrs):
    identifier = attrs['identifier'].strip().lower()
    username = identifier
    if '@' in identifier:
      user = User.objects.filter(email__iexact=identifier).first()
      username = user.username if user else identifier
    user = authenticate(username=username, password=attrs['password'])
    if not user or not user.is_active:
      raise serializers.ValidationError('Invalid internal staff credentials.')
    staff = AdminStaffProfile.objects.select_related('role').filter(
      user=user, status=AdminStaffProfile.STATUS_ACTIVE
    ).first()
    if not staff:
      raise serializers.ValidationError('This account is not authorized for the Admin Portal.')
    attrs['user'] = user
    attrs['staff'] = staff
    return attrs


def staff_payload(staff):
  return {
    'staff_id': staff.staff_id,
    'username': staff.user.username,
    'full_name': staff.user.get_full_name() or staff.user.username,
    'email': staff.user.email,
    'role': staff.role.name,
    'role_slug': staff.role.slug,
    'department': staff.department,
    'department_label': staff.get_department_display(),
    'authority_level': staff.authority_level,
    'is_owner': staff.is_owner,
    'must_change_password': staff.must_change_password,
    'last_admin_login_at': staff.last_admin_login_at,
    'permissions': permission_codes_for(staff),
  }


class AdminAuditLogSerializer(serializers.ModelSerializer):
  class Meta:
    model = AdminAuditLog
    fields = [
      'id', 'correlation_id', 'staff_reference_snapshot', 'role_snapshot', 'permission_used',
      'action', 'target_type', 'target_display', 'success', 'created_at',
    ]


class FinanceLedgerEntrySerializer(serializers.ModelSerializer):
  professional_display = serializers.SerializerMethodField()

  class Meta:
    model = FinanceLedgerEntry
    fields = ['entry_id', 'entry_type', 'status', 'amount', 'currency', 'professional_display', 'description', 'occurred_at']

  def get_professional_display(self, obj):
    if not obj.professional:
      return 'Platform'
    profile = getattr(obj.professional, 'professional_profile', None)
    return f'{obj.professional.username} · {getattr(profile, "internal_reference_code", "")}'.strip(' ·')


class ErrorLogListSerializer(serializers.ModelSerializer):
  """Compact row for the queue view — stack_trace/context are only sent on
  the detail fetch so a 200-row list doesn't drag megabytes of traceback."""

  class Meta:
    model = ErrorLog
    fields = [
      'error_id', 'platform', 'source', 'level', 'reporter_role',
      'professional_username', 'client_username', 'message',
      'occurrence_count', 'status', 'first_seen_at', 'last_seen_at',
    ]


class ErrorLogSerializer(serializers.ModelSerializer):
  resolved_by_username = serializers.SerializerMethodField()

  class Meta:
    model = ErrorLog
    fields = [
      'error_id', 'platform', 'source', 'level', 'reporter_role',
      'professional_username', 'client_username', 'client_reference',
      'message', 'stack_trace', 'context', 'app_version', 'device_info', 'request_path',
      'occurrence_count', 'status', 'resolution_note', 'resolved_by_username', 'resolved_at',
      'first_seen_at', 'last_seen_at',
    ]

  def get_resolved_by_username(self, obj):
    return obj.resolved_by.username if obj.resolved_by else ''
