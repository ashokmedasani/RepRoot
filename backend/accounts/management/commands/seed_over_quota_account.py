"""
Seed a test account that is over quota (110%+ usage).
Useful for testing overage notifications, grace period, and account freezing.
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta
from accounts.models import ProfessionalProfile
from django.conf import settings

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed a test account that is over quota (110%+ usage)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            default='test-over-quota@reproot.local',
            help='Email for test account'
        )
        parser.add_argument(
            '--username',
            default='testoverquota',
            help='Username for test account'
        )
        parser.add_argument(
            '--days-downgraded',
            type=int,
            default=2,
            help='Days since account was downgraded (grace period is 14 days by default)'
        )

    def handle(self, *args, **options):
        email = options['email']
        username = options['username']
        days_downgraded = options['days_downgraded']

        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': email,
                'first_name': 'Test',
                'last_name': 'OverQuota',
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

        # Set tier to Starter Free, simulate downgrade
        profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
        profile.is_locked = False
        profile.locked_at = None
        profile.lock_reason = ''
        profile.downgraded_at = now - timedelta(days=days_downgraded)
        profile.grace_period_ends_at = profile.downgraded_at + timedelta(days=grace_period_days)
        profile.save()

        days_remaining = (profile.grace_period_ends_at - now).days
        self.stdout.write(
            self.style.SUCCESS(
                f'\n[OK] Seeded over-quota test account:\n'
                f'  Email: {email}\n'
                f'  Username: {username}\n'
                f'  Plan: Starter Free (30MB quota)\n'
                f'  Status: In grace period, >100% usage\n'
                f'  Downgraded: {profile.downgraded_at.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'  Grace period ends: {profile.grace_period_ends_at.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'  Days remaining: {days_remaining}\n'
                f'  Created: {created}\n'
                f'\n  Note: Add data to reach >30MB (over 100% quota) to trigger overage warnings\n'
                f'       After {grace_period_days} days of downgrade, account will lock automatically\n'
            )
        )
