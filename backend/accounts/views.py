from datetime import datetime, time, timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.conf import settings
from django.core.mail import send_mail
from django.db import IntegrityError, transaction
from django.db.models import Count, ProtectedError, Q
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView

from .models import (
  default_client_registration_fields,
  ChatMessage,
  ClientAccess,
  ClientAuthToken,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  GroupRegistrationSubmission,
  LeadSubmission,
  ProgressEntry,
  RecycledTrainerAccount,
  ReferenceCategory,
  SupportIncident,
  SupportIncidentMessage,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  TrainerGroup,
  TrainerLeadForm,
  TrainerProfile,
  TrainerReference,
)
from .serializers import (
  ChatMessageSerializer,
  ClientAccessCreateSerializer,
  ClientAdditionalInfoUpdateSerializer,
  ClientPhotoUpdateSerializer,
  ClientDetailChangeRequestSerializer,
  ClientLoginSerializer,
  ClientTrainerLookupSerializer,
  ClientAccessSerializer,
  ClientPasswordChangeSerializer,
  ClientRegistrationFormSerializer,
  ClientReminderSerializer,
  ClientTrackingEntrySubmitSerializer,
  EmailAvailabilitySerializer,
  ProgressEntrySerializer,
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
  ReferenceCategorySerializer,
  SupportIncidentCreateSerializer,
  SupportIncidentSerializer,
  TemplateAssignmentSerializer,
  TrackingEntrySerializer,
  TrackingTemplateReferenceSerializer,
  TrackingTemplateSerializer,
  TrainerAccountSerializer,
  TrainerGroupSerializer,
  TrainerLeadFormSerializer,
  TrainerLoginSerializer,
  TrainerPasswordChangeSerializer,
  TrainerProfileSerializer,
  normalize_profile_visibility,
  TrainerProfileStatusSerializer,
  TrainerReferenceSerializer,
  TrainerSignupSerializer,
  UsernameAvailabilitySerializer,
)
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient, issue_client_token
from .data_usage import calculate_trainer_data_usage
from .email_verification import OtpCooldownError, send_email_otp, verify_email_otp
from .standard_templates import STANDARD_TEMPLATES, get_standard_template
from .plan_limits import plan_limit, trainer_plan

User = get_user_model()


def generate_temporary_password():
  return f'{get_random_string(9)}!7a'


def send_client_credentials(client_access, temporary_password):
  send_mail(
    subject='Your CoachFlow client access',
    message=(
      f'Your client access has been created.\n\n'
      f'Trainer code: {client_access.trainer.trainer_profile.trainer_id}\n'
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

    if not TrainerLeadForm.objects.filter(public_slug=slug).exists():
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


def build_trainer_account_snapshot(user):
  profile = getattr(user, 'trainer_profile', None)
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
    'trainer_profile': None,
  }

  if profile:
    snapshot['trainer_profile'] = {
      'id': profile.id,
      'trainer_id': profile.trainer_id,
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
      'trainer_type': profile.trainer_type,
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


def build_public_trainer_profile(user, request=None):
  profile = getattr(user, 'trainer_profile', None)

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
    'trainer_name': user.get_full_name() or user.username,
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
      'trainer_type': profile.trainer_type if visibility.get('professional_summary') else '',
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
      }
    )


class TrainerCodeAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def post(self, request):
    code = str(request.data.get('trainer_code', '')).strip().lower()

    if len(code) < 4 or len(code) > 32:
      return Response({'available': False, 'message': 'Trainer code must be 4 to 32 characters.'})

    if not code.replace('-', '').replace('_', '').isalnum():
      return Response({'available': False, 'message': 'Trainer code can only use letters, numbers, hyphens, and underscores.'})

    is_available = not TrainerProfile.objects.filter(trainer_id__iexact=code).exists()

    return Response(
      {
        'trainer_code': code,
        'available': is_available,
        'message': 'Trainer code is available.' if is_available else 'Trainer code is already taken.',
      }
    )


class TrainerCodeUpdateView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    return Response({'trainer_code': request.user.trainer_profile.trainer_id or ''})

  def put(self, request):
    profile = request.user.trainer_profile
    code = str(request.data.get('trainer_code', '')).strip().lower()

    if len(code) < 4 or len(code) > 32:
      return Response({'message': 'Trainer code must be 4 to 32 characters.'}, status=status.HTTP_400_BAD_REQUEST)

    if not code.replace('-', '').replace('_', '').isalnum():
      return Response(
        {'message': 'Trainer code can only use letters, numbers, hyphens, and underscores.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    if TrainerProfile.objects.filter(trainer_id__iexact=code).exclude(pk=profile.pk).exists():
      return Response({'message': 'Trainer code is already taken.'}, status=status.HTTP_400_BAD_REQUEST)

    profile.trainer_id = code
    profile.save(update_fields=['trainer_id', 'updated_at'])

    return Response({'trainer_code': profile.trainer_id, 'message': 'Trainer code saved.'})


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


class TrainerSignupView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = TrainerSignupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.save()
    token, _created = Token.objects.get_or_create(user=user)

    return Response(
      {
        'token': token.key,
        'trainer': TrainerAccountSerializer(user).data,
        'message': 'Trainer account created successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrainerLoginView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'auth'

  def post(self, request):
    serializer = TrainerLoginSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    user = serializer.validated_data['user']
    token, _created = Token.objects.get_or_create(user=user)

    return Response(
      {
        'token': token.key,
        'trainer': TrainerAccountSerializer(user).data,
        'message': 'Trainer login successful.',
      }
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

    if not User.objects.filter(email__iexact=email, trainer_profile__isnull=False).exists():
      return Response(
        {
          'email': email,
          'available': True,
          'message': 'No trainer account found. Try Sign up or Login.',
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


class TrainerProfileStatusView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    profile = request.user.trainer_profile
    return Response(TrainerProfileStatusSerializer(profile).data)


class TrainerDataUsageView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    return Response(calculate_trainer_data_usage(request.user))


class TrainerProfileView(APIView):
  permission_classes = [permissions.IsAuthenticated]
  parser_classes = [MultiPartParser, FormParser]

  def get(self, request):
    profile = request.user.trainer_profile
    return Response(TrainerProfileSerializer(profile, context={'request': request}).data)

  def post(self, request):
    profile = request.user.trainer_profile
    serializer = TrainerProfileSerializer(
      profile,
      data=request.data,
      partial=True,
      context={'request': request},
    )
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response(
      {
        'profile': TrainerProfileSerializer(profile, context={'request': request}).data,
        'message': 'Trainer profile saved successfully.',
      }
    )

  def put(self, request):
    return self.post(request)


class TrainerProfileVisibilityView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request):
    profile = request.user.trainer_profile
    visibility = request.data.get('visibility', {})

    if not isinstance(visibility, dict):
      return Response({'message': 'visibility must be an object.'}, status=status.HTTP_400_BAD_REQUEST)

    profile.profile_visibility = normalize_profile_visibility(visibility)
    profile.save(update_fields=['profile_visibility', 'updated_at'])

    return Response(
      {'profile_visibility': profile.profile_visibility, 'message': 'Profile visibility updated.'}
    )


class TrainerLogoutView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    Token.objects.filter(user=request.user).delete()
    return Response({'message': 'Logged out successfully.'})


class TrainerAccountView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def delete(self, request):
    user = User.objects.select_related('trainer_profile').get(pk=request.user.pk)

    if not isinstance(getattr(user, 'trainer_profile', None), TrainerProfile):
      return Response({'message': 'Trainer account not found.'}, status=status.HTTP_404_NOT_FOUND)

    with transaction.atomic():
      RecycledTrainerAccount.objects.create(
        original_user_id=user.id,
        email=user.email,
        username=user.username,
        first_name=user.first_name,
        last_name=user.last_name,
        account_snapshot=build_trainer_account_snapshot(user),
      )
      user.delete()

    return Response({'message': 'Trainer account deleted and moved to recycle space.'})


class TrainerPasswordChangeView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    serializer = TrainerPasswordChangeSerializer(data=request.data, context={'user': request.user})
    serializer.is_valid(raise_exception=True)
    serializer.save(request.user)
    Token.objects.filter(user=request.user).delete()
    return Response({'message': 'Password changed successfully. Please sign in again.'})


class FormsGroupsOverviewView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    lead_form = TrainerLeadForm.objects.filter(trainer=request.user, is_active=True).first()
    groups = TrainerGroup.objects.filter(trainer=request.user, is_active=True).select_related('client_registration_form')
    submissions = LeadSubmission.objects.filter(lead_form__trainer=request.user).select_related('client_access__group')
    pending_submissions = submissions.filter(status=LeadSubmission.STATUS_PENDING)
    approved_submissions = submissions.filter(status=LeadSubmission.STATUS_APPROVED)
    deleted_submissions = submissions.filter(status=LeadSubmission.STATUS_DELETED)

    return Response(
      {
        'has_lead_form': lead_form is not None,
        'lead_form': TrainerLeadFormSerializer(lead_form, context={'request': request}).data if lead_form else None,
        'groups': TrainerGroupSerializer(groups, many=True).data,
        'pending_forms': LeadSubmissionSerializer(pending_submissions, many=True).data,
        'approved_forms': LeadSubmissionSerializer(approved_submissions, many=True).data,
        'deleted_forms': LeadSubmissionSerializer(deleted_submissions, many=True).data,
        'max_groups': plan_limit(request.user, 'groups'),
        'plan': trainer_plan(request.user),
      }
    )


class TrainerLeadFormView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    lead_form = TrainerLeadForm.objects.filter(trainer=request.user, is_active=True).first()
    serializer = TrainerLeadFormSerializer(
      lead_form,
      data=request.data,
      partial=lead_form is not None,
      context={'request': request},
    )
    serializer.is_valid(raise_exception=True)

    if lead_form:
      serializer.save()
    else:
      serializer.save(trainer=request.user, public_slug=generate_unique_slug())

    return Response(
      {
        'lead_form': TrainerLeadFormSerializer(serializer.instance, context={'request': request}).data,
        'message': 'Public lead form saved successfully.',
      },
      status=status.HTTP_201_CREATED if lead_form is None else status.HTTP_200_OK,
    )

  def put(self, request):
    return self.post(request)


class TrainerGroupListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    group_limit = plan_limit(request.user, 'groups')
    if group_limit is not None and TrainerGroup.objects.filter(trainer=request.user, is_active=True).count() >= group_limit:
      return Response({'message': 'Maximum groups limit reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = TrainerGroupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    try:
      group = serializer.save(trainer=request.user)
    except IntegrityError:
      return Response({'message': 'Group Name must be unique for this trainer.'}, status=status.HTTP_400_BAD_REQUEST)

    # Seed the universal client creation form so every group has one from the
    # start. A registration form is mandatory before a lead can be converted
    # into a client; the trainer can still customise these fields afterwards.
    ClientRegistrationForm.objects.create(group=group, fields=default_client_registration_fields())

    return Response(
      {
        'group': TrainerGroupSerializer(group).data,
        'message': 'Group saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrainerGroupDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_group(self, request, group_id):
    return TrainerGroup.objects.filter(id=group_id, trainer=request.user, is_active=True).first()

  def get(self, request, group_id):
    group = self.get_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'group': TrainerGroupSerializer(group).data})

  def put(self, request, group_id):
    group = self.get_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = TrainerGroupSerializer(group, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)

    try:
      serializer.save()
    except IntegrityError:
      return Response({'message': 'Group Name must be unique for this trainer.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'group': TrainerGroupSerializer(group).data, 'message': 'Group updated successfully.'})


class ClientRegistrationFormView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, group_id):
    group = TrainerGroup.objects.filter(id=group_id, trainer=request.user, is_active=True).first()

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
    lead_form = TrainerLeadForm.objects.filter(public_slug=public_slug, is_active=True).select_related('trainer').first()

    if lead_form is None:
      return Response({'message': 'Public form not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(PublicLeadFormSerializer(lead_form).data)

  def post(self, request, public_slug):
    lead_form = TrainerLeadForm.objects.filter(public_slug=public_slug, is_active=True).select_related('trainer').first()

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

    send_mail(
      subject='Your CoachFlow form reference ID',
      message=f'Your form has been submitted successfully. Your reference ID is {submission.reference_id}. Please save this for future communication.',
      from_email=None,
      recipient_list=[submission.email],
      fail_silently=False,
    )

    return Response(
      {
        'reference_id': submission.reference_id,
        'message': f'Your form has been submitted successfully. Your reference ID is {submission.reference_id}. Please save this for future communication. A copy has been sent to your email.',
      },
      status=status.HTTP_201_CREATED,
    )


class PendingLeadSubmissionView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def delete(self, request, submission_id):
    submission = LeadSubmission.objects.filter(
      id=submission_id,
      lead_form__trainer=request.user,
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
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, submission_id):
    client_limit = plan_limit(request.user, 'clients')
    if client_limit is not None and ClientAccess.objects.filter(trainer=request.user, is_active=True).count() >= client_limit:
      return Response({'message': f'Your {trainer_plan(request.user)["name"]} plan allows up to {client_limit} active clients.'}, status=status.HTTP_400_BAD_REQUEST)

    submission = LeadSubmission.objects.filter(
      id=submission_id,
      lead_form__trainer=request.user,
      status=LeadSubmission.STATUS_PENDING,
      is_active=True,
    ).first()

    if submission is None:
      return Response({'message': 'Pending form request not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientAccessCreateSerializer(data=request.data, context={'trainer': request.user})
    serializer.is_valid(raise_exception=True)
    group = TrainerGroup.objects.filter(id=serializer.validated_data['group_id'], trainer=request.user, is_active=True).first()

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
    # account, via an edit request the trainer approves) - not for the trainer
    # to fill in at creation time. So no required-answer validation here.

    client_password = serializer.validated_data['password']

    try:
      with transaction.atomic():
        client_access = ClientAccess.objects.create(
          trainer=request.user,
          group=group,
          lead_submission=submission,
          reference_id=submission.reference_id,
          onboarding_method=ClientAccess.ONBOARDING_PUBLIC_LEAD,
          first_name=submission.first_name,
          last_name=submission.last_name,
          email=submission.email,
          username=serializer.validated_data['username'],
          temporary_password=make_password(client_password),
          photo=serializer.validated_data.get('photo', ''),
          registration_answers=registration_answers,
          must_change_password=True,
        )
        submission.status = LeadSubmission.STATUS_APPROVED
        submission.converted_at = timezone.now()
        submission.save(update_fields=['status', 'converted_at', 'updated_at'])
    except IntegrityError:
      return Response(
        {'message': 'Same email or username already exists under this trainer.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    send_client_credentials(client_access, client_password)

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'message': 'Client access created. Temporary credentials were sent to the client email.',
      },
      status=status.HTTP_201_CREATED,
    )


class ManualClientAccessCreateView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    client_limit = plan_limit(request.user, 'clients')
    if client_limit is not None and ClientAccess.objects.filter(trainer=request.user, is_active=True).count() >= client_limit:
      return Response({'message': f'Your {trainer_plan(request.user)["name"]} plan allows up to {client_limit} active clients.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ClientAccessCreateSerializer(data=request.data, context={'trainer': request.user})
    serializer.is_valid(raise_exception=True)
    group = TrainerGroup.objects.filter(
      id=serializer.validated_data['group_id'], trainer=request.user, is_active=True
    ).select_related('client_registration_form').first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    registration_form = getattr(group, 'client_registration_form', None)

    if registration_form is None or not registration_form.is_active:
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

    validate_required_answers(registration_form.fields, answers)
    first_name = str(answers.get('first_name', '')).strip()
    last_name = str(answers.get('last_name', '')).strip()
    email = str(answers.get('email', '')).strip().lower()

    if not first_name or not last_name or not email:
      return Response({'message': 'First name, last name, and email are required.'}, status=status.HTTP_400_BAD_REQUEST)

    temporary_password = serializer.validated_data['password']
    onboarding_method = (
      ClientAccess.ONBOARDING_GROUP_REGISTRATION
      if registration_submission
      else ClientAccess.ONBOARDING_MANUAL
    )

    try:
      with transaction.atomic():
        client_kwargs = {
          'trainer': request.user,
          'group': group,
          'registration_submission': registration_submission,
          'onboarding_method': onboarding_method,
          'first_name': first_name,
          'last_name': last_name,
          'email': email,
          'username': serializer.validated_data['username'],
          'temporary_password': make_password(temporary_password),
          'photo': serializer.validated_data.get('photo', ''),
          'registration_answers': answers,
          'must_change_password': True,
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
        {'message': 'The email or username already exists under this trainer.'},
        status=status.HTTP_400_BAD_REQUEST,
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
          'Client account created and temporary credentials emailed.'
          if credentials_sent
          else 'Client account created. Temporary credentials were not emailed.'
        ),
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
    ).select_related('group', 'group__trainer').first()

  def get(self, request, public_slug):
    registration_form = self._form(public_slug)

    if registration_form is None:
      return Response({'message': 'Registration form not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(
      {
        'group': {'id': registration_form.group_id, 'name': registration_form.group.name},
        'trainer_name': registration_form.group.trainer.get_full_name() or registration_form.group.trainer.username,
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

    send_mail(
      subject=f'Your {registration_form.group.name} registration',
      message=(
        f'Your registration was submitted for trainer review.\n\n'
        f'Reference ID: {submission.reference_id}\n\n'
        f'Your trainer will send account credentials after review.'
      ),
      from_email=None,
      recipient_list=[submission.email],
      fail_silently=False,
    )

    return Response(
      {'reference_id': submission.reference_id, 'message': 'Registration submitted for trainer review.'},
      status=status.HTTP_201_CREATED,
    )


class GroupClientAccessListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request, group_id):
    group = TrainerGroup.objects.filter(id=group_id, trainer=request.user, is_active=True).first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    # Include suspended clients too so the trainer can see status and reactivate.
    clients = ClientAccess.objects.filter(trainer=request.user, group=group).order_by('-is_active', '-created_at')
    registration_submissions = group.registration_submissions.filter(
      status=GroupRegistrationSubmission.STATUS_PENDING
    )

    return Response(
      {
        'group': TrainerGroupSerializer(group).data,
        'clients': ClientAccessSerializer(clients, many=True).data,
        'registration_submissions': GroupRegistrationSubmissionSerializer(registration_submissions, many=True).data,
      }
    )


class ClientAccessDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_client(self, request, client_id):
    # No is_active filter: the trainer can open a suspended client to reactivate.
    return ClientAccess.objects.filter(
      id=client_id,
      trainer=request.user,
    ).select_related('group', 'lead_submission', 'trainer').first()

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
          'trainer_notes': client_access.trainer_notes,
        },
        'group': TrainerGroupSerializer(group).data,
        'registration_fields': registration_form.fields if registration_form and registration_form.is_active else [],
        'lead_submission': (
          LeadSubmissionSerializer(client_access.lead_submission).data if client_access.lead_submission else None
        ),
        'trainer_notes': client_access.trainer_notes,
        'trainer_notes_updated_at': serialize_datetime(client_access.trainer_notes_updated_at),
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
    username = str(request.data.get('username', client_access.username)).strip()

    if not first_name or not last_name or not email or not username:
      return Response({'message': 'First name, last name, email, and username are required.'}, status=status.HTTP_400_BAD_REQUEST)

    if ClientAccess.objects.filter(trainer=request.user, username=username).exclude(id=client_access.id).exists():
      return Response({'message': 'Username is already used by another client.'}, status=status.HTTP_400_BAD_REQUEST)

    if ClientAccess.objects.filter(trainer=request.user, email=email).exclude(id=client_access.id).exists():
      return Response({'message': 'Email is already used by another client.'}, status=status.HTTP_400_BAD_REQUEST)

    client_access.first_name = first_name
    client_access.last_name = last_name
    client_access.email = email
    client_access.username = username
    client_access.registration_answers = registration_answers

    if 'is_active' in request.data:
      client_access.is_active = bool(request.data.get('is_active'))

    client_access.save(
      update_fields=['first_name', 'last_name', 'email', 'username', 'registration_answers', 'is_active', 'updated_at']
    )

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Client information updated.'})


class ClientTrainerNotesView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    client_access.trainer_notes = str(request.data.get('notes', '')).strip()
    client_access.trainer_notes_updated_at = timezone.now()
    client_access.save(update_fields=['trainer_notes', 'trainer_notes_updated_at', 'updated_at'])

    return Response(
      {
        'trainer_notes': client_access.trainer_notes,
        'trainer_notes_updated_at': serialize_datetime(client_access.trainer_notes_updated_at),
        'message': 'Trainer notes saved.',
      }
    )

class ClientAccessPhotoView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientPhotoUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access.photo = serializer.validated_data['photo']
    client_access.save(update_fields=['photo', 'updated_at'])

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Client photo updated.'})


class ClientAdditionalInfoView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientAdditionalInfoUpdateSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access.additional_info = serializer.validated_data['additional_info']

    if 'additional_info_shared' in serializer.validated_data:
      client_access.additional_info_shared = serializer.validated_data['additional_info_shared']

    client_access.save(update_fields=['additional_info', 'additional_info_shared', 'updated_at'])

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': 'Additional information saved.'})


class ClientReminderListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'reminders': ClientReminderSerializer(client.reminders.all(), many=True).data})

  def post(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientReminderSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    reminder = serializer.save(trainer=request.user, client=client)

    return Response(
      {'reminder': ClientReminderSerializer(reminder).data, 'message': 'Reminder scheduled.'},
      status=status.HTTP_201_CREATED,
    )


class ClientReminderDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def _reminder(self, request, reminder_id):
    return ClientReminder.objects.filter(id=reminder_id, trainer=request.user).select_related('client').first()

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


class TrainerUpcomingRemindersView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    reminders_queryset = ClientReminder.objects.filter(trainer=request.user).select_related('client')
    pending = list(reminders_queryset.filter(status=ClientReminder.STATUS_PENDING))
    completed = reminders_queryset.filter(status=ClientReminder.STATUS_DONE)
    pending_profile_edits_queryset = ClientDetailChangeRequest.objects.filter(
      client__trainer=request.user,
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
  permission_classes = [permissions.IsAuthenticated]

  def _client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

  def get(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'progress': ProgressEntrySerializer(client.progress_entries.all(), many=True).data})

  def post(self, request, client_id):
    client = self._client(request, client_id)

    if client is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ProgressEntrySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    entry = serializer.save(
      trainer=request.user,
      client=client,
      created_by=request.user.get_full_name() or request.user.username,
    )

    return Response(
      {'progress': ProgressEntrySerializer(entry).data, 'message': 'Progress record saved.'},
      status=status.HTTP_201_CREATED,
    )


class ClientProgressDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, entry_id):
    entry = ProgressEntry.objects.filter(id=entry_id, client__trainer=request.user).first()

    if entry is None:
      return Response({'message': 'Progress record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ProgressEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save()

    return Response({'progress': ProgressEntrySerializer(entry).data, 'message': 'Progress record updated.'})

  def delete(self, request, entry_id):
    entry = ProgressEntry.objects.filter(id=entry_id, client__trainer=request.user).first()

    if entry is None:
      return Response({'message': 'Progress record not found.'}, status=status.HTTP_404_NOT_FOUND)

    entry.delete()
    return Response({'message': 'Progress record deleted.'})


class TrainerClientChangeRequestActionView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, client_id, request_id):
    change_request = ClientDetailChangeRequest.objects.filter(
      id=request_id,
      client_id=client_id,
      client__trainer=request.user,
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

    change_request.trainer_note = note
    change_request.reviewed_at = timezone.now()
    change_request.save(update_fields=['status', 'trainer_note', 'reviewed_at'])

    return Response(
      {
        'change_request': ClientDetailChangeRequestSerializer(change_request).data,
        'client': ClientAccessSerializer(client_access).data,
        'message': f'Change request {change_request.status}.',
      }
    )


class ClientTrainerLookupView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def post(self, request):
    serializer = ClientTrainerLookupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    trainer_id = serializer.validated_data['trainer_id']
    profile = TrainerProfile.objects.select_related('user').filter(trainer_id__iexact=trainer_id).first()

    if profile is None:
      return Response({'message': 'Trainer ID not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response(
      {
        'trainer_id': profile.trainer_id,
        'trainer_name': profile.user.get_full_name() or profile.user.username,
        'message': 'Trainer ID found.',
      }
    )


class TrainerDirectoryView(APIView):
  permission_classes = [permissions.AllowAny]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'directory'

  def get(self, request):
    search = str(request.query_params.get('search', '')).strip()
    profiles = (
      TrainerProfile.objects.select_related('user')
      .exclude(trainer_id__isnull=True)
      .exclude(trainer_id__exact='')
    )

    if search:
      profiles = profiles.filter(
        Q(trainer_id__icontains=search)
        | Q(user__first_name__icontains=search)
        | Q(user__last_name__icontains=search)
      )

    profiles = profiles.order_by('user__first_name', 'user__last_name')[:100]

    trainers = [
      {
        'trainer_id': profile.trainer_id,
        'trainer_name': profile.user.get_full_name() or profile.user.username,
      }
      for profile in profiles
    ]

    return Response({'trainers': trainers})


class ClientAccessStatusView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    client_access.is_active = bool(request.data.get('is_active'))
    client_access.save(update_fields=['is_active', 'updated_at'])
    state = 'reactivated' if client_access.is_active else 'suspended'

    return Response({'client': ClientAccessSerializer(client_access).data, 'message': f'Client access {state}.'})


class ClientAccessPasswordResetView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    # Consistent with manual client creation (Option A): the trainer defines
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

    send_mail(
      subject='Your CoachFlow client password reset',
      message=(
        f'Your trainer reset your CoachFlow client password.\n\n'
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

  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    with transaction.atomic():
      TemplateAssignment.objects.filter(client=client_access).delete()
      TrackingEntry.objects.filter(client=client_access).delete()
      ChatMessage.objects.filter(client=client_access).delete()
      ClientReminder.objects.filter(client=client_access).delete()
      ProgressEntry.objects.filter(client=client_access).delete()
      ClientDetailChangeRequest.objects.filter(client=client_access).delete()

      client_access.additional_info = []
      client_access.additional_info_shared = False
      client_access.trainer_notes = ''
      client_access.trainer_notes_updated_at = None
      client_access.save(
        update_fields=[
          'additional_info',
          'additional_info_shared',
          'trainer_notes',
          'trainer_notes_updated_at',
          'updated_at',
        ]
      )

    return Response(
      {
        'client': ClientAccessSerializer(client_access).data,
        'message': "Client reset. Templates, entries, chat, and notes were cleared; profile details were kept.",
      }
    )


class ClientAccessDeleteView(APIView):
  """Permanently delete a client account and every record tied to it."""

  permission_classes = [permissions.IsAuthenticated]

  def delete(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

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

      # Cascades assignments, entries, chat, reminders, progress, change requests, token.
      client_access.delete()

    return Response({'message': 'Client account permanently deleted.'})


class TrainerReferenceCategoryListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    categories = ReferenceCategory.objects.filter(trainer=request.user)
    return Response({'categories': ReferenceCategorySerializer(categories, many=True).data})

  def post(self, request):
    category_limit = plan_limit(request.user, 'categories')

    if category_limit is not None and ReferenceCategory.objects.filter(trainer=request.user).count() >= category_limit:
      return Response({'message': 'The Version 1 category limit has been reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = ReferenceCategorySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    subcategory_limit = plan_limit(request.user, 'subcategories_per_category')

    if subcategory_limit is not None and len(serializer.validated_data.get('subcategories', [])) > subcategory_limit:
      return Response({'message': f'Each category can contain up to {subcategory_limit} subcategories.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      category = serializer.save(trainer=request.user)
    except IntegrityError:
      return Response({'message': 'Category name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'category': ReferenceCategorySerializer(category).data,
        'message': 'Category saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrainerReferenceCategoryDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_category(self, request, category_id):
    return ReferenceCategory.objects.filter(id=category_id, trainer=request.user).first()

  def put(self, request, category_id):
    category = self.get_category(request, category_id)

    if category is None:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ReferenceCategorySerializer(category, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)

    subcategory_limit = plan_limit(request.user, 'subcategories_per_category')
    next_subcategories = serializer.validated_data.get('subcategories', category.subcategories)

    if subcategory_limit is not None and len(next_subcategories) > subcategory_limit:
      return Response({'message': f'Each category can contain up to {subcategory_limit} subcategories.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      serializer.save()
    except IntegrityError:
      return Response({'message': 'Category name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response({'category': ReferenceCategorySerializer(category).data, 'message': 'Category updated successfully.'})

  def delete(self, request, category_id):
    category = self.get_category(request, category_id)

    if category is None:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    try:
      category.delete()
    except ProtectedError:
      return Response(
        {'message': 'Category still has references. Move or delete them first.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    return Response({'message': 'Category deleted.'})


class TrainerReferenceListView(APIView):
  permission_classes = [permissions.IsAuthenticated]
  parser_classes = [MultiPartParser, FormParser, JSONParser]

  def get(self, request):
    references = TrainerReference.objects.filter(trainer=request.user).select_related('category')
    reference_limit = plan_limit(request.user, 'references')
    return Response(
      {
        'references': TrainerReferenceSerializer(references, many=True, context={'request': request}).data,
        'usage': {'used': references.count(), 'limit': reference_limit},
      }
    )

  def post(self, request):
    reference_limit = plan_limit(request.user, 'references')

    if reference_limit is not None and TrainerReference.objects.filter(trainer=request.user).count() >= reference_limit:
      return Response(
        {'message': 'You have reached the Version 1 reference limit.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    serializer = TrainerReferenceSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)
    category = serializer.validated_data.get('category')

    if category is None or category.trainer_id != request.user.id:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    reference = serializer.save(trainer=request.user)

    return Response(
      {
        'reference': TrainerReferenceSerializer(reference, context={'request': request}).data,
        'message': 'Reference saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrainerReferenceDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]
  parser_classes = [MultiPartParser, FormParser, JSONParser]

  def get_reference(self, request, reference_id):
    return TrainerReference.objects.filter(id=reference_id, trainer=request.user).select_related('category').first()

  def get(self, request, reference_id):
    reference = self.get_reference(request, reference_id)

    if reference is None:
      return Response({'message': 'Reference not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'reference': TrainerReferenceSerializer(reference, context={'request': request}).data})

  def put(self, request, reference_id):
    reference = self.get_reference(request, reference_id)

    if reference is None:
      return Response({'message': 'Reference not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = TrainerReferenceSerializer(reference, data=request.data, partial=True, context={'request': request})
    serializer.is_valid(raise_exception=True)
    category = serializer.validated_data.get('category')

    if category is not None and category.trainer_id != request.user.id:
      return Response({'message': 'Category not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer.save()

    return Response(
      {
        'reference': TrainerReferenceSerializer(reference, context={'request': request}).data,
        'message': 'Reference updated successfully.',
      }
    )

  def delete(self, request, reference_id):
    reference = self.get_reference(request, reference_id)

    if reference is None:
      return Response({'message': 'Reference not found.'}, status=status.HTTP_404_NOT_FOUND)

    reference.delete()
    return Response({'message': 'Reference deleted.'})


class StandardTemplateListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    adopted_keys = set(
      TrackingTemplate.objects.filter(trainer=request.user, is_active=True)
      .exclude(standard_key='')
      .values_list('standard_key', flat=True)
    )
    standard_templates = [{**template, 'adopted': template['key'] in adopted_keys} for template in STANDARD_TEMPLATES]
    return Response({'standard_templates': standard_templates})


class StandardTemplateAdoptView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request):
    key = str(request.data.get('key', '')).strip()
    standard_template = get_standard_template(key)

    if standard_template is None:
      return Response({'message': 'Standard template not found.'}, status=status.HTTP_404_NOT_FOUND)

    template_limit = plan_limit(request.user, 'templates')
    if template_limit is not None and TrackingTemplate.objects.filter(trainer=request.user, is_active=True).count() >= template_limit:
      return Response({'message': f'Maximum of {template_limit} templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      template = TrackingTemplate.objects.create(
        trainer=request.user,
        name=standard_template['name'],
        purpose=standard_template['purpose'],
        cadence=standard_template['cadence'],
        accent=standard_template['accent'],
        fields=standard_template['fields'],
        standard_key=key,
      )
    except IntegrityError:
      return Response({'message': 'A template with this name already exists.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'template': TrackingTemplateSerializer(template, context={'request': request}).data,
        'message': f'{template.name} template added.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrackingTemplateListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    templates = TrackingTemplate.objects.filter(trainer=request.user, is_active=True).prefetch_related('assignments')
    return Response(
      {
        'templates': TrackingTemplateSerializer(templates, many=True, context={'request': request}).data,
        'max_templates': plan_limit(request.user, 'templates'),
        'plan': trainer_plan(request.user),
      }
    )

  def post(self, request):
    template_limit = plan_limit(request.user, 'templates')
    if template_limit is not None and TrackingTemplate.objects.filter(trainer=request.user, is_active=True).count() >= template_limit:
      return Response({'message': f'Maximum of {template_limit} templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = TrackingTemplateSerializer(data=request.data, context={'request': request})
    serializer.is_valid(raise_exception=True)

    try:
      template = serializer.save(trainer=request.user)
    except IntegrityError:
      return Response({'message': 'Template name must be unique.'}, status=status.HTTP_400_BAD_REQUEST)

    return Response(
      {
        'template': TrackingTemplateSerializer(template, context={'request': request}).data,
        'message': 'Template saved successfully.',
      },
      status=status.HTTP_201_CREATED,
    )


class TrackingTemplateDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_template(self, request, template_id):
    return TrackingTemplate.objects.filter(id=template_id, trainer=request.user, is_active=True).first()

  def get(self, request, template_id):
    template = self.get_template(request, template_id)

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    return Response({'template': TrackingTemplateSerializer(template, context={'request': request}).data})

  def put(self, request, template_id):
    template = self.get_template(request, template_id)

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

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

    template.delete()
    return Response({'message': 'Template deleted. Past client entries are kept.'})


class ClientTemplateAssignmentListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

  def get(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignments = (
      client_access.template_assignments.filter(template__is_active=True)
      .select_related('template')
      .prefetch_related('references__category')
    )
    return Response({'assignments': TemplateAssignmentSerializer(assignments, many=True, context={'request': request}).data})

  def post(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    template = TrackingTemplate.objects.filter(
      id=request.data.get('template_id'),
      trainer=request.user,
      is_active=True,
    ).first()

    if template is None:
      return Response({'message': 'Template not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignment, created = TemplateAssignment.objects.get_or_create(client=client_access, template=template)

    if not created:
      return Response({'message': 'Template is already assigned to this client.'}, status=status.HTTP_400_BAD_REQUEST)

    set_assignment_references(assignment, request.user, request.data.get('reference_ids'))

    return Response(
      {
        'assignment': TemplateAssignmentSerializer(assignment, context={'request': request}).data,
        'message': f'{template.name} assigned to {client_access.first_name}.',
      },
      status=status.HTTP_201_CREATED,
    )


def set_assignment_references(assignment, trainer, reference_ids):
  if reference_ids is None or not isinstance(reference_ids, list):
    return

  references = TrainerReference.objects.filter(trainer=trainer, id__in=reference_ids)
  assignment.references.set(references)


class ClientTemplateAssignmentDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_assignment(self, request, client_id, assignment_id):
    return TemplateAssignment.objects.filter(
      id=assignment_id,
      client_id=client_id,
      client__trainer=request.user,
    ).select_related('template', 'client').first()

  def put(self, request, client_id, assignment_id):
    assignment = self.get_assignment(request, client_id, assignment_id)

    if assignment is None:
      return Response({'message': 'Template assignment not found.'}, status=status.HTTP_404_NOT_FOUND)

    set_assignment_references(assignment, request.user, request.data.get('reference_ids', []))

    return Response(
      {
        'assignment': TemplateAssignmentSerializer(assignment, context={'request': request}).data,
        'message': 'Shared references updated.',
      }
    )

  def delete(self, request, client_id, assignment_id):
    assignment = self.get_assignment(request, client_id, assignment_id)

    if assignment is None:
      return Response({'message': 'Template assignment not found.'}, status=status.HTTP_404_NOT_FOUND)

    assignment.delete()
    return Response({'message': 'Template unassigned. Past entries are kept.'})


class ClientTrackingEntryListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    entries = client_access.tracking_entries.all()
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
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientTrackingEntrySubmitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    template = TrackingTemplate.objects.filter(
      id=serializer.validated_data['template_id'],
      trainer=request.user,
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
        'edited_by_trainer': True,
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


class TrainerTrackingEntryDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, entry_id):
    entry = TrackingEntry.objects.filter(id=entry_id, client__trainer=request.user).first()

    if entry is None:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not entry_editable(entry):
      return Response(
        {'message': 'This entry is older than 72 hours and can no longer be edited.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    serializer = TrackingEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save(edited_by_trainer=True)

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry updated successfully.',
      }
    )


class TrainerClientChatView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get_client(self, request, client_id):
    return ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

  def get(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    messages = ChatMessage.objects.filter(trainer=request.user, client=client_access)
    after_id = request.query_params.get('after')

    if after_id:
      messages = messages.filter(id__gt=after_id)

    ChatMessage.objects.filter(
      trainer=request.user,
      client=client_access,
      sender=ChatMessage.SENDER_CLIENT,
      is_read=False,
    ).update(is_read=True)

    return Response({'messages': ChatMessageSerializer(messages, many=True).data})

  def post(self, request, client_id):
    client_access = self.get_client(request, client_id)

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ChatMessageSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    message = serializer.save(trainer=request.user, client=client_access, sender=ChatMessage.SENDER_TRAINER)

    return Response({'chat_message': ChatMessageSerializer(message).data}, status=status.HTTP_201_CREATED)


class TrainerChatUnreadView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    unread_rows = (
      ChatMessage.objects.filter(
        trainer=request.user,
        client__is_active=True,
        sender=ChatMessage.SENDER_CLIENT,
        is_read=False,
      )
      .values('client_id')
      .annotate(unread_count=Count('id'))
    )
    by_client = {str(row['client_id']): row['unread_count'] for row in unread_rows}

    return Response(
      {
        'unread_count': sum(by_client.values()),
        'by_client': by_client,
      }
    )


class ClientPasswordChangeView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

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
        'client': ClientAccessSerializer(client_access, context={'include_trainer_notes': True}).data,
        'message': 'Password changed successfully.',
      }
    )


class ClientDashboardView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client_access = request.auth
    now = timezone.localtime()
    week_start = now.date() - timedelta(days=now.weekday())
    entries = client_access.tracking_entries.all()
    assignments = client_access.template_assignments.filter(template__is_active=True)
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
        'group': TrainerGroupSerializer(client_access.group).data,
        'registration_fields': registration_form.fields if registration_form and registration_form.is_active else [],
        'lead_submission': (
          LeadSubmissionSerializer(client_access.lead_submission).data if client_access.lead_submission else None
        ),
        'trainer_profile': build_public_trainer_profile(client_access.trainer, request),
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
        {'message': 'You already have an edit request awaiting your trainer\'s approval.'},
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
        'message': 'Edit request submitted. Your trainer will review it.',
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
        {'message': 'An account deletion request is already awaiting trainer review.'},
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
        'message': 'Account deletion request sent to your trainer for review.',
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
    assignments = (
      request.auth.template_assignments.filter(template__is_active=True)
      .select_related('template')
      .prefetch_related('references__category')
    )
    templates = []

    for assignment in assignments:
      template_data = TrackingTemplateSerializer(assignment.template, context={'request': request}).data
      template_data['assignment_id'] = assignment.id
      template_data['references'] = TrackingTemplateReferenceSerializer(
        assignment.references.all(),
        many=True,
        context={'request': request},
      ).data
      templates.append(template_data)

    return Response({'templates': templates})


class ClientTrackingEntryView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    entries = request.auth.tracking_entries.all()
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

  def post(self, request):
    serializer = ClientTrackingEntrySubmitSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    client_access = request.auth
    template = TrackingTemplate.objects.filter(
      id=serializer.validated_data['template_id'],
      trainer=client_access.trainer,
      is_active=True,
      assignments__client=client_access,
    ).first()

    if template is None:
      return Response({'message': 'Template is not assigned to you.'}, status=status.HTTP_404_NOT_FOUND)

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
      edited_by_trainer=False,
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
    return Response({'progress': ProgressEntrySerializer(request.auth.progress_entries.all(), many=True).data})


class ClientTrackingEntryDetailView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def put(self, request, entry_id):
    entry = TrackingEntry.objects.filter(id=entry_id, client=request.auth).first()

    if entry is None:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

    if not entry_editable(entry):
      return Response(
        {'message': 'This entry is older than 72 hours and can no longer be edited.'},
        status=status.HTTP_403_FORBIDDEN,
      )

    serializer = TrackingEntrySerializer(entry, data=request.data, partial=True)
    serializer.is_valid(raise_exception=True)
    serializer.save(edited_by_trainer=False)

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry updated successfully.',
      }
    )


class ClientChatView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    client_access = request.auth
    messages = ChatMessage.objects.filter(trainer=client_access.trainer, client=client_access)
    after_id = request.query_params.get('after')

    if after_id:
      messages = messages.filter(id__gt=after_id)

    ChatMessage.objects.filter(
      trainer=client_access.trainer,
      client=client_access,
      sender=ChatMessage.SENDER_TRAINER,
      is_read=False,
    ).update(is_read=True)

    return Response({'messages': ChatMessageSerializer(messages, many=True).data})

  def post(self, request):
    client_access = request.auth
    serializer = ChatMessageSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    message = serializer.save(trainer=client_access.trainer, client=client_access, sender=ChatMessage.SENDER_CLIENT)

    return Response({'chat_message': ChatMessageSerializer(message).data}, status=status.HTTP_201_CREATED)


class ClientChatUnreadView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def get(self, request):
    unread_count = ChatMessage.objects.filter(
      trainer=request.auth.trainer,
      client=request.auth,
      sender=ChatMessage.SENDER_TRAINER,
      is_read=False,
    ).count()

    return Response({'unread_count': unread_count})


def _support_reporter_filter(role, reporter):
  if role == SupportIncident.ROLE_TRAINER:
    return {'reporter_trainer': reporter, 'reporter_role': role}
  return {'reporter_client': reporter, 'reporter_role': role}


def _support_reporter_identity(role, reporter):
  if role == SupportIncident.ROLE_TRAINER:
    return reporter.get_full_name() or reporter.username, reporter.email
  return f'{reporter.first_name} {reporter.last_name}'.strip() or reporter.username, reporter.email


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


class TrainerSupportIncidentListView(APIView):
  permission_classes = [permissions.IsAuthenticated]
  parser_classes = [JSONParser, FormParser, MultiPartParser]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request):
    return _support_incident_list(request, SupportIncident.ROLE_TRAINER, request.user)

  def post(self, request):
    return _support_incident_create(request, SupportIncident.ROLE_TRAINER, request.user)


class TrainerSupportIncidentDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]
  throttle_classes = [ScopedRateThrottle]
  throttle_scope = 'support'

  def get(self, request, incident_id):
    incident = SupportIncident.objects.filter(
      incident_id=incident_id, reporter_trainer=request.user, reporter_role=SupportIncident.ROLE_TRAINER
    ).prefetch_related('messages').first()
    if incident is None:
      return Response({'message': 'Support request not found.'}, status=status.HTTP_404_NOT_FOUND)
    return Response({'incident': SupportIncidentSerializer(incident, context={'request': request}).data})

  def post(self, request, incident_id):
    return _support_incident_action(request, SupportIncident.ROLE_TRAINER, request.user, incident_id)


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
