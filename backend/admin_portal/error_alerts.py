"""Human-readable operations alerts for captured errors.

Why this exists: ERROR_ALERT_EMAIL has been configured since the Test launch
but nothing ever read it, so no alert has ever been sent — every error lived
only in the Admin Portal console and had to be found by looking. This module
is the missing sender.

Design rules, in priority order:

1. **Answer the operator's questions first.** Who hit it, what page were they
   on, where did they come from, what did they click. Status codes and stack
   traces are debugging aids, not the headline, so they sit in a clearly
   fenced TECHNICAL DETAIL block at the bottom.
2. **Never break a request.** This is called from `record_error`, which is
   itself called from exception middleware. Every failure here is swallowed —
   an alert that raises would turn one error into two.
3. **Never flood the mailbox.** `record_error` already dedupes repeats of the
   same problem into one row, so only genuinely new problems reach here. On
   top of that a process-local hourly cap stops a cascade (one bad deploy
   throwing twenty distinct errors) from burying the inbox.
"""

import logging
import threading
from datetime import datetime, timedelta, timezone as dt_timezone

from django.conf import settings

logger = logging.getLogger(__name__)

# Alerts are worth sending for real failures only. A warning is something the
# app already handled; it belongs in the console, not in anyone's inbox.
ALERTABLE_LEVELS = ('error', 'fatal')

# Process-local burst guard. Deliberately not in the database: this is a
# blunt safety valve, not an audit trail, and it must not add a write to the
# error path. Worst case with multiple workers is one cap per worker, which
# is still bounded and still far better than unbounded.
_ALERT_CAP_PER_HOUR = 20
_alert_lock = threading.Lock()
_alert_window_started = None
_alert_window_count = 0


def _within_alert_budget():
  """True if we may send now. Also emits one 'further alerts suppressed'
  notice as the cap is crossed, so silence is never ambiguous."""
  global _alert_window_started, _alert_window_count

  now = datetime.now(dt_timezone.utc)
  with _alert_lock:
    if _alert_window_started is None or now - _alert_window_started > timedelta(hours=1):
      _alert_window_started = now
      _alert_window_count = 0

    _alert_window_count += 1
    if _alert_window_count <= _ALERT_CAP_PER_HOUR:
      return True, False
    # Exactly one notice on the transition, then silence for the rest of the hour.
    return False, _alert_window_count == _ALERT_CAP_PER_HOUR + 1


def _describe_reporter(log):
  if log.reporter_role == 'client':
    who = f'Client "{log.client_username or "unknown"}"'
    if log.professional_username:
      who += f' (under professional "{log.professional_username}")'
    if log.client_reference:
      who += f'\n  Client reference: {log.client_reference}'
    return who
  if log.reporter_role == 'professional':
    return f'Professional "{log.professional_username or "unknown"}"'
  return 'Signed-out visitor (not logged in)'


def _describe_device(log):
  """Turn a raw user-agent into something readable, keeping the original
  available underneath for when the summary is not enough."""
  agent = (log.device_info or '').strip()
  platform_label = {
    'web': 'Web browser', 'android': 'Android app', 'ios': 'iOS app',
  }.get(log.platform, 'Unknown platform')

  if not agent:
    return platform_label

  browser = ''
  for name, token in (
    ('Edge', 'Edg/'), ('Opera', 'OPR/'), ('Samsung Internet', 'SamsungBrowser/'),
    ('Chrome', 'Chrome/'), ('Firefox', 'Firefox/'), ('Safari', 'Version/'),
  ):
    if token in agent:
      browser = name
      break

  system = ''
  for name, token in (
    ('Windows', 'Windows NT'), ('macOS', 'Mac OS X'), ('Android', 'Android'),
    ('iPhone', 'iPhone'), ('iPad', 'iPad'), ('Linux', 'Linux'),
  ):
    if token in agent:
      system = name
      break

  summary = ' on '.join(part for part in (browser, system) if part)
  return f'{platform_label}{" — " + summary if summary else ""}'


def _human_action(context):
  """The breadcrumb the web app records on every click. Absent for older
  clients and for errors that happen without any interaction (a failed load
  on arrival), which is itself useful information — say so plainly."""
  action = str(context.get('last_action') or '').strip()
  if not action:
    return 'Not recorded (the error may have occurred on page load, before any interaction)'
  target = str(context.get('last_action_page') or '').strip()
  when = str(context.get('last_action_age_ms') or '').strip()
  detail = action
  if when.isdigit():
    seconds = int(when) / 1000
    detail += f' — {seconds:.1f}s before the error'
  if target and target != context.get('app_route'):
    detail += f' (on {target})'
  return detail


def _format_alert(log):
  context = log.context if isinstance(log.context, dict) else {}

  page = context.get('app_route') or log.request_path or 'Unknown'
  previous = context.get('previous_route') or ''
  online = context.get('online')

  when = log.first_seen_at or datetime.now(dt_timezone.utc)
  try:
    when_text = when.strftime('%d %b %Y at %H:%M:%S %Z').strip()
  except Exception:
    when_text = str(when)

  lines = [
    'WHAT HAPPENED',
    f'  {log.message}',
    '',
    'WHO HIT IT',
    f'  {_describe_reporter(log)}',
    '',
    'WHERE THEY WERE',
    f'  Page:          {page}',
    f'  Came from:     {previous or "No previous page in this session (direct arrival or first page)"}',
    f'  Last action:   {_human_action(context)}',
    '',
    'WHEN',
    f'  {when_text}',
    '',
    'DEVICE',
    f'  {_describe_device(log)}',
  ]

  if online is False:
    lines.append('  Connection:    Browser reported OFFLINE at the moment of the error')
  elif online is True:
    lines.append('  Connection:    Online')

  lines += [
    '',
    '=' * 62,
    'TECHNICAL DETAIL',
    '=' * 62,
    f'  Reference:     {log.error_id}',
    f'  Severity:      {log.get_level_display()}',
    f'  Origin:        {log.get_source_display()}',
  ]

  status_code = context.get('http_status')
  method = context.get('method')
  endpoint = context.get('api_endpoint')
  if status_code or endpoint:
    call = ' '.join(str(part) for part in (method, endpoint) if part)
    suffix = f' -> HTTP {status_code}' if status_code else ''
    lines.append(f'  Failed call:   {call}{suffix}')
    status_text = context.get('status_text')
    if status_text:
      lines.append(f'  Server said:   {status_text}')

  if log.app_version:
    lines.append(f'  App version:   {log.app_version}')

  extra = {
    key: value for key, value in context.items()
    if key not in {
      'app_route', 'previous_route', 'online', 'reported_at', 'last_action',
      'last_action_page', 'last_action_age_ms', 'http_status', 'method',
      'api_endpoint', 'status_text', 'current_page', 'category',
    }
  }
  if extra:
    lines.append('')
    lines.append('  Additional context:')
    for key, value in list(extra.items())[:15]:
      lines.append(f'    {key}: {str(value)[:200]}')

  if log.stack_trace:
    trace_lines = log.stack_trace.strip().splitlines()
    lines += ['', '  Stack trace (first 25 lines):']
    lines += [f'    {line[:200]}' for line in trace_lines[:25]]
    if len(trace_lines) > 25:
      lines.append(f'    ... {len(trace_lines) - 25} more lines in the Admin Portal console.')

  lines += [
    '',
    '-' * 62,
    f'Open the Admin Portal error console and search {log.error_id} for the',
    'full record, the occurrence count, and to mark it resolved.',
  ]

  # A subject that is scannable in a phone notification: severity, the page,
  # and the start of the message — not an opaque code.
  page_label = page if page and page != 'Unknown' else 'unknown page'
  subject = f'[RepRoot] {log.get_level_display()} on {page_label} — {_header_safe(log.message, 70)}'
  return subject, '\n'.join(lines)


def _header_safe(value, limit):
  """Collapse a message into something usable as an email Subject.

  Django raises BadHeaderError for any header containing a newline, and it
  raises it while *sending* — inside the background thread, after the alert has
  already been queued. So a single multi-line error message meant the alert
  about it was never delivered, and the only trace was a second traceback in
  the console.

  Database errors are the common case and are always multi-line: psycopg
  appends `LINE 1: ...` and a caret under the offending token. That detail is
  genuinely useful, but it belongs in the body — which already carries the full
  message — not in the subject.
  """
  collapsed = ' '.join(str(value or '').split())
  if len(collapsed) <= limit:
    return collapsed or 'no message'
  return collapsed[:limit].rstrip() + '…'


def send_error_alert(log):
  """Email one newly-recorded error to the operations mailbox.

  Called only for genuinely new problems — repeats are folded into the
  existing row by `record_error` and never reach here. Silent no-op when
  ERROR_ALERT_EMAIL is unset, so local and CI runs never try to send.
  """
  try:
    recipient = (getattr(settings, 'ERROR_ALERT_EMAIL', '') or '').strip()
    if not recipient:
      return
    if log.level not in ALERTABLE_LEVELS:
      return

    allowed, send_cap_notice = _within_alert_budget()

    # Local import: admin_portal must not import accounts at module load time.
    from accounts.email_utils import send_mail_background

    if not allowed:
      if send_cap_notice:
        send_mail_background(
          '[RepRoot] Error alerts paused — too many distinct errors this hour',
          (
            f'More than {_ALERT_CAP_PER_HOUR} distinct errors were recorded within an hour, '
            'so further alert emails are paused until the hour rolls over.\n\n'
            'This usually means a deploy or an outage rather than isolated bugs. '
            'Open the Admin Portal error console for the full list.\n\n'
            f'Most recent reference: {log.error_id}'
          ),
          settings.DEFAULT_FROM_EMAIL,
          [recipient],
        )
      return

    subject, body = _format_alert(log)
    send_mail_background(subject, body, settings.DEFAULT_FROM_EMAIL, [recipient])
  except Exception:  # noqa: BLE001 - an alert must never escalate the error it reports
    logger.exception('Error alert email could not be prepared or queued')
