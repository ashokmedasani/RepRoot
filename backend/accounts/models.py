from django.conf import settings
from django.db import models


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


class TrainerProfile(models.Model):
  user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='trainer_profile')
  trainer_id = models.CharField(max_length=32, unique=True, null=True, blank=True, db_index=True)
  profile_setup_completed = models.BooleanField(default=False)
  profile_photo = models.FileField(upload_to='trainer-profiles/photos/', blank=True)
  middle_name = models.CharField(max_length=150, blank=True)
  gender = models.CharField(max_length=40, blank=True)
  state = models.CharField(max_length=80, blank=True)
  country = models.CharField(max_length=80, blank=True)
  birth_month = models.PositiveSmallIntegerField(null=True, blank=True)
  birth_year = models.PositiveSmallIntegerField(null=True, blank=True)
  professional_headline = models.CharField(max_length=180, blank=True)
  about_me = models.TextField(blank=True)
  trainer_type = models.CharField(max_length=120, blank=True)
  years_experience = models.PositiveSmallIntegerField(null=True, blank=True)
  specializations = models.TextField(blank=True)
  training_style = models.TextField(blank=True)
  languages_known = models.CharField(max_length=240, blank=True)
  certification_name = models.CharField(max_length=180, blank=True)
  certification_issued_by = models.CharField(max_length=180, blank=True)
  certification_year = models.PositiveSmallIntegerField(null=True, blank=True)
  certification_file = models.FileField(upload_to='trainer-profiles/certifications/', blank=True)
  transformation_photo = models.FileField(upload_to='trainer-profiles/transformations/', blank=True)
  training_photo = models.FileField(upload_to='trainer-profiles/training/', blank=True)
  intro_video_url = models.URLField(blank=True)
  instagram_url = models.URLField(blank=True)
  youtube_url = models.URLField(blank=True)
  website_url = models.URLField(blank=True)
  terms_accepted = models.BooleanField(default=False)
  privacy_policy_accepted = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'trainer_profiles'

  def __str__(self) -> str:
    return f'{self.user.get_full_name()} ({self.user.username})'


class TrainerLeadForm(models.Model):
  trainer = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='lead_form')
  public_slug = models.SlugField(max_length=64, unique=True)
  title = models.CharField(max_length=160, default='Trainer Lead Form')
  fields = models.JSONField(default=list)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'trainer_lead_forms'

  def __str__(self) -> str:
    return f'{self.trainer.username} lead form'


class TrainerGroup(models.Model):
  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='trainer_groups')
  name = models.CharField(max_length=120)
  description = models.TextField(blank=True)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'trainer_groups'
    ordering = ['created_at']
    unique_together = ('trainer', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.trainer.username})'


class ClientRegistrationForm(models.Model):
  group = models.OneToOneField(TrainerGroup, on_delete=models.CASCADE, related_name='client_registration_form')
  fields = models.JSONField(default=list)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'client_registration_forms'

  def __str__(self) -> str:
    return f'{self.group.name} client registration form'


class LeadSubmission(models.Model):
  STATUS_PENDING = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_DELETED = 'deleted'

  STATUS_CHOICES = [
    (STATUS_PENDING, 'Pending'),
    (STATUS_APPROVED, 'Approved / Converted'),
    (STATUS_DELETED, 'Deleted'),
  ]

  lead_form = models.ForeignKey(TrainerLeadForm, on_delete=models.CASCADE, related_name='submissions')
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


class ClientAccess(models.Model):
  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='client_access_records')
  group = models.ForeignKey(TrainerGroup, on_delete=models.PROTECT, related_name='client_access_records')
  lead_submission = models.OneToOneField(LeadSubmission, on_delete=models.PROTECT, related_name='client_access')
  first_name = models.CharField(max_length=150)
  last_name = models.CharField(max_length=150)
  email = models.EmailField()
  username = models.CharField(max_length=150)
  temporary_password = models.CharField(max_length=128)
  registration_answers = models.JSONField(default=dict)
  trainer_notes = models.TextField(blank=True)
  trainer_notes_updated_at = models.DateTimeField(null=True, blank=True)
  must_change_password = models.BooleanField(default=True)
  is_active = models.BooleanField(default=True, db_index=True)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'client_access'
    unique_together = [('trainer', 'email'), ('trainer', 'username')]
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.username} for {self.trainer.username}'


class ReferenceCategory(models.Model):
  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='reference_categories')
  name = models.CharField(max_length=120)
  subcategories = models.JSONField(default=list)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'reference_categories'
    ordering = ['created_at']
    unique_together = ('trainer', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.trainer.username})'


class TrainerReference(models.Model):
  TYPE_VIDEO_LINK = 'video_link'
  TYPE_PDF = 'pdf'
  TYPE_IMAGE = 'image'
  TYPE_DOCUMENT = 'document'
  TYPE_TEXT_NOTE = 'text_note'
  TYPE_EXTERNAL_LINK = 'external_link'

  REFERENCE_TYPE_CHOICES = [
    (TYPE_VIDEO_LINK, 'Video Link'),
    (TYPE_PDF, 'PDF'),
    (TYPE_IMAGE, 'Image'),
    (TYPE_DOCUMENT, 'Document'),
    (TYPE_TEXT_NOTE, 'Text Note'),
    (TYPE_EXTERNAL_LINK, 'External Link'),
  ]

  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='trainer_references')
  category = models.ForeignKey(ReferenceCategory, on_delete=models.PROTECT, related_name='references')
  subcategory = models.CharField(max_length=120, blank=True)
  title = models.CharField(max_length=180)
  reference_type = models.CharField(max_length=20, choices=REFERENCE_TYPE_CHOICES)
  description = models.TextField(blank=True)
  link = models.URLField(blank=True)
  file = models.FileField(upload_to='trainer-references/', blank=True)
  tags = models.JSONField(default=list)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'trainer_references'
    ordering = ['-created_at']

  def __str__(self) -> str:
    return f'{self.title} ({self.trainer.username})'


class TrackingTemplate(models.Model):
  CADENCE_DAILY = 'daily'
  CADENCE_WEEKLY = 'weekly'
  CADENCE_MONTHLY = 'monthly'

  CADENCE_CHOICES = [
    (CADENCE_DAILY, 'Daily'),
    (CADENCE_WEEKLY, 'Weekly'),
    (CADENCE_MONTHLY, 'Monthly'),
  ]

  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='tracking_templates')
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
    unique_together = ('trainer', 'name')

  def __str__(self) -> str:
    return f'{self.name} ({self.trainer.username})'


class TemplateAssignment(models.Model):
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='template_assignments')
  template = models.ForeignKey(TrackingTemplate, on_delete=models.CASCADE, related_name='assignments')
  references = models.ManyToManyField(TrainerReference, blank=True, related_name='template_assignments')
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
  answers = models.JSONField(default=dict)
  note = models.TextField(blank=True)
  edited_by_trainer = models.BooleanField(default=False)
  created_at = models.DateTimeField(auto_now_add=True)
  updated_at = models.DateTimeField(auto_now=True)

  class Meta:
    db_table = 'tracking_entries'
    ordering = ['-entry_date', '-updated_at']
    unique_together = ('client', 'template', 'entry_date')

  def __str__(self) -> str:
    return f'{self.client.username} {self.template_name} {self.entry_date}'


class ChatMessage(models.Model):
  SENDER_TRAINER = 'trainer'
  SENDER_CLIENT = 'client'

  SENDER_CHOICES = [
    (SENDER_TRAINER, 'Trainer'),
    (SENDER_CLIENT, 'Client'),
  ]

  trainer = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='chat_messages')
  client = models.ForeignKey(ClientAccess, on_delete=models.CASCADE, related_name='chat_messages')
  sender = models.CharField(max_length=10, choices=SENDER_CHOICES)
  text = models.TextField()
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


class RecycledTrainerAccount(models.Model):
  original_user_id = models.PositiveIntegerField(db_index=True)
  email = models.EmailField(db_index=True)
  username = models.CharField(max_length=150, db_index=True)
  first_name = models.CharField(max_length=150, blank=True)
  last_name = models.CharField(max_length=150, blank=True)
  account_snapshot = models.JSONField()
  deleted_at = models.DateTimeField(auto_now_add=True)

  class Meta:
    db_table = 'recycled_trainer_accounts'
    ordering = ['-deleted_at']

  def __str__(self) -> str:
    return f'{self.email} recycled at {self.deleted_at:%Y-%m-%d %H:%M}'
