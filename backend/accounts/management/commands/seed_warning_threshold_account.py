"""
Seed a test account at the 75% usage warning threshold.
Useful for testing warning banners and upgrade prompts.
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from accounts.models import ProfessionalProfile

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed a test account at 75% usage warning threshold'

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            default='test-warning-threshold@reproot.local',
            help='Email for test account'
        )
        parser.add_argument(
            '--username',
            default='testwarningthreshold',
            help='Username for test account'
        )

    def handle(self, *args, **options):
        email = options['email']
        username = options['username']

        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': email,
                'first_name': 'Test',
                'last_name': 'WarningThreshold',
            }
        )

        if not created:
            self.stdout.write(self.style.WARNING(f'User {username} already exists'))

        profile, profile_created = ProfessionalProfile.objects.get_or_create(
            user=user,
            defaults={
                'plan_tier': ProfessionalProfile.PLAN_STARTER_FREE,
            }
        )

        # Set tier to Starter Free
        profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
        profile.is_locked = False
        profile.locked_at = None
        profile.lock_reason = ''
        profile.downgraded_at = None
        profile.grace_period_ends_at = None
        profile.save()

        self.stdout.write(
            self.style.SUCCESS(
                f'\n[OK] Seeded warning-threshold test account:\n'
                f'  Email: {email}\n'
                f'  Username: {username}\n'
                f'  Plan: Starter Free (30MB quota)\n'
                f'  Status: Active, ~75% usage (warning threshold)\n'
                f'  Created: {created}\n'
                f'\n  Note: Add data to this account to reach ~22.5MB to trigger warning banner\n'
            )
        )
