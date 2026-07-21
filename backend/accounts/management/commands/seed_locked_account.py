"""
Seed a test account that is already locked (frozen).
Useful for testing feature lockdown, lock banners, and account reactivation on upgrade.
"""

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta
from accounts.models import ProfessionalProfile

User = get_user_model()


class Command(BaseCommand):
    help = 'Seed a test account that is already locked (frozen)'

    def add_arguments(self, parser):
        parser.add_argument(
            '--email',
            default='test-locked@reproot.local',
            help='Email for test account'
        )
        parser.add_argument(
            '--username',
            default='testlocked',
            help='Username for test account'
        )
        parser.add_argument(
            '--lock-reason',
            default='overage_grace_expired',
            choices=['overage_grace_expired', 'overage'],
            help='Reason for account lock'
        )

    def handle(self, *args, **options):
        email = options['email']
        username = options['username']
        lock_reason = options['lock_reason']

        user, created = User.objects.get_or_create(
            username=username,
            defaults={
                'email': email,
                'first_name': 'Test',
                'last_name': 'Locked',
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

        # Set account to locked state
        profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
        profile.is_locked = True
        profile.locked_at = now - timedelta(days=5)  # Locked 5 days ago
        profile.lock_reason = lock_reason
        profile.downgraded_at = now - timedelta(days=12)
        profile.grace_period_ends_at = None
        profile.save()

        self.stdout.write(
            self.style.SUCCESS(
                f'\n[OK] Seeded locked test account:\n'
                f'  Email: {email}\n'
                f'  Username: {username}\n'
                f'  Plan: Starter Free\n'
                f'  Status: LOCKED (frozen)\n'
                f'  Lock reason: {lock_reason}\n'
                f'  Locked at: {profile.locked_at.strftime("%Y-%m-%d %H:%M:%S")}\n'
                f'  Created: {created}\n'
                f'\n  Effects:\n'
                f'    - Cannot add clients, forms, templates\n'
                f'    - Cannot edit client profiles\n'
                f'    - Cannot send chat messages\n'
                f'    - Cannot upload references\n'
                f'    - Lock banner visible on all pages\n'
                f'    - Upgrade to Pro/Premium to unlock\n'
            )
        )
