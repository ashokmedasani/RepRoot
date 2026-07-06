from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0003_trainerprofile_birth_month_birth_year_and_more'),
  ]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='about_me',
      field=models.TextField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='certification_file',
      field=models.FileField(blank=True, upload_to='trainer-profiles/certifications/'),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='certification_issued_by',
      field=models.CharField(blank=True, max_length=180),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='certification_name',
      field=models.CharField(blank=True, max_length=180),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='certification_year',
      field=models.PositiveSmallIntegerField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='gender',
      field=models.CharField(blank=True, max_length=40),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='instagram_url',
      field=models.URLField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='intro_video_url',
      field=models.URLField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='languages_known',
      field=models.CharField(blank=True, max_length=240),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='professional_headline',
      field=models.CharField(blank=True, max_length=180),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='profile_photo',
      field=models.FileField(blank=True, upload_to='trainer-profiles/photos/'),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='profile_setup_completed',
      field=models.BooleanField(default=False),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='specializations',
      field=models.TextField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='trainer_type',
      field=models.CharField(blank=True, max_length=120),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='training_photo',
      field=models.FileField(blank=True, upload_to='trainer-profiles/training/'),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='training_style',
      field=models.TextField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='transformation_photo',
      field=models.FileField(blank=True, upload_to='trainer-profiles/transformations/'),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='website_url',
      field=models.URLField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='years_experience',
      field=models.PositiveSmallIntegerField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='youtube_url',
      field=models.URLField(blank=True),
    ),
  ]
