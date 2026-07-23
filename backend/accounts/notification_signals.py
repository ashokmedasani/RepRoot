from django.db.models.signals import post_save
from django.dispatch import receiver

from .models import (
  ChatMessage, ClientDetailChangeRequest, ClientReminder, LeadMeetingRequest,
  GroupRegistrationSubmission, LeadSubmission, ProgressEntry, ScheduledMeeting, SupportIncident,
  SupportIncidentMessage, TemplateAssignment, TrackingEntry,
)
from .notifications import notify_admin, notify_client, notify_professional
from . import web_routes


@receiver(post_save, sender=LeadSubmission)
def lead_submitted(sender, instance, created, **kwargs):
  if created:
    professional = instance.lead_form.professional
    notify_professional(professional, category='forms', event_type='lead.submitted', event_key=f'lead:{instance.pk}:submitted',
      title='New lead form submission', body=f'{instance.first_name} {instance.last_name} submitted your form.',
      action_url=web_routes.professional_form_request(instance.pk), payload={'submission_id': instance.pk, 'reference_id': instance.reference_id}, requires_action=True)


@receiver(post_save, sender=GroupRegistrationSubmission)
def group_registration_submitted(sender, instance, created, **kwargs):
  if created:
    professional = instance.group.professional
    notify_professional(
      professional,
      category='forms',
      event_type='group_registration.submitted',
      event_key=f'group-registration:{instance.pk}:submitted',
      title='New group registration',
      body=f'{instance.first_name} {instance.last_name} submitted the {instance.group.name} registration form.',
      action_url=web_routes.PROFESSIONAL_FORMS_GROUPS,
      payload={'group_id': instance.group_id, 'registration_submission_id': instance.pk, 'reference_id': instance.reference_id},
      requires_action=True,
    )


@receiver(post_save, sender=LeadMeetingRequest)
def lead_meeting_requested(sender, instance, created, **kwargs):
  if created:
    professional = instance.submission.lead_form.professional
    notify_professional(professional, category='meetings', event_type='lead_meeting.requested', event_key=f'lead-meeting:{instance.pk}:requested',
      title='Introductory meeting requested', body=f'{instance.submission.first_name} requested an introductory meeting.',
      action_url=web_routes.PROFESSIONAL_FORMS_GROUPS, payload={'meeting_request_id': instance.pk, 'source': 'lead_form'}, requires_action=True, priority='high')


@receiver(post_save, sender=ClientDetailChangeRequest)
def client_change_requested(sender, instance, created, **kwargs):
  if created:
    label = 'account deletion' if instance.request_type == instance.TYPE_ACCOUNT_DELETION else 'profile change'
    notify_professional(instance.client.professional, category='clients', event_type=f'client.{instance.request_type}.requested', event_key=f'client-change:{instance.pk}:requested',
      title=f'Client {label} request', body=f'{instance.client.username} submitted a {label} request.', action_url=web_routes.professional_client(instance.client_id), payload={'client_id': instance.client_id, 'request_id': instance.pk}, requires_action=True, priority='high')
    if instance.request_type == instance.TYPE_ACCOUNT_DELETION:
      notify_admin(scope='lifecycle', category='account', event_type='client.deletion.requested', event_key=f'admin:client-change:{instance.pk}:requested', title='Client deletion request submitted', body='A trainer must review a client account deletion request.', payload={'client_id': instance.client_id, 'request_id': instance.pk}, requires_action=True)


@receiver(post_save, sender=TemplateAssignment)
def template_assigned(sender, instance, created, **kwargs):
  if created:
    notify_client(instance.client, category='templates', event_type='template.assigned', event_key=f'assignment:{instance.pk}:created', title='New template assigned', body=f'{instance.template.name} is ready for you.', action_url=web_routes.CLIENT_PROGRAMS, payload={'assignment_id': instance.pk, 'template_id': instance.template_id})


@receiver(post_save, sender=TrackingEntry)
def tracking_entry_created(sender, instance, created, **kwargs):
  if created and not instance.edited_by_professional:
    notify_professional(instance.client.professional, category='progress', event_type='tracking.entry.created', event_key=f'tracking:{instance.pk}:created', title='Client tracking update', body=f'{instance.client.username} added {instance.template_name}.', action_url=web_routes.professional_client(instance.client_id), payload={'client_id': instance.client_id, 'entry_id': instance.pk})


@receiver(post_save, sender=ProgressEntry)
def progress_created(sender, instance, created, **kwargs):
  if created:
    notify_client(instance.client, category='progress', event_type='progress.created', event_key=f'progress:{instance.pk}:created', title='Progress update added', body=instance.title, action_url=web_routes.CLIENT_PROGRESS, payload={'progress_id': instance.pk})


@receiver(post_save, sender=ClientReminder)
def reminder_created(sender, instance, created, **kwargs):
  if created:
    notify_client(instance.client, category='reminders', event_type='reminder.created', event_key=f'reminder:{instance.pk}:created', title='New reminder', body=instance.title, action_url=web_routes.CLIENT_MEETINGS, payload={'reminder_id': instance.pk})


@receiver(post_save, sender=ScheduledMeeting)
def meeting_created(sender, instance, created, **kwargs):
  if created:
    notify_client(instance.client, category='meetings', event_type='meeting.scheduled', event_key=f'meeting:{instance.pk}:scheduled', title='Meeting invitation', body=instance.title, action_url=web_routes.CLIENT_MEETINGS, payload={'meeting_id': instance.pk}, requires_action=True, priority='high')


@receiver(post_save, sender=ChatMessage)
def chat_created(sender, instance, created, **kwargs):
  if not created:
    return
  common = dict(category='chat', event_type='chat.message', event_key=f'chat:{instance.pk}', title='New message', body=(instance.text or 'Image attachment')[:240], payload={'message_id': instance.pk, 'client_id': instance.client_id})
  if instance.sender == ChatMessage.SENDER_CLIENT:
    notify_professional(instance.professional, action_url=web_routes.professional_client(instance.client_id), **common)
  else:
    notify_client(instance.client, action_url=web_routes.CLIENT_PROFESSIONAL, **common)


@receiver(post_save, sender=SupportIncident)
def support_created(sender, instance, created, **kwargs):
  if created:
    notify_admin(scope='support', category='support', event_type='support.incident.created', event_key=f'support:{instance.pk}:created', title=f'New support request: {instance.subject}', body=f'{instance.reporter_name} submitted {instance.incident_id}.', payload={'incident_id': instance.incident_id}, requires_action=True, priority='high')


@receiver(post_save, sender=SupportIncidentMessage)
def support_message_created(sender, instance, created, **kwargs):
  if not created:
    return
  incident = instance.incident
  if instance.author_type == SupportIncidentMessage.AUTHOR_SUPPORT:
    args = dict(category='support', event_type='support.reply', event_key=f'support-message:{instance.pk}', title=f'Support replied to {incident.incident_id}', body=instance.body[:240], action_url='/professional/account-settings', payload={'incident_id': incident.incident_id})
    if incident.reporter_role == SupportIncident.ROLE_PROFESSIONAL:
      notify_professional(incident.reporter_professional, **args)
    else:
      notify_client(incident.reporter_client, **args)
  elif instance.author_type == SupportIncidentMessage.AUTHOR_USER:
    notify_admin(scope='support', category='support', event_type='support.user_reply', event_key=f'admin:support-message:{instance.pk}', title=f'New reply on {incident.incident_id}', body=instance.body[:240], payload={'incident_id': incident.incident_id}, requires_action=True)
