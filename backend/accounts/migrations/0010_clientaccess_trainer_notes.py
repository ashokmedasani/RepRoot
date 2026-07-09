from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0009_remove_trackingtemplate_references_and_more'),
  ]

  operations = [
    migrations.AddField(
      model_name='clientaccess',
      name='trainer_notes',
      field=models.TextField(blank=True),
    ),
  ]
