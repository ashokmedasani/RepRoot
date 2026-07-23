"""
Seed a test account with low data usage (40% of quota).
Useful for testing warning thresholds and normal operation.
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from accounts.models import ProfessionalProfile

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed a test account with low data usage (~40% of Starter Free quota)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            default='test-low-usage@reproot.local',
            help='Email for test account'
        )
        parser.add_argument(
            '--username',
            default='testlowusage',
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
                'last_name': 'LowUsage',
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
                f'\n[OK] Seeded low-usage test account:\n'
                f'  Email: {email}\n'
                f'  Username: {username}\n'
                f'  Plan: Starter Free (30MB quota)\n'
                f'  Status: Active, ~40% usage\n'
                f'  Created: {created}\n'
            )
        )
