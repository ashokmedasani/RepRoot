"""Email notifications for support incidents and professional onboarding."""

import logging
from html import escape

from django.conf import settings
from django.utils import timezone

from .email_utils import send_mail_background

logger = logging.getLogger(__name__)


def _mark_delivery(incident_pk: int, field: str, delivery_status: str, error: str = '') -> None:
  """Persist delivery state so saved tickets and delivered mail are distinguishable."""
  from .models import SupportIncident

  if field not in {'support_email_status', 'acknowledgement_email_status'}:
    raise ValueError('Unsupported support email status field.')
  updates = {field: delivery_status, 'email_delivery_updated_at': timezone.now()}
  if error:
    updates['email_delivery_error'] = error[:500]
  SupportIncident.objects.filter(pk=incident_pk).update(**updates)


def _delivery_callbacks(incident, field: str):
  from .models import SupportIncident

  def _success(sent_count):
    if sent_count:
      _mark_delivery(incident.pk, field, SupportIncident.EMAIL_SENT)
    else:
      _mark_delivery(
        incident.pk,
        field,
        SupportIncident.EMAIL_FAILED,
        'The email backend reported that no message was sent.',
      )

  def _error(exc):
    _mark_delivery(
      incident.pk,
      field,
      SupportIncident.EMAIL_FAILED,
      f'{type(exc).__name__}: {exc}',
    )

  return _success, _error


def _email_frame(title: str, body: str, footer: str = '') -> str:
  """Return a small, email-client-friendly HTML layout."""
  return f'''<!doctype html>
<html lang="en">
  <body style="margin:0;background:#f4f7fb;color:#111827;font-family:Arial,sans-serif;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f7fb;padding:28px 12px;">
      <tr><td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#ffffff;border:1px solid #dbe5f3;border-radius:14px;overflow:hidden;">
          <tr><td style="background:#2563eb;padding:20px 28px;color:#ffffff;font-size:20px;font-weight:700;">RepRoot</td></tr>
          <tr><td style="padding:30px 28px;">
            <h1 style="margin:0 0 18px;font-size:24px;line-height:1.3;color:#111827;">{escape(title)}</h1>
            <div style="font-size:15px;line-height:1.7;color:#475569;">{body}</div>
          </td></tr>
          <tr><td style="padding:18px 28px;background:#f8fafc;border-top:1px solid #e2e8f0;font-size:12px;line-height:1.6;color:#64748b;">{footer}</td></tr>
        </table>
      </td></tr>
    </table>
  </body>
</html>'''


def notify_support_team(incident) -> None:
  """Email the configured support mailbox about a newly persisted incident."""
  support_email = str(getattr(settings, 'SUPPORT_EMAIL', '') or '').strip()
  if not support_email:
    logger.warning('Support incident %s was saved, but SUPPORT_EMAIL is not configured.', incident.incident_id)
    from .models import SupportIncident
    _mark_delivery(
      incident.pk,
      'support_email_status',
      SupportIncident.EMAIL_SKIPPED,
      'SUPPORT_EMAIL is not configured.',
    )
    return

  on_success, on_error = _delivery_callbacks(incident, 'support_email_status')

  category = incident.get_category_display()
  subject = f'[{incident.incident_id}] {incident.subject}'
  text = (
    f'New RepRoot support request\n\n'
    f'Reference: {incident.incident_id}\n'
    f'Reporter: {incident.reporter_name}\n'
    f'Reporter email: {incident.reporter_email}\n'
    f'Category: {category}\n'
    f'Priority: {incident.get_priority_display()}\n'
    f'Platform: {incident.platform}\n\n'
    f'{incident.description}\n\n'
    f'Open the RepRoot operator support queue to respond.'
  )
  body = (
    f'<p>A new support request has been recorded.</p>'
    f'<p><strong>Reference:</strong> {escape(incident.incident_id)}<br>'
    f'<strong>Reporter:</strong> {escape(incident.reporter_name)}<br>'
    f'<strong>Email:</strong> {escape(incident.reporter_email)}<br>'
    f'<strong>Category:</strong> {escape(category)}<br>'
    f'<strong>Priority:</strong> {escape(incident.get_priority_display())}<br>'
    f'<strong>Platform:</strong> {escape(incident.platform)}</p>'
    f'<p style="white-space:pre-wrap;">{escape(incident.description)}</p>'
  )
  send_mail_background(
    subject=subject,
    message=text,
    from_email=settings.DEFAULT_FROM_EMAIL,
    recipient_list=[support_email],
    reply_to=[incident.reporter_email] if incident.reporter_email else None,
    html_message=_email_frame(
      f'New support request {incident.incident_id}',
      body,
      'Open the RepRoot operator support queue to assign, review, or respond to this request.',
    ),
    fail_silently=False,
    on_success=on_success,
    on_error=on_error,
  )


def send_support_acknowledgement(incident) -> None:
  """Confirm a public support submission to the requester."""
  if not incident.reporter_email:
    from .models import SupportIncident
    _mark_delivery(
      incident.pk,
      'acknowledgement_email_status',
      SupportIncident.EMAIL_SKIPPED,
      'The reporter did not provide an email address.',
    )
    return
  on_success, on_error = _delivery_callbacks(incident, 'acknowledgement_email_status')
  support_email = str(getattr(settings, 'SUPPORT_EMAIL', '') or '').strip()
  text = (
    f'Hello {incident.reporter_name},\n\n'
    f'Your query has been sent to the RepRoot support team. '
    f'Our team will respond as soon as possible.\n\n'
    f'Support reference: {incident.incident_id}\n'
    f'Subject: {incident.subject}\n\n'
    f'Keep this reference when contacting us about the same request.\n\n'
    f'RepRoot Support\n{support_email}'
  )
  body = (
    f'<p>Hello {escape(incident.reporter_name)},</p>'
    f'<p>Your query has been sent to the RepRoot support team. Our team will respond as soon as possible.</p>'
    f'<div style="margin:22px 0;padding:16px 18px;border-radius:10px;background:#eff6ff;border:1px solid #bfdbfe;">'
    f'<span style="font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#1d4ed8;">Support reference</span><br>'
    f'<strong style="font-size:20px;color:#1e3a8a;">{escape(incident.incident_id)}</strong></div>'
    f'<p><strong>Subject:</strong> {escape(incident.subject)}</p>'
    f'<p>Keep this reference when contacting us about the same request.</p>'
  )
  send_mail_background(
    subject=f'We received your RepRoot query [{incident.incident_id}]',
    message=text,
    from_email=settings.DEFAULT_FROM_EMAIL,
    recipient_list=[incident.reporter_email],
    reply_to=[support_email] if support_email else None,
    html_message=_email_frame(
      'Your support request has been received',
      body,
      f'RepRoot Support | {escape(support_email)}' if support_email else 'RepRoot Support',
    ),
    fail_silently=False,
    on_success=on_success,
    on_error=on_error,
  )


def send_public_support_reply(incident, reply: str) -> None:
  """Deliver an operator reply for a public support incident by email."""
  if not incident.reporter_email:
    return
  support_email = str(getattr(settings, 'SUPPORT_EMAIL', '') or '').strip()
  text = (
    f'Hello {incident.reporter_name},\n\n'
    f'The RepRoot support team replied to {incident.incident_id}:\n\n'
    f'{reply}\n\nRepRoot Support\n{support_email}'
  )
  body = (
    f'<p>Hello {escape(incident.reporter_name)},</p>'
    f'<p>The RepRoot support team replied to <strong>{escape(incident.incident_id)}</strong>.</p>'
    f'<div style="margin:20px 0;padding:16px 18px;border-left:4px solid #2563eb;background:#f8fafc;white-space:pre-wrap;">{escape(reply)}</div>'
  )
  send_mail_background(
    subject=f'RepRoot support reply [{incident.incident_id}]',
    message=text,
    from_email=settings.DEFAULT_FROM_EMAIL,
    recipient_list=[incident.reporter_email],
    reply_to=[support_email] if support_email else None,
    html_message=_email_frame(
      'A reply from RepRoot Support',
      body,
      f'RepRoot Support | {escape(support_email)}' if support_email else 'RepRoot Support',
    ),
    fail_silently=False,
  )


def send_professional_welcome_email(user) -> None:
  """Send a welcome message after a professional account is created."""
  email = str(getattr(user, 'email', '') or '').strip()
  if not email:
    return
  display_name = (user.get_full_name() or user.username).strip()
  support_email = str(getattr(settings, 'SUPPORT_EMAIL', '') or '').strip()
  support_text = (
    f'If you need help, contact {support_email}.\n\n'
    if support_email
    else ''
  )
  support_html = (
    f'<p>If you need help, contact <a href="mailto:{escape(support_email)}" style="color:#1d4ed8;">'
    f'{escape(support_email)}</a>.</p>'
    if support_email
    else ''
  )
  site_url = str(getattr(settings, 'REPROOT_FRONTEND_URL', '') or '').rstrip('/')
  professional_code = ''
  profile = getattr(user, 'professional_profile', None)
  if profile is not None:
    professional_code = str(getattr(profile, 'professional_id', '') or '').strip()

  # The code is how clients find this professional, so it is the single most
  # useful thing this email can carry. Only mentioned once it exists.
  code_text = (
    f'Your professional code is {professional_code}. Clients use it to reach your portal.\n\n'
    if professional_code else ''
  )
  code_html = (
    f'<p>Your professional code is <strong>{escape(professional_code)}</strong>. '
    f'Clients use it to reach your portal.</p>'
    if professional_code else ''
  )

  steps = [
    ('Complete your profile', 'Add your details and photo. This is what clients see.'),
    ('Create forms and groups', 'Set up the enquiry form and the groups clients join.'),
    ('Build templates', 'Reusable tracking templates you assign to clients.'),
    ('Check resources', 'Upload the PDFs, images and videos you share.'),
    ('Approve or add clients', 'Bring people in and start tracking progress.'),
  ]
  steps_text = '\n'.join(f'  {i}. {title} — {detail}' for i, (title, detail) in enumerate(steps, 1))
  steps_html = ''.join(
    f'<li style="margin-bottom:8px;"><strong>{escape(title)}</strong><br>{escape(detail)}</li>'
    for title, detail in steps
  )

  text = (
    f'Hello {display_name},\n\n'
    f'Your RepRoot professional account is ready.\n\n'
    f'{code_text}'
    f'Here is the order we suggest getting set up:\n\n'
    f'{steps_text}\n\n'
    f'{f"Sign in: {site_url}/professional/login" + chr(10) + chr(10) if site_url else ""}'
    f'{support_text}'
    f'Welcome to RepRoot.\n\n'
    f'RepRoot Team'
  )
  body = (
    f'<p>Hello {escape(display_name)},</p>'
    f'<p>Your RepRoot professional account is ready.</p>'
    f'{code_html}'
    f'<p>Here is the order we suggest getting set up:</p>'
    f'<ol style="padding-left:18px;">{steps_html}</ol>'
    + (f'<p><a href="{escape(site_url)}/professional/login" style="color:#1d4ed8;">Sign in to RepRoot</a></p>'
       if site_url else '')
    + f'{support_html}'
  )
  send_mail_background(
    subject='Welcome to RepRoot',
    message=text,
    from_email=settings.DEFAULT_FROM_EMAIL,
    recipient_list=[email],
    reply_to=[support_email] if support_email else None,
    html_message=_email_frame(
      'Welcome to RepRoot',
      body,
      f'RepRoot | Support: {escape(support_email)}' if support_email else 'RepRoot',
    ),
    fail_silently=False,
  )
