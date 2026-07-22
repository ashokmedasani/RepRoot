import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('accounts', '0012_professional_lifecycle'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='ClientResetAudit',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('professional_reference', models.CharField(max_length=24)),
                ('client_reference', models.CharField(max_length=32)),
                ('client_username', models.CharField(max_length=150)),
                ('reason', models.TextField()),
                ('deleted_counts', models.JSONField(default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True, db_index=True)),
                ('client', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='reset_audits', to='accounts.clientaccess')),
                ('professional', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='client_reset_audits', to=settings.AUTH_USER_MODEL)),
            ],
            options={'db_table': 'client_reset_audits', 'ordering': ['-created_at']},
        ),
        migrations.AlterField(
            model_name='paymentauditlog',
            name='action',
            field=models.CharField(
                choices=[
                    ('method_created', 'Method created'), ('method_updated', 'Method updated'),
                    ('method_shared', 'Method shared'), ('method_unshared', 'Method unshared'),
                    ('request_created', 'Request created'), ('request_cancelled', 'Request cancelled'),
                    ('proof_submitted', 'Proof submitted'), ('proof_rejected', 'Proof rejected'),
                    ('info_requested', 'More info requested'), ('payment_acknowledged', 'Payment acknowledged'),
                    ('payment_verified', 'Payment verified'), ('payment_recorded', 'Payment recorded'),
                    ('payment_edited', 'Payment edited'), ('payment_deleted', 'Payment deleted'),
                    ('proof_expired', 'Proof expired under retention policy'),
                ],
                db_index=True, max_length=32,
            ),
        ),
    ]
