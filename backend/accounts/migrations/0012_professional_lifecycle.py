from datetime import timedelta

from django.db import migrations, models


def expire_legacy_snapshots(apps, schema_editor):
    Snapshot = apps.get_model('accounts', 'RecycledProfessionalAccount')
    for snapshot in Snapshot.objects.filter(expires_at__isnull=True).iterator():
        snapshot.expires_at = snapshot.deleted_at + timedelta(days=14)
        snapshot.save(update_fields=['expires_at'])


class Migration(migrations.Migration):
    dependencies = [('accounts', '0011_alter_paymentauditlog_action_and_more')]

    operations = [
        migrations.AddField(
            model_name='professionalprofile',
            name='lifecycle_status',
            field=models.CharField(
                choices=[
                    ('active', 'Active'),
                    ('over_quota_grace', 'Over quota grace'),
                    ('frozen', 'Frozen'),
                    ('recycled', 'Recycle Bin'),
                ],
                db_index=True,
                default='active',
                max_length=24,
            ),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='lifecycle_reason',
            field=models.CharField(
                blank=True,
                choices=[
                    ('trainer_requested', 'Trainer requested'),
                    ('billing_overage', 'Billing storage overage'),
                    ('admin_action', 'Administrative action'),
                ],
                db_index=True,
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='recycled_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='recycle_expires_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='recycled_by_reference',
            field=models.CharField(blank=True, max_length=24),
        ),
        migrations.AddField(
            model_name='recycledprofessionalaccount',
            name='expires_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.RunPython(expire_legacy_snapshots, migrations.RunPython.noop),
    ]
