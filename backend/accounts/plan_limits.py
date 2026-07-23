from django.conf import settings


def professional_plan_code(professional) -> str:
  default_plan = settings.REPROOT_DEFAULT_PLAN
  try:
    requested_plan = str(professional.professional_profile.plan_tier or default_plan).strip().lower()
  except (AttributeError, professional.__class__.professional_profile.RelatedObjectDoesNotExist):
    requested_plan = default_plan
  return requested_plan if requested_plan in settings.REPROOT_PLAN_TIERS else default_plan


def professional_plan(professional) -> dict:
  code = professional_plan_code(professional)
  plan = {'code': code, **settings.REPROOT_PLAN_TIERS[code]}
  # Keep compatibility with older deployments/tests that override the former
  # single-tier dictionary while they transition to REPROOT_PLAN_TIERS.
  plan.update(getattr(settings, 'REPROOT_PLAN_LIMITS', {}) or {})
  return plan


def plan_limit(professional, name: str):
  return professional_plan(professional).get(name)
