# Companion to 0028_rename_reference_to_resource: the notification-preference
# category list (accounts/notifications.py CATEGORIES) also had a 'references'
# entry renamed to 'resources'. Any row a user already saved under the old
# category name needs to move to the new one so their existing toggle choice
# (in_app/email/push/digest settings) carries over instead of silently
# resetting to defaults. Guarded with get_or_create-style handling in case a
# 'resources' row already exists for that recipient (shouldn't happen in
# practice since the old category was never wired to an actual notify() call,
# but kept safe regardless).
from django.db import migrations


OLD_CATEGORY = 'references'
NEW_CATEGORY = 'resources'


def forwards_rename_category(apps, schema_editor):
  NotificationPreference = apps.get_model('accounts', 'NotificationPreference')
  for row in NotificationPreference.objects.filter(category=OLD_CATEGORY):
    lookup = {'recipient_type': row.recipient_type, 'category': NEW_CATEGORY}
    if row.recipient_professional_id:
      lookup['recipient_professional_id'] = row.recipient_professional_id
    if row.recipient_client_id:
      lookup['recipient_client_id'] = row.recipient_client_id
    if NotificationPreference.objects.filter(**lookup).exists():
      row.delete()
    else:
      row.category = NEW_CATEGORY
      row.save(update_fields=['category'])


def backwards_rename_category(apps, schema_editor):
  NotificationPreference = apps.get_model('accounts', 'NotificationPreference')
  for row in NotificationPreference.objects.filter(category=NEW_CATEGORY):
    lookup = {'recipient_type': row.recipient_type, 'category': OLD_CATEGORY}
    if row.recipient_professional_id:
      lookup['recipient_professional_id'] = row.recipient_professional_id
    if row.recipient_client_id:
      lookup['recipient_client_id'] = row.recipient_client_id
    if NotificationPreference.objects.filter(**lookup).exists():
      row.delete()
    else:
      row.category = OLD_CATEGORY
      row.save(update_fields=['category'])


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0028_rename_reference_to_resource'),
  ]

  operations = [
    migrations.RunPython(forwards_rename_category, backwards_rename_category),
  ]
