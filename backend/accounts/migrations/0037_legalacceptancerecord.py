from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone


def backfill_existing_acceptances(apps, schema_editor):
    ProfessionalProfile = apps.get_model('accounts', 'ProfessionalProfile')
    ClientAccess = apps.get_model('accounts', 'ClientAccess')
    LegalAcceptanceRecord = apps.get_model('accounts', 'LegalAcceptanceRecord')

    professional_rows = []
    for profile in ProfessionalProfile.objects.filter(terms_accepted=True, privacy_policy_accepted=True):
        professional_rows.append(LegalAcceptanceRecord(
            actor_type='professional',
            professional_profile_id=profile.id,
            actor_reference=str(profile.professional_id or profile.user_id),
            legal_document_version=profile.legal_document_version or 'legacy',
            accepted_at=profile.terms_accepted_at or profile.privacy_policy_accepted_at or profile.updated_at,
        ))
    LegalAcceptanceRecord.objects.bulk_create(professional_rows, batch_size=500)

    client_rows = []
    for client in ClientAccess.objects.filter(terms_accepted=True, privacy_policy_accepted=True):
        client_rows.append(LegalAcceptanceRecord(
            actor_type='client',
            client_access_id=client.id,
            actor_reference=client.reference_id,
            legal_document_version=client.legal_document_version or 'legacy',
            accepted_at=client.terms_accepted_at or client.privacy_policy_accepted_at or client.updated_at,
        ))
    LegalAcceptanceRecord.objects.bulk_create(client_rows, batch_size=500)


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0036_clientaccess_legal_acceptance'),
    ]

    operations = [
        migrations.CreateModel(
            name='LegalAcceptanceRecord',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('actor_type', models.CharField(choices=[('professional', 'Professional'), ('client', 'Client')], db_index=True, max_length=16)),
                ('actor_reference', models.CharField(db_index=True, max_length=150)),
                ('legal_document_version', models.CharField(db_index=True, max_length=32)),
                ('terms_accepted', models.BooleanField(default=True)),
                ('privacy_policy_accepted', models.BooleanField(default=True)),
                ('accepted_at', models.DateTimeField(db_index=True, default=django.utils.timezone.now)),
                ('client_timezone', models.CharField(blank=True, max_length=80)),
                ('client_access', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='legal_acceptance_records', to='accounts.clientaccess')),
                ('professional_profile', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='legal_acceptance_records', to='accounts.professionalprofile')),
            ],
            options={
                'db_table': 'legal_acceptance_records',
                'ordering': ['-accepted_at', '-id'],
            },
        ),
        migrations.RunPython(backfill_existing_acceptances, migrations.RunPython.noop),
    ]
