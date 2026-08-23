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


def run_in_background(fn, *args, on_success=None, on_error=None, **kwargs):
  """Run `fn(*args, **kwargs)` on a daemon thread. Any exception is logged,
  never raised back to the caller — callers should not depend on this
  completing before they return a response."""

  def _target():
    try:
      result = fn(*args, **kwargs)
      if on_success:
        on_success(result)
    except Exception as exc:  # noqa: BLE001 - best-effort background send, always log
      if on_error:
        try:
          on_error(exc)
        except Exception:  # noqa: BLE001 - tracking must not hide the original failure
          logger.exception('Background task failure callback failed')
      logger.exception('Background email send failed')

  thread = threading.Thread(target=_target, daemon=True)
  thread.start()
  return thread


def sanitize_subject(subject, limit=200):
  """Fold a subject into a single line that Django will accept as a header.

  Django refuses any header containing a newline (BadHeaderError) — and it
  refuses at *send* time, on the background thread, long after the caller has
  returned. So a subject built from text that happened to be multi-line failed
  silently: no email, just a traceback in the log.

  This is also the standard header-injection guard. A subject assembled from
  anything a user can influence (a name, a support ticket title, a server error
  message) must never be able to introduce `Bcc:` by embedding a newline.
  """
  collapsed = ' '.join(str(subject or '').split())
  if not collapsed:
    return '(no subject)'
  if len(collapsed) <= limit:
    return collapsed
  return collapsed[:limit].rstrip() + '…'


def send_mail_background(
  subject, message, from_email, recipient_list, *, on_success=None, on_error=None, **kwargs
):
  """Fire-and-forget wrapper around django.core.mail.send_mail. Returns
  immediately; the actual send happens on a background thread so a slow or
  unreachable mail server never blocks the request."""
  kwargs.setdefault('fail_silently', False)
  return run_in_background(
    _django_send_mail,
    # Every background email goes through here, so this is the one place that
    # can guarantee no caller can produce an unsendable header.
    sanitize_subject(subject),
    message,
    from_email,
    recipient_list,
    on_success=on_success,
    on_error=on_error,
    **kwargs,
  )
