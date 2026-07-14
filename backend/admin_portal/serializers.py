from django.contrib.auth import authenticate, get_user_model
from rest_framework import serializers

from .models import AdminAuditLog, AdminStaffProfile, FinanceLedgerEntry
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
  trainer_display = serializers.SerializerMethodField()

  class Meta:
    model = FinanceLedgerEntry
    fields = ['entry_id', 'entry_type', 'status', 'amount', 'currency', 'trainer_display', 'description', 'occurred_at']

  def get_trainer_display(self, obj):
    if not obj.trainer:
      return 'Platform'
    profile = getattr(obj.trainer, 'trainer_profile', None)
    return f'{obj.trainer.username} · {getattr(profile, "internal_reference_code", "")}'.strip(' ·')
