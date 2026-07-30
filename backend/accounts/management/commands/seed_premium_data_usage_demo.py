"""
Seed a Premium-tier professional account with heavy, purely-synthetic
TEXT-based data (many groups, many clients, long chat/tracking/progress
text) so real Data Usage MB/GB numbers can be observed against a paid
plan's quota -- see the "Data Usage MB/GB for Pro/Premium" feature and the
plan-limit lock system's storage-usage exclusion logic.

No real names, emails, or any other PII are used anywhere here -- every
client is a numbered placeholder on the @reproot-demo.local domain, and all
body text is generic coaching-style filler generated from small template
pools. This is safe to run repeatedly (idempotent via get_or_create /
update_or_create) and safe to point at any environment.
"""

import random
from datetime import date, time, timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token

from accounts.client_auth import issue_client_token
from accounts.models import (
  ChatMessage,
  ClientAccess,
  ClientRegistrationForm,
  LeadSubmission,
  ProgressEntry,
  ResourceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalProfile,
  ProfessionalResource,
  default_client_registration_fields,
)
from accounts.plan_lock_status import bust_lock_status_cache

User = get_user_model()

PROFESSIONAL_USERNAME = 'premium_usage_demo'
PROFESSIONAL_EMAIL = 'premium-usage-demo@reproot-demo.local'
PROFESSIONAL_PASSWORD = 'PremiumUsageDemo!2026'
CLIENT_PASSWORD = 'PremiumClientDemo!2026'

GROUP_COUNT = 15          # Premium allows 25 -- leaves headroom to test the lock system by hand
CLIENTS_PER_GROUP = 4     # 60 clients total
TRACKING_DAYS = 90        # ~3 months of daily history per client
CHAT_MESSAGES_PER_CLIENT = 40
PROGRESS_ENTRIES_PER_CLIENT = 6
RESOURCE_CATEGORY_COUNT = 10
RESOURCES_PER_CATEGORY = 4

random.seed(20260730)  # deterministic output run-to-run

# Long-form filler paragraphs -- generic coaching language, no PII, reused
# and lightly varied across clients/days to build up realistic text volume
# without needing hundreds of hand-written strings.
NOTE_PARAGRAPHS = [
  'Session felt controlled today. Focused on keeping tempo steady through the working sets and '
  'kept rest periods consistent. Energy was solid through the first half and tapered slightly '
  'toward the end, which tracks with the reported sleep total from last night.',
  'Client reported the meal plan was easier to follow this week now that prep happens on Sunday '
  'evening instead of daily. Protein target was hit on five of seven days. Hydration is still the '
  'most inconsistent habit and worth a specific reminder next check-in.',
  'Noticed some tightness through the hips during the warm-up, so we backed off range of motion on '
  'the loaded work and substituted a mobility-focused finisher instead. No pain reported, just '
  'general stiffness that eased with movement.',
  'Great consistency this week across all tracked habits. Sleep, water, and workout completion were '
  'all above the running average. This is a good week to nudge intensity slightly on the primary '
  'lift while keeping accessory volume the same.',
  'Schedule was disrupted by a work trip, so we shifted to a shorter home-based routine using just '
  'bodyweight and a resistance band. Client stayed engaged despite the change, which is a good sign '
  'for long-term adherence beyond the structured gym sessions.',
  'Weekly check-in covered stress levels, which were elevated due to a deadline at work. We agreed '
  'to keep training volume the same but added an extra short walk most days to help with recovery '
  'and general stress management outside the gym.',
  'Form on the main lift continues to improve -- bar path is more consistent and there is less '
  'compensation through the lower back on heavier sets. Cueing around bracing before each rep seems '
  'to be translating well from the last few sessions.',
  'Nutrition notes: client experimented with a new breakfast option this week that includes more '
  'protein up front. Reported feeling less hungry mid-morning as a result, which is worth continuing '
  'and building the rest of the day\'s meals around.',
]

FOLLOWUP_QUESTIONS = [
  'How did the new warm-up feel before today\'s session?',
  'Any soreness left over from the last workout, especially through the lower back?',
  'Were you able to hit the water target most days this week?',
  'How is sleep trending compared to last week\'s average?',
  'Did the meal prep plan make weekday dinners easier to manage?',
  'Any schedule conflicts coming up we should plan around next week?',
]

CLIENT_REPLIES = [
  'Feeling good overall, energy was a bit low mid-week but bounced back by the weekend.',
  'Yes, stuck to the plan most days -- missed one day because of a late meeting.',
  'A little sore through the hips but nothing that affected the workout.',
  'Sleep was actually better this week, averaged closer to seven and a half hours.',
  'Meal prep is helping a lot, dinners are much less stressful now.',
  'Should be a normal week, no major schedule conflicts I can see right now.',
]

GROUP_THEMES = [
  'Strength Foundations', 'Habit Building', 'Return to Training', 'Endurance Base',
  'Busy Professionals', 'Mobility Focus', 'General Fitness', 'Nutrition First',
  'Beginner Onboarding', 'Consistency Track', 'Recomposition Focus', 'Active Recovery',
  'Weekend Warriors', 'Home Training', 'Accountability Group',
]

RESOURCE_CATEGORY_NAMES = [
  'Coaching Notes', 'Program Guides', 'Nutrition Reference', 'Recovery Reference',
  'Habit Frameworks', 'Onboarding Reference', 'Mobility Reference', 'Check-in Templates',
  'Progress Frameworks', 'General Reference',
]

TEMPLATES = [
  {
    'name': 'Daily Check-In',
    'purpose': 'Daily habit and readiness tracking with a written reflection.',
    'cadence': 'daily',
    'accent': 'green',
    'fields': [
      {'key': 'workout_completed', 'label': 'Workout completed?', 'field_type': 'yes_no', 'placeholder': '', 'options': [], 'scale': None},
      {'key': 'energy', 'label': 'Energy level', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
      {'key': 'reflection', 'label': 'Daily reflection', 'field_type': 'long_text', 'placeholder': 'How did today go?', 'options': [], 'scale': None},
    ],
  },
  {
    'name': 'Training Log',
    'purpose': 'Session-by-session strength and conditioning notes.',
    'cadence': 'daily',
    'accent': 'blue',
    'fields': [
      {'key': 'session_notes', 'label': 'Session notes', 'field_type': 'long_text', 'placeholder': 'What did you work on?', 'options': [], 'scale': None},
      {'key': 'effort', 'label': 'Effort', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 10},
    ],
  },
  {
    'name': 'Weekly Review',
    'purpose': 'A longer-form weekly reflection on progress and barriers.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      {'key': 'weekly_summary', 'label': 'Weekly summary', 'field_type': 'long_text', 'placeholder': 'Summarize the week', 'options': [], 'scale': None},
      {'key': 'next_focus', 'label': 'Focus for next week', 'field_type': 'long_text', 'placeholder': '', 'options': [], 'scale': None},
    ],
  },
]


def _sample_paragraph(seedable_index):
  return NOTE_PARAGRAPHS[seedable_index % len(NOTE_PARAGRAPHS)]


class Command(BaseCommand):
  help = (
    'Seed a Premium-tier professional account with many groups/clients and heavy, purely '
    'synthetic text data (chat, tracking entries, progress notes) so real Data Usage MB/GB '
    'numbers can be observed. No real names, emails, or PII are used.'
  )

  def add_arguments(self, parser):
    parser.add_argument('--groups', type=int, default=GROUP_COUNT)
    parser.add_argument('--clients-per-group', type=int, default=CLIENTS_PER_GROUP)
    parser.add_argument('--tracking-days', type=int, default=TRACKING_DAYS)

  def handle(self, *args, **options):
    group_count = options['groups']
    clients_per_group = options['clients_per_group']
    tracking_days = options['tracking_days']

    with transaction.atomic():
      professional = self.seed_professional()
      groups = self.seed_groups(professional, group_count)
      lead_form = self.seed_lead_form(professional)
      categories, resources = self.seed_resources(professional)
      templates = self.seed_templates(professional)
      clients = self.seed_clients(professional, groups, lead_form, clients_per_group)
      self.seed_assignments(clients, templates, resources)
      self.seed_tracking(clients, templates, tracking_days)
      self.seed_progress(professional, clients)
      self.seed_chat(professional, clients)

    bust_lock_status_cache(professional)
    cache.delete(f'professional-data-usage:v5:{professional.pk}')

    professional_token, _created = Token.objects.get_or_create(user=professional)
    sample_client = clients[0]
    sample_client_token = issue_client_token(sample_client)

    total_entries = TrackingEntry.objects.filter(client__professional=professional).count()
    total_chat = ChatMessage.objects.filter(professional=professional).count()
    total_progress = ProgressEntry.objects.filter(professional=professional).count()

    self.stdout.write(self.style.SUCCESS('Premium Data Usage demo account seeded successfully.'))
    self.stdout.write(f'Professional login: {PROFESSIONAL_USERNAME} / {PROFESSIONAL_PASSWORD}')
    self.stdout.write(f'Professional token: {professional_token.key}')
    self.stdout.write(f'Sample client login: username={sample_client.username}, password={CLIENT_PASSWORD}')
    self.stdout.write(f'Sample client token: {sample_client_token.key}')
    self.stdout.write(
      f'Created/updated: {len(groups)} groups, {len(clients)} clients, {len(categories)} resource '
      f'categories, {len(resources)} resources, {len(templates)} templates, {total_entries} tracking '
      f'entries, {total_chat} chat messages, {total_progress} progress entries.'
    )
    self.stdout.write(
      'Open Settings > Plan & Billing > Data Usage as this professional to see the MB/GB column '
      '(Pro/Premium only) next to each section\'s percentage.'
    )

  def seed_professional(self):
    professional, _created = User.objects.get_or_create(
      username=PROFESSIONAL_USERNAME,
      defaults={'email': PROFESSIONAL_EMAIL, 'first_name': 'Premium', 'last_name': 'Demo'},
    )
    professional.email = PROFESSIONAL_EMAIL
    professional.set_password(PROFESSIONAL_PASSWORD)
    professional.is_active = True
    professional.save()

    profile, _created = ProfessionalProfile.objects.get_or_create(user=professional)
    profile.plan_tier = ProfessionalProfile.PLAN_PREMIUM_UNLIMITED
    profile.professional_id = profile.professional_id or 'premium-usage-demo'
    profile.profile_setup_completed = True
    profile.is_locked = False
    profile.locked_at = None
    profile.lock_reason = ''
    profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_ACTIVE
    profile.lifecycle_reason = ''
    profile.professional_headline = 'Data Usage demo account (synthetic data only)'
    profile.about_me = 'This account exists only to generate realistic text-data volume for testing Data Usage reporting.'
    profile.professional_type = 'Demo Account'
    profile.save()
    return professional

  def seed_groups(self, professional, group_count):
    groups = []
    for index in range(group_count):
      theme = GROUP_THEMES[index % len(GROUP_THEMES)]
      name = f'{theme} {index // len(GROUP_THEMES) + 1}' if index >= len(GROUP_THEMES) else theme
      group, _created = ProfessionalGroup.objects.update_or_create(
        professional=professional,
        name=name,
        defaults={'description': f'Synthetic demo group for {theme.lower()} coaching.', 'is_active': True},
      )
      ClientRegistrationForm.objects.update_or_create(
        group=group,
        defaults={'fields': default_client_registration_fields(), 'is_active': True},
      )
      groups.append(group)
    return groups

  def seed_lead_form(self, professional):
    lead_form, _created = ProfessionalLeadForm.objects.update_or_create(
      professional=professional,
      defaults={
        'public_slug': 'premium-usage-demo-intake',
        'title': 'Premium Usage Demo Intake Form',
        'fields': default_client_registration_fields(),
        'is_active': True,
      },
    )
    return lead_form

  def seed_resources(self, professional):
    categories = []
    for index in range(RESOURCE_CATEGORY_COUNT):
      name = RESOURCE_CATEGORY_NAMES[index % len(RESOURCE_CATEGORY_NAMES)]
      label = f'{name} {index // len(RESOURCE_CATEGORY_NAMES) + 1}' if index >= len(RESOURCE_CATEGORY_NAMES) else name
      category, _created = ResourceCategory.objects.update_or_create(
        professional=professional,
        name=label,
        defaults={'description': f'Synthetic reference material for {label.lower()}.', 'subcategories': ['General']},
      )
      categories.append(category)

    resources = []
    for category_index, category in enumerate(categories):
      for resource_index in range(RESOURCES_PER_CATEGORY):
        title = f'{category.name} Note {resource_index + 1}'
        body = _sample_paragraph(category_index * RESOURCES_PER_CATEGORY + resource_index)
        resource, _created = ProfessionalResource.objects.update_or_create(
          professional=professional,
          title=title,
          defaults={
            'category': category,
            'subcategory': 'General',
            'resource_type': ProfessionalResource.TYPE_TEXT_NOTE,
            'description': body,
            'link': '',
            'tags': ['demo', 'synthetic'],
          },
        )
        resources.append(resource)
    return categories, resources

  def seed_templates(self, professional):
    templates = []
    for data in TEMPLATES:
      template, _created = TrackingTemplate.objects.update_or_create(
        professional=professional,
        name=data['name'],
        defaults={
          'purpose': data['purpose'],
          'cadence': data['cadence'],
          'accent': data['accent'],
          'fields': data['fields'],
          'standard_key': '',
          'is_active': True,
        },
      )
      templates.append(template)
    return templates

  def seed_clients(self, professional, groups, lead_form, clients_per_group):
    clients = []
    counter = 0
    for group in groups:
      for slot in range(clients_per_group):
        counter += 1
        username = f'demo_client_{counter:03d}'
        email = f'{username}@reproot-demo.local'
        first_name = f'Demo{counter:03d}'
        last_name = 'Client'

        lead, _created = LeadSubmission.objects.update_or_create(
          reference_id=f'PREMIUM-DEMO-{counter:03d}',
          defaults={
            'lead_form': lead_form,
            'first_name': first_name,
            'last_name': last_name,
            'email': email,
            'answers': {'primary_goal': 'General Fitness', 'training_experience': 'Intermediate'},
            'status': LeadSubmission.STATUS_APPROVED,
            'is_active': True,
            'converted_at': timezone.now(),
          },
        )
        client, _created = ClientAccess.objects.update_or_create(
          professional=professional,
          email=email,
          defaults={
            'group': group,
            'lead_submission': lead,
            'first_name': first_name,
            'last_name': last_name,
            'username': username,
            'temporary_password': make_password(CLIENT_PASSWORD),
            'registration_answers': {'primary_goal': 'General Fitness', 'training_experience': 'Intermediate'},
            'professional_notes': _sample_paragraph(counter),
            'professional_notes_updated_at': timezone.now(),
            'must_change_password': False,
            'is_active': True,
          },
        )
        clients.append(client)
    return clients

  def seed_assignments(self, clients, templates, resources):
    for client_index, client in enumerate(clients):
      for template in templates:
        assignment, _created = TemplateAssignment.objects.get_or_create(client=client, template=template)
        start = (client_index * 3) % max(1, len(resources))
        assignment.resources.set(resources[start:start + 6])

  def seed_tracking(self, clients, templates, tracking_days):
    end_date = date.today()
    start_date = end_date - timedelta(days=tracking_days - 1)

    TrackingEntry.objects.filter(client__in=clients, template__in=templates, entry_date__gte=start_date).delete()

    entries = []
    for client_index, client in enumerate(clients):
      for day_index in range(tracking_days):
        entry_date = start_date + timedelta(days=day_index)
        for template_index, template in enumerate(templates):
          if template.cadence == 'weekly' and day_index % 7 != client_index % 7:
            continue

          paragraph_index = client_index + day_index + template_index
          if template.name == 'Daily Check-In':
            answers = {
              'workout_completed': 'Yes' if (day_index + client_index) % 6 != 4 else 'No',
              'energy': 2 + (day_index % 4),
              'reflection': _sample_paragraph(paragraph_index),
            }
          elif template.name == 'Training Log':
            answers = {
              'session_notes': _sample_paragraph(paragraph_index),
              'effort': 5 + (day_index % 5),
            }
          else:
            answers = {
              'weekly_summary': _sample_paragraph(paragraph_index),
              'next_focus': _sample_paragraph(paragraph_index + 1),
            }

          entries.append(
            TrackingEntry(
              client=client,
              template=template,
              template_name=template.name,
              entry_date=entry_date,
              entry_time=time(hour=7 + template_index),
              answers=answers,
              note=_sample_paragraph(paragraph_index + 2),
              edited_by_professional=False,
            )
          )

      # Flush per-client to keep memory bounded across a large seed run.
      TrackingEntry.objects.bulk_create(entries)
      entries = []

  def seed_progress(self, professional, clients):
    ProgressEntry.objects.filter(professional=professional, client__in=clients).delete()
    today = date.today()
    entries = []
    for client_index, client in enumerate(clients):
      for entry_index in range(PROGRESS_ENTRIES_PER_CLIENT):
        entries.append(
          ProgressEntry(
            professional=professional,
            client=client,
            title=f'Progress Review {entry_index + 1}',
            date=today - timedelta(days=(PROGRESS_ENTRIES_PER_CLIENT - entry_index) * 21),
            notes=_sample_paragraph(client_index + entry_index),
            status='On Track',
            next_step=_sample_paragraph(client_index + entry_index + 3),
            created_by='Demo Coach',
          )
        )
    ProgressEntry.objects.bulk_create(entries)

  def seed_chat(self, professional, clients):
    ChatMessage.objects.filter(professional=professional, client__in=clients).delete()
    messages = []
    for client_index, client in enumerate(clients):
      for message_index in range(CHAT_MESSAGES_PER_CLIENT):
        if message_index % 2 == 0:
          sender = ChatMessage.SENDER_PROFESSIONAL
          text = FOLLOWUP_QUESTIONS[(client_index + message_index) % len(FOLLOWUP_QUESTIONS)]
        else:
          sender = ChatMessage.SENDER_CLIENT
          text = CLIENT_REPLIES[(client_index + message_index) % len(CLIENT_REPLIES)]

        messages.append(
          ChatMessage(
            professional=professional,
            client=client,
            sender=sender,
            text=text,
            is_read=sender == ChatMessage.SENDER_PROFESSIONAL,
          )
        )
    ChatMessage.objects.bulk_create(messages)
