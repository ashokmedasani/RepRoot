from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0018_profile_links_images_category_description'),
  ]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='profile_visibility',
      field=models.JSONField(blank=True, default=dict),
    ),
  ]
