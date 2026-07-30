"""
Plan-limit lock system: computes which of a professional's groups, lead
forms, templates, resources, and categories are "active" vs "locked" given
their current plan's count limits and each item's priority_rank.

Design, agreed over a long planning discussion, in short:
- Ranked lowest-first, defaulting to creation order (oldest = highest
  priority) until a professional explicitly reorders. priority_rank is left
  NULL for anything never explicitly reordered; NULL sorts last within its
  model, tie-broken by created_at, so "default to creation order" falls out
  naturally without needing to stamp a rank at creation time.
- Categories are evaluated as their own tier FIRST. A resource's own rank
  only matters if its category survived; a resource inside a locked category
  is locked regardless of the resource's individual standing.
- Locked items are never deleted by this system. They're simply excluded
  from the active set -- callers (storage-quota calculation, client-facing
  views, professional-facing "locked" badges) are responsible for treating
  locked_ids accordingly.
- Computed live, not stored, and cached briefly for the same reason
  data_usage.py caches its (also-recomputed-live) totals: consistency over
  micro-optimization. Callers that change rank, delete an item, or move a
  professional's plan_tier must call bust_lock_status_cache().
"""

from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.db.models import F

from .models import (
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalResource,
  ResourceCategory,
  TrackingTemplate,
)
from .plan_limits import professional_plan


CACHE_TIMEOUT_SECONDS = 60
CACHE_VERSION = 'v1'

# Maps the dict keys used throughout this module (and by feature_access.py's
# per-item lock checks) to the model class that owns priority_rank for that
# counted thing.
MODEL_MAP = {
  'groups': ProfessionalGroup,
  'lead_forms': ProfessionalLeadForm,
  'templates': TrackingTemplate,
  'categories': ResourceCategory,
  'resources': ProfessionalResource,
}


def _cache_key(professional_pk) -> str:
  return f'professional-plan-lock-status:{CACHE_VERSION}:{professional_pk}'


def bust_lock_status_cache(professional) -> None:
  """Call after anything that changes rank, membership, or plan tier --
  creating/deleting a group/lead-form/template/resource/category, reordering,
  or a plan_tier change (upgrade/downgrade)."""
  pk = getattr(professional, 'pk', professional)
  cache.delete(_cache_key(pk))


def _rank_ordered(queryset):
  return list(queryset.order_by(F('priority_rank').asc(nulls_last=True), 'created_at', 'id'))


def _split_by_limit(ordered_items, limit: int):
  """First `limit` items (by rank order) are active, the rest are locked."""
  active = ordered_items[:limit] if limit > 0 else []
  locked = ordered_items[limit:] if limit > 0 else ordered_items
  return [item.id for item in active], [item.id for item in locked]


def compute_lock_status(professional, plan_override=None) -> dict:
  """Returns {'groups': {...}, 'lead_forms': {...}, 'templates': {...},
  'categories': {...}, 'resources': {...}}, each a dict of
  {'active_ids': [...], 'locked_ids': [...]}.

  `plan_override` lets a caller simulate a *different* tier's limits (e.g.
  subscription_cancellation.downgrade_assessment previewing what a downgrade
  to Starter Free would lock) against the professional's real current rows,
  without touching their actual plan_tier or priority_rank. Only the real,
  no-override computation is cached -- a simulated result must never be
  served back for the real question of "what's locked right now"."""
  cache_key = _cache_key(professional.pk)
  if plan_override is None:
    cached = cache.get(cache_key)
    if cached is not None:
      return cached

  plan = plan_override if plan_override is not None else professional_plan(professional)

  groups_ordered = _rank_ordered(ProfessionalGroup.objects.filter(professional=professional))
  groups_active, groups_locked = _split_by_limit(groups_ordered, int(plan['groups']))

  lead_forms_ordered = _rank_ordered(ProfessionalLeadForm.objects.filter(professional=professional))
  lead_forms_active, lead_forms_locked = _split_by_limit(lead_forms_ordered, int(plan['lead_forms']))

  templates_ordered = _rank_ordered(TrackingTemplate.objects.filter(professional=professional))
  templates_active, templates_locked = _split_by_limit(templates_ordered, int(plan['templates']))

  categories_ordered = _rank_ordered(ResourceCategory.objects.filter(professional=professional))
  categories_active, categories_locked = _split_by_limit(categories_ordered, int(plan['categories']))

  # Resources: only ranked against the resource-count limit within categories
  # that are themselves still active. Anything sitting in a locked category
  # is locked outright, regardless of its own rank.
  resources_in_active_categories = _rank_ordered(
    ProfessionalResource.objects.filter(professional=professional, category_id__in=categories_active)
  )
  resources_active, resources_locked_by_rank = _split_by_limit(resources_in_active_categories, int(plan['resources']))
  resources_locked_by_category = list(
    ProfessionalResource.objects.filter(professional=professional, category_id__in=categories_locked)
    .values_list('id', flat=True)
  )
  resources_locked = resources_locked_by_rank + list(resources_locked_by_category)

  result = {
    'groups': {'active_ids': groups_active, 'locked_ids': groups_locked},
    'lead_forms': {'active_ids': lead_forms_active, 'locked_ids': lead_forms_locked},
    'templates': {'active_ids': templates_active, 'locked_ids': templates_locked},
    'categories': {'active_ids': categories_active, 'locked_ids': categories_locked},
    'resources': {'active_ids': resources_active, 'locked_ids': resources_locked},
  }
  if plan_override is None:
    cache.set(cache_key, result, timeout=CACHE_TIMEOUT_SECONDS)
  return result


def is_group_locked(professional, group_id) -> bool:
  return group_id in compute_lock_status(professional)['groups']['locked_ids']


def is_lead_form_locked(professional, lead_form_id) -> bool:
  return lead_form_id in compute_lock_status(professional)['lead_forms']['locked_ids']


def is_template_locked(professional, template_id) -> bool:
  return template_id in compute_lock_status(professional)['templates']['locked_ids']


def is_category_locked(professional, category_id) -> bool:
  return category_id in compute_lock_status(professional)['categories']['locked_ids']


def is_resource_locked(professional, resource_id) -> bool:
  return resource_id in compute_lock_status(professional)['resources']['locked_ids']


class ReorderError(Exception):
  """Raised when a submitted reorder doesn't match the professional's
  current active set for that model."""
  pass


def reorder_active_items(professional, model_key: str, ordered_ids) -> None:
  """Persist a professional's chosen priority order for their currently
  ACTIVE items of one model (groups/lead_forms/templates/categories/
  resources). Per the agreed design, only active items can be reordered --
  locked items cannot be touched directly, and keep whatever relative order
  they already had the moment they locked, so "next in line" promotion (see
  _split_by_limit) stays predictable and fair rather than something a
  professional could game after the fact.

  `ordered_ids` must be exactly the professional's current active_ids for
  this model, just permuted -- no locked id may be smuggled in, and no
  active id may be dropped. Raises ReorderError otherwise.
  """
  model = MODEL_MAP.get(model_key)
  if model is None:
    raise ReorderError(f'Unknown model_key: {model_key}')

  ordered_ids = [int(item_id) for item_id in ordered_ids]
  status = compute_lock_status(professional)[model_key]
  current_active_ids = set(status['active_ids'])
  submitted_ids = set(ordered_ids)

  if len(ordered_ids) != len(submitted_ids):
    raise ReorderError('Duplicate ids in submitted order.')
  if submitted_ids != current_active_ids:
    raise ReorderError(
      'Submitted order must contain exactly the current active items -- no locked items, none missing.'
    )

  locked_ids_ordered = status['locked_ids']  # already in rank order from compute_lock_status

  with transaction.atomic():
    for index, item_id in enumerate(ordered_ids):
      model.objects.filter(id=item_id, professional=professional).update(priority_rank=index)
    # Locked items are pushed to ranks starting right after the active
    # window, in their existing relative order -- so they stay behind every
    # active item regardless of any stale rank value they held before, and
    # their own mutual order (used to decide who's "next" once a slot frees
    # up) is preserved untouched.
    offset = len(ordered_ids)
    for index, item_id in enumerate(locked_ids_ordered):
      model.objects.filter(id=item_id, professional=professional).update(priority_rank=offset + index)

  bust_lock_status_cache(professional)
