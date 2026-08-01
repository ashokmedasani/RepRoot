from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0035_paymentrecord_source_proof'),
    ]

    operations = [
        migrations.AddField(
            model_name='clientaccess',
            name='terms_accepted',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='clientaccess',
            name='privacy_policy_accepted',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='clientaccess',
            name='terms_accepted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='clientaccess',
            name='privacy_policy_accepted_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='clientaccess',
            name='legal_document_version',
            field=models.CharField(blank=True, max_length=32),
        ),
    ]
