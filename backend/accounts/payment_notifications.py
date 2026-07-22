"""In-app + email notifications for the Client Payments module.

Single entry point (`notify`) mirroring admin_portal's record_error() pattern:
every payment event calls notify(), which inserts a PaymentNotification row
(for the nav badge) and sends a plain-text email via Django's send_mail —
the same email style email_verification.py already uses. Email failures are
swallowed so a broken SMTP config never blocks a payment action.
"""

import logging

from django.conf import settings
from django.core.mail import send_mail

from .models import PaymentNotification
from .notifications import notify_client as notify_shared_client, notify_professional as notify_shared_professional

logger = logging.getLogger(__name__)


def _frontend_link(path):
  base = settings.REPROOT_FRONTEND_URL.rstrip('/')
  return f'{base}{path}'


def notify_professional(professional, notif_type, title, body, payload=None, email=True):
  PaymentNotification.objects.create(
    recipient_type='professional',
    recipient_professional=professional,
    notif_type=notif_type,
    title=title[:200],
    body=body,
    payload=payload or {},
  )
  notify_shared_professional(professional, category='payments', event_type=notif_type,
    title=title,
    body=body, action_url=(payload or {}).get('action_url', '/professional/payments'), payload=payload or {}, requires_action=True)


def notify_client(client, notif_type, title, body, payload=None, email=True):
  PaymentNotification.objects.create(
    recipient_type='client',
    recipient_client=client,
    notif_type=notif_type,
    title=title[:200],
    body=body,
    payload=payload or {},
  )
  notify_shared_client(client, category='payments', event_type=notif_type,
    title=title,
    body=body, action_url=(payload or {}).get('action_url', '/client/payments'), payload=payload or {})


def _send(recipient, subject, body):
  try:
    send_mail(
      subject=subject,
      message=body,
      from_email=None,
      recipient_list=[recipient],
      fail_silently=False,
    )
  except Exception:  # noqa: BLE001 - notification emails must never break the payment flow
    logger.exception('Payment notification email failed for %s', recipient)


def request_link_for_client(request_id):
  return _frontend_link(f'/client/payments/requests/{request_id}')


def request_link_for_professional(request_id):
  return _frontend_link(f'/professional/payments/requests/{request_id}')
