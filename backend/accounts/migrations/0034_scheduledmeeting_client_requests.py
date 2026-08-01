from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0033_professionalprofile_legal_acceptance'),
    ]

    operations = [
        migrations.AddField(
            model_name='scheduledmeeting',
            name='professional_responded_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='scheduledmeeting',
            name='requested_by',
            field=models.CharField(
                choices=[('professional', 'Professional'), ('client', 'Client')],
                db_index=True,
                default='professional',
                max_length=16,
            ),
        ),
        migrations.AlterField(
            model_name='scheduledmeeting',
            name='status',
            field=models.CharField(
                choices=[
                    ('pending_approval', 'Pending professional approval'),
                    ('scheduled', 'Scheduled'),
                    ('cancelled', 'Cancelled'),
                    ('completed', 'Completed'),
                    ('declined', 'Declined'),
                ],
                db_index=True,
                default='scheduled',
                max_length=18,
            ),
        ),
    ]
