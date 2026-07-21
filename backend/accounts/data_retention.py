"""
Client data retention for the 3-tier billing system.

Chat messages and day-to-day client activity (tracking entries, progress
entries, reminders) are rolling operational data, not permanent records —
each plan tier keeps only a trailing window of it:
  - Starter Free / Pro: 60 days
  - Premium Unlimited:  180 days (6 months)

Only file-bearing chat messages (ones with an image) go through the Recycle
Bin when they expire — plain text messages, tracking entries, progress notes,
and reminders are deleted outright. They're high-volume, low-value operational
noise; the Bin is reserved for things actually worth the overhead of
restorability (see accounts/recycle_bin.py).

This is independent of account lifecycle deletion (account_lifecycle.py),
which erases everything after a frozen account goes unresolved for 30 days —
that stays a genuine hard delete; retention here is a rolling window, not
account abandonment.
"""

from datetime import timedelta

from django.utils import timezone

from accounts import recycle_bin
from accounts.models import ChatMessage, ClientReminder, ProfessionalProfile, ProgressEntry, RecycleBinItem, TrackingEntry
from accounts.plan_limits import professional_plan


def purge_expired_client_data():
  """Daily task: remove chat messages and client activity records older than
  each professional's plan retention window."""
  now = timezone.now()

  for profile in ProfessionalProfile.objects.select_related('user').iterator():
    professional = profile.user
    retention_days = professional_plan(professional).get('client_data_retention_days')
    if not retention_days:
      continue

    cutoff = now - timedelta(days=retention_days)

    stale_messages = ChatMessage.objects.filter(professional=professional, created_at__lt=cutoff)
    for message in stale_messages.exclude(image=''):
      recycle_bin.soft_delete_chat_message(message, deleted_by=RecycleBinItem.DELETED_BY_RETENTION_POLICY)
    stale_messages.filter(image='').delete()

    TrackingEntry.objects.filter(client__professional=professional, created_at__lt=cutoff).delete()
    ProgressEntry.objects.filter(professional=professional, created_at__lt=cutoff).delete()
    ClientReminder.objects.filter(professional=professional, date__lt=cutoff.date()).delete()
