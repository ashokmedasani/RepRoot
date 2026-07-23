import json

from django.conf import settings
from django.core.cache import cache
from django.forms.models import model_to_dict

from .models import (
  ChatMessage,
  ClientAccess,
  ClientAuthToken,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  GroupRegistrationSubmission,
  LeadSubmission,
  ProgressEntry,
  ReferenceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalProfile,
  ProfessionalReference,
)
from .plan_limits import professional_plan


def _serialized_size(value) -> int:
  return len(json.dumps(value, default=str, separators=(',', ':'), ensure_ascii=False).encode('utf-8'))


def _queryset_size(queryset) -> int:
  return sum(_serialized_size(row) for row in queryset.values().iterator(chunk_size=500))


def _file_size(file_field) -> int:
  if not file_field:
    return 0

  try:
    return int(file_field.size)
  # Remote storage backends can raise provider-specific errors for a missing
  # object; one unavailable upload must not break navigation for the professional.
  except Exception:
    return 0


def _section_usage(*, values=(), querysets=(), files=()) -> dict[str, int]:
  database_bytes = sum(_serialized_size(value) for value in values)
  database_bytes += sum(_queryset_size(queryset) for queryset in querysets)
  file_bytes = sum(_file_size(file_field) for file_field in files)
  record_count = len(values) + sum(queryset.count() for queryset in querysets)
  return {
    'database_bytes': database_bytes,
    'file_bytes': file_bytes,
    'total_bytes': database_bytes + file_bytes,
    'record_count': record_count,
  }


# Professionals only ever see a percentage of their plan, never a raw byte
# count — these are the only two things allowed to translate storage bytes
# into something byte-free for the API response.
def _percent_of_quota(byte_count: int, quota_bytes: int) -> float:
  return round((byte_count / quota_bytes) * 100, 2)


def _sanitize_sections(sections: dict, quota_bytes: int) -> dict:
  return {
    name: {
      'percent_of_quota': min(100, _percent_of_quota(section['total_bytes'], quota_bytes)),
      'record_count': section['record_count'],
    }
    for name, section in sections.items()
  }


def _usage_status_label(usage_percent: float) -> str:
  """A human, non-numeric read on the percentage — the percent itself still
  ships in the response, this is just friendlier phrasing to hang it on."""
  if usage_percent >= settings.REPROOT_STORAGE_HARD_LIMIT_PERCENT:
    return 'uploads_paused'
  if usage_percent > 100:
    return 'over_capacity'
  if usage_percent >= settings.REPROOT_DATA_USAGE_DANGER_PERCENT:
    return 'almost_full'
  if usage_percent >= settings.REPROOT_DATA_USAGE_WARNING_PERCENT:
    return 'filling_up'
  if usage_percent >= 40:
    return 'comfortable'
  return 'plenty_of_room'


def _data_usage_cache_key(professional_pk) -> str:
  return f'professional-data-usage:v5:{professional_pk}'


def bust_professional_data_usage_cache(professional) -> None:
  """Call this after any write that changes a professional's counted records
  (clients, forms, templates, references, ...) so Settings > Data Usage
  reflects the change immediately instead of waiting out the cache TTL.
  Safe to call with either a User instance or a raw pk."""
  pk = getattr(professional, 'pk', professional)
  cache.delete(_data_usage_cache_key(pk))


def calculate_professional_data_usage(professional) -> dict:
  """Estimate professional-owned storage, broken down by product section and client."""
  cache_key = _data_usage_cache_key(professional.pk)
  cached = cache.get(cache_key)
  if cached is not None:
    return cached

  profile = ProfessionalProfile.objects.filter(user=professional).first()
  professional_data = model_to_dict(professional)
  # Authentication timestamps change during normal navigation and do not
  # represent user-created content.
  professional_data.pop('last_login', None)

  profile_values = [professional_data]
  profile_files = []
  if profile:
    profile_values.append(model_to_dict(profile))
    profile_files = [
      profile.profile_photo,
      profile.certification_file,
      profile.transformation_photo,
      profile.training_photo,
    ]

  assignments = TemplateAssignment.objects.filter(client__professional=professional)
  assignment_links = TemplateAssignment.references.through.objects.filter(
    templateassignment__client__professional=professional
  )
  references = ProfessionalReference.objects.filter(professional=professional)
  sections = {
    'professional_profile': _section_usage(values=profile_values, files=profile_files),
    'forms_groups': _section_usage(
      querysets=[
        ProfessionalLeadForm.objects.filter(professional=professional),
        ProfessionalGroup.objects.filter(professional=professional),
        ClientRegistrationForm.objects.filter(group__professional=professional),
        LeadSubmission.objects.filter(lead_form__professional=professional),
        GroupRegistrationSubmission.objects.filter(group__professional=professional),
      ]
    ),
    'clients': _section_usage(
      querysets=[
        ClientAccess.objects.filter(professional=professional),
        ClientDetailChangeRequest.objects.filter(client__professional=professional),
        ClientAuthToken.objects.filter(client__professional=professional),
      ]
    ),
    'schedules_progress': _section_usage(
      querysets=[
        ClientReminder.objects.filter(professional=professional),
        ProgressEntry.objects.filter(professional=professional),
      ]
    ),
    'references': _section_usage(
      querysets=[ReferenceCategory.objects.filter(professional=professional), references],
      files=[reference.file for reference in references.only('file')],
    ),
    'templates_tracking': _section_usage(
      querysets=[
        TrackingTemplate.objects.filter(professional=professional),
        assignments,
        assignment_links,
        TrackingEntry.objects.filter(client__professional=professional),
      ]
    ),
    'messages': _section_usage(
      querysets=[ChatMessage.objects.filter(professional=professional)],
      files=[
        message.image
        for message in ChatMessage.objects.filter(professional=professional).exclude(image='').only('image')
      ],
    ),
  }

  database_bytes = sum(section['database_bytes'] for section in sections.values())
  file_bytes = sum(section['file_bytes'] for section in sections.values())
  total_bytes = database_bytes + file_bytes
  plan = professional_plan(professional)
  quota_bytes = max(1, int(plan.get('professional_storage_bytes') or 1))

  # Uncapped: over-100 values are what drive is_over_quota / account-lock logic
  # below, so this must never be clamped. Anything shown to the professional
  # goes through _usage_status_label()/usage_display_percent instead, which is
  # visually capped at 100 — percentage only, never raw byte counts.
  usage_percent = round((total_bytes / quota_bytes) * 100, 2)
  usage_display_percent = min(settings.REPROOT_STORAGE_HARD_LIMIT_PERCENT, usage_percent)
  warning_threshold = settings.REPROOT_DATA_USAGE_WARNING_PERCENT
  danger_threshold = settings.REPROOT_DATA_USAGE_DANGER_PERCENT

  # Get professional profile for account lock status
  profile = ProfessionalProfile.objects.filter(user=professional).first()
  is_locked = profile.is_locked if profile else False
  lock_reason = profile.lock_reason if profile else None
  grace_period_ends_at = profile.grace_period_ends_at if profile else None
  locked_at = profile.locked_at if profile else None

  # 'professional_storage_bytes' is the one plan_limits entry that's a raw data
  # amount rather than a feature count (clients, templates, forms, ...) — those
  # stay numeric, storage stays percentage-only.
  plan_limits = {
    key: value for key, value in plan.items() if key not in ('code', 'name', 'professional_storage_bytes')
  }

  result = {
    'plan_code': plan['code'],
    'plan_name': plan['name'],
    'plan_limits': plan_limits,
    'usage_percent': usage_display_percent,
    'included_quota_bytes': quota_bytes,
    'hard_limit_percent': settings.REPROOT_STORAGE_HARD_LIMIT_PERCENT,
    'hard_limit_bytes': int(quota_bytes * settings.REPROOT_STORAGE_HARD_LIMIT_PERCENT / 100),
    'usage_label': _usage_status_label(usage_percent),
    'record_count': sum(section['record_count'] for section in sections.values()),
    'sections': _sanitize_sections(sections, quota_bytes),

    # NEW: Warning & account lifecycle fields
    'warning_threshold_percent': warning_threshold,
    'danger_threshold_percent': danger_threshold,
    'is_warning': usage_percent >= warning_threshold,
    'is_danger': usage_percent >= danger_threshold,
    'is_over_quota': usage_percent > 100,
    'is_storage_blocked': usage_percent >= settings.REPROOT_STORAGE_HARD_LIMIT_PERCENT,
    'is_locked': is_locked,
    'lock_reason': lock_reason,
    'grace_period_ends_at': grace_period_ends_at.isoformat() if grace_period_ends_at else None,
    'locked_at': locked_at.isoformat() if locked_at else None,
  }
  cache.set(cache_key, result, timeout=settings.REPROOT_DATA_USAGE_CACHE_SECONDS)
  return result
