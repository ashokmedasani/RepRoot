import json
import re

from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from rest_framework import serializers

from .email_verification import consume_verified_email_token
from .models import (
  ChatMessage,
  ClientAccess,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  LeadSubmission,
  ProgressEntry,
  ReferenceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  TrainerGroup,
  TrainerLeadForm,
  TrainerProfile,
  TrainerReference,
  UNIVERSAL_CORE_FIELDS,
)

User = get_user_model()

FIELD_TYPES = {
  'short_text',
  'long_text',
  'email',
  'phone',
  'number',
  'dropdown',
  'checkbox',
  'radio',
  'yes_no',
  'date',
  'location',
  'address',
  'image',
}

TRAINER_ID_PATTERN = re.compile(r'^[a-z0-9._-]+$')


def normalize_dynamic_fields(fields):
  normalized_fields = []

  for index, field in enumerate(fields or []):
    label = str(field.get('label', '')).strip()
    field_type = str(field.get('field_type', '')).strip()

    if not label:
      raise serializers.ValidationError({'fields': f'Field {index + 1} label is required.'})

    if field_type not in FIELD_TYPES:
      raise serializers.ValidationError({'fields': f'Field {index + 1} type is not supported.'})

    options = field.get('options', [])

    if isinstance(options, str):
      options = [option.strip() for option in options.split(',') if option.strip()]

    if not isinstance(options, list):
      options = []

    normalized_fields.append(
      {
        'key': field.get('key') or f'custom_{index + 1}',
        'label': label,
        'field_type': field_type,
        'required': bool(field.get('required', False)),
        'placeholder': str(field.get('placeholder', '')).strip(),
        'help_text': str(field.get('help_text', '')).strip(),
        'options': [str(option).strip() for option in options if str(option).strip()],
        'is_core': False,
      }
    )

  return [field.copy() for field in UNIVERSAL_CORE_FIELDS] + normalized_fields


def get_public_form_link(request, public_slug):
  origin = request.headers.get('Origin') if request else ''
  base_url = origin or request.build_absolute_uri('/').rstrip('/') if request else ''
  return f'{base_url}/public/forms/{public_slug}' if base_url else f'/public/forms/{public_slug}'


def validate_required_answers(fields, answers):
  missing_fields = []

  for field in fields:
    key = field.get('key')
    value = answers.get(key)

    if field.get('required') and (value is None or str(value).strip() == ''):
      missing_fields.append(field.get('label', key))

  if missing_fields:
    raise serializers.ValidationError({'answers': f'Required fields missing: {", ".join(missing_fields)}.'})


def validate_password_strength(password: str) -> None:
  if len(password) < 8 or password.isalnum():
    raise serializers.ValidationError('Password must be at least 8 characters and include 1 special character.')


class UsernameAvailabilitySerializer(serializers.Serializer):
  username = serializers.CharField(max_length=10)

  def validate_username(self, value: str) -> str:
    username = value.strip().lower()

    if not username:
      raise serializers.ValidationError('Username is required.')

    if len(username) < 5:
      raise serializers.ValidationError('Username must be at least 5 characters.')

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
  username = serializers.CharField(min_length=5, max_length=10)
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
    validated_data.pop('confirm_password')
    validated_data.pop('email_verification_token')
    password = validated_data.pop('password')

    with transaction.atomic():
      user = User.objects.create_user(
        username=validated_data['username'],
        email=validated_data['email'],
        password=password,
        first_name='',
        last_name='',
      )
      TrainerProfile.objects.create(user=user)

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
  trainer_id = serializers.CharField(max_length=32)
  first_name = serializers.CharField(source='user.first_name', max_length=150)
  middle_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
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
      'trainer_id',
      'first_name',
      'middle_name',
      'last_name',
      'profile_setup_completed',
      'profile_photo',
      'profile_photo_url',
      'phone',
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
      'profile_images',
      'profile_links',
      'profile_visibility',
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
    required_fields = ['trainer_id', 'first_name', 'last_name', 'gender', 'birth_month', 'birth_year', 'country', 'state']
    user_attrs = attrs.get('user', {})

    for field in required_fields:
      value = user_attrs.get(field) if field in user_attrs else attrs.get(field)

      if value in (None, ''):
        raise serializers.ValidationError({field: 'This field is required for profile setup.'})

    return attrs

  def validate_trainer_id(self, value: str) -> str:
    trainer_id = value.strip().lower()

    if not trainer_id:
      raise serializers.ValidationError('Trainer ID is required.')

    if len(trainer_id) < 4:
      raise serializers.ValidationError('Trainer ID must be at least 4 characters.')

    if not TRAINER_ID_PATTERN.match(trainer_id):
      raise serializers.ValidationError('Use only letters, numbers, periods, underscores, or hyphens.')

    query = TrainerProfile.objects.filter(trainer_id__iexact=trainer_id)

    if self.instance:
      query = query.exclude(pk=self.instance.pk)

    if query.exists():
      raise serializers.ValidationError('Trainer ID is already taken.')

    return trainer_id

  def validate_profile_images(self, value):
    return self.normalize_profile_collection(value, {'category', 'title', 'url'})

  def validate_profile_links(self, value):
    return self.normalize_profile_collection(value, {'title', 'url'})

  def validate_profile_visibility(self, value):
    if isinstance(value, str):
      try:
        value = json.loads(value or '{}')
      except json.JSONDecodeError:
        raise serializers.ValidationError('Invalid JSON format.')

    if not isinstance(value, dict):
      raise serializers.ValidationError('Expected an object.')

    allowed_keys = {
      'about',
      'professional_summary',
      'training_style',
      'certification',
      'images',
      'links',
    }

    return {key: bool(value.get(key, False)) for key in allowed_keys}

  def normalize_profile_collection(self, value, allowed_keys):
    if isinstance(value, str):
      try:
        value = json.loads(value or '[]')
      except json.JSONDecodeError:
        raise serializers.ValidationError('Invalid JSON format.')

    if not isinstance(value, list):
      raise serializers.ValidationError('Expected a list.')

    cleaned_items = []

    for item in value:
      if not isinstance(item, dict):
        continue

      cleaned = {key: str(item.get(key, '')).strip() for key in allowed_keys}

      if cleaned.get('title') and cleaned.get('url'):
        cleaned_items.append(cleaned)

    return cleaned_items

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


class TrainerLeadFormSerializer(serializers.ModelSerializer):
  public_link = serializers.SerializerMethodField()
  custom_fields = serializers.ListField(child=serializers.DictField(), write_only=True, required=False)

  class Meta:
    model = TrainerLeadForm
    fields = ['id', 'title', 'public_slug', 'public_link', 'fields', 'custom_fields', 'is_active', 'created_at', 'updated_at']
    read_only_fields = ['public_slug', 'public_link', 'fields', 'is_active', 'created_at', 'updated_at']

  def get_public_link(self, obj):
    return get_public_form_link(self.context.get('request'), obj.public_slug)

  def validate(self, attrs):
    attrs['fields'] = normalize_dynamic_fields(attrs.pop('custom_fields', []))
    attrs['title'] = attrs.get('title', 'Trainer Lead Form').strip() or 'Trainer Lead Form'
    return attrs


class PublicLeadFormSerializer(serializers.ModelSerializer):
  trainer_name = serializers.SerializerMethodField()

  class Meta:
    model = TrainerLeadForm
    fields = ['id', 'title', 'public_slug', 'trainer_name', 'fields']

  def get_trainer_name(self, obj):
    return obj.trainer.get_full_name() or obj.trainer.username


class TrainerGroupSerializer(serializers.ModelSerializer):
  has_registration_form = serializers.SerializerMethodField()
  registration_form = serializers.SerializerMethodField()

  class Meta:
    model = TrainerGroup
    fields = ['id', 'name', 'description', 'is_active', 'has_registration_form', 'registration_form', 'created_at', 'updated_at']
    read_only_fields = ['id', 'is_active', 'has_registration_form', 'registration_form', 'created_at', 'updated_at']

  def get_has_registration_form(self, obj):
    form = getattr(obj, 'client_registration_form', None)
    return bool(form and form.is_active)

  def get_registration_form(self, obj):
    form = getattr(obj, 'client_registration_form', None)
    return ClientRegistrationFormSerializer(form).data if form and form.is_active else None

  def validate_name(self, value):
    name = value.strip()

    if not name:
      raise serializers.ValidationError('Group Name is required.')

    return name


class ClientRegistrationFormSerializer(serializers.ModelSerializer):
  custom_fields = serializers.ListField(child=serializers.DictField(), write_only=True, required=False)

  class Meta:
    model = ClientRegistrationForm
    fields = ['id', 'group', 'fields', 'custom_fields', 'is_active', 'created_at', 'updated_at']
    read_only_fields = ['id', 'group', 'fields', 'is_active', 'created_at', 'updated_at']

  def validate(self, attrs):
    attrs['fields'] = normalize_dynamic_fields(attrs.pop('custom_fields', []))
    return attrs


class LeadSubmissionSerializer(serializers.ModelSerializer):
  applicant_name = serializers.SerializerMethodField()
  client_access = serializers.SerializerMethodField()

  class Meta:
    model = LeadSubmission
    fields = [
      'id',
      'applicant_name',
      'first_name',
      'last_name',
      'email',
      'reference_id',
      'answers',
      'status',
      'is_active',
      'submitted_at',
      'updated_at',
      'converted_at',
      'deleted_at',
      'client_access',
    ]
    read_only_fields = fields

  def get_applicant_name(self, obj):
    return f'{obj.first_name} {obj.last_name}'.strip()

  def get_client_access(self, obj):
    try:
      client_access = obj.client_access
    except ClientAccess.DoesNotExist:
      client_access = None

    if client_access and client_access.is_active:
      return {
        'id': client_access.id,
        'group': client_access.group_id,
        'group_name': client_access.group.name,
        'username': client_access.username,
      }

    return None


class PublicLeadSubmissionSerializer(serializers.Serializer):
  answers = serializers.DictField()

  def validate(self, attrs):
    lead_form = self.context['lead_form']
    answers = attrs['answers']
    validate_required_answers(lead_form.fields, answers)
    attrs['first_name'] = str(answers.get('first_name', '')).strip()
    attrs['last_name'] = str(answers.get('last_name', '')).strip()
    attrs['email'] = str(answers.get('email', '')).strip().lower()

    if not attrs['email']:
      raise serializers.ValidationError({'email': 'Email Address is required.'})

    return attrs


class ClientAccessCreateSerializer(serializers.Serializer):
  group_id = serializers.IntegerField()
  username = serializers.CharField(max_length=150)
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)
  photo = serializers.CharField(required=False, allow_blank=True, default='')
  registration_answers = serializers.DictField(required=False)

  def validate_username(self, value):
    username = value.strip().lower()

    if not username:
      raise serializers.ValidationError('Client username is required.')

    if ClientAccess.objects.filter(username__iexact=username, is_active=True).exists():
      raise serializers.ValidationError('Client username is already taken.')

    return username

  def validate(self, attrs):
    try:
      validate_password_strength(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    return attrs


class ClientLoginSerializer(serializers.Serializer):
  trainer_id = serializers.CharField(max_length=32)
  username = serializers.CharField(max_length=150)
  password = serializers.CharField(write_only=True)

  def validate(self, attrs):
    trainer_id = attrs['trainer_id'].strip().lower()
    username = attrs['username'].strip().lower()
    password = attrs['password']

    if not trainer_id:
      raise serializers.ValidationError({'trainer_id': 'Trainer ID is required.'})

    access_records = ClientAccess.objects.filter(
      trainer__trainer_profile__trainer_id__iexact=trainer_id,
      username__iexact=username,
      is_active=True,
      lead_submission__status=LeadSubmission.STATUS_APPROVED,
    ).select_related('trainer', 'group', 'lead_submission')

    client_access = None

    for access_record in access_records:
      stored_password = access_record.temporary_password

      if stored_password.startswith('pbkdf2_') and check_password(password, stored_password):
        client_access = access_record
        break

      if stored_password == password:
        access_record.temporary_password = make_password(password)
        access_record.must_change_password = False
        access_record.save(update_fields=['temporary_password', 'must_change_password', 'updated_at'])
        client_access = access_record
        break

    if client_access is None:
      raise serializers.ValidationError('Invalid trainer ID, client username, or password.')

    attrs['client_access'] = client_access
    return attrs


class ClientTrainerLookupSerializer(serializers.Serializer):
  trainer_id = serializers.CharField(max_length=32)

  def validate_trainer_id(self, value: str) -> str:
    trainer_id = value.strip().lower()

    if not trainer_id:
      raise serializers.ValidationError('Trainer ID is required.')

    return trainer_id


TEMPLATE_FIELD_TYPES = {
  'number',
  'short_text',
  'long_text',
  'yes_no',
  'dropdown',
  'rating',
}

MAX_TEMPLATE_FIELDS = 8

YOUTUBE_HOSTS = ('youtube.com', 'www.youtube.com', 'm.youtube.com', 'youtu.be')


def is_youtube_link(link: str) -> bool:
  from urllib.parse import urlparse

  try:
    host = (urlparse(link).netloc or '').lower()
  except ValueError:
    return False

  return host in YOUTUBE_HOSTS


def normalize_template_fields(fields):
  fields = fields or []

  if len(fields) > MAX_TEMPLATE_FIELDS:
    raise serializers.ValidationError({'fields': f'A template can have at most {MAX_TEMPLATE_FIELDS} fields.'})

  normalized_fields = []

  for index, field in enumerate(fields):
    label = str(field.get('label', '')).strip()
    field_type = str(field.get('field_type', '')).strip()

    if not label:
      raise serializers.ValidationError({'fields': f'Field {index + 1} label is required.'})

    if field_type not in TEMPLATE_FIELD_TYPES:
      raise serializers.ValidationError({'fields': f'Field {index + 1} type is not supported.'})

    options = field.get('options', [])

    if isinstance(options, str):
      options = [option.strip() for option in options.split(',') if option.strip()]

    if not isinstance(options, list):
      options = []

    options = [str(option).strip() for option in options if str(option).strip()]

    if field_type == 'dropdown' and not options:
      raise serializers.ValidationError({'fields': f'Field {index + 1} (dropdown) needs at least one option.'})

    try:
      scale = int(field.get('scale') or 5)
    except (TypeError, ValueError):
      scale = 5

    scale = min(10, max(2, scale))

    normalized_fields.append(
      {
        'key': str(field.get('key') or f'field_{index + 1}').strip(),
        'label': label,
        'field_type': field_type,
        'placeholder': str(field.get('placeholder', '')).strip(),
        'options': options,
        'scale': scale if field_type == 'rating' else None,
      }
    )

  return normalized_fields


class ReferenceCategorySerializer(serializers.ModelSerializer):
  reference_count = serializers.SerializerMethodField()

  class Meta:
    model = ReferenceCategory
    fields = ['id', 'name', 'description', 'subcategories', 'reference_count', 'created_at', 'updated_at']
    read_only_fields = ['id', 'reference_count', 'created_at', 'updated_at']

  def get_reference_count(self, obj):
    return obj.references.count()

  def validate_name(self, value):
    name = value.strip()

    if not name:
      raise serializers.ValidationError('Category name is required.')

    return name

  def validate_subcategories(self, value):
    if not isinstance(value, list):
      raise serializers.ValidationError('Subcategories must be a list.')

    return [str(subcategory).strip() for subcategory in value if str(subcategory).strip()]


class TrainerReferenceSerializer(serializers.ModelSerializer):
  category_name = serializers.CharField(source='category.name', read_only=True)
  file_url = serializers.SerializerMethodField()
  file_name = serializers.SerializerMethodField()

  class Meta:
    model = TrainerReference
    fields = [
      'id',
      'category',
      'category_name',
      'subcategory',
      'title',
      'reference_type',
      'description',
      'link',
      'file',
      'file_url',
      'file_name',
      'tags',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'category_name', 'file_url', 'file_name', 'created_at', 'updated_at']
    extra_kwargs = {'file': {'write_only': True, 'required': False}}

  def get_file_url(self, obj):
    if not obj.file:
      return ''

    request = self.context.get('request')
    return request.build_absolute_uri(obj.file.url) if request else obj.file.url

  def get_file_name(self, obj):
    return obj.file.name.rsplit('/', 1)[-1] if obj.file else ''

  def validate_title(self, value):
    title = value.strip()

    if not title:
      raise serializers.ValidationError('Title is required.')

    return title

  def to_internal_value(self, data):
    # Multipart forms send tags as a comma-separated string.
    if hasattr(data, 'getlist') or isinstance(data.get('tags'), str):
      data = data.copy()
      raw_tags = data.get('tags', '')

      if isinstance(raw_tags, str):
        data.setlist('tags', []) if hasattr(data, 'setlist') else None
        parsed_tags = [tag.strip() for tag in raw_tags.split(',') if tag.strip()]
        internal_value = super().to_internal_value(data)
        internal_value['tags'] = parsed_tags
        return internal_value

    return super().to_internal_value(data)

  def validate(self, attrs):
    reference_type = attrs.get('reference_type') or (self.instance.reference_type if self.instance else '')
    link = (attrs.get('link') if 'link' in attrs else (self.instance.link if self.instance else '')) or ''
    file = attrs.get('file') if 'file' in attrs else (self.instance.file if self.instance else None)

    if reference_type == TrainerReference.TYPE_VIDEO_LINK:
      if not link:
        raise serializers.ValidationError({'link': 'Video URL is required.'})

      if not is_youtube_link(link):
        raise serializers.ValidationError({'link': 'Videos must be YouTube links so they can be streamed in-app.'})

      attrs['file'] = None

    upload = attrs.get('file')

    if reference_type == TrainerReference.TYPE_PDF:
      if not link:
        raise serializers.ValidationError({'link': 'PDF URL is required.'})

      attrs['file'] = None

    if reference_type == TrainerReference.TYPE_TEXT_NOTE:
      if not attrs.get('description', '').strip():
        raise serializers.ValidationError({'description': 'Text is required.'})

      attrs['link'] = ''
      attrs['file'] = None

    if reference_type == TrainerReference.TYPE_IMAGE:
      if not file:
        raise serializers.ValidationError({'file': 'Image upload is required.'})

      content_type = getattr(upload or file, 'content_type', '')
      if upload and not content_type.startswith('image/'):
        raise serializers.ValidationError({'file': 'Only image uploads are allowed.'})

    return attrs


class TrackingTemplateReferenceSerializer(serializers.ModelSerializer):
  """Read-only, compact reference representation shared with a client via an assignment."""

  category_name = serializers.CharField(source='category.name', read_only=True)
  file_url = serializers.SerializerMethodField()

  class Meta:
    model = TrainerReference
    fields = ['id', 'title', 'reference_type', 'category_name', 'subcategory', 'description', 'link', 'file_url', 'tags']
    read_only_fields = fields

  def get_file_url(self, obj):
    if not obj.file:
      return ''

    request = self.context.get('request')
    return request.build_absolute_uri(obj.file.url) if request else obj.file.url


class TrackingTemplateSerializer(serializers.ModelSerializer):
  custom_fields = serializers.ListField(child=serializers.DictField(), write_only=True, required=False)
  assigned_count = serializers.SerializerMethodField()

  class Meta:
    model = TrackingTemplate
    fields = [
      'id',
      'name',
      'purpose',
      'cadence',
      'accent',
      'fields',
      'custom_fields',
      'standard_key',
      'assigned_count',
      'is_active',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'fields', 'standard_key', 'assigned_count', 'is_active', 'created_at', 'updated_at']

  def get_assigned_count(self, obj):
    return obj.assignments.count()

  def validate_name(self, value):
    name = value.strip()

    if not name:
      raise serializers.ValidationError('Template name is required.')

    return name

  def validate(self, attrs):
    if 'custom_fields' in attrs:
      attrs['fields'] = normalize_template_fields(attrs.pop('custom_fields'))

    return attrs


class ClientTrackingEntrySubmitSerializer(serializers.Serializer):
  template_id = serializers.IntegerField()
  entry_date = serializers.DateField()
  entry_time = serializers.TimeField(required=False, allow_null=True)
  answers = serializers.DictField(required=False, default=dict)
  note = serializers.CharField(required=False, allow_blank=True, default='')


class TemplateAssignmentSerializer(serializers.ModelSerializer):
  template_id = serializers.IntegerField(source='template.id', read_only=True)
  template_name = serializers.CharField(source='template.name', read_only=True)
  template_cadence = serializers.CharField(source='template.cadence', read_only=True)
  template_accent = serializers.CharField(source='template.accent', read_only=True)
  references = TrackingTemplateReferenceSerializer(many=True, read_only=True)

  class Meta:
    model = TemplateAssignment
    fields = ['id', 'template_id', 'template_name', 'template_cadence', 'template_accent', 'references', 'assigned_at']
    read_only_fields = fields


class TrackingEntrySerializer(serializers.ModelSerializer):
  class Meta:
    model = TrackingEntry
    fields = [
      'id',
      'client',
      'template',
      'template_name',
      'entry_date',
      'entry_time',
      'answers',
      'note',
      'edited_by_trainer',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'client', 'template', 'template_name', 'edited_by_trainer', 'created_at', 'updated_at']


class ChatMessageSerializer(serializers.ModelSerializer):
  class Meta:
    model = ChatMessage
    fields = ['id', 'sender', 'text', 'created_at']
    read_only_fields = ['id', 'sender', 'created_at']

  def validate_text(self, value):
    text = value.strip()

    if not text:
      raise serializers.ValidationError('Message text is required.')

    return text


class ClientPasswordChangeSerializer(serializers.Serializer):
  current_password = serializers.CharField(write_only=True)
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)

  def validate(self, attrs):
    try:
      validate_password_strength(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    client_access = self.context['client_access']

    if not check_password(attrs['current_password'], client_access.temporary_password):
      raise serializers.ValidationError({'current_password': 'Current password is incorrect.'})

    return attrs

  def save(self):
    client_access = self.context['client_access']
    client_access.temporary_password = make_password(self.validated_data['password'])
    client_access.must_change_password = False
    client_access.save(update_fields=['temporary_password', 'must_change_password', 'updated_at'])
    return client_access


class ClientAccessSerializer(serializers.ModelSerializer):
  group_name = serializers.CharField(source='group.name', read_only=True)
  trainer_name = serializers.SerializerMethodField()

  class Meta:
    model = ClientAccess
    fields = [
      'id',
      'group',
      'group_name',
      'trainer_name',
      'lead_submission',
      'first_name',
      'last_name',
      'email',
      'username',
      'photo',
      'registration_answers',
      'additional_info',
      'additional_info_shared',
      'must_change_password',
      'is_active',
      'created_at',
      'updated_at',
    ]
    read_only_fields = fields

  def get_trainer_name(self, obj):
    return obj.trainer.get_full_name() or obj.trainer.username


class ClientDetailChangeRequestSerializer(serializers.ModelSerializer):
  class Meta:
    model = ClientDetailChangeRequest
    fields = [
      'id',
      'client',
      'proposed_answers',
      'status',
      'client_note',
      'trainer_note',
      'created_at',
      'reviewed_at',
    ]
    read_only_fields = fields


class ClientReminderSerializer(serializers.ModelSerializer):
  client_name = serializers.SerializerMethodField()

  class Meta:
    model = ClientReminder
    fields = [
      'id',
      'client',
      'client_name',
      'title',
      'date',
      'time',
      'notes',
      'status',
      'notify_trainer',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'client', 'client_name', 'created_at', 'updated_at']

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username


class ProgressEntrySerializer(serializers.ModelSerializer):
  class Meta:
    model = ProgressEntry
    fields = [
      'id',
      'client',
      'title',
      'date',
      'notes',
      'status',
      'next_step',
      'created_by',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'client', 'created_by', 'created_at', 'updated_at']
