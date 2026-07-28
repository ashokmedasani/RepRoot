from django.db import migrations, models


class Migration(migrations.Migration):
  dependencies = [('accounts', '0021_google_calendar_sync')]

  operations = [
    migrations.AddField(
      model_name='professionalprofile',
      name='razorpay_payment_id',
      field=models.CharField(blank=True, db_index=True, max_length=64),
    ),
    migrations.AddField(
      model_name='professionalprofile',
      name='razorpay_payment_link_id',
      field=models.CharField(blank=True, db_index=True, max_length=64),
    ),
  ]
