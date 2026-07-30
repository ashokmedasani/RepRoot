"""
Applies the consequence of a group locking/unlocking: suspending or
reactivating the clients inside it. Never deletes anything -- suspension via
ClientAccess.is_active, same mechanism a professional already uses to
manually suspend a client (see ClientAccessStatusView).

Call sync_group_lock_cascade(professional) after anything that could change
which groups are locked: a plan_tier change (upgrade/downgrade), a reorder,
or a group/category/etc. deletion that might promote a previously-locked
item into the active set.
"""

from .models import ClientAccess
from .plan_lock_status import compute_lock_status


def sync_group_lock_cascade(professional) -> dict:
  """Suspends clients in newly-locked groups, reactivates clients in groups
  that are unlocked again -- but only clients this system suspended in the
  first place (suspended_by_plan_lock=True). A professional's own manual
  suspension is never touched here.

  Returns {'suspended': [client_id, ...], 'reactivated': [client_id, ...]}.
  """
  status = compute_lock_status(professional)
  locked_group_ids = status['groups']['locked_ids']
  active_group_ids = status['groups']['active_ids']

  to_suspend = ClientAccess.objects.filter(
    professional=professional,
    group_id__in=locked_group_ids,
    is_active=True,
  )
  suspended_ids = list(to_suspend.values_list('id', flat=True))
  to_suspend.update(is_active=False, suspended_by_plan_lock=True)

  to_reactivate = ClientAccess.objects.filter(
    professional=professional,
    group_id__in=active_group_ids,
    suspended_by_plan_lock=True,
  )
  reactivated_ids = list(to_reactivate.values_list('id', flat=True))
  to_reactivate.update(is_active=True, suspended_by_plan_lock=False)

  return {'suspended': suspended_ids, 'reactivated': reactivated_ids}
