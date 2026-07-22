"""Operational-data visibility and permanent-retention enforcement.

Plans expose a trailing history window of 60, 90, or 180 days. Hidden history
remains stored, counts toward storage, and becomes visible again after an
upgrade while it is still inside the universal 180-day maximum.

After 180 days, operational records and payment proof files are permanently
removed. Core payment records remain available for the life of the account.
Account lifecycle deletion is handled separately by account_lifecycle.py.
"""

from datetime import timedelta

from django.utils import timezone

from django.conf import settings
from django.core.files.storage import default_storage

from accounts.models import (
  ChatMessage, ClientReminder, PaymentAuditLog, PaymentNotification, PaymentProof,
  PaymentRecord, ProfessionalProfile, ProgressEntry, TrackingEntry,
)
from accounts.plan_limits import professional_plan


def visible_client_data_cutoff(professional):
  """Plan window controls visibility; records remain recoverable until day 180."""
  days = professional_plan(professional).get('client_data_retention_days') or 180
  return timezone.now() - timedelta(days=days)


def purge_expired_client_data():
  """Permanently remove operational data only after the universal 180-day maximum."""
  now = timezone.now()
  cutoff = now - timedelta(days=settings.REPROOT_OPERATIONAL_DATA_MAX_DAYS)

  for profile in ProfessionalProfile.objects.select_related('user').iterator():
    professional = profile.user
    stale_messages = ChatMessage.objects.filter(professional=professional, created_at__lt=cutoff)
    for message in stale_messages.exclude(image=''):
      if message.image and default_storage.exists(message.image.name):
        default_storage.delete(message.image.name)
    stale_messages.delete()

    TrackingEntry.objects.filter(client__professional=professional, created_at__lt=cutoff).delete()
    ProgressEntry.objects.filter(professional=professional, created_at__lt=cutoff).delete()
    ClientReminder.objects.filter(professional=professional, date__lt=cutoff.date()).delete()

    # Core payment requests/records and immutable audits remain. Only transient
    # notifications and proof files expire at 180 days.
    PaymentNotification.objects.filter(
      recipient_professional=professional, created_at__lt=cutoff
    ).delete()
    PaymentNotification.objects.filter(
      recipient_client__professional=professional, created_at__lt=cutoff
    ).delete()
    for proof in PaymentProof.objects.filter(
      payment_request__professional=professional, submitted_at__lt=cutoff
    ).exclude(proof_file=''):
      path = proof.proof_file.name
      if path and default_storage.exists(path):
        default_storage.delete(path)
      proof.proof_file = None
      proof.save(update_fields=['proof_file'])
      PaymentAuditLog.objects.create(
        action='proof_expired', professional=professional, client=proof.payment_request.client,
        payment_request=proof.payment_request, changed_by='retention-policy',
        reason='Payment proof file removed after the 180-day operational-data maximum.',
      )
    for record in PaymentRecord.objects.filter(
      professional=professional, created_at__lt=cutoff
    ).exclude(proof_file=''):
      path = record.proof_file.name
      if path and default_storage.exists(path):
        default_storage.delete(path)
      record.proof_file = None
      record.save(update_fields=['proof_file'])
      PaymentAuditLog.objects.create(
        action='proof_expired', professional=professional, client=record.client,
        payment_request=record.payment_request, payment_record=record,
        changed_by='retention-policy',
        reason='Payment proof file removed after the 180-day operational-data maximum.',
      )
