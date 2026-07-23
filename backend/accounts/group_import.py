"""Bulk group-member import (CSV).

Two-step flow mirroring the rest of the multi-step forms/groups endpoints in this
app: an unauthenticated-looking-but-owner-checked "preview" step that never writes
to the database, followed by a "confirm" step that performs the writes.

Design note on state between the two steps: rather than caching the parsed rows
server-side behind a token (there is no existing precedent for that in this app -
the closest analogue, email OTP in email_verification.py, caches a short opaque
code, not a payload), the frontend simply keeps the originally selected File object
in memory and re-submits it on confirm together with the trainer-approved column
mapping. This avoids adding a cache-eviction/TTL concern, works the same on a
single instance or many, and re-parsing a small CSV a second time is negligible
work - it is exactly the same file, so parsing it again is deterministic.

Row creation reuses ClientAccessCreateSerializer (the same serializer
ManualClientAccessCreateView uses) so username/password/registration-answer
validation rules do not have to be duplicated here.
"""
import csv
import io
import json
import re

from django.contrib.auth.hashers import make_password
from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.response import Response
from rest_framework.serializers import ValidationError as SerializerValidationError
from rest_framework.views import APIView

from .access_permissions import ProfessionalAccessPermission
from .models import ClientAccess, ProfessionalGroup
from .plan_limits import plan_limit, professional_plan
from .serializers import ClientAccessCreateSerializer, ClientAccessSerializer, validate_required_answers
from .views import generate_temporary_password, send_client_credentials

PREVIEW_ROW_LIMIT = 5
MAX_IMPORT_ROWS = 1000


def _normalize(text):
  """Lowercase and strip everything but letters/digits, for fuzzy header matching."""
  return re.sub(r'[^a-z0-9]', '', str(text or '').lower())


def match_columns(file_columns, fields):
  """Match uploaded CSV column headers against a registration form's fields.

  Matching is a simple normalized-string comparison (case-insensitive,
  alphanumeric-only): exact match on key/label -> 'exact', substring match either
  direction -> 'partial', otherwise unmatched (confidence None). No fuzzy-matching
  dependency is used.
  """
  candidates = [
    {
      'key': field.get('key') or '',
      'label': field.get('label') or '',
      'norm_key': _normalize(field.get('key')),
      'norm_label': _normalize(field.get('label')),
    }
    for field in (fields or [])
  ]
  used_keys = set()
  columns = []

  for file_column in file_columns:
    norm_column = _normalize(file_column)
    matched_key = None
    matched_label = None
    confidence = None

    if norm_column:
      for candidate in candidates:
        if candidate['key'] in used_keys:
          continue
        if norm_column == candidate['norm_key'] or norm_column == candidate['norm_label']:
          matched_key, matched_label, confidence = candidate['key'], candidate['label'], 'exact'
          break

      if matched_key is None:
        for candidate in candidates:
          if candidate['key'] in used_keys:
            continue
          key_hit = candidate['norm_key'] and (candidate['norm_key'] in norm_column or norm_column in candidate['norm_key'])
          label_hit = candidate['norm_label'] and (candidate['norm_label'] in norm_column or norm_column in candidate['norm_label'])
          if key_hit or label_hit:
            matched_key, matched_label, confidence = candidate['key'], candidate['label'], 'partial'
            break

    if matched_key:
      used_keys.add(matched_key)

    columns.append({
      'file_column': file_column,
      'matched_field_key': matched_key,
      'matched_field_label': matched_label,
      'confidence': confidence,
    })

  return columns


def parse_upload(uploaded_file):
  """Parse a CSV upload into (headers, rows). Each row is a dict keyed by header."""
  raw = uploaded_file.read()

  try:
    text = raw.decode('utf-8-sig')
  except UnicodeDecodeError:
    text = raw.decode('latin-1')

  rows_raw = [row for row in csv.reader(io.StringIO(text)) if any(cell.strip() for cell in row)]

  if not rows_raw:
    return [], []

  headers = [cell.strip() for cell in rows_raw[0]]
  rows = []

  for raw_row in rows_raw[1:]:
    rows.append({header: (raw_row[index].strip() if index < len(raw_row) else '') for index, header in enumerate(headers)})

  return headers, rows


def _owned_group(request, group_id):
  return ProfessionalGroup.objects.filter(
    id=group_id, professional=request.user, is_active=True
  ).select_related('client_registration_form').first()


def _flatten_serializer_errors(errors):
  parts = []

  for field, messages in errors.items():
    text = '; '.join(str(message) for message in messages) if isinstance(messages, list) else str(messages)
    parts.append(f'{field}: {text}')

  return ' | '.join(parts) or 'Invalid row.'


def _unique_username(base, professional, taken):
  base = re.sub(r'[^a-z0-9.\-]', '', (base or 'client').lower()) or 'client'
  candidate = base
  suffix = 1

  while candidate in taken or ClientAccess.objects.filter(professional=professional, username__iexact=candidate).exists():
    suffix += 1
    candidate = f'{base}{suffix}'

  taken.add(candidate)
  return candidate


class GroupImportPreviewView(APIView):
  """Step 1: parse the uploaded CSV and match its columns against the group's
  client registration form fields. Nothing is created here."""

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, group_id):
    group = _owned_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    uploaded_file = request.FILES.get('file')

    if uploaded_file is None:
      return Response({'message': 'A CSV file is required.'}, status=status.HTTP_400_BAD_REQUEST)

    if not uploaded_file.name.lower().endswith('.csv'):
      return Response({'message': 'Only CSV files are supported.'}, status=status.HTTP_400_BAD_REQUEST)

    registration_form = getattr(group, 'client_registration_form', None)
    fields = registration_form.fields if registration_form else []

    try:
      headers, rows = parse_upload(uploaded_file)
    except (UnicodeDecodeError, csv.Error):
      return Response({'message': 'Could not read this file as CSV.'}, status=status.HTTP_400_BAD_REQUEST)

    if not headers:
      return Response({'message': 'The file has no header row.'}, status=status.HTTP_400_BAD_REQUEST)

    if len(rows) > MAX_IMPORT_ROWS:
      return Response(
        {'message': f'This file has {len(rows)} rows; imports are limited to {MAX_IMPORT_ROWS} rows at a time.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    columns = match_columns(headers, fields)
    unmatched_columns = [column['file_column'] for column in columns if column['matched_field_key'] is None]

    return Response({
      'columns': columns,
      'rows_preview': rows[:PREVIEW_ROW_LIMIT],
      'row_count': len(rows),
      'unmatched_columns': unmatched_columns,
      'fields': [
        {'key': field.get('key'), 'label': field.get('label'), 'required': bool(field.get('required'))}
        for field in fields
      ],
    })


class GroupImportConfirmView(APIView):
  """Step 2: create one ClientAccess per confirmed row.

  Re-reads the same uploaded file plus the trainer-approved mapping (see module
  docstring for why the file is re-sent rather than cached server-side). Each row
  is created in its own transaction.atomic() savepoint nested inside one outer
  transaction, so a bad row is rolled back individually without discarding the
  rows already created in this batch and without needing an all-or-nothing toggle.
  """

  permission_classes = [ProfessionalAccessPermission]

  def post(self, request, group_id):
    group = _owned_group(request, group_id)

    if group is None:
      return Response({'message': 'Group not found.'}, status=status.HTTP_404_NOT_FOUND)

    uploaded_file = request.FILES.get('file')

    if uploaded_file is None:
      return Response({'message': 'A CSV file is required.'}, status=status.HTTP_400_BAD_REQUEST)

    mapping_raw = request.data.get('mapping')

    if not mapping_raw:
      return Response({'message': 'A column mapping is required.'}, status=status.HTTP_400_BAD_REQUEST)

    try:
      mapping = json.loads(mapping_raw) if isinstance(mapping_raw, str) else mapping_raw
    except (TypeError, ValueError):
      return Response({'message': 'Invalid mapping payload.'}, status=status.HTTP_400_BAD_REQUEST)

    if not isinstance(mapping, list):
      return Response({'message': 'Invalid mapping payload.'}, status=status.HTTP_400_BAD_REQUEST)

    registration_form = getattr(group, 'client_registration_form', None)
    fields = registration_form.fields if registration_form else []
    valid_field_keys = {field.get('key') for field in fields}

    column_field_map = {}
    for entry in mapping:
      if not isinstance(entry, dict):
        continue
      field_key = entry.get('matched_field_key') or entry.get('field_key')
      file_column = entry.get('file_column')
      if file_column is not None and field_key in valid_field_keys:
        column_field_map[str(file_column)] = field_key

    try:
      headers, rows = parse_upload(uploaded_file)
    except (UnicodeDecodeError, csv.Error):
      return Response({'message': 'Could not read this file as CSV.'}, status=status.HTTP_400_BAD_REQUEST)

    if len(rows) > MAX_IMPORT_ROWS:
      return Response(
        {'message': f'This file has {len(rows)} rows; imports are limited to {MAX_IMPORT_ROWS} rows at a time.'},
        status=status.HTTP_400_BAD_REQUEST,
      )

    def _flag(name, default=False):
      value = request.data.get(name, default)
      if isinstance(value, bool):
        return value
      return str(value).strip().lower() in ('1', 'true', 'yes', 'on')

    create_portal_access = _flag('create_portal_access', False)
    send_credentials = _flag('send_credentials', True)

    registration_form_required = registration_form is None or registration_form.is_mandatory

    if registration_form_required and (registration_form is None or not registration_form.is_active):
      return Response({'message': 'This group needs an active client registration form.'}, status=status.HTTP_400_BAD_REQUEST)

    client_limit = plan_limit(request.user, 'clients')
    current_count = ClientAccess.objects.filter(professional=request.user, is_active=True).count()

    created = []
    errors = []
    taken_usernames = set()

    with transaction.atomic():
      for index, row in enumerate(rows):
        row_number = index + 2  # header is row 1 when the file is opened in a spreadsheet

        if client_limit is not None and current_count >= client_limit:
          errors.append({
            'row_index': row_number,
            'error': f'Your {professional_plan(request.user)["name"]} plan allows up to {client_limit} active clients; row skipped.',
          })
          continue

        answers = {field_key: row.get(file_column, '') for file_column, field_key in column_field_map.items()}

        first_name = str(answers.get('first_name', '')).strip()
        last_name = str(answers.get('last_name', '')).strip()
        email = str(answers.get('email', '')).strip().lower()

        if not first_name or not last_name or not email:
          errors.append({'row_index': row_number, 'error': 'First name, last name, and email are required.'})
          continue

        if registration_form is not None and registration_form.is_mandatory:
          try:
            validate_required_answers(fields, answers)
          except SerializerValidationError as error:
            detail = error.detail
            message = detail.get('answers') if isinstance(detail, dict) else detail
            errors.append({'row_index': row_number, 'error': str(message)})
            continue

        payload = {
          'group_id': group.id,
          'has_portal_access': create_portal_access,
          'registration_answers': answers,
          'send_credentials': send_credentials,
        }

        if create_portal_access:
          username = _unique_username(email.split('@')[0], request.user, taken_usernames)
          temporary_password = generate_temporary_password()
          payload['username'] = username
          payload['password'] = temporary_password
          payload['confirm_password'] = temporary_password

        serializer = ClientAccessCreateSerializer(data=payload, context={'professional': request.user})

        if not serializer.is_valid():
          errors.append({'row_index': row_number, 'error': _flatten_serializer_errors(serializer.errors)})
          continue

        try:
          with transaction.atomic():
            client_access = ClientAccess.objects.create(
              professional=request.user,
              group=group,
              onboarding_method=ClientAccess.ONBOARDING_MANUAL,
              first_name=first_name,
              last_name=last_name,
              email=email,
              has_portal_access=create_portal_access,
              username=serializer.validated_data['username'] if create_portal_access else None,
              temporary_password=make_password(serializer.validated_data['password']) if create_portal_access else None,
              registration_answers=answers,
              must_change_password=create_portal_access,
            )
        except IntegrityError:
          errors.append({'row_index': row_number, 'error': 'A client with this email or username already exists.'})
          continue

        current_count += 1
        credentials_sent = create_portal_access and send_credentials

        if credentials_sent:
          send_client_credentials(client_access, serializer.validated_data['password'])

        created.append({
          'row_index': row_number,
          'client_access': ClientAccessSerializer(client_access).data,
          'temporary_password': serializer.validated_data['password'] if create_portal_access else None,
          'credentials_sent': credentials_sent,
        })

    return Response({
      'created': created,
      'errors': errors,
      'created_count': len(created),
      'error_count': len(errors),
      'message': f'{len(created)} client(s) created, {len(errors)} row(s) failed.',
    }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
