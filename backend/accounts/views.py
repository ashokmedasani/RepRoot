import json
import random
import tempfile
import zipfile
from datetime import datetime, time, timedelta

import stripe
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.conf import settings
from django.core.cache import cache
from django.core.files.storage import default_storage
from django.db import IntegrityError, transaction
from django.db.models import Count, Max, ProtectedError, Q
from django.http import FileResponse, HttpResponse
from django.utils import timezone
from django.utils.crypto import get_random_string
from django.views.decorators.csrf import csrf_exempt
from rest_framework import permissions, status
from .authentication import ExpiringTokenAuthentication as TokenAuthentication, issue_professional_token
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from admin_portal.models import ErrorLog, FinanceLedgerEntry, record_error

from . import (
  account_lifecycle,
  billing,
  feature_access,
  plan_lock_status,
  razorpay_billing,
  recycle_bin,
  resource_cold_storage,
  subscription_cancellation,
)
from .models import (
  default_client_registration_fields,
  ChatMessage,
  ClientAccess,
  ClientAuthToken,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  ClientResetAudit,
  GroupRegistrationSubmission,
  LeadSubmission,
  LegalAcceptanceRecord,
  ProgressEntry,
  RecycledProfessionalAccount,
  RecycleBinItem,
  ResourceCategory,
  SupportIncident,
  SupportIncidentMessage,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalProfile,
  ProfessionalAvailabilityWindow,
  ProfessionalSchedulingSettings,
  ProfessionalResource,
  BillingWebhookEvent,
)
from .serializers import (
  ChatMessageSerializer,
  ClientAccessCreateSerializer,
  ClientAdditionalInfoUpdateSerializer,
  ClientPhotoUpdateSerializer,
  ClientDetailChangeRequestSerializer,
  ClientLoginSerializer,
  ClientPortalAccessGrantSerializer,
  ClientProfessionalLookupSerializer,
  ClientAccessSerializer,
  ClientPasswordChangeSerializer,
  ClientRegistrationFormSerializer,
  ClientReminderSerializer,
  ClientTrackingEntrySubmitSerializer,
  EmailAvailabilitySerializer,
  ErrorReportSerializer,
  ProgressEntrySerializer,
  RecycleBinItemSerializer,
  EmailOtpRequestSerializer,
  EmailOtpVerifySerializer,
  LeadSubmissionSerializer,
  GroupRegistrationSubmissionSerializer,
  PasswordResetConfirmSerializer,
  PasswordResetOtpRequestSerializer,
  PasswordResetOtpVerifySerializer,
  PublicLeadFormSerializer,
  PublicLeadSubmissionSerializer,
  PublicGroupRegistrationSerializer,
  ResourceCategorySerializer,
  SupportIncidentCreateSerializer,
  SupportIncidentSerializer,
  TemplateAssignmentSerializer,
  TrackingEntrySerializer,
  TrackingTemplateResourceSerializer,
  TrackingTemplateSerializer,
  ProfessionalAccountSerializer,
  ProfessionalGoogleAuthSerializer,
  ProfessionalGroupSerializer,
  ProfessionalLeadFormSerializer,
  ProfessionalLoginSerializer,
  ProfessionalPasswordChangeSerializer,
  ProfessionalProfileSerializer,
  normalize_profile_visibility,
  ProfessionalProfileStatusSerializer,
  ProfessionalResourceSerializer,
  ProfessionalSignupSerializer,
  UsernameAvailabilitySerializer,
)
from .notifications import notify_client
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient, issue_client_token
from .access_permissions import ProfessionalAccessPermission
from .data_retention import visible_client_data_cutoff
from .data_usage import bust_professional_data_usage_cache, calculate_professional_data_usage
from .email_utils import send_mail_background
from .email_verification import OtpCooldownError, send_email_otp, verify_email_otp
from .standard_templates import STANDARD_TEMPLATES, get_standard_template
from .plan_limits import plan_limit, professional_plan

User = get_user_model()


def generate_temporary_password():
  return f'{get_random_string(9)}!7a'


def send_client_credentials(client_access, temporary_password):
  send_mail_background(
    subject='Your RepRoot client access',
    message=(
      f'Your client access has been created.\n\n'
      f'Professional code: {client_access.professional.professional_profile.professional_id}\n'
      f'Username: {client_access.username}\n'
      f'Temporary password: {temporary_password}\n\n'
      f'You will be asked to choose a new password after your first login.'
    ),
    from_email=None,
    recipient_list=[client_access.email],
    fail_silently=False,
  )


def serialize_datetime(value):
  return value.isoformat() if value else None


def generate_unique_slug():
  while True:
    slug = get_random_string(12).lower()

    if not ProfessionalLeadForm.objects.filter(public_slug=slug).exists():
      return slug


def generate_reference_id():
  while True:
    reference_id = f'APP-{get_random_string(10).upper()}'

    if not LeadSubmission.objects.filter(reference_id=reference_id).exists():
      return reference_id


def email_delivery_message(message: str) -> str:
  if settings.EMAIL_BACKEND == 'django.core.mail.backends.console.EmailBackend':
    return f'{message} In local testing, check the Django backend terminal.'

  return f'{message} Check your email inbox.'


def local_debug_otp_payload(otp: str) -> dict:
  if settings.DEBUG and settings.EMAIL_BACKEND == 'django.core.mail.backends.console.EmailBackend':
    return {'dev_otp': otp}

  return {}


def build_professional_account_snapshot(user):
  profile = getattr(user, 'professional_profile', None)
  snapshot = {
    'user': {
      'id': user.id,
      'username': user.username,
      'email': user.email,
      'first_name': user.first_name,
      'last_name': user.last_name,
      'is_active': user.is_active,
      'is_staff': user.is_staff,
      'is_superuser': user.is_superuser,
      'date_joined': serialize_datetime(user.date_joined),
      'last_login': serialize_datetime(user.last_login),
    },
    'professional_profile': None,
  }

  if profile:
    snapshot['professional_profile'] = {
      'id': profile.id,
      'professional_id': profile.professional_id,
      'profile_setup_completed': profile.profile_setup_completed,
      'profile_photo': profile.profile_photo.name,
      'middle_name': profile.middle_name,
      'gender': profile.gender,
      'state': profile.state,
      'country': profile.country,
      'birth_month': profile.birth_month,
      'birth_year': profile.birth_year,
      'professional_headline': profile.professional_headline,
      'about_me': profile.about_me,
      'professional_type': profile.professional_type,
      'years_experience': profile.years_experience,
      'specializations': profile.specializations,
      'training_style': profile.training_style,
      'languages_known': profile.languages_known,
      'certification_name': profile.certification_name,
      'certification_issued_by': profile.certification_issued_by,
      'certification_year': profile.certification_year,
      'certification_file': profile.certification_file.name,
      'transformation_photo': profile.transformation_photo.name,
      'training_photo': profile.training_photo.name,
      'intro_video_url': profile.intro_video_url,
      'instagram_url': profile.instagram_url,
      'youtube_url': profile.youtube_url,
      'website_url': profile.website_url,
      'profile_images': profile.profile_images,
      'profile_links': profile.profile_links,
      'terms_accepted': profile.terms_accepted,
      'privacy_policy_accepted': profile.privacy_policy_accepted,
      'created_at': serialize_datetime(profile.created_at),
      'updated_at': serialize_datetime(profile.updated_at),
    }

  return snapshot


def build_public_professional_profile(user, request=None):
  profile = getattr(user, 'professional_profile', None)

  if profile is None:
    return None

  visibility = normalize_profile_visibility(profile.profile_visibility)

  def file_url(file_field):
    if not file_field:
      return ''

    return request.build_absolute_uri(file_field.url) if request else file_field.url

  public_images = list(profile.profile_images or []) if visibility.get('images') else []
  if visibility.get('images'):
    legacy_images = [
      ('Transformation Photos', 'Transformation photo', profile.transformation_photo),
      ('Training', 'Training photo', profile.training_photo),
    ]
    existing_image_urls = {str(item.get('url', '')) for item in public_images if isinstance(item, dict)}
    for category, title, file_field in legacy_images:
      url = file_url(file_field)
      if url and url not in existing_image_urls:
        public_images.append({'category': category, 'title': title, 'url': url})

  public_links = list(profile.profile_links or []) if visibility.get('links') else []
  if visibility.get('links'):
    legacy_links = [
      ('Website', profile.website_url),
      ('Instagram', profile.instagram_url),
      ('YouTube', profile.youtube_url),
      ('Introduction video', profile.intro_video_url),
    ]
    existing_link_urls = {str(item.get('url', '')) for item in public_links if isinstance(item, dict)}
    for title, url in legacy_links:
      if url and url not in existing_link_urls:
        public_links.append({'title': title, 'url': url})

  payload = {
    'professional_name': user.get_full_name() or user.username,
    'profile_photo_url': file_url(profile.profile_photo),
    'professional_headline': profile.professional_headline if visibility.get('professional_headline') else '',
    'location': ', '.join(item for item in [profile.state, profile.country] if item),
    'about_me': profile.about_me if visibility.get('about') else '',
    'professional_summary': None,
    'training_style': profile.training_style if visibility.get('training_style') else '',
    'certification': None,
    'images': public_images,
    'links': public_links,
  }

  if any(
    visibility.get(key)
    for key in ('professional_summary', 'specializations', 'experience', 'languages')
  ):
    payload['professional_summary'] = {
      'professional_type': profile.professional_type if visibility.get('professional_summary') else '',
      'years_experience': (
        profile.years_experience if visibility.get('experience', visibility.get('professional_summary')) else None
      ),
      'specializations': (
        profile.specializations if visibility.get('specializations', visibility.get('professional_summary')) else ''
      ),
      'languages_known': (
        profile.languages_known if visibility.get('languages', visibility.get('professional_summary')) else ''
      ),
    }

  if visibility.get('certification'):
    payload['certification'] = {
      'name': profile.certification_name,
      'issued_by': profile.certification_issued_by,
      'year': profile.certification_year,
      'file_url': file_url(profile.certification_file),
    }

  return payload


def _username_suggestions(base: str, limit: int = 3) -> list[str]:
  """A handful of available variations on a taken username, checked in one query."""
  candidates = []
  seen_candidates = set()
  for suffix in random.sample(range(1, 100), 8):
    candidate = f'{base[:10 - len(str(suffix))]}{suffix}'
    if candidate not in seen_candidates:
      seen_candidates.add(candidate)
      candidates.append(candidate)

  if not candidates:
    return []

  taken_query = Q()
  for candidate in candidates:
    taken_query |= Q(username__iexact=candidate)
  taken_lower = {name.lower() for name in User.objects.filter(taken_query).values_list('username', flat=True)}

  return [candidate for candidate in candidates if candidate.lower() not in taken_lower][:limit]


class UsernameAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def post(self, request):
    serializer = UsernameAvailabilitySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    username = serializer.validated_data['username']
    is_available = not User.objects.filter(username__iexact=username).exists()

    return Response(
      {
        'username': username,
        'available': is_available,
        'message': 'Username is available.' if is_available else 'Username is already taken.',
        'suggestions': [] if is_available else _username_suggestions(username),
      }
    )


class ProfessionalCodeAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def get(self, request):
    return self._check(request.query_params.get('professional_code', ''))

  def post(self, request):
    return self._check(request.data.get('professional_code', ''))

  def _check(self, raw_code):
    code = str(raw_code).strip().lower()

    if len(code) < 4 or len(code) > 32:
      return Response({'available': False, 'message': 'Professional code must be 4 to 32 characters.'})

    if not code.replace('-', '').replace('_', '').isalnum():
      return Response({'available': False, 'message': 'Professional code can only use letters, numbers, hyphens, and underscores.'})

    is_available = not ProfessionalProfile.objects.filter(professional_id__iexact=code).exists()

    return Response(
      {
        'professional_code': code,
        'available': is_available,
        'message': 'Professional code is available.' if is_available else 'Professional code is already taken.',
      }
    )


class ProfessionalCodeUpdateView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    return Response({'professional_code': request.user.professional_profile.professional_id or ''})

  def put(self, request):
    profile = request.user.professional_profile
    code = str(request.data.get('professional_code', '')).strip().lower()

    if len(code) < 4 or len(code) > 32:
      return Response({'message': 'Professional code must be 4 to 32 characters.'}, status=status.HTTP_400_BAD_REQUEST)

    if not code.replace('-', '').replace('_', '').isalnum():
      return Response(
        {'message': 'Professional code can only use letters, numbers, hyphens, and underscores.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    if ProfessionalProfile.objects.filter(professional_id__iexact=code).exclude(pk=profile.pk).exists():
      return Response({'message': 'Professional code is already taken.'}, status=status.HTTP_400_BAD_REQUEST)

    profile.professional_id = code
    profile.save(update_fields=['professional_id', 'updated_at'])

    return Response({'professional_code': profile.professional_id, 'message': 'Professional code saved.'})


class EmailAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def post(self, request):
    serializer = EmailAvailabilitySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data['email']
    is_available = not User.objects.filter(email__iexact=email).exists()

    return Response(
      {
        'email': email,
        'available': is_available,
        'message': 'Email is available.' if is_available else 'Email is already registered.',
      }
    )


class EmailOtpRequestView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'otp'

  def post(self, request):
    serializer = EmailOtpRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data['email']

    if User.objects.filter(email__iexact=email).exists():
      return Response(
        {
          'email': email,
          'available': False,
          'message': 'Email exists already. Try Login or Forgot Password.',
        }
      )

    try:
      otp = send_email_otp(email)
    except OtpCooldownError as error:
      return Response(
        {'message': f'Please wait {error.remaining_seconds} seconds before requesting another OTP.'},
        status=status.HTTP_429_TOO_MANY_REQUESTS,
      )

    return Response(
      {
        'email': email,
        'message': email_delivery_message('Verification code sent.'),
        **local_debug_otp_payload(otp),
      }
    )


class EmailOtpVerifyView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'otp'

  def post(self, request):
    serializer = EmailOtpVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data['email']
    result = verify_email_otp(email, serializer.validated_data['otp'])

    if result is None:
      return Response({'message': 'Invalid or expired verification code.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'email': email,
        'email_verification_token': result.token,
        'message': 'Email verified successfully.',
      }
    )


class ProfessionalSignupView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = ProfessionalSignupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    token = issue_professional_token(user)

    return Response(
      {
        'token': token.key,
        'professional': ProfessionalAccountSerializer(user).data,
        'message': 'Professional account created successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class ProfessionalLoginView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = ProfessionalLoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']
    token = issue_professional_token(user)

    return Response(
      {
        'token': token.key,
        'professional': ProfessionalAccountSerializer(user).data,
        'message': 'Professional login successful.',
      }
    )


class ProfessionalGoogleAuthView(APIView):
  """Handles both "Continue with Google" signup and "Log in with Google".

  The frontend posts the same Google Identity Services credential regardless
  of whether the professional is new; ProfessionalGoogleAuthSerializer /
  google_oauth.get_or_create_professional_for_google decide whether to
  create an account, link an existing password account, or just log in.
  """

  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = ProfessionalGoogleAuthSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']
    created = serializer.validated_data['created']
    token = issue_professional_token(user)

    return Response(
      {
        'token': token.key,
        'professional': ProfessionalAccountSerializer(user).data,
        'is_new_account': created,
        'message': 'Professional account created successfully.' if created else 'Professional login successful.',
      },
      status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


class ClientLoginView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = ClientLoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access = serializer.validated_data['client_access']
    token = issue_client_token(client_access)

    return Response(
      {
        'token': token.key,
        'client': ClientAccessSerializer(client_access).data,
        'message': 'Client login successful.',
      }
    )


class PasswordResetOtpRequestView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'otp'

  def post(self, request):
    serializer = PasswordResetOtpRequestSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data['email']

    if not User.objects.filter(email__iexact=email, professional_profile__isnull=False).exists():
      return Response(
        {
          'email': email,
          'available': True,
          'message': 'No professional account found. Try Sign up or Login.',
        }
      )

    try:
      otp = send_email_otp(email, purpose='password-reset')
    except OtpCooldownError as error:
      return Response(
        {'message': f'Please wait {error.remaining_seconds} seconds before requesting another OTP.'},
        status=status.HTTP_429_TOO_MANY_REQUESTS,
      )

    return Response(
      {
        'email': email,
        'message': email_delivery_message('Password reset code sent.'),
        **local_debug_otp_payload(otp),
      }
    )


class PasswordResetOtpVerifyView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'otp'

  def post(self, request):
    serializer = PasswordResetOtpVerifySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    email = serializer.validated_data['email']
    result = verify_email_otp(email, serializer.validated_data['otp'], purpose='password-reset')

    if result is None:
      return Response({'message': 'Invalid or expired reset code.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'email': email,
        'reset_token': result.token,
        'message': 'Password reset email verified.',
      }
    )


class PasswordResetConfirmView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = PasswordResetConfirmSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    serializer.save()

    return Response({'message': 'Password reset successfully. You can now login.'})


class ProfessionalProfileStatusView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def get(self, request):
    profile = request.user.professional_profile
    return Response(ProfessionalProfileStatusSerializer(profile).data)


class ProfessionalLegalAcceptanceView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def post(self, request):
    if request.data.get('accept_terms') is not True or request.data.get('accept_privacy') is not True:
      return Response(
        {'message': 'You must review and accept both Professional Terms and the Professional Privacy Notice.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    profile = request.user.professional_profile
    accepted_at = timezone.now()
    profile.terms_accepted = True
    profile.privacy_policy_accepted = True
    profile.terms_accepted_at = accepted_at
    profile.privacy_policy_accepted_at = accepted_at
    profile.legal_document_version = settings.REPROOT_PROFESSIONAL_LEGAL_VERSION
    profile.save(update_fields=[
      'terms_accepted', 'privacy_policy_accepted', 'terms_accepted_at',
      'privacy_policy_accepted_at', 'legal_document_version', 'updated_at',
    ])
    LegalAcceptanceRecord.objects.create(
      actor_type=LegalAcceptanceRecord.ACTOR_PROFESSIONAL,
      professional_profile=profile,
      actor_reference=profile.professional_id or str(request.user.id),
      legal_document_version=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
      accepted_at=accepted_at,
      client_timezone=str(request.data.get('client_timezone') or '')[:80],
    )
    return Response({
      'profile': ProfessionalProfileSerializer(profile).data,
      'message': 'Professional legal documents accepted.',
    })


class LegalConfigurationView(APIView):
  """Public, non-secret metadata used by legal pages and consent screens."""

  permission_classes = [permissions.AllowAny]

  def get(self, request):
    return Response({
      'effective_date': settings.REPROOT_LEGAL_EFFECTIVE_DATE,
      'professional': {
        'version': settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
      },
      'client': {
        'version': settings.REPROOT_CLIENT_LEGAL_VERSION,
      },
    })


class ProfessionalDataUsageView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    return Response(calculate_professional_data_usage(request.user))


class ProfessionalOnboardingStatusView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    checks = {
      'profile': request.user.professional_profile.profile_setup_completed,
      'form': ProfessionalLeadForm.objects.filter(professional=request.user).exists(),
      'group': ProfessionalGroup.objects.filter(professional=request.user, is_active=True).exists(),
      'template': TrackingTemplate.objects.filter(professional=request.user, is_active=True).exists(),
      'resource': ProfessionalResource.objects.filter(professional=request.user).exists(),
      'meeting_setup': ProfessionalAvailabilityWindow.objects.filter(
        professional=request.user, is_active=True
      ).exists(),
    }
    routes = {
      'profile': '/professional/profile',
      'form': '/professional/forms/create',
      'group': '/professional/groups/create',
      'template': '/professional/templates/create',
      'resource': '/professional/resource',
      'meeting_setup': '/professional/schedule',
    }
    labels = {
      'profile': 'Complete Profile',
      'form': 'Create Form',
      'group': 'Create Group',
      'template': 'Create Template',
      'resource': 'Add Resource',
      'meeting_setup': 'Complete Meeting Setup',
    }
    # Short forms for the compact dashboard card -- deliberately terse so the
    # "Action Required" card doesn't grow tall with a full sentence per item.
    short_nouns = {
      'profile': 'profile',
      'form': 'form',
      'group': 'group',
      'template': 'template',
      'resource': 'resource',
      'meeting_setup': 'meeting setup',
    }
    single_action_phrases = {
      'profile': 'completing your profile',
      'form': 'creating a form',
      'group': 'creating a group',
      'template': 'creating a template',
      'resource': 'adding a resource',
      'meeting_setup': 'completing your meeting setup',
    }
    missing = [key for key, complete in checks.items() if not complete]

    if not missing:
      message = ''
    elif len(missing) == 1:
      message = f'Complete your workspace by {single_action_phrases[missing[0]]}.'
    else:
      nouns = [short_nouns[key] for key in missing]
      message = 'Complete your workspace: ' + ', '.join(nouns[:-1]) + f', and {nouns[-1]}.'

    return Response({
      'profile_complete': checks['profile'],
      'form_created': checks['form'],
      'group_created': checks['group'],
      'template_created': checks['template'],
      'resource_created': checks['resource'],
      'meeting_setup_complete': checks['meeting_setup'],
      'missing_actions': missing,
      'actions': [
        {'code': key, 'label': labels[key], 'route': routes[key]}
        for key in missing
      ],
      'message': message,
    })


class ProfessionalMeetingEligibilityView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    scheduling = ProfessionalSchedulingSettings.objects.filter(professional=request.user).first()
    has_availability = ProfessionalAvailabilityWindow.objects.filter(
      professional=request.user, is_active=True
    ).exists()
    missing = []
    if scheduling is None or not scheduling.timezone:
      missing.append('timezone')
    if scheduling is None or scheduling.default_duration_minutes <= 0:
      missing.append('meeting_duration')
    if scheduling is None or scheduling.buffer_minutes < 0:
      missing.append('buffer_time')
    if not has_availability:
      missing.append('weekly_availability')
    return Response({
      'can_enable': not missing,
      'missing_requirements': missing,
      'message': (
        'Meeting scheduling is ready to enable.'
        if not missing
        else 'Complete your meeting setup and add your weekly availability before enabling meeting scheduling.'
      ),
    })


class RecycleBinListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    items = RecycleBinItem.objects.filter(professional=request.user)
    return Response({'items': RecycleBinItemSerializer(items, many=True).data})


class RecycleBinRestoreView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, item_id):
    item = RecycleBinItem.objects.filter(id=item_id, professional=request.user).first()
    if item is None:
      return Response({'message': 'Recycle Bin item not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      recycle_bin.restore_item(item)
    except recycle_bin.RestoreError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_409_CONFLICT)

    cache.delete(f'professional-data-usage:v5:{request.user.pk}')
    return Response({'message': 'Restored.'})


class RecycleBinPermanentDeleteView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request, item_id):
    item = RecycleBinItem.objects.filter(id=item_id, professional=request.user).first()
    if item is None:
      return Response({'message': 'Recycle Bin item not found.'}, status=status.HTTP_404_NOT_FOUND)

    recycle_bin.delete_permanently(item)
    return Response({'message': 'Permanently deleted.'})


class ProfessionalBillingStatusView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    profile = request.user.professional_profile
    subscription_cancellation.apply_due_cancellation(profile)
    profile.refresh_from_db()
    country_code = next((
      str(request.META.get(header, '')).strip().upper()
      for header in ('HTTP_CF_IPCOUNTRY', 'HTTP_X_VERCEL_IP_COUNTRY', 'HTTP_X_COUNTRY_CODE')
      if request.META.get(header)
    ), '')
    profile_country = str(profile.country or '').strip().lower()
    is_india = country_code == 'IN' or (not country_code and profile_country in ('india', 'in', 'ind'))
    return Response(
      {
        'plan': professional_plan(request.user),
        'plan_renews_at': profile.plan_renews_at,
        'cancellation_requested_at': profile.cancellation_requested_at,
        'cancellation_effective_at': profile.cancellation_effective_at,
        'downgrade_assessment': subscription_cancellation.downgrade_assessment(request.user),
        'has_billing_account': bool(profile.razorpay_payment_link_id or profile.stripe_customer_id),
        # billing_configured reflects whether Razorpay itself is actually set
        # up (real key/secret/webhook secret present) -- not whether the
        # no-charge test-mode shortcut happens to be on. Those are separate
        # things: test mode can be off in production with Razorpay fully
        # configured, or (in a dev sandbox) on with no real keys at all.
        'billing_configured': razorpay_billing.is_configured() or settings.REPROOT_BILLING_TEST_MODE,
        'test_mode': settings.REPROOT_BILLING_TEST_MODE,
        'billing_currency': 'INR' if is_india else 'USD',
        'billing_region': 'India' if is_india else 'International',
        'support_email': settings.SUPPORT_EMAIL,
        # A tier is offered once Razorpay is genuinely configured for it, or
        # test mode is on (which applies the tier directly with no charge).
        'available_upgrades': {
          tier: (razorpay_billing.is_configured() or settings.REPROOT_BILLING_TEST_MODE)
          for tier in razorpay_billing.PLAN_PRICES
        },
        'catalog': razorpay_billing.public_catalog(),
        'plans': [
          {'code': code, **settings.REPROOT_PLAN_TIERS[code]}
          for code in ('starter_free', 'pro', 'premium_unlimited')
        ],
      }
    )


class ProfessionalBillingCheckoutView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'payments'

  def post(self, request):
    target_tier = str(request.data.get('target_tier', '')).strip().lower()
    allowed_tiers = tuple(razorpay_billing.PLAN_PRICES)
    if target_tier not in allowed_tiers:
      return Response(
        {'message': 'target_tier must be one of: ' + ', '.join(allowed_tiers)},
        status=status.HTTP_400_BAD_REQUEST,
      )

    profile = request.user.professional_profile
    if profile.plan_tier == target_tier:
      return Response({'message': f'This professional is already on {target_tier}.'}, status=status.HTTP_400_BAD_REQUEST)

    billing_cycle = str(request.data.get('billing_cycle', 'monthly')).strip().lower()
    if settings.REPROOT_BILLING_TEST_MODE:
      cycle_price = razorpay_billing.PLAN_PRICES.get(target_tier, {}).get(billing_cycle)
      profile.plan_tier = target_tier
      profile.plan_renews_at = (
        razorpay_billing.renewal_date(cycle_price['months'])
        if cycle_price else None
      )
      profile.cancellation_requested_at = None
      profile.cancellation_effective_at = None
      profile.save(update_fields=[
        'plan_tier', 'plan_renews_at', 'cancellation_requested_at', 'cancellation_effective_at',
      ])
      account_lifecycle.reactivate_on_upgrade(profile)
      return Response({
        'applied': True,
        'test_mode': True,
        'message': f'Plan updated to {professional_plan(request.user)["name"]} for testing.',
      })

    if not settings.REPROOT_PAYMENTS_ENABLED:
      return Response(
        {'message': 'Subscription payments are not available yet.'},
        status=status.HTTP_503_SERVICE_UNAVAILABLE,
      )

    profile_country = str(profile.country or '').strip().lower()
    currency = 'INR' if profile_country in ('india', 'in', 'ind') else 'USD'
    try:
      payment_link = razorpay_billing.create_payment_link(profile, target_tier, billing_cycle, currency)
    except ValueError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_400_BAD_REQUEST)
    except razorpay_billing.RazorpayError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)
    profile.razorpay_payment_link_id = payment_link.get('id', '')
    profile.save(update_fields=['razorpay_payment_link_id'])
    return Response({
      'checkout_url': payment_link.get('short_url', ''),
      'provider': 'razorpay',
      'payment_link_id': payment_link.get('id', ''),
    })


def _allowed_downgrade_targets(plan_tier):
  """Which tiers a professional on the given plan_tier may self-serve
  downgrade to. Premium can step down to Pro (a softer landing) or all the
  way to Free; Pro can only go to Free, since there's nothing between Pro
  and Free in the 3-tier lineup."""
  if plan_tier in (ProfessionalProfile.PLAN_PREMIUM_UNLIMITED, ProfessionalProfile.PLAN_PREMIUM):
    return ('starter_free', 'pro')
  return ('starter_free',)


class ProfessionalBillingCancelView(APIView):
  """Self-serve 'cancel plan' — the missing piece that left professionals
  stuck once they'd been moved off the Free plan with no way back. Also
  lets a Premium professional choose Pro as a softer downgrade target
  instead of dropping straight to Free."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    profile = request.user.professional_profile
    target_tier_code = request.query_params.get('target_tier', 'starter_free')
    if target_tier_code not in _allowed_downgrade_targets(profile.plan_tier):
      return Response({'message': 'Invalid downgrade target for your current plan.'}, status=status.HTTP_400_BAD_REQUEST)
    return Response(subscription_cancellation.downgrade_assessment(request.user, target_tier_code))

  def post(self, request):
    profile = request.user.professional_profile
    if profile.plan_tier in (ProfessionalProfile.PLAN_STARTER_FREE, ProfessionalProfile.PLAN_STARTER):
      return Response({'message': 'This professional is already on the Free plan.'}, status=status.HTTP_400_BAD_REQUEST)

    target_tier_code = request.data.get('target_tier', 'starter_free')
    if target_tier_code not in _allowed_downgrade_targets(profile.plan_tier):
      return Response({'message': 'Invalid downgrade target for your current plan.'}, status=status.HTTP_400_BAD_REQUEST)
    target_name = settings.REPROOT_PLAN_TIERS[target_tier_code]['name']

    # Nothing about the plan-limit lock system blocks cancellation -- any
    # group/lead form/template/resource/category over the target tier's
    # limits simply locks (never deleted), and any client in a group that
    # locks loses portal access without losing their data. Only genuine
    # storage overage -- the separate, unmodified byte-quota pipeline -- can
    # still block a self-serve cancellation, since that data genuinely
    # can't be deleted automatically.
    assessment = subscription_cancellation.downgrade_assessment(request.user, target_tier_code)
    if not assessment['storage']['eligible']:
      support = settings.SUPPORT_EMAIL or 'the configured support team'
      return Response({
        'message': (
          f'Your storage is {assessment["storage"]["free_tier_percent"]}% of the {target_name} allowance. '
          f'Self-service cancellation is blocked because storage cannot be deleted automatically. Contact {support}.'
        ),
        'assessment': assessment,
      }, status=status.HTTP_409_CONFLICT)

    effective_at = subscription_cancellation.schedule_cancellation(profile, target_tier_code)
    return Response({
      'message': (
        f'Membership cancellation scheduled. Your paid plan remains active until the displayed expiry date. '
        f'Nothing is deleted at any point -- anything over the {target_name} plan\'s limits will simply lock, '
        f'and you can unlock it again any time by upgrading.'
      ),
      'cancellation_effective_at': effective_at,
      'assessment': assessment,
    })

  def legacy_post(self, request):
    profile = request.user.professional_profile
    if profile.plan_tier in (ProfessionalProfile.PLAN_STARTER_FREE, ProfessionalProfile.PLAN_STARTER):
      return Response({'message': 'This professional is already on the Free plan.'}, status=status.HTTP_400_BAD_REQUEST)

    if profile.razorpay_payment_id:
      return Response({
        'message': 'Razorpay prepaid plans do not auto-renew. Your paid plan remains active until its renewal date.'
      })

    if profile.stripe_subscription_id and settings.STRIPE_SECRET_KEY:
      try:
        billing.cancel_subscription(profile)
      except stripe.StripeError as exc:
        return Response({'message': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)
      # The subscription.deleted webhook finishes the job (process_downgrade)
      # once Stripe confirms the cancellation — nothing more to do here.
    else:
      # Test-mode tiers (and anything else with no real subscription behind
      # it) have nothing for Stripe to cancel, so apply the downgrade directly.
      account_lifecycle.downgrade_to_starter_free_voluntarily(profile)

    return Response({'message': 'Plan cancelled — moving to the Free plan.'})


class ProfessionalBillingPortalView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    if settings.REPROOT_BILLING_PROVIDER == 'razorpay':
      if not settings.RAZORPAY_PERSONAL_LINK:
        return Response({'message': 'Billing support link is not configured yet.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)
      return Response({'portal_url': settings.RAZORPAY_PERSONAL_LINK})

    if not settings.STRIPE_SECRET_KEY:
      return Response({'message': 'Billing is not configured yet.'}, status=status.HTTP_503_SERVICE_UNAVAILABLE)

    profile = request.user.professional_profile
    if not profile.stripe_customer_id:
      return Response({'message': 'Upgrade to Premium first to manage billing.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      portal_url = billing.create_portal_session(profile)
    except stripe.StripeError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    return Response({'portal_url': portal_url})


@csrf_exempt
def razorpay_webhook(request):
  if request.method != 'POST':
    return HttpResponse(status=405)
  if not settings.RAZORPAY_WEBHOOK_SECRET:
    return HttpResponse(status=503)
  signature = request.META.get('HTTP_X_RAZORPAY_SIGNATURE', '')
  if not razorpay_billing.verify_webhook(request.body, signature):
    return HttpResponse(status=400)

  try:
    payload = json.loads(request.body.decode('utf-8'))
  except (UnicodeDecodeError, json.JSONDecodeError):
    return HttpResponse(status=400)
  if payload.get('event') not in ('payment_link.paid', 'payment.captured'):
    return HttpResponse(status=200)
  event_payload = payload.get('payload') or {}
  payment_link = (event_payload.get('payment_link') or {}).get('entity') or {}
  payment = (event_payload.get('payment') or {}).get('entity') or {}
  notes = payment_link.get('notes') or payment.get('notes') or {}
  user_id = notes.get('professional_user_id')
  target_tier = notes.get('target_tier')
  profile = ProfessionalProfile.objects.filter(user_id=user_id).first() if user_id else None
  if profile is None or target_tier not in razorpay_billing.PLAN_PRICES:
    return HttpResponse(status=400)

  payment_id = payment.get('id', '')
  payment_link_id = payment_link.get('id', '')
  event_id = request.META.get('HTTP_X_RAZORPAY_EVENT_ID', '').strip() or payment_id or payment_link_id
  billing_cycle = notes.get('billing_cycle', '')
  currency = (payment.get('currency') or payment_link.get('currency') or '').upper()
  try:
    amount_subunits = int(payment.get('amount') or payment_link.get('amount') or 0)
  except (TypeError, ValueError):
    return HttpResponse(status=400)
  expected = razorpay_billing.expected_payment(target_tier, billing_cycle, currency)
  if not event_id or not payment_id or not expected:
    return HttpResponse(status=400)
  if amount_subunits != expected['amount_subunits']:
    return HttpResponse(status=400)
  if payment.get('status') not in ('captured', 'paid') and payment_link.get('status') != 'paid':
    return HttpResponse(status=400)
  if profile.razorpay_payment_link_id and payment_link_id != profile.razorpay_payment_link_id:
    return HttpResponse(status=400)

  try:
    with transaction.atomic():
      BillingWebhookEvent.objects.create(
        provider='razorpay',
        event_id=event_id,
        event_type=payload.get('event', ''),
      )
      profile = ProfessionalProfile.objects.select_for_update().get(pk=profile.pk)
      profile.plan_tier = target_tier
      profile.razorpay_payment_link_id = payment_link_id
      profile.razorpay_payment_id = payment_id
      profile.plan_renews_at = razorpay_billing.renewal_date(expected['months'])
      profile.save(update_fields=[
        'plan_tier', 'razorpay_payment_link_id', 'razorpay_payment_id', 'plan_renews_at',
      ])
      account_lifecycle.reactivate_on_upgrade(profile)

      amount = amount_subunits / 100
      FinanceLedgerEntry.objects.create(
        entry_type=FinanceLedgerEntry.TYPE_SUBSCRIPTION,
        status=FinanceLedgerEntry.STATUS_COMPLETED,
        amount=amount,
        currency=currency,
        professional=profile.user,
        description=f'{profile.get_plan_tier_display()} prepaid membership started',
        external_reference=payment_id,
        source='platform_subscription',
        professional_reference=profile.internal_reference_code,
        original_amount=amount,
        original_currency=currency,
        reporting_amount=amount,
        reporting_currency=currency,
        provider='razorpay',
        metadata={'target_tier': target_tier, 'billing_cycle': billing_cycle, 'event_id': event_id},
        occurred_at=timezone.now(),
      )
  except IntegrityError:
    return HttpResponse(status=200)
  return HttpResponse(status=200)


@csrf_exempt
def stripe_webhook(request):
  """Stripe -> us. The only writer of ProfessionalProfile.plan_tier.

  Not a DRF view: needs the raw request body for signature verification,
  and Stripe is not one of our authenticated callers.
  """
  if request.method != 'POST':
    return HttpResponse(status=405)

  if not settings.STRIPE_WEBHOOK_SECRET:
    return HttpResponse(status=503)

  sig_header = request.META.get('HTTP_STRIPE_SIGNATURE', '')
  try:
    event = stripe.Webhook.construct_event(request.body, sig_header, settings.STRIPE_WEBHOOK_SECRET)
  except (ValueError, stripe.SignatureVerificationError):
    return HttpResponse(status=400)

  event_type = event['type']
  data = event['data']['object']

  if event_type == 'checkout.session.completed':
    professional_user_id = (data.get('metadata') or {}).get('professional_user_id') or data.get('client_reference_id')
    target_tier = (data.get('metadata') or {}).get('target_tier')
    customer_id = data.get('customer')
    profile = ProfessionalProfile.objects.filter(user_id=professional_user_id).first() if professional_user_id else None
    if profile is None and customer_id:
      profile = ProfessionalProfile.objects.filter(stripe_customer_id=customer_id).first()
    if profile is not None:
      profile.plan_tier = target_tier if target_tier in dict(ProfessionalProfile.PLAN_CHOICES) else ProfessionalProfile.PLAN_PREMIUM
      profile.stripe_customer_id = customer_id or profile.stripe_customer_id
      profile.stripe_subscription_id = data.get('subscription') or profile.stripe_subscription_id
      profile.save(update_fields=['plan_tier', 'stripe_customer_id', 'stripe_subscription_id'])
      account_lifecycle.reactivate_on_upgrade(profile)
      FinanceLedgerEntry.objects.create(
        entry_type=FinanceLedgerEntry.TYPE_SUBSCRIPTION,
        status=FinanceLedgerEntry.STATUS_COMPLETED,
        amount=(data.get('amount_total') or 0) / 100,
        currency=(data.get('currency') or 'usd').upper(),
        professional=profile.user,
        description=f'{profile.get_plan_tier_display()} subscription started',
        external_reference=data.get('id', ''),
        source='platform_subscription',
        professional_reference=profile.internal_reference_code,
        original_amount=(data.get('amount_total') or 0) / 100,
        original_currency=(data.get('currency') or 'usd').upper(),
        reporting_amount=(data.get('amount_total') or 0) / 100,
        reporting_currency=(data.get('currency') or 'usd').upper(),
        provider='stripe',
        metadata={'target_tier': profile.plan_tier, 'subscription_reference': data.get('subscription') or ''},
        occurred_at=timezone.now(),
      )

  elif event_type == 'customer.subscription.updated':
    customer_id = data.get('customer')
    profile = ProfessionalProfile.objects.filter(stripe_customer_id=customer_id).first()
    if profile is not None:
      sub_status = data.get('status')
      period_end = data.get('current_period_end')
      if period_end:
        profile.plan_renews_at = datetime.fromtimestamp(period_end, tz=timezone.get_current_timezone())
        profile.save(update_fields=['plan_renews_at'])
      if sub_status in ('canceled', 'unpaid', 'incomplete_expired'):
        # Route through the lifecycle service, not a direct plan_tier write —
        # this starts the 14-day grace period and sends the downgrade email
        # instead of silently dropping the professional to Starter Free.
        account_lifecycle.process_downgrade(profile)
      elif sub_status in ('active', 'trialing'):
        price_id = ((data.get('items') or {}).get('data') or [{}])[0].get('price', {}).get('id', '')
        resolved_tier = billing.resolve_tier_from_price(price_id)
        if resolved_tier:
          profile.plan_tier = resolved_tier
          profile.save(update_fields=['plan_tier'])
          account_lifecycle.reactivate_on_upgrade(profile)

  elif event_type == 'customer.subscription.deleted':
    customer_id = data.get('customer')
    profile = ProfessionalProfile.objects.filter(stripe_customer_id=customer_id).first()
    if profile is not None:
      profile.plan_renews_at = None
      profile.save(update_fields=['plan_renews_at'])
      account_lifecycle.process_downgrade(profile)

  elif event_type == 'invoice.payment_failed':
    customer_id = data.get('customer')
    profile = ProfessionalProfile.objects.filter(stripe_customer_id=customer_id).first()
    if profile is not None:
      FinanceLedgerEntry.objects.create(
        entry_type=FinanceLedgerEntry.TYPE_SUBSCRIPTION,
        status=FinanceLedgerEntry.STATUS_FAILED,
        amount=(data.get('amount_due') or 0) / 100,
        currency=(data.get('currency') or 'usd').upper(),
        professional=profile.user,
        description='Premium subscription payment failed',
        external_reference=data.get('id', ''),
        source='platform_subscription',
        professional_reference=profile.internal_reference_code,
        original_amount=(data.get('amount_due') or 0) / 100,
        original_currency=(data.get('currency') or 'usd').upper(),
        reporting_amount=(data.get('amount_due') or 0) / 100,
        reporting_currency=(data.get('currency') or 'usd').upper(),
        provider='stripe',
        metadata={'invoice_reference': data.get('id', '')},
        occurred_at=timezone.now(),
      )

  return HttpResponse(status=200)


class ProfessionalProfileView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [MultiPartParser, FormParser]

  def get(self, request):
    profile = request.user.professional_profile
    return Response(ProfessionalProfileSerializer(profile, context={'request': request}).data)

  def post(self, request):
    profile = request.user.professional_profile
    serializer = ProfessionalProfileSerializer(
      profile,
      data=request.data,
      partial=True,
      context={'request': request},
    )
    serializer.is_valid(raise_exception=True)

    try:
      serializer.save()
    except IntegrityError:
      # Narrow race window: two requests can both pass the pre-save
      # case-insensitive uniqueness check in validate_professional_id()
      # before either commits. Fail cleanly instead of a raw 500.
      return Response(
        {'message': 'Professional ID is already taken.'}, status=status.HTTP_400_BAD_REQUEST
      )

    return Response(
      {
        'profile': ProfessionalProfileSerializer(profile, context={'request': request}).data,
        'message': 'Professional profile saved successfully.',
      }
    )

  def put(self, request):
    return self.post(request)


class ProfessionalProfilePhotoRemoveView(APIView):
  """Dedicated, authorized action to remove a professional's custom profile
  picture. Deleting via the generic profile save endpoint is intentionally
  not supported for this field -- clearing a FileField through a partial
  multipart update is error-prone, so removal gets its own explicit action
  per the "Fixes after 1 Test Launch" spec (item 3)."""

  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request):
    profile = request.user.professional_profile
    file_name = profile.profile_photo.name if profile.profile_photo else ''

    if not file_name:
      return Response(
        {
          'profile': ProfessionalProfileSerializer(profile, context={'request': request}).data,
          'message': 'No profile picture to remove.',
        }
      )

    if default_storage.exists(file_name):
      default_storage.delete(file_name)

    profile.profile_photo = ''
    profile.save(update_fields=['profile_photo', 'updated_at'])

    return Response(
      {
        'profile': ProfessionalProfileSerializer(profile, context={'request': request}).data,
        'message': 'Profile picture removed.',
      }
    )


class ProfessionalProfileVisibilityView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request):
    profile = request.user.professional_profile
    visibility = request.data.get('visibility', {})

    if not isinstance(visibility, dict):
      return Response({'message': 'visibility must be an object.'}, status=status.HTTP_400_BAD_REQUEST)

    profile.profile_visibility = normalize_profile_visibility(visibility)
    profile.save(update_fields=['profile_visibility', 'updated_at'])

    return Response(
      {'profile_visibility': profile.profile_visibility, 'message': 'Profile visibility updated.'}
    )


class ProfessionalLogoutView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def post(self, request):
    Token.objects.filter(user=request.user).delete()
    return Response({'message': 'Logged out successfully.'})


class ProfessionalAccountView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request):
    existing = SupportIncident.objects.filter(
      reporter_professional=request.user,
      reporter_role=SupportIncident.ROLE_PROFESSIONAL,
      category=SupportIncident.CATEGORY_ACCOUNT,
      subject='Professional account deletion request',
      status__in=SupportIncident.ACTIVE_STATUSES,
    ).first()
    if existing:
      return Response({
        'incident_id': existing.incident_id,
        'message': 'Your account deletion request is already being reviewed by support.',
      })

    incident = SupportIncident.objects.create(
      reporter_role=SupportIncident.ROLE_PROFESSIONAL,
      reporter_professional=request.user,
      reporter_name=request.user.get_full_name() or request.user.username,
      reporter_email=request.user.email,
      category=SupportIncident.CATEGORY_ACCOUNT,
      subject='Professional account deletion request',
      description=(
        'The trainer requested deletion of the complete professional account. '
        'Support must verify identity and receive explicit confirmation before moving it to the 14-day Recycle Bin.'
      ),
      page_feature='Professional account settings',
      platform='web',
      priority=SupportIncident.PRIORITY_HIGH,
    )
    _notify_support_team(incident)
    return Response({
      'incident_id': incident.incident_id,
      'message': 'Deletion request sent to support. Your account remains active until identity and consent are verified.',
    }, status=status.HTTP_202_ACCEPTED)


class ProfessionalPasswordChangeView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  allow_outdated_legal = True

  def post(self, request):
    serializer = ProfessionalPasswordChangeSerializer(data=request.data, context={'user': request.user})
    serializer.is_valid(raise_exception=True)
    serializer.save(request.user)
    Token.objects.filter(user=request.user).delete()
    return Response({'message': 'Password changed successfully. Please sign in again.'})


class FormsGroupsOverviewView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    lead_forms = ProfessionalLeadForm.objects.filter(professional=request.user).order_by('created_at')
    lead_form = lead_forms.first()
    groups = ProfessionalGroup.objects.filter(professional=request.user, is_active=True).select_related('client_registration_form')
    submissions = LeadSubmission.objects.filter(lead_form__professional=request.user).select_related('client_access__group')
    pending_submissions = submissions.filter(status=LeadSubmission.STATUS_PENDING)
    approved_submissions = submissions.filter(status=LeadSubmission.STATUS_APPROVED)
    deleted_submissions = submissions.filter(status=LeadSubmission.STATUS_DELETED)

    return Response(
      {
        'has_lead_form': lead_form is not None,
        'lead_form': ProfessionalLeadFormSerializer(lead_form, context={'request': request}).data if lead_form else None,
        'lead_forms': ProfessionalLeadFormSerializer(lead_forms, many=True, context={'request': request}).data,
        'max_lead_forms': plan_limit(request.user, 'lead_forms'),
        'groups': ProfessionalGroupSerializer(groups, many=True).data,
        'pending_forms': LeadSubmissionSerializer(pending_submissions, many=True).data,
        'approved_forms': LeadSubmissionSerializer(approved_submissions, many=True).data,
        'deleted_forms': LeadSubmissionSerializer(deleted_submissions, many=True).data,
        'max_groups': plan_limit(request.user, 'groups'),
        'plan': professional_plan(request.user),
      }
    )


class ProfessionalLeadFormView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    form_id = request.data.get('form_id')
    lead_form = None
    if form_id:
      lead_form = ProfessionalLeadForm.objects.filter(id=form_id, professional=request.user).first()
      if lead_form is None:
        return Response({'message': 'Lead form not found.'}, status=status.HTTP_404_NOT_FOUND)
      try:
        feature_access.assert_item_not_locked(request.user, 'lead_forms', lead_form.id)
      except feature_access.FeatureAccessError as exc:
        return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)
    else:
      form_limit = plan_limit(request.user, 'lead_forms')
      current_count = ProfessionalLeadForm.objects.filter(professional=request.user).count()
      if form_limit is not None and current_count >= form_limit:
        return Response(
          {'message': f'Your current plan supports {form_limit} lead form{"s" if form_limit != 1 else ""}.'},
          status=status.HTTP_400_BAD_REQUEST,
        )
    serializer = ProfessionalLeadFormSerializer(
      lead_form,
      data=request.data,
      partial=lead_form is not None,
      context={'request': request},
    )
    serializer.is_valid(raise_exception=True)

    if lead_form:
      serializer.save()
    else:
      serializer.save(professional=request.user, public_slug=generate_unique_slug())
      plan_lock_status.bust_lock_status_cache(request.user)

    return Response(
      {
        'lead_form': ProfessionalLeadFormSerializer(serializer.instance, context={'request': request}).data,
        'message': 'Public lead form saved successfully.',
      },
      status=status.HTTP_201_CREATED if lead_form is None else status.HTTP_200_OK,
    )

  def put(self, request):
    return self.post(request)


class ProfessionalLeadFormStatusView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request):
    form_id = request.data.get('form_id')
    forms = ProfessionalLeadForm.objects.filter(professional=request.user)
    lead_form = forms.filter(id=form_id).first() if form_id else forms.first()

    if lead_form is None:
      return Response({'message': 'Create the lead form first.'}, status=status.HTTP_404_NOT_FOUND)

    lead_form.is_active = bool(request.data.get('is_active'))
    lead_form.save(update_fields=['is_active', 'updated_at'])
    state = 'enabled' if lead_form.is_active else 'disabled'

    return Response({
      'lead_form': ProfessionalLeadFormSerializer(lead_form, context={'request': request}).data,
      'message': f'Lead form {state}.',
    })


class ProfessionalGroupListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    group_limit = plan_limit(request.user, 'groups')
    if group_limit is not None and ProfessionalGroup.objects.filter(professional=request.user, is_active=True).count() >= group_limit:
      return Response({'message': 'Maximum groups limit reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ProfessionalGroupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    try:
      group = serializer.save(professional=request.user)
    except IntegrityError:
      return Response({'message': 'Group Name must be unique for this professional.'}, status=status.HTTP_400_BAD_REQUEST)

    plan_lock_status.bust_lock_status_cache(request.user)

    # Seed the universal client creation form so every group has one from the
    # start. A registration form is mandatory before a lead can be converted
    # into a client; the professional can still customise these fields afterwards.
    ClientRegistrationForm.objects.create(group=group, fields=default_client_registration_fields())

    return Response(
      {
        'group': ProfessionalGroupSerializer(group).data,
        'message': 'Group saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class ProfessionalGroupDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_group(self, request, group_id):
    return ProfessionalGroup.objects.filter(id=group_id, professional=request.user, is_active=True).first()

  def get(self, request, group_id):
    group = self.get_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'group': ProfessionalGroupSerializer(group).data})

  def put(self, request, group_id):
    group = self.get_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_item_not_locked(request.user, 'groups', group.id)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = ProfessionalGroupSerializer(group, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)

    try:
      serializer.save()
    except IntegrityError:
      return Response({'message': 'Group Name must be unique for this professional.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'group': ProfessionalGroupSerializer(group).data, 'message': 'Group updated successfully.'})


class PlanLockStatusView(APIView):
  """Read-only view of which of the professional's groups/lead forms/
  templates/categories/resources are currently active vs. locked under the
  plan-limit lock system, so the frontend can render lock badges/reasons
  (and know which ids are eligible for the reorder endpoint below)."""

  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    return Response({'lock_status': plan_lock_status.compute_lock_status(request.user)})


class PlanLockReorderView(APIView):
  """Lets a professional set their own priority order among their currently
  ACTIVE items of one of the five counted models. Locked items can never be
  reordered directly -- see plan_lock_status.reorder_active_items for the
  full rationale. Expects {'model_key': 'groups'|'lead_forms'|'templates'|
  'categories'|'resources', 'ordered_ids': [id, id, ...]}."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    model_key = request.data.get('model_key')
    ordered_ids = request.data.get('ordered_ids')

    if model_key not in plan_lock_status.MODEL_MAP:
      return Response({'message': 'Unknown model_key.'}, status=status.HTTP_400_BAD_REQUEST)

    if not isinstance(ordered_ids, list) or not ordered_ids:
      return Response({'message': 'ordered_ids must be a non-empty list.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      plan_lock_status.reorder_active_items(request.user, model_key, ordered_ids)
    except (plan_lock_status.ReorderError, ValueError, TypeError) as exc:
      return Response({'message': str(exc)}, status=status.HTTP_400_BAD_REQUEST)

    # Reordering categories changes which ones are active, which cascades to
    # which resources are locked -- reordering resources changes the resource
    # rank directly. Either way, heavy locked resources may need to move.
    if model_key in ('categories', 'resources'):
      resource_cold_storage.sync_resource_cold_storage(request.user)

    return Response({'lock_status': plan_lock_status.compute_lock_status(request.user), 'message': 'Order updated.'})


class ClientRegistrationFormView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, group_id):
    group = ProfessionalGroup.objects.filter(id=group_id, professional=request.user, is_active=True).first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    registration_form = getattr(group, 'client_registration_form', None)
    serializer = ClientRegistrationFormSerializer(
      registration_form,
      data=request.data,
      partial=registration_form is not None,
    )
    serializer.is_valid(raise_exception=True)
    serializer.save(group=group)

    return Response(
      {
        'registration_form': ClientRegistrationFormSerializer(serializer.instance).data,
        'message': 'Client registration form saved successfully.',
      },
      status=status.HTTP_201_CREATED if registration_form is None else status.HTTP_200_OK,
    )

  def put(self, request, group_id):
    return self.post(request, group_id)


class PublicLeadFormView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'public_registration'

  def get(self, request, public_slug):
    lead_form = ProfessionalLeadForm.objects.filter(
      public_slug=public_slug, is_active=True, professional__is_active=True,
      professional__professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_ACTIVE,
    ).select_related('professional').first()

    if lead_form is None:
      return Response({'message': 'Public form not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(PublicLeadFormSerializer(lead_form).data)

  def post(self, request, public_slug):
    lead_form = ProfessionalLeadForm.objects.filter(
      public_slug=public_slug, is_active=True, professional__is_active=True,
      professional__professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_ACTIVE,
    ).select_related('professional').first()

    if lead_form is None:
      return Response({'message': 'Public form not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = PublicLeadSubmissionSerializer(data=request.data, context={'lead_form': lead_form})
    serializer.is_valid(raise_exception=True)

    submission = LeadSubmission.objects.create(
      lead_form=lead_form,
      first_name=serializer.validated_data['first_name'],
      last_name=serializer.validated_data['last_name'],
      email=serializer.validated_data['email'],
      reference_id=generate_reference_id(),
      answers=serializer.validated_data['answers'],
    )

    send_mail_background(
      subject='Your RepRoot form reference ID',
      message=f'Your form has been submitted successfully. Your reference ID is {submission.reference_id}. Please save this for future communication.',
      from_email=None,
      recipient_list=[submission.email],
      fail_silently=False,
    )

    return Response(
      {
        'reference_id': submission.reference_id,
        'booking_access_token': str(submission.booking_access_token) if lead_form.introductory_meeting_enabled else '',
        'meeting_offer': PublicLeadFormSerializer(lead_form).data['meeting_offer'],
        'message': f'Your form has been submitted successfully. Your reference ID is {submission.reference_id}. Please save this for future communication. A copy has been sent to your email.',
      },
      status=status.HTTP_201_CREATED,
    )


class PendingLeadSubmissionView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request, submission_id):
    submission = LeadSubmission.objects.filter(
      id=submission_id,
      lead_form__professional=request.user,
      status=LeadSubmission.STATUS_PENDING,
      is_active=True,
    ).first()

    if submission is None:
      return Response({'message': 'Pending form request not found.'}, status=status.HTTP_404_NOT_FOUND)

    submission.status = LeadSubmission.STATUS_DELETED
    submission.is_active = False
    submission.deleted_at = timezone.now()
    submission.save(update_fields=['status', 'is_active', 'deleted_at', 'updated_at'])
    return Response({'message': 'Pending form request deleted.'})


class ClientAccessCreateView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, submission_id):
    client_limit = plan_limit(request.user, 'clients')
    if client_limit is not None and ClientAccess.objects.filter(professional=request.user, is_active=True).count() >= client_limit:
      return Response({'message': f'Your {professional_plan(request.user)["name"]} plan allows up to {client_limit} active clients.'}, status=status.HTTP_400_BAD_REQUEST)

    submission = LeadSubmission.objects.filter(
      id=submission_id,
      lead_form__professional=request.user,
      status=LeadSubmission.STATUS_PENDING,
      is_active=True,
    ).first()

    if submission is None:
      return Response({'message': 'Pending form request not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientAccessCreateSerializer(data=request.data, context={'professional': request.user})
    serializer.is_valid(raise_exception=True)
    group = ProfessionalGroup.objects.filter(id=serializer.validated_data['group_id'], professional=request.user, is_active=True).first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    registration_form = getattr(group, 'client_registration_form', None)

    if registration_form is None:
      return Response({'message': 'Create client registration form for this group first.'}, status=status.HTTP_400_BAD_REQUEST)

    registration_answers = serializer.validated_data.get('registration_answers', {})
    registration_answers['first_name'] = submission.first_name
    registration_answers['last_name'] = submission.last_name
    registration_answers['email'] = submission.email

    # Required fields are mandatory for the CLIENT to complete (from their
    # account, via an edit request the professional approves) - not for the professional
    # to fill in at creation time. So no required-answer validation here.

    has_portal_access = serializer.validated_data.get('has_portal_access', True)
    client_password = serializer.validated_data.get('password') or ''

    try:
      with transaction.atomic():
        client_access = ClientAccess.objects.create(
          professional=request.user,
          group=group,
          lead_submission=submission,
          reference_id=submission.reference_id,
          onboarding_method=ClientAccess.ONBOARDING_PUBLIC_LEAD,
          first_name=submission.first_name,
          last_name=submission.last_name,
          email=submission.email,
          has_portal_access=has_portal_access,
          username=serializer.validated_data['username'] if has_portal_access else None,
          temporary_password=make_password(client_password) if has_portal_access else None,
          photo=serializer.validated_data.get('photo', ''),
          registration_answers=registration_answers,
          must_change_password=has_portal_access,
        )
        submission.status = LeadSubmission.STATUS_APPROVED
        submission.converted_at = timezone.now()
        submission.save(update_fields=['status', 'converted_at', 'updated_at'])
    except IntegrityError:
      return Response(
        {'message': 'Same email or username already exists under this professional.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    bust_professional_data_usage_cache(request.user)
    credentials_sent = has_portal_access and serializer.validated_data.get('send_credentials', True)

    if credentials_sent:
      send_client_credentials(client_access, client_password)

    if not has_portal_access:
      message = 'Client record created without portal access.'
    elif credentials_sent:
      message = 'Client access created. Temporary credentials were sent to the client email.'
    else:
      message = 'Client access created. Temporary credentials were not emailed.'

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'credentials_sent': credentials_sent,
        'message': message,
      },
      status=status.HTTP_201_CREATED,
    )


class ManualClientAccessCreateView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    client_limit = plan_limit(request.user, 'clients')
    if client_limit is not None and ClientAccess.objects.filter(professional=request.user, is_active=True).count() >= client_limit:
      return Response({'message': f'Your {professional_plan(request.user)["name"]} plan allows up to {client_limit} active clients.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ClientAccessCreateSerializer(data=request.data, context={'professional': request.user})
    serializer.is_valid(raise_exception=True)
    group = ProfessionalGroup.objects.filter(
      id=serializer.validated_data['group_id'], professional=request.user, is_active=True
    ).select_related('client_registration_form').first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    registration_form = getattr(group, 'client_registration_form', None)
    registration_form_required = registration_form is None or registration_form.is_mandatory

    if registration_form_required and (registration_form is None or not registration_form.is_active):
      return Response({'message': 'This group needs an active client registration form.'}, status=status.HTTP_400_BAD_REQUEST)

    answers = dict(serializer.validated_data.get('registration_answers') or {})
    registration_submission = None
    registration_submission_id = serializer.validated_data.get('registration_submission_id')

    if registration_submission_id:
      registration_submission = GroupRegistrationSubmission.objects.filter(
        id=registration_submission_id,
        group=group,
        status=GroupRegistrationSubmission.STATUS_PENDING,
      ).first()

      if registration_submission is None:
        return Response({'message': 'Pending group registration was not found.'}, status=status.HTTP_404_NOT_FOUND)

      answers = dict(registration_submission.answers or {})

    from .serializers import validate_required_answers

    if registration_form is not None and registration_form.is_mandatory:
      validate_required_answers(registration_form.fields, answers)

    first_name = str(answers.get('first_name', '')).strip()
    last_name = str(answers.get('last_name', '')).strip()
    email = str(answers.get('email', '')).strip().lower()

    if not first_name or not last_name or not email:
      return Response({'message': 'First name, last name, and email are required.'}, status=status.HTTP_400_BAD_REQUEST)

    has_portal_access = serializer.validated_data.get('has_portal_access', True)
    temporary_password = serializer.validated_data.get('password') or ''
    onboarding_method = (
      ClientAccess.ONBOARDING_GROUP_REGISTRATION
      if registration_submission
      else ClientAccess.ONBOARDING_MANUAL
    )

    try:
      with transaction.atomic():
        client_kwargs = {
          'professional': request.user,
          'group': group,
          'registration_submission': registration_submission,
          'onboarding_method': onboarding_method,
          'first_name': first_name,
          'last_name': last_name,
          'email': email,
          'has_portal_access': has_portal_access,
          'username': serializer.validated_data['username'] if has_portal_access else None,
          'temporary_password': make_password(temporary_password) if has_portal_access else None,
          'photo': serializer.validated_data.get('photo', ''),
          'registration_answers': answers,
          'must_change_password': has_portal_access,
        }

        if registration_submission:
          client_kwargs['reference_id'] = registration_submission.reference_id

        client_access = ClientAccess.objects.create(
          **client_kwargs,
        )

        if registration_submission:
          registration_submission.status = GroupRegistrationSubmission.STATUS_CONVERTED
          registration_submission.converted_at = timezone.now()
          registration_submission.save(update_fields=['status', 'converted_at', 'updated_at'])
    except IntegrityError:
      return Response(
        {'message': 'The email or username already exists under this professional.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    bust_professional_data_usage_cache(request.user)
    credentials_sent = has_portal_access and serializer.validated_data.get('send_credentials', True)

    if credentials_sent:
      send_client_credentials(client_access, temporary_password)

    if not has_portal_access:
      message = 'Client record created without portal access.'
    elif credentials_sent:
      message = 'Client account created and temporary credentials emailed.'
    else:
      message = 'Client account created. Temporary credentials were not emailed.'

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'temporary_password': temporary_password if has_portal_access else None,
        'credentials_sent': credentials_sent,
        'message': message,
      },
      status=status.HTTP_201_CREATED,
    )


class PublicGroupRegistrationView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'public_registration'

  def _form(self, public_slug):
    return ClientRegistrationForm.objects.filter(
      public_slug=public_slug,
      is_active=True,
      group__is_active=True,
      group__professional__is_active=True,
      group__professional__professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_ACTIVE,
    ).select_related('group', 'group__professional').first()

  def get(self, request, public_slug):
    registration_form = self._form(public_slug)

    if registration_form is None:
      return Response({'message': 'Registration form not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(
      {
        'group': {'id': registration_form.group_id, 'name': registration_form.group.name},
        'professional_name': registration_form.group.professional.get_full_name() or registration_form.group.professional.username,
        'fields': registration_form.fields,
      }
    )

  def post(self, request, public_slug):
    registration_form = self._form(public_slug)

    if registration_form is None:
      return Response({'message': 'Registration form not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = PublicGroupRegistrationSerializer(
      data=request.data,
      context={'registration_form': registration_form},
    )
    serializer.is_valid(raise_exception=True)
    submission = GroupRegistrationSubmission.objects.create(
      group=registration_form.group,
      first_name=serializer.validated_data['first_name'],
      last_name=serializer.validated_data['last_name'],
      email=serializer.validated_data['email'],
      answers=serializer.validated_data['answers'],
    )

    send_mail_background(
      subject=f'Your {registration_form.group.name} registration',
      message=(
        f'Your registration was submitted for professional review.\n\n'
        f'Reference ID: {submission.reference_id}\n\n'
        f'Your professional will send account credentials after review.'
      ),
      from_email=None,
      recipient_list=[submission.email],
      fail_silently=False,
    )

    return Response(
      {'reference_id': submission.reference_id, 'message': 'Registration submitted for professional review.'},
      status=status.HTTP_201_CREATED,
    )


class GroupClientAccessListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, group_id):
    group = ProfessionalGroup.objects.filter(id=group_id, professional=request.user, is_active=True).first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    # Include suspended clients too so the professional can see status and reactivate.
    clients = ClientAccess.objects.filter(professional=request.user, group=group).order_by('-is_active', '-created_at')
    registration_submissions = group.registration_submissions.filter(
      status=GroupRegistrationSubmission.STATUS_PENDING
    )

    return Response(
      {
        'group': ProfessionalGroupSerializer(group).data,
        'clients': ClientAccessSerializer(clients, many=True).data,
        'registration_submissions': GroupRegistrationSubmissionSerializer(registration_submissions, many=True).data,
      }
    )


class GroupRegistrationSubmissionDeclineView(APIView):
  """Decline a pending group registration request (Pending Users tab).

  Distinct from approval (ManualClientAccessCreateView with
  registration_submission_id): no client account is created, and the
  submission moves out of Pending Users without becoming Approved Users.
  """

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, group_id, submission_id):
    submission = GroupRegistrationSubmission.objects.filter(
      id=submission_id,
      group_id=group_id,
      group__professional=request.user,
      status=GroupRegistrationSubmission.STATUS_PENDING,
    ).first()

    if submission is None:
      return Response({'message': 'Pending registration request not found.'}, status=status.HTTP_404_NOT_FOUND)

    submission.status = GroupRegistrationSubmission.STATUS_DELETED
    submission.save(update_fields=['status', 'updated_at'])

    return Response({'message': 'Registration request declined.'})


class ClientAccessDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_client(self, request, client_id):
    # No is_active filter: the professional can open a suspended client to reactivate.
    return ClientAccess.objects.filter(
      id=client_id,
      professional=request.user,
    ).select_related('group', 'lead_submission', 'professional').first()

  def get(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    group = client_access.group
    registration_form = getattr(group, 'client_registration_form', None)
    pending_change_request = client_access.detail_change_requests.filter(
      status=ClientDetailChangeRequest.STATUS_PENDING,
      request_type=ClientDetailChangeRequest.TYPE_PROFILE_EDIT,
    ).first()

    return Response(
      {
        'client': {
          **ClientAccessSerializer(client_access).data,
          'professional_notes': client_access.professional_notes,
        },
        'group': ProfessionalGroupSerializer(group).data,
        'registration_fields': registration_form.fields if registration_form and registration_form.is_active else [],
        'lead_submission': (
          LeadSubmissionSerializer(client_access.lead_submission).data if client_access.lead_submission else None
        ),
        'professional_notes': client_access.professional_notes,
        'professional_notes_updated_at': serialize_datetime(client_access.professional_notes_updated_at),
        'pending_change_request': (
          ClientDetailChangeRequestSerializer(pending_change_request).data if pending_change_request else None
        ),
      }
    )

  def put(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    registration_answers = dict(client_access.registration_answers or {})
    submitted_answers = request.data.get('registration_answers')

    if submitted_answers is not None:
      if not isinstance(submitted_answers, dict):
        return Response({'message': 'registration_answers must be an object.'}, status=status.HTTP_400_BAD_REQUEST)
      registration_answers.update(submitted_answers)

    first_name = str(request.data.get('first_name', client_access.first_name)).strip()
    last_name = str(request.data.get('last_name', client_access.last_name)).strip()
    email = str(request.data.get('email', client_access.email)).strip().lower()
    username_default = client_access.username or ''
    username = str(request.data.get('username', username_default)).strip()

    if not first_name or not last_name or not email:
      return Response({'message': 'First name, last name, and email are required.'}, status=status.HTTP_400_BAD_REQUEST)

    if client_access.has_portal_access and not username:
      return Response({'message': 'Username is required for clients with portal access.'}, status=status.HTTP_400_BAD_REQUEST)

    if username and ClientAccess.objects.filter(professional=request.user, username=username).exclude(id=client_access.id).exists():
      return Response({'message': 'Username is already used by another client.'}, status=status.HTTP_400_BAD_REQUEST)

    if ClientAccess.objects.filter(professional=request.user, email=email).exclude(id=client_access.id).exists():
      return Response({'message': 'Email is already used by another client.'}, status=status.HTTP_400_BAD_REQUEST)

    client_access.first_name = first_name
    client_access.last_name = last_name
    client_access.email = email

    if client_access.has_portal_access:
      client_access.username = username

    client_access.registration_answers = registration_answers

    if 'is_active' in request.data:
      client_access.is_active = bool(request.data.get('is_active'))

    client_access.save(
      update_fields=['first_name', 'last_name', 'email', 'username', 'registration_answers', 'is_active', 'updated_at']
    )

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Client information updated.'})


class ClientAccessGrantPortalAccessView(APIView):
  """Grant portal login access to an existing info-only (has_portal_access=False) client."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    if client_access.has_portal_access:
      return Response({'message': 'This client already has portal access.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ClientPortalAccessGrantSerializer(
      data=request.data, context={'professional': request.user, 'client_access': client_access}
    )
    serializer.is_valid(raise_exception=True)

    temporary_password = serializer.validated_data['password']

    client_access.username = serializer.validated_data['username']
    client_access.temporary_password = make_password(temporary_password)
    client_access.has_portal_access = True
    client_access.must_change_password = True
    client_access.save(
      update_fields=['username', 'temporary_password', 'has_portal_access', 'must_change_password', 'updated_at']
    )

    credentials_sent = serializer.validated_data.get('send_credentials', True)

    if credentials_sent:
      send_client_credentials(client_access, temporary_password)

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'temporary_password': temporary_password,
        'credentials_sent': credentials_sent,
        'message': (
          'Portal access granted and credentials emailed.'
          if credentials_sent
          else 'Portal access granted. Credentials were not emailed.'
        ),
      }
    )


class ClientAccessRevokePortalAccessView(APIView):
  """Disable portal login access for a client that currently has it.

  Non-destructive: username/temporary_password are left in place so access
  can be re-granted later. `ClientTokenAuthentication` and `ClientLoginSerializer`
  already gate on `has_portal_access`, so flipping this flag immediately locks
  the client out without needing to revoke any issued token separately.
  """

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not client_access.has_portal_access:
      return Response({'message': 'This client does not currently have portal access.'}, status=status.HTTP_400_BAD_REQUEST)

    client_access.has_portal_access = False
    client_access.save(update_fields=['has_portal_access', 'updated_at'])

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'message': 'Portal access disabled. The client can no longer log in.',
      }
    )


class ClientProfessionalNotesView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    client_access.professional_notes = str(request.data.get('notes', '')).strip()
    client_access.professional_notes_updated_at = timezone.now()
    client_access.save(update_fields=['professional_notes', 'professional_notes_updated_at', 'updated_at'])

    return Response(
      {
        'professional_notes': client_access.professional_notes,
        'professional_notes_updated_at': serialize_datetime(client_access.professional_notes_updated_at),
        'message': 'Professional notes saved.',
      }
    )

class ClientAccessPhotoView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientPhotoUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access.photo = serializer.validated_data['photo']
    client_access.save(update_fields=['photo', 'updated_at'])

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Client photo updated.'})


class ClientAdditionalInfoView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientAdditionalInfoUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access.additional_info = serializer.validated_data['additional_info']

    if 'additional_info_shared' in serializer.validated_data:
      client_access.additional_info_shared = serializer.validated_data['additional_info_shared']

    client_access.save(update_fields=['additional_info', 'additional_info_shared', 'updated_at'])

    if client_access.additional_info_shared:
      notify_client(
        client_access,
        category='clients',
        event_type='client.additional_info_updated',
        title='Your information was updated',
        body='Your trainer updated information shared with you.',
        action_url='/client/profile?tab=professional&professionalTab=additional',
        payload={'client_id': client_access.id},
      )

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Additional information saved.'})


class ClientReminderListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    cutoff = visible_client_data_cutoff(request.user)
    return Response({'reminders': ClientReminderSerializer(client.reminders.filter(date__gte=cutoff.date()), many=True).data})

  def post(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientReminderSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    reminder = serializer.save(professional=request.user, client=client)

    return Response(
      {'reminder': ClientReminderSerializer(reminder).data, 'message': 'Reminder scheduled.'},
      status=status.HTTP_201_CREATED,
    )


class ClientReminderDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def _reminder(self, request, reminder_id):
    return ClientReminder.objects.filter(id=reminder_id, professional=request.user).select_related('client').first()

  def put(self, request, reminder_id):
    reminder = self._reminder(request, reminder_id)

    if reminder is None:
      return Response({'message': 'Reminder not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientReminderSerializer(reminder, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()

    return Response({'reminder': ClientReminderSerializer(reminder).data, 'message': 'Reminder updated.'})

  def delete(self, request, reminder_id):
    reminder = self._reminder(request, reminder_id)

    if reminder is None:
      return Response({'message': 'Reminder not found.'}, status=status.HTTP_404_NOT_FOUND)

    reminder.delete()
    return Response({'message': 'Reminder deleted.'})


class ProfessionalUpcomingRemindersView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    cutoff = visible_client_data_cutoff(request.user)
    reminders_queryset = ClientReminder.objects.filter(
      professional=request.user, date__gte=cutoff.date()
    ).select_related('client')
    pending = list(reminders_queryset.filter(status=ClientReminder.STATUS_PENDING))
    completed = reminders_queryset.filter(status=ClientReminder.STATUS_DONE)
    pending_profile_edits_queryset = ClientDetailChangeRequest.objects.filter(
      client__professional=request.user,
      status=ClientDetailChangeRequest.STATUS_PENDING,
    ).select_related('client', 'client__group').order_by('-created_at')
    pending_profile_edit_count = pending_profile_edits_queryset.count()
    pending_profile_edits = list(
      pending_profile_edits_queryset[:50]
    )
    now = timezone.localtime()

    def reminder_datetime(reminder):
      naive = datetime.combine(reminder.date, reminder.time or time(hour=23, minute=59))
      return timezone.make_aware(naive, timezone.get_current_timezone())

    pending.sort(key=reminder_datetime)

    overdue_count = sum(1 for reminder in pending if reminder_datetime(reminder) < now)

    def due_within(delta):
      cutoff = now + delta
      return sum(1 for reminder in pending if now <= reminder_datetime(reminder) <= cutoff)

    visible_reminders = pending[:50]
    nearest_upcoming = next(
      (reminder for reminder in visible_reminders if reminder_datetime(reminder) >= now),
      None,
    )

    def changed_field_count(change_request):
      current_answers = change_request.client.registration_answers or {}
      return sum(
        1
        for key, value in (change_request.proposed_answers or {}).items()
        if key not in ('first_name', 'last_name', 'email')
        and str(current_answers.get(key, '')).strip() != str(value or '').strip()
      )

    return Response(
      {
        'reminders': ClientReminderSerializer(visible_reminders, many=True).data,
        'profile_edits': [
          {
            'id': change_request.id,
            'client': change_request.client_id,
            'client_name': f'{change_request.client.first_name} {change_request.client.last_name}'.strip(),
            'group_name': change_request.client.group.name,
            'request_type': change_request.request_type,
            'proposed_field_count': changed_field_count(change_request),
            'client_note': change_request.client_note,
            'created_at': serialize_datetime(change_request.created_at),
          }
          for change_request in pending_profile_edits
        ],
        'summary': {
          'total_pending': len(pending),
          'overdue': overdue_count,
          'due_24_hours': due_within(timedelta(hours=24)),
          'due_7_days': due_within(timedelta(days=7)),
          'total_completed': completed.count(),
          'completed_last_7_days': completed.filter(updated_at__gte=now - timedelta(days=7)).count(),
          'pending_profile_edits': pending_profile_edit_count,
          'nearest_date': nearest_upcoming.date.isoformat() if nearest_upcoming else '',
        },
      }
    )


class ClientProgressListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    cutoff = visible_client_data_cutoff(request.user)
    return Response({'progress': ProgressEntrySerializer(client.progress_entries.filter(created_at__gte=cutoff), many=True).data})

  def post(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ProgressEntrySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    entry = serializer.save(
      professional=request.user,
      client=client,
      created_by=request.user.get_full_name() or request.user.username,
    )

    return Response(
      {'progress': ProgressEntrySerializer(entry).data, 'message': 'Progress record saved.'},
      status=status.HTTP_201_CREATED,
    )


class ClientProgressDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, entry_id):
    entry = ProgressEntry.objects.filter(
      id=entry_id, client__professional=request.user, created_at__gte=visible_client_data_cutoff(request.user)
    ).first()

    if entry is None:
      return Response({'message': 'Progress record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ProgressEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()

    return Response({'progress': ProgressEntrySerializer(entry).data, 'message': 'Progress record updated.'})

  def delete(self, request, entry_id):
    entry = ProgressEntry.objects.filter(
      id=entry_id, client__professional=request.user, created_at__gte=visible_client_data_cutoff(request.user)
    ).first()

    if entry is None:
      return Response({'message': 'Progress record not found.'}, status=status.HTTP_404_NOT_FOUND)

    entry.delete()
    return Response({'message': 'Progress record deleted.'})


class ProfessionalClientChangeRequestActionView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, client_id, request_id):
    change_request = ClientDetailChangeRequest.objects.filter(
      id=request_id,
      client_id=client_id,
      client__professional=request.user,
      status=ClientDetailChangeRequest.STATUS_PENDING,
    ).select_related('client').first()

    if change_request is None:
      return Response({'message': 'Pending change request not found.'}, status=status.HTTP_404_NOT_FOUND)

    action = str(request.data.get('action', '')).strip().lower()
    note = str(request.data.get('note', '')).strip()

    if action not in ('approve', 'reject'):
      return Response({'message': 'Action must be approve or reject.'}, status=status.HTTP_400_BAD_REQUEST)

    client_access = change_request.client

    if action == 'approve' and change_request.request_type == ClientDetailChangeRequest.TYPE_PROFILE_EDIT:
      # Preserve the immutable core identity fields; apply everything else.
      answers = dict(client_access.registration_answers or {})
      for key, value in (change_request.proposed_answers or {}).items():
        if key in ('first_name', 'last_name', 'email'):
          continue
        answers[key] = value

      client_access.registration_answers = answers
      client_access.save(update_fields=['registration_answers', 'updated_at'])
      change_request.status = ClientDetailChangeRequest.STATUS_APPROVED
    elif action == 'approve':
      client_access.is_active = False
      client_access.save(update_fields=['is_active', 'updated_at'])
      ClientAuthToken.objects.filter(client=client_access).delete()
      change_request.status = ClientDetailChangeRequest.STATUS_APPROVED
    else:
      change_request.status = ClientDetailChangeRequest.STATUS_REJECTED

    change_request.professional_note = note
    change_request.reviewed_at = timezone.now()
    change_request.save(update_fields=['status', 'professional_note', 'reviewed_at'])

    return Response(
      {
        'change_request': ClientDetailChangeRequestSerializer(change_request).data,
        'client': ClientAccessSerializer(client_access).data,
        'message': f'Change request {change_request.status}.',
      }
    )


class ClientProfessionalLookupView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def post(self, request):
    serializer = ClientProfessionalLookupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    professional_id = serializer.validated_data['professional_id']
    profile = ProfessionalProfile.objects.select_related('user').filter(professional_id__iexact=professional_id).first()

    if profile is None:
      return Response({'message': 'Professional ID not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(
      {
        'professional_id': profile.professional_id,
        'professional_name': profile.user.get_full_name() or profile.user.username,
        'message': 'Professional ID found.',
      }
    )


class ProfessionalDirectoryView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def get(self, request):
    search = str(request.query_params.get('search', '')).strip()
    if len(search) < 3:
      return Response({'professionals': []})

    profiles = (
      ProfessionalProfile.objects.select_related('user')
      .filter(user__is_active=True, is_locked=False)
      .exclude(professional_id__isnull=True)
      .exclude(professional_id__exact='')
    )

    profiles = profiles.filter(
      Q(professional_id__icontains=search)
      | Q(user__first_name__icontains=search)
      | Q(user__last_name__icontains=search)
    )

    profiles = profiles.order_by('user__first_name', 'user__last_name', 'professional_id')[:5]

    professionals = [
      {
        'professional_id': profile.professional_id,
        'professional_name': profile.user.get_full_name() or profile.user.username,
      }
      for profile in profiles
    ]

    return Response({'professionals': professionals})


class ClientAccessStatusView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    client_access.is_active = bool(request.data.get('is_active'))
    client_access.save(update_fields=['is_active', 'updated_at'])
    state = 'reactivated' if client_access.is_active else 'suspended'

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': f'Client access {state}.'})


class ClientAccessPasswordResetView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not client_access.has_portal_access:
      return Response(
        {'message': 'This client does not have portal access. Grant portal access first.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    # Consistent with manual client creation (Option A): the professional defines
    # the temporary password. A generated one is used only when none is sent.
    temporary_password = str(request.data.get('password', '') or '').strip()

    if temporary_password:
      from rest_framework.serializers import ValidationError as SerializerValidationError

      from .serializers import validate_password_strength

      try:
        validate_password_strength(temporary_password)
      except SerializerValidationError as error:
        return Response({'message': error.detail[0]}, status=status.HTTP_400_BAD_REQUEST)
    else:
      temporary_password = f'{get_random_string(8)}!7'

    client_access.temporary_password = make_password(temporary_password)
    client_access.must_change_password = True
    client_access.save(update_fields=['temporary_password', 'must_change_password', 'updated_at'])

    send_mail_background(
      subject='Your RepRoot client password reset',
      message=(
        f'Your professional reset your RepRoot client password.\n\n'
        f'Username: {client_access.username}\n'
        f'Temporary password: {temporary_password}\n\n'
        f'Please log in and change your password.'
      ),
      from_email=None,
      recipient_list=[client_access.email],
      fail_silently=False,
    )

    return Response(
      {
        'temporary_password': temporary_password,
        'message': 'Client password reset email sent.',
      }
    )


class ClientAccessResetView(APIView):
  """Wipe a client's activity (templates, entries, chat, reminders, progress,
  additional info, notes) while keeping their profile / registration identity."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    confirmation = str(request.data.get('confirmation') or '').strip()
    current_password = str(request.data.get('current_password') or '')
    reason = str(request.data.get('reason') or '').strip()
    # Info-only clients have no username, so the reference ID doubles as the
    # confirmation phrase for them.
    expected_confirmation = client_access.username or client_access.reference_id
    if confirmation != expected_confirmation:
      return Response({'message': f'Type {expected_confirmation} exactly to confirm the reset.'}, status=status.HTTP_400_BAD_REQUEST)
    if not check_password(current_password, request.user.password):
      return Response({'message': 'Your current professional password is incorrect.'}, status=status.HTTP_400_BAD_REQUEST)
    if not reason:
      return Response({'message': 'A reset reason is required.'}, status=status.HTTP_400_BAD_REQUEST)

    chat_file_names = list(
      ChatMessage.objects.filter(client=client_access).exclude(image='').values_list('image', flat=True)
    )
    with transaction.atomic():
      deleted_counts = {
        'assignments': TemplateAssignment.objects.filter(client=client_access).count(),
        'tracking_entries': TrackingEntry.objects.filter(client=client_access).count(),
        'chat_messages': ChatMessage.objects.filter(client=client_access).count(),
        'reminders': ClientReminder.objects.filter(client=client_access).count(),
        'progress_entries': ProgressEntry.objects.filter(client=client_access).count(),
        'change_requests': ClientDetailChangeRequest.objects.filter(client=client_access).count(),
      }
      TemplateAssignment.objects.filter(client=client_access).delete()
      TrackingEntry.objects.filter(client=client_access).delete()
      ChatMessage.objects.filter(client=client_access).delete()
      ClientReminder.objects.filter(client=client_access).delete()
      ProgressEntry.objects.filter(client=client_access).delete()
      ClientDetailChangeRequest.objects.filter(client=client_access).delete()

      client_access.additional_info = []
      client_access.additional_info_shared = False
      client_access.professional_notes = ''
      client_access.professional_notes_updated_at = None
      client_access.save(
        update_fields=[
          'additional_info',
          'additional_info_shared',
          'professional_notes',
          'professional_notes_updated_at',
          'updated_at',
        ]
      )
      ClientAuthToken.objects.filter(client=client_access).delete()
      ClientResetAudit.objects.create(
        professional=request.user, client=client_access,
        professional_reference=request.user.professional_profile.internal_reference_code,
        client_reference=client_access.reference_id, client_username=client_access.username or '',
        reason=reason, deleted_counts=deleted_counts,
      )

    for file_name in chat_file_names:
      if file_name and default_storage.exists(file_name):
        default_storage.delete(file_name)

    bust_professional_data_usage_cache(request.user)
    return Response(
      {
        'client': ClientAccessSerializer(client_access).data,
        'message': "Client reset. Templates, entries, chat, and notes were cleared; profile details were kept.",
      }
    )


class ClientAccessExportView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, client_id):
    client = ClientAccess.objects.filter(id=client_id, professional=request.user).first()
    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)
    payload = {
      'exported_at': timezone.now(),
      'client': {
        'reference_id': client.reference_id, 'first_name': client.first_name, 'last_name': client.last_name,
        'email': client.email, 'username': client.username, 'group': client.group.name,
        'registration_answers': client.registration_answers, 'additional_info': client.additional_info,
        'professional_notes': client.professional_notes, 'created_at': client.created_at,
      },
      # Export includes hidden-but-still-stored operational history.
      'tracking_entries': list(client.tracking_entries.values()),
      'progress_entries': list(client.progress_entries.values()),
      'reminders': list(client.reminders.values()),
      'chat_messages': list(client.chat_messages.values('id', 'sender', 'text', 'image', 'created_at')),
      'template_assignments': list(client.template_assignments.values('id', 'template_id', 'template__name', 'assigned_at')),
      'payment_requests': list(client.payment_requests.values()),
      'payment_records': list(client.payment_records.values()),
    }
    archive = tempfile.TemporaryFile()
    with zipfile.ZipFile(archive, mode='w', compression=zipfile.ZIP_DEFLATED) as bundle:
      bundle.writestr('client-data.json', json.dumps(payload, default=str, indent=2))
      for message in client.chat_messages.exclude(image=''):
        if not message.image or not default_storage.exists(message.image.name):
          continue
        with default_storage.open(message.image.name, 'rb') as stored_file:
          safe_name = message.image.name.replace('..', '').lstrip('/\\')
          bundle.writestr(f'chat-attachments/{message.pk}-{safe_name.split("/")[-1]}', stored_file.read())
    archive.seek(0)
    return FileResponse(
      archive, as_attachment=True, filename=f'reproot-{client.reference_id}-export.zip',
      content_type='application/zip',
    )


class ClientAccessDeleteView(APIView):
  """Delete a client account, moving the client plus their chat/tracking/progress/
  reminders/template assignments into the Recycle Bin as one bundled entry —
  deleting a whole client is consequential enough that it should always be
  fully restorable, unlike smaller individual deletes."""

  permission_classes = [ProfessionalAccessPermission]

  def delete(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    confirmation = str(request.data.get('confirmation') or '').strip()
    current_password = str(request.data.get('current_password') or '')
    reason = str(request.data.get('reason') or '').strip()
    expected_confirmation = client_access.username or client_access.reference_id

    if confirmation != expected_confirmation:
      return Response(
        {'message': f'Type {expected_confirmation} exactly to confirm account deletion.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    if not check_password(current_password, request.user.password):
      return Response(
        {'message': 'Your current professional password is incorrect.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    if not reason:
      return Response({'message': 'A deletion reason is required.'}, status=status.HTTP_400_BAD_REQUEST)

    with transaction.atomic():
      lead_submission = client_access.lead_submission

      if lead_submission:
        # Free the roster slot: retire the original lead as deleted.
        lead_submission.status = LeadSubmission.STATUS_DELETED
        lead_submission.is_active = False
        lead_submission.deleted_at = timezone.now()
        lead_submission.save(update_fields=['status', 'is_active', 'deleted_at', 'updated_at'])

      registration_submission = client_access.registration_submission

      if registration_submission:
        registration_submission.status = GroupRegistrationSubmission.STATUS_DELETED
        registration_submission.save(update_fields=['status', 'updated_at'])

      recycle_bin.soft_delete_client_account(client_access)

    bust_professional_data_usage_cache(request.user)
    return Response({'message': 'Client account moved to Recycle Bin.'})


class ProfessionalResourceCategoryListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    categories = ResourceCategory.objects.filter(professional=request.user)
    return Response({'categories': ResourceCategorySerializer(categories, many=True).data})

  def post(self, request):
    category_limit = plan_limit(request.user, 'categories')

    if category_limit is not None and ResourceCategory.objects.filter(professional=request.user).count() >= category_limit:
      return Response({'message': 'The Version 1 category limit has been reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ResourceCategorySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    subcategory_limit = plan_limit(request.user, 'subcategories_per_category')

    if subcategory_limit is not None and len(serializer.validated_data.get('subcategories', [])) > subcategory_limit:
      return Response({'message': f'Each category can contain up to {subcategory_limit} subcategories.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      category = serializer.save(professional=request.user)
    except IntegrityError:
      return Response({'message': 'Category name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    plan_lock_status.bust_lock_status_cache(request.user)

    return Response(
      {
        'category': ResourceCategorySerializer(category).data,
        'message': 'Category saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class ProfessionalResourceCategoryDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_category(self, request, category_id):
    return ResourceCategory.objects.filter(id=category_id, professional=request.user).first()

  def put(self, request, category_id):
    category = self.get_category(request, category_id)

    if category is None:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_item_not_locked(request.user, 'categories', category.id)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = ResourceCategorySerializer(category, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)

    subcategory_limit = plan_limit(request.user, 'subcategories_per_category')
    next_subcategories = serializer.validated_data.get('subcategories', category.subcategories)

    if subcategory_limit is not None and len(next_subcategories) > subcategory_limit:
      return Response({'message': f'Each category can contain up to {subcategory_limit} subcategories.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      serializer.save()
    except IntegrityError:
      return Response({'message': 'Category name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'category': ResourceCategorySerializer(category).data, 'message': 'Category updated successfully.'})

  def delete(self, request, category_id):
    category = self.get_category(request, category_id)

    if category is None:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      category.delete()
    except ProtectedError:
      return Response(
        {'message': 'Category still has resources. Move or delete them first.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    plan_lock_status.bust_lock_status_cache(request.user)
    resource_cold_storage.sync_resource_cold_storage(request.user)

    return Response({'message': 'Category deleted.'})


class ProfessionalResourceListView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [MultiPartParser, FormParser, JSONParser]

  def get(self, request):
    resources = ProfessionalResource.objects.filter(professional=request.user).select_related('category')
    resource_limit = plan_limit(request.user, 'resources')
    return Response(
      {
        'resources': ProfessionalResourceSerializer(resources, many=True, context={'request': request}).data,
        'usage': {'used': resources.count(), 'limit': resource_limit},
      }
    )

  def post(self, request):
    resource_limit = plan_limit(request.user, 'resources')

    if resource_limit is not None and ProfessionalResource.objects.filter(professional=request.user).count() >= resource_limit:
      return Response(
        {'message': 'You have reached the Version 1 resource limit.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    serializer = ProfessionalResourceSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)
    category = serializer.validated_data.get('category')

    if category is None or category.professional_id != request.user.id:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    resource = serializer.save(professional=request.user)
    plan_lock_status.bust_lock_status_cache(request.user)
    # Covers the edge case of a resource created directly into an already-
    # locked category -- it should land in cold storage immediately, not
    # wait for the next unrelated lock-status change to notice it.
    resource_cold_storage.sync_resource_cold_storage(request.user)

    return Response(
      {
        'resource': ProfessionalResourceSerializer(resource, context={'request': request}).data,
        'message': 'Resource saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class ProfessionalResourceDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [MultiPartParser, FormParser, JSONParser]

  def get_resource(self, request, resource_id):
    return ProfessionalResource.objects.filter(id=resource_id, professional=request.user).select_related('category').first()

  def get(self, request, resource_id):
    resource = self.get_resource(request, resource_id)

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'resource': ProfessionalResourceSerializer(resource, context={'request': request}).data})

  def put(self, request, resource_id):
    resource = self.get_resource(request, resource_id)

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_item_not_locked(request.user, 'resources', resource.id)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = ProfessionalResourceSerializer(resource, data=request.data, partial=True, context={'request': request})
    serializer.is_valid(raise_exception=True)
    category = serializer.validated_data.get('category')

    if category is not None and category.professional_id != request.user.id:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer.save()

    return Response(
      {
        'resource': ProfessionalResourceSerializer(resource, context={'request': request}).data,
        'message': 'Resource updated successfully.',
      }
    )

  def delete(self, request, resource_id):
    resource = self.get_resource(request, resource_id)

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    recycle_bin.soft_delete_resource(resource)
    plan_lock_status.bust_lock_status_cache(request.user)
    resource_cold_storage.sync_resource_cold_storage(request.user)
    return Response({'message': 'Resource moved to Recycle Bin.'})


class ResourceAssignedClientsView(APIView):
  """Lists which clients currently have this resource shared with them via a
  template assignment. Used by the professional-facing "locked resource"
  view -- a locked resource that's still shared with clients needs to show
  exactly who's affected, with a way to unassign it (see the two views
  below), per the plan-lock design's 3.2."""

  permission_classes = [ProfessionalAccessPermission]

  def get_resource(self, request, resource_id):
    return ProfessionalResource.objects.filter(id=resource_id, professional=request.user).first()

  def get(self, request, resource_id):
    resource = self.get_resource(request, resource_id)

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignments = (
      resource.template_assignments.select_related('client', 'template')
      .order_by('client__first_name', 'client__last_name')
    )

    return Response({
      'resource_id': resource.id,
      'resource_title': resource.title,
      'assigned_clients': [
        {
          'assignment_id': assignment.id,
          'client_id': assignment.client_id,
          'client_name': f'{assignment.client.first_name} {assignment.client.last_name}'.strip(),
          'template_id': assignment.template_id,
          'template_name': assignment.template.name,
        }
        for assignment in assignments
      ],
    })


class ResourceUnassignClientView(APIView):
  """Removes this resource from a single client's template assignment,
  without deleting the resource or the assignment itself -- only the M2M
  link between them. The counterpart bulk action is
  ResourceUnassignAllClientsView below."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, resource_id):
    resource = ProfessionalResource.objects.filter(id=resource_id, professional=request.user).first()

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignment_id = request.data.get('assignment_id')
    assignment = TemplateAssignment.objects.filter(
      id=assignment_id, client__professional=request.user, resources=resource
    ).select_related('client').first()

    if assignment is None:
      return Response({'message': 'Assignment not found for this resource.'}, status=status.HTTP_404_NOT_FOUND)

    assignment.resources.remove(resource)

    return Response({
      'message': f'Unassigned {resource.title} from {assignment.client.first_name}.',
    })


class ResourceUnassignAllClientsView(APIView):
  """Bulk version of ResourceUnassignClientView -- clears this resource from
  every client it's currently shared with in one action."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, resource_id):
    resource = ProfessionalResource.objects.filter(id=resource_id, professional=request.user).first()

    if resource is None:
      return Response({'message': 'Resource not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignments = TemplateAssignment.objects.filter(client__professional=request.user, resources=resource)
    affected_count = assignments.count()

    for assignment in assignments:
      assignment.resources.remove(resource)

    return Response({
      'message': f'Unassigned {resource.title} from {affected_count} {"client" if affected_count == 1 else "clients"}.',
      'affected_count': affected_count,
    })


class StandardTemplateListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    adopted_keys = set(
      TrackingTemplate.objects.filter(professional=request.user, is_active=True)
      .exclude(standard_key='')
      .values_list('standard_key', flat=True)
    )
    standard_templates = [{**template, 'adopted': template['key'] in adopted_keys} for template in STANDARD_TEMPLATES]
    return Response({'standard_templates': standard_templates})


class StandardTemplateAdoptView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def post(self, request):
    key = str(request.data.get('key', '')).strip()
    standard_template = get_standard_template(key)

    if standard_template is None:
      return Response({'message': 'Standard template not found.'}, status=status.HTTP_404_NOT_FOUND)

    template_limit = plan_limit(request.user, 'templates')
    if template_limit is not None and TrackingTemplate.objects.filter(professional=request.user, is_active=True).count() >= template_limit:
      return Response({'message': f'Maximum of {template_limit} templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      template = TrackingTemplate.objects.create(
        professional=request.user,
        name=standard_template['name'],
        purpose=standard_template['purpose'],
        cadence=standard_template['cadence'],
        accent=standard_template['accent'],
        fields=standard_template['fields'],
        standard_key=key,
      )
    except IntegrityError:
      return Response({'message': 'A template with this name already exists.'}, status=status.HTTP_400_BAD_REQUEST)

    plan_lock_status.bust_lock_status_cache(request.user)

    return Response(
      {
        'template': TrackingTemplateSerializer(template, context={'request': request}).data,
        'message': f'{template.name} template added.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrackingTemplateListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    templates = TrackingTemplate.objects.filter(professional=request.user, is_active=True).prefetch_related('assignments')
    return Response(
      {
        'templates': TrackingTemplateSerializer(templates, many=True, context={'request': request}).data,
        'max_templates': plan_limit(request.user, 'templates'),
        'plan': professional_plan(request.user),
      }
    )

  def post(self, request):
    template_limit = plan_limit(request.user, 'templates')
    if template_limit is not None and TrackingTemplate.objects.filter(professional=request.user, is_active=True).count() >= template_limit:
      return Response({'message': f'Maximum of {template_limit} templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = TrackingTemplateSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)

    try:
      template = serializer.save(professional=request.user)
    except IntegrityError:
      return Response({'message': 'Template name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    plan_lock_status.bust_lock_status_cache(request.user)

    return Response(
      {
        'template': TrackingTemplateSerializer(template, context={'request': request}).data,
        'message': 'Template saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrackingTemplateDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_template(self, request, template_id):
    return TrackingTemplate.objects.filter(id=template_id, professional=request.user, is_active=True).first()

  def get(self, request, template_id):
    template = self.get_template(request, template_id)

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'template': TrackingTemplateSerializer(template, context={'request': request}).data})

  def put(self, request, template_id):
    template = self.get_template(request, template_id)

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_item_not_locked(request.user, 'templates', template.id)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = TrackingTemplateSerializer(template, data=request.data, partial=True, context={'request': request})
    serializer.is_valid(raise_exception=True)

    try:
      serializer.save()
    except IntegrityError:
      return Response({'message': 'Template name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'template': TrackingTemplateSerializer(template, context={'request': request}).data,
        'message': 'Template updated successfully.',
      }
    )

  def delete(self, request, template_id):
    template = self.get_template(request, template_id)

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    # A template still assigned to clients cannot be deleted: the professional must
    # unassign it from each client first. TemplateAssignment cascades on this
    # FK, so without this check the delete would silently strip the template
    # from every client who is actively logging against it.
    assigned_count = template.assignments.count()

    if assigned_count:
      return Response(
        {
          'message': (
            f'This template is assigned to {assigned_count} '
            f'{"client" if assigned_count == 1 else "clients"}. '
            'Remove it from every client before deleting it.'
          ),
          'assigned_count': assigned_count,
        },
        status=status.HTTP_400_BAD_REQUEST,
      )

    template.delete()
    plan_lock_status.bust_lock_status_cache(request.user)
    return Response({'message': 'Template deleted. Past client entries are kept.'})


class ClientTemplateAssignmentListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignments = (
      client_access.template_assignments.filter(template__is_active=True)
      .select_related('template')
      .prefetch_related('resources__category')
    )
    return Response({'assignments': TemplateAssignmentSerializer(assignments, many=True, context={'request': request}).data})

  def post(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    template = TrackingTemplate.objects.filter(
      id=request.data.get('template_id'),
      professional=request.user,
      is_active=True,
    ).first()

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_item_not_locked(request.user, 'templates', template.id)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    access_level = request.data.get('client_access_level') or TemplateAssignment.ACCESS_EDITABLE
    valid_access_levels = {choice for choice, _ in TemplateAssignment.CLIENT_ACCESS_LEVEL_CHOICES}

    if access_level not in valid_access_levels:
      return Response({'message': 'Invalid client access level.'}, status=status.HTTP_400_BAD_REQUEST)

    assignment, created = TemplateAssignment.objects.get_or_create(
      client=client_access, template=template, defaults={'client_access_level': access_level}
    )

    if not created:
      return Response({'message': 'Template is already assigned to this client.'}, status=status.HTTP_400_BAD_REQUEST)

    set_assignment_resources(assignment, request.user, request.data.get('reference_ids'))

    return Response(
      {
        'assignment': TemplateAssignmentSerializer(assignment, context={'request': request}).data,
        'message': f'{template.name} assigned to {client_access.first_name}.',
      },
      status=status.HTTP_201_CREATED,
    )


def set_assignment_resources(assignment, professional, resource_ids):
  if resource_ids is None or not isinstance(resource_ids, list):
    return

  # Locked resources (over the current plan's limit) are silently excluded --
  # they shouldn't be assignable to a client while locked, but this isn't a
  # user-facing error since the professional's UI shouldn't offer them anyway.
  locked_ids = set(plan_lock_status.compute_lock_status(professional)['resources']['locked_ids'])
  resources = ProfessionalResource.objects.filter(professional=professional, id__in=resource_ids).exclude(id__in=locked_ids)
  assignment.resources.set(resources)


class ClientTemplateAssignmentDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get_assignment(self, request, client_id, assignment_id):
    return TemplateAssignment.objects.filter(
      id=assignment_id,
      client_id=client_id,
      client__professional=request.user,
    ).select_related('template', 'client').first()

  def put(self, request, client_id, assignment_id):
    assignment = self.get_assignment(request, client_id, assignment_id)

    if assignment is None:
      return Response({'message': 'Template assignment not found.'}, status=status.HTTP_404_NOT_FOUND)

    set_assignment_resources(assignment, request.user, request.data.get('reference_ids'))

    if 'client_access_level' in request.data:
      access_level = request.data.get('client_access_level') or TemplateAssignment.ACCESS_EDITABLE
      valid_access_levels = {choice for choice, _ in TemplateAssignment.CLIENT_ACCESS_LEVEL_CHOICES}

      if access_level not in valid_access_levels:
        return Response({'message': 'Invalid client access level.'}, status=status.HTTP_400_BAD_REQUEST)

      assignment.client_access_level = access_level
      assignment.save(update_fields=['client_access_level'])

    return Response(
      {
        'assignment': TemplateAssignmentSerializer(assignment, context={'request': request}).data,
        'message': 'Assignment updated.',
      }
    )

  def delete(self, request, client_id, assignment_id):
    assignment = self.get_assignment(request, client_id, assignment_id)

    if assignment is None:
      return Response({'message': 'Template assignment not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignment.delete()
    return Response({'message': 'Template unassigned. Past entries are kept.'})


class ClientTrackingEntryListView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    entries = client_access.tracking_entries.filter(created_at__gte=visible_client_data_cutoff(request.user))
    template_id = request.query_params.get('template')
    month = request.query_params.get('month')

    if template_id:
      entries = entries.filter(template_id=template_id)

    if month:
      try:
        year_value, month_value = month.split('-')
        entries = entries.filter(entry_date__year=int(year_value), entry_date__month=int(month_value))
      except ValueError:
        return Response({'message': 'Month filter must use the YYYY-MM format.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'entries': TrackingEntrySerializer(entries, many=True).data})

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientTrackingEntrySubmitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    template = TrackingTemplate.objects.filter(
      id=serializer.validated_data['template_id'],
      professional=request.user,
      is_active=True,
      assignments__client=client_access,
    ).first()

    if template is None:
      return Response({'message': 'Template is not assigned to this client.'}, status=status.HTTP_404_NOT_FOUND)

    entry, created = TrackingEntry.objects.update_or_create(
      client=client_access,
      template=template,
      entry_date=serializer.validated_data['entry_date'],
      defaults={
        'template_name': template.name,
        'answers': serializer.validated_data['answers'],
        'note': serializer.validated_data['note'],
        'edited_by_professional': True,
      },
    )

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry recorded.' if created else 'Entry updated.',
      },
      status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
    )


ENTRY_EDIT_WINDOW = timedelta(hours=72)


def entry_editable(entry):
  """Entries can only be edited within 72 hours of being submitted."""
  return timezone.now() - entry.created_at <= ENTRY_EDIT_WINDOW


class ProfessionalTrackingEntryDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def put(self, request, entry_id):
    entry = TrackingEntry.objects.filter(
      id=entry_id, client__professional=request.user, created_at__gte=visible_client_data_cutoff(request.user)
    ).first()

    if entry is None:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not entry_editable(entry):
      return Response(
        {'message': 'This entry is older than 72 hours and can no longer be edited.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    serializer = TrackingEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save(edited_by_professional=True)

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry updated successfully.',
      }
    )


class ProfessionalClientChatView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [JSONParser, FormParser, MultiPartParser]

  def get_client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, professional=request.user, is_active=True).first()

  def get(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    cutoff = visible_client_data_cutoff(request.user)
    messages = ChatMessage.objects.filter(professional=request.user, client=client_access, created_at__gte=cutoff)
    after_id = request.query_params.get('after')

    if after_id:
      messages = messages.filter(id__gt=after_id)

    ChatMessage.objects.filter(
      professional=request.user,
      client=client_access,
      sender=ChatMessage.SENDER_CLIENT,
      is_read=False,
    ).update(is_read=True)

    return Response({'messages': ChatMessageSerializer(messages, many=True, context={'request': request}).data})

  def post(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      feature_access.assert_can_use_chat(request.user.professional_profile)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = ChatMessageSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)
    message = serializer.save(professional=request.user, client=client_access, sender=ChatMessage.SENDER_PROFESSIONAL)

    return Response(
      {'chat_message': ChatMessageSerializer(message, context={'request': request}).data}, status=status.HTTP_201_CREATED
    )


class ProfessionalChatUnreadView(APIView):
  permission_classes = [ProfessionalAccessPermission]

  def get(self, request):
    unread_rows = (
      ChatMessage.objects.filter(
        professional=request.user,
        client__is_active=True,
        created_at__gte=visible_client_data_cutoff(request.user),
        sender=ChatMessage.SENDER_CLIENT,
        is_read=False,
      )
      .values('client_id')
      .annotate(unread_count=Count('id'), last_unread_at=Max('created_at'))
    )
    by_client = {}
    last_unread_at = {}
    client_names = {}

    for row in unread_rows:
      client_id = str(row['client_id'])
      by_client[client_id] = row['unread_count']
      # Lets a client list float waiting chats to the top, newest first. It's the
      # newest *unread* message rather than the newest message in the thread: the
      # professional's own reply shouldn't push a chat up, and once they read it the
      # row drops out of here entirely and the list settles back down.
      last_unread_at[client_id] = row['last_unread_at'].isoformat()

    if by_client:
      client_names = {
        str(client.id): (f'{client.first_name} {client.last_name}'.strip() or client.username)
        for client in ClientAccess.objects.filter(
          professional=request.user, id__in=by_client.keys()
        ).only('id', 'first_name', 'last_name', 'username')
      }

    return Response(
      {
        'unread_count': sum(by_client.values()),
        'by_client': by_client,
        'last_unread_at': last_unread_at,
        'client_names': client_names,
      }
    )


class ClientPasswordChangeView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  allow_outdated_legal = True

  def post(self, request):
    serializer = ClientPasswordChangeSerializer(data=request.data, context={'client_access': request.auth})
    serializer.is_valid(raise_exception=True)
    client_access = serializer.save()
    # Old tokens must die with the old password, but the client stays signed
    # in: issue a fresh token so the session continues without an
    # "Invalid token" failure right after the change.
    ClientAuthToken.objects.filter(client=client_access).delete()
    token = issue_client_token(client_access)

    return Response(
      {
        'token': token.key,
        'client': ClientAccessSerializer(client_access, context={'include_professional_notes': True}).data,
        'message': 'Password changed successfully.',
      }
    )


class ClientLegalAcceptanceView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  allow_outdated_legal = True

  def post(self, request):
    if request.data.get('accept_terms') is not True or request.data.get('accept_privacy') is not True:
      return Response(
        {'message': 'You must review and accept both the Client Terms and Client Privacy Notice.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    client_access = request.auth
    accepted_at = timezone.now()
    client_access.terms_accepted = True
    client_access.privacy_policy_accepted = True
    client_access.terms_accepted_at = accepted_at
    client_access.privacy_policy_accepted_at = accepted_at
    client_access.legal_document_version = settings.REPROOT_CLIENT_LEGAL_VERSION
    client_access.save(update_fields=[
      'terms_accepted', 'privacy_policy_accepted',
      'terms_accepted_at', 'privacy_policy_accepted_at',
      'legal_document_version', 'updated_at',
    ])
    LegalAcceptanceRecord.objects.create(
      actor_type=LegalAcceptanceRecord.ACTOR_CLIENT,
      client_access=client_access,
      actor_reference=client_access.reference_id,
      legal_document_version=settings.REPROOT_CLIENT_LEGAL_VERSION,
      terms_accepted=True,
      privacy_policy_accepted=True,
      accepted_at=accepted_at,
      client_timezone=str(request.data.get('client_timezone') or '')[:80],
    )
    return Response({
      'client': ClientAccessSerializer(client_access).data,
      'message': 'Client legal documents accepted.',
    })


class ClientDashboardView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client_access = request.auth
    now = timezone.localtime()
    week_start = now.date() - timedelta(days=now.weekday())
    entries = client_access.tracking_entries.all()
    locked_template_ids = plan_lock_status.compute_lock_status(client_access.professional)['templates']['locked_ids']
    assignments = client_access.template_assignments.filter(template__is_active=True).exclude(
      template_id__in=locked_template_ids
    )
    reminders = list(client_access.reminders.filter(status=ClientReminder.STATUS_PENDING))

    def reminder_datetime(reminder):
      naive = datetime.combine(reminder.date, reminder.time or time(hour=23, minute=59))
      return timezone.make_aware(naive, timezone.get_current_timezone())

    reminders.sort(key=reminder_datetime)

    overdue_count = sum(1 for reminder in reminders if reminder_datetime(reminder) < now)
    thirty_days_ago = now.date() - timedelta(days=29)
    recent_entry_dates = sorted(
      set(entries.filter(entry_date__gte=thirty_days_ago).values_list('entry_date', flat=True)),
      reverse=True,
    )
    current_streak = 0
    if recent_entry_dates and recent_entry_dates[0] >= now.date() - timedelta(days=1):
      expected_date = recent_entry_dates[0]
      for entry_date in recent_entry_dates:
        if entry_date != expected_date:
          break
        current_streak += 1
        expected_date -= timedelta(days=1)
    completed_last_30 = client_access.reminders.filter(
      status=ClientReminder.STATUS_DONE,
      updated_at__date__gte=thirty_days_ago,
    ).count()

    def due_within(delta):
      cutoff = now + delta
      return sum(1 for reminder in reminders if now <= reminder_datetime(reminder) <= cutoff)

    return Response(
      {
        'summary': {
          'total_entries': entries.count(),
          'entries_this_week': entries.filter(entry_date__gte=week_start).count(),
          'entries_last_30_days': entries.filter(entry_date__gte=thirty_days_ago).count(),
          'active_days_last_30': len(recent_entry_dates),
          'consistency_percent': round((len(recent_entry_dates) / 30) * 100),
          'current_streak': current_streak,
          'last_entry_date': recent_entry_dates[0].isoformat() if recent_entry_dates else '',
          'completed_schedules_last_30': completed_last_30,
          'active_templates': assignments.count(),
          'overdue': overdue_count,
          'due_24_hours': due_within(timedelta(hours=24)),
          'due_7_days': due_within(timedelta(days=7)),
        },
        'schedules': ClientReminderSerializer(reminders[:50], many=True).data,
      }
    )


class ClientLogoutView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  allow_outdated_legal = True

  def post(self, request):
    ClientAuthToken.objects.filter(client=request.auth).delete()
    return Response({'message': 'Logged out successfully.'})


class ClientMeView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client_access = request.auth
    registration_form = getattr(client_access.group, 'client_registration_form', None)

    return Response(
      {
        'client': ClientAccessSerializer(client_access).data,
        'group': ProfessionalGroupSerializer(client_access.group).data,
        'registration_fields': registration_form.fields if registration_form and registration_form.is_active else [],
        'lead_submission': (
          LeadSubmissionSerializer(client_access.lead_submission).data if client_access.lead_submission else None
        ),
        'professional_profile': build_public_professional_profile(client_access.professional, request),
        'additional_info_shared': client_access.additional_info_shared,
        'shared_additional_info': client_access.additional_info if client_access.additional_info_shared else [],
      }
    )


class ClientPhotoView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def put(self, request):
    client_access = request.auth
    serializer = ClientPhotoUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access.photo = serializer.validated_data['photo']
    client_access.save(update_fields=['photo', 'updated_at'])
    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Photo updated.'})


class ClientDetailChangeRequestView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    history = request.auth.detail_change_requests.filter(
      request_type=ClientDetailChangeRequest.TYPE_PROFILE_EDIT
    )
    change_request = history.filter(archived_at__isnull=True).first()
    return Response(
      {
        'change_request': (
          ClientDetailChangeRequestSerializer(change_request).data if change_request else None
        ),
        'history': ClientDetailChangeRequestSerializer(history, many=True).data,
      }
    )

  def post(self, request):
    client_access = request.auth

    if client_access.detail_change_requests.filter(status=ClientDetailChangeRequest.STATUS_PENDING).exists():
      return Response(
        {'message': 'You already have an edit request awaiting your professional\'s approval.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    registration_form = getattr(client_access.group, 'client_registration_form', None)
    proposed_answers = request.data.get('proposed_answers') or {}

    if not isinstance(proposed_answers, dict) or not proposed_answers:
      return Response({'message': 'Proposed answers are required.'}, status=status.HTTP_400_BAD_REQUEST)

    # Core identity stays fixed - always carry the current values through.
    proposed_answers['first_name'] = client_access.first_name
    proposed_answers['last_name'] = client_access.last_name
    proposed_answers['email'] = client_access.email

    if registration_form and registration_form.is_active:
      from .serializers import validate_required_answers

      validate_required_answers(registration_form.fields, proposed_answers)

    change_request = ClientDetailChangeRequest.objects.create(
      client=client_access,
      request_type=ClientDetailChangeRequest.TYPE_PROFILE_EDIT,
      proposed_answers=proposed_answers,
      client_note=str(request.data.get('note', '')).strip(),
    )

    return Response(
      {
        'change_request': ClientDetailChangeRequestSerializer(change_request).data,
        'message': 'Edit request submitted. Your professional will review it.',
      },
      status=status.HTTP_201_CREATED,
    )

  def delete(self, request):
    change_request = request.auth.detail_change_requests.filter(
      request_type=ClientDetailChangeRequest.TYPE_PROFILE_EDIT,
      archived_at__isnull=True,
    ).first()
    if change_request is None:
      return Response({'message': 'No visible edit request was found.'}, status=status.HTTP_404_NOT_FOUND)
    if change_request.status == ClientDetailChangeRequest.STATUS_PENDING:
      change_request.status = ClientDetailChangeRequest.STATUS_CANCELLED
      change_request.reviewed_at = timezone.now()
      change_request.save(update_fields=['status', 'reviewed_at'])
      return Response({'message': 'Edit request cancelled. It remains in your request history.'})
    change_request.archived_at = timezone.now()
    change_request.save(update_fields=['archived_at'])
    return Response({'message': 'Request archived from your current view. History was preserved.'})


class ClientAccountDeletionRequestView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    history = request.auth.detail_change_requests.filter(
      request_type=ClientDetailChangeRequest.TYPE_ACCOUNT_DELETION
    )
    deletion_request = history.filter(archived_at__isnull=True).first()
    return Response({
      'deletion_request': ClientDetailChangeRequestSerializer(deletion_request).data if deletion_request else None,
      'history': ClientDetailChangeRequestSerializer(history, many=True).data,
    })

  def post(self, request):
    client_access = request.auth
    if client_access.detail_change_requests.filter(
      request_type=ClientDetailChangeRequest.TYPE_ACCOUNT_DELETION,
      status=ClientDetailChangeRequest.STATUS_PENDING,
    ).exists():
      return Response(
        {'message': 'An account deletion request is already awaiting professional review.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    deletion_request = ClientDetailChangeRequest.objects.create(
      client=client_access,
      request_type=ClientDetailChangeRequest.TYPE_ACCOUNT_DELETION,
      proposed_answers={},
      client_note=str(request.data.get('note', '')).strip(),
    )
    return Response(
      {
        'deletion_request': ClientDetailChangeRequestSerializer(deletion_request).data,
        'message': 'Account deletion request sent to your professional for review.',
      },
      status=status.HTTP_201_CREATED,
    )

  def delete(self, request):
    deletion_request = request.auth.detail_change_requests.filter(
      request_type=ClientDetailChangeRequest.TYPE_ACCOUNT_DELETION,
      archived_at__isnull=True,
    ).first()
    if deletion_request is None:
      return Response({'message': 'No visible account deletion request was found.'}, status=status.HTTP_404_NOT_FOUND)
    if deletion_request.status == ClientDetailChangeRequest.STATUS_PENDING:
      deletion_request.status = ClientDetailChangeRequest.STATUS_CANCELLED
      deletion_request.reviewed_at = timezone.now()
      deletion_request.save(update_fields=['status', 'reviewed_at'])
      return Response({'message': 'Account deletion request cancelled. History was preserved.'})
    deletion_request.archived_at = timezone.now()
    deletion_request.save(update_fields=['archived_at'])
    return Response({'message': 'Request archived from your current view. History was preserved.'})


class ClientTemplateListView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    # Plan-limit lock system: a locked template or resource simply doesn't
    # exist from the client's point of view -- no error, no "unavailable"
    # message, just absent, exactly as if it were never assigned. See
    # DOWNGRADE_LOCK_SYSTEM_PLAN.md 3.3.
    lock_status = plan_lock_status.compute_lock_status(request.auth.professional)
    locked_template_ids = lock_status['templates']['locked_ids']
    locked_resource_ids = set(lock_status['resources']['locked_ids'])

    assignments = (
      request.auth.template_assignments.filter(template__is_active=True)
      .exclude(client_access_level=TemplateAssignment.ACCESS_PRIVATE)
      .exclude(template_id__in=locked_template_ids)
      .select_related('template')
      .prefetch_related('resources__category')
    )
    templates = []

    for assignment in assignments:
      template_data = TrackingTemplateSerializer(assignment.template, context={'request': request}).data
      template_data['assignment_id'] = assignment.id
      template_data['client_access_level'] = assignment.client_access_level
      template_data['resources'] = TrackingTemplateResourceSerializer(
        assignment.resources.exclude(id__in=locked_resource_ids),
        many=True,
        context={'request': request},
      ).data
      templates.append(template_data)

    return Response({'templates': templates})


class ClientTrackingEntryView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    entries = request.auth.tracking_entries.filter(
      created_at__gte=visible_client_data_cutoff(request.auth.professional)
    )
    template_id = request.query_params.get('template')
    month = request.query_params.get('month')

    if template_id:
      assignment = TemplateAssignment.objects.filter(client=request.auth, template_id=template_id).first()

      if assignment is not None and assignment.client_access_level == TemplateAssignment.ACCESS_PRIVATE:
        return Response({'message': 'Tracking entries not found.'}, status=status.HTTP_404_NOT_FOUND)

      entries = entries.filter(template_id=template_id)
    else:
      # Hide entries for templates the trainer has since marked private, even
      # in the unfiltered list, so a private assignment never leaks via
      # entries created before it was made private.
      private_template_ids = TemplateAssignment.objects.filter(
        client=request.auth, client_access_level=TemplateAssignment.ACCESS_PRIVATE
      ).values_list('template_id', flat=True)
      entries = entries.exclude(template_id__in=private_template_ids)

    if month:
      try:
        year_value, month_value = month.split('-')
        entries = entries.filter(entry_date__year=int(year_value), entry_date__month=int(month_value))
      except ValueError:
        return Response({'message': 'Month filter must use the YYYY-MM format.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'entries': TrackingEntrySerializer(entries, many=True).data})

  def post(self, request):
    serializer = ClientTrackingEntrySubmitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access = request.auth
    assignment = TemplateAssignment.objects.filter(
      client=client_access,
      template_id=serializer.validated_data['template_id'],
      template__professional=client_access.professional,
      template__is_active=True,
    ).select_related('template').first()

    if assignment is None or assignment.client_access_level == TemplateAssignment.ACCESS_PRIVATE:
      return Response({'message': 'Template is not assigned to you.'}, status=status.HTTP_404_NOT_FOUND)

    if plan_lock_status.is_template_locked(client_access.professional, assignment.template_id):
      # Same "doesn't exist" treatment as the list view -- a locked template
      # simply isn't available to submit against, no different framing.
      return Response({'message': 'Template is not assigned to you.'}, status=status.HTTP_404_NOT_FOUND)

    if assignment.client_access_level == TemplateAssignment.ACCESS_VIEW_ONLY:
      return Response(
        {'message': 'This template is view-only. You cannot submit entries.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    template = assignment.template

    # A client may log the same template multiple times per day, so every
    # submission creates a new entry (rather than overwriting the day's row).
    entry_time = serializer.validated_data.get('entry_time') or timezone.localtime().time()
    entry = TrackingEntry.objects.create(
      client=client_access,
      template=template,
      template_name=template.name,
      entry_date=serializer.validated_data['entry_date'],
      entry_time=entry_time,
      answers=serializer.validated_data['answers'],
      note=serializer.validated_data['note'],
      edited_by_professional=False,
    )

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry submitted successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class ClientPortalProgressView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    cutoff = visible_client_data_cutoff(request.auth.professional)
    return Response({'progress': ProgressEntrySerializer(request.auth.progress_entries.filter(created_at__gte=cutoff), many=True).data})


class ClientTrackingEntryDetailView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def put(self, request, entry_id):
    entry = TrackingEntry.objects.filter(
      id=entry_id, client=request.auth, created_at__gte=visible_client_data_cutoff(request.auth.professional)
    ).first()

    if entry is None:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignment = None
    if entry.template_id is not None:
      assignment = TemplateAssignment.objects.filter(client=request.auth, template_id=entry.template_id).first()

    if assignment is not None and assignment.client_access_level == TemplateAssignment.ACCESS_PRIVATE:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

    if assignment is not None and assignment.client_access_level == TemplateAssignment.ACCESS_VIEW_ONLY:
      return Response(
        {'message': 'This template is view-only. You cannot edit entries.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    if not entry_editable(entry):
      return Response(
        {'message': 'This entry is older than 72 hours and can no longer be edited.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    serializer = TrackingEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save(edited_by_professional=False)

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry updated successfully.',
      }
    )


class ClientChatView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  parser_classes = [JSONParser, FormParser, MultiPartParser]

  def get(self, request):
    client_access = request.auth
    cutoff = visible_client_data_cutoff(client_access.professional)
    messages = ChatMessage.objects.filter(
      professional=client_access.professional, client=client_access, created_at__gte=cutoff
    )
    after_id = request.query_params.get('after')

    if after_id:
      messages = messages.filter(id__gt=after_id)

    ChatMessage.objects.filter(
      professional=client_access.professional,
      client=client_access,
      sender=ChatMessage.SENDER_PROFESSIONAL,
      is_read=False,
    ).update(is_read=True)

    return Response({'messages': ChatMessageSerializer(messages, many=True, context={'request': request}).data})

  def post(self, request):
    client_access = request.auth

    try:
      feature_access.assert_can_use_chat(client_access.professional.professional_profile)
    except feature_access.FeatureAccessError as exc:
      return Response({'message': str(exc)}, status=status.HTTP_403_FORBIDDEN)

    serializer = ChatMessageSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)
    message = serializer.save(professional=client_access.professional, client=client_access, sender=ChatMessage.SENDER_CLIENT)

    return Response(
      {'chat_message': ChatMessageSerializer(message, context={'request': request}).data}, status=status.HTTP_201_CREATED
    )


class ClientChatUnreadView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    unread_count = ChatMessage.objects.filter(
      professional=request.auth.professional,
      client=request.auth,
      created_at__gte=visible_client_data_cutoff(request.auth.professional),
      sender=ChatMessage.SENDER_PROFESSIONAL,
      is_read=False,
    ).count()

    return Response({'unread_count': unread_count})


def _support_reporter_filter(role, reporter):
  if role == SupportIncident.ROLE_PROFESSIONAL:
    return {'reporter_professional': reporter, 'reporter_role': role}
  return {'reporter_client': reporter, 'reporter_role': role}


def _support_reporter_identity(role, reporter):
  if role == SupportIncident.ROLE_PROFESSIONAL:
    return reporter.get_full_name() or reporter.username, reporter.email
  return f'{reporter.first_name} {reporter.last_name}'.strip() or reporter.username, reporter.email


def _notify_support_team(incident):
  if not settings.SUPPORT_EMAIL:
    return
  send_mail_background(
    subject=f'[{incident.incident_id}] {incident.subject}',
    message=(
      f'New RepRoot support request\n\n'
      f'Reference: {incident.incident_id}\n'
      f'Reporter: {incident.reporter_name}\n'
      f'Reporter email: {incident.reporter_email}\n'
      f'Category: {incident.get_category_display()}\n'
      f'Priority: {incident.get_priority_display()}\n'
      f'Platform: {incident.platform}\n\n'
      f'{incident.description}\n\n'
      f'Open the RepRoot admin support queue to respond.'
    ),
    from_email=settings.DEFAULT_FROM_EMAIL,
    recipient_list=[settings.SUPPORT_EMAIL],
    fail_silently=False,
  )


def _support_incident_list(request, role, reporter):
  incidents = SupportIncident.objects.filter(**_support_reporter_filter(role, reporter)).prefetch_related('messages')
  return Response({
    'incidents': SupportIncidentSerializer(incidents, many=True, context={'request': request}).data,
    'active_count': incidents.filter(status__in=SupportIncident.ACTIVE_STATUSES).count(),
    'active_limit': 3,
  })


def _support_incident_create(request, role, reporter):
  reporter_filter = _support_reporter_filter(role, reporter)
  if SupportIncident.objects.filter(**reporter_filter, status__in=SupportIncident.ACTIVE_STATUSES).count() >= 3:
    return Response(
      {'message': 'You already have the maximum of three active support requests.'},
      status=status.HTTP_400_BAD_REQUEST,
    )

  serializer = SupportIncidentCreateSerializer(data=request.data)
  serializer.is_valid(raise_exception=True)
  reporter_name, reporter_email = _support_reporter_identity(role, reporter)
  values = serializer.validated_data
  incident = SupportIncident.objects.create(
    **reporter_filter,
    reporter_name=reporter_name,
    reporter_email=reporter_email,
    category=values['category'],
    subject=values['subject'].strip(),
    description=values['description'].strip(),
    page_feature=values.get('page_feature', '').strip(),
    platform=values.get('platform', 'web'),
    app_version=values.get('app_version', '').strip(),
    device_info=values.get('device_info', '').strip(),
    screenshot=values.get('screenshot'),
  )
  _notify_support_team(incident)
  return Response(
    {
      'incident': SupportIncidentSerializer(incident, context={'request': request}).data,
      'message': f'Support request {incident.incident_id} was submitted.',
    },
    status=status.HTTP_201_CREATED,
  )


def _support_incident_action(request, role, reporter, incident_id):
  incident = SupportIncident.objects.filter(
    incident_id=incident_id, **_support_reporter_filter(role, reporter)
  ).prefetch_related('messages').first()
  if incident is None:
    return Response({'message': 'Support request not found.'}, status=status.HTTP_404_NOT_FOUND)

  action = str(request.data.get('action', '')).strip().lower()
  body = str(request.data.get('body', '')).strip()
  reporter_name, _ = _support_reporter_identity(role, reporter)

  if action == 'follow_up':
    if incident.status != SupportIncident.STATUS_WAITING:
      return Response(
        {'message': 'You can reply after Support requests more information.'},
        status=status.HTTP_400_BAD_REQUEST,
      )
    if not body:
      return Response({'message': 'A response is required.'}, status=status.HTTP_400_BAD_REQUEST)
    SupportIncidentMessage.objects.create(
      incident=incident, author_type=SupportIncidentMessage.AUTHOR_USER, author_name=reporter_name, body=body[:5000]
    )
    incident.status = SupportIncident.STATUS_REVIEW
    incident.save(update_fields=['status', 'updated_at'])
  elif action == 'reopen':
    if incident.status not in (SupportIncident.STATUS_RESOLVED, SupportIncident.STATUS_CLOSED):
      return Response({'message': 'Only resolved or closed requests can be reopened.'}, status=status.HTTP_400_BAD_REQUEST)
    active_count = SupportIncident.objects.filter(
      **_support_reporter_filter(role, reporter), status__in=SupportIncident.ACTIVE_STATUSES
    ).exclude(pk=incident.pk).count()
    if active_count >= 3:
      return Response({'message': 'Resolve another active request before reopening this one.'}, status=status.HTTP_400_BAD_REQUEST)
    if body:
      SupportIncidentMessage.objects.create(
        incident=incident, author_type=SupportIncidentMessage.AUTHOR_USER, author_name=reporter_name, body=body[:5000]
      )
    incident.status = SupportIncident.STATUS_REOPENED
    incident.closed_at = None
    incident.save(update_fields=['status', 'closed_at', 'updated_at'])
  else:
    return Response({'message': 'Action must be follow_up or reopen.'}, status=status.HTTP_400_BAD_REQUEST)

  incident.refresh_from_db()
  return Response({
    'incident': SupportIncidentSerializer(incident, context={'request': request}).data,
    'message': 'Support request updated.',
  })


class ProfessionalSupportIncidentListView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  parser_classes = [JSONParser, FormParser, MultiPartParser]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request):
    return _support_incident_list(request, SupportIncident.ROLE_PROFESSIONAL, request.user)

  def post(self, request):
    return _support_incident_create(request, SupportIncident.ROLE_PROFESSIONAL, request.user)


class ProfessionalSupportIncidentDetailView(APIView):
  permission_classes = [ProfessionalAccessPermission]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request, incident_id):
    incident = SupportIncident.objects.filter(
      incident_id=incident_id, reporter_professional=request.user, reporter_role=SupportIncident.ROLE_PROFESSIONAL
    ).prefetch_related('messages').first()
    if incident is None:
      return Response({'message': 'Support request not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'incident': SupportIncidentSerializer(incident, context={'request': request}).data})

  def post(self, request, incident_id):
    return _support_incident_action(request, SupportIncident.ROLE_PROFESSIONAL, request.user, incident_id)


class ClientSupportIncidentListView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  parser_classes = [JSONParser, FormParser, MultiPartParser]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request):
    return _support_incident_list(request, SupportIncident.ROLE_CLIENT, request.auth)

  def post(self, request):
    return _support_incident_create(request, SupportIncident.ROLE_CLIENT, request.auth)


class ClientSupportIncidentDetailView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request, incident_id):
    incident = SupportIncident.objects.filter(
      incident_id=incident_id, reporter_client=request.auth, reporter_role=SupportIncident.ROLE_CLIENT
    ).prefetch_related('messages').first()
    if incident is None:
      return Response({'message': 'Support request not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'incident': SupportIncidentSerializer(incident, context={'request': request}).data})

  def post(self, request, incident_id):
    return _support_incident_action(request, SupportIncident.ROLE_CLIENT, request.auth, incident_id)


class ErrorReportView(APIView):
  """Automatic crash/error beacon from the running web or mobile app.

  Accepts a professional token, a client token, or no credentials at all — a
  crash can happen before login (e.g. on the login screen itself), and this
  must never itself fail hard, so identity resolution is best-effort.
  """
  authentication_classes = [TokenAuthentication, ClientTokenAuthentication]
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'errors'

  def post(self, request):
    serializer = ErrorReportSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    data = serializer.validated_data

    professional = None
    client = None
    if isinstance(request.auth, ClientAccess):
      client = request.auth
    elif request.user and request.user.is_authenticated:
      professional = request.user

    log, deduped = record_error(
      platform=data['platform'],
      message=data['message'],
      level=data.get('level', ErrorLog.LEVEL_ERROR),
      professional=professional,
      client=client,
      stack_trace=data.get('stack_trace', ''),
      context=data.get('context'),
      app_version=data.get('app_version', ''),
      device_info=data.get('device_info', ''),
      request_path=data.get('request_path', ''),
    )
    return Response(
      {'error_id': log.error_id, 'deduped': deduped},
      status=status.HTTP_202_ACCEPTED if deduped else status.HTTP_201_CREATED,
    )
