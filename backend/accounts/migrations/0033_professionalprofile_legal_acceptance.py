from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0032_professionalprofile_cancellation_target_tier'),
    ]

    operations = [
        migrations.CreateModel(
            name='BillingWebhookEvent',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('provider', models.CharField(max_length=32)),
                ('event_id', models.CharField(max_length=160)),
                ('event_type', models.CharField(blank=True, max_length=80)),
                ('processed_at', models.DateTimeField(auto_now_add=True)),
            ],
            options={
                'db_table': 'billing_webhook_events',
                'constraints': [
                    models.UniqueConstraint(
                        fields=('provider', 'event_id'),
                        name='unique_billing_provider_event',
                    ),
                ],
            },
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='legal_document_version',
            field=models.CharField(blank=True, max_length=32),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='privacy_policy_accepted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='terms_accepted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
