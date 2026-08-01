"""
Local, self-contained slot computation — replaces the old Cal.com-backed
scheduling in cal_com.py / views_scheduling.py. Nothing here talks to any
third-party service: available slots are derived purely from a
professional's own ProfessionalAvailabilityWindow rows and
ProfessionalSchedulingSettings, minus whatever is already booked.

Kept deterministic on purpose (no "test mode" branching) so it behaves the
same in every environment.
"""

import secrets
import uuid
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from django.utils import timezone

from .models import (
  LeadMeetingRequest,
  ProfessionalAvailabilityWindow,
  ProfessionalDateOff,
  ProfessionalWeekdayOff,
  ProfessionalSchedulingSettings,
  ScheduledMeeting,
)


def get_or_create_scheduling_settings(professional) -> ProfessionalSchedulingSettings:
  settings_obj, _ = ProfessionalSchedulingSettings.objects.get_or_create(professional=professional)
  return settings_obj


def compute_available_slots(
  professional,
  start_date: date,
  end_date: date,
  duration_minutes: int,
  buffer_minutes: int | None = None,
  min_notice_hours: int = 0,
) -> dict:
  """Returns { "YYYY-MM-DD": [{"start": "<ISO8601 UTC>"}, ...] } for every
  date in [start_date, end_date] that has at least one open slot. Dates with
  no open slots are omitted entirely."""

  scheduling_settings = get_or_create_scheduling_settings(professional)
  slot_interval_minutes = scheduling_settings.slot_interval_minutes or 30
  if buffer_minutes is None:
    buffer_minutes = scheduling_settings.buffer_minutes
  try:
    tzinfo = ZoneInfo(scheduling_settings.timezone or 'UTC')
  except Exception:
    tzinfo = ZoneInfo('UTC')

  windows = list(
    ProfessionalAvailabilityWindow.objects.filter(professional=professional, is_active=True)
  )
  if not windows:
    return {}

  windows_by_weekday: dict[int, list[ProfessionalAvailabilityWindow]] = {}
  for window in windows:
    windows_by_weekday.setdefault(window.weekday, []).append(window)

  # Specific calendar dates the professional has blocked off (holidays,
  # vacation days, etc.) -- these skip slot generation entirely for that date
  # regardless of what the recurring weekly windows above say, and don't
  # touch the recurring schedule itself.
  off_dates = set(
    ProfessionalDateOff.objects.filter(
      professional=professional, date__gte=start_date, date__lte=end_date
    ).values_list('date', flat=True)
  )

  # Recurring weekly days off (e.g. "every Monday off") -- same skip
  # behaviour as off_dates above, but keyed by weekday number instead of a
  # specific date, so it applies every week until toggled off again.
  off_weekdays = set(
    ProfessionalWeekdayOff.objects.filter(professional=professional).values_list('weekday', flat=True)
  )

  now = timezone.now()
  minimum_start = now + timedelta(hours=min_notice_hours)
  buffer_delta = timedelta(minutes=buffer_minutes)
  duration_delta = timedelta(minutes=duration_minutes)

  # Existing commitments this professional already has, across the whole
  # range in one query rather than one query per day.
  range_start = datetime.combine(start_date, datetime.min.time(), tzinfo=tzinfo)
  range_end = datetime.combine(end_date + timedelta(days=1), datetime.min.time(), tzinfo=tzinfo)

  booked_meetings = list(
    ScheduledMeeting.objects.filter(
      professional=professional,
      status=ScheduledMeeting.STATUS_SCHEDULED,
      start_at__lt=range_end,
      end_at__gt=range_start,
    ).values_list('start_at', 'end_at')
  )
  pending_holds = list(
    LeadMeetingRequest.objects.filter(
      submission__lead_form__professional=professional,
      status=LeadMeetingRequest.STATUS_PENDING,
      expires_at__gt=now,
      requested_start__lt=range_end,
      requested_end__gt=range_start,
    ).values_list('requested_start', 'requested_end')
  )
  busy_blocks = booked_meetings + pending_holds

  def overlaps_busy(candidate_start: datetime, candidate_end: datetime) -> bool:
    return any(
      candidate_start < busy_end + buffer_delta and busy_start - buffer_delta < candidate_end
      for busy_start, busy_end in busy_blocks
    )

  result: dict[str, list[dict]] = {}
  current = start_date
  while current <= end_date:
    if current in off_dates or current.weekday() in off_weekdays:
      current += timedelta(days=1)
      continue
    day_windows = windows_by_weekday.get(current.weekday(), [])
    day_slots = []
    for window in day_windows:
      cursor = datetime.combine(current, window.start_time, tzinfo=tzinfo)
      window_end = datetime.combine(current, window.end_time, tzinfo=tzinfo)
      step = timedelta(minutes=slot_interval_minutes)
      while cursor + duration_delta <= window_end:
        candidate_end = cursor + duration_delta
        if cursor >= minimum_start and not overlaps_busy(cursor, candidate_end):
          day_slots.append({'start': cursor.astimezone(ZoneInfo('UTC')).strftime('%Y-%m-%dT%H:%M:%SZ')})
        cursor += step
    if day_slots:
      result[current.isoformat()] = day_slots
    current += timedelta(days=1)

  return result


def generate_meeting_room_url() -> str:
  """A free, no-signup Jitsi Meet room — works immediately for anyone with
  the link, no API key or account needed on either side."""
  return f'https://meet.jit.si/RepRoot-{secrets.token_urlsafe(12)}'


def generate_meeting_uid() -> str:
  """Stable calendar UID for a meeting/request across its lifetime, reschedules
  included — RFC 5545 keys an update off the same UID with a higher SEQUENCE,
  not a brand-new event."""
  return uuid.uuid4().hex
