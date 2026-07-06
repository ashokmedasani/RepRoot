from django.conf import settings
from django.db import models


class TrainerProfile(models.Model):
  user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='trainer_profile')
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
