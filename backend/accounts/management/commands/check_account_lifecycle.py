from django.core.management.base import BaseCommand
from accounts.account_lifecycle import (
    check_and_lock_overages,
    check_and_delete_data,
    send_overage_notifications,
)


class Command(BaseCommand):
    help = 'Check and process account lifecycle events: locks, deletions, notifications'

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS('Starting account lifecycle checks...'))

        try:
            self.stdout.write('Checking for accounts to lock (over quota + grace expired)...')
            check_and_lock_overages()
            self.stdout.write(self.style.SUCCESS('[OK] Lock check complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Lock check failed: {e}'))

        try:
            self.stdout.write('Sending overage notifications to accounts in grace period...')
            send_overage_notifications()
            self.stdout.write(self.style.SUCCESS('[OK] Notification send complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Notification send failed: {e}'))

        try:
            self.stdout.write('Checking for accounts to delete data (locked 30+ days)...')
            check_and_delete_data()
            self.stdout.write(self.style.SUCCESS('[OK] Data deletion check complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Data deletion check failed: {e}'))

        self.stdout.write(self.style.SUCCESS('All account lifecycle checks complete'))
