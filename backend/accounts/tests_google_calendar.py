from datetime import datetime, timezone
from unittest.mock import Mock, patch

from django.test import SimpleTestCase, override_settings

from .google_calendar import create_google_meet_event, is_google_calendar_configured


GOOGLE_SETTINGS = {
  'GOOGLE_CALENDAR_ENABLED': True,
  'GOOGLE_CALENDAR_CLIENT_ID': 'placeholder-client-id',
  'GOOGLE_CALENDAR_CLIENT_SECRET': 'placeholder-client-secret',
  'GOOGLE_CALENDAR_REFRESH_TOKEN': 'placeholder-refresh-token',
  'GOOGLE_CALENDAR_ID': 'calendar@example.test',
  'GOOGLE_CALENDAR_TIMEOUT_SECONDS': 5,
}


class GoogleCalendarIntegrationTests(SimpleTestCase):

  @override_settings(**GOOGLE_SETTINGS)
  def test_configuration_requires_all_expected_values(self):
    self.assertTrue(is_google_calendar_configured())

  @override_settings(**GOOGLE_SETTINGS)
  @patch('accounts.google_calendar.requests.post')
  def test_creates_unique_google_meet_event(self, mock_post):
    token_response = Mock()
    token_response.raise_for_status.return_value = None
    token_response.json.return_value = {'access_token': 'placeholder-access-token'}
    event_response = Mock()
    event_response.raise_for_status.return_value = None
    event_response.json.return_value = {
      'id': 'google-event-id',
      'hangoutLink': 'https://meet.google.com/example-room',
      'htmlLink': 'https://calendar.google.com/calendar/event?eid=example',
    }
    mock_post.side_effect = [token_response, event_response]

    result = create_google_meet_event(
      uid='internal-meeting-uid',
      title='15-minute consultation',
      description='Test appointment',
      start_at=datetime(2026, 8, 1, 10, 0, tzinfo=timezone.utc),
      end_at=datetime(2026, 8, 1, 10, 15, tzinfo=timezone.utc),
      attendee_emails=['client@example.test'],
    )

    self.assertEqual(result.event_id, 'google-event-id')
    self.assertEqual(result.meeting_url, 'https://meet.google.com/example-room')
    event_call = mock_post.call_args_list[1]
    self.assertEqual(event_call.kwargs['params']['conferenceDataVersion'], 1)
    self.assertEqual(event_call.kwargs['params']['sendUpdates'], 'all')
    self.assertEqual(event_call.kwargs['json']['attendees'], [{'email': 'client@example.test'}])
    self.assertEqual(
      event_call.kwargs['json']['conferenceData']['createRequest']['conferenceSolutionKey']['type'],
      'hangoutsMeet',
    )
