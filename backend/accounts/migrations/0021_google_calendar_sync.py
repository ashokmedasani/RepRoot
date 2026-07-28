from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0020_scheduling_rework'),
  ]

  operations = [
    migrations.AddField(
      model_name='leadmeetingrequest',
      name='external_calendar_event_id',
      field=models.CharField(blank=True, db_index=True, max_length=255),
    ),
    migrations.AddField(
      model_name='leadmeetingrequest',
      name='external_calendar_provider',
      field=models.CharField(blank=True, max_length=20),
    ),
    migrations.AddField(
      model_name='leadmeetingrequest',
      name='external_calendar_sync_status',
      field=models.CharField(default='internal', max_length=20),
    ),
    migrations.AddField(
      model_name='leadmeetingrequest',
      name='external_calendar_url',
      field=models.URLField(blank=True),
    ),
    migrations.AddField(
      model_name='scheduledmeeting',
      name='external_calendar_event_id',
      field=models.CharField(blank=True, db_index=True, max_length=255),
    ),
    migrations.AddField(
      model_name='scheduledmeeting',
      name='external_calendar_provider',
      field=models.CharField(blank=True, max_length=20),
    ),
    migrations.AddField(
      model_name='scheduledmeeting',
      name='external_calendar_sync_status',
      field=models.CharField(default='internal', max_length=20),
    ),
    migrations.AddField(
      model_name='scheduledmeeting',
      name='external_calendar_url',
      field=models.URLField(blank=True),
    ),
  ]
