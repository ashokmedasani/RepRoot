from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.conf import settings
from django.core.mail import send_mail
from django.db import IntegrityError, transaction
from django.db.models import ProtectedError
from django.utils import timezone
from django.utils.crypto import get_random_string
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import (
  ChatMessage,
  ClientAccess,
  ClientRegistrationForm,
  LeadSubmission,
  RecycledTrainerAccount,
  ReferenceCategory,
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
  ClientLoginSerializer,
  ClientAccessSerializer,
  ClientPasswordChangeSerializer,
  ClientRegistrationFormSerializer,
  ClientTrackingEntrySubmitSerializer,
  EmailAvailabilitySerializer,
  EmailOtpRequestSerializer,
  EmailOtpVerifySerializer,
  LeadSubmissionSerializer,
  PasswordResetConfirmSerializer,
  PasswordResetOtpRequestSerializer,
  PasswordResetOtpVerifySerializer,
  PublicLeadFormSerializer,
  PublicLeadSubmissionSerializer,
  ReferenceCategorySerializer,
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
  TrainerProfileStatusSerializer,
  TrainerReferenceSerializer,
  TrainerSignupSerializer,
  UsernameAvailabilitySerializer,
)
from .client_auth import ClientTokenAuthentication, IsAuthenticatedClient, issue_client_token
from .email_verification import OtpCooldownError, send_email_otp, verify_email_otp
from .standard_templates import STANDARD_TEMPLATES, get_standard_template

MAX_TRACKING_TEMPLATES = 5

User = get_user_model()


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
      'terms_accepted': profile.terms_accepted,
      'privacy_policy_accepted': profile.privacy_policy_accepted,
      'created_at': serialize_datetime(profile.created_at),
      'updated_at': serialize_datetime(profile.updated_at),
    }

  return snapshot


class UsernameAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]

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

  def post(self, request):
    from .serializers import normalize_trainer_code
    from rest_framework import serializers as drf_serializers

    try:
      code = normalize_trainer_code(request.data.get('trainer_code', ''))
    except drf_serializers.ValidationError as error:
      return Response({'available': False, 'message': error.detail[0]}, status=status.HTTP_200_OK)

    is_available = not TrainerProfile.objects.filter(trainer_code__iexact=code).exists()

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
    return Response({'trainer_code': request.user.trainer_profile.trainer_code})

  def put(self, request):
    from .serializers import TrainerCodeSerializer

    serializer = TrainerCodeSerializer(data=request.data, context={'trainer': request.user})
    serializer.is_valid(raise_exception=True)
    profile = serializer.save()

    return Response({'trainer_code': profile.trainer_code, 'message': 'Trainer code saved.'})


class EmailAvailabilityView(APIView):
  permission_classes = [permissions.AllowAny]

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
    serializer = TrainerPasswordChangeSerializer(data=request.data)
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
        'max_groups': 5,
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
    if TrainerGroup.objects.filter(trainer=request.user, is_active=True).count() >= 5:
      return Response({'message': 'Maximum groups limit reached.'}, status=status.HTTP_400_BAD_REQUEST)

    serializer = TrainerGroupSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

    try:
      group = serializer.save(trainer=request.user)
    except IntegrityError:
      return Response({'message': 'Group Name must be unique for this trainer.'}, status=status.HTTP_400_BAD_REQUEST)

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
    submission = LeadSubmission.objects.filter(
      id=submission_id,
      lead_form__trainer=request.user,
      status=LeadSubmission.STATUS_PENDING,
      is_active=True,
    ).first()

    if submission is None:
      return Response({'message': 'Pending form request not found.'}, status=status.HTTP_404_NOT_FOUND)

    serializer = ClientAccessCreateSerializer(data=request.data)
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

    from .serializers import validate_required_answers

    validate_required_answers(registration_form.fields, registration_answers)

    client_password = serializer.validated_data['password']

    try:
      with transaction.atomic():
        client_access = ClientAccess.objects.create(
          trainer=request.user,
          group=group,
          lead_submission=submission,
          first_name=submission.first_name,
          last_name=submission.last_name,
          email=submission.email,
          username=serializer.validated_data['username'],
          temporary_password=make_password(client_password),
          registration_answers=registration_answers,
          must_change_password=False,
        )
        submission.status = LeadSubmission.STATUS_APPROVED
        submission.converted_at = timezone.now()
        submission.save(update_fields=['status', 'converted_at', 'updated_at'])
    except IntegrityError:
      return Response(
        {'message': 'Same email or username already exists under this trainer.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    send_mail(
      subject='Your CoachFlow client access',
      message=(
        f'Your client access has been created.\n\n'
        f'Username: {client_access.username}\n'
        f'Password: the password your trainer created for you.\n\n'
        f'Use these details to log in to the client portal.'
      ),
      from_email=None,
      recipient_list=[client_access.email],
      fail_silently=False,
    )

    return Response(
      {
        'client_access': ClientAccessSerializer(client_access).data,
        'message': 'Client access created. The client can log in with the username and password you created.',
      },
      status=status.HTTP_201_CREATED,
    )


class GroupClientAccessListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request, group_id):
    group = TrainerGroup.objects.filter(id=group_id, trainer=request.user, is_active=True).first()

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    clients = ClientAccess.objects.filter(trainer=request.user, group=group, is_active=True)

    return Response(
      {
        'group': TrainerGroupSerializer(group).data,
        'clients': ClientAccessSerializer(clients, many=True).data,
      }
    )


class ClientAccessDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request, client_id):
    client_access = ClientAccess.objects.filter(
      id=client_id,
      trainer=request.user,
      is_active=True,
    ).select_related('group', 'lead_submission', 'trainer').first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

    group = client_access.group
    registration_form = getattr(group, 'client_registration_form', None)

    return Response(
      {
        'client': ClientAccessSerializer(client_access).data,
        'group': TrainerGroupSerializer(group).data,
        'registration_fields': registration_form.fields if registration_form and registration_form.is_active else [],
        'lead_submission': LeadSubmissionSerializer(client_access.lead_submission).data,
        'trainer_notes': client_access.trainer_notes,
        'trainer_notes_updated_at': serialize_datetime(client_access.trainer_notes_updated_at),
      }
    )


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


class ClientAccessPasswordResetView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def post(self, request, client_id):
    client_access = ClientAccess.objects.filter(id=client_id, trainer=request.user, is_active=True).first()

    if client_access is None:
      return Response({'message': 'Client access record not found.'}, status=status.HTTP_404_NOT_FOUND)

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


class TrainerReferenceCategoryListView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def get(self, request):
    categories = ReferenceCategory.objects.filter(trainer=request.user)
    return Response({'categories': ReferenceCategorySerializer(categories, many=True).data})

  def post(self, request):
    serializer = ReferenceCategorySerializer(data=request.data)
    serializer.is_valid(raise_exception=True)

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
    return Response({'references': TrainerReferenceSerializer(references, many=True, context={'request': request}).data})

  def post(self, request):
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

    if TrackingTemplate.objects.filter(trainer=request.user, is_active=True).count() >= MAX_TRACKING_TEMPLATES:
      return Response({'message': 'Maximum of 5 templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

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
        'max_templates': MAX_TRACKING_TEMPLATES,
      }
    )

  def post(self, request):
    if TrackingTemplate.objects.filter(trainer=request.user, is_active=True).count() >= MAX_TRACKING_TEMPLATES:
      return Response({'message': 'Maximum of 5 templates reached.'}, status=status.HTTP_400_BAD_REQUEST)

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


class TrainerTrackingEntryDetailView(APIView):
  permission_classes = [permissions.IsAuthenticated]

  def put(self, request, entry_id):
    entry = TrackingEntry.objects.filter(id=entry_id, client__trainer=request.user).first()

    if entry is None:
      return Response({'message': 'Tracking entry not found.'}, status=status.HTTP_404_NOT_FOUND)

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


class ClientPasswordChangeView(APIView):
  authentication_classes = [ClientTokenAuthentication]
  permission_classes = [IsAuthenticatedClient]

  def post(self, request):
    serializer = ClientPasswordChangeSerializer(data=request.data, context={'client_access': request.auth})
    serializer.is_valid(raise_exception=True)
    client_access = serializer.save()

    return Response(
      {
        'client': ClientAccessSerializer(client_access).data,
        'message': 'Password changed successfully.',
      }
    )


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
        'lead_submission': LeadSubmissionSerializer(client_access.lead_submission).data,
      }
    )


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

    entry, created = TrackingEntry.objects.update_or_create(
      client=client_access,
      template=template,
      entry_date=serializer.validated_data['entry_date'],
      defaults={
        'template_name': template.name,
        'answers': serializer.validated_data['answers'],
        'note': serializer.validated_data['note'],
        'edited_by_trainer': False,
      },
    )

    return Response(
      {
        'entry': TrackingEntrySerializer(entry).data,
        'message': 'Entry submitted successfully.' if created else 'Entry updated successfully.',
      },
      status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
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
