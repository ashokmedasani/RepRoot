from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0040_alter_paymentauditlog_action'),
  ]

  operations = [
    migrations.AlterField(
      model_name='supportincident',
      name='reporter_role',
      field=models.CharField(
        choices=[
          ('professional', 'Professional'),
          ('client', 'Client'),
          ('public', 'Public website'),
        ],
        db_index=True,
        max_length=12,
      ),
    ),
  ]
