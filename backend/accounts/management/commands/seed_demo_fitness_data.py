from datetime import date, time, timedelta

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
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
  ReferenceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalProfile,
  ProfessionalReference,
  default_client_registration_fields,
)


User = get_user_model()


PROFESSIONAL_USERNAME = 'maya_coach'
PROFESSIONAL_EMAIL = 'maya.coach@example.com'
PROFESSIONAL_PASSWORD = 'ProfessionalDemo!2026'
CLIENT_PASSWORD = 'ClientDemo!2026'


GROUPS = [
  {
    'name': 'Strength Foundations',
    'description': 'Beginner to intermediate clients building movement quality, consistency, and baseline strength.',
  },
  {
    'name': '90-Day Transformation',
    'description': 'Clients focused on body composition, nutrition habits, weekly progress, and accountability.',
  },
]


CLIENTS = [
  ('Alex', 'Rivera', 'alex.rivera@example.com', 'alex_rivera', '90-Day Transformation', 'Weight Loss', 34, 'Moderately Active'),
  ('Priya', 'Shah', 'priya.shah@example.com', 'priya_shah', 'Strength Foundations', 'Strength', 29, 'Lightly Active'),
  ('Jordan', 'Miles', 'jordan.miles@example.com', 'jordan_miles', '90-Day Transformation', 'Muscle Gain', 41, 'Moderately Active'),
  ('Sam', 'Taylor', 'sam.taylor@example.com', 'sam_taylor', 'Strength Foundations', 'General Fitness', 36, 'Sedentary'),
  ('Nia', 'Brooks', 'nia.brooks@example.com', 'nia_brooks', '90-Day Transformation', 'Weight Loss', 27, 'Very Active'),
  ('Ethan', 'Cole', 'ethan.cole@example.com', 'ethan_cole', 'Strength Foundations', 'Mobility', 45, 'Lightly Active'),
  ('Lena', 'Morgan', 'lena.morgan@example.com', 'lena_morgan', '90-Day Transformation', 'Strength', 31, 'Moderately Active'),
  ('Omar', 'Bennett', 'omar.bennett@example.com', 'omar_bennett', 'Strength Foundations', 'Sports Performance', 24, 'Very Active'),
  ('Mia', 'Patel', 'mia.patel@example.com', 'mia_patel', '90-Day Transformation', 'General Fitness', 39, 'Lightly Active'),
  ('Noah', 'Kim', 'noah.kim@example.com', 'noah_kim', 'Strength Foundations', 'Muscle Gain', 33, 'Moderately Active'),
]


REFERENCE_CATEGORIES = [
  ('Warm-Up and Mobility', ['Hips', 'Shoulders', 'Ankles', 'Spine']),
  ('Strength Technique', ['Squat', 'Hinge', 'Push', 'Pull', 'Core']),
  ('Nutrition Habits', ['Meal Planning', 'Protein', 'Hydration', 'Portions']),
  ('Recovery and Mindset', ['Sleep', 'Stress', 'Consistency', 'Reflection']),
]


REFERENCES = [
  ('Warm-Up and Mobility', 'Hips', 'Hip Mobility Flow', 'video_link', 'Use before lower-body days to open hips and improve squat depth.', 'https://www.youtube.com/watch?v=jj2AAH6jbHk', ['mobility', 'warm-up']),
  ('Warm-Up and Mobility', 'Shoulders', 'Shoulder Prep Sequence', 'video_link', 'Quick shoulder activation before push or pull sessions.', 'https://www.youtube.com/watch?v=Vwn5hSf3WEg', ['shoulders', 'warm-up']),
  ('Warm-Up and Mobility', 'Ankles', 'Ankle Mobility Drill', 'video_link', 'Simple ankle work for better squat mechanics and walking comfort.', 'https://www.youtube.com/watch?v=IikP_teeLkI', ['ankles', 'mobility']),
  ('Warm-Up and Mobility', 'Spine', 'Thoracic Rotation Reset', 'text_note', 'Complete 2 sets of 8 rotations per side. Move slowly and breathe out at the end range.', '', ['spine', 'mobility']),
  ('Warm-Up and Mobility', 'Hips', 'Glute Activation Primer', 'text_note', 'Before training: 12 glute bridges, 10 lateral band walks each way, then 8 bodyweight squats.', '', ['glutes', 'activation']),
  ('Strength Technique', 'Squat', 'Goblet Squat Setup', 'video_link', 'Reference for foot position, bracing, and controlled depth.', 'https://www.youtube.com/watch?v=MeIiIdhvXT4', ['squat', 'technique']),
  ('Strength Technique', 'Hinge', 'Romanian Deadlift Form', 'video_link', 'Hinge pattern tutorial for hamstrings and posterior chain training.', 'https://www.youtube.com/watch?v=2SHsk9AzdjA', ['hinge', 'deadlift']),
  ('Strength Technique', 'Push', 'Push-Up Progressions', 'video_link', 'Choose wall, incline, knee, or floor push-ups based on current strength.', 'https://www.youtube.com/watch?v=IODxDxX7oi4', ['push', 'bodyweight']),
  ('Strength Technique', 'Pull', 'Dumbbell Row Technique', 'video_link', 'Pulling pattern reference for back engagement and shoulder position.', 'https://www.youtube.com/watch?v=pYcpY20QaE8', ['pull', 'dumbbell']),
  ('Strength Technique', 'Core', 'Dead Bug Coaching Notes', 'text_note', 'Keep ribs down, lower back quiet, and move only as far as control allows. Log which variation you used.', '', ['core', 'control']),
  ('Strength Technique', 'Squat', 'Rate of Perceived Exertion Guide', 'text_note', 'RPE 6 feels easy with 4 reps left. RPE 8 feels challenging with 2 reps left. Most demo workouts stay at RPE 6-8.', '', ['rpe', 'intensity']),
  ('Nutrition Habits', 'Meal Planning', 'Build a Balanced Plate', 'video_link', 'Use this structure for most meals: protein, produce, smart carbs, and healthy fats.', 'https://www.youtube.com/watch?v=Gmh_xMMJ2Pw', ['nutrition', 'plate']),
  ('Nutrition Habits', 'Protein', 'Protein Target Cheat Sheet', 'text_note', 'Aim for protein at each meal. Easy anchors: Greek yogurt, eggs, chicken, fish, tofu, beans, lentils, or protein powder.', '', ['protein', 'habits']),
  ('Nutrition Habits', 'Hydration', 'Daily Hydration Plan', 'text_note', 'Start with 500 ml after waking, then drink with each meal. Add electrolytes on heavy sweat days.', '', ['hydration']),
  ('Nutrition Habits', 'Portions', 'Portion Control Basics', 'video_link', 'Simple visual portion guidelines for clients who do not want to count calories.', 'https://www.youtube.com/watch?v=TYeZVfPxwKM', ['portions', 'nutrition']),
  ('Nutrition Habits', 'Meal Planning', 'Sunday Prep Checklist', 'text_note', 'Pick 2 proteins, 2 carbs, 3 vegetables, and 1 snack option. Prep only enough for 3-4 days to keep food fresh.', '', ['meal-prep']),
  ('Recovery and Mindset', 'Sleep', 'Sleep Routine Reset', 'text_note', 'Set a fixed wind-down time, dim screens 45 minutes before bed, and keep caffeine before noon where possible.', '', ['sleep', 'recovery']),
  ('Recovery and Mindset', 'Stress', 'Five-Minute Breathing Drill', 'video_link', 'Use on high-stress days before logging meals or training.', 'https://www.youtube.com/watch?v=inpok4MKVLM', ['breathing', 'stress']),
  ('Recovery and Mindset', 'Consistency', 'Missed Workout Rule', 'text_note', 'Never miss twice. If a full workout is not possible, complete the 10-minute minimum and log it honestly.', '', ['consistency']),
  ('Recovery and Mindset', 'Reflection', 'Weekly Review Prompts', 'text_note', 'What worked this week? What got in the way? What is one small adjustment for next week?', '', ['reflection', 'weekly']),
]


TEMPLATES = [
  {
    'name': 'Daily Nutrition Check-In',
    'purpose': 'Daily meals, hydration, protein, and notes for 90-day accountability.',
    'cadence': 'daily',
    'accent': 'green',
    'fields': [
      {'key': 'meals', 'label': 'Meals eaten today', 'field_type': 'long_text', 'placeholder': 'Breakfast, lunch, dinner, snacks', 'options': [], 'scale': None},
      {'key': 'water_liters', 'label': 'Water intake (liters)', 'field_type': 'number', 'placeholder': '2.5', 'options': [], 'scale': None},
      {'key': 'protein_servings', 'label': 'Protein servings', 'field_type': 'number', 'placeholder': '4', 'options': [], 'scale': None},
      {'key': 'nutrition_score', 'label': 'Nutrition score', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
    ],
  },
  {
    'name': 'Workout Performance Log',
    'purpose': 'Track training completion, intensity, and movement notes.',
    'cadence': 'daily',
    'accent': 'blue',
    'fields': [
      {'key': 'workout_done', 'label': 'Workout completed?', 'field_type': 'yes_no', 'placeholder': '', 'options': [], 'scale': None},
      {'key': 'session_focus', 'label': 'Session focus', 'field_type': 'dropdown', 'placeholder': 'Choose focus', 'options': ['Lower Body', 'Upper Body', 'Full Body', 'Cardio', 'Mobility'], 'scale': None},
      {'key': 'rpe', 'label': 'Effort level', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 10},
      {'key': 'training_notes', 'label': 'Training notes', 'field_type': 'long_text', 'placeholder': 'Weights, reps, energy, modifications', 'options': [], 'scale': None},
    ],
  },
  {
    'name': 'Recovery and Readiness',
    'purpose': 'Monitor sleep, soreness, stress, and readiness to train.',
    'cadence': 'daily',
    'accent': 'orange',
    'fields': [
      {'key': 'sleep_hours', 'label': 'Sleep hours', 'field_type': 'number', 'placeholder': '7.5', 'options': [], 'scale': None},
      {'key': 'soreness', 'label': 'Soreness', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
      {'key': 'stress', 'label': 'Stress', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
      {'key': 'readiness_note', 'label': 'Readiness note', 'field_type': 'short_text', 'placeholder': 'Ready, tired, sore, motivated', 'options': [], 'scale': None},
    ],
  },
]


def client_answers(first_name, last_name, email, goal, age, activity_level):
  return {
    'first_name': first_name,
    'last_name': last_name,
    'email': email,
    'phone_number': '555-0100',
    'date_of_birth': f'{date.today().year - age}-05-15',
    'age': age,
    'gender': 'Prefer not to say',
    'height': 170,
    'weight': 82,
    'primary_goal': goal,
    'activity_level': activity_level,
    'medical_conditions': 'No major injuries reported in demo data.',
    'address': 'Demo address, New York, NY',
  }


def entry_payload(template_name, day_index):
  if template_name == 'Daily Nutrition Check-In':
    return {
      'meals': 'Greek yogurt breakfast, chicken rice bowl lunch, salmon dinner, fruit snack.',
      'water_liters': round(2.2 + (day_index % 5) * 0.15, 2),
      'protein_servings': 3 + (day_index % 2),
      'nutrition_score': 3 + (day_index % 3),
    }

  if template_name == 'Workout Performance Log':
    focuses = ['Lower Body', 'Upper Body', 'Full Body', 'Cardio', 'Mobility']
    return {
      'workout_done': 'Yes' if day_index % 7 not in (3, 6) else 'No',
      'session_focus': focuses[day_index % len(focuses)],
      'rpe': 6 + (day_index % 4),
      'training_notes': 'Completed the planned session with controlled tempo and clean form.',
    }

  return {
    'sleep_hours': round(6.5 + (day_index % 5) * 0.25, 2),
    'soreness': 1 + (day_index % 5),
    'stress': 2 + (day_index % 4),
    'readiness_note': 'Steady energy and ready for the next planned step.',
  }


class Command(BaseCommand):
  help = 'Seed a complete demo professional, groups, clients, references, assignments, and 90 days of client inputs.'

  def handle(self, *args, **options):
    with transaction.atomic():
      professional = self.seed_professional()
      groups = self.seed_groups(professional)
      lead_form = self.seed_lead_form(professional)
      clients = self.seed_clients(professional, groups, lead_form)
      references = self.seed_references(professional)
      templates = self.seed_templates(professional)
      self.seed_assignments(clients, templates, references)
      self.seed_tracking_entries(clients[0], templates)
      self.seed_chat(professional, clients[0])

    professional_token, _created = Token.objects.get_or_create(user=professional)
    client_token = issue_client_token(clients[0])

    self.stdout.write(self.style.SUCCESS('Demo fitness data seeded successfully.'))
    self.stdout.write(f'Professional login: {PROFESSIONAL_USERNAME} / {PROFESSIONAL_PASSWORD}')
    self.stdout.write(f'Professional email: {PROFESSIONAL_EMAIL}')
    self.stdout.write(f'Professional token: {professional_token.key}')
    self.stdout.write(f'Client login: professional_id=coach-maya, username={clients[0].username}, password={CLIENT_PASSWORD}')
    self.stdout.write(f'Client token: {client_token.key}')
    self.stdout.write(f'Created/updated: 1 professional, {len(groups)} groups, {len(clients)} clients, {len(references)} references, {len(templates)} templates, 270 tracking entries for {clients[0].first_name}.')

  def seed_professional(self):
    professional, created = User.objects.get_or_create(
      username=PROFESSIONAL_USERNAME,
      defaults={
        'email': PROFESSIONAL_EMAIL,
        'first_name': 'Maya',
        'last_name': 'Santos',
      },
    )
    professional.email = PROFESSIONAL_EMAIL
    professional.first_name = 'Maya'
    professional.last_name = 'Santos'
    professional.set_password(PROFESSIONAL_PASSWORD)
    professional.save()

    profile, _profile_created = ProfessionalProfile.objects.get_or_create(user=professional)
    profile.professional_id = 'coach-maya'
    profile.profile_setup_completed = True
    profile.gender = 'Female'
    profile.state = 'New York'
    profile.country = 'United States'
    profile.birth_month = 4
    profile.birth_year = 1988
    profile.professional_headline = 'Strength, nutrition, and 90-day transformation coach'
    profile.about_me = 'Maya helps everyday clients build confident strength, simple nutrition habits, and sustainable progress without all-or-nothing pressure.'
    profile.professional_type = 'Personal Professional and Nutrition Coach'
    profile.years_experience = 9
    profile.specializations = 'Strength training, fat loss, habit coaching, beginner fitness, mobility'
    profile.training_style = 'Structured, supportive, data-informed, and focused on small daily wins.'
    profile.languages_known = 'English, Spanish'
    profile.certification_name = 'Certified Personal Professional'
    profile.certification_issued_by = 'NASM'
    profile.certification_year = 2017
    profile.intro_video_url = 'https://www.youtube.com/watch?v=ml6cT4AZdqI'
    profile.instagram_url = 'https://www.instagram.com/coachmaya.demo'
    profile.youtube_url = 'https://www.youtube.com/@coachmayademo'
    profile.website_url = 'https://coachmaya.example.com'
    profile.terms_accepted = True
    profile.privacy_policy_accepted = True
    profile.save()
    return professional

  def seed_groups(self, professional):
    groups = {}
    for group_data in GROUPS:
      group, _created = ProfessionalGroup.objects.update_or_create(
        professional=professional,
        name=group_data['name'],
        defaults={'description': group_data['description'], 'is_active': True},
      )
      ClientRegistrationForm.objects.update_or_create(
        group=group,
        defaults={'fields': default_client_registration_fields(), 'is_active': True},
      )
      groups[group.name] = group
    return groups

  def seed_lead_form(self, professional):
    lead_form, _created = ProfessionalLeadForm.objects.update_or_create(
      professional=professional,
      defaults={
        'public_slug': 'coach-maya-demo',
        'title': 'Coach Maya Demo Lead Form',
        'fields': default_client_registration_fields(),
        'is_active': True,
      },
    )
    return lead_form

  def seed_clients(self, professional, groups, lead_form):
    clients = []
    for index, (first_name, last_name, email, username, group_name, goal, age, activity_level) in enumerate(CLIENTS, start=1):
      answers = client_answers(first_name, last_name, email, goal, age, activity_level)
      lead, _created = LeadSubmission.objects.update_or_create(
        reference_id=f'DEMO-MAYA-{index:03d}',
        defaults={
          'lead_form': lead_form,
          'first_name': first_name,
          'last_name': last_name,
          'email': email,
          'answers': answers,
          'status': LeadSubmission.STATUS_APPROVED,
          'is_active': True,
          'converted_at': timezone.now(),
        },
      )
      client, _created = ClientAccess.objects.update_or_create(
        professional=professional,
        email=email,
        defaults={
          'group': groups[group_name],
          'lead_submission': lead,
          'first_name': first_name,
          'last_name': last_name,
          'username': username,
          'temporary_password': make_password(CLIENT_PASSWORD),
          'registration_answers': answers,
          'professional_notes': f'Demo client focused on {goal.lower()} with {activity_level.lower()} baseline activity.',
          'must_change_password': False,
          'is_active': True,
        },
      )
      issue_client_token(client)
      clients.append(client)
    return clients

  def seed_references(self, professional):
    category_lookup = {}
    for name, subcategories in REFERENCE_CATEGORIES:
      category, _created = ReferenceCategory.objects.update_or_create(
        professional=professional,
        name=name,
        defaults={'subcategories': subcategories},
      )
      category_lookup[name] = category

    references = []
    for category_name, subcategory, title, reference_type, description, link, tags in REFERENCES:
      reference, _created = ProfessionalReference.objects.update_or_create(
        professional=professional,
        title=title,
        defaults={
          'category': category_lookup[category_name],
          'subcategory': subcategory,
          'reference_type': reference_type,
          'description': description,
          'link': link,
          'tags': tags,
        },
      )
      references.append(reference)
    return references

  def seed_templates(self, professional):
    templates = []
    for template_data in TEMPLATES:
      template, _created = TrackingTemplate.objects.update_or_create(
        professional=professional,
        name=template_data['name'],
        defaults={
          'purpose': template_data['purpose'],
          'cadence': template_data['cadence'],
          'accent': template_data['accent'],
          'fields': template_data['fields'],
          'standard_key': '',
          'is_active': True,
        },
      )
      templates.append(template)
    return templates

  def seed_assignments(self, clients, templates, references):
    nutrition_refs = [ref for ref in references if ref.category.name == 'Nutrition Habits'][:5]
    strength_refs = [ref for ref in references if ref.category.name in ('Strength Technique', 'Warm-Up and Mobility')][:6]
    recovery_refs = [ref for ref in references if ref.category.name == 'Recovery and Mindset'][:4]
    refs_by_template = {
      'Daily Nutrition Check-In': nutrition_refs,
      'Workout Performance Log': strength_refs,
      'Recovery and Readiness': recovery_refs,
    }

    for client in clients:
      for template in templates:
        assignment, _created = TemplateAssignment.objects.get_or_create(client=client, template=template)
        assignment.references.set(refs_by_template.get(template.name, []))

  def seed_tracking_entries(self, client, templates):
    end_date = date.today()
    start_date = end_date - timedelta(days=89)
    TrackingEntry.objects.filter(
      client=client,
      template__in=templates,
      entry_date__gte=start_date,
      entry_date__lte=end_date,
    ).delete()

    entries = []
    for day_index in range(90):
      entry_date = start_date + timedelta(days=day_index)
      for template_index, template in enumerate(templates):
        entries.append(
          TrackingEntry(
            client=client,
            template=template,
            template_name=template.name,
            entry_date=entry_date,
            entry_time=time(hour=8 + template_index),
            answers=entry_payload(template.name, day_index),
            note='Demo 90-day input generated for professional/client review.',
            edited_by_professional=False,
          )
        )

    TrackingEntry.objects.bulk_create(entries)

  def seed_chat(self, professional, client):
    if ChatMessage.objects.filter(professional=professional, client=client).exists():
      return

    ChatMessage.objects.create(
      professional=professional,
      client=client,
      sender=ChatMessage.SENDER_PROFESSIONAL,
      text='Welcome, Alex. Your 90-day check-ins, workout log, and reference links are ready.',
      is_read=True,
    )
    ChatMessage.objects.create(
      professional=professional,
      client=client,
      sender=ChatMessage.SENDER_CLIENT,
      text='Thanks Coach Maya. I will start with the nutrition and recovery check-ins today.',
      is_read=False,
    )
