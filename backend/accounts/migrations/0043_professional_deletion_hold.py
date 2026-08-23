from django.db import migrations, models


class Migration(migrations.Migration):
  """Adds the cooling-off state for self-service professional account deletion.

  No data migration is needed: every existing profile keeps its current
  lifecycle_status, and the three new fields are null/empty until a deletion is
  actually requested.
  """

  dependencies = [
    ('accounts', '0042_supportincident_email_delivery'),
  ]

  operations = [
    migrations.AlterField(
      model_name='professionalprofile',
      name='lifecycle_status',
      field=models.CharField(
        choices=[
          ('active', 'Active'),
          ('over_quota_grace', 'Over quota grace'),
          ('frozen', 'Frozen'),
          ('pending_deletion', 'Deletion pending'),
          ('recycled', 'Recycle Bin'),
        ],
        db_index=True,
        default='active',
        max_length=24,
      ),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='deletion_requested_at',
      field=models.DateTimeField(blank=True, db_index=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='deletion_hold_ends_at',
      field=models.DateTimeField(blank=True, db_index=True, null=True),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='deletion_impact_snapshot',
      field=models.JSONField(blank=True, default=dict),
    ),
  ]
