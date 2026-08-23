from django.db import migrations, models


class Migration(migrations.Migration):
  """Lets a professional decide the order their profile sections appear in.

  Defaults to an empty list, which every existing profile gets: the serializer
  reads that as "use the built-in order", so nothing changes until someone
  actually drags a section.
  """

  dependencies = [
    ('accounts', '0045_professional_profile_images'),
  ]

  operations = [
    migrations.AddField(
      model_name='professionalprofile',
      name='profile_section_order',
      field=models.JSONField(blank=True, default=list),
    ),
  ]
