"""
Self-hosted calendar invites — replaces Cal.com's automatic invite emails now
that meetings are booked entirely inside RepRoot (see scheduling_engine.py).
Builds a real RFC 5545 (.ics) calendar attachment by hand — no new dependency
— and emails it to every attendee via Django's EmailMessage, so recipients
still get the usual "Add to calendar" / accept-decline experience in
Gmail/Outlook/Apple Calendar.

RFC 5545 basics this relies on:
  - Same UID + a higher SEQUENCE number = an update to an existing calendar
    entry, not a new one. The model's `cal_booking_uid` field IS the ICS UID
    (name kept for backward compatibility with rows created under Cal.com).
  - METHOD:REQUEST for create/update, METHOD:CANCEL (+ STATUS:CANCELLED) to
    remove it from the attendee's calendar.
  - Every DTSTART/DTEND/DTSTAMP here is emitted in UTC ("...Z" suffix) so no
    VTIMEZONE block is needed.
"""

import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from django.conf import settings
from django.core.mail import EmailMessage
from django.utils import timezone as dj_timezone

from .email_utils import run_in_background

_UTC = ZoneInfo('UTC')
logger = logging.getLogger(__name__)


def _escape_text(value: str) -> str:
  return (
    (value or '')
    .replace('\\', '\\\\')
    .replace(';', '\\;')
    .replace(',', '\\,')
    .replace('\n', '\\n')
  )


def _fold(line: str) -> str:
  """RFC 5545 requires lines over 75 octets to be "folded" with a leading
  space on each continuation line. Our lines are short in practice, but this
  keeps a long name/description from producing an invalid .ics file."""
  encoded = line.encode('utf-8')
  if len(encoded) <= 75:
    return line
  folded = line[:75]
  rest = line[75:]
  while rest:
    folded += '\r\n ' + rest[:74]
    rest = rest[74:]
  return folded


def _format_dt(value: datetime) -> str:
  if dj_timezone.is_naive(value):
    value = dj_timezone.make_aware(value, dj_timezone.get_default_timezone())
  return value.astimezone(_UTC).strftime('%Y%m%dT%H%M%SZ')


def build_ics_bytes(
  uid: str,
  sequence: int,
  start_at: datetime,
  end_at: datetime,
  summary: str,
  organizer_email: str,
  organizer_name: str,
  attendees: list[tuple[str, str]],
  location: str = '',
  description: str = '',
  method: str = 'REQUEST',
  cancelled: bool = False,
) -> bytes:
  """`attendees` is a list of (name, email) tuples."""

  now_stamp = _format_dt(dj_timezone.now())
  lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//RepRoot//Scheduling//EN',
    'CALSCALE:GREGORIAN',
    f'METHOD:{method}',
    'BEGIN:VEVENT',
    f'UID:{uid}',
    f'SEQUENCE:{sequence}',
    f'DTSTAMP:{now_stamp}',
    f'DTSTART:{_format_dt(start_at)}',
    f'DTEND:{_format_dt(end_at)}',
    f'SUMMARY:{_escape_text(summary)}',
    f'STATUS:{"CANCELLED" if cancelled else "CONFIRMED"}',
    f'ORGANIZER;CN={_escape_text(organizer_name)}:mailto:{organizer_email}',
  ]
  if location:
    lines.append(f'LOCATION:{_escape_text(location)}')
  if description:
    lines.append(f'DESCRIPTION:{_escape_text(description)}')
  for name, email in attendees:
    lines.append(
      f'ATTENDEE;CN={_escape_text(name)};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:{email}'
    )
  lines += ['END:VEVENT', 'END:VCALENDAR']

  folded = [_fold(line) for line in lines]
  return ('\r\n'.join(folded) + '\r\n').encode('utf-8')


def send_meeting_invite_email(
  *,
  uid: str,
  sequence: int,
  start_at: datetime,
  end_at: datetime,
  summary: str,
  organizer_email: str,
  organizer_name: str,
  attendees: list[tuple[str, str]],
  meeting_url: str = '',
  extra_body: str = '',
  cancelled: bool = False,
) -> None:
  """Emails every attendee an .ics invite (or cancellation).

  The .ics bytes are built synchronously (cheap, CPU-only, and any input
  error here is a real bug worth surfacing immediately). The actual network
  sends — one per attendee, which is what can hang if the SMTP host is slow
  or unreachable — run on a background thread so this function always
  returns immediately. The booking itself is already committed to the DB
  before this is called, so a slow or failed send should never hold up the
  request or the response the user sees; failures are logged instead."""

  method = 'CANCEL' if cancelled else 'REQUEST'
  description_lines = [extra_body] if extra_body else []
  if meeting_url and not cancelled:
    description_lines.append(f'Join: {meeting_url}')
  description = '\n'.join(description_lines)

  ics_bytes = build_ics_bytes(
    uid=uid,
    sequence=sequence,
    start_at=start_at,
    end_at=end_at,
    summary=summary,
    organizer_email=organizer_email,
    organizer_name=organizer_name,
    attendees=attendees,
    location=meeting_url,
    description=description,
    method=method,
    cancelled=cancelled,
  )

  run_in_background(
    _send_invite_emails,
    attendees=attendees, summary=summary, start_at=start_at, end_at=end_at,
    meeting_url=meeting_url, extra_body=extra_body, cancelled=cancelled, ics_bytes=ics_bytes,
  )


def _send_invite_emails(
  *, attendees, summary, start_at, end_at, meeting_url, extra_body, cancelled, ics_bytes,
) -> None:
  """Runs on a background thread (see send_meeting_invite_email above) —
  never called directly from a request. Best-effort per recipient: one bad
  address shouldn't block the others, and any failure is logged rather than
  raised, since there's no request left waiting on this by the time it runs."""

  method = 'CANCEL' if cancelled else 'REQUEST'
  filename = 'cancelled-meeting.ics' if cancelled else 'meeting.ics'
  content_type = f'text/calendar; method={method}; charset=UTF-8'

  subject = f'Cancelled: {summary}' if cancelled else f'Meeting confirmed: {summary}'
  body_parts = [
    'This meeting has been cancelled.' if cancelled else 'Your meeting is confirmed.',
    f'When: {start_at.strftime("%A, %B %d, %Y %I:%M %p")} - {end_at.strftime("%I:%M %p")}',
  ]
  if meeting_url and not cancelled:
    body_parts.append(f'Join link: {meeting_url}')
  if extra_body:
    body_parts.append(extra_body)
  body = '\n\n'.join(body_parts)

  errors = []
  for name, email in attendees:
    if not email:
      continue
    try:
      message = EmailMessage(
        subject=subject,
        body=body,
        from_email=getattr(settings, 'DEFAULT_FROM_EMAIL', None),
        to=[email],
      )
      message.attach(filename, ics_bytes, content_type)
      message.send(fail_silently=False)
    except Exception as exc:  # noqa: BLE001 - collect and continue, see docstring
      errors.append(f'{email}: {exc}')

  if errors:
    logger.warning('Could not send calendar invite to: %s', '; '.join(errors))
