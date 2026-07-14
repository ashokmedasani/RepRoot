import uuid

import accounts.models
import django.db.models.deletion
from django.db import migrations, models


def populate_onboarding_references(apps, schema_editor):
  ClientRegistrationForm = apps.get_model('accounts', 'ClientRegistrationForm')
  ClientAccess = apps.get_model('accounts', 'ClientAccess')

  for form in ClientRegistrationForm.objects.filter(public_slug__isnull=True):
    form.public_slug = f'group-{form.group_id}-{uuid.uuid4().hex[:12]}'
    form.save(update_fields=['public_slug'])

  for client in ClientAccess.objects.filter(reference_id__isnull=True).select_related('lead_submission'):
    if client.lead_submission_id and client.lead_submission.reference_id:
      reference_id = client.lead_submission.reference_id
    else:
      reference_id = f'CL-{uuid.uuid4().hex[:10].upper()}'
    client.reference_id = reference_id
    client.save(update_fields=['reference_id'])


class Migration(migrations.Migration):
  dependencies = [
    ('accounts', '0020_clientaccess_additional_info_shared_clientreminder_and_more'),
  ]

  operations = [
    migrations.AddField(
      model_name='clientregistrationform',
      name='public_slug',
      field=models.SlugField(blank=True, db_index=True, max_length=64, null=True, unique=True),
    ),
    migrations.CreateModel(
      name='GroupRegistrationSubmission',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('first_name', models.CharField(max_length=150)),
        ('last_name', models.CharField(max_length=150)),
        ('email', models.EmailField(max_length=254)),
        ('reference_id', models.CharField(default=accounts.models.generate_client_reference_id, max_length=32, unique=True)),
        ('answers', models.JSONField(default=dict)),
        ('status', models.CharField(choices=[('pending', 'Pending'), ('converted', 'Converted'), ('deleted', 'Deleted')], db_index=True, default='pending', max_length=20)),
        ('submitted_at', models.DateTimeField(auto_now_add=True)),
        ('converted_at', models.DateTimeField(blank=True, null=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        ('group', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='registration_submissions', to='accounts.trainergroup')),
      ],
      options={
        'db_table': 'group_registration_submissions',
        'ordering': ['-submitted_at'],
      },
    ),
    migrations.AlterField(
      model_name='clientaccess',
      name='lead_submission',
      field=models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='client_access', to='accounts.leadsubmission'),
    ),
    migrations.AddField(
      model_name='clientaccess',
      name='onboarding_method',
      field=models.CharField(choices=[('public_lead', 'Public lead'), ('manual', 'Manual'), ('group_registration', 'Group registration')], default='public_lead', max_length=24),
    ),
    migrations.AddField(
      model_name='clientaccess',
      name='reference_id',
      field=models.CharField(max_length=32, null=True),
    ),
    migrations.AddField(
      model_name='clientaccess',
      name='registration_submission',
      field=models.OneToOneField(blank=True, null=True, on_delete=django.db.models.deletion.PROTECT, related_name='client_access', to='accounts.groupregistrationsubmission'),
    ),
    migrations.RunPython(populate_onboarding_references, migrations.RunPython.noop),
    migrations.AlterField(
      model_name='clientaccess',
      name='reference_id',
      field=models.CharField(default=accounts.models.generate_client_reference_id, max_length=32, unique=True),
    ),
  ]
