from django.db.models.signals import post_save
from django.dispatch import receiver

from accounts.models import (
  ActivityNotification, ChatMessage, ClientAccess, ClientReminder, LeadSubmission,
  ProfessionalGroup, ProfessionalLeadForm, ProfessionalReference, ScheduledMeeting,
  SupportIncident, TemplateAssignment, TrackingEntry, TrackingTemplate,
)

from .models import ErrorLog, OperationEvent


MODEL_EVENTS = {
  ProfessionalLeadForm: ('forms', 'lead_form_created'), LeadSubmission: ('submissions', 'lead_form_submitted'),
  ProfessionalGroup: ('groups', 'group_created'), ClientAccess: ('clients', 'client_added'),
  TrackingTemplate: ('templates', 'template_created'), TemplateAssignment: ('assignments', 'template_assigned'),
  TrackingEntry: ('entries', 'template_entry_submitted'), ProfessionalReference: ('references', 'reference_shared'),
  ScheduledMeeting: ('schedules', 'schedule_created'), ClientReminder: ('reminders', 'reminder_created'),
  ChatMessage: ('chat', 'chat_message_sent'), SupportIncident: ('support', 'support_ticket_created'),
  ActivityNotification: ('notifications', 'notification_created'), ErrorLog: ('errors', 'error_recorded'),
}


def context_for(instance):
  professional = getattr(instance, 'professional', None) or getattr(instance, 'reporter_professional', None) or getattr(instance, 'recipient_professional', None)
  client = getattr(instance, 'client', None) or getattr(instance, 'reporter_client', None) or getattr(instance, 'recipient_client', None)
  if not professional and client:
    professional = getattr(client, 'professional', None)
  try:
    profile = professional.professional_profile if professional else None
  except Exception:
    profile = None
  return {
    'actor_type': 'client' if client else ('professional' if professional else 'system'),
    'professional_reference': getattr(profile, 'internal_reference_code', '') if profile else '',
    'client_reference': getattr(client, 'reference_id', '') if client else '',
    'plan_tier': getattr(profile, 'plan_tier', '') if profile else '',
    'platform': getattr(instance, 'platform', '') or 'web',
  }


@receiver(post_save, sender=None, dispatch_uid='admin_portal_privacy_minimized_events')
def record_operation_event(sender, instance, created, **kwargs):
  mapping = MODEL_EVENTS.get(sender)
  if not created or not mapping:
    return
  module, event_type = mapping
  values = context_for(instance)
  if sender is ErrorLog:
    values['success'] = False
    values['platform'] = instance.platform
  OperationEvent.objects.create(module=module, event_type=event_type, **values)
