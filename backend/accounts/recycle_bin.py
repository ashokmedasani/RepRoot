"""
Recycle bin for RepRoot Studio — scoped narrow on purpose.

Only three things go through soft_delete_*() instead of a raw .delete():
  - chat messages that carry an image (the text itself is cheap to lose)
  - references (they're a curated content library, often file-backed)
  - whole client accounts (bundled with all their chat/tracking/progress/
    reminders/assignments — deleting an entire client is consequential
    enough to always be fully recoverable)

Plain text records — tracking entries, progress notes, reminders, templates —
are deleted outright when removed on their own; they're high-volume,
low-value operational data not worth the Bin's overhead. They only survive
via the client_account bundle if the whole client goes with them.

A RecycleBinItem snapshot is written first, then the live row is removed.
The item stays restorable for REPROOT_RECYCLE_BIN_DAYS; purge_expired()
removes anything past that window for good, including any underlying file
(chat image / reference upload) it was still holding onto.

Underlying files are deliberately NOT deleted at soft-delete time — restore
needs them to still exist on disk/S3. They're only removed at permanent
purge, in _delete_underlying_file() below.
"""

from datetime import timedelta

from django.conf import settings
from django.core.files.storage import default_storage
from django.utils import timezone

from .models import (
  ChatMessage,
  ClientAccess,
  ClientReminder,
  GroupRegistrationSubmission,
  LeadSubmission,
  ProfessionalGroup,
  ProfessionalReference,
  ProgressEntry,
  ReferenceCategory,
  RecycleBinItem,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
)


class RestoreError(Exception):
  """Raised when a recycle bin item can't be restored (e.g. its parent client/category was removed)."""


def _expires_at():
  return timezone.now() + timedelta(days=settings.REPROOT_RECYCLE_BIN_DAYS)


# ---- Chat message ----

def soft_delete_chat_message(message, deleted_by=RecycleBinItem.DELETED_BY_PROFESSIONAL):
  RecycleBinItem.objects.create(
    professional=message.professional,
    category=RecycleBinItem.CATEGORY_CHAT_MESSAGE,
    title=(message.text.strip()[:60] if message.text.strip() else 'Image message') if message.text else 'Image message',
    payload={
      'client_id': message.client_id,
      'sender': message.sender,
      'text': message.text,
      'image': message.image.name if message.image else '',
      'is_read': message.is_read,
    },
    deleted_by=deleted_by,
    expires_at=_expires_at(),
  )
  message.delete()


def _restore_chat_message(item):
  client = ClientAccess.objects.filter(id=item.payload.get('client_id')).first()
  if not client:
    raise RestoreError('The client this message belonged to no longer exists.')

  message = ChatMessage(
    professional=item.professional,
    client=client,
    sender=item.payload.get('sender', ChatMessage.SENDER_PROFESSIONAL),
    text=item.payload.get('text', ''),
    is_read=item.payload.get('is_read', False),
  )
  if item.payload.get('image'):
    message.image.name = item.payload['image']
  message.save()


# Tracking entries, progress notes, and reminders are plain text/small JSON —
# not worth the Recycle Bin's overhead on their own. They're deleted outright
# (see views.py) unless they're part of a whole client_account bundle below,
# where losing the client makes them worth preserving alongside the client.

# ---- Reference ----

def soft_delete_reference(reference, deleted_by=RecycleBinItem.DELETED_BY_PROFESSIONAL):
  RecycleBinItem.objects.create(
    professional=reference.professional,
    category=RecycleBinItem.CATEGORY_REFERENCE,
    title=reference.title,
    payload={
      'category_id': reference.category_id,
      'subcategory': reference.subcategory,
      'title': reference.title,
      'reference_type': reference.reference_type,
      'description': reference.description,
      'link': reference.link,
      'file': reference.file.name if reference.file else '',
      'tags': reference.tags,
    },
    deleted_by=deleted_by,
    expires_at=_expires_at(),
  )
  reference.delete()


def _restore_reference(item):
  category = ReferenceCategory.objects.filter(id=item.payload.get('category_id')).first()
  if not category:
    raise RestoreError('The category this reference belonged to no longer exists.')

  reference = ProfessionalReference(
    professional=item.professional,
    category=category,
    subcategory=item.payload.get('subcategory', ''),
    title=item.payload.get('title', ''),
    reference_type=item.payload.get('reference_type', ProfessionalReference.TYPE_TEXT_NOTE),
    description=item.payload.get('description', ''),
    link=item.payload.get('link', ''),
    tags=item.payload.get('tags', []),
  )
  if item.payload.get('file'):
    reference.file.name = item.payload['file']
  reference.save()


# ---- Client account (bundles the client plus its chat/tracking/progress/
# reminders/assignments into one recycle bin entry, since those only make
# sense restored together with the client they belong to) ----

def soft_delete_client_account(client, deleted_by=RecycleBinItem.DELETED_BY_PROFESSIONAL):
  chat_messages = [
    {
      'sender': m['sender'],
      'text': m['text'],
      'image': m['image'],
      'is_read': m['is_read'],
    }
    for m in ChatMessage.objects.filter(client=client).values('sender', 'text', 'image', 'is_read')
  ]
  tracking_entries = [
    {
      'template_id': e['template_id'],
      'template_name': e['template_name'],
      'entry_date': e['entry_date'].isoformat(),
      'entry_time': e['entry_time'].isoformat() if e['entry_time'] else None,
      'answers': e['answers'],
      'note': e['note'],
      'edited_by_professional': e['edited_by_professional'],
    }
    for e in TrackingEntry.objects.filter(client=client).values(
      'template_id', 'template_name', 'entry_date', 'entry_time', 'answers', 'note', 'edited_by_professional'
    )
  ]
  progress_entries = [
    {
      'title': p['title'],
      'date': p['date'].isoformat(),
      'notes': p['notes'],
      'status': p['status'],
      'next_step': p['next_step'],
      'created_by': p['created_by'],
    }
    for p in ProgressEntry.objects.filter(client=client).values('title', 'date', 'notes', 'status', 'next_step', 'created_by')
  ]
  reminders = [
    {
      'title': r['title'],
      'date': r['date'].isoformat(),
      'time': r['time'].isoformat() if r['time'] else None,
      'notes': r['notes'],
      'status': r['status'],
    }
    for r in ClientReminder.objects.filter(client=client).values('title', 'date', 'time', 'notes', 'status')
  ]
  assignments = [
    {'template_id': a.template_id, 'reference_ids': list(a.references.values_list('id', flat=True))}
    for a in TemplateAssignment.objects.filter(client=client)
  ]

  RecycleBinItem.objects.create(
    professional=client.professional,
    category=RecycleBinItem.CATEGORY_CLIENT_ACCOUNT,
    title=f'{client.first_name} {client.last_name}'.strip() or client.username,
    payload={
      'group_id': client.group_id,
      'lead_submission_id': client.lead_submission_id,
      'registration_submission_id': client.registration_submission_id,
      'reference_id': client.reference_id,
      'onboarding_method': client.onboarding_method,
      'first_name': client.first_name,
      'last_name': client.last_name,
      'email': client.email,
      'username': client.username,
      'temporary_password': client.temporary_password,
      'photo': client.photo,
      'registration_answers': client.registration_answers,
      'additional_info': client.additional_info,
      'additional_info_shared': client.additional_info_shared,
      'professional_notes': client.professional_notes,
      'must_change_password': client.must_change_password,
      'chat_messages': chat_messages,
      'tracking_entries': tracking_entries,
      'progress_entries': progress_entries,
      'reminders': reminders,
      'assignments': assignments,
    },
    deleted_by=deleted_by,
    expires_at=_expires_at(),
  )
  client.delete()


def _restore_client_account(item):
  payload = item.payload
  group = ProfessionalGroup.objects.filter(id=payload.get('group_id')).first()
  if not group:
    raise RestoreError('The group this client belonged to no longer exists.')

  conflict = ClientAccess.objects.filter(professional=item.professional, username=payload['username']).exists() or \
    ClientAccess.objects.filter(professional=item.professional, email=payload['email']).exists()
  if conflict:
    raise RestoreError('A client with this username or email already exists. Resolve the conflict before restoring.')

  lead_submission = None
  if payload.get('lead_submission_id'):
    lead_submission = LeadSubmission.objects.filter(id=payload['lead_submission_id'], client_access__isnull=True).first()

  registration_submission = None
  if payload.get('registration_submission_id'):
    registration_submission = GroupRegistrationSubmission.objects.filter(
      id=payload['registration_submission_id'], client_access__isnull=True
    ).first()

  client_kwargs = dict(
    professional=item.professional,
    group=group,
    lead_submission=lead_submission,
    registration_submission=registration_submission,
    onboarding_method=payload.get('onboarding_method', ClientAccess.ONBOARDING_MANUAL),
    first_name=payload.get('first_name', ''),
    last_name=payload.get('last_name', ''),
    email=payload.get('email', ''),
    username=payload.get('username', ''),
    temporary_password=payload.get('temporary_password', ''),
    photo=payload.get('photo', ''),
    registration_answers=payload.get('registration_answers', {}),
    additional_info=payload.get('additional_info', []),
    additional_info_shared=payload.get('additional_info_shared', False),
    professional_notes=payload.get('professional_notes', ''),
    must_change_password=payload.get('must_change_password', True),
  )
  # reference_id has a default generator (generate_client_reference_id) and no
  # null=True — only override it if the original value is still available and
  # not already taken by a client created after this one was deleted.
  original_reference_id = payload.get('reference_id')
  if original_reference_id and not ClientAccess.objects.filter(reference_id=original_reference_id).exists():
    client_kwargs['reference_id'] = original_reference_id

  client = ClientAccess.objects.create(**client_kwargs)

  for m in payload.get('chat_messages', []):
    message = ChatMessage(professional=item.professional, client=client, sender=m['sender'], text=m.get('text', ''), is_read=m.get('is_read', False))
    if m.get('image'):
      message.image.name = m['image']
    message.save()

  for e in payload.get('tracking_entries', []):
    TrackingEntry.objects.create(
      client=client,
      template_id=e.get('template_id'),
      template_name=e.get('template_name', ''),
      entry_date=e['entry_date'],
      entry_time=e.get('entry_time'),
      answers=e.get('answers', {}),
      note=e.get('note', ''),
      edited_by_professional=e.get('edited_by_professional', False),
    )

  for p in payload.get('progress_entries', []):
    ProgressEntry.objects.create(
      client=client,
      professional=item.professional,
      title=p.get('title', ''),
      date=p['date'],
      notes=p.get('notes', ''),
      status=p.get('status', ''),
      next_step=p.get('next_step', ''),
      created_by=p.get('created_by', ''),
    )

  for r in payload.get('reminders', []):
    ClientReminder.objects.create(
      professional=item.professional,
      client=client,
      title=r.get('title', ''),
      date=r['date'],
      time=r.get('time'),
      notes=r.get('notes', ''),
      status=r.get('status', ClientReminder.STATUS_PENDING),
    )

  for a in payload.get('assignments', []):
    if not TrackingTemplate.objects.filter(id=a['template_id']).exists():
      continue
    assignment = TemplateAssignment.objects.create(client=client, template_id=a['template_id'])
    reference_ids = ProfessionalReference.objects.filter(id__in=a.get('reference_ids', [])).values_list('id', flat=True)
    assignment.references.set(reference_ids)


_RESTORE_HANDLERS = {
  RecycleBinItem.CATEGORY_CHAT_MESSAGE: _restore_chat_message,
  RecycleBinItem.CATEGORY_REFERENCE: _restore_reference,
  RecycleBinItem.CATEGORY_CLIENT_ACCOUNT: _restore_client_account,
}


def restore_item(item: RecycleBinItem) -> None:
  """Recreate the item from its snapshot and remove it from the bin. Raises RestoreError on failure."""
  handler = _RESTORE_HANDLERS.get(item.category)
  if handler is None:
    raise RestoreError(f'Unknown recycle bin category: {item.category}')

  handler(item)
  item.delete()


def _delete_underlying_file(item: RecycleBinItem) -> None:
  """Removes whatever files a recycle bin entry was still holding onto —
  a single image/file for chat messages and references, or every chat
  image bundled into a client_account snapshot."""
  paths = []
  if item.category == RecycleBinItem.CATEGORY_CHAT_MESSAGE:
    paths = [item.payload.get('image')]
  elif item.category == RecycleBinItem.CATEGORY_REFERENCE:
    paths = [item.payload.get('file')]
  elif item.category == RecycleBinItem.CATEGORY_CLIENT_ACCOUNT:
    paths = [m.get('image') for m in item.payload.get('chat_messages', [])]

  for path in paths:
    if path and default_storage.exists(path):
      default_storage.delete(path)


def delete_permanently(item: RecycleBinItem) -> None:
  _delete_underlying_file(item)
  item.delete()


def purge_expired() -> None:
  """Daily task: hard-delete anything past its recycle bin window, including underlying files."""
  now = timezone.now()
  for item in RecycleBinItem.objects.filter(expires_at__lt=now).iterator():
    _delete_underlying_file(item)
  RecycleBinItem.objects.filter(expires_at__lt=now).delete()
