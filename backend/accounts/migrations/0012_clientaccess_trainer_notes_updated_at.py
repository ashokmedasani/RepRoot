from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0011_trainerprofile_trainer_id'),
  ]

  operations = [
    migrations.AddField(
      model_name='clientaccess',
      name='trainer_notes_updated_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
  ]
