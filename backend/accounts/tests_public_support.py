from types import SimpleNamespace
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings
from rest_framework.test import APITestCase

from .models import SupportIncident
from .support_emails import send_professional_welcome_email


class PublicContactTests(APITestCase):
  @patch('accounts.public_contact.send_support_acknowledgement')
  @patch('accounts.public_contact.notify_support_team')
  def test_contact_submission_creates_rrns_incident_and_sends_both_emails(
    self, notify_support_team, send_support_acknowledgement
  ):
    response = self.client.post(
      '/api/accounts/public/contact/',
      {
        'name': 'Example Person',
        'email': 'Person@Example.test',
        'category': 'account_support',
        'subject': 'Account access question',
        'message': 'Please help me understand the account access process.',
        'website': '',
      },
      format='json',
    )

    self.assertEqual(response.status_code, 201)
    self.assertRegex(response.data['ticket_number'], r'^RRNS\d{6}[A-F0-9]{6}$')
    incident = SupportIncident.objects.get(incident_id=response.data['ticket_number'])
    self.assertEqual(incident.reporter_role, SupportIncident.ROLE_PUBLIC)
    self.assertEqual(incident.reporter_name, 'Example Person')
    self.assertEqual(incident.reporter_email, 'person@example.test')
    self.assertEqual(incident.category, SupportIncident.CATEGORY_ACCOUNT)
    self.assertEqual(incident.support_email_status, SupportIncident.EMAIL_PENDING)
    self.assertEqual(incident.acknowledgement_email_status, SupportIncident.EMAIL_PENDING)
    notify_support_team.assert_called_once_with(incident)
    send_support_acknowledgement.assert_called_once_with(incident)

  @patch('accounts.public_contact.send_support_acknowledgement')
  @patch('accounts.public_contact.notify_support_team')
  def test_honeypot_submission_is_accepted_without_creating_or_emailing(
    self, notify_support_team, send_support_acknowledgement
  ):
    response = self.client.post(
      '/api/accounts/public/contact/',
      {
        'name': 'Automated Sender',
        'email': 'bot@example.test',
        'category': 'general',
        'message': 'Automated submission',
        'website': 'https://spam.example.test',
      },
      format='json',
    )

    self.assertEqual(response.status_code, 202)
    self.assertFalse(SupportIncident.objects.exists())
    notify_support_team.assert_not_called()
    send_support_acknowledgement.assert_not_called()


@override_settings(
  DEFAULT_FROM_EMAIL='RepRoot <no-reply@example.test>',
  SUPPORT_EMAIL='support@example.test',
)
class ProfessionalWelcomeEmailTests(SimpleTestCase):
  @patch('accounts.support_emails.send_mail_background')
  def test_welcome_email_uses_configured_sender_and_support_address(self, send_mail_background):
    user = SimpleNamespace(
      email='professional@example.test',
      username='example-professional',
      get_full_name=lambda: 'Example Professional',
    )

    send_professional_welcome_email(user)

    send_mail_background.assert_called_once()
    payload = send_mail_background.call_args.kwargs
    self.assertEqual(payload['subject'], 'Welcome to RepRoot')
    self.assertEqual(payload['from_email'], 'RepRoot <no-reply@example.test>')
    self.assertEqual(payload['recipient_list'], ['professional@example.test'])
    self.assertEqual(payload['reply_to'], ['support@example.test'])
    self.assertIn('support@example.test', payload['message'])
    self.assertIn('support@example.test', payload['html_message'])
