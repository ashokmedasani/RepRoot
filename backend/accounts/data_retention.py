"""
Client data retention for the 3-tier billing system.

Chat messages and day-to-day client activity (tracking entries, progress
entries, reminders) are rolling operational data, not permanent records —
each plan tier keeps only a trailing window of it:
  - Starter Free / Pro: 60 days
  - Premium Unlimited:  180 days (6 months)

This is independent of account lifecycle deletion (account_lifecycle.py),
which erases everything after a frozen account goes unresolved for 30 days.
Retention purges run continuously for every active professional regardless
of lock state.
"""

from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from accounts.models import ChatMessage, ClientReminder, ProfessionalProfile, ProgressEntry, TrackingEntry
from accounts.plan_limits import professional_plan


def purge_expired_client_data():
  """
  Daily task: delete chat messages and client activity records older than
  the professional's plan retention window.
  """
  now = timezone.now()

  for profile in ProfessionalProfile.objects.select_related('user').iterator():
    professional = profile.user
    retention_days = professional_plan(professional).get('client_data_retention_days')
    if not retention_days:
      continue

    cutoff = now - timedelta(days=retention_days)

    ChatMessage.objects.filter(professional=professional, created_at__lt=cutoff).delete()
    TrackingEntry.objects.filter(client__professional=professional, created_at__lt=cutoff).delete()
    ProgressEntry.objects.filter(professional=professional, created_at__lt=cutoff).delete()
    ClientReminder.objects.filter(professional=professional, date__lt=cutoff.date()).delete()
