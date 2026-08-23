from django.db import transaction
from rest_framework import permissions, serializers, status
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from rest_framework.views import APIView

from .models import SupportIncident, public_support_incident_reference
from .support_emails import notify_support_team, send_support_acknowledgement


class PublicContactSerializer(serializers.Serializer):
  CATEGORY_CHOICES = (
    ('general', 'General question'),
    ('product_feedback', 'Product feedback'),
    ('account_support', 'Account support'),
    ('privacy_security', 'Privacy or security'),
    ('partnership', 'Partnership'),
    ('other', 'Other'),
  )

  name = serializers.CharField(max_length=120)
  email = serializers.EmailField(max_length=254)
  category = serializers.ChoiceField(choices=CATEGORY_CHOICES)
  subject = serializers.CharField(max_length=160, required=False, allow_blank=True)
  message = serializers.CharField(max_length=5000)
  # Honeypot for basic bot filtering. Real visitors never see or fill it.
  website = serializers.CharField(required=False, allow_blank=True, write_only=True)

  def validate(self, attrs):
    if attrs['category'] == 'other' and not attrs.get('subject', '').strip():
      raise serializers.ValidationError({'subject': 'Enter a subject when Other is selected.'})
    return attrs


class PublicContactThrottle(AnonRateThrottle):
  rate = '5/hour'


class PublicContactView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [PublicContactThrottle]

  def post(self, request):
    serializer = PublicContactSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    # Return the same response for honeypot submissions without sending mail.
    if data.get('website', '').strip():
      return Response({'message': 'Your message has been received.'}, status=status.HTTP_202_ACCEPTED)

    category_label = dict(PublicContactSerializer.CATEGORY_CHOICES)[data['category']]
    subject_detail = data.get('subject', '').strip()
    category_map = {
      'general': SupportIncident.CATEGORY_OTHER,
      'product_feedback': SupportIncident.CATEGORY_FEEDBACK,
      'account_support': SupportIncident.CATEGORY_ACCOUNT,
      'privacy_security': SupportIncident.CATEGORY_TECHNICAL,
      'partnership': SupportIncident.CATEGORY_OTHER,
      'other': SupportIncident.CATEGORY_OTHER,
    }
    with transaction.atomic():
      incident = SupportIncident.objects.create(
        incident_id=public_support_incident_reference(),
        reporter_role=SupportIncident.ROLE_PUBLIC,
        reporter_name=data['name'].strip(),
        reporter_email=data['email'].strip().lower(),
        category=category_map[data['category']],
        subject=(subject_detail or category_label).strip(),
        description=data['message'].strip(),
        page_feature='Public website contact form',
        platform='web',
        priority=(
          SupportIncident.PRIORITY_HIGH
          if data['category'] == 'privacy_security'
          else SupportIncident.PRIORITY_NORMAL
        ),
        support_email_status=SupportIncident.EMAIL_PENDING,
        acknowledgement_email_status=SupportIncident.EMAIL_PENDING,
      )

    notify_support_team(incident)
    send_support_acknowledgement(incident)
    return Response(
      {
        'message': 'Your query has been sent. Our team will respond as soon as possible.',
        'ticket_number': incident.incident_id,
      },
      status=status.HTTP_201_CREATED,
    )
