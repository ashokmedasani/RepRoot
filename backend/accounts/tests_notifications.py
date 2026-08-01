from django.contrib.auth import get_user_model
from django.test import TestCase

from .models import ActivityNotification, NotificationPreference
from .notifications import notify_professional
from . import web_routes


class SharedNotificationTests(TestCase):
  def setUp(self):
    self.user = get_user_model().objects.create_user(username='notify-pro', email='notify@example.test', password='Test!Pass27')

  def test_notification_is_mobile_ready_and_unread(self):
    item = notify_professional(self.user, category='forms', event_type='lead.submitted', event_key='test:lead:1', title='New lead', action_url='/professional/forms-groups', payload={'submission_id': 1})
    self.assertFalse(item.is_read)
    self.assertEqual(item.payload['submission_id'], 1)
    self.assertEqual(item.push_status, 'pending')

  def test_email_is_queued_only_when_opted_in_immediately(self):
    NotificationPreference.objects.create(recipient_type='professional', recipient_professional=self.user, category='payments', email_enabled=True, digest_frequency='immediate')
    item = notify_professional(self.user, category='payments', event_type='payment.received', event_key='test:payment:1', title='Payment received')
    self.assertEqual(item.email_status, 'pending')

  def test_event_key_deduplicates_retries(self):
    for _ in range(2):
      notify_professional(self.user, category='chat', event_type='chat.message', event_key='test:chat:1', title='New message')
    self.assertEqual(ActivityNotification.objects.filter(event_key='test:chat:1').count(), 1)

  def test_backend_notification_destinations_match_web_routes(self):
    self.assertEqual(web_routes.professional_client(42), '/professional/clients/42?section=overview')
    self.assertEqual(web_routes.professional_form_request(7), '/professional/forms-groups/requests/7')
    self.assertEqual(web_routes.CLIENT_PROGRAMS, '/client/profile?tab=templates')
    self.assertEqual(web_routes.CLIENT_PROGRESS, '/client/dashboard')
    self.assertEqual(web_routes.CLIENT_PROFESSIONAL, '/client/profile?tab=professional&professionalTab=profile')
    self.assertEqual(web_routes.CLIENT_MEETINGS, '/client/meetings')
