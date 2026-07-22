from django.db import migrations, models


def reset_legacy_dashboard_lock(apps, schema_editor):
    settings_model = apps.get_model('accounts', 'ProfessionalPaymentSettings')
    settings_model.objects.update(reporting_currency_locked=False, reporting_currency_locked_at=None)


class Migration(migrations.Migration):
    dependencies = [('accounts', '0013_retention_and_reset_audit')]
    operations = [
        migrations.AddField(
            model_name='professionalpaymentsettings',
            name='reporting_currency_locked_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name='professionalpaymentsettings',
            name='reporting_currency_locked',
            field=models.BooleanField(default=False),
        ),
        migrations.RunPython(reset_legacy_dashboard_lock, migrations.RunPython.noop),
    ]
