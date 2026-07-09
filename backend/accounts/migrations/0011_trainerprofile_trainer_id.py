from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0010_clientaccess_trainer_notes'),
  ]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='trainer_id',
      field=models.CharField(blank=True, db_index=True, max_length=32, null=True, unique=True),
    ),
  ]
