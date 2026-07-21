"""
Scheduling — real video meetings between a professional and one client,
booked through the professional's own Cal.com account (see cal_com.py for
the API contract). Kept separate from views.py the same way views_payments.py
is: a self-contained feature module.

ClientReminder (in views.py / forms_groups) stays the lightweight "call this
client back" follow-up with no video component; ScheduledMeeting is the
richer, Cal.com-backed booking. Both show up together on a client's
Schedule tab in the frontend, but they're distinct models here.
"""

from datetime import date

from django.db.models import Q
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from . import cal_com
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient
from .models import CalComConnection, ClientAccess, ScheduledMeeting, ScheduledMeetingGuest
from .serializers import CalComConnectionSerializer, ScheduledMeetingSerializer


def _get_or_create_connection(professional) -> CalComConnection:
  connection, _ = CalComConnection.objects.get_or_create(professional=professional)
  return connection


class CalComConnectionView(APIView):
  """View/update the professional's own Cal.com account link. Saving a new
  api_key immediately validates it against Cal.com (a real API call) rather
  than trusting it blindly, and returns the account's event types so the
  frontend can offer a default-meeting-type picker in the same step."""

  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    connection = _get_or_create_connection(request.user)
    return Response({'connection': CalComConnectionSerializer(connection).data})

  def put(self, request):
    connection = _get_or_create_connection(request.user)

    api_key = request.data.get('api_key')
    cal_username = request.data.get('cal_username', connection.cal_username)

    if api_key:
      connection.api_key = api_key.strip()
    connection.cal_username = (cal_username or '').strip()

    if not connection.api_key:
      return Response({'message': 'An API key is required to connect Cal.com.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      event_types = cal_com.list_event_types(connection)
    except cal_com.CalComError as exc:
      connection.is_connected = False
      connection.save(update_fields=['api_key', 'cal_username', 'is_connected', 'updated_at'])
      return Response({'message': f'Could not connect to Cal.com: {exc}'}, status=status.HTTP_502_BAD_GATEWAY)

    connection.is_connected = True

    default_id = request.data.get('default_event_type_id')
    if default_id:
      matching = next((et for et in event_types if et.get('id') == int(default_id)), None)
      if matching:
        connection.default_event_type_id = matching['id']
        connection.default_event_type_slug = matching.get('slug', '')
        connection.default_event_type_label = matching.get('title', '')
        connection.default_duration_minutes = matching.get('lengthInMinutes') or connection.default_duration_minutes
    elif not connection.default_event_type_id and event_types:
      # First-time connect with no explicit choice: default to the first
      # event type rather than leaving meeting creation with nothing to book.
      first = event_types[0]
      connection.default_event_type_id = first['id']
      connection.default_event_type_slug = first.get('slug', '')
      connection.default_event_type_label = first.get('title', '')
      connection.default_duration_minutes = first.get('lengthInMinutes') or connection.default_duration_minutes

    timezone_value = request.data.get('timezone')
    if timezone_value:
      connection.timezone = timezone_value

    connection.save()

    return Response(
      {
        'connection': CalComConnectionSerializer(connection).data,
        'event_types': event_types,
        'message': 'Cal.com connected.',
      }
    )


class CalComEventTypesView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    connection = _get_or_create_connection(request.user)
    if not connection.is_connected:
      return Response({'message': 'Connect your Cal.com account first.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      event_types = cal_com.list_event_types(connection)
    except cal_com.CalComError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    return Response({'event_types': event_types})


class CalComSlotsView(APIView):
  """Available booking slots for the professional's default (or given) event
  type over a date range — what the "pick a slot" step in the UI reads from."""

  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    connection = _get_or_create_connection(request.user)
    if not connection.is_connected:
      return Response({'message': 'Connect your Cal.com account first.'}, status=status.HTTP_400_BAD_REQUEST)

    event_type_id = request.query_params.get('event_type_id') or connection.default_event_type_id
    if not event_type_id:
      return Response({'message': 'No event type configured.'}, status=status.HTTP_400_BAD_REQUEST)

    start_param = request.query_params.get('start')
    end_param = request.query_params.get('end')
    try:
      start_date = date.fromisoformat(start_param) if start_param else timezone.localdate()
      end_date = date.fromisoformat(end_param) if end_param else start_date
    except ValueError:
      return Response({'message': 'start and end must be valid dates (YYYY-MM-DD).'}, status=status.HTTP_400_BAD_REQUEST)

    tz = request.query_params.get('timezone') or connection.timezone

    try:
      slots = cal_com.get_available_slots(connection, int(event_type_id), start_date.isoformat(), end_date.isoformat(), tz)
    except cal_com.CalComError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    return Response({'slots': slots})


class ScheduledMeetingListView(APIView):
  """All of a professional's meetings across every client — powers the
  account-wide Schedule section where clashes/overlaps are visible."""

  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    meetings = ScheduledMeeting.objects.filter(professional=request.user).select_related('client')
    client_id = request.query_params.get('client_id')
    if client_id:
      meetings = meetings.filter(client_id=client_id)
    return Response({'meetings': ScheduledMeetingSerializer(meetings, many=True).data})

  def post(self, request):
    connection = _get_or_create_connection(request.user)
    if not connection.is_connected:
      return Response({'message': 'Connect your Cal.com account first.'}, status=status.HTTP_400_BAD_REQUEST)

    client = ClientAccess.objects.filter(id=request.data.get('client'), professional=request.user, is_active=True).first()
    if client is None:
      return Response({'message': 'Client not found.'}, status=status.HTTP_404_NOT_FOUND)

    start_iso = request.data.get('start')
    if not start_iso:
      return Response({'message': 'A start time is required.'}, status=status.HTTP_400_BAD_REQUEST)

    event_type_id = request.data.get('event_type_id') or connection.default_event_type_id
    if not event_type_id:
      return Response({'message': 'No event type configured.'}, status=status.HTTP_400_BAD_REQUEST)

    if not client.email:
      return Response(
        {'message': f'{client.first_name or client.username} has no email on file — Cal.com requires one to book.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    guest_client_ids = [gid for gid in (request.data.get('guest_client_ids') or []) if gid != client.id]
    guest_clients = list(ClientAccess.objects.filter(id__in=guest_client_ids, professional=request.user, is_active=True))
    missing_email = [c for c in guest_clients if not c.email]
    if missing_email:
      names = ', '.join(c.first_name or c.username for c in missing_email)
      return Response({'message': f'{names} has no email on file — Cal.com requires one to book.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      booking = cal_com.create_booking(
        connection,
        int(event_type_id),
        start_iso,
        attendee_name=f'{client.first_name} {client.last_name}'.strip() or client.username,
        attendee_email=client.email,
        attendee_timezone=connection.timezone,
        guest_emails=[c.email for c in guest_clients] or None,
      )
    except cal_com.CalComError as exc:
      return Response({'message': f'Could not book with Cal.com: {exc}'}, status=status.HTTP_502_BAD_GATEWAY)

    meeting = ScheduledMeeting.objects.create(
      professional=request.user,
      client=client,
      title=request.data.get('title') or booking.get('title') or 'Meeting',
      notes=request.data.get('notes', ''),
      start_at=booking.get('start') or start_iso,
      end_at=booking.get('end') or start_iso,
      meeting_url=booking.get('location') or '',
      cal_booking_uid=booking.get('uid', ''),
      status=ScheduledMeeting.STATUS_SCHEDULED,
    )
    for guest_client in guest_clients:
      ScheduledMeetingGuest.objects.create(meeting=meeting, client=guest_client)

    all_names = ', '.join([client.first_name or client.username] + [c.first_name or c.username for c in guest_clients])
    return Response(
      {
        'meeting': ScheduledMeetingSerializer(meeting).data,
        'message': f'Meeting scheduled with {all_names}.',
      },
      status=status.HTTP_201_CREATED,
    )


class ScheduledMeetingRescheduleView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, meeting_id):
    meeting = ScheduledMeeting.objects.filter(id=meeting_id, professional=request.user).first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
    if meeting.status != ScheduledMeeting.STATUS_SCHEDULED:
      return Response({'message': 'Only scheduled meetings can be rescheduled.'}, status=status.HTTP_400_BAD_REQUEST)

    start_iso = request.data.get('start')
    if not start_iso:
      return Response({'message': 'A new start time is required.'}, status=status.HTTP_400_BAD_REQUEST)

    connection = _get_or_create_connection(request.user)
    try:
      booking = cal_com.reschedule_booking(connection, meeting.cal_booking_uid, start_iso, request.data.get('reason', ''))
    except cal_com.CalComError as exc:
      return Response({'message': f'Could not reschedule with Cal.com: {exc}'}, status=status.HTTP_502_BAD_GATEWAY)

    # Cal.com's reschedule creates a new booking under the hood and marks the
    # old uid cancelled — the response carries the new uid, and losing track
    # of it here means every future reschedule/cancel call 400s against a
    # booking that's already gone.
    meeting.start_at = booking.get('start') or start_iso
    meeting.end_at = booking.get('end') or meeting.end_at
    meeting.cal_booking_uid = booking.get('uid') or meeting.cal_booking_uid
    meeting.meeting_url = booking.get('location') or meeting.meeting_url
    meeting.save(update_fields=['start_at', 'end_at', 'cal_booking_uid', 'meeting_url', 'updated_at'])

    return Response({'meeting': ScheduledMeetingSerializer(meeting).data, 'message': 'Meeting rescheduled.'})


class ScheduledMeetingCancelView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, meeting_id):
    meeting = ScheduledMeeting.objects.filter(id=meeting_id, professional=request.user).first()
    if meeting is None:
      return Response({'message': 'Meeting not found.'}, status=status.HTTP_404_NOT_FOUND)
    if meeting.status != ScheduledMeeting.STATUS_SCHEDULED:
      return Response({'message': 'This meeting is already cancelled or completed.'}, status=status.HTTP_400_BAD_REQUEST)

    reason = request.data.get('reason', '')
    connection = _get_or_create_connection(request.user)
    try:
      cal_com.cancel_booking(connection, meeting.cal_booking_uid, reason)
    except cal_com.CalComError as exc:
      return Response({'message': f'Could not cancel with Cal.com: {exc}'}, status=status.HTTP_502_BAD_GATEWAY)

    meeting.status = ScheduledMeeting.STATUS_CANCELLED
    meeting.cancellation_reason = reason
    meeting.save(update_fields=['status', 'cancellation_reason', 'updated_at'])

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
