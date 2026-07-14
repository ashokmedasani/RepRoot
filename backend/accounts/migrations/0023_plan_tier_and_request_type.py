from django.db import migrations, models


class Migration(migrations.Migration):
  dependencies = [('accounts', '0022_trainerprofile_internal_reference_code')]

  operations = [
    migrations.AddField(
      model_name='trainerprofile',
      name='plan_tier',
      field=models.CharField(
        choices=[('starter', 'Starter'), ('premium', 'Premium')],
        db_index=True,
        default='starter',
        max_length=20,
      ),
    ),
    migrations.AddField(
      model_name='clientdetailchangerequest',
      name='request_type',
      field=models.CharField(
        choices=[('profile_edit', 'Profile edit'), ('account_deletion', 'Account deletion')],
        db_index=True,
        default='profile_edit',
        max_length=24,
      ),
    ),
  ]
