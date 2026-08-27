"""Seed six demo professionals, each with a full working account.

Built for showing the product to someone: every professional lands on a
dashboard with real activity, a populated client list, tracked history,
schedules, payments and resources, on the Free plan throughout.

Each professional gets one client with portal access -- the account you can
hand out for a demo login -- and the rest as record-only clients, which is how
most professionals actually use it.

Passwords are generated per account and printed at the end. They are also
written to a markdown file (--output) so the list can be forwarded.

  python manage.py seed_demo_professionals
  python manage.py seed_demo_professionals --only fitness --days 30
  python manage.py seed_demo_professionals --clients 6 --output demo-accounts.md

Re-running is safe: the demo professionals' generated data is cleared first,
so history never accumulates twice. Passwords change on every run, and the
output file is rewritten to match.
"""

import random
import secrets
import string
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.conf import settings as django_settings
from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from accounts.demo_professions import PROFESSIONS
from accounts.models import (
  ChatMessage,
  ClientAccess,
  ClientRegistrationForm,
  ClientReminder,
  GroupRegistrationSubmission,
  LeadMeetingRequest,
  LeadSubmission,
  ManualPaymentProfile,
  PaymentPlan,
  PaymentProof,
  PaymentRecord,
  PaymentRequest,
  PaymentRequestAllowedMethod,
  ProfessionalAvailabilityWindow,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalPaymentSettings,
  ProfessionalProfile,
  ProfessionalResource,
  ProfessionalSchedulingSettings,
  ProgressEntry,
  ResourceCategory,
  ScheduledMeeting,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  default_client_registration_fields,
)
from accounts.serializers import DEFAULT_PROFILE_SECTION_ORDER, PROFILE_VISIBILITY_KEYS

User = get_user_model()

# Free plan allowances. Asserted rather than assumed: if the plan is ever
# retuned, this seed should fail loudly instead of quietly creating an account
# that is already over its limit on the day it is handed out.
FREE_MAX_TEMPLATES = 5
FREE_MAX_TEMPLATE_FIELDS = 8
FREE_MAX_GROUPS = 3
FREE_MAX_CATEGORIES = 5
FREE_MAX_SUBCATEGORIES = 3
FREE_MAX_RESOURCES = 30

PAYMENT_MONTHS = 6
PASSWORD_ALPHABET = string.ascii_letters + string.digits


def generate_password(length=14):
  """Readable but not guessable. These accounts get emailed around, so the
  alphabet stays alphanumeric -- punctuation gets mangled by chat clients."""
  return ''.join(secrets.choice(PASSWORD_ALPHABET) for _ in range(length))


def aware(day, hour=9, minute=0):
  return timezone.make_aware(datetime.combine(day, time(hour=hour, minute=minute)))


class Command(BaseCommand):
  help = 'Seed six demo professionals with clients, templates, history, schedules and payments.'

  def add_arguments(self, parser):
    parser.add_argument('--days', type=int, default=90, help='Days of tracked history per client (default 90).')
    parser.add_argument('--clients', type=int, default=10, help='Clients per professional (default 10).')
    parser.add_argument('--only', default='', help='Seed a single profession by key, e.g. fitness.')
    parser.add_argument('--output', default='demo-accounts.md', help='Where to write the credentials list. Pass "" to skip.')

  def handle(self, *args, **options):
    self.history_days = max(7, min(options['days'], 365))
    self.clients_per_professional = max(2, min(options['clients'], 40))
    only = (options['only'] or '').strip().lower()

    professions = [p for p in PROFESSIONS if not only or p['key'] == only]
    if not professions:
      raise CommandError(f'No demo profession with key "{only}". Known keys: {", ".join(p["key"] for p in PROFESSIONS)}.')

    for profession in professions:
      self.validate(profession)

    self.today = timezone.now().date()
    credentials = []

    for profession in professions:
      with transaction.atomic():
        credentials.append(self.seed_profession(profession))
      self.stdout.write(self.style.SUCCESS(f'  seeded {profession["username"]} ({profession["professional_type"]})'))

    self.report(credentials, options['output'])

  # -- validation ---------------------------------------------------------

  def validate(self, profession):
    """Fail before writing anything, not halfway through."""
    where = profession['key']
    templates = profession['templates']
    if len(templates) > FREE_MAX_TEMPLATES:
      raise CommandError(f'{where}: {len(templates)} templates exceeds the Free plan limit of {FREE_MAX_TEMPLATES}.')
    for template in templates:
      if len(template['fields']) > FREE_MAX_TEMPLATE_FIELDS:
        raise CommandError(f'{where}/{template["name"]}: {len(template["fields"])} fields exceeds the limit of {FREE_MAX_TEMPLATE_FIELDS}.')
      for field in template['fields']:
        if field['field_type'] == 'dropdown' and not field['options']:
          raise CommandError(f'{where}/{template["name"]}/{field["key"]}: dropdown fields need options.')
    if len(profession['groups']) > FREE_MAX_GROUPS:
      raise CommandError(f'{where}: {len(profession["groups"])} groups exceeds the Free plan limit of {FREE_MAX_GROUPS}.')
    if len(profession['resources']) > FREE_MAX_CATEGORIES:
      raise CommandError(f'{where}: {len(profession["resources"])} resource categories exceeds the limit of {FREE_MAX_CATEGORIES}.')
    resource_count = 0
    for name, subcategories, items in profession['resources']:
      if len(subcategories) > FREE_MAX_SUBCATEGORIES:
        raise CommandError(f'{where}/{name}: {len(subcategories)} subcategories exceeds the limit of {FREE_MAX_SUBCATEGORIES}.')
      resource_count += len(items)
    if resource_count > FREE_MAX_RESOURCES:
      raise CommandError(f'{where}: {resource_count} resources exceeds the Free plan limit of {FREE_MAX_RESOURCES}.')

  # -- one professional ---------------------------------------------------

  def seed_profession(self, profession):
    self.random = random.Random(f'reproot-demo-{profession["key"]}')
    professional, professional_password = self.seed_professional(profession)
    self.purge(professional)

    groups = self.seed_groups(professional, profession)
    lead_form = self.seed_lead_form(professional, profession)
    resources = self.seed_resources(professional, profession)
    templates = self.seed_templates(professional, profession)
    clients, portal_password = self.seed_clients(professional, profession, groups, lead_form)

    self.seed_assignments(clients, templates, resources)
    for index, client in enumerate(clients):
      self.seed_entries(client, templates, index)
    self.seed_scheduling(professional, clients)
    self.seed_payments(professional, profession, clients)
    self.seed_chat(professional, profession, clients[0])
    self.seed_follow_ups(professional, clients)
    self.seed_pending_work(professional, profession, lead_form, groups)

    return {
      'profession': profession,
      'professional_password': professional_password,
      'portal_client': clients[0],
      'portal_password': portal_password,
      'client_count': len(clients),
    }

  def purge(self, professional):
    """Everything generated below, cleared. Deliberately not the professional,
    the groups, the templates or the clients themselves -- those are matched by
    natural key and updated in place, so ids stay stable between runs."""
    TrackingEntry.objects.filter(client__professional=professional).delete()
    ChatMessage.objects.filter(professional=professional).delete()
    ScheduledMeeting.objects.filter(professional=professional).delete()
    ClientReminder.objects.filter(professional=professional).delete()
    ProgressEntry.objects.filter(professional=professional).delete()
    PaymentProof.objects.filter(payment_request__professional=professional).delete()
    PaymentRecord.objects.filter(professional=professional).delete()
    PaymentRequest.objects.filter(professional=professional).delete()
    LeadSubmission.objects.filter(lead_form__professional=professional, status=LeadSubmission.STATUS_PENDING).delete()
    GroupRegistrationSubmission.objects.filter(group__professional=professional).delete()

  # -- professional and profile -------------------------------------------

  def seed_professional(self, profession):
    password = generate_password()
    professional, _created = User.objects.get_or_create(
      username=profession['username'],
      defaults={'email': profession['email']},
    )
    professional.email = profession['email']
    professional.first_name = profession['first_name']
    professional.last_name = profession['last_name']
    professional.is_active = True
    professional.set_password(password)
    professional.save()

    profile, _created = ProfessionalProfile.objects.get_or_create(user=professional)
    certification_name, certification_issuer, certification_year = profession['certification']
    birth_month, birth_year = profession['birth']

    profile.professional_id = profession['professional_id']
    profile.plan_tier = ProfessionalProfile.PLAN_STARTER_FREE
    profile.profile_setup_completed = True
    profile.professional_headline = profession['headline']
    profile.about_me = profession['about']
    profile.professional_type = profession['professional_type']
    profile.years_experience = profession['years_experience']
    profile.specializations = profession['specializations']
    profile.languages_known = profession['languages']
    profile.certification_name = certification_name
    profile.certification_issued_by = certification_issuer
    profile.certification_year = certification_year
    profile.gender = profession['gender']
    profile.country = profession['country']
    profile.state = profession['state']
    profile.birth_month = birth_month
    profile.birth_year = birth_year
    profile.website_url = f'https://{profession["key"]}.reproot.demo'
    profile.profile_visibility = {key: True for key in PROFILE_VISIBILITY_KEYS}
    profile.profile_section_order = list(DEFAULT_PROFILE_SECTION_ORDER)
    profile.terms_accepted = True
    profile.privacy_policy_accepted = True
    profile.terms_accepted_at = timezone.now()
    profile.privacy_policy_accepted_at = timezone.now()
    profile.legal_document_version = django_settings.REPROOT_PROFESSIONAL_LEGAL_VERSION
    profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    profile.is_locked = False
    profile.save()
    return professional, password

  # -- structure ----------------------------------------------------------

  def seed_groups(self, professional, profession):
    groups = {}
    for rank, (name, description) in enumerate(profession['groups'], start=1):
      group, _created = ProfessionalGroup.objects.update_or_create(
        professional=professional,
        name=name,
        defaults={'description': description, 'is_active': True, 'priority_rank': rank},
      )
      ClientRegistrationForm.objects.update_or_create(
        group=group,
        defaults={'fields': default_client_registration_fields(), 'is_active': True},
      )
      groups[name] = group
    return groups

  def seed_lead_form(self, professional, profession):
    lead_form, _created = ProfessionalLeadForm.objects.update_or_create(
      professional=professional,
      public_slug=f'{profession["professional_id"]}-enquiries',
      defaults={
        'title': f'Work with {profession["first_name"]} {profession["last_name"]}',
        'fields': default_client_registration_fields(),
        'is_active': True,
        'priority_rank': 1,
      },
    )
    return lead_form

  def seed_resources(self, professional, profession):
    resources = []
    for rank, (category_name, subcategories, items) in enumerate(profession['resources'], start=1):
      category, _created = ResourceCategory.objects.update_or_create(
        professional=professional,
        name=category_name,
        defaults={'subcategories': list(subcategories), 'priority_rank': rank},
      )
      for subcategory, title, resource_type, description, link in items:
        resource, _created = ProfessionalResource.objects.update_or_create(
          professional=professional,
          title=title,
          defaults={
            'category': category,
            'subcategory': subcategory,
            'resource_type': resource_type,
            'description': description,
            'link': link,
            'tags': [category_name.lower(), subcategory.lower()],
          },
        )
        resources.append(resource)
    return resources

  def seed_templates(self, professional, profession):
    templates = []
    for rank, definition in enumerate(profession['templates'], start=1):
      # `sample` is seed-only metadata and must not reach the database: the
      # template editor round-trips whatever it finds in `fields`.
      stored_fields = [{k: v for k, v in field.items() if k != 'sample'} for field in definition['fields']]
      template, _created = TrackingTemplate.objects.update_or_create(
        professional=professional,
        name=definition['name'],
        defaults={
          'purpose': definition['purpose'],
          'cadence': definition['cadence'],
          'accent': definition['accent'],
          'fields': stored_fields,
          'standard_key': '',
          'is_active': True,
          'priority_rank': rank,
        },
      )
      templates.append((template, definition))
    return templates

  # -- clients ------------------------------------------------------------

  def seed_clients(self, professional, profession, groups, lead_form):
    clients = []
    portal_password = generate_password()
    roster = profession['clients'][:self.clients_per_professional]

    for index, (first_name, last_name, group_name) in enumerate(roster):
      email = f'{first_name}.{last_name}@{profession["key"]}.reproot.demo'.lower()
      is_portal = index == 0
      username = f'{first_name}.{last_name}'.lower().replace(' ', '') if is_portal else None
      joined = self.today - timedelta(days=self.history_days + self.random.randint(5, 60))

      defaults = {
        'group': groups[group_name],
        'first_name': first_name,
        'last_name': last_name,
        'onboarding_method': ClientAccess.ONBOARDING_MANUAL,
        'has_portal_access': is_portal,
        'username': username,
        'temporary_password': make_password(portal_password) if is_portal else None,
        'must_change_password': False,
        'registration_answers': {
          'first_name': first_name,
          'last_name': last_name,
          'email': email,
          'joined_on': joined.isoformat(),
        },
        'professional_notes': self.client_note(profession, first_name, group_name),
        'is_active': True,
        'terms_accepted': True,
        'privacy_policy_accepted': True,
        'legal_document_version': django_settings.REPROOT_CLIENT_LEGAL_VERSION,
      }
      client, _created = ClientAccess.objects.update_or_create(
        professional=professional,
        email=email,
        defaults=defaults,
      )
      clients.append(client)
    return clients, portal_password

  def client_note(self, profession, first_name, group_name):
    return f'{first_name} is in {group_name}. Demo record created for {profession["professional_type"].lower()} testing.'

  def seed_assignments(self, clients, templates, resources):
    by_index = {}
    for position, (template, _definition) in enumerate(templates):
      start = (position * 3) % max(len(resources), 1)
      by_index[template.id] = resources[start:start + 3]
    for client in clients:
      for template, _definition in templates:
        assignment, _created = TemplateAssignment.objects.get_or_create(client=client, template=template)
        assignment.resources.set(by_index.get(template.id, []))

  # -- tracked history ----------------------------------------------------

  def seed_entries(self, client, templates, client_index):
    start = self.today - timedelta(days=self.history_days - 1)
    rows = []

    for position, (template, definition) in enumerate(templates):
      dates = self.entry_dates(definition, start, client_index)
      total = max(len(dates) - 1, 1)
      for step, entry_date in enumerate(dates):
        progress = step / total
        rows.append(
          TrackingEntry(
            client=client,
            template=template,
            template_name=template.name,
            entry_date=entry_date,
            entry_time=time(hour=(7 + position * 2) % 22, minute=self.random.choice([0, 15, 30, 45])),
            answers={
              field['key']: self.sample_value(field, progress, entry_date)
              for field in definition['fields']
            },
            note='',
            # Only the portal client fills anything in themselves; for everyone
            # else the professional is the one keeping the record.
            edited_by_professional=client_index != 0,
          )
        )

    TrackingEntry.objects.bulk_create(rows, batch_size=500)

  def entry_dates(self, definition, start, client_index):
    """Dates are thinned per client so no two clients have identical history --
    a demo where every row lines up perfectly reads as fake immediately."""
    dates = []
    cadence = definition['cadence']

    if cadence == 'daily':
      per_week = definition.get('days_per_week', 7)
      day = start
      while day <= self.today:
        if per_week >= 7 or (day.weekday() < per_week):
          # Everyone misses the occasional day.
          if self.random.random() > 0.06:
            dates.append(day)
        day += timedelta(days=1)
      return dates

    # A weekly or monthly template can legitimately be filled in more than
    # once per period -- a consultant records several consultations a week --
    # so `repeat` spreads that many entries across each period.
    offsets = {1: [0], 2: [0, 3], 3: [0, 2, 4]}[min(max(definition.get('repeat', 1), 1), 3)]

    if cadence == 'weekly':
      weekday = (client_index + 6) % 7
      day = start
      while day.weekday() != weekday and day <= self.today:
        day += timedelta(days=1)
      while day <= self.today:
        for offset in offsets:
          moment = day + timedelta(days=offset)
          if moment <= self.today:
            dates.append(moment)
        day += timedelta(days=7)
      return dates

    day = start + timedelta(days=(client_index % 7))
    while day <= self.today:
      for offset in offsets:
        moment = day + timedelta(days=offset * 3)
        if moment <= self.today:
          dates.append(moment)
      day += timedelta(days=30)
    return dates

  def sample_value(self, field, progress, entry_date):
    """Turn a field's `sample` spec into a plausible value.

    Vocabulary:
      ('const', v)                  a fixed value
      ('int', lo, hi)               whole number in range
      ('float', lo, hi, digits)     decimal in range
      ('pct', lo, hi)               whole percentage
      ('rating', lo, hi)            rating within the field's scale
      ('trend_rating', lo, hi)      rating that improves across the history
      ('trend', start, end, jitter, digits)
                                    a value moving from start to end with noise
      ('choice', [..])              one option, evenly
      ('weighted', [(v, p), ..])    one option, by probability
      ('bool', p_yes)               Yes / No
      ('text', [..])                one of several written notes
      ('datestr', lo_days, hi_days) a date near the entry, as readable text
    """
    kind = field['sample'][0]
    spec = field['sample'][1:]

    if kind == 'const':
      return spec[0]
    if kind == 'int':
      return self.random.randint(spec[0], spec[1])
    if kind == 'float':
      return round(self.random.uniform(spec[0], spec[1]), spec[2])
    if kind == 'pct':
      return self.random.randint(spec[0], spec[1])
    if kind == 'rating':
      return self.random.randint(spec[0], spec[1])
    if kind == 'trend_rating':
      low, high = spec
      value = low + (high - low) * progress + self.random.uniform(-0.6, 0.6)
      return int(max(low, min(high, round(value))))
    if kind == 'trend':
      start_value, end_value, jitter, digits = spec
      value = start_value + (end_value - start_value) * progress + self.random.uniform(-jitter, jitter)
      return round(value, digits) if digits else int(round(value))
    if kind == 'choice':
      return self.random.choice(spec[0])
    if kind == 'weighted':
      options = spec[0]
      roll = self.random.random()
      running = 0.0
      for value, weight in options:
        running += weight
        if roll <= running:
          return value
      return options[-1][0]
    if kind == 'bool':
      return 'Yes' if self.random.random() < spec[0] else 'No'
    if kind == 'text':
      return self.random.choice(spec[0])
    if kind == 'datestr':
      offset = self.random.randint(spec[0], spec[1])
      return (entry_date + timedelta(days=offset)).strftime('%d %B %Y')
    return ''

  # -- schedule -----------------------------------------------------------

  def seed_scheduling(self, professional, clients):
    ProfessionalSchedulingSettings.objects.update_or_create(
      professional=professional,
      defaults={'timezone': 'UTC', 'default_duration_minutes': 45, 'slot_interval_minutes': 30, 'buffer_minutes': 15},
    )
    for weekday in range(0, 5):
      ProfessionalAvailabilityWindow.objects.get_or_create(
        professional=professional,
        weekday=weekday,
        start_time=time(9, 0),
        end_time=time(17, 0),
        defaults={'is_active': True},
      )

    meetings = []
    for index, client in enumerate(clients):
      for back in (42, 21, 7):
        day = self.today - timedelta(days=back + index)
        meetings.append(ScheduledMeeting(
          professional=professional,
          client=client,
          title=f'Review session with {client.first_name}',
          start_at=aware(day, 10 + (index % 6)),
          end_at=aware(day, 10 + (index % 6)) + timedelta(minutes=45),
          status=ScheduledMeeting.STATUS_COMPLETED,
          client_response_status=ScheduledMeeting.RESPONSE_ACCEPTED,
          requested_by=ScheduledMeeting.REQUESTED_BY_PROFESSIONAL,
        ))

      ahead = self.today + timedelta(days=2 + (index % 12))
      meetings.append(ScheduledMeeting(
        professional=professional,
        client=client,
        title=f'Check-in with {client.first_name}',
        start_at=aware(ahead, 9 + (index % 7)),
        end_at=aware(ahead, 9 + (index % 7)) + timedelta(minutes=45),
        status=ScheduledMeeting.STATUS_SCHEDULED,
        client_response_status=ScheduledMeeting.RESPONSE_ACCEPTED,
        requested_by=ScheduledMeeting.REQUESTED_BY_PROFESSIONAL,
      ))

    # Two requests waiting on the professional, so the Schedule page opens with
    # something to act on rather than an empty approvals box.
    for index, client in enumerate(clients[:2]):
      day = self.today + timedelta(days=3 + index)
      meetings.append(ScheduledMeeting(
        professional=professional,
        client=client,
        title=f'{client.first_name} requested a session',
        notes='Requested through the client portal.',
        start_at=aware(day, 16),
        end_at=aware(day, 16) + timedelta(minutes=45),
        status=ScheduledMeeting.STATUS_PENDING_APPROVAL,
        client_response_status=ScheduledMeeting.RESPONSE_ACCEPTED,
        requested_by=ScheduledMeeting.REQUESTED_BY_CLIENT,
      ))

    ScheduledMeeting.objects.bulk_create(meetings, batch_size=200)

  def seed_follow_ups(self, professional, clients):
    reminders = []
    notes = []
    for index, client in enumerate(clients):
      reminders.append(ClientReminder(
        professional=professional,
        client=client,
        title=f'Follow up with {client.first_name}',
        date=self.today + timedelta(days=2 + (index % 10)),
        notes='Check progress since the last review and confirm the next block.',
        status=ClientReminder.STATUS_PENDING,
      ))
      reminders.append(ClientReminder(
        professional=professional,
        client=client,
        title=f'Send {client.first_name} the updated plan',
        date=self.today - timedelta(days=6 + index),
        notes='Sent and acknowledged.',
        status=ClientReminder.STATUS_DONE,
      ))
      for step, back in enumerate((60, 30, 10)):
        notes.append(ProgressEntry(
          client=client,
          professional=professional,
          title=['Starting point', 'Mid-point review', 'Latest review'][step],
          date=self.today - timedelta(days=back + index),
          notes='Reviewed the tracked history together and agreed the next step.',
          status=['Baseline recorded', 'On track', 'On track'][step],
          next_step=['Begin the first block', 'Continue as planned', 'Increase the target slightly'][step],
          created_by=professional.get_full_name() or professional.username,
        ))
    ClientReminder.objects.bulk_create(reminders, batch_size=200)
    ProgressEntry.objects.bulk_create(notes, batch_size=200)

  # -- payments -----------------------------------------------------------

  def seed_payments(self, professional, profession, clients):
    currency = profession['currency']
    ProfessionalPaymentSettings.objects.update_or_create(
      professional=professional,
      defaults={
        'payment_tracking_enabled': True,
        'reporting_currency': currency,
        'reporting_currency_locked': True,
        'reporting_currency_locked_at': timezone.now(),
        'client_payment_history_enabled': True,
      },
    )

    methods = []
    for category, name, label, private_fields, instructions in profession['payment_methods']:
      method, _created = ManualPaymentProfile.objects.update_or_create(
        professional=professional,
        category=category,
        defaults={
          'name': name,
          'display_label': label,
          'supported_currencies': [currency],
          'private_fields': private_fields,
          'client_visible_fields': private_fields,
          'client_instructions': instructions,
          'status': ManualPaymentProfile.STATUS_ACTIVE,
        },
      )
      methods.append(method)

    amount = Decimal(profession['plan_price'])
    plan, _created = PaymentPlan.objects.update_or_create(
      professional=professional,
      name=profession['plan_name'],
      defaults={
        'description': f'Standard {profession["plan_name"].lower()} used across demo clients.',
        'amount': amount,
        'currency': currency,
        'billing_cycle': 'monthly',
        'status': 'active',
      },
    )

    from admin_portal.models import FinanceLedgerEntry

    ledger_rows = []
    for index, client in enumerate(clients):
      # One client per professional is behind, one has an open request under
      # review, and the rest are up to date -- which is what a real book looks
      # like and gives every payment status something to render.
      behind = index == 2
      under_review = index == 1
      open_request = index == 0

      for month_back in range(PAYMENT_MONTHS, 0, -1):
        # Staggered by client so billing dates are spread across the month
        # rather than every client falling due on the same day -- which also
        # means the last seven days always contain some real revenue for the
        # dashboard's default period.
        due_date = self.today - timedelta(days=30 * (month_back - 1) + (index % 26))
        is_latest = month_back == 1
        sent_at = aware(due_date - timedelta(days=5), 9)

        request = PaymentRequest.objects.create(
          professional=professional,
          client=client,
          payment_plan=plan,
          title=f'{profession["plan_name"]} — {due_date.strftime("%B %Y")}',
          description=f'{profession["plan_name"]} for {due_date.strftime("%B %Y")}.',
          requested_amount=amount,
          requested_currency=currency,
          due_date=due_date,
          payment_type='manual',
          status=PaymentRequest.STATUS_SENT,
          client_visibility='visible',
          sent_at=sent_at,
        )
        PaymentRequest.objects.filter(id=request.id).update(created_at=sent_at)
        for method in methods:
          PaymentRequestAllowedMethod.objects.create(payment_request=request, manual_payment_profile=method)

        if behind and month_back <= 2:
          PaymentRequest.objects.filter(id=request.id).update(status=PaymentRequest.STATUS_OVERDUE)
          continue

        if is_latest and under_review:
          paid_date = due_date + timedelta(days=1)
          proof = PaymentProof.objects.create(
            payment_request=request,
            submitted_by=client.username or client.email,
            transaction_reference=f'DEMO-{request.request_id}',
            reported_amount=amount,
            reported_currency=currency,
            reported_payment_date=paid_date,
            payment_method=methods[0],
            note='Paid this morning, screenshot attached.',
            confirmed_accurate=True,
            status=PaymentProof.STATUS_SUBMITTED,
          )
          PaymentProof.objects.filter(id=proof.id).update(submitted_at=aware(paid_date, 11))
          PaymentRequest.objects.filter(id=request.id).update(
            status=PaymentRequest.STATUS_PROOF_SUBMITTED,
            viewed_at=sent_at + timedelta(days=1),
          )
          continue

        if is_latest and open_request:
          PaymentRequest.objects.filter(id=request.id).update(
            status=PaymentRequest.STATUS_VIEWED,
            viewed_at=sent_at + timedelta(days=1),
          )
          continue

        paid_date = due_date + timedelta(days=self.random.randint(0, 4))
        if paid_date > self.today:
          paid_date = self.today
        paid_at = aware(paid_date, 12)
        method = methods[index % len(methods)]

        # Half the clients pay and upload a proof the professional accepts;
        # for the other half the professional logs the payment directly, which
        # is what happens with cash and bank transfers. The revenue rollup
        # counts only directly-logged records, so a demo built entirely out of
        # proofs would show a revenue dashboard of zero.
        proof = None
        if index % 2 == 1:
          proof = PaymentProof.objects.create(
            payment_request=request,
            submitted_by=client.username or client.email,
            transaction_reference=f'DEMO-{request.request_id}',
            reported_amount=amount,
            reported_currency=currency,
            reported_payment_date=paid_date,
            payment_method=method,
            note=f'Paid by {method.name}.',
            confirmed_accurate=True,
            status=PaymentProof.STATUS_ACCEPTED,
          )
          PaymentProof.objects.filter(id=proof.id).update(submitted_at=paid_at, reviewed_at=paid_at)

        record = PaymentRecord.objects.create(
          professional=professional,
          client=client,
          payment_request=request,
          source_proof=proof,
          original_amount=amount,
          original_currency=currency,
          reporting_amount=amount,
          reporting_currency=currency,
          exchange_rate_source='manual',
          payment_method=method,
          transaction_reference=(proof.transaction_reference if proof else f'DEMO-{request.request_id}'),
          received_date=paid_date,
          status=PaymentRecord.STATUS_COMPLETED,
          client_visibility='visible',
          verified_by=professional,
          verified_at=paid_at,
        )
        PaymentRecord.objects.filter(id=record.id).update(created_at=paid_at)
        PaymentRequest.objects.filter(id=request.id).update(
          status=PaymentRequest.STATUS_COMPLETED,
          viewed_at=sent_at + timedelta(days=1),
          completed_at=paid_at,
        )

        ledger_rows.append(FinanceLedgerEntry(
          entry_type=FinanceLedgerEntry.TYPE_PAYMENT,
          status=FinanceLedgerEntry.STATUS_COMPLETED,
          amount=record.reporting_amount,
          currency=record.reporting_currency,
          professional=professional,
          description=f'Client payment {record.payment_record_id}',
          external_reference=record.transaction_reference,
          occurred_at=paid_at,
        ))

    FinanceLedgerEntry.objects.bulk_create(ledger_rows, batch_size=200)

  # -- conversation and inbound work --------------------------------------

  def seed_chat(self, professional, profession, client):
    sent_at = timezone.now() - timedelta(days=len(profession['chat']) + 2)
    for position, (sender, text) in enumerate(profession['chat']):
      message = ChatMessage.objects.create(
        professional=professional,
        client=client,
        sender=(ChatMessage.SENDER_PROFESSIONAL if sender == 'professional' else ChatMessage.SENDER_CLIENT),
        text=text,
        # The last two messages from the client stay unread, so the dashboard
        # has genuine unread activity to show.
        is_read=not (sender == 'client' and position >= len(profession['chat']) - 2),
      )
      ChatMessage.objects.filter(id=message.id).update(created_at=sent_at + timedelta(days=position))

  def seed_pending_work(self, professional, profession, lead_form, groups):
    enquiries = [
      ('Jordan', 'Blake'), ('Amelia', 'Ford'), ('Hassan', 'Karim'), ('Beatriz', 'Lima'),
    ]
    for index, (first_name, last_name) in enumerate(enquiries):
      email = f'{first_name}.{last_name}@enquiry.reproot.demo'.lower()
      submission = LeadSubmission.objects.create(
        lead_form=lead_form,
        first_name=first_name,
        last_name=last_name,
        email=email,
        reference_id=f'DEMO-{profession["key"].upper()}-{index + 1:03d}',
        answers={'first_name': first_name, 'last_name': last_name, 'email': email},
        status=LeadSubmission.STATUS_PENDING,
        is_active=True,
      )
      submitted = timezone.now() - timedelta(days=index + 1)
      LeadSubmission.objects.filter(id=submission.id).update(submitted_at=submitted)

      if index < 2:
        start = aware(self.today + timedelta(days=3 + index), 15)
        LeadMeetingRequest.objects.create(
          submission=submission,
          requested_start=start,
          requested_end=start + timedelta(minutes=15),
          contact_email=email,
          status=LeadMeetingRequest.STATUS_PENDING,
          expires_at=start + timedelta(days=2),
        )

    first_group = next(iter(groups.values()))
    for index, (first_name, last_name) in enumerate([('Marta', 'Kowalski'), ('Elias', 'Berg')]):
      email = f'{first_name}.{last_name}@registration.reproot.demo'.lower()
      GroupRegistrationSubmission.objects.create(
        group=first_group,
        first_name=first_name,
        last_name=last_name,
        email=email,
        answers={'first_name': first_name, 'last_name': last_name, 'email': email},
        status=GroupRegistrationSubmission.STATUS_PENDING,
      )

  # -- output -------------------------------------------------------------

  def report(self, credentials, output_path):
    lines = [
      '# RepRoot demo accounts',
      '',
      f'Generated {self.today.strftime("%d %B %Y")}. Every professional is on the Free plan '
      f'with {self.history_days} days of tracked history.',
      '',
      'Clients sign in with the professional code, their own username, and their password.',
      '',
    ]

    for entry in credentials:
      profession = entry['profession']
      client = entry['portal_client']
      lines += [
        f'## {profession["first_name"]} {profession["last_name"]} — {profession["professional_type"]}',
        '',
        '| | |',
        '| --- | --- |',
        f'| Professional login | `{profession["username"]}` |',
        f'| Password | `{entry["professional_password"]}` |',
        f'| Professional code | `{profession["professional_id"]}` |',
        f'| Reporting currency | {profession["currency"]} (locked) |',
        f'| Clients | {entry["client_count"]} ({entry["client_count"] - 1} record-only) |',
        '',
        '**Demo client login**',
        '',
        '| | |',
        '| --- | --- |',
        f'| Professional code | `{profession["professional_id"]}` |',
        f'| Client username | `{client.username}` |',
        f'| Password | `{entry["portal_password"]}` |',
        f'| Name | {client.first_name} {client.last_name} |',
        '',
      ]

    document = '\n'.join(lines)

    if output_path:
      with open(output_path, 'w', encoding='utf-8') as handle:
        handle.write(document + '\n')

    self.stdout.write('')
    self.stdout.write(self.style.SUCCESS(f'Seeded {len(credentials)} demo professionals.'))
    self.stdout.write('')
    for entry in credentials:
      profession = entry['profession']
      client = entry['portal_client']
      self.stdout.write(f'{profession["professional_type"]}')
      self.stdout.write(f'  professional : {profession["username"]} / {entry["professional_password"]}')
      self.stdout.write(f'  code         : {profession["professional_id"]}')
      self.stdout.write(f'  demo client  : {client.username} / {entry["portal_password"]}')
      self.stdout.write('')
    if output_path:
      self.stdout.write(self.style.SUCCESS(f'Credentials written to {output_path}'))
