from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0039_alter_paymentrequest_status'),
    ]

    operations = [
        migrations.AlterField(
            model_name='paymentauditlog',
            name='action',
            field=models.CharField(
                choices=[
                    ('method_created', 'Method created'),
                    ('method_updated', 'Method updated'),
                    ('method_shared', 'Method shared'),
                    ('method_unshared', 'Method unshared'),
                    ('request_created', 'Request created'),
                    ('request_updated', 'Request updated'),
                    ('request_cancelled', 'Request cancelled'),
                    ('proof_submitted', 'Proof submitted'),
                    ('proof_rejected', 'Proof rejected'),
                    ('info_requested', 'More info requested'),
                    ('payment_acknowledged', 'Payment acknowledged'),
                    ('payment_verified', 'Payment verified'),
                    ('payment_recorded', 'Payment recorded'),
                    ('payment_edited', 'Payment edited'),
                    ('payment_deleted', 'Payment deleted'),
                    ('proof_expired', 'Proof expired under retention policy'),
                ],
                db_index=True,
                max_length=32,
            ),
        ),
    ]
