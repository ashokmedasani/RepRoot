"""Immutable audit trail for Client Payments actions.

Mirrors admin_portal.audit.record_admin_action's single-entry-point shape but
is scoped to professional/client payment activity. Rows are insert-only —
PaymentAuditLog.save() raises on update attempts.
"""

from .models import PaymentAuditLog


def record_payment_action(
  *,
  action,
  professional=None,
  client=None,
  payment_request=None,
  payment_record=None,
  previous_values=None,
  new_values=None,
  changed_by='',
  reason='',
):
  return PaymentAuditLog.objects.create(
    action=action,
    professional=professional,
    client=client,
    payment_request=payment_request,
    payment_record=payment_record,
    previous_values=previous_values or {},
    new_values=new_values or {},
    changed_by=changed_by[:180],
    reason=reason,
  )
