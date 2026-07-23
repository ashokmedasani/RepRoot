from django.core.mail import send_mail
from django.core.management.base import BaseCommand

from accounts.models import ActivityNotification, NotificationDeliveryAttempt


class Command(BaseCommand):
  help = 'Deliver queued immediate notification emails. Safe to run repeatedly from a scheduler.'

  def add_arguments(self, parser):
    parser.add_argument('--limit', type=int, default=100)

  def handle(self, *args, **options):
    delivered = failed = 0
    rows = ActivityNotification.objects.filter(email_status='pending').select_related('recipient_professional', 'recipient_client')[:max(1, options['limit'])]
    for row in rows:
      recipient = row.recipient_professional if row.recipient_type == 'professional' else row.recipient_client
      email = getattr(recipient, 'email', '') if recipient else ''
      if not email:
        row.email_status = 'suppressed'
        row.save(update_fields=['email_status', 'updated_at'])
        continue
      try:
        send_mail(row.title, row.body, None, [email], fail_silently=False)
        row.email_status = 'sent'
        NotificationDeliveryAttempt.objects.create(notification=row, channel='email', status='sent')
        delivered += 1
      except Exception as exc:  # a delivery outage must not lose the notification
        row.email_status = 'failed'
        NotificationDeliveryAttempt.objects.create(notification=row, channel='email', status='failed', error=str(exc)[:2000])
        failed += 1
      row.save(update_fields=['email_status', 'updated_at'])
    self.stdout.write(self.style.SUCCESS(f'Delivered {delivered}; failed {failed}.'))
