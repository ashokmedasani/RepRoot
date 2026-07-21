from django.conf import settings
from django.db import models, transaction
from django.utils import timezone
import uuid


UNIVERSAL_CORE_FIELDS = [
  {
    'label': 'First Name',
    'field_type': 'short_text',
    'required': True,
    'placeholder': '',
    'help_text': '',
    'is_core': True,
    'key': 'first_name',
  },
  {
    'label': 'Last Name',
    'field_type': 'short_text',
    'required': True,
    'placeholder': '',
    'help_text': '',
    'is_core': True,
    'key': 'last_name',
  },
  {
    'label': 'Email Address',
    'field_type': 'email',
    'required': True,
    'placeholder': '',
    'help_text': '',
    'is_core': True,
    'key': 'email',
  },
]


# Universal client creation form template.
# Every professional group is seeded with these personal-information fields so a
# client creation form always exists (it is mandatory before a lead can be
# converted into a client). Professionals can customise, reorder, or remove any of
# these afterwards - they are a starting point, not fixed like the core fields.
UNIVERSAL_CLIENT_FORM_FIELDS = [
  {
    'key': 'phone_number',
    'label': 'Phone Number',
    'field_type': 'phone',
    'required': True,
    'placeholder': 'Mobile number',
    'help_text': 'Best contact number for the client.',
    'options': [],
    'is_core': False,
  },
  {
    'key': 'primary_goal',
    'label': 'Primary Goal',
    'field_type': 'dropdown',
    'required': True,
    'placeholder': 'Select primary goal',
    'help_text': 'Capture the client goal before assigning a program.',
    'options': ['Weight Loss', 'Muscle Gain', 'Strength', 'General Fitness', 'Mobility', 'Sports Performance'],
    'is_core': False,
  },
  {
    'key': 'training_experience',
    'label': 'Training Experience',
    'field_type': 'dropdown',
    'required': False,
    'placeholder': 'Select experience level',
    'help_text': 'Beginner, intermediate, or advanced training history.',
    'options': ['Beginner', 'Intermediate', 'Advanced'],
    'is_core': False,
  },
  {
    'key': 'medical_conditions',
    'label': 'Medical Conditions or Injuries',
    'field_type': 'long_text',
    'required': False,
    'placeholder': 'List any medical conditions or past injuries',
    'help_text': 'Important health context before training begins.',
    'options': [],
    'is_core': False,
  },
  {
    'key': 'preferred_training_mode',
    'label': 'Preferred Training Mode',
    'field_type': 'dropdown',
    'required': False,
    'placeholder': 'Select mode',
    'help_text': 'Online, in person, or hybrid coaching preference.',
    'options': ['Online', 'In Person', 'Hybrid'],
    'is_core': False,
  },
]


def default_client_registration_fields():
  """Core fields plus the universal personal-information template (fresh copies)."""
  fields = [field.copy() for field in UNIVERSAL_CORE_FIELDS]
  fields += [field.copy() for field in UNIVERSAL_CLIENT_FORM_FIELDS]
  return fields


def generate_client_reference_id():
  """Generate a compact internal reference for every client onboarding path."""
  return f'CL-{uuid.uuid4().hex[:10].upper()}'


def generate_professional_internal_reference():
  """Generate an immutable, support-safe identifier for professional audit history."""
  return f'TRN-{uuid.uuid4().hex[:10].upper()}'


class ProfessionalProfile(models.Model):
  # Legacy plan choices (for backward compatibility during migration)
  PLAN_STARTER = 'starter'
  PLAN_PREMIUM = 'premium'

  # New 3-tier plan choices
  PLAN_STARTER_FREE = 'starter_free'
  PLAN_PRO = 'pro'
  PLAN_PREMIUM_UNLIMITED = 'premium_unlimited'

  PLAN_CHOICES = [
    (PLAN_STARTER_FREE, 'Starter Free'),
    (PLAN_PRO, 'Pro'),
    (PLAN_PREMIUM_UNLIMITED, 'Premium Unlimited'),
    # Keep legacy for backward compatibility during migration
    (PLAN_STARTER, 'Starter (Legacy)'),
    (PLAN_PREMIUM, 'Premium (Legacy)'),
  ]

  user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='professional_profile')
  internal_reference_code = models.CharField(
    max_length=24,
    unique=True,
    default=generate_professional_internal_reference,
    editable=False,
    db_index=True,
  )
  professional_id = models.CharField(max_length=32, unique=True, null=True, blank=True, db_index=True)
  plan_tier = models.CharField(max_length=20, choices=PLAN_CHOICES, default=PLAN_STARTER_FREE, db_index=True)
  stripe_customer_id = models.CharField(max_length=64, blank=True, db_index=True)
  stripe_subscription_id = models.CharField(max_length=64, blank=True, db_index=True)
  plan_renews_at = models.DateTimeField(null=True, blank=True)

  # NEW: Account lifecycle fields
  is_locked = models.BooleanField(default=False, db_index=True)
  locked_at = models.DateTimeField(null=True, blank=True)
  lock_reason = models.CharField(max_length=100, blank=True, help_text="'overage' or 'downgrade_grace_expired'")
  downgraded_at = models.DateTimeField(null=True, blank=True)
  grace_period_ends_at = models.DateTimeField(null=True, blank=True, db_index=True)
  usage_warning_acknowledged_at = models.DateTimeField(null=True, blank=True)
  last_overage_notification_sent_at = models.DateTimeField(null=True, blank=True)
  profile_setup_completed = models.BooleanField(default=False)
  profile_photo = models.FileField(upload_to='professional-profiles/photos/', blank=True)
  middle_name = models.CharField(max_length=150, blank=True)
  phone = models.CharField(max_length=40, blank=True)
  gender = models.CharField(max_length=40, blank=True)
  state = models.CharField(max_length=80, blank=True)
  country = models.CharField(max_length=80, blank=True)
  birth_month = models.PositiveSmallIntegerField(null=True, blank=True)
  birth_year = models.PositiveSmallIntegerField(null=True, blank=True)
  professional_headline = models.CharField(max_length=180, blank=True)
  about_me = models.TextField(blank=True)
  professional_type = models.CharField(max_length=120, blank=True)
  years_experience = models.PositiveSmallIntegerField(null=True, blank=True)
  specializations = models.TextField(blank=True)
  training_style = models.TextField(blank=True)
  languages_known = models.CharField(max_length=240, blank=True)
  certification_name = models.CharField(max_length=180, blank=True)
  certification_issued_by = models.CharField(max_length=180, blank=True)
  certification_year = models.PositiveSmallIntegerField(null=True, blank=True)
  certification_file = models.FileField(upload_to='professional-profiles/certifications/', blank=True)
  transformation_photo = models.FileField(upload_to='professional-profiles/transformations/', blank=True)
  training_photo = models.FileField(upload_to='professional-profiles/training/', blank=True)
  intro_video_url = models.URLField(blank=True)
  instagram_url = models.URLField(blank=True)
  youtube_url = models.URLField(blank=True)
  website_url = models.URLField(blank=True)
  profile_images = models.JSONField(default=list, blank=True)
  profile_links = models.JSONField(default=list, blank=True)
  profile_visibility = models.JSONField(default=dict, blank=True)
  terms_accepted = models.BooleanField(default=False)
  privacy_policy_accepted = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'professional_profiles'

  def __str__(self) -> str:
    return f'{self.user.get_full_name()} ({self.user.username})'


class ProfessionalLeadForm(models.Model):
  professional = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='lead_form')
  public_slug = models.SlugField(max_length=64, unique=True)
  title = models.CharField(max_length=160, default='Professional Lead Form')
  fields = models.JSONField(default=list)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'professional_lead_forms'

  def __str__(self) -> str:
    return f'{self.professional.username} lead form'


class ProfessionalGroup(models.Model):
  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='professional_groups')
  name = models.CharField(max_length=120)
  description = models.TextField(blank=True)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'professional_groups'
    ordering = ['created_at']
    unique_together = ('professional', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.professional.username})'


class ClientRegistrationForm(models.Model):
  group = models.OneToOneField(ProfessionalGroup, on_delete=models.CASCADE, related_name='client_registration_form')
  public_slug = models.SlugField(max_length=64, unique=True, null=True, blank=True, db_index=True)
  fields = models.JSONField(default=list)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'client_registration_forms'

  def __str__(self) -> str:
    return f'{self.group.name} client registration form'

  def save(self, *args, **kwargs):
    if not self.public_slug:
      self.public_slug = f'group-{self.group_id}-{uuid.uuid4().hex[:12]}'
    return super().save(*args, **kwargs)


class LeadSubmission(models.Model):
  STATUS_PENDING = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_DELETED = 'deleted'

  STATUS_CHOICES = [
    (STATUS_PENDING, 'Pending'),
    (STATUS_APPROVED, 'Approved / Converted'),
    (STATUS_DELETED, 'Deleted'),
  ]

  lead_form = models.ForeignKey(ProfessionalLeadForm, on_delete=models.CASCADE, related_name='submissions')
  first_name = models.CharField(max_length=150)
  last_name = models.CharField(max_length=150)
  email = models.EmailField()
  reference_id = models.CharField(max_length=32, unique=True)
  answers = models.JSONField(default=dict)
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
  is_active = models.BooleanField(default=True, db_index=True)
  submitted_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)
  converted_at = models.DateTimeField(null=True, blank=True)
  deleted_at = models.DateTimeField(null=True, blank=True)

  class Meta:
    db_table = 'lead_submissions'
    ordering = ['-submitted_at']

  def __str__(self) -> str:
    return f'{self.reference_id} - {self.email}'


class GroupRegistrationSubmission(models.Model):
  STATUS_PENDING = 'pending'
  STATUS_CONVERTED = 'converted'
  STATUS_DELETED = 'deleted'

  STATUS_CHOICES = [
    (STATUS_PENDING, 'Pending'),
    (STATUS_CONVERTED, 'Converted'),
    (STATUS_DELETED, 'Deleted'),
  ]

  group = models.ForeignKey(ProfessionalGroup, on_delete=models.CASCADE, related_name='registration_submissions')
  first_name = models.CharField(max_length=150)
  last_name = models.CharField(max_length=150)
  email = models.EmailField()
  reference_id = models.CharField(max_length=32, unique=True, default=generate_client_reference_id)
  answers = models.JSONField(default=dict)
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
  submitted_at = models.DateTimeField(auto_now_add=True)
  converted_at = models.DateTimeField(null=True, blank=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'group_registration_submissions'
    ordering = ['-submitted_at']

  def __str__(self) -> str:
    return f'{self.reference_id} - {self.group.name}'


class ClientAccess(models.Model):
  ONBOARDING_PUBLIC_LEAD = 'public_lead'
  ONBOARDING_MANUAL = 'manual'
  ONBOARDING_GROUP_REGISTRATION = 'group_registration'
  ONBOARDING_CHOICES = [
    (ONBOARDING_PUBLIC_LEAD, 'Public lead'),
    (ONBOARDING_MANUAL, 'Manual'),
    (ONBOARDING_GROUP_REGISTRATION, 'Group registration'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='client_access_records')
  group = models.ForeignKey(ProfessionalGroup, on_delete=models.PROTECT, related_name='client_access_records')
  lead_submission = models.OneToOneField(
    LeadSubmission,
    on_delete=models.PROTECT,
    related_name='client_access',
    null=True,
    blank=True,
  )
  registration_submission = models.OneToOneField(
    GroupRegistrationSubmission,
    on_delete=models.PROTECT,
    related_name='client_access',
    null=True,
    blank=True,
  )
  reference_id = models.CharField(max_length=32, unique=True, default=generate_client_reference_id)
  onboarding_method = models.CharField(max_length=24, choices=ONBOARDING_CHOICES, default=ONBOARDING_PUBLIC_LEAD)
  first_name = models.CharField(max_length=150)
  last_name = models.CharField(max_length=150)
  email = models.EmailField()
  username = models.CharField(max_length=150)
  temporary_password = models.CharField(max_length=128)
  photo = models.TextField(blank=True)
  registration_answers = models.JSONField(default=dict)
  additional_info = models.JSONField(default=list)
  additional_info_shared = models.BooleanField(default=False)
  professional_notes = models.TextField(blank=True)
  professional_notes_updated_at = models.DateTimeField(null=True, blank=True)
  must_change_password = models.BooleanField(default=True)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'client_access'
    unique_together = [('professional', 'email'), ('professional', 'username')]
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.username} for {self.professional.username}'


class ClientDetailChangeRequest(models.Model):
  TYPE_PROFILE_EDIT = 'profile_edit'
  TYPE_ACCOUNT_DELETION = 'account_deletion'
  TYPE_CHOICES = [
    (TYPE_PROFILE_EDIT, 'Profile edit'),
    (TYPE_ACCOUNT_DELETION, 'Account deletion'),
  ]

  STATUS_PENDING = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_REJECTED = 'rejected'
  STATUS_CANCELLED = 'cancelled'
  STATUS_ARCHIVED = 'archived'

  STATUS_CHOICES = [
    (STATUS_PENDING, 'Pending'),
    (STATUS_APPROVED, 'Approved'),
    (STATUS_REJECTED, 'Rejected'),
    (STATUS_CANCELLED, 'Cancelled'),
    (STATUS_ARCHIVED, 'Archived'),
  ]

  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='detail_change_requests')
  request_type = models.CharField(max_length=24, choices=TYPE_CHOICES, default=TYPE_PROFILE_EDIT, db_index=True)
  proposed_answers = models.JSONField(default=dict)
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
  client_note = models.TextField(blank=True)
  professional_note = models.TextField(blank=True)
  created_at = models.DateTimeField(auto_now_add=True)
  reviewed_at = models.DateTimeField(null=True, blank=True)
  archived_at = models.DateTimeField(null=True, blank=True)

  class Meta:
    db_table = 'client_detail_change_requests'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.client.username} detail change ({self.status})'


def support_incident_reference():
  return f'INC-{uuid.uuid4().hex[:10].upper()}'


class SupportIncident(models.Model):
  ROLE_PROFESSIONAL = 'professional'
  ROLE_CLIENT = 'client'
  ROLE_CHOICES = [(ROLE_PROFESSIONAL, 'Professional'), (ROLE_CLIENT, 'Client')]

  CATEGORY_FEEDBACK = 'feedback'
  CATEGORY_BUG = 'bug_report'
  CATEGORY_ACCOUNT = 'account_issue'
  CATEGORY_PAYMENT = 'payment_subscription'
  CATEGORY_FEATURE = 'feature_request'
  CATEGORY_TECHNICAL = 'technical_problem'
  CATEGORY_OTHER = 'other'
  CATEGORY_CHOICES = [
    (CATEGORY_FEEDBACK, 'Feedback'),
    (CATEGORY_BUG, 'Bug report'),
    (CATEGORY_ACCOUNT, 'Account issue'),
    (CATEGORY_PAYMENT, 'Payment or subscription issue'),
    (CATEGORY_FEATURE, 'Feature request'),
    (CATEGORY_TECHNICAL, 'Technical problem'),
    (CATEGORY_OTHER, 'Other issue'),
  ]

  STATUS_SUBMITTED = 'submitted'
  STATUS_OPEN = 'open'
  STATUS_REVIEW = 'under_review'
  STATUS_WAITING = 'waiting_for_user'
  STATUS_RESOLVED = 'resolved'
  STATUS_CLOSED = 'closed'
  STATUS_REOPENED = 'reopened'
  STATUS_CHOICES = [
    (STATUS_SUBMITTED, 'Submitted'),
    (STATUS_OPEN, 'Open'),
    (STATUS_REVIEW, 'Under review'),
    (STATUS_WAITING, 'Waiting for user'),
    (STATUS_RESOLVED, 'Resolved'),
    (STATUS_CLOSED, 'Closed'),
    (STATUS_REOPENED, 'Reopened'),
  ]
  ACTIVE_STATUSES = (STATUS_SUBMITTED, STATUS_OPEN, STATUS_REVIEW, STATUS_WAITING, STATUS_REOPENED)

  PRIORITY_LOW = 'low'
  PRIORITY_NORMAL = 'normal'
  PRIORITY_HIGH = 'high'
  PRIORITY_URGENT = 'urgent'
  PRIORITY_CHOICES = [
    (PRIORITY_LOW, 'Low'),
    (PRIORITY_NORMAL, 'Normal'),
    (PRIORITY_HIGH, 'High'),
    (PRIORITY_URGENT, 'Urgent'),
  ]

  incident_id = models.CharField(max_length=24, unique=True, default=support_incident_reference, editable=False, db_index=True)
  reporter_role = models.CharField(max_length=12, choices=ROLE_CHOICES, db_index=True)
  reporter_professional = models.ForeignKey(
    settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name='support_incidents'
  )
  reporter_client = models.ForeignKey(
    ClientAccess, on_delete=models.CASCADE, null=True, blank=True, related_name='support_incidents'
  )
  reporter_name = models.CharField(max_length=180)
  reporter_email = models.EmailField(blank=True)
  category = models.CharField(max_length=32, choices=CATEGORY_CHOICES, db_index=True)
  subject = models.CharField(max_length=180)
  description = models.TextField()
  page_feature = models.CharField(max_length=180, blank=True)
  platform = models.CharField(max_length=24, default='web')
  app_version = models.CharField(max_length=40, blank=True)
  device_info = models.CharField(max_length=300, blank=True)
  screenshot = models.FileField(upload_to='support-incidents/%Y/%m/', null=True, blank=True)
  priority = models.CharField(max_length=12, choices=PRIORITY_CHOICES, default=PRIORITY_NORMAL, db_index=True)
  status = models.CharField(max_length=24, choices=STATUS_CHOICES, default=STATUS_SUBMITTED, db_index=True)
  assigned_support = models.ForeignKey(
    settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='assigned_support_incidents'
  )
  resolution_note = models.TextField(blank=True)
  closed_at = models.DateTimeField(null=True, blank=True)
  created_at = models.DateTimeField(auto_now_add=True, db_index=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'support_incidents'
    ordering = ['-updated_at']
    indexes = [models.Index(fields=['reporter_role', 'status'], name='support_role_status_idx')]

  def __str__(self) -> str:
    return f'{self.incident_id} · {self.subject}'


class SupportIncidentMessage(models.Model):
  AUTHOR_USER = 'user'
  AUTHOR_SUPPORT = 'support'
  AUTHOR_INTERNAL = 'internal'
  AUTHOR_CHOICES = [
    (AUTHOR_USER, 'Reporter'),
    (AUTHOR_SUPPORT, 'Support'),
    (AUTHOR_INTERNAL, 'Internal note'),
  ]

  incident = models.ForeignKey(SupportIncident, on_delete=models.CASCADE, related_name='messages')
  author_type = models.CharField(max_length=12, choices=AUTHOR_CHOICES, db_index=True)
  author_name = models.CharField(max_length=180)
  author_staff = models.ForeignKey(
    settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='support_incident_messages'
  )
  body = models.TextField()
  created_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'support_incident_messages'
    ordering = ['created_at']

  def __str__(self) -> str:
    return f'{self.incident.incident_id} · {self.author_type}'


class ClientReminder(models.Model):
  STATUS_PENDING = 'pending'
  STATUS_DONE = 'done'

  STATUS_CHOICES = [
    (STATUS_PENDING, 'Pending'),
    (STATUS_DONE, 'Done'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='client_reminders')
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='reminders')
  title = models.CharField(max_length=180)
  date = models.DateField()
  time = models.TimeField(null=True, blank=True)
  notes = models.TextField(blank=True)
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING, db_index=True)
  notify_professional = models.BooleanField(default=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'client_reminders'
    ordering = ['date', 'time']

  def __str__(self) -> str:
    return f'{self.title} for {self.client.username} ({self.date})'


class ProgressEntry(models.Model):
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='progress_entries')
  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='progress_entries')
  title = models.CharField(max_length=180)
  date = models.DateField()
  notes = models.TextField(blank=True)
  status = models.CharField(max_length=80, blank=True)
  next_step = models.TextField(blank=True)
  created_by = models.CharField(max_length=180, blank=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'progress_entries'
    ordering = ['-date', '-created_at']

  def __str__(self) -> str:
    return f'{self.title} - {self.client.username} ({self.date})'


class ReferenceCategory(models.Model):
  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='reference_categories')
  name = models.CharField(max_length=120)
  description = models.TextField(blank=True)
  subcategories = models.JSONField(default=list)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'reference_categories'
    ordering = ['created_at']
    unique_together = ('professional', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.professional.username})'


class ProfessionalReference(models.Model):
  TYPE_VIDEO_LINK = 'video_link'
  TYPE_PDF = 'pdf'
  TYPE_IMAGE = 'image'
  TYPE_TEXT_NOTE = 'text_note'

  REFERENCE_TYPE_CHOICES = [
    (TYPE_VIDEO_LINK, 'Video Link'),
    (TYPE_PDF, 'PDF Link'),
    (TYPE_TEXT_NOTE, 'Text'),
    (TYPE_IMAGE, 'Image'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='professional_references')
  category = models.ForeignKey(ReferenceCategory, on_delete=models.PROTECT, related_name='references')
  subcategory = models.CharField(max_length=120, blank=True)
  title = models.CharField(max_length=180)
  reference_type = models.CharField(max_length=20, choices=REFERENCE_TYPE_CHOICES)
  description = models.TextField(blank=True)
  link = models.URLField(blank=True)
  file = models.FileField(upload_to='professional-references/', blank=True)
  tags = models.JSONField(default=list)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'professional_references'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.title} ({self.professional.username})'


class TrackingTemplate(models.Model):
  CADENCE_DAILY = 'daily'
  CADENCE_WEEKLY = 'weekly'
  CADENCE_MONTHLY = 'monthly'

  CADENCE_CHOICES = [
    (CADENCE_DAILY, 'Daily'),
    (CADENCE_WEEKLY, 'Weekly'),
    (CADENCE_MONTHLY, 'Monthly'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='tracking_templates')
  name = models.CharField(max_length=120)
  purpose = models.TextField(blank=True)
  cadence = models.CharField(max_length=10, choices=CADENCE_CHOICES, default=CADENCE_DAILY)
  accent = models.CharField(max_length=20, blank=True, default='green')
  fields = models.JSONField(default=list)
  standard_key = models.CharField(max_length=40, blank=True)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'tracking_templates'
    ordering = ['created_at']
    unique_together = ('professional', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.professional.username})'


class TemplateAssignment(models.Model):
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='template_assignments')
  template = models.ForeignKey(TrackingTemplate, on_delete=models.CASCADE, related_name='assignments')
  references = models.ManyToManyField(ProfessionalReference, blank=True, related_name='template_assignments')
  assigned_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'template_assignments'
    ordering = ['assigned_at']
    unique_together = ('client', 'template')

  def __str__(self) -> str:
    return f'{self.template.name} -> {self.client.username}'


class TrackingEntry(models.Model):
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='tracking_entries')
  template = models.ForeignKey(TrackingTemplate, on_delete=models.SET_NULL, null=True, blank=True, related_name='entries')
  template_name = models.CharField(max_length=120)
  entry_date = models.DateField()
  entry_time = models.TimeField(null=True, blank=True)
  answers = models.JSONField(default=dict)
  note = models.TextField(blank=True)
  edited_by_professional = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'tracking_entries'
    # A client may log the same template multiple times per day (each with its
    # own editable date/time), so there is no per-day uniqueness constraint.
    ordering = ['-entry_date', '-entry_time', '-created_at']

  def __str__(self) -> str:
    return f'{self.client.username} {self.template_name} {self.entry_date}'


class ChatMessage(models.Model):
  SENDER_PROFESSIONAL = 'professional'
  SENDER_CLIENT = 'client'

  SENDER_CHOICES = [
    (SENDER_PROFESSIONAL, 'Professional'),
    (SENDER_CLIENT, 'Client'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='chat_messages')
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='chat_messages')
  sender = models.CharField(max_length=20, choices=SENDER_CHOICES)
  text = models.TextField(blank=True)
  image = models.FileField(upload_to='client-chat/images/%Y/%m/', blank=True)
  is_read = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'chat_messages'
    ordering = ['created_at']
    indexes = [models.Index(fields=['client', 'created_at'])]

  def __str__(self) -> str:
    return f'{self.sender} -> {self.client.username} at {self.created_at:%Y-%m-%d %H:%M}'


class ClientAuthToken(models.Model):
  client = models.OneToOneField(ClientAccess, on_delete=models.CASCADE, related_name='auth_token')
  key = models.CharField(max_length=40, unique=True)
  created_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'client_auth_tokens'

  def __str__(self) -> str:
    return f'Token for {self.client.username}'


class RecycledProfessionalAccount(models.Model):
  original_user_id = models.PositiveIntegerField(db_index=True)
  email = models.EmailField(db_index=True)
  username = models.CharField(max_length=150, db_index=True)
  first_name = models.CharField(max_length=150, blank=True)
  last_name = models.CharField(max_length=150, blank=True)
  account_snapshot = models.JSONField()
  deleted_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'recycled_professional_accounts'
    ordering = ['-deleted_at']

  def __str__(self) -> str:
    return f'{self.email} recycled at {self.deleted_at:%Y-%m-%d %H:%M}'


# ---------------------------------------------------------------------------
# Client Payments
#
# Money professionals collect FROM their clients. Fully separate from RepRoot
# Studio Billing (professionals paying RepRoot for their subscription tier).
# For manual payment methods RepRoot never receives, holds, or transfers the
# money - these models only track what the professional and client report.
# ---------------------------------------------------------------------------


def generate_payment_record_id():
  return f'PMT-{uuid.uuid4().hex[:10].upper()}'


class PaymentSequence(models.Model):
  """Year-scoped counter backing PAY-RRS request ids. Locked with
  select_for_update so concurrent request creation can't collide."""

  year = models.PositiveIntegerField(unique=True)
  last_number = models.PositiveIntegerField(default=0)

  class Meta:
    db_table = 'payment_sequences'

  @classmethod
  def next_request_id(cls):
    with transaction.atomic():
      year = timezone.now().year
      sequence, _ = cls.objects.select_for_update().get_or_create(year=year)
      sequence.last_number += 1
      sequence.save(update_fields=['last_number'])
      return f'PAY-RRS-{year}-{sequence.last_number:06d}'


class ProfessionalPaymentSettings(models.Model):
  VISIBILITY_PRIVATE = 'private'
  VISIBILITY_VISIBLE = 'visible'
  VISIBILITY_CHOICES = [(VISIBILITY_PRIVATE, 'Private'), (VISIBILITY_VISIBLE, 'Visible to client')]

  professional = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='payment_settings')
  # Master opt-in: a professional who does not want to track money at all can
  # turn this off, which hides every payments surface. Payments are never forced.
  payment_tracking_enabled = models.BooleanField(default=True)
  reporting_currency = models.CharField(max_length=3, default='USD')
  client_payment_history_enabled = models.BooleanField(default=True)
  default_payment_visibility = models.CharField(max_length=12, choices=VISIBILITY_CHOICES, default=VISIBILITY_PRIVATE)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'professional_payment_settings'

  def __str__(self) -> str:
    return f'Payment settings for {self.professional.username} ({self.reporting_currency})'


class ManualPaymentProfile(models.Model):
  CATEGORY_CHOICES = [
    ('upi', 'UPI'),
    ('google_pay', 'Google Pay'),
    ('phonepe', 'PhonePe'),
    ('paytm', 'Paytm'),
    ('bank_transfer', 'Bank Transfer'),
    ('zelle', 'Zelle'),
    ('venmo', 'Venmo'),
    ('cash_app', 'Cash App'),
    ('paypal_manual', 'PayPal (manual transfer)'),
    ('cash', 'Cash'),
    ('other', 'Other'),
  ]
  STATUS_ACTIVE = 'active'
  STATUS_INACTIVE = 'inactive'
  STATUS_CHOICES = [(STATUS_ACTIVE, 'Active'), (STATUS_INACTIVE, 'Inactive')]
  MAX_ACTIVE_PROFILES = 5

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='manual_payment_profiles')
  name = models.CharField(max_length=120)
  category = models.CharField(max_length=20, choices=CATEGORY_CHOICES, db_index=True)
  display_label = models.CharField(max_length=120)
  supported_currencies = models.JSONField(default=list, blank=True)
  country = models.CharField(max_length=80, blank=True)
  # JSON blobs keep category-specific shapes flexible without per-category
  # migrations. private_fields never leaves professional-facing serializers.
  private_fields = models.JSONField(default=dict, blank=True)
  client_visible_fields = models.JSONField(default=dict, blank=True)
  qr_code = models.FileField(upload_to='payments/qr-codes/%Y/%m/', null=True, blank=True)
  internal_notes = models.TextField(blank=True)
  client_instructions = models.TextField(blank=True)
  status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=STATUS_ACTIVE, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'manual_payment_profiles'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.display_label} ({self.professional.username})'


class IntegratedPaymentAccount(models.Model):
  """Provider-connection shell. Deliberately has no field capable of holding
  a secret - only opaque provider-issued references are ever stored."""

  PROVIDER_CHOICES = [('stripe', 'Stripe'), ('paypal', 'PayPal'), ('razorpay', 'Razorpay')]
  CONNECTION_CHOICES = [
    ('not_connected', 'Not Connected'),
    ('setup_required', 'Setup Required'),
    ('verification_pending', 'Verification Pending'),
    ('connected', 'Connected'),
    ('restricted', 'Restricted'),
    ('disconnected', 'Disconnected'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='integrated_payment_accounts')
  provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES, db_index=True)
  provider_account_reference = models.CharField(max_length=120, blank=True)
  connection_status = models.CharField(max_length=20, choices=CONNECTION_CHOICES, default='not_connected', db_index=True)
  verification_status = models.CharField(max_length=40, blank=True)
  account_type = models.CharField(max_length=40, blank=True)
  country = models.CharField(max_length=80, blank=True)
  supported_currencies = models.JSONField(default=list, blank=True)
  last_connection_check = models.DateTimeField(null=True, blank=True)
  is_active = models.BooleanField(default=False, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'integrated_payment_accounts'
    constraints = [models.UniqueConstraint(fields=['professional', 'provider'], name='one_account_per_provider')]

  def __str__(self) -> str:
    return f'{self.provider} for {self.professional.username} ({self.connection_status})'


class ClientPaymentMethodAccess(models.Model):
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='payment_method_access')
  payment_profile = models.ForeignKey(ManualPaymentProfile, on_delete=models.CASCADE, related_name='client_access_grants')
  is_visible = models.BooleanField(default=True, db_index=True)
  enabled_at = models.DateTimeField(auto_now_add=True)
  disabled_at = models.DateTimeField(null=True, blank=True)

  class Meta:
    db_table = 'client_payment_method_access'
    constraints = [models.UniqueConstraint(fields=['client', 'payment_profile'], name='one_grant_per_client_method')]

  def __str__(self) -> str:
    return f'{self.payment_profile.display_label} -> {self.client.username}'


class PaymentPlan(models.Model):
  """Reusable payment-plan template (e.g. a monthly coaching package).

  Schema groundwork only for now: future plan features (auto-generated
  recurring requests, client assignment) attach here so nothing about
  PaymentRequest needs restructuring later."""

  CYCLE_CHOICES = [
    ('one_time', 'One time'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
    ('quarterly', 'Quarterly'),
    ('custom', 'Custom'),
  ]
  STATUS_CHOICES = [('active', 'Active'), ('inactive', 'Inactive'), ('archived', 'Archived')]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='payment_plans')
  name = models.CharField(max_length=120)
  description = models.TextField(blank=True)
  amount = models.DecimalField(max_digits=12, decimal_places=2)
  currency = models.CharField(max_length=3)
  billing_cycle = models.CharField(max_length=12, choices=CYCLE_CHOICES, default='monthly')
  installment_count = models.PositiveIntegerField(null=True, blank=True)
  status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='active', db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'payment_plans'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.name} ({self.amount} {self.currency} / {self.billing_cycle})'


class PaymentRequest(models.Model):
  TYPE_CHOICES = [('manual', 'Manual'), ('integrated', 'Integrated'), ('both', 'Both')]

  STATUS_DRAFT = 'draft'
  STATUS_SENT = 'sent'
  STATUS_VIEWED = 'viewed'
  STATUS_PROOF_SUBMITTED = 'proof_submitted'
  STATUS_UNDER_REVIEW = 'under_review'
  STATUS_COMPLETED = 'completed'
  STATUS_PARTIALLY_PAID = 'partially_paid'
  STATUS_REJECTED = 'rejected'
  STATUS_CANCELLED = 'cancelled'
  STATUS_OVERDUE = 'overdue'
  STATUS_REFUNDED = 'refunded'
  STATUS_CHOICES = [
    (STATUS_DRAFT, 'Draft'),
    (STATUS_SENT, 'Sent'),
    (STATUS_VIEWED, 'Viewed'),
    (STATUS_PROOF_SUBMITTED, 'Proof Submitted'),
    (STATUS_UNDER_REVIEW, 'Under Review'),
    (STATUS_COMPLETED, 'Completed'),
    (STATUS_PARTIALLY_PAID, 'Partially Paid'),
    (STATUS_REJECTED, 'Rejected'),
    (STATUS_CANCELLED, 'Cancelled'),
    (STATUS_OVERDUE, 'Overdue'),
    (STATUS_REFUNDED, 'Refunded'),
  ]
  OPEN_STATUSES = (STATUS_SENT, STATUS_VIEWED, STATUS_PROOF_SUBMITTED, STATUS_UNDER_REVIEW, STATUS_OVERDUE, STATUS_PARTIALLY_PAID)

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='payment_requests')
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='payment_requests')
  payment_plan = models.ForeignKey(PaymentPlan, on_delete=models.SET_NULL, null=True, blank=True, related_name='requests')
  request_id = models.CharField(max_length=32, unique=True, editable=False, db_index=True)
  title = models.CharField(max_length=180)
  description = models.TextField(blank=True)
  requested_amount = models.DecimalField(max_digits=12, decimal_places=2)
  requested_currency = models.CharField(max_length=3)
  due_date = models.DateField(null=True, blank=True, db_index=True)
  payment_type = models.CharField(max_length=12, choices=TYPE_CHOICES, default='manual')
  status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_DRAFT, db_index=True)
  client_visibility = models.CharField(
    max_length=12,
    choices=ProfessionalPaymentSettings.VISIBILITY_CHOICES,
    default=ProfessionalPaymentSettings.VISIBILITY_VISIBLE,
  )
  notes = models.TextField(blank=True)
  created_at = models.DateTimeField(auto_now_add=True)
  sent_at = models.DateTimeField(null=True, blank=True)
  viewed_at = models.DateTimeField(null=True, blank=True)
  completed_at = models.DateTimeField(null=True, blank=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'payment_requests'
    ordering = ['-created_at']
    indexes = [
      models.Index(fields=['professional', 'status'], name='pay_req_prof_status_idx'),
      models.Index(fields=['client', 'status'], name='pay_req_client_status_idx'),
    ]

  def save(self, *args, **kwargs):
    if not self.request_id:
      self.request_id = PaymentSequence.next_request_id()
    return super().save(*args, **kwargs)

  def __str__(self) -> str:
    return f'{self.request_id} ({self.status})'


class PaymentRequestAllowedMethod(models.Model):
  payment_request = models.ForeignKey(PaymentRequest, on_delete=models.CASCADE, related_name='allowed_methods')
  manual_payment_profile = models.ForeignKey(ManualPaymentProfile, on_delete=models.CASCADE, null=True, blank=True, related_name='allowed_on_requests')
  integrated_payment_account = models.ForeignKey(IntegratedPaymentAccount, on_delete=models.CASCADE, null=True, blank=True, related_name='allowed_on_requests')

  class Meta:
    db_table = 'payment_request_allowed_methods'
    constraints = [
      models.CheckConstraint(
        check=(
          models.Q(manual_payment_profile__isnull=False, integrated_payment_account__isnull=True)
          | models.Q(manual_payment_profile__isnull=True, integrated_payment_account__isnull=False)
        ),
        name='payment_allowed_method_one_target',
      )
    ]


class PaymentProof(models.Model):
  STATUS_SUBMITTED = 'submitted'
  STATUS_UNDER_REVIEW = 'under_review'
  STATUS_ACCEPTED = 'accepted'
  STATUS_REJECTED = 'rejected'
  STATUS_CHOICES = [
    (STATUS_SUBMITTED, 'Submitted'),
    (STATUS_UNDER_REVIEW, 'Under Review'),
    (STATUS_ACCEPTED, 'Accepted'),
    (STATUS_REJECTED, 'Rejected'),
  ]

  payment_request = models.ForeignKey(PaymentRequest, on_delete=models.CASCADE, related_name='proofs')
  submitted_by = models.CharField(max_length=150, blank=True)
  transaction_reference = models.CharField(max_length=120, blank=True)
  reported_amount = models.DecimalField(max_digits=12, decimal_places=2)
  reported_currency = models.CharField(max_length=3)
  reported_payment_date = models.DateField()
  payment_method = models.ForeignKey(ManualPaymentProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='proofs')
  proof_file = models.FileField(upload_to='payments/proofs/%Y/%m/', null=True, blank=True)
  note = models.TextField(blank=True)
  confirmed_accurate = models.BooleanField(default=False)
  status = models.CharField(max_length=14, choices=STATUS_CHOICES, default=STATUS_SUBMITTED, db_index=True)
  review_note = models.TextField(blank=True)
  submitted_at = models.DateTimeField(auto_now_add=True)
  reviewed_at = models.DateTimeField(null=True, blank=True)

  class Meta:
    db_table = 'payment_proofs'
    ordering = ['-submitted_at']

  def __str__(self) -> str:
    return f'Proof for {self.payment_request.request_id} ({self.status})'


class PaymentRecord(models.Model):
  STATUS_COMPLETED = 'completed'
  STATUS_PARTIALLY_PAID = 'partially_paid'
  STATUS_REFUNDED = 'refunded'
  STATUS_CHOICES = [
    (STATUS_COMPLETED, 'Completed'),
    (STATUS_PARTIALLY_PAID, 'Partially Paid'),
    (STATUS_REFUNDED, 'Refunded'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='payment_records')
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='payment_records')
  payment_request = models.ForeignKey(PaymentRequest, on_delete=models.SET_NULL, null=True, blank=True, related_name='records')
  payment_record_id = models.CharField(max_length=32, unique=True, default=generate_payment_record_id, editable=False, db_index=True)
  original_amount = models.DecimalField(max_digits=12, decimal_places=2)
  original_currency = models.CharField(max_length=3)
  reporting_amount = models.DecimalField(max_digits=12, decimal_places=2)
  reporting_currency = models.CharField(max_length=3)
  exchange_rate_reference = models.DecimalField(max_digits=14, decimal_places=6, null=True, blank=True)
  exchange_rate_source = models.CharField(max_length=40, blank=True, default='manual')
  payment_method = models.ForeignKey(ManualPaymentProfile, on_delete=models.SET_NULL, null=True, blank=True, related_name='records')
  transaction_reference = models.CharField(max_length=120, blank=True)
  received_date = models.DateField(db_index=True)
  status = models.CharField(max_length=14, choices=STATUS_CHOICES, default=STATUS_COMPLETED, db_index=True)
  client_visibility = models.CharField(
    max_length=12,
    choices=ProfessionalPaymentSettings.VISIBILITY_CHOICES,
    default=ProfessionalPaymentSettings.VISIBILITY_VISIBLE,
  )
  internal_note = models.TextField(blank=True)
  client_note = models.TextField(blank=True)
  proof_file = models.FileField(upload_to='payments/records/%Y/%m/', null=True, blank=True)
  verified_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='verified_payment_records')
  verified_at = models.DateTimeField(null=True, blank=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'payment_records'
    ordering = ['-received_date', '-created_at']
    indexes = [
      models.Index(fields=['professional', 'received_date'], name='pay_rec_prof_date_idx'),
      models.Index(fields=['client', 'status'], name='pay_rec_client_status_idx'),
    ]

  def __str__(self) -> str:
    return f'{self.payment_record_id} ({self.status})'


class PaymentAuditLog(models.Model):
  """Immutable insert-only log of payment actions, mirroring the shape of
  admin_portal.AdminAuditLog but scoped to professional/client activity."""

  ACTION_CHOICES = [
    ('method_created', 'Method created'),
    ('method_updated', 'Method updated'),
    ('method_shared', 'Method shared'),
    ('method_unshared', 'Method unshared'),
    ('request_created', 'Request created'),
    ('request_cancelled', 'Request cancelled'),
    ('proof_submitted', 'Proof submitted'),
    ('proof_rejected', 'Proof rejected'),
    ('info_requested', 'More info requested'),
    ('payment_verified', 'Payment verified'),
    ('payment_recorded', 'Payment recorded'),
    ('payment_edited', 'Payment edited'),
    ('payment_deleted', 'Payment deleted'),
  ]

  professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='payment_audit_logs')
  client = models.ForeignKey(ClientAccess, on_delete=models.SET_NULL, null=True, blank=True, related_name='payment_audit_logs')
  payment_request = models.ForeignKey(PaymentRequest, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
  payment_record = models.ForeignKey(PaymentRecord, on_delete=models.SET_NULL, null=True, blank=True, related_name='audit_logs')
  action = models.CharField(max_length=32, choices=ACTION_CHOICES, db_index=True)
  previous_values = models.JSONField(default=dict, blank=True)
  new_values = models.JSONField(default=dict, blank=True)
  changed_by = models.CharField(max_length=180, blank=True)
  reason = models.TextField(blank=True)
  created_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'payment_audit_logs'
    ordering = ['-created_at']
    indexes = [models.Index(fields=['professional', 'created_at'], name='pay_audit_prof_created_idx')]

  def save(self, *args, **kwargs):
    if self.pk:
      raise ValueError('Payment audit logs are immutable.')
    return super().save(*args, **kwargs)

  def __str__(self) -> str:
    return f'{self.action} @ {self.created_at:%Y-%m-%d %H:%M}'


class PaymentNotification(models.Model):
  """Minimal in-app notification row backing the payments nav badge. There is
  no app-wide notification system yet; this stays payments-scoped."""

  RECIPIENT_CHOICES = [('professional', 'Professional'), ('client', 'Client')]

  recipient_type = models.CharField(max_length=12, choices=RECIPIENT_CHOICES, db_index=True)
  recipient_professional = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name='payment_notifications')
  recipient_client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, null=True, blank=True, related_name='payment_notifications')
  notif_type = models.CharField(max_length=40, db_index=True)
  title = models.CharField(max_length=200)
  body = models.TextField(blank=True)
  payload = models.JSONField(default=dict, blank=True)
  is_read = models.BooleanField(default=False, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True, db_index=True)

  class Meta:
    db_table = 'payment_notifications'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.notif_type} ({self.recipient_type})'
