from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0041_alter_supportincident_reporter_role'),
  ]

  operations = [
    migrations.AddField(
      model_name='supportincident',
      name='acknowledgement_email_status',
      field=models.CharField(
        choices=[
          ('not_requested', 'Not requested'),
          ('pending', 'Pending'),
          ('sent', 'Sent'),
          ('failed', 'Failed'),
          ('skipped', 'Skipped'),
        ],
        default='not_requested',
        max_length=20,
      ),
    ),
    migrations.AddField(
      model_name='supportincident',
      name='email_delivery_error',
      field=models.CharField(blank=True, max_length=500),
    ),
    migrations.AddField(
      model_name='supportincident',
      name='email_delivery_updated_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='supportincident',
      name='support_email_status',
      field=models.CharField(
        choices=[
          ('not_requested', 'Not requested'),
          ('pending', 'Pending'),
          ('sent', 'Sent'),
          ('failed', 'Failed'),
          ('skipped', 'Skipped'),
        ],
        default='not_requested',
        max_length=20,
      ),
    ),
  ]
