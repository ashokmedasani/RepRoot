from django.contrib.auth import authenticate, get_user_model
from rest_framework import serializers

from .email_verification import consume_verified_email_token
from .models import TrainerProfile

User = get_user_model()


def validate_password_strength(password: str) -> None:
  if len(password) < 8 or password.isalnum():
    raise serializers.ValidationError('Password must be at least 8 characters and include 1 special character.')


class UsernameAvailabilitySerializer(serializers.Serializer):
  username = serializers.CharField(max_length=150)

  def validate_username(self, value: str) -> str:
    username = value.strip().lower()

    if not username:
      raise serializers.ValidationError('Username is required.')

    return username


class EmailAvailabilitySerializer(serializers.Serializer):
  email = serializers.EmailField()

  def validate_email(self, value: str) -> str:
    email = value.strip().lower()

    if not email:
      raise serializers.ValidationError('Email is required.')

    return email


class EmailOtpRequestSerializer(serializers.Serializer):
  email = serializers.EmailField()

  def validate_email(self, value: str) -> str:
    return value.strip().lower()


class EmailOtpVerifySerializer(serializers.Serializer):
  email = serializers.EmailField()
  otp = serializers.CharField(min_length=6, max_length=6)

  def validate_email(self, value: str) -> str:
    return value.strip().lower()


class TrainerSignupSerializer(serializers.Serializer):
  email = serializers.EmailField()
  username = serializers.CharField(max_length=150)
  first_name = serializers.CharField(max_length=150)
  middle_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
  last_name = serializers.CharField(max_length=150)
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)
  email_verification_token = serializers.CharField(write_only=True)

  def validate_username(self, value: str) -> str:
    username = value.strip().lower()

    if User.objects.filter(username__iexact=username).exists():
      raise serializers.ValidationError('Username is already taken.')

    return username

  def validate_email(self, value: str) -> str:
    email = value.strip().lower()

    if User.objects.filter(email__iexact=email).exists():
      raise serializers.ValidationError('Email is already registered.')

    return email

  def validate(self, attrs):
    try:
      validate_password_strength(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    if not consume_verified_email_token(attrs['email'], attrs['email_verification_token']):
      raise serializers.ValidationError({'email_verification_token': 'Email must be verified before signup.'})

    return attrs

  def create(self, validated_data):
    profile_data = {
      'middle_name': validated_data.pop('middle_name', '').strip(),
    }
    validated_data.pop('confirm_password')
    validated_data.pop('email_verification_token')
    password = validated_data.pop('password')

    user = User.objects.create_user(
      username=validated_data['username'],
      email=validated_data['email'],
      password=password,
      first_name=validated_data['first_name'].strip(),
      last_name=validated_data['last_name'].strip(),
    )
    TrainerProfile.objects.create(user=user, **profile_data)
    return user


class TrainerLoginSerializer(serializers.Serializer):
  identifier = serializers.CharField()
  password = serializers.CharField(write_only=True)

  def validate(self, attrs):
    identifier = attrs['identifier'].strip().lower()
    password = attrs['password']
    username = identifier

    if '@' in identifier:
      user = User.objects.filter(email__iexact=identifier).first()
      username = user.username if user else identifier

    user = authenticate(username=username, password=password)

    if user is None:
      raise serializers.ValidationError('Invalid username/email or password.')

    if not hasattr(user, 'trainer_profile'):
      raise serializers.ValidationError('This account is not a trainer account.')

    attrs['user'] = user
    return attrs


class PasswordResetOtpRequestSerializer(serializers.Serializer):
  email = serializers.EmailField()

  def validate_email(self, value: str) -> str:
    return value.strip().lower()


class PasswordResetOtpVerifySerializer(serializers.Serializer):
  email = serializers.EmailField()
  otp = serializers.CharField(min_length=6, max_length=6)

  def validate_email(self, value: str) -> str:
    return value.strip().lower()


class PasswordResetConfirmSerializer(serializers.Serializer):
  email = serializers.EmailField()
  reset_token = serializers.CharField()
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)

  def validate_email(self, value: str) -> str:
    return value.strip().lower()

  def validate(self, attrs):
    try:
      validate_password_strength(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    if not consume_verified_email_token(attrs['email'], attrs['reset_token'], purpose='password-reset'):
      raise serializers.ValidationError({'reset_token': 'Password reset email must be verified.'})

    return attrs

  def save(self):
    user = User.objects.get(email__iexact=self.validated_data['email'])
    user.set_password(self.validated_data['password'])
    user.save(update_fields=['password'])
    return user


class TrainerPasswordChangeSerializer(serializers.Serializer):
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)

  def validate(self, attrs):
    try:
      validate_password_strength(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    return attrs

  def save(self, user):
    user.set_password(self.validated_data['password'])
    user.save(update_fields=['password'])
    return user


class TrainerAccountSerializer(serializers.ModelSerializer):
  middle_name = serializers.CharField(source='trainer_profile.middle_name')
  birth_month = serializers.IntegerField(source='trainer_profile.birth_month', allow_null=True)
  birth_year = serializers.IntegerField(source='trainer_profile.birth_year', allow_null=True)
  profile_setup_completed = serializers.BooleanField(source='trainer_profile.profile_setup_completed')

  class Meta:
    model = User
    fields = [
      'id',
      'email',
      'username',
      'first_name',
      'middle_name',
      'last_name',
      'birth_month',
      'birth_year',
      'profile_setup_completed',
    ]


class TrainerProfileStatusSerializer(serializers.ModelSerializer):
  class Meta:
    model = TrainerProfile
    fields = ['profile_setup_completed']


class TrainerProfileSerializer(serializers.ModelSerializer):
  first_name = serializers.CharField(source='user.first_name', max_length=150)
  last_name = serializers.CharField(source='user.last_name', max_length=150)
  email = serializers.EmailField(source='user.email', read_only=True)
  username = serializers.CharField(source='user.username', read_only=True)
  profile_photo_url = serializers.SerializerMethodField()
  certification_file_url = serializers.SerializerMethodField()
  transformation_photo_url = serializers.SerializerMethodField()
  training_photo_url = serializers.SerializerMethodField()

  class Meta:
    model = TrainerProfile
    fields = [
      'email',
      'username',
      'first_name',
      'last_name',
      'profile_setup_completed',
      'profile_photo',
      'profile_photo_url',
      'gender',
      'birth_month',
      'birth_year',
      'country',
      'state',
      'professional_headline',
      'about_me',
      'trainer_type',
      'years_experience',
      'specializations',
      'training_style',
      'languages_known',
      'certification_name',
      'certification_issued_by',
      'certification_year',
      'certification_file',
      'certification_file_url',
      'transformation_photo',
      'transformation_photo_url',
      'training_photo',
      'training_photo_url',
      'intro_video_url',
      'instagram_url',
      'youtube_url',
      'website_url',
    ]
    read_only_fields = [
      'profile_setup_completed',
      'profile_photo_url',
      'certification_file_url',
      'transformation_photo_url',
      'training_photo_url',
    ]

  def get_profile_photo_url(self, obj):
    return self.get_file_url(obj.profile_photo)

  def get_certification_file_url(self, obj):
    return self.get_file_url(obj.certification_file)

  def get_transformation_photo_url(self, obj):
    return self.get_file_url(obj.transformation_photo)

  def get_training_photo_url(self, obj):
    return self.get_file_url(obj.training_photo)

  def get_file_url(self, file_field):
    if not file_field:
      return ''

    request = self.context.get('request')
    return request.build_absolute_uri(file_field.url) if request else file_field.url

  def validate(self, attrs):
    required_fields = ['first_name', 'last_name', 'gender', 'birth_month', 'birth_year', 'country', 'state']
    user_attrs = attrs.get('user', {})

    for field in required_fields:
      value = user_attrs.get(field) if field in user_attrs else attrs.get(field)

      if value in (None, ''):
        raise serializers.ValidationError({field: 'This field is required for profile setup.'})

    return attrs

  def update(self, instance, validated_data):
    user_data = validated_data.pop('user', {})
    user = instance.user

    if 'first_name' in user_data:
      user.first_name = user_data['first_name'].strip()

    if 'last_name' in user_data:
      user.last_name = user_data['last_name'].strip()

    user.save(update_fields=['first_name', 'last_name'])

    for field, value in validated_data.items():
      if isinstance(value, str):
        value = value.strip()

      setattr(instance, field, value)

    instance.profile_setup_completed = True
    instance.save()
    return instance
