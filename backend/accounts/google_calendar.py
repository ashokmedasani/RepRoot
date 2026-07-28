"""Google Calendar/Meet integration for RepRoot-managed appointments.

RepRoot remains the source of truth. This module mirrors an internal meeting to
one configured Google Calendar and asks Google to create a unique Meet room.
Credentials are read only through Django settings and are never logged.
"""

from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4

import requests
from django.conf import settings


class GoogleCalendarError(RuntimeError):
  """A safe, non-secret error suitable for application logs and UI status."""


@dataclass(frozen=True)
class GoogleCalendarEvent:
  event_id: str
  meeting_url: str
  calendar_url: str


def is_google_calendar_configured() -> bool:
  return bool(
    getattr(settings, 'GOOGLE_CALENDAR_ENABLED', False)
    and getattr(settings, 'GOOGLE_CALENDAR_CLIENT_ID', '')
    and getattr(settings, 'GOOGLE_CALENDAR_CLIENT_SECRET', '')
    and getattr(settings, 'GOOGLE_CALENDAR_REFRESH_TOKEN', '')
    and getattr(settings, 'GOOGLE_CALENDAR_ID', '')
  )


def _access_token() -> str:
  if not is_google_calendar_configured():
    raise GoogleCalendarError('Google Calendar is not configured.')
  try:
    response = requests.post(
      'https://oauth2.googleapis.com/token',
      data={
        'client_id': settings.GOOGLE_CALENDAR_CLIENT_ID,
        'client_secret': settings.GOOGLE_CALENDAR_CLIENT_SECRET,
        'refresh_token': settings.GOOGLE_CALENDAR_REFRESH_TOKEN,
        'grant_type': 'refresh_token',
      },
      timeout=getattr(settings, 'GOOGLE_CALENDAR_TIMEOUT_SECONDS', 15),
    )
    response.raise_for_status()
    token = response.json().get('access_token', '')
  except (requests.RequestException, ValueError) as exc:
    raise GoogleCalendarError('Google Calendar authorization failed.') from exc
  if not token:
    raise GoogleCalendarError('Google Calendar did not return an access token.')
  return token


def _headers() -> dict[str, str]:
  return {'Authorization': f'Bearer {_access_token()}', 'Content-Type': 'application/json'}


def _event_endpoint(event_id: str = '') -> str:
  calendar_id = requests.utils.quote(settings.GOOGLE_CALENDAR_ID, safe='')
  base = f'https://www.googleapis.com/calendar/v3/calendars/{calendar_id}/events'
  return f'{base}/{requests.utils.quote(event_id, safe="")}' if event_id else base


def _date_time(value: datetime) -> dict[str, str]:
  return {'dateTime': value.isoformat()}


def create_google_meet_event(
  *,
  uid: str,
  title: str,
  description: str,
  start_at: datetime,
  end_at: datetime,
  attendee_emails: list[str],
) -> GoogleCalendarEvent:
  payload = {
    'summary': title,
    'description': description,
    'start': _date_time(start_at),
    'end': _date_time(end_at),
    'attendees': [{'email': email} for email in attendee_emails if email],
    'conferenceData': {
      'createRequest': {
        'requestId': f'reproot-{uid}-{uuid4().hex[:12]}',
        'conferenceSolutionKey': {'type': 'hangoutsMeet'},
      }
    },
    'extendedProperties': {'private': {'reproot_uid': uid}},
  }
  try:
    response = requests.post(
      _event_endpoint(),
      headers=_headers(),
      params={'conferenceDataVersion': 1, 'sendUpdates': 'all'},
      json=payload,
      timeout=getattr(settings, 'GOOGLE_CALENDAR_TIMEOUT_SECONDS', 15),
    )
    response.raise_for_status()
    data = response.json()
  except (requests.RequestException, ValueError) as exc:
    raise GoogleCalendarError('Google Calendar could not create the meeting.') from exc

  meeting_url = data.get('hangoutLink', '')
  if not meeting_url:
    for entry in data.get('conferenceData', {}).get('entryPoints', []):
      if entry.get('entryPointType') == 'video':
        meeting_url = entry.get('uri', '')
        break
  event_id = data.get('id', '')
  if not event_id or not meeting_url:
    raise GoogleCalendarError('Google Calendar created an incomplete meeting.')
  return GoogleCalendarEvent(
    event_id=event_id,
    meeting_url=meeting_url,
    calendar_url=data.get('htmlLink', ''),
  )


def update_google_event(event_id: str, *, start_at: datetime, end_at: datetime) -> None:
  try:
    response = requests.patch(
      _event_endpoint(event_id),
      headers=_headers(),
      params={'conferenceDataVersion': 1, 'sendUpdates': 'all'},
      json={'start': _date_time(start_at), 'end': _date_time(end_at)},
      timeout=getattr(settings, 'GOOGLE_CALENDAR_TIMEOUT_SECONDS', 15),
    )
    response.raise_for_status()
  except requests.RequestException as exc:
    raise GoogleCalendarError('Google Calendar could not reschedule the meeting.') from exc


def cancel_google_event(event_id: str) -> None:
  try:
    response = requests.delete(
      _event_endpoint(event_id),
      headers=_headers(),
      params={'sendUpdates': 'all'},
      timeout=getattr(settings, 'GOOGLE_CALENDAR_TIMEOUT_SECONDS', 15),
    )
    response.raise_for_status()
  except requests.RequestException as exc:
    raise GoogleCalendarError('Google Calendar could not cancel the meeting.') from exc
