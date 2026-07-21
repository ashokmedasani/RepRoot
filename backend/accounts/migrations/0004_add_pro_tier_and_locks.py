# Generated migration for 3-tier billing system with account lifecycle

from django.db import migrations, models


def backfill_plan_tiers(apps, schema_editor):
    """Migrate existing plan_tier values to new 3-tier system."""
    ProfessionalProfile = apps.get_model('accounts', 'ProfessionalProfile')

    # Migrate old 'starter' to 'starter_free'
    ProfessionalProfile.objects.filter(plan_tier='starter').update(plan_tier='starter_free')

    # Migrate old 'premium' to 'premium_unlimited'
    ProfessionalProfile.objects.filter(plan_tier='premium').update(plan_tier='premium_unlimited')


def reverse_backfill_plan_tiers(apps, schema_editor):
    """Reverse data migration (optional)."""
    ProfessionalProfile = apps.get_model('accounts', 'ProfessionalProfile')
    ProfessionalProfile.objects.filter(plan_tier='starter_free').update(plan_tier='starter')
    ProfessionalProfile.objects.filter(plan_tier='premium_unlimited').update(plan_tier='premium')


class Migration(migrations.Migration):

    dependencies = [
        ('accounts', '0003_payment_tracking_toggle'),
    ]

    operations = [
        # Add new fields for account lifecycle tracking
        migrations.AddField(
            model_name='professionalprofile',
            name='is_locked',
            field=models.BooleanField(default=False, db_index=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='locked_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='lock_reason',
            field=models.CharField(
                blank=True,
                help_text="'overage' or 'downgrade_grace_expired'",
                max_length=100,
            ),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='downgraded_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='grace_period_ends_at',
            field=models.DateTimeField(blank=True, db_index=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='usage_warning_acknowledged_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='professionalprofile',
            name='last_overage_notification_sent_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        # Alter the plan_tier field to accept new tier choices and set default to 'starter_free'
        migrations.AlterField(
            model_name='professionalprofile',
            name='plan_tier',
            field=models.CharField(
                choices=[
                    ('starter_free', 'Starter Free'),
                    ('pro', 'Pro'),
                    ('premium_unlimited', 'Premium Unlimited'),
                    ('starter', 'Starter (Legacy)'),
                    ('premium', 'Premium (Legacy)'),
                ],
                db_index=True,
                default='starter_free',
                max_length=20,
            ),
        ),
        # Data migration: Backfill existing plan_tier values
        migrations.RunPython(backfill_plan_tiers, reverse_backfill_plan_tiers),
    ]
