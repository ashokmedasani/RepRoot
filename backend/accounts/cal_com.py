"""
Thin wrapper around the Cal.com API v2 — lets a professional book, reschedule,
and cancel real video meetings with a client from inside RepRoot, using the
professional's own Cal.com account as the backend.

Contract notes (pulled from cal.com/docs/api-reference/v2, since this is a
third-party API and guessing the shape wrong means silently broken bookings):
  - Auth: `Authorization: Bearer <api_key>` on every request.
  - Every endpoint requires a `cal-api-version` header, and the required
    value differs per endpoint family — event-types/slots pin to older
    dated versions than bookings. Getting this wrong doesn't 401; Cal.com
    silently falls back to an older API shape, so keep these exact.
  - All booking start times are UTC ISO-8601 strings, regardless of the
    attendee's timezone.

This module never logs or returns the raw API key — callers pass a
CalComConnection instance and get back plain dicts.
"""

import requests
from django.conf import settings

_EVENT_TYPES_VERSION = '2024-06-14'
_SLOTS_VERSION = '2024-09-04'
_BOOKINGS_VERSION = '2026-02-25'

REQUEST_TIMEOUT_SECONDS = 15


class CalComError(Exception):
  """Raised for any non-2xx response or network failure talking to Cal.com."""

  def __init__(self, message: str, status_code: int | None = None):
    super().__init__(message)
    self.status_code = status_code


def _headers(connection, api_version: str) -> dict:
  return {
    'Authorization': f'Bearer {connection.api_key}',
    'cal-api-version': api_version,
    'Content-Type': 'application/json',
  }


def _request(method: str, path: str, connection, api_version: str, **kwargs) -> dict:
  url = f'{settings.CAL_COM_API_BASE_URL}{path}'
  try:
    response = requests.request(
      method, url, headers=_headers(connection, api_version), timeout=REQUEST_TIMEOUT_SECONDS, **kwargs
    )
  except requests.RequestException as exc:
    raise CalComError(f'Could not reach Cal.com: {exc}') from exc

  if response.status_code >= 400:
    detail = response.text[:300]
    try:
      body = response.json()
      detail = body.get('message') or body.get('error', {}).get('message') or detail
    except ValueError:
      pass
    raise CalComError(f'Cal.com returned {response.status_code}: {detail}', status_code=response.status_code)

  try:
    return response.json()
  except ValueError as exc:
    raise CalComError('Cal.com returned a non-JSON response.') from exc


def list_event_types(connection) -> list[dict]:
  """Every event type (bookable meeting template) on the professional's Cal.com account."""
  params = {'username': connection.cal_username} if connection.cal_username else {}
  body = _request('GET', '/v2/event-types', connection, _EVENT_TYPES_VERSION, params=params)
  return body.get('data', [])


def get_available_slots(connection, event_type_id: int, start_date: str, end_date: str, timezone: str) -> dict:
  """Returns {date_str: [{'start': iso_datetime}, ...]} for the given range."""
  params = {
    'eventTypeId': event_type_id,
    'start': start_date,
    'end': end_date,
    'timeZone': timezone or 'UTC',
  }
  body = _request('GET', '/v2/slots', connection, _SLOTS_VERSION, params=params)
  return body.get('data', {})


def create_booking(connection, event_type_id: int, start_iso: str, attendee_name: str, attendee_email: str, attendee_timezone: str, guest_emails: list[str] | None = None) -> dict:
  payload = {
    'start': start_iso,
    'eventTypeId': event_type_id,
    'attendee': {
      'name': attendee_name,
      'email': attendee_email,
      'timeZone': attendee_timezone or 'UTC',
    },
  }
  if guest_emails:
    payload['guests'] = guest_emails
  body = _request('POST', '/v2/bookings', connection, _BOOKINGS_VERSION, json=payload)
  return body.get('data', {})


def reschedule_booking(connection, booking_uid: str, start_iso: str, reason: str = '') -> dict:
  payload = {'start': start_iso}
  if reason:
    payload['reschedulingReason'] = reason
  body = _request('POST', f'/v2/bookings/{booking_uid}/reschedule', connection, _BOOKINGS_VERSION, json=payload)
  return body.get('data', {})


def cancel_booking(connection, booking_uid: str, reason: str = '') -> dict:
  payload = {'cancellationReason': reason} if reason else {}
  body = _request('POST', f'/v2/bookings/{booking_uid}/cancel', connection, _BOOKINGS_VERSION, json=payload)
  return body.get('data', {})
