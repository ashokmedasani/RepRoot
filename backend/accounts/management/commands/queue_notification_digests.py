from datetime import timedelta

from django.core.management.base import BaseCommand
from django.db.models import Count
from django.utils import timezone

from accounts.models import ActivityNotification, NotificationPreference


class Command(BaseCommand):
  help = 'Queue daily, weekly or monthly email summaries from notification preferences.'

  def add_arguments(self, parser):
    parser.add_argument('frequency', choices=['daily', 'weekly', 'monthly'])

  def handle(self, *args, **options):
    frequency = options['frequency']
    days = {'daily': 1, 'weekly': 7, 'monthly': 31}[frequency]
    since = timezone.now() - timedelta(days=days)
    queued = 0
    preferences = NotificationPreference.objects.filter(email_enabled=True, digest_frequency=frequency)
    recipients = {}
    for pref in preferences.select_related('recipient_professional', 'recipient_client'):
      recipient = pref.recipient_professional if pref.recipient_type == 'professional' else pref.recipient_client
      recipients.setdefault((pref.recipient_type, recipient.pk), {'recipient': recipient, 'categories': set()})['categories'].add(pref.category)
    period = timezone.localdate().isoformat()
    for (recipient_type, recipient_id), config in recipients.items():
      target_key = 'recipient_professional_id' if recipient_type == 'professional' else 'recipient_client_id'
      counts = ActivityNotification.objects.filter(recipient_type=recipient_type, created_at__gte=since, category__in=config['categories'], **{target_key: recipient_id}).values('category').annotate(total=Count('id'))
      summary = {row['category']: row['total'] for row in counts}
      if not summary:
        continue
      target = {'recipient_professional': config['recipient']} if recipient_type == 'professional' else {'recipient_client': config['recipient']}
      _, created = ActivityNotification.objects.get_or_create(event_key=f'digest:{frequency}:{recipient_type}:{recipient_id}:{period}', defaults={
        'recipient_type': recipient_type, 'category': 'system', 'event_type': f'digest.{frequency}',
        'title': f'Your RepRoot {frequency} activity summary',
        'body': ', '.join(f'{category}: {count}' for category, count in sorted(summary.items())),
        'payload': {'frequency': frequency, 'counts': summary, 'period_ending': period},
        'action_url': '/professional/dashboard' if recipient_type == 'professional' else '/client/dashboard',
        'email_status': 'pending', 'push_status': 'suppressed', **target,
      })
      queued += int(created)
    self.stdout.write(self.style.SUCCESS(f'Queued {queued} {frequency} digest(s).'))
