import uuid

from django.db import migrations, models
import django.db.models.deletion


def populate_booking_tokens(apps, schema_editor):
  LeadSubmission = apps.get_model('accounts', 'LeadSubmission')
  for submission in LeadSubmission.objects.filter(booking_access_token__isnull=True).iterator():
    submission.booking_access_token = uuid.uuid4()
    submission.save(update_fields=['booking_access_token'])


class Migration(migrations.Migration):
  dependencies = [('accounts', '0014_reporting_currency_confirmation')]

  operations = [
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_buffer_minutes', field=models.PositiveIntegerField(default=15)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_duration_minutes', field=models.PositiveIntegerField(default=15)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_enabled', field=models.BooleanField(default=False)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_event_type_id', field=models.PositiveIntegerField(blank=True, null=True)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_max_advance_days', field=models.PositiveIntegerField(default=30)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_min_notice_hours', field=models.PositiveIntegerField(default=24)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_requires_approval', field=models.BooleanField(default=True)),
    migrations.AddField(model_name='professionalleadform', name='introductory_meeting_title', field=models.CharField(default='15-minute introductory call', max_length=180)),
    migrations.AddField(model_name='leadsubmission', name='booking_access_token', field=models.UUIDField(editable=False, null=True)),
    migrations.RunPython(populate_booking_tokens, migrations.RunPython.noop),
    migrations.AlterField(model_name='leadsubmission', name='booking_access_token', field=models.UUIDField(default=uuid.uuid4, editable=False, unique=True)),
    migrations.CreateModel(
      name='LeadMeetingRequest',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('requested_start', models.DateTimeField(db_index=True)),
        ('requested_end', models.DateTimeField()),
        ('contact_email', models.EmailField(max_length=254)),
        ('contact_mobile', models.CharField(blank=True, max_length=32)),
        ('status', models.CharField(choices=[('pending', 'Pending'), ('accepted', 'Accepted'), ('declined', 'Declined'), ('expired', 'Expired')], db_index=True, default='pending', max_length=12)),
        ('trainer_note', models.TextField(blank=True)),
        ('cal_booking_uid', models.CharField(blank=True, db_index=True, max_length=64)),
        ('meeting_url', models.URLField(blank=True)),
        ('expires_at', models.DateTimeField(db_index=True)),
        ('reviewed_at', models.DateTimeField(blank=True, null=True)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        ('submission', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='meeting_request', to='accounts.leadsubmission')),
      ],
      options={'db_table': 'lead_meeting_requests', 'ordering': ['-created_at']},
    ),
  ]
