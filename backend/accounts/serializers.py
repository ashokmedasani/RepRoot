import hashlib
import json
import re
import secrets
from datetime import timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

from django.conf import settings
from django.contrib.auth import authenticate, get_user_model
from django.contrib.auth.hashers import check_password, make_password
from django.db import transaction
from django.utils import timezone
from rest_framework import serializers

from .email_verification import consume_verified_email_token
from .models import (
  ChatMessage,
  ClientAccess,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  ProfessionalAvailabilityWindow,
  ProfessionalDateOff,
  ProfessionalWeekdayOff,
  ProfessionalSchedulingSettings,
  ScheduledMeeting,
  ScheduledMeetingGuest,
  GroupRegistrationSubmission,
  LeadSubmission,
  LeadMeetingRequest,
  LegalAcceptanceRecord,
  ProgressEntry,
  ResourceCategory,
  SupportIncident,
  SupportIncidentMessage,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ManualPaymentProfile,
  PaymentProof,
  PaymentRecord,
  PaymentRequest,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalPaymentSettings,
  ProfessionalProfile,
  ProfessionalResource,
  RecycleBinItem,
  UNIVERSAL_CORE_FIELDS,
)
from .payment_constants import (
  CATEGORY_REQUIRED_CLIENT_FIELDS,
  ISO_4217_CODES,
  PAYMENT_PROOF_CONTENT_TYPES,
  PAYMENT_PROOF_MAX_BYTES,
  PAYMENT_QR_CONTENT_TYPES,
  PAYMENT_QR_MAX_BYTES,
)

User = get_user_model()


def detect_upload_content_type(value):
  """Sniff the real content type of an uploaded file from its leading bytes.

  Uploaded ``content_type`` is fully attacker-controlled (it's just a
  multipart header), so it must never be trusted on its own to decide what a
  file "is" before it's stored and later served back to another user. This
  checks the actual file signature against the small set of formats we
  accept for payment proofs / QR codes, and returns ``None`` if it doesn't
  match a known-good signature (including for formats we deliberately don't
  support, like SVG/HTML, which could otherwise be used to smuggle a script
  that executes when the file is later served inline to another party).
  """
  try:
    position = value.tell()
  except (AttributeError, OSError):
    position = None

  head = value.read(16)

  if position is not None:
    value.seek(position)
  else:
    value.seek(0)

  if head.startswith(b'\x89PNG\r\n\x1a\n'):
    return 'image/png'
  if head.startswith(b'\xff\xd8\xff'):
    return 'image/jpeg'
  if head[:4] == b'RIFF' and head[8:12] == b'WEBP':
    return 'image/webp'
  if head.startswith(b'GIF87a') or head.startswith(b'GIF89a'):
    return 'image/gif'
  if head.startswith(b'%PDF-'):
    return 'application/pdf'
  return None


PROFILE_VISIBILITY_KEYS = {
  'professional_headline',
  'about',
  'professional_summary',
  'specializations',
  'experience',
  'languages',
  'training_style',
  'certification',
  'images',
  'links',
}

LEGACY_PROFILE_VISIBILITY_KEYS = {
  'certifications': 'certification',
  'gallery': 'images',
  'social_links': 'links',
}


def normalize_profile_visibility(value):
  """Return the complete, current section-visibility contract."""
  source = value if isinstance(value, dict) else {}
  normalized = {key: bool(source.get(key, False)) for key in PROFILE_VISIBILITY_KEYS}

  for legacy_key, current_key in LEGACY_PROFILE_VISIBILITY_KEYS.items():
    if current_key not in source and legacy_key in source:
      normalized[current_key] = bool(source[legacy_key])

  return normalized


def normalize_additional_info(items):
  """Convert legacy label/value items to the current, stable UI contract."""
  if not isinstance(items, list):
    return []

  normalized = []
  used_ids = set()

  for index, item in enumerate(items[:100]):
    if not isinstance(item, dict):
      continue

    title = str(item.get('title') or item.get('label') or '').strip()[:200]
    if not title:
      continue

    item_type = str(item.get('type') or '').strip().lower()
    if item_type not in {'text', 'link', 'reference'}:
      item_type = 'link' if item.get('link') or item.get('url') else 'text'

    item_id = str(item.get('id') or '').strip()[:120]
    if not item_id:
      fingerprint = hashlib.sha256(
        json.dumps(item, sort_keys=True, default=str).encode('utf-8')
      ).hexdigest()[:12]
      item_id = f'legacy-{index}-{fingerprint}'

    base_id = item_id
    duplicate_index = 2
    while item_id in used_ids:
      item_id = f'{base_id}-{duplicate_index}'[:120]
      duplicate_index += 1
    used_ids.add(item_id)

    visibility = str(item.get('visibility') or '').strip().lower()
    if visibility not in {'private', 'client'}:
      visibility = 'client' if 'label' in item else 'private'

    cleaned = {
      'id': item_id,
      'title': title,
      'type': item_type,
      'visibility': visibility,
    }

    if item_type == 'text':
      cleaned['text'] = str(item.get('text') or item.get('value') or '').strip()[:10000]
    else:
      cleaned['link'] = str(item.get('link') or item.get('url') or '').strip()[:2000]

    if item_type == 'reference':
      reference_id = item.get('reference_id')
      try:
        cleaned['reference_id'] = int(reference_id) if reference_id not in (None, '') else None
      except (TypeError, ValueError):
        cleaned['reference_id'] = None
      cleaned['reference_title'] = str(item.get('reference_title') or '').strip()[:200]

    normalized.append(cleaned)

  return normalized


def validate_client_photo(value):
  import base64
  from io import BytesIO

  photo = str(value or '')
  if not photo:
    return ''

  if len(photo) > 7_000_000:
    raise serializers.ValidationError('The profile photo must be smaller than 5 MB.')

  match = re.match(r'^data:image/(jpeg|jpg|png|webp|gif);base64,(?P<data>.+)$', photo, re.IGNORECASE | re.DOTALL)
  if not match:
    raise serializers.ValidationError('Upload a JPEG, PNG, WebP, or GIF image.')

  try:
    decoded = base64.b64decode(match.group('data'), validate=True)
  except (ValueError, TypeError):
    raise serializers.ValidationError('That image file appears to be corrupted - try a different file.')

  # The data-URI prefix above is just attacker-controlled text; confirm the
  # base64 payload actually decodes to real image bytes rather than trusting
  # the declared type on its own (same class of check as file uploads).
  if detect_upload_content_type(BytesIO(decoded)) is None:
    raise serializers.ValidationError('That file does not look like a valid image - try a different file.')

  return photo

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

PROFESSIONAL_ID_PATTERN = re.compile(r'^[a-z0-9._-]+$')


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


def validate_strong_password(password: str) -> None:
  """Stricter password policy for professional accounts.

  Applied only on account creation, password reset, and voluntary password
  change so existing password hashes are never invalidated retroactively.
  """
  errors = []

  if len(password) < 8:
    errors.append('at least 8 characters')
  if not re.search(r'[A-Z]', password):
    errors.append('one uppercase letter')
  if not re.search(r'[a-z]', password):
    errors.append('one lowercase letter')
  if not re.search(r'[0-9]', password):
    errors.append('one number')
  if not re.search(r'[^A-Za-z0-9]', password):
    errors.append('one special character')

  if errors:
    raise serializers.ValidationError(
      'Password must contain ' + ', '.join(errors) + '.'
    )


USERNAME_ALLOWED_PATTERN = re.compile(r'^[A-Za-z0-9.\-]+$')
USERNAME_CHARSET_MESSAGE = "Only letters, numbers, '.' and '-' are allowed."


def validate_username_charset(username: str) -> None:
  """Usernames may only contain letters, digits, dot, and hyphen (no spaces)."""
  if not USERNAME_ALLOWED_PATTERN.match(username):
    raise serializers.ValidationError(USERNAME_CHARSET_MESSAGE)


class UsernameAvailabilitySerializer(serializers.Serializer):
  username = serializers.CharField(max_length=30)

  def validate_username(self, value: str) -> str:
    username = value.strip().lower()

    if not username:
      raise serializers.ValidationError('Username is required.')

    if len(username) < 5:
      raise serializers.ValidationError('Username must be at least 5 characters.')

    validate_username_charset(username)

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


class ProfessionalSignupSerializer(serializers.Serializer):
  email = serializers.EmailField()
  username = serializers.CharField(min_length=5, max_length=30)
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)
  email_verification_token = serializers.CharField(write_only=True)
  accept_terms = serializers.BooleanField(write_only=True)
  accept_privacy = serializers.BooleanField(write_only=True)

  def validate_username(self, value: str) -> str:
    username = value.strip().lower()

    validate_username_charset(username)

    if User.objects.filter(username__iexact=username).exists():
      raise serializers.ValidationError('Username is already taken.')

    return username

  def validate_email(self, value: str) -> str:
    email = value.strip().lower()

    if User.objects.filter(email__iexact=email).exists():
      raise serializers.ValidationError('An account already exists for this email. Please sign in.')

    return email

  def validate(self, attrs):
    if not attrs.get('accept_terms'):
      raise serializers.ValidationError({'accept_terms': 'You must accept the Terms & Conditions.'})
    if not attrs.get('accept_privacy'):
      raise serializers.ValidationError({'accept_privacy': 'You must acknowledge the Privacy Policy.'})
    try:
      validate_strong_password(attrs['password'])
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
    validated_data.pop('accept_terms')
    validated_data.pop('accept_privacy')
    password = validated_data.pop('password')

    with transaction.atomic():
      user = User.objects.create_user(
        username=validated_data['username'],
        email=validated_data['email'],
        password=password,
        first_name='',
        last_name='',
      )
      accepted_at = timezone.now()
      ProfessionalProfile.objects.create(
        user=user,
        terms_accepted=True,
        privacy_policy_accepted=True,
        terms_accepted_at=accepted_at,
        privacy_policy_accepted_at=accepted_at,
        legal_document_version=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
      )
      profile = user.professional_profile
      LegalAcceptanceRecord.objects.create(
        actor_type=LegalAcceptanceRecord.ACTOR_PROFESSIONAL,
        professional_profile=profile,
        actor_reference=profile.professional_id or str(user.id),
        legal_document_version=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
        accepted_at=accepted_at,
      )

    return user


def _reject_login_if_locked(user):
  """Block sign-in for a professional whose account is frozen/recycled.

  Previously nothing checked this at login: freezing only deleted the auth
  token and left `User.is_active` untouched, so a frozen professional could
  simply log back in and get a brand-new token, fully bypassing the freeze.
  This is the fix -- login now genuinely enforces the lock, matching what a
  "frozen account" is supposed to mean. There is deliberately no self-service
  way back in from here: restoring access for a genuinely frozen professional
  (e.g. so they can reach billing to upgrade) is an admin-side action, tracked
  separately in ADMIN_CONTROLS_NEEDED.md, not built as part of this change.
  """
  profile = getattr(user, 'professional_profile', None)
  if profile is None:
    return
  if profile.is_locked or profile.lifecycle_status == profile.LIFECYCLE_RECYCLED:
    raise serializers.ValidationError(
      'This account is frozen due to a billing overage. Contact support to restore access.'
    )


class ProfessionalLoginSerializer(serializers.Serializer):
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

    if not hasattr(user, 'professional_profile'):
      raise serializers.ValidationError('This account is not a professional account.')

    _reject_login_if_locked(user)

    attrs['user'] = user
    return attrs


class ProfessionalGoogleAuthSerializer(serializers.Serializer):
  """Verifies a Google Identity Services credential and resolves it to a user.

  Used for both "Continue with Google" signup and "Log in with Google" -- the
  frontend uses the same button/callback for both, matching Google's own
  recommended flow, and the backend decides create-vs-link-vs-login.
  """

  credential = serializers.CharField(write_only=True)
  accept_terms = serializers.BooleanField(write_only=True, required=False, default=False)
  accept_privacy = serializers.BooleanField(write_only=True, required=False, default=False)

  def validate(self, attrs):
    from . import google_oauth

    try:
      claims = google_oauth.verify_google_id_token(attrs['credential'])
      user, created = google_oauth.get_or_create_professional_for_google(
        claims,
        allow_create=bool(attrs.get('accept_terms') and attrs.get('accept_privacy')),
      )
    except google_oauth.GoogleAuthError as error:
      raise serializers.ValidationError({'credential': str(error)})

    if not created:
      _reject_login_if_locked(user)

    attrs['user'] = user
    attrs['created'] = created
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
      validate_strong_password(attrs['password'])
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


class ProfessionalPasswordChangeSerializer(serializers.Serializer):
  # Deliberately no current_password field: the request is already
  # authenticated (ProfessionalAccessPermission requires a valid token), so
  # re-confirming the current password here was judged unnecessary friction
  # for this flow.
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)

  def validate(self, attrs):
    try:
      validate_strong_password(attrs['password'])
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if attrs['password'] != attrs['confirm_password']:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    return attrs

  def save(self, user):
    user.set_password(self.validated_data['password'])
    user.save(update_fields=['password'])
    return user


class ProfessionalAccountSerializer(serializers.ModelSerializer):
  middle_name = serializers.CharField(source='professional_profile.middle_name')
  birth_month = serializers.IntegerField(source='professional_profile.birth_month', allow_null=True)
  birth_year = serializers.IntegerField(source='professional_profile.birth_year', allow_null=True)
  profile_setup_completed = serializers.BooleanField(source='professional_profile.profile_setup_completed')

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


class ProfessionalProfileStatusSerializer(serializers.ModelSerializer):
  legal_acceptance_required = serializers.SerializerMethodField()
  current_legal_document_version = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalProfile
    fields = ['profile_setup_completed', 'legal_acceptance_required', 'current_legal_document_version']

  def get_legal_acceptance_required(self, obj):
    return not (
      obj.terms_accepted
      and obj.privacy_policy_accepted
      and obj.legal_document_version == settings.REPROOT_PROFESSIONAL_LEGAL_VERSION
    )

  def get_current_legal_document_version(self, _obj):
    return settings.REPROOT_PROFESSIONAL_LEGAL_VERSION


class ProfessionalProfileSerializer(serializers.ModelSerializer):
  professional_id = serializers.CharField(max_length=32)
  first_name = serializers.CharField(source='user.first_name', max_length=150)
  middle_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
  last_name = serializers.CharField(source='user.last_name', max_length=150)
  email = serializers.EmailField(source='user.email', read_only=True)
  username = serializers.CharField(source='user.username', read_only=True)
  profile_photo_url = serializers.SerializerMethodField()
  certification_file_url = serializers.SerializerMethodField()
  transformation_photo_url = serializers.SerializerMethodField()
  training_photo_url = serializers.SerializerMethodField()
  legal_acceptance_history = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalProfile
    fields = [
      'email',
      'username',
      'professional_id',
      'first_name',
      'middle_name',
      'last_name',
      'profile_setup_completed',
      'terms_accepted',
      'privacy_policy_accepted',
      'terms_accepted_at',
      'privacy_policy_accepted_at',
      'legal_document_version',
      'legal_acceptance_history',
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
      'professional_type',
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

  def get_legal_acceptance_history(self, obj):
    return [
      {
        'legal_document_version': row.legal_document_version,
        'accepted_at': row.accepted_at,
        'client_timezone': row.client_timezone,
      }
      for row in obj.legal_acceptance_records.all()[:20]
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
    required_fields = ['professional_id', 'first_name', 'last_name', 'gender', 'birth_month', 'birth_year', 'country', 'state']
    user_attrs = attrs.get('user', {})

    for field in required_fields:
      value = user_attrs.get(field) if field in user_attrs else attrs.get(field)

      if value in (None, ''):
        raise serializers.ValidationError({field: 'This field is required for profile setup.'})

    return attrs

  def validate_professional_id(self, value: str) -> str:
    professional_id = value.strip().lower()

    if not professional_id:
      raise serializers.ValidationError('Professional ID is required.')

    if len(professional_id) < 4:
      raise serializers.ValidationError('Professional ID must be at least 4 characters.')

    if not PROFESSIONAL_ID_PATTERN.match(professional_id):
      raise serializers.ValidationError('Use only letters, numbers, periods, underscores, or hyphens.')

    query = ProfessionalProfile.objects.filter(professional_id__iexact=professional_id)

    if self.instance:
      query = query.exclude(pk=self.instance.pk)

    if query.exists():
      raise serializers.ValidationError('Professional ID is already taken.')

    return professional_id

  def validate_country(self, value):
    country = str(value or '').strip()
    if country.upper() not in settings.REPROOT_SUPPORTED_COUNTRIES:
      raise serializers.ValidationError(
        'RepRoot is currently available for professionals in India and the United States only.'
      )
    return country

  def validate_profile_photo(self, value):
    return self.validate_image_upload(value)

  def validate_transformation_photo(self, value):
    return self.validate_image_upload(value)

  def validate_training_photo(self, value):
    return self.validate_image_upload(value)

  def validate_certification_file(self, value):
    if value.size > 10 * 1024 * 1024:
      raise serializers.ValidationError('Certification files must be smaller than 10 MB.')

    content_type = str(getattr(value, 'content_type', '') or '').lower()
    if content_type and content_type != 'application/pdf' and not content_type.startswith('image/'):
      raise serializers.ValidationError('Upload a PDF or image certification file.')

    detected_type = detect_upload_content_type(value)
    if detected_type is None:
      raise serializers.ValidationError('Upload a PDF or a JPG/PNG/WEBP image - the file content could not be verified.')
    return value

  def validate_image_upload(self, value):
    if value.size > 5 * 1024 * 1024:
      raise serializers.ValidationError('Images must be smaller than 5 MB.')

    content_type = str(getattr(value, 'content_type', '') or '').lower()
    if content_type and not content_type.startswith('image/'):
      raise serializers.ValidationError('Upload a valid image file.')

    detected_type = detect_upload_content_type(value)
    if detected_type is None or not detected_type.startswith('image/'):
      raise serializers.ValidationError('Upload a valid JPG, PNG, WEBP, or GIF image - the file content could not be verified.')
    return value

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

    return normalize_profile_visibility(value)

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


class ProfessionalLeadFormSerializer(serializers.ModelSerializer):
  public_link = serializers.SerializerMethodField()
  custom_fields = serializers.ListField(child=serializers.DictField(), write_only=True, required=False)

  class Meta:
    model = ProfessionalLeadForm
    fields = [
      'id', 'title', 'public_slug', 'public_link', 'fields', 'custom_fields', 'is_active', 'is_mandatory',
      'introductory_meeting_enabled', 'introductory_meeting_title', 'introductory_meeting_duration_minutes',
      'introductory_meeting_min_notice_hours',
      'introductory_meeting_max_advance_days', 'introductory_meeting_buffer_minutes',
      'introductory_meeting_requires_approval', 'created_at', 'updated_at',
    ]
    read_only_fields = ['public_slug', 'public_link', 'fields', 'is_active', 'created_at', 'updated_at']

  def get_public_link(self, obj):
    return get_public_form_link(self.context.get('request'), obj.public_slug)

  def validate_introductory_meeting_duration_minutes(self, value):
    if value not in (15, 30):
      raise serializers.ValidationError('Introductory video meetings must be 15 or 30 minutes.')
    return value

  def validate(self, attrs):
    if 'custom_fields' in attrs:
      attrs['fields'] = normalize_dynamic_fields(attrs.pop('custom_fields'))
    elif self.instance is None:
      attrs['fields'] = normalize_dynamic_fields([])
    if 'title' in attrs:
      attrs['title'] = attrs['title'].strip() or 'Professional Lead Form'
    elif self.instance is None:
      attrs['title'] = 'Professional Lead Form'
    return attrs


class PublicLeadFormSerializer(serializers.ModelSerializer):
  professional_name = serializers.SerializerMethodField()
  meeting_offer = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalLeadForm
    fields = ['id', 'title', 'public_slug', 'professional_name', 'fields', 'meeting_offer']

  def get_professional_name(self, obj):
    return obj.professional.get_full_name() or obj.professional.username

  def get_meeting_offer(self, obj):
    has_availability = ProfessionalAvailabilityWindow.objects.filter(professional=obj.professional, is_active=True).exists()
    enabled = bool(obj.introductory_meeting_enabled and has_availability)
    return {
      'enabled': enabled,
      'title': obj.introductory_meeting_title,
      'duration_minutes': obj.introductory_meeting_duration_minutes,
      'requires_approval': obj.introductory_meeting_requires_approval,
      'min_notice_hours': obj.introductory_meeting_min_notice_hours,
      'max_advance_days': obj.introductory_meeting_max_advance_days,
    }


class ProfessionalGroupSerializer(serializers.ModelSerializer):
  has_registration_form = serializers.SerializerMethodField()
  registration_form = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalGroup
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
    fields = ['id', 'group', 'public_slug', 'fields', 'custom_fields', 'is_active', 'is_mandatory', 'created_at', 'updated_at']
    read_only_fields = ['id', 'group', 'public_slug', 'fields', 'is_active', 'created_at', 'updated_at']

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


class LeadMeetingRequestSerializer(serializers.ModelSerializer):
  reference_id = serializers.CharField(source='submission.reference_id', read_only=True)
  applicant_name = serializers.SerializerMethodField()
  form_title = serializers.CharField(source='submission.lead_form.title', read_only=True)

  class Meta:
    model = LeadMeetingRequest
    fields = [
      'id', 'reference_id', 'applicant_name', 'form_title', 'contact_email', 'contact_mobile',
      'requested_start', 'requested_end', 'status', 'trainer_note', 'meeting_url', 'expires_at',
      'external_calendar_provider', 'external_calendar_url', 'external_calendar_sync_status',
      'reviewed_at', 'created_at', 'updated_at',
    ]
    read_only_fields = fields

  def get_applicant_name(self, obj):
    return f'{obj.submission.first_name} {obj.submission.last_name}'.strip()


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


class GroupRegistrationSubmissionSerializer(serializers.ModelSerializer):
  applicant_name = serializers.SerializerMethodField()
  client_access_id = serializers.SerializerMethodField()

  class Meta:
    model = GroupRegistrationSubmission
    fields = [
      'id',
      'group',
      'applicant_name',
      'first_name',
      'last_name',
      'email',
      'reference_id',
      'answers',
      'status',
      'submitted_at',
      'converted_at',
      'client_access_id',
    ]
    read_only_fields = fields

  def get_applicant_name(self, obj):
    return f'{obj.first_name} {obj.last_name}'.strip()

  def get_client_access_id(self, obj):
    try:
      return obj.client_access.id
    except ClientAccess.DoesNotExist:
      return None


class PublicGroupRegistrationSerializer(serializers.Serializer):
  answers = serializers.DictField()

  def validate(self, attrs):
    registration_form = self.context['registration_form']
    answers = attrs['answers']
    validate_required_answers(registration_form.fields, answers)
    attrs['first_name'] = str(answers.get('first_name', '')).strip()
    attrs['last_name'] = str(answers.get('last_name', '')).strip()
    attrs['email'] = str(answers.get('email', '')).strip().lower()
    return attrs


class ClientAccessCreateSerializer(serializers.Serializer):
  group_id = serializers.IntegerField()
  has_portal_access = serializers.BooleanField(required=False, default=True)
  username = serializers.CharField(max_length=150, required=False, allow_blank=True)
  password = serializers.CharField(min_length=8, write_only=True, required=False, allow_blank=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True, required=False, allow_blank=True)
  photo = serializers.CharField(required=False, allow_blank=True, default='')
  registration_answers = serializers.DictField(required=False)
  send_credentials = serializers.BooleanField(required=False, default=True)
  registration_submission_id = serializers.IntegerField(required=False, allow_null=True)

  def validate_username(self, value):
    username = value.strip().lower()

    if not username:
      return username

    validate_username_charset(username)

    professional = self.context.get('professional')

    if professional and ClientAccess.objects.filter(professional=professional, username__iexact=username).exists():
      raise serializers.ValidationError('Client username is already taken.')

    return username

  def validate(self, attrs):
    has_portal_access = attrs.get('has_portal_access', True)

    if not has_portal_access:
      # Info-only client: no login credentials are created or expected.
      attrs['username'] = ''
      attrs['password'] = ''
      attrs['confirm_password'] = ''
      return attrs

    username = attrs.get('username', '')
    password = attrs.get('password', '')
    confirm_password = attrs.get('confirm_password', '')

    if not username:
      raise serializers.ValidationError({'username': 'Client username is required.'})

    if not password:
      raise serializers.ValidationError({'password': 'Client password is required.'})

    if not confirm_password:
      raise serializers.ValidationError({'confirm_password': 'Please confirm the client password.'})

    try:
      validate_password_strength(password)
    except serializers.ValidationError as error:
      raise serializers.ValidationError({'password': error.detail[0]})

    if password != confirm_password:
      raise serializers.ValidationError({'confirm_password': 'Passwords must match.'})

    return attrs


class ClientPortalAccessGrantSerializer(serializers.Serializer):
  """Used to grant portal login access to an existing info-only ClientAccess."""

  username = serializers.CharField(max_length=150)
  password = serializers.CharField(min_length=8, write_only=True)
  confirm_password = serializers.CharField(min_length=8, write_only=True)
  send_credentials = serializers.BooleanField(required=False, default=True)

  def validate_username(self, value):
    username = value.strip().lower()

    if not username:
      raise serializers.ValidationError('Client username is required.')

    validate_username_charset(username)

    professional = self.context.get('professional')
    client_access = self.context.get('client_access')

    existing = ClientAccess.objects.filter(professional=professional, username__iexact=username)

    if client_access is not None:
      existing = existing.exclude(id=client_access.id)

    if professional and existing.exists():
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
  professional_id = serializers.CharField(max_length=32)
  username = serializers.CharField(max_length=150)
  password = serializers.CharField(write_only=True)

  def validate(self, attrs):
    professional_id = attrs['professional_id'].strip().lower()
    username = attrs['username'].strip().lower()
    password = attrs['password']

    if not professional_id:
      raise serializers.ValidationError({'professional_id': 'Professional ID is required.'})

    base_records = ClientAccess.objects.filter(
      professional__professional_profile__professional_id__iexact=professional_id,
      professional__is_active=True,
      professional__professional_profile__lifecycle_status=ProfessionalProfile.LIFECYCLE_ACTIVE,
      username__iexact=username,
      is_active=True,
    ).select_related('professional', 'group', 'lead_submission', 'registration_submission')

    if base_records.filter(has_portal_access=False).exists() and not base_records.filter(has_portal_access=True).exists():
      raise serializers.ValidationError('This client does not have portal access. Ask your professional to grant access.')

    access_records = base_records.filter(has_portal_access=True)

    client_access = None

    for access_record in access_records:
      stored_password = access_record.temporary_password

      if stored_password.startswith('pbkdf2_') and check_password(password, stored_password):
        client_access = access_record
        break

      # Legacy fallback for any record whose password was never hashed
      # (every current write path uses make_password(), so this should be
      # unreachable in practice - kept only so an old plaintext row isn't
      # a permanent lockout). Constant-time compare to avoid a timing
      # side-channel on a raw string in the database.
      if secrets.compare_digest(stored_password, password):
        access_record.temporary_password = make_password(password)
        access_record.must_change_password = False
        access_record.save(update_fields=['temporary_password', 'must_change_password', 'updated_at'])
        client_access = access_record
        break

    if client_access is None:
      raise serializers.ValidationError('Invalid professional ID, client username, or password.')

    attrs['client_access'] = client_access
    return attrs


class ClientProfessionalLookupSerializer(serializers.Serializer):
  professional_id = serializers.CharField(max_length=32)

  def validate_professional_id(self, value: str) -> str:
    professional_id = value.strip().lower()

    if not professional_id:
      raise serializers.ValidationError('Professional ID is required.')

    return professional_id


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


class ResourceCategorySerializer(serializers.ModelSerializer):
  resource_count = serializers.SerializerMethodField()

  class Meta:
    model = ResourceCategory
    fields = ['id', 'name', 'description', 'subcategories', 'resource_count', 'created_at', 'updated_at']
    read_only_fields = ['id', 'resource_count', 'created_at', 'updated_at']

  def get_resource_count(self, obj):
    return obj.resources.count()

  def validate_name(self, value):
    name = value.strip()

    if not name:
      raise serializers.ValidationError('Category name is required.')

    return name

  def validate_subcategories(self, value):
    if not isinstance(value, list):
      raise serializers.ValidationError('Subcategories must be a list.')

    return [str(subcategory).strip() for subcategory in value if str(subcategory).strip()]


class ProfessionalResourceSerializer(serializers.ModelSerializer):
  category_name = serializers.CharField(source='category.name', read_only=True)
  file_url = serializers.SerializerMethodField()
  file_name = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalResource
    fields = [
      'id',
      'category',
      'category_name',
      'subcategory',
      'title',
      'resource_type',
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
    resource_type = attrs.get('resource_type') or (self.instance.resource_type if self.instance else '')
    link = (attrs.get('link') if 'link' in attrs else (self.instance.link if self.instance else '')) or ''
    file = attrs.get('file') if 'file' in attrs else (self.instance.file if self.instance else None)

    if resource_type == ProfessionalResource.TYPE_VIDEO_LINK:
      if not link:
        raise serializers.ValidationError({'link': 'Video URL is required.'})

      if not is_youtube_link(link):
        raise serializers.ValidationError({'link': 'Videos must be YouTube links so they can be streamed in-app.'})

      attrs['file'] = None

    upload = attrs.get('file')

    if resource_type == ProfessionalResource.TYPE_PDF:
      if not link and not file:
        raise serializers.ValidationError({'file': 'Upload a PDF or paste a PDF URL.'})

      if upload and getattr(upload, 'content_type', '') != 'application/pdf':
        raise serializers.ValidationError({'file': 'Only PDF uploads are allowed.'})

      if upload and detect_upload_content_type(upload) != 'application/pdf':
        raise serializers.ValidationError({'file': 'The file content does not match a valid PDF.'})

    if resource_type == ProfessionalResource.TYPE_TEXT_NOTE:
      if not attrs.get('description', '').strip():
        raise serializers.ValidationError({'description': 'Text is required.'})

      attrs['link'] = ''
      attrs['file'] = None

    if resource_type == ProfessionalResource.TYPE_IMAGE:
      if not file:
        raise serializers.ValidationError({'file': 'Image upload is required.'})

      content_type = getattr(upload or file, 'content_type', '')
      if upload and not content_type.startswith('image/'):
        raise serializers.ValidationError({'file': 'Only image uploads are allowed.'})

      if upload:
        detected_type = detect_upload_content_type(upload)
        if detected_type is None or not detected_type.startswith('image/'):
          raise serializers.ValidationError({'file': 'The file content does not match a supported image format.'})

    return attrs


class TrackingTemplateResourceSerializer(serializers.ModelSerializer):
  """Read-only, compact resource representation shared with a client via an assignment."""

  category_name = serializers.CharField(source='category.name', read_only=True)
  file_url = serializers.SerializerMethodField()

  class Meta:
    model = ProfessionalResource
    fields = ['id', 'title', 'resource_type', 'category_name', 'subcategory', 'description', 'link', 'file_url', 'tags']
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
  resources = TrackingTemplateResourceSerializer(many=True, read_only=True)

  class Meta:
    model = TemplateAssignment
    fields = [
      'id',
      'template_id',
      'template_name',
      'template_cadence',
      'template_accent',
      'resources',
      'client_access_level',
      'assigned_at',
    ]
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
      'edited_by_professional',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'client', 'template', 'template_name', 'edited_by_professional', 'created_at', 'updated_at']


CHAT_IMAGE_MAX_BYTES = 5 * 1024 * 1024
CHAT_IMAGE_CONTENT_TYPES = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'}


class RecycleBinItemSerializer(serializers.ModelSerializer):
  days_remaining = serializers.SerializerMethodField()
  category_label = serializers.CharField(source='get_category_display', read_only=True)
  deleted_by_label = serializers.CharField(source='get_deleted_by_display', read_only=True)

  class Meta:
    model = RecycleBinItem
    fields = [
      'id', 'category', 'category_label', 'title', 'deleted_by', 'deleted_by_label',
      'deleted_at', 'expires_at', 'days_remaining',
    ]
    read_only_fields = fields

  def get_days_remaining(self, obj):
    from django.utils import timezone

    remaining = (obj.expires_at - timezone.now()).days
    return max(0, remaining)


class ChatMessageSerializer(serializers.ModelSerializer):
  image_url = serializers.SerializerMethodField()

  class Meta:
    model = ChatMessage
    fields = ['id', 'sender', 'text', 'image', 'image_url', 'created_at']
    read_only_fields = ['id', 'sender', 'image_url', 'created_at']
    extra_kwargs = {'image': {'write_only': True, 'required': False}}

  def validate_text(self, value):
    return value.strip()

  def validate_image(self, value):
    if value.size > CHAT_IMAGE_MAX_BYTES:
      raise serializers.ValidationError('Images must be 5MB or smaller.')
    if value.content_type not in CHAT_IMAGE_CONTENT_TYPES:
      raise serializers.ValidationError('Images must be JPEG, PNG, WebP, or GIF.')
    detected_type = detect_upload_content_type(value)
    if detected_type is None or detected_type not in CHAT_IMAGE_CONTENT_TYPES:
      raise serializers.ValidationError('The file content does not match a supported image format.')
    return value

  def validate(self, attrs):
    if not attrs.get('text') and not attrs.get('image'):
      raise serializers.ValidationError('Send some text, an image, or both.')
    return attrs

  def get_image_url(self, obj):
    if not obj.image:
      return ''
    request = self.context.get('request')
    return request.build_absolute_uri(obj.image.url) if request else obj.image.url


class ClientPasswordChangeSerializer(serializers.Serializer):
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

  def save(self):
    client_access = self.context['client_access']
    client_access.temporary_password = make_password(self.validated_data['password'])
    client_access.must_change_password = False
    client_access.save(update_fields=['temporary_password', 'must_change_password', 'updated_at'])
    return client_access


class ClientAccessSerializer(serializers.ModelSerializer):
  group_name = serializers.CharField(source='group.name', read_only=True)
  professional_name = serializers.SerializerMethodField()
  additional_info = serializers.SerializerMethodField()
  legal_acceptance_history = serializers.SerializerMethodField()
  current_legal_document_version = serializers.SerializerMethodField()

  class Meta:
    model = ClientAccess
    fields = [
      'id',
      'group',
      'group_name',
      'professional_name',
      'lead_submission',
      'registration_submission',
      'reference_id',
      'onboarding_method',
      'first_name',
      'last_name',
      'email',
      'username',
      'has_portal_access',
      'photo',
      'registration_answers',
      'additional_info',
      'additional_info_shared',
      'must_change_password',
      'terms_accepted',
      'privacy_policy_accepted',
      'legal_document_version',
      'terms_accepted_at',
      'privacy_policy_accepted_at',
      'legal_acceptance_history',
      'current_legal_document_version',
      'is_active',
      'created_at',
      'updated_at',
    ]
    read_only_fields = fields

  def get_professional_name(self, obj):
    return obj.professional.get_full_name() or obj.professional.username

  def get_additional_info(self, obj):
    return normalize_additional_info(obj.additional_info)

  def get_legal_acceptance_history(self, obj):
    return [
      {
        'legal_document_version': row.legal_document_version,
        'accepted_at': row.accepted_at,
        'client_timezone': row.client_timezone,
      }
      for row in obj.legal_acceptance_records.all()[:20]
    ]

  def get_current_legal_document_version(self, _obj):
    return settings.REPROOT_CLIENT_LEGAL_VERSION

  def to_representation(self, instance):
    data = super().to_representation(instance)
    if instance.legal_document_version != settings.REPROOT_CLIENT_LEGAL_VERSION:
      data['terms_accepted'] = False
      data['privacy_policy_accepted'] = False
    return data


class ClientAdditionalInfoUpdateSerializer(serializers.Serializer):
  additional_info = serializers.JSONField()
  additional_info_shared = serializers.BooleanField(required=False)

  def validate_additional_info(self, value):
    if not isinstance(value, list):
      raise serializers.ValidationError('Must be a list.')

    if len(value) > 100:
      raise serializers.ValidationError('A maximum of 100 additional information items is allowed.')

    return normalize_additional_info(value)


class ClientPhotoUpdateSerializer(serializers.Serializer):
  photo = serializers.CharField(required=False, allow_blank=True, trim_whitespace=False, default='')

  def validate_photo(self, value):
    return validate_client_photo(value)


class ClientDetailChangeRequestSerializer(serializers.ModelSerializer):
  reviewed_by = serializers.SerializerMethodField()

  class Meta:
    model = ClientDetailChangeRequest
    fields = [
      'id',
      'client',
      'request_type',
      'proposed_answers',
      'status',
      'client_note',
      'professional_note',
      'created_at',
      'reviewed_at',
      'reviewed_by',
      'archived_at',
    ]
    read_only_fields = fields

  def get_reviewed_by(self, obj):
    if not obj.reviewed_at:
      return ''
    professional = obj.client.professional
    return professional.get_full_name() or professional.username


class SupportIncidentMessageSerializer(serializers.ModelSerializer):
  class Meta:
    model = SupportIncidentMessage
    fields = ['id', 'author_type', 'author_name', 'body', 'created_at']
    read_only_fields = fields


class SupportIncidentSerializer(serializers.ModelSerializer):
  messages = serializers.SerializerMethodField()
  screenshot_url = serializers.SerializerMethodField()
  assigned_support_name = serializers.SerializerMethodField()

  class Meta:
    model = SupportIncident
    fields = [
      'id', 'incident_id', 'reporter_role', 'reporter_name', 'reporter_email', 'category',
      'subject', 'description', 'page_feature', 'platform', 'app_version', 'device_info',
      'screenshot_url', 'priority', 'status', 'assigned_support_name', 'resolution_note',
      'closed_at', 'created_at', 'updated_at', 'messages',
    ]
    read_only_fields = fields

  def get_messages(self, obj):
    messages = obj.messages.all()
    if not self.context.get('include_internal', False):
      messages = messages.exclude(author_type=SupportIncidentMessage.AUTHOR_INTERNAL)
    return SupportIncidentMessageSerializer(messages, many=True).data

  def get_screenshot_url(self, obj):
    if not obj.screenshot:
      return ''
    request = self.context.get('request')
    return request.build_absolute_uri(obj.screenshot.url) if request else obj.screenshot.url

  def get_assigned_support_name(self, obj):
    if not obj.assigned_support:
      return ''
    return obj.assigned_support.get_full_name() or obj.assigned_support.username


class SupportIncidentCreateSerializer(serializers.Serializer):
  category = serializers.ChoiceField(choices=SupportIncident.CATEGORY_CHOICES)
  subject = serializers.CharField(max_length=180)
  description = serializers.CharField(max_length=5000)
  page_feature = serializers.CharField(max_length=180, required=False, allow_blank=True, default='')
  platform = serializers.ChoiceField(choices=['web', 'android'], default='web')
  app_version = serializers.CharField(max_length=40, required=False, allow_blank=True, default='')
  device_info = serializers.CharField(max_length=300, required=False, allow_blank=True, default='')
  screenshot = serializers.FileField(required=False, allow_null=True)

  def validate_screenshot(self, value):
    if not value:
      return value
    if value.size > 5 * 1024 * 1024:
      raise serializers.ValidationError('Screenshots must be 5 MB or smaller.')
    content_type = str(getattr(value, 'content_type', '')).lower()
    if content_type not in ('image/jpeg', 'image/png', 'image/webp'):
      raise serializers.ValidationError('Only PNG, JPEG, and WebP screenshots are supported.')
    detected_type = detect_upload_content_type(value)
    if detected_type not in ('image/jpeg', 'image/png', 'image/webp'):
      raise serializers.ValidationError('The file content does not match a supported image format.')
    return value


class ErrorReportSerializer(serializers.Serializer):
  """Automatic crash/error capture from the running web or mobile app — a
  fire-and-forget beacon, not a user-filled form, so every field beyond
  platform/message stays optional rather than rejecting a malformed report.
  """
  platform = serializers.ChoiceField(choices=['web', 'android', 'ios'])
  level = serializers.ChoiceField(choices=['warning', 'error', 'fatal'], default='error')
  message = serializers.CharField(max_length=500)
  stack_trace = serializers.CharField(max_length=20000, required=False, allow_blank=True, default='')
  context = serializers.JSONField(required=False, default=dict)
  app_version = serializers.CharField(max_length=40, required=False, allow_blank=True, default='')
  device_info = serializers.CharField(max_length=300, required=False, allow_blank=True, default='')
  request_path = serializers.CharField(max_length=300, required=False, allow_blank=True, default='')

  def validate_context(self, value):
    return value if isinstance(value, dict) else {}


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
      'notify_professional',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'client', 'client_name', 'created_at', 'updated_at']

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username


class ProfessionalSchedulingSettingsSerializer(serializers.ModelSerializer):
  """Local, self-contained scheduling configuration — no third-party account
  required. Replaces the old CalComConnectionSerializer entirely."""

  class Meta:
    model = ProfessionalSchedulingSettings
    fields = ['timezone', 'default_duration_minutes', 'slot_interval_minutes', 'buffer_minutes', 'updated_at']
    read_only_fields = ['updated_at']

  def validate_timezone(self, value):
    try:
      ZoneInfo(value)
    except Exception:
      raise serializers.ValidationError('That is not a recognized timezone.')
    return value

  def validate_default_duration_minutes(self, value):
    if value not in (15, 30):
      raise serializers.ValidationError('Default video meetings must be 15 or 30 minutes.')
    return value

  def validate_slot_interval_minutes(self, value):
    if value <= 0:
      raise serializers.ValidationError('Slot interval must be at least 1 minute.')
    return value


class ProfessionalAvailabilityWindowSerializer(serializers.ModelSerializer):
  """One weekly recurring block of bookable time. A professional can have
  several rows for the same weekday — that's how multiple separate blocks on
  one day (e.g. Monday 10-12 and Monday 14-16) are represented — so there is
  deliberately no uniqueness validation on weekday alone."""

  class Meta:
    model = ProfessionalAvailabilityWindow
    fields = ['id', 'weekday', 'start_time', 'end_time', 'is_active', 'created_at', 'updated_at']
    read_only_fields = ['id', 'created_at', 'updated_at']

  def validate_weekday(self, value):
    if not (0 <= value <= 6):
      raise serializers.ValidationError('weekday must be between 0 (Monday) and 6 (Sunday).')
    return value

  def validate(self, attrs):
    start_time = attrs.get('start_time', getattr(self.instance, 'start_time', None))
    end_time = attrs.get('end_time', getattr(self.instance, 'end_time', None))
    weekday = attrs.get('weekday', getattr(self.instance, 'weekday', None))

    if start_time and end_time and start_time >= end_time:
      raise serializers.ValidationError({'end_time': 'End time must be after start time.'})

    professional = self.context.get('professional')
    if professional and start_time and end_time and weekday is not None:
      overlapping = ProfessionalAvailabilityWindow.objects.filter(
        professional=professional,
        weekday=weekday,
        start_time__lt=end_time,
        end_time__gt=start_time,
      )
      if self.instance is not None:
        overlapping = overlapping.exclude(id=self.instance.id)
      if overlapping.exists():
        raise serializers.ValidationError(
          {'start_time': 'This overlaps with an existing availability block on this day.'}
        )

    return attrs


class ProfessionalDateOffSerializer(serializers.ModelSerializer):
  """A single blocked-off calendar date -- see ProfessionalDateOff for why
  this is separate from the recurring weekly ProfessionalAvailabilityWindow
  rows."""

  class Meta:
    model = ProfessionalDateOff
    fields = ['id', 'date', 'created_at']
    read_only_fields = ['id', 'created_at']

  def validate_date(self, value):
    from django.utils import timezone as dj_timezone

    if value < dj_timezone.now().date():
      raise serializers.ValidationError('Cannot mark a date in the past as a day off.')
    professional = self.context.get('professional')
    if professional and ProfessionalDateOff.objects.filter(professional=professional, date=value).exists():
      raise serializers.ValidationError('This date is already marked as a day off.')
    return value


class ProfessionalWeekdayOffSerializer(serializers.ModelSerializer):
  """A recurring weekly day off (e.g. every Monday) -- see
  ProfessionalWeekdayOff for how this differs from the one-off
  ProfessionalDateOff rows above."""

  class Meta:
    model = ProfessionalWeekdayOff
    fields = ['id', 'weekday', 'created_at']
    read_only_fields = ['id', 'created_at']

  def validate_weekday(self, value):
    if value < 0 or value > 6:
      raise serializers.ValidationError('Weekday must be between 0 (Monday) and 6 (Sunday).')
    professional = self.context.get('professional')
    if professional and ProfessionalWeekdayOff.objects.filter(professional=professional, weekday=value).exists():
      raise serializers.ValidationError('This weekday is already marked as a recurring day off.')
    return value


class ScheduledMeetingGuestSerializer(serializers.ModelSerializer):
  client_name = serializers.SerializerMethodField()

  class Meta:
    model = ScheduledMeetingGuest
    fields = ['id', 'client', 'client_name', 'response_status', 'responded_at']
    read_only_fields = fields

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username


class ScheduledMeetingSerializer(serializers.ModelSerializer):
  """`context['client']` (a ClientAccess), when present, is the requesting
  client-portal user — used to surface `my_response_status` so the client's
  own UI doesn't have to figure out whether they're the primary attendee or
  a guest to know which response applies to them."""

  client_name = serializers.SerializerMethodField()
  guests = ScheduledMeetingGuestSerializer(many=True, read_only=True)
  is_group_meeting = serializers.SerializerMethodField()
  my_response_status = serializers.SerializerMethodField()

  class Meta:
    model = ScheduledMeeting
    fields = [
      'id',
      'client',
      'client_name',
      'title',
      'notes',
      'start_at',
      'end_at',
      'meeting_url',
      'external_calendar_provider',
      'external_calendar_url',
      'external_calendar_sync_status',
      'status',
      'requested_by',
      'professional_responded_at',
      'cancellation_reason',
      'client_response_status',
      'guests',
      'is_group_meeting',
      'my_response_status',
      'created_at',
      'updated_at',
    ]
    read_only_fields = [
      'id', 'client_name', 'meeting_url', 'external_calendar_provider', 'external_calendar_url',
      'external_calendar_sync_status', 'status', 'requested_by', 'professional_responded_at',
      'cancellation_reason', 'client_response_status',
      'guests', 'is_group_meeting', 'my_response_status', 'created_at', 'updated_at',
    ]

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username

  def get_is_group_meeting(self, obj):
    return len(obj.guests.all()) > 0

  def get_my_response_status(self, obj):
    requesting_client = self.context.get('client')
    if requesting_client is None:
      return None
    if requesting_client.id == obj.client_id:
      return obj.client_response_status
    guest = next((g for g in obj.guests.all() if g.client_id == requesting_client.id), None)
    return guest.response_status if guest else None


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


class ProfessionalPaymentSettingsSerializer(serializers.ModelSerializer):
  class Meta:
    model = ProfessionalPaymentSettings
    fields = [
      'payment_tracking_enabled',
      'reporting_currency',
      'reporting_currency_locked',
      'reporting_currency_locked_at',
      'client_payment_history_enabled',
      'updated_at',
    ]
    read_only_fields = [
      'payment_tracking_enabled',
      'client_payment_history_enabled',
      'reporting_currency_locked',
      'reporting_currency_locked_at',
      'updated_at',
    ]

  def validate_reporting_currency(self, value):
    code = value.strip().upper()
    if code not in ISO_4217_CODES:
      raise serializers.ValidationError('Choose a supported ISO currency code.')
    return code

  def validate(self, attrs):
    if self.instance and self.instance.reporting_currency_locked:
      requested = attrs.get('reporting_currency', self.instance.reporting_currency)
      if requested != self.instance.reporting_currency:
        raise serializers.ValidationError({
          'reporting_currency': 'Reporting currency is permanently locked. Contact support to request an audited change.'
        })
    return attrs


class ManualPaymentProfileSerializer(serializers.ModelSerializer):
  """Full professional-facing view of a manual payment method. The redacted
  client projection lives in ManualPaymentProfileClientSerializer - private
  fields must never be added there."""

  class Meta:
    model = ManualPaymentProfile
    fields = [
      'id',
      'name',
      'category',
      'display_label',
      'supported_currencies',
      'country',
      'private_fields',
      'client_visible_fields',
      'qr_code',
      'internal_notes',
      'client_instructions',
      'status',
      'created_at',
      'updated_at',
    ]
    read_only_fields = ['id', 'created_at', 'updated_at']

  def validate_display_label(self, value):
    label = value.strip()
    if not label:
      raise serializers.ValidationError('Display label is required.')
    return label

  def validate_supported_currencies(self, value):
    if not isinstance(value, list):
      raise serializers.ValidationError('Supported currencies must be a list of currency codes.')
    codes = []
    for code in value:
      normalized = str(code).strip().upper()
      if normalized not in ISO_4217_CODES:
        raise serializers.ValidationError(f'{code} is not a supported currency code.')
      if normalized not in codes:
        codes.append(normalized)
    return codes

  def validate_qr_code(self, value):
    if value is None:
      return value
    content_type = getattr(value, 'content_type', '')
    if content_type not in PAYMENT_QR_CONTENT_TYPES:
      raise serializers.ValidationError('QR code must be a PNG, JPG, or WEBP image.')
    if value.size > PAYMENT_QR_MAX_BYTES:
      raise serializers.ValidationError('QR code image must be under 2MB.')
    detected_type = detect_upload_content_type(value)
    if detected_type is None or detected_type != content_type:
      raise serializers.ValidationError('The file content does not match a supported PNG, JPG, or WEBP image.')
    return value

  def validate(self, attrs):
    category = attrs.get('category') or (self.instance.category if self.instance else None)
    client_fields = attrs.get('client_visible_fields')
    if client_fields is None:
      client_fields = self.instance.client_visible_fields if self.instance else {}

    if not isinstance(client_fields, dict):
      raise serializers.ValidationError({'client_visible_fields': 'Client-visible fields must be an object.'})

    required_keys = CATEGORY_REQUIRED_CLIENT_FIELDS.get(category, [])
    missing = [key for key in required_keys if not str(client_fields.get(key) or '').strip()]
    if missing:
      labels = ', '.join(key.replace('_', ' ') for key in missing)
      raise serializers.ValidationError(
        {'client_visible_fields': f'This payment category needs: {labels}.'}
      )

    private_fields = attrs.get('private_fields')
    if private_fields is not None and not isinstance(private_fields, dict):
      raise serializers.ValidationError({'private_fields': 'Private fields must be an object.'})

    return attrs


class ManualPaymentProfileClientSerializer(serializers.ModelSerializer):
  """What a client is allowed to see about a shared payment method. Keep this
  list tight: name, private_fields, and internal_notes must NEVER appear."""

  class Meta:
    model = ManualPaymentProfile
    fields = [
      'id',
      'category',
      'display_label',
      'supported_currencies',
      'client_visible_fields',
      'qr_code',
      'client_instructions',
    ]
    read_only_fields = fields


class PaymentRequestSerializer(serializers.ModelSerializer):
  client_name = serializers.SerializerMethodField()
  allowed_method_labels = serializers.SerializerMethodField()
  accepted_amount = serializers.SerializerMethodField()
  remaining_amount = serializers.SerializerMethodField()
  overpaid_amount = serializers.SerializerMethodField()
  correction_deadline = serializers.SerializerMethodField()
  is_locked = serializers.SerializerMethodField()

  class Meta:
    model = PaymentRequest
    fields = [
      'id',
      'request_id',
      'client',
      'client_name',
      'payment_plan',
      'title',
      'description',
      'requested_amount',
      'requested_currency',
      'accepted_amount',
      'remaining_amount',
      'overpaid_amount',
      'due_date',
      'payment_type',
      'status',
      'client_visibility',
      'notes',
      'allowed_method_labels',
      'created_at',
      'sent_at',
      'viewed_at',
      'completed_at',
      'correction_deadline',
      'is_locked',
      'updated_at',
    ]
    read_only_fields = [
      'id', 'request_id', 'client', 'client_name', 'status', 'allowed_method_labels',
      'created_at', 'sent_at', 'viewed_at', 'completed_at', 'updated_at',
    ]

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username

  def get_allowed_method_labels(self, obj):
    return [
      allowed.manual_payment_profile.display_label
      for allowed in obj.allowed_methods.select_related('manual_payment_profile')
      if allowed.manual_payment_profile
    ]

  def get_accepted_amount(self, obj):
    return sum(
      (proof.reported_amount for proof in obj.proofs.all()
       if proof.status == PaymentProof.STATUS_ACCEPTED and proof.reported_currency == obj.requested_currency),
      Decimal('0.00'),
    )

  def get_remaining_amount(self, obj):
    return max(Decimal('0.00'), obj.requested_amount - self.get_accepted_amount(obj))

  def get_overpaid_amount(self, obj):
    return max(Decimal('0.00'), self.get_accepted_amount(obj) - obj.requested_amount)

  def get_correction_deadline(self, obj):
    return obj.completed_at + timedelta(days=14) if obj.completed_at else None

  def get_is_locked(self, obj):
    deadline = self.get_correction_deadline(obj)
    return bool(deadline and timezone.now() > deadline)

  def validate_title(self, value):
    title = value.strip()
    if not title:
      raise serializers.ValidationError('Payment title is required.')
    return title

  def validate_requested_amount(self, value):
    if value <= 0:
      raise serializers.ValidationError('Requested amount must be greater than zero.')
    return value

  def validate_requested_currency(self, value):
    code = value.strip().upper()
    if code not in ISO_4217_CODES:
      raise serializers.ValidationError('Choose a supported ISO currency code.')
    return code


class ClientPaymentRequestSerializer(serializers.ModelSerializer):
  """Client-facing projection of a payment request. Professional notes and
  internal linkage fields are deliberately absent."""

  professional_name = serializers.SerializerMethodField()
  available_methods = serializers.SerializerMethodField()
  proofs = serializers.SerializerMethodField()
  accepted_amount = serializers.SerializerMethodField()
  remaining_amount = serializers.SerializerMethodField()
  overpaid_amount = serializers.SerializerMethodField()
  correction_deadline = serializers.SerializerMethodField()
  is_locked = serializers.SerializerMethodField()

  class Meta:
    model = PaymentRequest
    fields = [
      'request_id',
      'professional_name',
      'title',
      'description',
      'requested_amount',
      'requested_currency',
      'accepted_amount',
      'remaining_amount',
      'overpaid_amount',
      'due_date',
      'payment_type',
      'status',
      'available_methods',
      'proofs',
      'created_at',
      'sent_at',
      'correction_deadline',
      'is_locked',
    ]
    read_only_fields = fields

  def get_professional_name(self, obj):
    professional = obj.professional
    return f'{professional.first_name} {professional.last_name}'.strip() or professional.username

  def get_available_methods(self, obj):
    methods = [
      allowed.manual_payment_profile
      for allowed in obj.allowed_methods.select_related('manual_payment_profile')
      if allowed.manual_payment_profile and allowed.manual_payment_profile.status == 'active'
    ]
    return ManualPaymentProfileClientSerializer(methods, many=True).data

  def get_proofs(self, obj):
    # The client's own submission history for this request, including any
    # rejection reason — without this, a rejected proof silently resets the
    # request to "viewed" with no visible trace of what happened.
    return PaymentProofSerializer(obj.proofs.order_by('-submitted_at'), many=True).data

  def get_accepted_amount(self, obj):
    return sum(
      (proof.reported_amount for proof in obj.proofs.all()
       if proof.status == PaymentProof.STATUS_ACCEPTED and proof.reported_currency == obj.requested_currency),
      Decimal('0.00'),
    )

  def get_remaining_amount(self, obj):
    return max(Decimal('0.00'), obj.requested_amount - self.get_accepted_amount(obj))

  def get_overpaid_amount(self, obj):
    return max(Decimal('0.00'), self.get_accepted_amount(obj) - obj.requested_amount)

  def get_correction_deadline(self, obj):
    return obj.completed_at + timedelta(days=14) if obj.completed_at else None

  def get_is_locked(self, obj):
    deadline = self.get_correction_deadline(obj)
    return bool(deadline and timezone.now() > deadline)


class PaymentProofSubmitSerializer(serializers.ModelSerializer):
  """Client-submitted proof of an external payment. Requires a transaction
  reference OR a proof file, plus an explicit accuracy confirmation."""

  confirmed_accurate = serializers.BooleanField()

  class Meta:
    model = PaymentProof
    fields = [
      'transaction_reference',
      'reported_amount',
      'reported_currency',
      'reported_payment_date',
      'payment_method',
      'proof_file',
      'note',
      'confirmed_accurate',
    ]

  def validate_reported_amount(self, value):
    if value <= 0:
      raise serializers.ValidationError('Amount paid must be greater than zero.')
    return value

  def validate_reported_currency(self, value):
    code = value.strip().upper()
    if code not in ISO_4217_CODES:
      raise serializers.ValidationError('Choose a supported ISO currency code.')
    return code

  def validate_reported_payment_date(self, value):
    from django.utils import timezone as dj_timezone
    if value > dj_timezone.now().date():
      raise serializers.ValidationError('Payment date cannot be in the future.')
    return value

  def validate_proof_file(self, value):
    if value is None:
      return value
    content_type = getattr(value, 'content_type', '')
    if content_type not in PAYMENT_PROOF_CONTENT_TYPES:
      raise serializers.ValidationError('Use a JPG, PNG, WEBP, or PDF file.')
    if value.size > PAYMENT_PROOF_MAX_BYTES:
      raise serializers.ValidationError('Proof file must be under 5MB.')
    detected_type = detect_upload_content_type(value)
    if detected_type is None or detected_type != content_type:
      raise serializers.ValidationError(
        'The file content does not match a supported JPG, PNG, WEBP, or PDF format.'
      )
    return value

  def validate_confirmed_accurate(self, value):
    if not value:
      raise serializers.ValidationError('Confirm the submitted information is accurate.')
    return value

  def validate(self, attrs):
    if not str(attrs.get('transaction_reference') or '').strip() and not attrs.get('proof_file'):
      raise serializers.ValidationError('Enter a transaction ID or attach a proof file before submitting.')
    return attrs


class PaymentProofSerializer(serializers.ModelSerializer):
  """Professional-facing review projection of a submitted proof."""

  payment_method_label = serializers.SerializerMethodField()
  has_file = serializers.SerializerMethodField()
  payment_record_id = serializers.SerializerMethodField()

  class Meta:
    model = PaymentProof
    fields = [
      'id',
      'transaction_reference',
      'reported_amount',
      'reported_currency',
      'reported_payment_date',
      'payment_method',
      'payment_method_label',
      'has_file',
      'payment_record_id',
      'note',
      'status',
      'review_note',
      'submitted_by',
      'submitted_at',
      'reviewed_at',
    ]
    read_only_fields = fields

  def get_payment_method_label(self, obj):
    return obj.payment_method.display_label if obj.payment_method else ''

  def get_has_file(self, obj):
    return bool(obj.proof_file)

  def get_payment_record_id(self, obj):
    try:
      record = obj.payment_record
    except PaymentRecord.DoesNotExist:
      return ''
    return record.payment_record_id if record.client_visibility == 'visible' else ''


class PaymentRecordSerializer(serializers.ModelSerializer):
  client_name = serializers.SerializerMethodField()
  payment_method_label = serializers.SerializerMethodField()
  request_reference = serializers.SerializerMethodField()
  editable_until = serializers.SerializerMethodField()
  is_locked = serializers.SerializerMethodField()
  record_type = serializers.SerializerMethodField()

  class Meta:
    model = PaymentRecord
    fields = [
      'id',
      'payment_record_id',
      'client',
      'client_name',
      'request_reference',
      'original_amount',
      'original_currency',
      'reporting_amount',
      'reporting_currency',
      'exchange_rate_reference',
      'exchange_rate_source',
      'payment_method',
      'payment_method_label',
      'transaction_reference',
      'received_date',
      'status',
      'client_visibility',
      'internal_note',
      'client_note',
      'verified_at',
      'created_at',
      'updated_at',
      'editable_until',
      'is_locked',
      'record_type',
    ]
    read_only_fields = [
      'id', 'payment_record_id', 'client', 'client_name', 'request_reference',
      'payment_method_label', 'verified_at', 'created_at', 'updated_at',
    ]

  def get_client_name(self, obj):
    return f'{obj.client.first_name} {obj.client.last_name}'.strip() or obj.client.username

  def get_payment_method_label(self, obj):
    return obj.payment_method.display_label if obj.payment_method else ''

  def validate_payment_method(self, value):
    if value is None:
      return value
    request = self.context.get('request')
    professional = getattr(request, 'user', None)
    if professional is None or value.professional_id != professional.id:
      raise serializers.ValidationError('Choose a payment method that belongs to your own account.')
    return value

  def get_request_reference(self, obj):
    return obj.payment_request.request_id if obj.payment_request else ''

  def get_editable_until(self, obj):
    return (obj.verified_at or obj.created_at) + timedelta(days=14)

  def get_is_locked(self, obj):
    return timezone.now() > self.get_editable_until(obj)

  def get_record_type(self, obj):
    return 'acknowledged_payment' if obj.source_proof_id else 'manual_log'

  def validate_original_amount(self, value):
    if value <= 0:
      raise serializers.ValidationError('Amount must be greater than zero.')
    return value

  def validate_reporting_amount(self, value):
    if value <= 0:
      raise serializers.ValidationError('Reporting amount must be greater than zero.')
    return value

  def validate_original_currency(self, value):
    code = value.strip().upper()
    if code not in ISO_4217_CODES:
      raise serializers.ValidationError('Choose a supported ISO currency code.')
    return code

  def validate_reporting_currency(self, value):
    code = value.strip().upper()
    if code not in ISO_4217_CODES:
      raise serializers.ValidationError('Choose a supported ISO currency code.')
    return code

  def validate_received_date(self, value):
    from django.utils import timezone as dj_timezone
    if value > dj_timezone.now().date():
      raise serializers.ValidationError('Received date cannot be in the future.')
    return value


class ClientPaymentRecordSerializer(serializers.ModelSerializer):
  """Client-facing record projection - internal notes are never included."""

  payment_method_label = serializers.SerializerMethodField()
  request_reference = serializers.SerializerMethodField()

  class Meta:
    model = PaymentRecord
    fields = [
      'payment_record_id',
      'request_reference',
      'original_amount',
      'original_currency',
      'payment_method_label',
      'transaction_reference',
      'received_date',
      'status',
      'client_note',
    ]
    read_only_fields = fields

  def get_payment_method_label(self, obj):
    return obj.payment_method.display_label if obj.payment_method else ''

  def get_request_reference(self, obj):
    return obj.payment_request.request_id if obj.payment_request else ''


class PaymentConfirmationSerializer(serializers.Serializer):
  """Read-only 'Payment Confirmation' document - explicitly NOT a bank or
  provider receipt. Denormalizes everything needed to render it standalone,
  for both the professional's and the client's view of the same record."""

  payment_record_id = serializers.CharField()
  request_reference = serializers.CharField()
  professional_name = serializers.CharField()
  client_name = serializers.CharField()
  amount_recorded = serializers.DecimalField(max_digits=12, decimal_places=2, source='original_amount')
  original_currency = serializers.CharField()
  reporting_amount = serializers.DecimalField(max_digits=12, decimal_places=2)
  reporting_currency = serializers.CharField()
  payment_method_label = serializers.CharField()
  transaction_reference = serializers.CharField()
  received_date = serializers.DateField()
  confirmed_date = serializers.DateTimeField(source='verified_at')
  status = serializers.CharField()
  professional_note = serializers.CharField(source='client_note')
