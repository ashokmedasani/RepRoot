from django.core.management.base import BaseCommand
from django.utils import timezone

from accounts.models import ProfessionalProfile
from accounts.subscription_cancellation import apply_due_cancellation


class Command(BaseCommand):
  help = 'Apply paid-plan cancellations whose effective date has passed.'

  def handle(self, *args, **options):
    processed = 0
    blocked = 0
    profiles = ProfessionalProfile.objects.select_related('user').filter(
      cancellation_effective_at__isnull=False,
      cancellation_effective_at__lte=timezone.now(),
    )
    for profile in profiles.iterator():
      if apply_due_cancellation(profile):
        processed += 1
      else:
        blocked += 1
    self.stdout.write(self.style.SUCCESS(
      f'Processed {processed} subscription cancellation(s); {blocked} remain blocked.'
    ))
