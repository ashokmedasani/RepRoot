from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0034_scheduledmeeting_client_requests'),
    ]

    operations = [
        migrations.AddField(
            model_name='paymentrecord',
            name='source_proof',
            field=models.OneToOneField(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='payment_record',
                to='accounts.paymentproof',
            ),
        ),
    ]
