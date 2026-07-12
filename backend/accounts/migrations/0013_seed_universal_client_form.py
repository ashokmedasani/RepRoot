from django.db import migrations


def seed_missing_registration_forms(apps, schema_editor):
  """Backfill the universal client creation form for groups that lack one."""
  from accounts.models import default_client_registration_fields

  TrainerGroup = apps.get_model('accounts', 'TrainerGroup')
  ClientRegistrationForm = apps.get_model('accounts', 'ClientRegistrationForm')

  for group in TrainerGroup.objects.filter(client_registration_form__isnull=True):
    ClientRegistrationForm.objects.create(group=group, fields=default_client_registration_fields())


def noop_reverse(apps, schema_editor):
  # Forms created by this data migration are indistinguishable from
  # trainer-created ones, so there is nothing safe to reverse.
  pass


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0012_clientaccess_trainer_notes_updated_at'),
  ]

  operations = [
    migrations.RunPython(seed_missing_registration_forms, noop_reverse),
  ]
