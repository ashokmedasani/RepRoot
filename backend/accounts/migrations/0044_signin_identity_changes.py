from django.db import migrations, models


class Migration(migrations.Migration):
  """Cooldown timestamps and the pending-email holding area for sign-in details.

  All nullable/blank, so every existing profile is treated as "never changed"
  and its owner gets one change immediately.
  """

  dependencies = [
    ('accounts', '0043_professional_deletion_hold'),
  ]

  operations = [
    migrations.AddField(
      model_name='professionalprofile',
      name='username_changed_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='email_changed_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='pending_email',
      field=models.EmailField(blank=True, max_length=254),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='pending_email_requested_at',
      field=models.DateTimeField(blank=True, null=True),
    ),
  ]
