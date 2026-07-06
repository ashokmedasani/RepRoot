from django.db import migrations, models


class Migration(migrations.Migration):
  dependencies = [
    ('accounts', '0002_trainerprofile_middle_name_and_privacy'),
  ]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='birth_month',
      field=models.PositiveSmallIntegerField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='trainerprofile',
      name='birth_year',
      field=models.PositiveSmallIntegerField(blank=True, null=True),
    ),
    migrations.AlterField(
      model_name='trainerprofile',
      name='country',
      field=models.CharField(blank=True, max_length=80),
    ),
  ]
