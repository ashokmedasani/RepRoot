from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token

from accounts.models import ClientAuthToken, LegalDocumentRelease


class Command(BaseCommand):
    help = 'Invalidate all portal sessions once when the published legal-document version changes.'

    def handle(self, *args, **options):
        with transaction.atomic():
            professional_changed, professional_count = self._enforce_release(
                singleton_key=1,
                current=settings.REPROOT_PROFESSIONAL_LEGAL_VERSION,
                token_model=Token,
            )
            client_changed, client_count = self._enforce_release(
                singleton_key=2,
                current=settings.REPROOT_CLIENT_LEGAL_VERSION,
                token_model=ClientAuthToken,
            )

        if not professional_changed and not client_changed:
            self.stdout.write('Legal document versions unchanged; sessions preserved.')
            return
        if professional_changed:
            self.stdout.write(self.style.SUCCESS(
                f'Professional legal version changed to {settings.REPROOT_PROFESSIONAL_LEGAL_VERSION}; '
                f'invalidated {professional_count} professional token records.'
            ))
        if client_changed:
            self.stdout.write(self.style.SUCCESS(
                f'Client legal version changed to {settings.REPROOT_CLIENT_LEGAL_VERSION}; '
                f'invalidated {client_count} client token records.'
            ))

    @staticmethod
    def _enforce_release(*, singleton_key, current, token_model):
        release, _ = LegalDocumentRelease.objects.select_for_update().get_or_create(
            singleton_key=singleton_key,
            defaults={'legal_document_version': current},
        )
        if release.legal_document_version == current:
            return False, 0
        deleted_count, _ = token_model.objects.all().delete()
        release.legal_document_version = current
        release.activated_at = timezone.now()
        release.save(update_fields=['legal_document_version', 'activated_at'])
        return True, deleted_count
