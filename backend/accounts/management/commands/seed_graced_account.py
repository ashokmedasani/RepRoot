"""
Seed a test account that is in the downgrade grace period.
Useful for testing grace period UI, countdown timers, and overage notifications.
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta
from accounts.models import ProfessionalProfile
from django.conf import settings

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed a test account that is in downgrade grace period'

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            default='test-graced@reproot.local',
            help='Email for test account'
        )
        parser.add_argument(
            '--username',
            default='testgraced',
            help='Username for test account'
        )
        parser.add_argument(
            '--day-of-grace',
            type=int,
            default=3,
            help='Which day of grace period (1-7, where 7 is last day)'
        )

    def handle(self, *args, **options):
        email = options['email']
        username = options['username']
        day_of_grace = max(1, min(7, options['day_of_grace']))

        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': email,
                'first_name': 'Test',
                'last_name': 'Graced',
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

        now = timezone.now()
        grace_period_days = settings.REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS
        days_since_downgrade = grace_period_days - day_of_grace

        # Set account to grace period state
        profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
        profile.is_locked = False
        profile.locked_at = None
        profile.lock_reason = ''
        profile.downgraded_at = now - timedelta(days=days_since_downgrade)
        profile.grace_period_ends_at = profile.downgraded_at + timedelta(days=grace_period_days)
        profile.save()

        days_remaining = day_of_grace
        self.stdout.write(
            self.style.SUCCESS(
                f'\n[OK] Seeded grace-period test account:\n'
                f'  Email: {email}\n'
                f'  Username: {username}\n'
                f'  Plan: Starter Free\n'
                f'  Status: In grace period (downgraded)\n'
                f'  Day of grace: {day_of_grace}/{grace_period_days}\n'
                f'  Downgraded: {profile.downgraded_at.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'  Grace period ends: {profile.grace_period_ends_at.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'  Days remaining: {days_remaining}\n'
                f'  Created: {created}\n'
                f'\n  Effects:\n'
                f'    - All premium features are LOCKED\n'
                f'    - Data remains but inaccessible\n'
                f'    - Grace period countdown visible\n'
                f'    - If over 100%: daily overage notifications sent\n'
                f'    - Upgrade to Pro/Premium to unlock immediately\n'
                f'    - Or delete data to come under 100% quota\n'
            )
        )
