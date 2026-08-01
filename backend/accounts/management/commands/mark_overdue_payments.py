"""Flip open payment requests to 'overdue' once their due date passes.

Run on a schedule (cron / scheduled task). System-derived transition, so it
notifies both parties but writes no audit-log entry (there's no discrete user
action behind it).
"""

from django.core.management.base import BaseCommand
from django.utils import timezone

from accounts import payment_notifications, web_routes
from accounts.models import PaymentRequest


class Command(BaseCommand):
  help = "Mark payment requests overdue when their due date has passed."

  def add_arguments(self, parser):
    parser.add_argument('--quiet', action='store_true', help='Suppress notifications (status change only).')

  def handle(self, *args, **options):
    today = timezone.now().date()
    open_statuses = (
      PaymentRequest.STATUS_SENT,
      PaymentRequest.STATUS_VIEWED,
      PaymentRequest.STATUS_UNDER_REVIEW,
    )
    due = PaymentRequest.objects.filter(
      status__in=open_statuses, due_date__isnull=False, due_date__lt=today
    ).select_related('professional', 'client')

    count = 0
    for payment_request in due:
      payment_request.status = PaymentRequest.STATUS_OVERDUE
      payment_request.save(update_fields=['status', 'updated_at'])
      count += 1

      if options['quiet']:
        continue

      professional = payment_request.professional
      client = payment_request.client
      payment_notifications.notify_professional(
        professional,
        'payment_overdue',
        f'Payment overdue - {payment_request.request_id}',
        (
          f'The payment request "{payment_request.title}" for '
          f'{client.first_name or client.username} was due '
          f'{payment_request.due_date:%b %d, %Y} and has not been completed. '
          f'Review it here: {payment_notifications.request_link_for_professional(payment_request.request_id, payment_request.client_id)}'
        ),
        payload={
          'request_id': payment_request.request_id,
          'action_url': web_routes.professional_payment_request(payment_request.client_id, payment_request.request_id),
        },
      )
      if payment_request.client_visibility == 'visible':
        payment_notifications.notify_client(
          client,
          'payment_overdue',
          f'Payment overdue - {payment_request.title}',
          (
            f'Your payment "{payment_request.title}" '
            f'({payment_request.requested_amount} {payment_request.requested_currency}) was due '
            f'{payment_request.due_date:%b %d, %Y}. Please complete it or contact '
            f'{professional.first_name or professional.username}: '
            f'{payment_notifications.request_link_for_client(payment_request.request_id)}'
          ),
          payload={
            'request_id': payment_request.request_id,
            'action_url': web_routes.client_payment_request(payment_request.request_id),
          },
        )

    self.stdout.write(self.style.SUCCESS(f'Marked {count} payment request(s) overdue.'))
