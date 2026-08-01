from django.db import migrations, models
import django.utils.timezone


def seed_release(apps, schema_editor):
    Release = apps.get_model('accounts', 'LegalDocumentRelease')
    Release.objects.create(singleton_key=1, legal_document_version='2026-07-30')


class Migration(migrations.Migration):

    dependencies = [('accounts', '0037_legalacceptancerecord')]

    operations = [
        migrations.CreateModel(
            name='LegalDocumentRelease',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('singleton_key', models.PositiveSmallIntegerField(default=1, unique=True)),
                ('legal_document_version', models.CharField(max_length=32)),
                ('activated_at', models.DateTimeField(default=django.utils.timezone.now)),
            ],
            options={'db_table': 'legal_document_release'},
        ),
        migrations.RunPython(seed_release, migrations.RunPython.noop),
    ]
