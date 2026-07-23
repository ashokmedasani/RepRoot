from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('admin_portal', '0003_lifecycle_permissions')]
    operations = [
        migrations.AddField(model_name='financeledgerentry', name='source', field=models.CharField(db_index=True, default='platform', max_length=24)),
        migrations.AddField(model_name='financeledgerentry', name='professional_reference', field=models.CharField(blank=True, max_length=24)),
        migrations.AddField(model_name='financeledgerentry', name='client_reference', field=models.CharField(blank=True, max_length=32)),
        migrations.AddField(model_name='financeledgerentry', name='payment_request_reference', field=models.CharField(blank=True, max_length=32)),
        migrations.AddField(model_name='financeledgerentry', name='payment_record_reference', field=models.CharField(blank=True, max_length=32)),
        migrations.AddField(model_name='financeledgerentry', name='original_amount', field=models.DecimalField(blank=True, decimal_places=2, max_digits=12, null=True)),
        migrations.AddField(model_name='financeledgerentry', name='original_currency', field=models.CharField(blank=True, max_length=3)),
        migrations.AddField(model_name='financeledgerentry', name='reporting_amount', field=models.DecimalField(blank=True, decimal_places=2, max_digits=12, null=True)),
        migrations.AddField(model_name='financeledgerentry', name='reporting_currency', field=models.CharField(blank=True, max_length=3)),
        migrations.AddField(model_name='financeledgerentry', name='provider', field=models.CharField(blank=True, max_length=32)),
        migrations.AddField(model_name='financeledgerentry', name='metadata', field=models.JSONField(blank=True, default=dict)),
    ]
