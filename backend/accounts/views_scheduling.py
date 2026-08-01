"""
Scheduling — real video meetings between a professional and their client(s),
booked entirely inside RepRoot: no third-party account or API key required
from any trainer. A free Jitsi Meet room is generated per meeting and a
calendar (.ics) invite is emailed to every attendee (see calendar_invites.py
and scheduling_engine.py for the mechanics).

ClientReminder (in views.py / forms_groups) stays the lightweight "call this
client back" follow-up with no video component; ScheduledMeeting is the
richer booking with a join link and calendar invite. Both show up together
on a client's Schedule tab in the frontend, but they're distinct models here.
"""

from datetime import date, timedelta
from uuid import UUID

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.http import HttpResponse
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .calendar_invites import build_ics_bytes, send_meeting_invite_email
from .email_utils import send_mail_background as send_mail
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient
from .access_permissions import ProfessionalAccessPermission
from .models import (
  ClientAccess,
  LeadMeetingRequest,
  LeadSubmission,
  ProfessionalAvailabilityWindow,
  ProfessionalDateOff,
  ProfessionalWeekdayOff,
  ProfessionalLeadForm,
  ScheduledMeeting,
  ScheduledMeetingGuest,
)
from .google_calendar import (
  GoogleCalendarError,
  cancel_google_event,
  create_google_meet_event,
  is_google_calendar_configured,
  update_google_event,
)
from .scheduling_engine import (
  compute_available_slots,
  generate_meeting_room_url,
  generate_meeting_uid,
  get_or_create_scheduling_settings,
)
from .notifications import notify_client, notify_professional
from . import web_routes
from .serializers import (
  LeadMeetingRequestSerializer,
  ProfessionalAvailabilityWindowSerializer,
  ProfessionalDateOffSerializer,
  ProfessionalWeekdayOffSerializer,
  ProfessionalLeadFormSerializer,
  ProfessionalSchedulingSettingsSerializer,
  ScheduledMeetingSerializer,
)


def _attendee_name(person) -> str:
  return f'{person.first_name} {person.last_name}'.strip() or person.username


def _meeting_attendees(client, guest_clients=()):
  return [(_attendee_name(client), client.email)] + [
    (_attendee_name(guest), guest.email) for guest in guest_clients
  ]


def _provision_video_meeting(*, uid, title, notes, start_at, end_at, attendee_emails):
  """Create a Google Meet event when configured, with an internal fallback."""
  if is_google_calendar_configured():
    try:
      event = create_google_meet_event(
        uid=uid,
        title=title,
        description=notes,
        start_at=start_at,
        end_at=end_at,
        attendee_emails=attendee_emails,
      )
      return {
        'meeting_url': event.meeting_url,
        'provider': 'google',
        'event_id': event.event_id,
        'calendar_url': event.calendar_url,
        'sync_status': 'synced',
      }
    except GoogleCalendarError:
      return {
        'meeting_url': generate_meeting_room_url(),
        'provider': 'google',
        'event_id': '',
        'calendar_url': '',
        'sync_status': 'failed',
      }
  return {
    'meeting_url': generate_meeting_room_url(),
    'provider': 'internal',
    'event_id': '',
    'calendar_url': '',
    'sync_status': 'internal',
  }


class ProfessionalLeadMeetingSettingsView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    forms = ProfessionalLeadForm.objects.filter(professional=request.user)
    form_id = request.query_params.get('form_id')
    lead_form = forms.filter(id=form_id).first() if form_id else forms.first()
    if lead_form is None:
      return Response({'message': 'Create the lead form first.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'lead_form': ProfessionalLeadFormSerializer(lead_form, context={'request': request}).data})

  def put(self, request):
    forms = ProfessionalLeadForm.objects.filter(professional=request.user)
    form_id = request.data.get('form_id')
    lead_form = forms.filter(id=form_id).first() if form_id else forms.first()
    if lead_form is None:
      return Response({'message': 'Create the lead form first.'}, status=status.HTTP_404_NOT_FOUND)

    enabled = bool(request.data.get('introductory_meeting_enabled', lead_form.introductory_meeting_enabled))
    if enabled and not ProfessionalAvailabilityWindow.objects.filter(professional=request.user, is_active=True).exists():
      return Response(
        {'message': 'Set your weekly availability before enabling public meeting requests.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    allowed = [
      'introductory_meeting_enabled', 'introductory_meeting_title', 'introductory_meeting_duration_minutes',
      'introductory_meeting_min_notice_hours', 'introductory_meeting_max_advance_days',
      'introductory_meeting_buffer_minutes',
    ]
    serializer = ProfessionalLeadFormSerializer(
      lead_form, data={key: request.data[key] for key in allowed if key in request.data},
      partial=True, context={'request': request},
    )
    serializer.is_valid(raise_exception=True)
    serializer.save(introductory_meeting_requires_approval=True)
    return Response({
      'lead_form': ProfessionalLeadFormSerializer(lead_form, context={'request': request}).data,
      'message': 'Introductory meeting settings saved.',
    })


def _public_submission(public_slug, token):
  try:
    token = UUID(str(token))
  except (TypeError, ValueError):
    return None
  return LeadSubmission.objects.filter(
    lead_form__public_slug=public_slug,
    lead_form__is_active=True,
    lead_form__introductory_meeting_enabled=True,
    booking_access_token=token,
    is_active=True,
  ).select_related('lead_form__professional').first()


class PublicLeadMeetingSlotsView(APIView):
  permission_classes = [permissions.AllowAny]

  def get(self, request, public_slug):
    submission = _public_submission(public_slug, request.query_params.get('token'))
    if submission is None:
      return Response({'message': 'This booking link is invalid or unavailable.'}, status=status.HTTP_404_NOT_FOUND)
    lead_form = submission.lead_form

    try:
      start_date = date.fromisoformat(request.query_params.get('start'))
      end_date = date.fromisoformat(request.query_params.get('end'))
    except (TypeError, ValueError):
      return Response({'message': 'start and end must be valid dates.'}, status=status.HTTP_400_BAD_REQUEST)
    today = timezone.localdate()
    latest = today + timedelta(days=lead_form.introductory_meeting_max_advance_days)
    if start_date < today or end_date < start_date or end_date > latest:
      return Response({'message': f'Choose dates between today and {latest.isoformat()}.'}, status=status.HTTP_400_BAD_REQUEST)

    slots = compute_available_slots(
      lead_form.professional,
      start_date,
      end_date,
      lead_form.introductory_meeting_duration_minutes,
      buffer_minutes=lead_form.introductory_meeting_buffer_minutes,
      min_notice_hours=lead_form.introductory_meeting_min_notice_hours,
    )
    scheduling_settings = get_or_create_scheduling_settings(lead_form.professional)
    return Response({'slots': slots, 'timezone': scheduling_settings.timezone})


class PublicLeadMeetingRequestView(APIView):
  permission_classes = [permissions.AllowAny]

  def post(self, request, public_slug):
    submission = _public_submission(public_slug, request.data.get('token'))
    if submission is None:
      return Response({'message': 'This booking link is invalid or unavailable.'}, status=status.HTTP_404_NOT_FOUND)
    lead_form = submission.lead_form
    start_at = parse_datetime(str(request.data.get('start', '')))
    if start_at is None:
      return Response({'message': 'Choose a valid available time.'}, status=status.HTTP_400_BAD_REQUEST)
    if start_at < timezone.now() + timedelta(hours=lead_form.introductory_meeting_min_notice_hours):
      return Response({'message': 'That time does not meet the minimum notice period.'}, status=status.HTTP_400_BAD_REQUEST)
    if start_at > timezone.now() + timedelta(days=lead_form.introductory_meeting_max_advance_days):
      return Response({'message': 'That time is too far in advance.'}, status=status.HTTP_400_BAD_REQUEST)
    if hasattr(submission, 'meeting_request'):
      return Response({'message': 'A meeting request already exists for this submission.'}, status=status.HTTP_400_BAD_REQUEST)

    duration = lead_form.introductory_meeting_duration_minutes
    day_slots = compute_available_slots(
      lead_form.professional,
      start_at.date(),
      start_at.date(),
      duration,
      buffer_minutes=lead_form.introductory_meeting_buffer_minutes,
      min_notice_hours=lead_form.introductory_meeting_min_notice_hours,
    )
    available_starts = {
      parse_datetime(entry.get('start', ''))
      for entries in day_slots.values()
      for entry in entries
    }
    if start_at not in available_starts:
      return Response({'message': 'That time is no longer available. Please choose another slot.'}, status=status.HTTP_409_CONFLICT)

    buffer_delta = timedelta(minutes=lead_form.introductory_meeting_buffer_minutes)
    end_at = start_at + timedelta(minutes=duration)
    if LeadMeetingRequest.objects.filter(
      submission__lead_form=lead_form,
      status=LeadMeetingRequest.STATUS_PENDING,
      expires_at__gt=timezone.now(),
      requested_start__lt=end_at + buffer_delta,
      requested_end__gt=start_at - buffer_delta,
    ).exists():
      return Response({'message': 'That time is being held for another request. Please choose another slot.'}, status=status.HTTP_409_CONFLICT)

    meeting_request = LeadMeetingRequest.objects.create(
      submission=submission,
      requested_start=start_at,
      requested_end=end_at,
      contact_email=submission.email,
      contact_mobile=str(request.data.get('contact_mobile', '')).strip(),
      expires_at=timezone.now() + timedelta(hours=24),
    )
    try:
      send_meeting_invite_email(
        uid=f'lead-request-{meeting_request.id}',
        sequence=0,
        start_at=start_at,
        end_at=end_at,
        summary=f'Introductory meeting request — {submission.first_name} {submission.last_name}'.strip(),
        organizer_email=lead_form.professional.email,
        organizer_name=lead_form.professional.get_full_name() or lead_form.professional.username,
        attendees=[(lead_form.professional.get_full_name() or lead_form.professional.username, lead_form.professional.email)],
        extra_body=(
          f'{submission.first_name} {submission.last_name} requested {start_at.isoformat()} '
          f'for form {submission.reference_id}. Sign in to RepRoot Studio to accept or decline it.'
        ),
      )
    except Exception:
      pass  # Notification best-effort; the request itself is already saved and visible in Studio.

    return Response(
      {'request': LeadMeetingRequestSerializer(meeting_request).data, 'message': 'Your preferred time was sent to the professional for approval.'},
      status=status.HTTP_201_CREATED,
    )


class ProfessionalLeadMeetingRequestListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    LeadMeetingRequest.objects.filter(status=LeadMeetingRequest.STATUS_PENDING, expires_at__lte=timezone.now()).update(status=LeadMeetingRequest.STATUS_EXPIRED)
    requests = LeadMeetingRequest.objects.filter(submission__lead_form__professional=request.user).select_related('submission__lead_form')
    return Response({'requests': LeadMeetingRequestSerializer(requests, many=True).data})


class ProfessionalLeadMeetingRequestActionView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, request_id):
    meeting_request = LeadMeetingRequest.objects.filter(id=request_id, submission__lead_form__professional=request.user).select_related('submission__lead_form').first()
    if meeting_request is None:
      return Response({'message': 'Meeting request not found.'}, status=status.HTTP_404_NOT_FOUND)
    action = request.data.get('action')

    if action == 'send_followup':
      if meeting_request.status != LeadMeetingRequest.STATUS_ACCEPTED or meeting_request.requested_start >= timezone.now():
        return Response({'message': 'Follow-up email is available only for overdue accepted meetings.'}, status=status.HTTP_400_BAD_REQUEST)
      custom_message = str(request.data.get('trainer_note', '')).strip()
      if not custom_message:
        return Response({'message': 'Write a message before sending the follow-up.'}, status=status.HTTP_400_BAD_REQUEST)
      send_mail(
        subject=f'Follow-up about your meeting with {request.user.get_full_name() or request.user.username}',
        message=custom_message,
        from_email=settings.MEETING_FROM_EMAIL,
        recipient_list=[meeting_request.contact_email],
        fail_silently=False,
      )
      meeting_request.trainer_note = custom_message
      meeting_request.save(update_fields=['trainer_note', 'updated_at'])
      return Response({'request': LeadMeetingRequestSerializer(meeting_request).data, 'message': 'Follow-up email sent.'})

    if meeting_request.status != LeadMeetingRequest.STATUS_PENDING or meeting_request.expires_at <= timezone.now():
      return Response({'message': 'This meeting request is no longer pending.'}, status=status.HTTP_400_BAD_REQUEST)
    meeting_request.trainer_note = str(request.data.get('trainer_note', '')).strip()

    if action == 'decline':
      meeting_request.status = LeadMeetingRequest.STATUS_DECLINED
      meeting_request.reviewed_at = timezone.now()
      meeting_request.save(update_fields=['status', 'trainer_note', 'reviewed_at', 'updated_at'])
      send_mail(
        subject='Meeting request update',
        message='Your introductory meeting request was declined. The professional may contact you with another option.',
        from_email=settings.MEETING_FROM_EMAIL, recipient_list=[meeting_request.contact_email], fail_silently=False,
      )
      return Response({'request': LeadMeetingRequestSerializer(meeting_request).data, 'message': 'Meeting request declined.'})

    if action != 'accept':
      return Response({'message': 'action must be accept or decline.'}, status=status.HTTP_400_BAD_REQUEST)

    uid = meeting_request.cal_booking_uid or generate_meeting_uid()
    applicant_name = f'{meeting_request.submission.first_name} {meeting_request.submission.last_name}'.strip()
    meeting_title = f'Introductory meeting with {request.user.get_full_name() or request.user.username}'
    external = _provision_video_meeting(
      uid=uid,
      title=meeting_title,
      notes=meeting_request.trainer_note,
      start_at=meeting_request.requested_start,
      end_at=meeting_request.requested_end,
      attendee_emails=[meeting_request.contact_email],
    )

    meeting_request.status = LeadMeetingRequest.STATUS_ACCEPTED
    meeting_request.cal_booking_uid = uid
    meeting_request.meeting_url = external['meeting_url']
    meeting_request.external_calendar_provider = external['provider']
    meeting_request.external_calendar_event_id = external['event_id']
    meeting_request.external_calendar_url = external['calendar_url']
    meeting_request.external_calendar_sync_status = external['sync_status']
    meeting_request.reviewed_at = timezone.now()
    meeting_request.save(update_fields=[
      'status', 'trainer_note', 'cal_booking_uid', 'meeting_url',
      'external_calendar_provider', 'external_calendar_event_id', 'external_calendar_url',
      'external_calendar_sync_status', 'reviewed_at', 'updated_at',
    ])

    invite_note = ''
    try:
      if external['sync_status'] == 'synced':
        raise StopIteration
      send_meeting_invite_email(
        uid=uid,
        sequence=meeting_request.ics_sequence,
        start_at=meeting_request.requested_start,
        end_at=meeting_request.requested_end,
        summary=meeting_title,
        organizer_email=request.user.email,
        organizer_name=request.user.get_full_name() or request.user.username,
        attendees=[(applicant_name, meeting_request.contact_email)],
        meeting_url=meeting_request.meeting_url,
      )
    except StopIteration:
      pass
    except Exception:
      invite_note = ' The confirmation email could not be sent — please contact them directly.'

    if external['sync_status'] == 'failed':
      invite_note += ' Google Calendar was unavailable, so a fallback video room was created.'
    return Response({
      'request': LeadMeetingRequestSerializer(meeting_request).data,
      'message': f'Meeting accepted and a calendar invitation was created.{invite_note}',
    })


class ProfessionalSchedulingSettingsView(APIView):
  """A professional's own local scheduling configuration (timezone, default
  meeting length, buffer) plus their weekly availability windows — replaces
  the old Cal.com account-connection step entirely. Nothing here talks to a
  third party; slots are computed purely from this data
  (see scheduling_engine.compute_available_slots)."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    scheduling_settings = get_or_create_scheduling_settings(request.user)
    windows = ProfessionalAvailabilityWindow.objects.filter(professional=request.user).order_by('weekday', 'start_time')
    return Response({
      'settings': ProfessionalSchedulingSettingsSerializer(scheduling_settings).data,
      'availability_windows': ProfessionalAvailabilityWindowSerializer(windows, many=True).data,
    })

  def put(self, request):
    scheduling_settings = get_or_create_scheduling_settings(request.user)
    serializer = ProfessionalSchedulingSettingsSerializer(scheduling_settings, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({
      'settings': ProfessionalSchedulingSettingsSerializer(scheduling_settings).data,
      'message': 'Scheduling settings saved.',
    })


class ProfessionalAvailabilityWindowsView(APIView):
  """A professional's weekly recurring availability. Several rows can share
  the same weekday (e.g. Monday 10:00-12:00 AND Monday 14:00-16:00) — that's
  how multiple separate blocks on one day are represented, so creating a
  second window for a weekday that already has one is expected, not an
  error."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    windows = ProfessionalAvailabilityWindow.objects.filter(professional=request.user).order_by('weekday', 'start_time')
    return Response({'availability_windows': ProfessionalAvailabilityWindowSerializer(windows, many=True).data})

  def post(self, request):
    serializer = ProfessionalAvailabilityWindowSerializer(data=request.data, context={'professional': request.user})
    serializer.is_valid(raise_exception=True)
    window = serializer.save(professional=request.user)
    return Response(
      {'availability_window': ProfessionalAvailabilityWindowSerializer(window).data, 'message': 'Availability window added.'},
      status=status.HTTP_201_CREATED,
    )


class ProfessionalAvailabilityWindowDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def _get_window(self, request, window_id):
    return ProfessionalAvailabilityWindow.objects.filter(id=window_id, professional=request.user).first()

  def put(self, request, window_id):
    window = self._get_window(request, window_id)
    if window is None:
      return Response({'message': 'Availability window not found.'}, status=status.HTTP_404_NOT_FOUND)
    serializer = ProfessionalAvailabilityWindowSerializer(
      window, data=request.data, partial=True, context={'professional': request.user}
    )
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({'availability_window': ProfessionalAvailabilityWindowSerializer(window).data, 'message': 'Availability window updated.'})

  def delete(self, request, window_id):
    window = self._get_window(request, window_id)
    if window is None:
      return Response({'message': 'Availability window not found.'}, status=status.HTTP_404_NOT_FOUND)
    window.delete()
    return Response({'message': 'Availability window removed.'})


class ProfessionalAvailabilityWindowCopyView(APIView):
  """Copy every block from one weekday onto one or more other weekdays --
  backs "Copy Monday's schedule to selected days" / "Apply to all weekdays"
  in the Schedule availability UI. Existing blocks on a target day are left
  alone; only non-overlapping source blocks are added."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    from_weekday = request.data.get('from_weekday')
    to_weekdays = request.data.get('to_weekdays') or []

    if not isinstance(to_weekdays, list) or from_weekday is None:
      return Response({'message': 'from_weekday and to_weekdays are required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      from_weekday = int(from_weekday)
      to_weekdays = [int(day) for day in to_weekdays]
    except (TypeError, ValueError):
      return Response({'message': 'Weekdays must be integers 0-6.'}, status=status.HTTP_400_BAD_REQUEST)

    if not (0 <= from_weekday <= 6) or any(not (0 <= day <= 6) for day in to_weekdays):
      return Response({'message': 'Weekdays must be between 0 (Monday) and 6 (Sunday).'}, status=status.HTTP_400_BAD_REQUEST)

    source_windows = list(
      ProfessionalAvailabilityWindow.objects.filter(professional=request.user, weekday=from_weekday)
    )

    if not source_windows:
      return Response({'message': 'The selected day has no availability blocks to copy.'}, status=status.HTTP_400_BAD_REQUEST)

    created = []
    skipped = 0

    with transaction.atomic():
      for target_day in to_weekdays:
        if target_day == from_weekday:
          continue

        for source in source_windows:
          overlapping = ProfessionalAvailabilityWindow.objects.filter(
            professional=request.user,
            weekday=target_day,
            start_time__lt=source.end_time,
            end_time__gt=source.start_time,
          )
          if overlapping.exists():
            skipped += 1
            continue

          created.append(
            ProfessionalAvailabilityWindow.objects.create(
              professional=request.user,
              weekday=target_day,
              start_time=source.start_time,
              end_time=source.end_time,
            )
          )

    message = f'Copied {len(created)} block(s).'
    if skipped:
      message += f' Skipped {skipped} that would have overlapped an existing block.'

    return Response({
      'availability_windows': ProfessionalAvailabilityWindowSerializer(created, many=True).data,
      'message': message,
    })


class ProfessionalDateOffsView(APIView):
  """Specific calendar dates a professional has blocked off (holidays,
  vacation days, one-off personal days) — separate from and layered on top
  of the recurring weekly ProfessionalAvailabilityWindow rows, so the regular
  schedule never needs to be re-entered once the date has passed."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    # Deliberately not filtered to today-or-later: the calendar still needs
    # to gray out a date off after it's passed (it's a record of a day that
    # WAS off, not just an upcoming plan), so a past entry has to keep
    # showing up here rather than quietly disappearing once its date passes.
    date_offs = ProfessionalDateOff.objects.filter(professional=request.user).order_by('date')
    return Response({'date_offs': ProfessionalDateOffSerializer(date_offs, many=True).data})

  def post(self, request):
    serializer = ProfessionalDateOffSerializer(data=request.data, context={'professional': request.user})
    serializer.is_valid(raise_exception=True)
    date_off = serializer.save(professional=request.user)
    return Response(
      {'date_off': ProfessionalDateOffSerializer(date_off).data, 'message': f'{date_off.date} marked as a day off.'},
      status=status.HTTP_201_CREATED,
    )


class ProfessionalDateOffDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request, date_off_id):
    date_off = ProfessionalDateOff.objects.filter(id=date_off_id, professional=request.user).first()
    if date_off is None:
      return Response({'message': 'Day off not found.'}, status=status.HTTP_404_NOT_FOUND)
    date_off.delete()
    return Response({'message': 'Day off removed.'})


class ProfessionalWeekdayOffsView(APIView):
  """Recurring weekly days off (e.g. "every Monday off") — repeats
  indefinitely until removed, unlike the one-off ProfessionalDateOff rows
  above. Layered on top of the recurring ProfessionalAvailabilityWindow
  blocks rather than deleting them, so a professional can toggle a weekday
  off and back on later without re-entering their hours."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    weekday_offs = ProfessionalWeekdayOff.objects.filter(professional=request.user).order_by('weekday')
    return Response({'weekday_offs': ProfessionalWeekdayOffSerializer(weekday_offs, many=True).data})

  def post(self, request):
    serializer = ProfessionalWeekdayOffSerializer(data=request.data, context={'professional': request.user})
    serializer.is_valid(raise_exception=True)
    weekday_off = serializer.save(professional=request.user)
    return Response(
      {'weekday_off': ProfessionalWeekdayOffSerializer(weekday_off).data, 'message': 'That weekday is now a recurring day off.'},
      status=status.HTTP_201_CREATED,
    )


class ProfessionalWeekdayOffDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request, weekday_off_id):
    weekday_off = ProfessionalWeekdayOff.objects.filter(id=weekday_off_id, professional=request.user).first()
    if weekday_off is None:
      return Response({'message': 'Recurring day off not found.'}, status=status.HTTP_404_NOT_FOUND)
    weekday_off.delete()
    return Response({'message': 'Recurring day off removed.'})


class ProfessionalSchedulingSlotsView(APIView):
  """Available booking slots for the logged-in professional over a date
  range — computed locally from their weekly availability windows, minus
  whatever is already booked. What the "pick a slot" step in the UI reads
  from when a professional books a client directly."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    scheduling_settings = get_or_create_scheduling_settings(request.user)

    start_param = request.query_params.get('start')
    end_param = request.query_params.get('end')
    try:
      start_date = date.fromisoformat(start_param) if start_param else timezone.localdate()
      end_date = date.fromisoformat(end_param) if end_param else start_date
    except ValueError:
      return Response({'message': 'start and end must be valid dates (YYYY-MM-DD).'}, status=status.HTTP_400_BAD_REQUEST)

    duration_param = request.query_params.get('duration_minutes')
    try:
      duration_minutes = int(duration_param) if duration_param else scheduling_settings.default_duration_minutes
    except (TypeError, ValueError):
      return Response({'message': 'duration_minutes must be a whole number of minutes.'}, status=status.HTTP_400_BAD_REQUEST)

    slots = compute_available_slots(request.user, start_date, end_date, duration_minutes)
    return Response({'slots': slots, 'timezone': scheduling_settings.timezone})


class ScheduledMeetingListView(APIView):
  """All of a professional's meetings across every client — powers the
  account-wide Schedule section where clashes/overlaps are visible."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    meetings = ScheduledMeeting.objects.filter(professional=request.user).select_related('client')
    client_id = request.query_params.get('client_id')
    if client_id:
      meetings = meetings.filter(client_id=client_id)
    lead_meetings = LeadMeetingRequest.objects.filter(
      submission__lead_form__professional=request.user,
      status=LeadMeetingRequest.STATUS_ACCEPTED,
    ).select_related('submission__lead_form')
    return Response({
      'meetings': ScheduledMeetingSerializer(meetings, many=True).data,
      'lead_meetings': LeadMeetingRequestSerializer(lead_meetings, many=True).data,
    })

  def post(self, request):
    scheduling_settings = get_or_create_scheduling_settings(request.user)

    client = ClientAccess.objects.filter(id=request.data.get('client'), professional=request.user, is_active=True).first()
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    start_at = parse_datetime(str(request.data.get('start', '')))
    if start_at is None:
      return Response({'message': 'A valid start time is required.'}, status=status.HTTP_400_BAD_REQUEST)
    if timezone.is_naive(start_at):
      start_at = timezone.make_aware(start_at, timezone.get_default_timezone())

    try:
      duration_minutes = int(request.data.get('duration_minutes') or scheduling_settings.default_duration_minutes)
    except (TypeError, ValueError):
      return Response({'message': 'duration_minutes must be a whole number of minutes.'}, status=status.HTTP_400_BAD_REQUEST)
    if duration_minutes not in (15, 30):
      return Response({'message': 'Video meetings must be 15 or 30 minutes.'}, status=status.HTTP_400_BAD_REQUEST)
    end_at = start_at + timedelta(minutes=duration_minutes)

    if not client.email:
      return Response(
        {'message': f'{client.first_name or client.username} has no email on file — a calendar invite needs one to send.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    guest_client_ids = [gid for gid in (request.data.get('guest_client_ids') or []) if gid != client.id]
    guest_clients = list(ClientAccess.objects.filter(id__in=guest_client_ids, professional=request.user, is_active=True))
    missing_email = [c for c in guest_clients if not c.email]
    if missing_email:
      names = ', '.join(c.first_name or c.username for c in missing_email)
      return Response({'message': f'{names} has no email on file — a calendar invite needs one to send.'}, status=status.HTTP_400_BAD_REQUEST)

    uid = generate_meeting_uid()
    title = request.data.get('title') or 'Meeting'
    attendee_rows = _meeting_attendees(client, guest_clients)
    external = _provision_video_meeting(
      uid=uid,
      title=title,
      notes=request.data.get('notes', ''),
      start_at=start_at,
      end_at=end_at,
      attendee_emails=[email for _, email in attendee_rows],
    )

    meeting = ScheduledMeeting.objects.create(
      professional=request.user,
      client=client,
      title=title,
      notes=request.data.get('notes', ''),
      start_at=start_at,
      end_at=end_at,
      meeting_url=external['meeting_url'],
      cal_booking_uid=uid,
      external_calendar_provider=external['provider'],
      external_calendar_event_id=external['event_id'],
      external_calendar_url=external['calendar_url'],
      external_calendar_sync_status=external['sync_status'],
      status=ScheduledMeeting.STATUS_SCHEDULED,
    )
    for guest_client in guest_clients:
      ScheduledMeetingGuest.objects.create(meeting=meeting, client=guest_client)

    invite_note = ''
    try:
      if external['sync_status'] == 'synced':
        raise StopIteration
      send_meeting_invite_email(
        uid=uid,
        sequence=0,
        start_at=start_at,
        end_at=end_at,
        summary=title,
        organizer_email=request.user.email,
        organizer_name=request.user.get_full_name() or request.user.username,
        attendees=attendee_rows,
        meeting_url=meeting.meeting_url,
      )
    except StopIteration:
      pass
    except Exception:
      invite_note = ' Calendar invite emails could not be sent — please share the join link directly.'

    if external['sync_status'] == 'failed':
      invite_note += ' Google Calendar was unavailable, so a fallback video room was created.'
    all_names = ', '.join([client.first_name or client.username] + [c.first_name or c.username for c in guest_clients])
    return Response(
      {'meeting': ScheduledMeetingSerializer(meeting).data, 'message': f'Meeting scheduled with {all_names}.{invite_note}'},
      status=status.HTTP_201_CREATED,
    )


class ScheduledMeetingRescheduleView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, meeting_id):
    meeting = ScheduledMeeting.objects.filter(id=meeting_id, professional=request.user).select_related('client').prefetch_related('guests__client').first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
    if meeting.status != ScheduledMeeting.STATUS_SCHEDULED:
      return Response({'message': 'Only scheduled meetings can be rescheduled.'}, status=status.HTTP_400_BAD_REQUEST)

    start_iso = request.data.get('start')
    if not start_iso:
      return Response({'message': 'A new start time is required.'}, status=status.HTTP_400_BAD_REQUEST)
    start_at = parse_datetime(str(start_iso))
    if start_at is None:
      return Response({'message': 'A valid new start time is required.'}, status=status.HTTP_400_BAD_REQUEST)
    if timezone.is_naive(start_at):
      start_at = timezone.make_aware(start_at, timezone.get_default_timezone())

    duration = meeting.end_at - meeting.start_at
    meeting.start_at = start_at
    meeting.end_at = start_at + duration
    meeting.cal_booking_uid = meeting.cal_booking_uid or generate_meeting_uid()
    meeting.ics_sequence += 1
    if meeting.external_calendar_provider == 'google' and meeting.external_calendar_event_id:
      try:
        update_google_event(
          meeting.external_calendar_event_id,
          start_at=meeting.start_at,
          end_at=meeting.end_at,
        )
        meeting.external_calendar_sync_status = 'synced'
      except GoogleCalendarError:
        meeting.external_calendar_sync_status = 'failed'
    meeting.save(update_fields=[
      'start_at', 'end_at', 'cal_booking_uid', 'ics_sequence',
      'external_calendar_sync_status', 'updated_at',
    ])

    guest_clients = [guest.client for guest in meeting.guests.all()]
    invite_note = ''
    try:
      if meeting.external_calendar_sync_status == 'synced':
        raise StopIteration
      send_meeting_invite_email(
        uid=meeting.cal_booking_uid,
        sequence=meeting.ics_sequence,
        start_at=meeting.start_at,
        end_at=meeting.end_at,
        summary=meeting.title,
        organizer_email=request.user.email,
        organizer_name=request.user.get_full_name() or request.user.username,
        attendees=_meeting_attendees(meeting.client, guest_clients),
        meeting_url=meeting.meeting_url,
        extra_body=f"This meeting was rescheduled. {request.data.get('reason', '')}".strip(),
      )
    except StopIteration:
      pass
    except Exception:
      invite_note = ' Updated calendar invites could not be emailed — please notify attendees directly.'

    if meeting.external_calendar_sync_status == 'failed':
      invite_note += ' Google Calendar could not be updated; the RepRoot appointment was updated.'
    for attendee in [meeting.client, *guest_clients]:
      notify_client(
        attendee,
        category='meetings',
        event_type='meeting.rescheduled',
        title='Meeting rescheduled',
        body=f'{meeting.title} has a new date or time.',
        action_url=web_routes.client_meeting(meeting.id),
        payload={'meeting_id': meeting.id},
        priority='high',
      )
    return Response({'meeting': ScheduledMeetingSerializer(meeting).data, 'message': f'Meeting rescheduled.{invite_note}'})


class ScheduledMeetingCancelView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, meeting_id):
    meeting = ScheduledMeeting.objects.filter(id=meeting_id, professional=request.user).select_related('client').prefetch_related('guests__client').first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
    if meeting.status != ScheduledMeeting.STATUS_SCHEDULED:
      return Response({'message': 'This meeting is already cancelled or completed.'}, status=status.HTTP_400_BAD_REQUEST)

    reason = request.data.get('reason', '')
    meeting.status = ScheduledMeeting.STATUS_CANCELLED
    meeting.cancellation_reason = reason
    meeting.ics_sequence += 1
    if meeting.external_calendar_provider == 'google' and meeting.external_calendar_event_id:
      try:
        cancel_google_event(meeting.external_calendar_event_id)
        meeting.external_calendar_sync_status = 'cancelled'
      except GoogleCalendarError:
        meeting.external_calendar_sync_status = 'failed'
    meeting.save(update_fields=[
      'status', 'cancellation_reason', 'ics_sequence', 'external_calendar_sync_status', 'updated_at',
    ])

    if meeting.cal_booking_uid and meeting.external_calendar_sync_status != 'cancelled':
      guest_clients = [guest.client for guest in meeting.guests.all()]
      try:
        send_meeting_invite_email(
          uid=meeting.cal_booking_uid,
          sequence=meeting.ics_sequence,
          start_at=meeting.start_at,
          end_at=meeting.end_at,
          summary=meeting.title,
          organizer_email=request.user.email,
          organizer_name=request.user.get_full_name() or request.user.username,
          attendees=_meeting_attendees(meeting.client, guest_clients),
          extra_body=reason,
          cancelled=True,
        )
      except Exception:
        pass  # Best-effort; the cancellation itself is already saved.
    else:
      guest_clients = [guest.client for guest in meeting.guests.all()]

    for attendee in [meeting.client, *guest_clients]:
      notify_client(
        attendee,
        category='meetings',
        event_type='meeting.cancelled',
        title='Meeting cancelled',
        body=f'{meeting.title} was cancelled.' + (f' Reason: {reason}' if reason else ''),
        action_url=web_routes.client_meeting(meeting.id),
        payload={'meeting_id': meeting.id},
        priority='high',
      )

    return Response({'meeting': ScheduledMeetingSerializer(meeting).data, 'message': 'Meeting cancelled.'})


class ProfessionalMeetingRequestActionView(APIView):
  """Approve or decline a meeting time requested by an authenticated client."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, meeting_id):
    meeting = ScheduledMeeting.objects.filter(
      id=meeting_id,
      professional=request.user,
      requested_by=ScheduledMeeting.REQUESTED_BY_CLIENT,
      status=ScheduledMeeting.STATUS_PENDING_APPROVAL,
    ).select_related('client').first()
    if meeting is None:
      return Response({'message': 'Pending meeting request not found.'}, status=status.HTTP_404_NOT_FOUND)

    action = str(request.data.get('action', '')).strip().lower()
    if action not in ('accept', 'decline'):
      return Response({'message': 'action must be "accept" or "decline".'}, status=status.HTTP_400_BAD_REQUEST)

    meeting.professional_responded_at = timezone.now()
    if action == 'decline':
      meeting.status = ScheduledMeeting.STATUS_DECLINED
      meeting.cancellation_reason = str(request.data.get('reason', '')).strip()
      meeting.save(update_fields=['status', 'cancellation_reason', 'professional_responded_at', 'updated_at'])
      notify_client(
        meeting.client,
        category='meetings',
        event_type='meeting.request_declined',
        event_key=f'meeting:{meeting.pk}:request-declined',
        title='Meeting request declined',
        body=meeting.cancellation_reason or f'Your request for {meeting.title} was declined.',
        action_url=web_routes.client_meeting(meeting.pk),
        payload={'meeting_id': meeting.pk},
        priority='high',
      )
      return Response({
        'meeting': ScheduledMeetingSerializer(meeting).data,
        'message': 'Meeting request declined.',
      })

    if meeting.start_at <= timezone.now():
      return Response(
        {'message': 'This requested time has passed. Decline it and ask the client to choose another time.'},
        status=status.HTTP_409_CONFLICT,
      )
    if ScheduledMeeting.objects.filter(
      professional=request.user,
      status=ScheduledMeeting.STATUS_SCHEDULED,
      start_at__lt=meeting.end_at,
      end_at__gt=meeting.start_at,
    ).exclude(pk=meeting.pk).exists():
      return Response(
        {'message': 'This time now conflicts with another confirmed meeting.'},
        status=status.HTTP_409_CONFLICT,
      )

    uid = generate_meeting_uid()
    external = _provision_video_meeting(
      uid=uid,
      title=meeting.title,
      notes=meeting.notes,
      start_at=meeting.start_at,
      end_at=meeting.end_at,
      attendee_emails=[meeting.client.email],
    )
    meeting.status = ScheduledMeeting.STATUS_SCHEDULED
    meeting.meeting_url = external['meeting_url']
    meeting.cal_booking_uid = uid
    meeting.external_calendar_provider = external['provider']
    meeting.external_calendar_event_id = external['event_id']
    meeting.external_calendar_url = external['calendar_url']
    meeting.external_calendar_sync_status = external['sync_status']
    meeting.client_response_status = ScheduledMeeting.RESPONSE_ACCEPTED
    meeting.client_responded_at = meeting.created_at
    meeting.save(update_fields=[
      'status', 'meeting_url', 'cal_booking_uid', 'external_calendar_provider',
      'external_calendar_event_id', 'external_calendar_url', 'external_calendar_sync_status',
      'client_response_status', 'client_responded_at', 'professional_responded_at', 'updated_at',
    ])

    invite_note = ''
    if external['sync_status'] != 'synced':
      try:
        send_meeting_invite_email(
          uid=uid,
          sequence=0,
          start_at=meeting.start_at,
          end_at=meeting.end_at,
          summary=meeting.title,
          organizer_email=request.user.email,
          organizer_name=request.user.get_full_name() or request.user.username,
          attendees=_meeting_attendees(meeting.client),
          meeting_url=meeting.meeting_url,
        )
      except Exception:
        invite_note = ' Calendar invite email could not be sent; share the join link directly.'

    notify_client(
      meeting.client,
      category='meetings',
      event_type='meeting.request_accepted',
      event_key=f'meeting:{meeting.pk}:request-accepted',
      title='Meeting request confirmed',
      body=f'{meeting.title} is confirmed.',
      action_url=web_routes.client_meeting(meeting.pk),
      payload={'meeting_id': meeting.pk},
      requires_action=True,
      priority='high',
    )
    return Response({
      'meeting': ScheduledMeetingSerializer(meeting).data,
      'message': f'Meeting request accepted and confirmed.{invite_note}',
    })


class ClientSchedulingSlotsView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client = request.auth
    start_param = request.query_params.get('start')
    end_param = request.query_params.get('end')
    try:
      start_date = date.fromisoformat(start_param) if start_param else timezone.localdate()
      end_date = date.fromisoformat(end_param) if end_param else start_date + timedelta(days=6)
      duration_minutes = int(request.query_params.get('duration_minutes', 30))
    except (TypeError, ValueError):
      return Response({'message': 'Use valid dates and a whole-number duration.'}, status=status.HTTP_400_BAD_REQUEST)
    if duration_minutes not in (15, 30):
      return Response({'message': 'Video meetings must be 15 or 30 minutes.'}, status=status.HTTP_400_BAD_REQUEST)
    if end_date < start_date or (end_date - start_date).days > 31:
      return Response({'message': 'Choose a date range of 31 days or less.'}, status=status.HTTP_400_BAD_REQUEST)
    scheduling_settings = get_or_create_scheduling_settings(client.professional)
    availability_configured = ProfessionalAvailabilityWindow.objects.filter(
      professional=client.professional,
      is_active=True,
    ).exists()
    return Response({
      'slots': compute_available_slots(client.professional, start_date, end_date, duration_minutes),
      'timezone': scheduling_settings.timezone,
      'availability_configured': availability_configured,
    })


class ClientMeetingRequestView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def post(self, request):
    client = request.auth
    start_at = parse_datetime(str(request.data.get('start', '')))
    if start_at is None:
      return Response({'message': 'A valid start time is required.'}, status=status.HTTP_400_BAD_REQUEST)
    if timezone.is_naive(start_at):
      start_at = timezone.make_aware(start_at, timezone.get_default_timezone())
    try:
      duration_minutes = int(request.data.get('duration_minutes', 30))
    except (TypeError, ValueError):
      return Response({'message': 'duration_minutes must be a whole number.'}, status=status.HTTP_400_BAD_REQUEST)
    if duration_minutes not in (15, 30):
      return Response({'message': 'Video meetings must be 15 or 30 minutes.'}, status=status.HTTP_400_BAD_REQUEST)
    if start_at <= timezone.now():
      return Response({'message': 'Choose a future meeting time.'}, status=status.HTTP_400_BAD_REQUEST)
    if not client.email:
      return Response({'message': 'Add an email address before requesting a meeting.'}, status=status.HTTP_400_BAD_REQUEST)

    available = compute_available_slots(
      client.professional,
      timezone.localtime(start_at).date(),
      timezone.localtime(start_at).date(),
      duration_minutes,
    )
    available_starts = {
      parse_datetime(slot['start'])
      for slots_for_day in available.values()
      for slot in slots_for_day
    }
    if start_at not in available_starts:
      return Response({'message': 'That time is no longer available.'}, status=status.HTTP_409_CONFLICT)

    meeting = ScheduledMeeting.objects.create(
      professional=client.professional,
      client=client,
      title=str(request.data.get('title') or 'Client-requested meeting')[:180],
      notes=str(request.data.get('notes') or '')[:2000],
      start_at=start_at,
      end_at=start_at + timedelta(minutes=duration_minutes),
      status=ScheduledMeeting.STATUS_PENDING_APPROVAL,
      requested_by=ScheduledMeeting.REQUESTED_BY_CLIENT,
      client_response_status=ScheduledMeeting.RESPONSE_ACCEPTED,
      client_responded_at=timezone.now(),
    )
    return Response({
      'meeting': ScheduledMeetingSerializer(meeting, context={'client': client}).data,
      'message': 'Meeting request sent. It will stay pending until your professional accepts it.',
    }, status=status.HTTP_201_CREATED)


class ClientMeetingCalendarInviteView(APIView):
  """Return an RFC 5545 invite that a mobile device can open in any calendar."""

  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request, meeting_id):
    client = request.auth
    meeting = ScheduledMeeting.objects.filter(
      Q(client=client) | Q(guests__client=client),
      id=meeting_id,
    ).select_related('professional', 'client').prefetch_related('guests__client').distinct().first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)

    attendees = _meeting_attendees(meeting.client, [guest.client for guest in meeting.guests.all()])
    invite = build_ics_bytes(
      uid=meeting.cal_booking_uid or f'reproot-meeting-{meeting.id}',
      sequence=meeting.ics_sequence,
      start_at=meeting.start_at,
      end_at=meeting.end_at,
      summary=meeting.title,
      organizer_email=meeting.professional.email,
      organizer_name=meeting.professional.get_full_name() or meeting.professional.username,
      attendees=attendees,
      location=meeting.meeting_url,
      description=f'{meeting.notes}\nJoin: {meeting.meeting_url}'.strip(),
      method='CANCEL' if meeting.status == ScheduledMeeting.STATUS_CANCELLED else 'REQUEST',
      cancelled=meeting.status == ScheduledMeeting.STATUS_CANCELLED,
    )
    response = HttpResponse(invite, content_type='text/calendar; charset=UTF-8')
    response['Content-Disposition'] = f'attachment; filename="reproot-meeting-{meeting.id}.ics"'
    return response


class ClientScheduledMeetingListView(APIView):
  """A client's own upcoming/past meetings with their professional — includes
  meetings where the client is the primary attendee or an invited guest on a
  group meeting."""

  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client = request.auth
    meetings = ScheduledMeeting.objects.filter(
      Q(client=client) | Q(guests__client=client)
    ).select_related('client').prefetch_related('guests__client').distinct()
    return Response({'meetings': ScheduledMeetingSerializer(meetings, many=True, context={'client': client}).data})


class ClientMeetingRespondView(APIView):
  """Lets the client accept or decline a meeting invite — whether they're the
  primary attendee or an invited guest — so the professional can see who's
  actually coming instead of assuming everyone will show up."""

  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def post(self, request, meeting_id):
    client = request.auth
    response_status = request.data.get('response_status')
    if response_status not in (ScheduledMeeting.RESPONSE_ACCEPTED, ScheduledMeeting.RESPONSE_DECLINED):
      return Response({'message': 'response_status must be "accepted" or "declined".'}, status=status.HTTP_400_BAD_REQUEST)

    meeting = ScheduledMeeting.objects.filter(
      Q(id=meeting_id, client=client) | Q(id=meeting_id, guests__client=client)
    ).first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
    if meeting.status != ScheduledMeeting.STATUS_SCHEDULED:
      return Response({'message': 'This meeting is no longer scheduled.'}, status=status.HTTP_400_BAD_REQUEST)

    now = timezone.now()
    if meeting.client_id == client.id:
      meeting.client_response_status = response_status
      meeting.client_responded_at = now
      meeting.save(update_fields=['client_response_status', 'client_responded_at', 'updated_at'])
    else:
      guest = meeting.guests.filter(client=client).first()
      if guest is None:
        return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
      guest.response_status = response_status
      guest.responded_at = now
      guest.save(update_fields=['response_status', 'responded_at'])

    meeting.refresh_from_db()
    notify_professional(
      meeting.professional,
      category='meetings',
      event_type=f'meeting.client_{response_status}',
      event_key=f'meeting:{meeting.pk}:client:{client.pk}:{response_status}',
      title=f'Client {response_status} meeting',
      body=f'{client.first_name or client.username} {response_status} {meeting.title}.',
      action_url=web_routes.professional_meeting(meeting.pk),
      payload={'meeting_id': meeting.pk, 'client_id': client.pk},
      priority='high' if response_status == ScheduledMeeting.RESPONSE_DECLINED else 'normal',
    )
    return Response({
      'meeting': ScheduledMeetingSerializer(meeting, context={'client': client}).data,
      'message': f'You have {response_status} this meeting.',
    })
