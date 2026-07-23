"""
Shared helpers for sending email without blocking the HTTP request.

Root cause this exists to fix: several views called Django's `send_mail` /
`EmailMessage.send()` directly and synchronously inside the request-response
cycle (e.g. client password reset, client credential emails, meeting invite
.ics emails). If the configured SMTP host is slow, unreachable, or has bad
credentials, that call can hang for a long time (well beyond a typical page
load), freezing the request — and, from the browser's point of view, the
whole tab — with no error and no way out for the user.

The account/database changes that trigger these emails are always committed
*before* the email is attempted, so the email itself is a "nice to have"
notification, not something the request should ever wait on. Everything here
sends on a background daemon thread and swallows/logs failures instead of
propagating them, so a slow or broken mail server can never block a request
again.
"""

import logging
import threading

from django.core.mail import send_mail as _django_send_mail

logger = logging.getLogger(__name__)


def run_in_background(fn, *args, **kwargs):
  """Run `fn(*args, **kwargs)` on a daemon thread. Any exception is logged,
  never raised back to the caller — callers should not depend on this
  completing before they return a response."""

  def _target():
    try:
      fn(*args, **kwargs)
    except Exception:  # noqa: BLE001 - best-effort background send, always log
      logger.exception('Background email send failed')

  thread = threading.Thread(target=_target, daemon=True)
  thread.start()
  return thread


def send_mail_background(subject, message, from_email, recipient_list, **kwargs):
  """Fire-and-forget wrapper around django.core.mail.send_mail. Returns
  immediately; the actual send happens on a background thread so a slow or
  unreachable mail server never blocks the request."""
  kwargs.setdefault('fail_silently', False)
  return run_in_background(_django_send_mail, subject, message, from_email, recipient_list, **kwargs)
