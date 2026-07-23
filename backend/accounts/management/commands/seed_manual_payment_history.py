"""
Seeds ~6 months of biweekly manual-payment history for one existing client of
an existing professional, so the payments UI (professional side and client
side) has something realistic to render while testing.

Deliberately manual-payments only (no Stripe/integrated accounts touched),
one currency throughout, and one payment mostly-paid history with two
exceptions: the most recent cycle is left pending (still owed) and one
mid-history cycle is left overdue/unpaid (a client who skipped a payment).
"""

from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand, CommandError
from django.contrib.auth import get_user_model
from django.utils import timezone

from accounts.models import (
  ClientAccess,
  ManualPaymentProfile,
  PaymentProof,
  PaymentRecord,
  PaymentRequest,
  PaymentRequestAllowedMethod,
  ProfessionalPaymentSettings,
)

User = get_user_model()

CYCLE_COUNT = 13  # every 2 weeks for ~6 months
CYCLE_DAYS = 14
AMOUNT = Decimal('150.00')
CURRENCY = 'USD'


class Command(BaseCommand):
  help = 'Seed ~6 months of biweekly manual payment history for one client of an existing professional.'

  def add_arguments(self, parser):
    parser.add_argument('--professional', default='maya_coach', help='Professional username to seed payments for.')
    parser.add_argument('--client', default=None, help='Client username to seed. Defaults to the professional\'s first client.')

  def handle(self, *args, **options):
    professional = User.objects.filter(username=options['professional']).first()
    if professional is None:
      raise CommandError(f'No professional found with username "{options["professional"]}".')

    client_username = options['client']
    client = (
      ClientAccess.objects.filter(professional=professional, username=client_username).first()
      if client_username
      else ClientAccess.objects.filter(professional=professional).order_by('id').first()
    )
    if client is None:
      raise CommandError(f'No client found for professional "{professional.username}".')

    settings_row, _ = ProfessionalPaymentSettings.objects.get_or_create(
      professional=professional,
      defaults={'reporting_currency': CURRENCY, 'payment_tracking_enabled': True, 'client_payment_history_enabled': True},
    )
    if settings_row.reporting_currency != CURRENCY:
      settings_row.reporting_currency = CURRENCY
      settings_row.save(update_fields=['reporting_currency'])

    method, created = ManualPaymentProfile.objects.get_or_create(
      professional=professional,
      category='zelle',
      defaults={
        'name': 'Zelle',
        'display_label': 'US Zelle',
        'supported_currencies': [],
        'status': ManualPaymentProfile.STATUS_ACTIVE,
      },
    )

    today = timezone.now().date()
    # Oldest cycle first: 182 days ago, stepping forward by 14 days to 14 days ago.
    due_dates = [today - timedelta(days=CYCLE_DAYS * (CYCLE_COUNT - i)) for i in range(CYCLE_COUNT)]

    skipped_index = 3  # one cycle ~140 days ago never gets paid (overdue)
    pending_index = CYCLE_COUNT - 1  # the most recent cycle is still awaiting payment

    created_requests = 0
    created_records = 0

    for i, due_date in enumerate(due_dates):
      title = f'Biweekly training — week of {due_date.strftime("%b %d, %Y")}'
      sent_date = due_date - timedelta(days=3)
      sent_at = timezone.make_aware(timezone.datetime.combine(sent_date, timezone.datetime.min.time()))

      payment_request = PaymentRequest.objects.create(
        professional=professional,
        client=client,
        title=title,
        description='Recurring biweekly coaching fee.',
        requested_amount=AMOUNT,
        requested_currency=CURRENCY,
        due_date=due_date,
        payment_type='manual',
        status=PaymentRequest.STATUS_SENT,
        client_visibility='visible',
        sent_at=sent_at,
      )
      PaymentRequest.objects.filter(id=payment_request.id).update(created_at=sent_at)
      PaymentRequestAllowedMethod.objects.create(payment_request=payment_request, manual_payment_profile=method)
      created_requests += 1

      if i == pending_index:
        # Client has viewed it but hasn't paid yet — the "current" open cycle.
        viewed_at = sent_at + timedelta(days=1)
        PaymentRequest.objects.filter(id=payment_request.id).update(status=PaymentRequest.STATUS_VIEWED, viewed_at=viewed_at)
        continue

      if i == skipped_index:
        # A payment the client tried to skip: request went overdue, never paid.
        PaymentRequest.objects.filter(id=payment_request.id).update(status=PaymentRequest.STATUS_OVERDUE)
        continue

      # Everything else: fully paid, a couple of days after the due date.
      paid_date = due_date + timedelta(days=2)
      paid_at = timezone.make_aware(timezone.datetime.combine(paid_date, timezone.datetime.min.time()))
      viewed_at = sent_at + timedelta(days=1)

      proof = PaymentProof.objects.create(
        payment_request=payment_request,
        submitted_by=client.username,
        transaction_reference=f'ZELLE-{payment_request.request_id}',
        reported_amount=AMOUNT,
        reported_currency=CURRENCY,
        reported_payment_date=paid_date,
        payment_method=method,
        note='Paid via Zelle.',
        confirmed_accurate=True,
        status=PaymentProof.STATUS_ACCEPTED,
      )
      PaymentProof.objects.filter(id=proof.id).update(submitted_at=paid_at, reviewed_at=paid_at)

      record = PaymentRecord.objects.create(
        professional=professional,
        client=client,
        payment_request=payment_request,
        original_amount=AMOUNT,
        original_currency=CURRENCY,
        reporting_amount=AMOUNT,
        reporting_currency=CURRENCY,
        exchange_rate_source='manual',
        payment_method=method,
        transaction_reference=proof.transaction_reference,
        received_date=paid_date,
        status=PaymentRecord.STATUS_COMPLETED,
        client_visibility='visible',
        verified_by=professional,
        verified_at=paid_at,
      )
      PaymentRecord.objects.filter(id=record.id).update(created_at=paid_at)
      created_records += 1

      PaymentRequest.objects.filter(id=payment_request.id).update(
        status=PaymentRequest.STATUS_COMPLETED, viewed_at=viewed_at, completed_at=paid_at
      )

      from admin_portal.models import FinanceLedgerEntry

      FinanceLedgerEntry.objects.create(
        entry_type=FinanceLedgerEntry.TYPE_PAYMENT,
        status=FinanceLedgerEntry.STATUS_COMPLETED,
        amount=record.reporting_amount,
        currency=record.reporting_currency,
        professional=professional,
        description=f'Client payment {record.payment_record_id}',
        external_reference=record.transaction_reference,
        occurred_at=paid_at,
      )

    self.stdout.write(
      self.style.SUCCESS(
        f'\nSeeded payment history for {professional.username} <-> {client.username}:\n'
        f'  {created_requests} payment requests over {CYCLE_COUNT * CYCLE_DAYS // 7} weeks\n'
        f'  {created_records} completed payment records ({AMOUNT} {CURRENCY} each)\n'
        f'  1 overdue/unpaid request (cycle {skipped_index + 1} of {CYCLE_COUNT})\n'
        f'  1 pending request awaiting payment (most recent, due {due_dates[pending_index]})\n'
        f'  Manual payment method used: {method.display_label} ({"created" if created else "reused existing"})\n'
      )
    )
