import uuid
from django.utils import timezone

from .models import AdminAuditLog


def correlation_id():
  return f'ADM-{timezone.now():%Y%m%d}-{uuid.uuid4().hex[:8].upper()}'


def trainer_log_identity(trainer):
  profile = getattr(trainer, 'trainer_profile', None)
  reference = getattr(profile, 'internal_reference_code', '') or ''
  return f'{trainer.username} · {reference}'.strip(' ·')


def client_log_identity(client):
  return f'{client.trainer.username}:{client.reference_id}'


def record_admin_action(request, *, permission, action, target_type='', target_id='', target_display='', trainer=None, client=None, success=True, reason='', metadata=None):
  staff = getattr(request, 'admin_staff', None)
  if client is not None:
    trainer = client.trainer
    target_display = target_display or client_log_identity(client)
    target_id = target_id or client.reference_id
  elif trainer is not None:
    target_display = target_display or trainer_log_identity(trainer)
    target_id = target_id or getattr(trainer.trainer_profile, 'internal_reference_code', '')
  return AdminAuditLog.objects.create(
    staff=staff,
    staff_reference_snapshot=f'{staff.staff_id} · {staff.user.get_full_name() or staff.user.username}' if staff else '',
    role_snapshot=staff.role.name if staff else '',
    permission_used=permission,
    action=action,
    target_type=target_type,
    target_id=str(target_id),
    target_display=target_display,
    trainer_username_snapshot=trainer.username if trainer else '',
    trainer_reference_snapshot=getattr(getattr(trainer, 'trainer_profile', None), 'internal_reference_code', '') if trainer else '',
    client_reference_snapshot=client.reference_id if client else '',
    reason=reason,
    ip_address=request.META.get('REMOTE_ADDR') or None,
    user_agent=(request.META.get('HTTP_USER_AGENT') or '')[:300],
    correlation_id=correlation_id(),
    success=success,
    metadata=metadata or {},
  )
