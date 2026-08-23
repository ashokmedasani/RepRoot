from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from .data_usage import bust_professional_data_usage_cache, calculate_professional_data_usage
from .models import ClientAccess, ProfessionalResource
from .plan_lock_status import MODEL_MAP, compute_lock_status


# The five things the plan-limit lock system counts. 'lead_forms' and
# 'resources' use 'title' as their display field, the rest use 'name'.
RESOURCE_MODEL_KEYS = ('lead_forms', 'groups', 'templates', 'resources', 'categories')
_DISPLAY_FIELD = {
  'lead_forms': 'title',
  'groups': 'name',
  'templates': 'name',
  'resources': 'title',
  'categories': 'name',
}


def downgrade_assessment(user, target_tier_code='starter_free'):
  """What would happen if this professional's plan dropped to the given
  target tier (Free by default, or Pro when a Premium professional chooses
  to step down only partway) right now. Computed live against their real
  rows via a simulated compute_lock_status() call -- changes nothing in the
  database.

  Per the plan-limit lock system (see DOWNGRADE_LOCK_SYSTEM_PLAN.md),
  nothing here is ever deleted: anything over the target tier's limits
  would simply lock, in priority-rank order (oldest first, until
  reordered), and any client whose group locks loses portal access without
  losing their data -- they're reactivated automatically the moment the
  group unlocks.

  The only thing that can still genuinely block a self-serve downgrade is
  storage overage (the existing, separate byte-quota grace/freeze pipeline)
  -- that stays completely unmodified by this system.
  """
  target = settings.REPROOT_PLAN_TIERS.get(target_tier_code, settings.REPROOT_PLAN_TIERS['starter_free'])
  usage = calculate_professional_data_usage(user)
  current_plan = settings.REPROOT_PLAN_TIERS.get(usage['plan_code'], target)
  current_quota = max(1, int(current_plan['professional_storage_bytes']))
  target_quota = max(1, int(target['professional_storage_bytes']))
  estimated_bytes = usage['usage_percent'] * current_quota / 100
  target_storage_percent = round((estimated_bytes / target_quota) * 100, 2)

  simulated = compute_lock_status(user, plan_override=target)

  locks = {}
  for key in RESOURCE_MODEL_KEYS:
    locked_ids = simulated[key]['locked_ids']
    model = MODEL_MAP[key]
    display_field = _DISPLAY_FIELD[key]
    names = (
      list(
        model.objects.filter(id__in=locked_ids, professional=user)
        .values_list(display_field, flat=True)
      )
      if locked_ids
      else []
    )
    locks[key] = {
      'locked_count': len(locked_ids),
      # Capped -- this feeds warning copy, not a full export of every item.
      'locked_names': names[:20],
      'free_limit': int(target[key]),
    }

  # The category cascade rule, called out on its own per 3.8: how many of
  # the locked resources are locked purely because their category locked
  # (regardless of the resource's own individual rank), vs. locked on their
  # own rank within a category that's still active.
  locked_category_ids = set(simulated['categories']['locked_ids'])
  resources_locked_by_category_cascade = (
    ProfessionalResource.objects.filter(professional=user, category_id__in=locked_category_ids).count()
    if locked_category_ids
    else 0
  )

  # Clients who would lose portal access: anyone currently active in a group
  # that would lock. Their data is untouched -- only portal login pauses.
  locked_group_ids = simulated['groups']['locked_ids']
  affected_clients = (
    ClientAccess.objects.filter(professional=user, group_id__in=locked_group_ids, is_active=True)
    .select_related('group')
    if locked_group_ids
    else ClientAccess.objects.none()
  )
  clients_losing_access = [
    {'client_id': client.id, 'client_name': f'{client.first_name} {client.last_name}'.strip(), 'group_name': client.group.name}
    for client in affected_clients
  ]

  storage_eligible = target_storage_percent <= 100
  return {
    # Cancellation is never blocked by the count-based lock system -- only
    # genuine storage overage can still block self-serve cancellation.
    'eligible': storage_eligible,
    'target_tier_code': target_tier_code,
    'target_tier_name': target['name'],
    'storage': {
      'free_tier_percent': target_storage_percent,
      'exceeded_by_percent': round(max(0, target_storage_percent - 100), 2),
      'eligible': storage_eligible,
    },
    'locks': locks,
    'category_cascade_resource_count': resources_locked_by_category_cascade,
    'clients_losing_access': clients_losing_access,
    'clients_losing_access_count': len(clients_losing_access),
    'nothing_is_deleted': True,
    'support_email': settings.SUPPORT_EMAIL,
  }


def schedule_cancellation(profile, target_tier_code='starter_free'):
  now = timezone.now()
  effective_at = profile.plan_renews_at if profile.plan_renews_at and profile.plan_renews_at > now else now + timedelta(days=30)
  profile.cancellation_requested_at = now
  profile.cancellation_effective_at = effective_at
  # Blank means Free, same as before target-tier selection existed -- only
  # store a non-default value when the professional actually chose Pro.
  profile.cancellation_target_tier = '' if target_tier_code == 'starter_free' else target_tier_code
  profile.save(update_fields=['cancellation_requested_at', 'cancellation_effective_at', 'cancellation_target_tier'])
  return effective_at


def apply_due_cancellation(profile):
  """Runs once a scheduled cancellation's effective date has passed (see
  management/commands/process_subscription_cancellations.py). Only genuine
  storage overage blocks this -- the count-based lock system never does;
  anything over the target tier's limits just locks as part of
  downgrade_to_starter_free_voluntarily() / downgrade_to_pro_voluntarily(),
  same as it would from any other downgrade path. Nothing is ever deleted
  here."""
  # A scheduled cancellation is still a billing mutation. Keep the member's
  # current plan and cancellation date visible during a billing freeze, but do
  # not execute the downgrade until payments are deliberately enabled again.
  if not settings.REPROOT_PAYMENTS_ENABLED:
    return False

  if not profile.cancellation_effective_at or profile.cancellation_effective_at > timezone.now():
    return False

  target_tier_code = profile.cancellation_target_tier or 'starter_free'
  assessment = downgrade_assessment(profile.user, target_tier_code)
  if not assessment['storage']['eligible']:
    return False

  from .account_lifecycle import downgrade_to_pro_voluntarily, downgrade_to_starter_free_voluntarily
  if target_tier_code == 'pro':
    downgrade_to_pro_voluntarily(profile)
  else:
    downgrade_to_starter_free_voluntarily(profile)
  profile.cancellation_requested_at = None
  profile.cancellation_effective_at = None
  profile.cancellation_target_tier = ''
  profile.plan_renews_at = None
  profile.save(update_fields=[
    'cancellation_requested_at', 'cancellation_effective_at', 'cancellation_target_tier', 'plan_renews_at',
  ])
  bust_professional_data_usage_cache(profile.user_id)
  return True
