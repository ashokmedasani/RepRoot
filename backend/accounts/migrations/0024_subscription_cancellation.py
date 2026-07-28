from django.db import migrations, models


class Migration(migrations.Migration):
  dependencies = [
    ('accounts', '0023_multiple_professional_lead_forms'),
  ]

  operations = [
    migrations.AddField(
      model_name='professionalprofile',
      name='cancellation_requested_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='cancellation_effective_at',
      field=models.DateTimeField(blank=True, db_index=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='cancellation_force_cleanup',
      field=models.BooleanField(default=False),
    ),
  ]
