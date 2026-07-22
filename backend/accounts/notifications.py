"""Shared notification creation and preference policy.

Delivery is deliberately queued in the database. SMTP and push workers can be
enabled later without changing any feature that emits a notification.
"""
from uuid import uuid4

from .models import ActivityNotification, NotificationPreference

CATEGORIES = (
  'chat', 'forms', 'meetings', 'clients', 'templates', 'progress',
  'reminders', 'references', 'payments', 'support', 'account',
  'storage', 'security', 'system',
)
MANDATORY_IN_APP = {'account', 'security', 'storage', 'system'}


def preferences_for(recipient_type, recipient):
  lookup = {'recipient_type': recipient_type}
  lookup['recipient_professional' if recipient_type == 'professional' else 'recipient_client'] = recipient
  existing = {row.category: row for row in NotificationPreference.objects.filter(**lookup)}
  return [existing.get(category) or NotificationPreference(category=category, **lookup) for category in CATEGORIES]


def notify(*, recipient_type, category, event_type, title, body='', recipient=None,
           action_url='', payload=None, priority='normal', requires_action=False,
           event_key=None, admin_scope=''):
  if category not in CATEGORIES:
    raise ValueError(f'Unsupported notification category: {category}')
  target = {}
  preference = None
  if recipient_type == 'professional':
    target['recipient_professional'] = recipient
  elif recipient_type == 'client':
    target['recipient_client'] = recipient
  elif recipient_type != 'admin':
    raise ValueError('Unsupported recipient type.')
  if recipient_type != 'admin':
    preference = NotificationPreference.objects.filter(
      recipient_type=recipient_type, category=category, **target
    ).first()
  email_enabled = bool(preference and preference.email_enabled and preference.digest_frequency == 'immediate')
  push_enabled = bool((preference is None or preference.push_enabled) and recipient_type != 'admin')
  notification, _ = ActivityNotification.objects.get_or_create(
    event_key=event_key or f'{recipient_type}:{event_type}:{uuid4().hex}',
    defaults={
      'recipient_type': recipient_type, 'admin_scope': admin_scope,
      'category': category, 'event_type': event_type, 'title': title[:200],
      'body': body, 'action_url': action_url, 'payload': payload or {},
      'priority': priority, 'requires_action': requires_action,
      'email_status': 'pending' if email_enabled else 'suppressed',
      'push_status': 'pending' if push_enabled else 'suppressed', **target,
    },
  )
  return notification


def notify_professional(professional, **kwargs):
  return notify(recipient_type='professional', recipient=professional, **kwargs)


def notify_client(client, **kwargs):
  return notify(recipient_type='client', recipient=client, **kwargs)


def notify_admin(*, scope='operations', **kwargs):
  return notify(recipient_type='admin', admin_scope=scope, **kwargs)
