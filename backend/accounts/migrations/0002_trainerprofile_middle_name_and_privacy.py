from django.db import migrations, models


class Migration(migrations.Migration):
  dependencies = [
    ('accounts', '0001_initial'),
  ]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='middle_name',
      field=models.CharField(blank=True, max_length=150),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='privacy_policy_accepted',
      field=models.BooleanField(default=False),
    ),
  ]
