from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import RecycledTrainerAccount, TrainerProfile
from .serializers import (
  EmailAvailabilitySerializer,
  EmailOtpRequestSerializer,
  EmailOtpVerifySerializer,
  PasswordResetConfirmSerializer,
  PasswordResetOtpRequestSerializer,
  PasswordResetOtpVerifySerializer,
  TrainerAccountSerializer,
  TrainerLoginSerializer,
  TrainerPasswordChangeSerializer,
  TrainerProfileSerializer,
  TrainerProfileStatusSerializer,
  TrainerSignupSerializer,
  UsernameAvailabilitySerializer,
)
from .email_verification import OtpCooldownError, send_email_otp, verify_email_otp

User = get_user_model()


def serialize_datetime(value):
  return value.isoformat() if value else None


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
      send_email_otp(email)
    except OtpCooldownError as error:
      return Response(
        {'message': f'Please wait {error.remaining_seconds} seconds before requesting another OTP.'},
        status=status.HTTP_429_TOO_MANY_REQUESTS,
      )

    return Response(
      {
        'email': email,
        'message': 'Verification code sent. In local testing, check the Django backend terminal.',
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
      send_email_otp(email, purpose='password-reset')
    except OtpCooldownError as error:
      return Response(
        {'message': f'Please wait {error.remaining_seconds} seconds before requesting another OTP.'},
        status=status.HTTP_429_TOO_MANY_REQUESTS,
      )

    return Response(
      {
        'email': email,
        'message': 'Password reset code sent. In local testing, check the Django backend terminal.',
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
