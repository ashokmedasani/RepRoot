from django.utils import timezone
from django.db.models import Count
from rest_framework.response import Response
from rest_framework.views import APIView

from .access_permissions import ProfessionalAccessPermission
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient
from .models import ActivityNotification, NotificationPreference
from .notifications import CATEGORIES, MANDATORY_IN_APP, preferences_for


def _serialize(row):
  return {
    'id': row.id, 'category': row.category, 'event_type': row.event_type,
    'title': row.title, 'body': row.body, 'action_url': row.action_url,
    'payload': row.payload, 'priority': row.priority,
    'requires_action': row.requires_action, 'is_read': row.is_read,
    'acknowledged_at': row.acknowledged_at, 'resolved_at': row.resolved_at,
    'created_at': row.created_at,
  }


class NotificationMixin:
  recipient_type = None

  def target(self, request):
    return request.user if self.recipient_type == 'professional' else request.auth

  def queryset(self, request):
    key = 'recipient_professional' if self.recipient_type == 'professional' else 'recipient_client'
    target = self.target(request)
    disabled = NotificationPreference.objects.filter(
      recipient_type=self.recipient_type, in_app_enabled=False, **{key: target}
    ).exclude(category__in=MANDATORY_IN_APP).values_list('category', flat=True)
    return ActivityNotification.objects.filter(recipient_type=self.recipient_type, **{key: target}).exclude(category__in=disabled)

  def get(self, request):
    qs = self.queryset(request)
    category = request.query_params.get('category')
    if category in CATEGORIES:
      qs = qs.filter(category=category)
    unread = qs.filter(is_read=False)
    counts = {row['category']: row['count'] for row in unread.values('category').annotate(count=Count('id'))}
    limit = min(max(int(request.query_params.get('limit', 30)), 1), 100)
    return Response({'notifications': [_serialize(row) for row in qs[:limit]], 'unread_count': unread.count(), 'unread_by_category': counts})

  def patch(self, request):
    qs = self.queryset(request)
    notification_id = request.data.get('notification_id')
    if notification_id:
      qs = qs.filter(id=notification_id)
    elif not request.data.get('mark_all_read'):
      return Response({'message': 'Provide notification_id or mark_all_read.'}, status=400)
    now = timezone.now()
    qs.filter(is_read=False).update(is_read=True, read_at=now, updated_at=now)
    return Response({'unread_count': self.queryset(request).filter(is_read=False).count()})


class ProfessionalNotificationsView(NotificationMixin, APIView):
  permission_classes = [ProfessionalAccessPermission]
  recipient_type = 'professional'


class ClientNotificationsView(NotificationMixin, APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  recipient_type = 'client'


class PreferenceMixin:
  recipient_type = None

  def target(self, request):
    return request.user if self.recipient_type == 'professional' else request.auth

  def lookup(self, request):
    key = 'recipient_professional' if self.recipient_type == 'professional' else 'recipient_client'
    return {'recipient_type': self.recipient_type, key: self.target(request)}

  def get(self, request):
    return Response({'categories': [self.serialize(row) for row in preferences_for(self.recipient_type, self.target(request))]})

  def put(self, request):
    category = request.data.get('category')
    if category not in CATEGORIES:
      return Response({'message': 'Unknown notification category.'}, status=400)
    defaults = {}
    for key in ('in_app_enabled', 'email_enabled', 'push_enabled', 'digest_frequency'):
      if key in request.data:
        defaults[key] = request.data[key]
    if category in MANDATORY_IN_APP:
      defaults['in_app_enabled'] = True
    row, _ = NotificationPreference.objects.update_or_create(category=category, **self.lookup(request), defaults=defaults)
    return Response(self.serialize(row))

  @staticmethod
  def serialize(row):
    return {'category': row.category, 'in_app_enabled': row.in_app_enabled, 'email_enabled': row.email_enabled, 'push_enabled': row.push_enabled, 'digest_frequency': row.digest_frequency, 'mandatory_in_app': row.category in MANDATORY_IN_APP}


class ProfessionalNotificationPreferencesView(PreferenceMixin, APIView):
  permission_classes = [ProfessionalAccessPermission]
  recipient_type = 'professional'


class ClientNotificationPreferencesView(PreferenceMixin, APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  recipient_type = 'client'
