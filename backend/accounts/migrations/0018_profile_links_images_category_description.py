from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0017_trainerprofile_phone'),
  ]

  operations = [
    migrations.AddField(
      model_name='referencecategory',
      name='description',
      field=models.TextField(blank=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='profile_images',
      field=models.JSONField(blank=True, default=list),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='profile_links',
      field=models.JSONField(blank=True, default=list),
    ),
    migrations.AlterField(
      model_name='trainerreference',
      name='reference_type',
      field=models.CharField(
        choices=[
          ('video_link', 'Video Link'),
          ('pdf', 'PDF Link'),
          ('text_note', 'Text'),
          ('image', 'Image'),
        ],
        max_length=20,
      ),
    ),
  ]
