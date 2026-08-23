from django.core.management.base import BaseCommand, CommandError
from accounts.account_lifecycle import (
    check_and_lock_overages,
    check_and_delete_data,
    send_overage_notifications,
)
from accounts.data_retention import purge_expired_client_data
from accounts.professional_deletion import process_expired_deletion_holds
from accounts.recycle_bin import purge_expired as purge_expired_recycle_bin
from admin_portal.models import ErrorLog
from django.conf import settings
from django.utils import timezone
from datetime import timedelta


class Command(BaseCommand):
    help = 'Check and process account lifecycle events: locks, deletions, notifications'

    def handle(self, *args, **options):
        self.stdout.write(self.style.SUCCESS('Starting account lifecycle checks...'))
        failures = []

        try:
            self.stdout.write('Checking for accounts to lock (over quota + grace expired)...')
            check_and_lock_overages()
            self.stdout.write(self.style.SUCCESS('[OK] Lock check complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Lock check failed: {e}'))
            failures.append(f'lock check: {e}')

        try:
            self.stdout.write('Sending overage notifications to accounts in grace period...')
            send_overage_notifications()
            self.stdout.write(self.style.SUCCESS('[OK] Notification send complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Notification send failed: {e}'))
            failures.append(f'notifications: {e}')

        try:
            self.stdout.write('Recycling accounts whose deletion hold has run out...')
            moved = process_expired_deletion_holds()
            self.stdout.write(self.style.SUCCESS(f'[OK] Deletion hold sweep complete ({moved} recycled)'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Deletion hold sweep failed: {e}'))
            failures.append(f'deletion holds: {e}')

        try:
            self.stdout.write('Moving 30-day frozen accounts to recycle and purging expired accounts...')
            check_and_delete_data()
            self.stdout.write(self.style.SUCCESS('[OK] Data deletion check complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Data deletion check failed: {e}'))
            failures.append(f'professional recycle/purge: {e}')

        try:
            self.stdout.write('Removing client chat/activity data past plan retention window...')
            purge_expired_client_data()
            self.stdout.write(self.style.SUCCESS('[OK] Data retention purge complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Data retention purge failed: {e}'))
            failures.append(f'data retention: {e}')

        try:
            self.stdout.write('Permanently removing Recycle Bin items past their restore window...')
            purge_expired_recycle_bin()
            self.stdout.write(self.style.SUCCESS('[OK] Recycle Bin purge complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Recycle Bin purge failed: {e}'))
            failures.append(f'item recycle purge: {e}')

        try:
            self.stdout.write('Removing diagnostic error logs past the configured retention window...')
            cutoff = timezone.now() - timedelta(days=settings.REPROOT_ERROR_LOG_RETENTION_DAYS)
            ErrorLog.objects.filter(last_seen_at__lt=cutoff).delete()
            self.stdout.write(self.style.SUCCESS('[OK] Error log retention purge complete'))
        except Exception as e:
            self.stdout.write(self.style.ERROR(f'[FAILED] Error log retention purge failed: {e}'))
            failures.append(f'error log retention: {e}')

        if failures:
            raise CommandError('Lifecycle processing failed: ' + '; '.join(failures))
        self.stdout.write(self.style.SUCCESS('All account lifecycle checks complete'))
