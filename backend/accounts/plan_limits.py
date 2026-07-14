from django.conf import settings


def trainer_plan_code(trainer) -> str:
  default_plan = settings.COACHFLOW_DEFAULT_PLAN
  try:
    requested_plan = str(trainer.trainer_profile.plan_tier or default_plan).strip().lower()
  except (AttributeError, trainer.__class__.trainer_profile.RelatedObjectDoesNotExist):
    requested_plan = default_plan
  return requested_plan if requested_plan in settings.COACHFLOW_PLAN_TIERS else default_plan


def trainer_plan(trainer) -> dict:
  code = trainer_plan_code(trainer)
  plan = {'code': code, **settings.COACHFLOW_PLAN_TIERS[code]}
  # Keep compatibility with older deployments/tests that override the former
  # single-tier dictionary while they transition to COACHFLOW_PLAN_TIERS.
  plan.update(getattr(settings, 'COACHFLOW_PLAN_LIMITS', {}) or {})
  return plan


def plan_limit(trainer, name: str):
  return trainer_plan(trainer).get(name)
