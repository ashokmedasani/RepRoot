from datetime import timedelta

from django.conf import settings
from django.db.models import ProtectedError
from django.utils import timezone

from .data_usage import bust_professional_data_usage_cache, calculate_professional_data_usage
from .models import (
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalReference,
  ReferenceCategory,
  TrackingTemplate,
)


RESOURCE_MODELS = {
  'lead_forms': ProfessionalLeadForm,
  'groups': ProfessionalGroup,
  'templates': TrackingTemplate,
  'references': ProfessionalReference,
  'categories': ReferenceCategory,
}


def downgrade_assessment(user):
  free = settings.REPROOT_PLAN_TIERS['starter_free']
  usage = calculate_professional_data_usage(user)
  current_plan = settings.REPROOT_PLAN_TIERS.get(usage['plan_code'], free)
  current_quota = max(1, int(current_plan['professional_storage_bytes']))
  free_quota = max(1, int(free['professional_storage_bytes']))
  estimated_bytes = usage['usage_percent'] * current_quota / 100
  free_storage_percent = round((estimated_bytes / free_quota) * 100, 2)

  resources = {}
  for key in RESOURCE_MODELS:
    used = int(usage['resource_usage'][key]['used'])
    limit = int(free[key])
    resources[key] = {
      'used': used,
      'free_limit': limit,
      'exceeded_by': max(0, used - limit),
      'eligible': used <= limit,
    }

  storage_eligible = free_storage_percent <= 100
  return {
    'eligible': storage_eligible and all(item['eligible'] for item in resources.values()),
    'storage': {
      'free_tier_percent': free_storage_percent,
      'exceeded_by_percent': round(max(0, free_storage_percent - 100), 2),
      'eligible': storage_eligible,
    },
    'resources': resources,
    'clients_preserved': True,
    'support_email': settings.SUPPORT_EMAIL,
  }


def schedule_cancellation(profile, *, force_cleanup=False):
  now = timezone.now()
  effective_at = profile.plan_renews_at if profile.plan_renews_at and profile.plan_renews_at > now else now + timedelta(days=30)
  profile.cancellation_requested_at = now
  profile.cancellation_effective_at = effective_at
  profile.cancellation_force_cleanup = force_cleanup
  profile.save(update_fields=[
    'cancellation_requested_at', 'cancellation_effective_at', 'cancellation_force_cleanup',
  ])
  return effective_at


def _delete_excess(queryset, excess):
  deleted = 0
  for item in queryset.order_by('-created_at')[:excess]:
    try:
      item.delete()
      deleted += 1
    except ProtectedError:
      continue
  return deleted


def cleanup_excess_non_client_resources(profile):
  user = profile.user
  free = settings.REPROOT_PLAN_TIERS['starter_free']
  totals = {
    'lead_forms': ProfessionalLeadForm.objects.filter(professional=user).count(),
    'groups': ProfessionalGroup.objects.filter(professional=user).count(),
    'templates': TrackingTemplate.objects.filter(professional=user).count(),
    'references': ProfessionalReference.objects.filter(professional=user).count(),
    'categories': ReferenceCategory.objects.filter(professional=user).count(),
  }
  return {
    'lead_forms': _delete_excess(
      ProfessionalLeadForm.objects.filter(professional=user),
      max(0, totals['lead_forms'] - free['lead_forms']),
    ),
    'groups': _delete_excess(
      ProfessionalGroup.objects.filter(professional=user, client_access_records__isnull=True).distinct(),
      max(0, totals['groups'] - free['groups']),
    ),
    'templates': _delete_excess(
      TrackingTemplate.objects.filter(professional=user, assignments__isnull=True).distinct(),
      max(0, totals['templates'] - free['templates']),
    ),
    'references': _delete_excess(
      ProfessionalReference.objects.filter(professional=user),
      max(0, totals['references'] - free['references']),
    ),
    'categories': _delete_excess(
      ReferenceCategory.objects.filter(professional=user, references__isnull=True).distinct(),
      max(0, totals['categories'] - free['categories']),
    ),
  }


def apply_due_cancellation(profile):
  if not profile.cancellation_effective_at or profile.cancellation_effective_at > timezone.now():
    return False

  if profile.cancellation_force_cleanup:
    cleanup_excess_non_client_resources(profile)

  assessment = downgrade_assessment(profile.user)
  if not assessment['storage']['eligible']:
    return False

  from .account_lifecycle import downgrade_to_starter_free_voluntarily
  downgrade_to_starter_free_voluntarily(profile)
  profile.cancellation_requested_at = None
  profile.cancellation_effective_at = None
  profile.cancellation_force_cleanup = False
  profile.plan_renews_at = None
  profile.save(update_fields=[
    'cancellation_requested_at', 'cancellation_effective_at',
    'cancellation_force_cleanup', 'plan_renews_at',
  ])
  bust_professional_data_usage_cache(profile.user_id)
  return True
