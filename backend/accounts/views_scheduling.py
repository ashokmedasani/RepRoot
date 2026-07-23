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

from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .calendar_invites import send_meeting_invite_email
from .email_utils import send_mail_background as send_mail
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient
from .access_permissions import ProfessionalAccessPermission
from .models import (
  ClientAccess,
  LeadMeetingRequest,
  LeadSubmission,
  ProfessionalAvailabilityWindow,
  ProfessionalLeadForm,
  ScheduledMeeting,
  ScheduledMeetingGuest,
)
from .scheduling_engine import (
  compute_available_slots,
  generate_meeting_room_url,
  generate_meeting_uid,
  get_or_create_scheduling_settings,
)
from .serializers import (
  LeadMeetingRequestSerializer,
  ProfessionalAvailabilityWindowSerializer,
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


class ProfessionalLeadMeetingSettingsView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    lead_form = ProfessionalLeadForm.objects.filter(professional=request.user, is_active=True).first()
    if lead_form is None:
      return Response({'message': 'Create the lead form first.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'lead_form': ProfessionalLeadFormSerializer(lead_form, context={'request': request}).data})

  def put(self, request):
    lead_form = ProfessionalLeadForm.objects.filter(professional=request.user, is_active=True).first()
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
        from_email=None,
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
        from_email=None, recipient_list=[meeting_request.contact_email], fail_silently=False,
      )
      return Response({'request': LeadMeetingRequestSerializer(meeting_request).data, 'message': 'Meeting request declined.'})

    if action != 'accept':
      return Response({'message': 'action must be accept or decline.'}, status=status.HTTP_400_BAD_REQUEST)

    uid = meeting_request.cal_booking_uid or generate_meeting_uid()
    meeting_url = generate_meeting_room_url()
    applicant_name = f'{meeting_request.submission.first_name} {meeting_request.submission.last_name}'.strip()

    meeting_request.status = LeadMeetingRequest.STATUS_ACCEPTED
    meeting_request.cal_booking_uid = uid
    meeting_request.meeting_url = meeting_url
    meeting_request.reviewed_at = timezone.now()
    meeting_request.save(update_fields=['status', 'trainer_note', 'cal_booking_uid', 'meeting_url', 'reviewed_at', 'updated_at'])

    invite_note = ''
    try:
      send_meeting_invite_email(
        uid=uid,
        sequence=meeting_request.ics_sequence,
        start_at=meeting_request.requested_start,
        end_at=meeting_request.requested_end,
        summary=f'Introductory meeting with {request.user.get_full_name() or request.user.username}',
        organizer_email=request.user.email,
        organizer_name=request.user.get_full_name() or request.user.username,
        attendees=[(applicant_name, meeting_request.contact_email)],
        meeting_url=meeting_url,
      )
    except Exception:
      invite_note = ' The confirmation email could not be sent — please contact them directly.'

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
    serializer = ProfessionalAvailabilityWindowSerializer(data=request.data)
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
    serializer = ProfessionalAvailabilityWindowSerializer(window, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response({'availability_window': ProfessionalAvailabilityWindowSerializer(window).data, 'message': 'Availability window updated.'})

  def delete(self, request, window_id):
    window = self._get_window(request, window_id)
    if window is None:
      return Response({'message': 'Availability window not found.'}, status=status.HTTP_404_NOT_FOUND)
    window.delete()
    return Response({'message': 'Availability window removed.'})


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

    meeting_url = generate_meeting_room_url()
    uid = generate_meeting_uid()
    title = request.data.get('title') or 'Meeting'

    meeting = ScheduledMeeting.objects.create(
      professional=request.user,
      client=client,
      title=title,
      notes=request.data.get('notes', ''),
      start_at=start_at,
      end_at=end_at,
      meeting_url=meeting_url,
      cal_booking_uid=uid,
      status=ScheduledMeeting.STATUS_SCHEDULED,
    )
    for guest_client in guest_clients:
      ScheduledMeetingGuest.objects.create(meeting=meeting, client=guest_client)

    invite_note = ''
    try:
      send_meeting_invite_email(
        uid=uid,
        sequence=0,
        start_at=start_at,
        end_at=end_at,
        summary=title,
        organizer_email=request.user.email,
        organizer_name=request.user.get_full_name() or request.user.username,
        attendees=_meeting_attendees(client, guest_clients),
        meeting_url=meeting_url,
      )
    except Exception:
      invite_note = ' Calendar invite emails could not be sent — please share the join link directly.'

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
    meeting.save(update_fields=['start_at', 'end_at', 'cal_booking_uid', 'ics_sequence', 'updated_at'])

    guest_clients = [guest.client for guest in meeting.guests.all()]
    invite_note = ''
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
        meeting_url=meeting.meeting_url,
        extra_body=f"This meeting was rescheduled. {request.data.get('reason', '')}".strip(),
      )
    except Exception:
      invite_note = ' Updated calendar invites could not be emailed — please notify attendees directly.'

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
    meeting.save(update_fields=['status', 'cancellation_reason', 'ics_sequence', 'updated_at'])

    if meeting.cal_booking_uid:
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

    return Response({'meeting': ScheduledMeetingSerializer(meeting).data, 'message': 'Meeting cancelled.'})


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
    return Response({
      'meeting': ScheduledMeetingSerializer(meeting, context={'client': client}).data,
      'message': f'You have {response_status} this meeting.',
    })
