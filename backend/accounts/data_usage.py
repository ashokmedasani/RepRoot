import json

from django.conf import settings
from django.core.cache import cache
from django.db.models import Count
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
  TrainerGroup,
  TrainerLeadForm,
  TrainerProfile,
  TrainerReference,
)
from .plan_limits import trainer_plan


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
  # object; one unavailable upload must not break navigation for the trainer.
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


def _client_usage(client) -> dict:
  lead_values = []
  if client.lead_submission_id:
    lead = LeadSubmission.objects.filter(pk=client.lead_submission_id).values().first()
    if lead:
      lead_values.append(lead)
  if client.registration_submission_id:
    submission = GroupRegistrationSubmission.objects.filter(pk=client.registration_submission_id).values().first()
    if submission:
      lead_values.append(submission)

  assignments = TemplateAssignment.objects.filter(client=client)
  assignment_links = TemplateAssignment.references.through.objects.filter(templateassignment__client=client)
  sections = {
    'profile_intake': _section_usage(values=[model_to_dict(client), *lead_values]),
    'templates': _section_usage(querysets=[assignments, assignment_links]),
    'tracking_history': _section_usage(querysets=[TrackingEntry.objects.filter(client=client)]),
    'progress': _section_usage(querysets=[ProgressEntry.objects.filter(client=client)]),
    'schedules': _section_usage(querysets=[ClientReminder.objects.filter(client=client)]),
    'messages': _section_usage(querysets=[ChatMessage.objects.filter(client=client)]),
    'account_activity': _section_usage(
      querysets=[
        ClientDetailChangeRequest.objects.filter(client=client),
        ClientAuthToken.objects.filter(client=client),
      ]
    ),
  }
  return {
    'id': client.pk,
    'reference_id': client.reference_id,
    'username': client.username,
    'name': f'{client.first_name} {client.last_name}'.strip(),
    'total_bytes': sum(section['total_bytes'] for section in sections.values()),
    'database_bytes': sum(section['database_bytes'] for section in sections.values()),
    'file_bytes': sum(section['file_bytes'] for section in sections.values()),
    'record_count': sum(section['record_count'] for section in sections.values()),
    'sections': sections,
  }


def calculate_trainer_data_usage(trainer) -> dict:
  """Estimate trainer-owned storage, broken down by product section and client."""
  cache_key = f'trainer-data-usage:v4:{trainer.pk}'
  cached = cache.get(cache_key)
  if cached is not None:
    return cached

  profile = TrainerProfile.objects.filter(user=trainer).first()
  trainer_data = model_to_dict(trainer)
  # Authentication timestamps change during normal navigation and do not
  # represent user-created content.
  trainer_data.pop('last_login', None)

  profile_values = [trainer_data]
  profile_files = []
  if profile:
    profile_values.append(model_to_dict(profile))
    profile_files = [
      profile.profile_photo,
      profile.certification_file,
      profile.transformation_photo,
      profile.training_photo,
    ]

  assignments = TemplateAssignment.objects.filter(client__trainer=trainer)
  assignment_links = TemplateAssignment.references.through.objects.filter(
    templateassignment__client__trainer=trainer
  )
  references = TrainerReference.objects.filter(trainer=trainer)
  sections = {
    'trainer_profile': _section_usage(values=profile_values, files=profile_files),
    'forms_groups': _section_usage(
      querysets=[
        TrainerLeadForm.objects.filter(trainer=trainer),
        TrainerGroup.objects.filter(trainer=trainer),
        ClientRegistrationForm.objects.filter(group__trainer=trainer),
        LeadSubmission.objects.filter(lead_form__trainer=trainer),
        GroupRegistrationSubmission.objects.filter(group__trainer=trainer),
      ]
    ),
    'clients': _section_usage(
      querysets=[
        ClientAccess.objects.filter(trainer=trainer),
        ClientDetailChangeRequest.objects.filter(client__trainer=trainer),
        ClientAuthToken.objects.filter(client__trainer=trainer),
      ]
    ),
    'schedules_progress': _section_usage(
      querysets=[
        ClientReminder.objects.filter(trainer=trainer),
        ProgressEntry.objects.filter(trainer=trainer),
      ]
    ),
    'references': _section_usage(
      querysets=[ReferenceCategory.objects.filter(trainer=trainer), references],
      files=[reference.file for reference in references.only('file')],
    ),
    'templates_tracking': _section_usage(
      querysets=[
        TrackingTemplate.objects.filter(trainer=trainer),
        assignments,
        assignment_links,
        TrackingEntry.objects.filter(client__trainer=trainer),
      ]
    ),
    'messages': _section_usage(querysets=[ChatMessage.objects.filter(trainer=trainer)]),
  }

  database_bytes = sum(section['database_bytes'] for section in sections.values())
  file_bytes = sum(section['file_bytes'] for section in sections.values())
  total_bytes = database_bytes + file_bytes
  plan = trainer_plan(trainer)
  quota_bytes = max(1, int(plan.get('trainer_storage_bytes') or 1))

  # The most active client is the most useful single-client storage example;
  # detailed histories naturally sort above profile-only clients.
  featured_client = (
    ClientAccess.objects.filter(trainer=trainer)
    .annotate(
      activity_count=(
        Count('tracking_entries', distinct=True)
        + Count('progress_entries', distinct=True)
        + Count('chat_messages', distinct=True)
      )
    )
    .order_by('-activity_count', 'pk')
    .first()
  )

  result = {
    'plan_code': plan['code'],
    'plan_name': plan['name'],
    'plan_limits': {key: value for key, value in plan.items() if key not in ('code', 'name')},
    'total_bytes': total_bytes,
    'database_bytes': database_bytes,
    'file_bytes': file_bytes,
    'quota_bytes': quota_bytes,
    'usage_percent': min(100, round((total_bytes / quota_bytes) * 100, 2)),
    'record_count': sum(section['record_count'] for section in sections.values()),
    'sections': sections,
    'featured_client': _client_usage(featured_client) if featured_client else None,
  }
  cache.set(cache_key, result, timeout=settings.COACHFLOW_DATA_USAGE_CACHE_SECONDS)
  return result
