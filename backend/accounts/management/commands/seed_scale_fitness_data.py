import calendar
from datetime import date, time, timedelta
from urllib.request import Request, urlopen

from django.contrib.auth import get_user_model
from django.contrib.auth.hashers import make_password
from django.core.cache import cache
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone
from rest_framework.authtoken.models import Token

from accounts.client_auth import issue_client_token
from accounts.models import (
  ChatMessage,
  ClientAccess,
  ClientRegistrationForm,
  ClientReminder,
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


User = get_user_model()

PROFESSIONAL_USERNAME = 'nolan_performance'
PROFESSIONAL_EMAIL = 'nolan.performance@example.com'
PROFESSIONAL_PASSWORD = 'ProfessionalScale!2026'
CLIENT_PASSWORD = 'ClientScale!2026'
FEATURED_CLIENT_USERNAME = 'ava_martinez'
CLIENT_COUNT = 100


GROUPS = [
  ('Performance Build', 'Strength, conditioning, and athletic performance clients.'),
  ('Lifestyle Reset', 'Busy professionals building consistent training, nutrition, and recovery habits.'),
  ('Mobility and Rehab Support', 'Clients focused on safer movement, mobility, and return-to-training routines.'),
  ('Nutrition Accountability', 'Clients who need meal, hydration, and habit follow-up.'),
]


FIRST_NAMES = [
  'Ava', 'Ben', 'Chloe', 'Darius', 'Elena', 'Felix', 'Grace', 'Hannah', 'Ivan', 'Jasmine',
  'Kai', 'Leah', 'Marcus', 'Natalie', 'Oscar', 'Paige', 'Quinn', 'Riley', 'Sofia', 'Theo',
  'Uma', 'Victor', 'Willow', 'Xavier', 'Yara', 'Zane', 'Amelia', 'Blake', 'Camila', 'Diego',
  'Emma', 'Finn', 'Gianna', 'Hudson', 'Iris', 'Jonah', 'Keira', 'Leo', 'Maya', 'Nolan',
  'Olivia', 'Parker', 'Reese', 'Sienna', 'Tyler', 'Valeria', 'Wyatt', 'Zara', 'Adrian', 'Bella',
]

LAST_NAMES = [
  'Martinez', 'Carter', 'Nguyen', 'Reed', 'Foster', 'Hayes', 'Collins', 'Price', 'Singh', 'Wallace',
  'Brooks', 'Ramirez', 'Cooper', 'Ward', 'Murphy', 'Bailey', 'Gray', 'Ross', 'Kelly', 'Bryant',
]

GOALS = ['Strength', 'Weight Loss', 'Muscle Gain', 'Mobility', 'General Fitness', 'Sports Performance']
EXPERIENCE = ['Beginner', 'Intermediate', 'Advanced']
MODES = ['Online', 'In Person', 'Hybrid']


RESOURCE_CATEGORIES = [
  ('Movement Library', 'Exercise demos, regressions, and form checkpoints.', ['Squat', 'Hinge', 'Push', 'Pull', 'Core']),
  ('Conditioning', 'Cardio, intervals, zone work, and conditioning plans.', ['Intervals', 'Zone 2', 'Warm-up']),
  ('Nutrition Coaching', 'Food quality, portions, protein, hydration, and planning.', ['Protein', 'Meal Prep', 'Hydration']),
  ('Recovery', 'Sleep, stress, soreness, and readiness routines.', ['Sleep', 'Stress', 'Mobility']),
  ('Mindset and Planning', 'Weekly planning, habit tracking, and reflection prompts.', ['Habits', 'Weekly Review']),
]


RESOURCES = [
  ('Movement Library', 'Squat', 'Bodyweight Squat Basics', 'video_link', 'Foot pressure, knee tracking, and depth for beginner squat practice.', 'https://www.youtube.com/watch?v=aclHkVaku9U', ['squat', 'form']),
  ('Movement Library', 'Hinge', 'Hip Hinge Pattern', 'video_link', 'Learn the hinge before deadlift and kettlebell variations.', 'https://www.youtube.com/watch?v=wYREQkVtvEc', ['hinge']),
  ('Movement Library', 'Push', 'Incline Push-Up Progression', 'video_link', 'Scalable push-up tutorial for different strength levels.', 'https://www.youtube.com/watch?v=IODxDxX7oi4', ['push']),
  ('Movement Library', 'Pull', 'Band Row Setup', 'text_note', 'Anchor band at chest height. Pull elbows back, pause for one count, keep ribs down.', '', ['pull', 'band']),
  ('Movement Library', 'Core', 'Core Brace Checklist', 'text_note', 'Exhale, stack ribs over pelvis, gently brace as if preparing for a cough, then move.', '', ['core']),
  ('Conditioning', 'Intervals', 'Low-Impact Interval Session', 'text_note', '10 rounds: 45 seconds brisk bike or walk, 75 seconds easy pace. Stop if form breaks.', '', ['conditioning']),
  ('Conditioning', 'Zone 2', 'Zone 2 Cardio Explained', 'video_link', 'Use conversational pace for aerobic base work.', 'https://www.youtube.com/watch?v=9L2b2khySLE', ['zone-2']),
  ('Conditioning', 'Warm-up', 'Dynamic Warm-Up Routine', 'video_link', 'Short full-body warm-up before strength or cardio sessions.', 'https://www.youtube.com/watch?v=R0mMyV5OtcM', ['warm-up']),
  ('Nutrition Coaching', 'Protein', 'Protein at Every Meal', 'text_note', 'Choose one anchor per meal: eggs, Greek yogurt, chicken, fish, tofu, beans, lentils, or lean meat.', '', ['protein']),
  ('Nutrition Coaching', 'Meal Prep', 'Three-Day Meal Prep Plan', 'text_note', 'Prep two proteins, one grain, chopped vegetables, and one simple sauce for mix-and-match meals.', '', ['meal-prep']),
  ('Nutrition Coaching', 'Hydration', 'Hydration Habit Builder', 'text_note', 'Drink water after waking, with training, with each meal, and before the evening wind-down.', '', ['hydration']),
  ('Nutrition Coaching', 'Meal Prep', 'Balanced Plate Visual Guide', 'video_link', 'Simple plate structure for everyday meals.', 'https://www.youtube.com/watch?v=Gmh_xMMJ2Pw', ['plate']),
  ('Recovery', 'Sleep', 'Sleep Hygiene Reset', 'text_note', 'Consistent sleep/wake time, dim lights 45 minutes before bed, caffeine cutoff by noon.', '', ['sleep']),
  ('Recovery', 'Stress', 'Box Breathing Drill', 'video_link', 'Use before check-ins, stressful work blocks, or evening recovery.', 'https://www.youtube.com/watch?v=tEmt1Znux58', ['breathing']),
  ('Recovery', 'Mobility', 'Evening Mobility Reset', 'text_note', 'Five minutes: child pose breathing, hip flexor stretch, hamstring floss, thoracic rotations.', '', ['mobility']),
  ('Mindset and Planning', 'Habits', 'Two-Minute Rule', 'text_note', 'When motivation is low, start with two minutes. Starting counts as keeping the identity alive.', '', ['habits']),
  ('Mindset and Planning', 'Weekly Review', 'Weekly Review Template', 'text_note', 'Wins, barriers, body feedback, sleep trend, food consistency, next week focus.', '', ['review']),
  ('Mindset and Planning', 'Habits', 'Consistency Over Perfection', 'video_link', 'A short habit mindset reference for avoiding all-or-nothing thinking.', 'https://www.youtube.com/watch?v=75d_29QWELk', ['mindset']),
]


TEMPLATES = [
  {
    'name': 'Daily Habit Scorecard',
    'purpose': 'Tracks the daily basics: workout, food quality, hydration, sleep, and stress.',
    'cadence': 'daily',
    'accent': 'green',
    'fields': [
      {'key': 'workout_completed', 'label': 'Workout completed?', 'field_type': 'yes_no', 'placeholder': '', 'options': [], 'scale': None},
      {'key': 'food_quality', 'label': 'Food quality', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
      {'key': 'water_liters', 'label': 'Water liters', 'field_type': 'number', 'placeholder': '2.5', 'options': [], 'scale': None},
      {'key': 'sleep_hours', 'label': 'Sleep hours', 'field_type': 'number', 'placeholder': '7.5', 'options': [], 'scale': None},
      {'key': 'stress_level', 'label': 'Stress level', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 5},
    ],
  },
  {
    'name': 'Strength Session Log',
    'purpose': 'Captures training focus, top set, effort, and form notes.',
    'cadence': 'daily',
    'accent': 'blue',
    'fields': [
      {'key': 'session_focus', 'label': 'Session focus', 'field_type': 'dropdown', 'placeholder': 'Choose focus', 'options': ['Lower Body', 'Upper Body', 'Full Body', 'Conditioning', 'Mobility'], 'scale': None},
      {'key': 'top_set', 'label': 'Top set or main work', 'field_type': 'short_text', 'placeholder': 'Goblet squat 35 lb x 10', 'options': [], 'scale': None},
      {'key': 'effort', 'label': 'Effort', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 10},
      {'key': 'form_notes', 'label': 'Form notes', 'field_type': 'long_text', 'placeholder': 'What felt good or needs work?', 'options': [], 'scale': None},
    ],
  },
  {
    'name': 'Nutrition Reflection',
    'purpose': 'Meal quality, protein, vegetables, cravings, and planning notes.',
    'cadence': 'daily',
    'accent': 'orange',
    'fields': [
      {'key': 'protein_servings', 'label': 'Protein servings', 'field_type': 'number', 'placeholder': '4', 'options': [], 'scale': None},
      {'key': 'vegetable_servings', 'label': 'Vegetable servings', 'field_type': 'number', 'placeholder': '3', 'options': [], 'scale': None},
      {'key': 'cravings', 'label': 'Cravings managed?', 'field_type': 'yes_no', 'placeholder': '', 'options': [], 'scale': None},
      {'key': 'meal_notes', 'label': 'Meal notes', 'field_type': 'long_text', 'placeholder': 'Wins, misses, hunger, planning', 'options': [], 'scale': None},
    ],
  },
  {
    'name': 'Weekly Progress Review',
    'purpose': 'A weekly reflection on progress, barriers, and next steps.',
    'cadence': 'weekly',
    'accent': 'purple',
    'fields': [
      {'key': 'weekly_win', 'label': 'Biggest win', 'field_type': 'long_text', 'placeholder': 'What went well?', 'options': [], 'scale': None},
      {'key': 'barrier', 'label': 'Main barrier', 'field_type': 'long_text', 'placeholder': 'What got in the way?', 'options': [], 'scale': None},
      {'key': 'next_focus', 'label': 'Next focus', 'field_type': 'short_text', 'placeholder': 'One priority for next week', 'options': [], 'scale': None},
    ],
  },
  {
    'name': 'Body Metrics Check-In',
    'purpose': 'Captures monthly body composition, recovery, and cardiovascular trends.',
    'cadence': 'monthly',
    'accent': 'purple',
    'fields': [
      {'key': 'weight_lb', 'label': 'Body weight (lb)', 'field_type': 'number', 'placeholder': '165.0', 'options': [], 'scale': None},
      {'key': 'waist_in', 'label': 'Waist (in)', 'field_type': 'number', 'placeholder': '33.5', 'options': [], 'scale': None},
      {'key': 'resting_hr', 'label': 'Resting heart rate', 'field_type': 'number', 'placeholder': '64', 'options': [], 'scale': None},
      {'key': 'energy', 'label': 'Average energy', 'field_type': 'rating', 'placeholder': '', 'options': [], 'scale': 10},
      {'key': 'progress_note', 'label': 'Monthly reflection', 'field_type': 'long_text', 'placeholder': 'What changed this month?', 'options': [], 'scale': None},
    ],
  },
]


def build_client_data(index):
  first = FIRST_NAMES[index % len(FIRST_NAMES)]
  last = LAST_NAMES[index % len(LAST_NAMES)]
  username = f'{first.lower()}_{last.lower()}_{index + 1:02d}'
  if index == 0:
    username = FEATURED_CLIENT_USERNAME

  goal = GOALS[index % len(GOALS)]
  age = 24 + (index % 28)
  experience = EXPERIENCE[index % len(EXPERIENCE)]
  mode = MODES[index % len(MODES)]

  return {
    'first_name': first,
    'last_name': last,
    'email': f'{username}@example.com',
    'username': username,
    'group_name': GROUPS[index % len(GROUPS)][0],
    'goal': goal,
    'age': age,
    'experience': experience,
    'mode': mode,
    'phone': f'555-2{index + 1:03d}',
  }


def registration_answers(client_data):
  weight = 138 + (client_data['age'] % 15) * 4
  target_delta = 12 if client_data['goal'] == 'Weight Loss' else -8 if client_data['goal'] == 'Muscle Gain' else 0
  return {
    'first_name': client_data['first_name'],
    'last_name': client_data['last_name'],
    'email': client_data['email'],
    'phone_number': client_data['phone'],
    'primary_goal': client_data['goal'],
    'training_experience': client_data['experience'],
    'medical_conditions': 'No current restrictions; cleared for progressive exercise.' if client_data['username'] != FEATURED_CLIENT_USERNAME else 'Past right knee irritation during running; no current pain. Prefers low-impact conditioning.',
    'preferred_training_mode': client_data['mode'],
    'age': client_data['age'],
    'height': '5 ft 6 in' if client_data['username'] == FEATURED_CLIENT_USERNAME else f'{5 + client_data["age"] % 2} ft {2 + client_data["age"] % 9} in',
    'current_weight': '168 lb' if client_data['username'] == FEATURED_CLIENT_USERNAME else f'{weight} lb',
    'target_weight': '150 lb' if client_data['username'] == FEATURED_CLIENT_USERNAME else f'{weight - target_delta} lb',
    'sleep_average': '6.5 hours' if client_data['username'] == FEATURED_CLIENT_USERNAME else f'{6.5 + (client_data["age"] % 4) * 0.5:.1f} hours',
    'nutrition_preference': 'High-protein Mediterranean style, no shellfish' if client_data['username'] == FEATURED_CLIENT_USERNAME else 'Balanced, high-protein meals with flexible weekend planning',
    'occupation_schedule': 'Hybrid office schedule with two evening commitments per week',
    'weekly_availability': 'Three training sessions plus two short recovery sessions',
    'consent_to_coaching': 'Yes',
  }


def featured_additional_info():
  values = [
    ('Emergency Contact', 'Mia Martinez, sister, 555-2010'),
    ('Preferred Training Days', 'Monday, Wednesday, Friday, Saturday'),
    ('Equipment Access', 'Apartment gym, dumbbells to 40 lb, cable stack, treadmill, yoga mat'),
    ('Work Schedule', 'Hybrid office, busiest Tuesday and Thursday afternoons'),
    ('Nutrition Target', '135 g protein, 2.7 L water, 25 g fiber most days'),
    ('Primary Barrier', 'Late meetings lead to skipped dinners and low evening energy'),
    ('Coach Focus', 'Build lower-body strength without knee flare-ups and improve weekend meal planning'),
    ('Measurements', 'Waist 34 in, hips 41 in, resting HR 68 bpm'),
    ('Communication Preference', 'Text-style check-in after workouts, deeper review on Fridays'),
    ('Motivation', 'Feel strong for hiking trip in October and build a sustainable routine'),
  ]
  return [
    {'id': f'seed-info-{index}', 'title': title, 'type': 'text', 'visibility': 'client', 'text': text}
    for index, (title, text) in enumerate(values, start=1)
  ]


def client_additional_info(client_data, index):
  values = [
    ('Goal Priority', f'{client_data["goal"]} with measurable monthly milestones'),
    ('Preferred Mode', client_data['mode']),
    ('Experience', client_data['experience']),
    ('Training Availability', 'Three structured sessions and two optional recovery sessions per week'),
    ('Equipment Access', ['Full commercial gym', 'Home dumbbells, bands, and mat', 'Apartment fitness center'][index % 3]),
    ('Nutrition Focus', ['Protein consistency', 'Meal timing', 'Portion awareness', 'Hydration and fiber'][index % 4]),
    ('Primary Barrier', ['Travel schedule', 'Evening fatigue', 'Inconsistent meal prep', 'Weekend routine'][index % 4]),
    ('Communication Preference', ['Monday planning check-in', 'Post-workout message', 'Friday progress summary'][index % 3]),
  ]
  return [
    {'id': f'seed-{index}-{item_index}', 'title': title, 'type': 'text', 'visibility': 'client', 'text': text}
    for item_index, (title, text) in enumerate(values, start=1)
  ]


def tracking_answers(template_name, day_index):
  if template_name == 'Daily Habit Scorecard':
    return {
      'workout_completed': 'Yes' if day_index % 6 != 4 else 'No',
      'food_quality': 3 + (day_index % 3),
      'water_liters': round(2.1 + (day_index % 6) * 0.12, 2),
      'sleep_hours': round(6.25 + (day_index % 7) * 0.2, 2),
      'stress_level': 2 + (day_index % 4),
    }

  if template_name == 'Strength Session Log':
    focuses = ['Lower Body', 'Upper Body', 'Full Body', 'Conditioning', 'Mobility']
    return {
      'session_focus': focuses[day_index % len(focuses)],
      'top_set': f'Demo top set week {day_index // 7 + 1}: controlled reps at RPE {6 + day_index % 4}',
      'effort': 6 + (day_index % 4),
      'form_notes': 'Kept tempo controlled, logged knee feedback, and adjusted load when needed.',
    }

  if template_name == 'Nutrition Reflection':
    return {
      'protein_servings': 3 + (day_index % 3),
      'vegetable_servings': 2 + (day_index % 4),
      'cravings': 'Yes' if day_index % 5 else 'No',
      'meal_notes': 'Packed lunch, hit protein target, and planned dinner before late meetings.',
    }

  if template_name == 'Body Metrics Check-In':
    month_index = day_index // 30
    return {
      'weight_lb': round(168 - month_index * 2.6, 1),
      'waist_in': round(34 - month_index * 0.35, 1),
      'resting_hr': max(60, 68 - month_index),
      'energy': min(9, 6 + month_index // 2),
      'progress_note': 'Strength and energy are improving. Clothing fit is better and the knee remains calm with low-impact conditioning.',
    }

  return {
    'weekly_win': 'Completed key sessions and kept nutrition notes current.',
    'barrier': 'Evening schedule was the main friction point.',
    'next_focus': 'Prep two dinners ahead and keep walks after lunch.',
  }


class Command(BaseCommand):
  help = 'Seed a full professional account with 100 clients and six months of detailed featured-client data.'

  def handle(self, *args, **options):
    with transaction.atomic():
      professional = self.seed_professional()
      groups = self.seed_groups(professional)
      lead_form = self.seed_lead_form(professional)
      clients = self.seed_clients(professional, groups, lead_form)
      resources = self.seed_resources(professional)
      templates = self.seed_templates(professional)
      self.seed_assignments(clients, templates, resources)
      self.seed_featured_tracking(clients[0], templates)
      self.seed_reminders(professional, clients)
      self.seed_progress(professional, clients[0])
      self.seed_chat(professional, clients[0])

    cache.delete(f'professional-data-usage:v3:{professional.pk}')

    professional_token, _created = Token.objects.get_or_create(user=professional)
    client_token = issue_client_token(clients[0])

    self.stdout.write(self.style.SUCCESS('Scale demo fitness data seeded successfully.'))
    self.stdout.write(f'Professional login: {PROFESSIONAL_USERNAME} / {PROFESSIONAL_PASSWORD}')
    self.stdout.write(f'Professional email: {PROFESSIONAL_EMAIL}')
    self.stdout.write(f'Professional token: {professional_token.key}')
    self.stdout.write(f'Featured client login: professional_id=coach-nolan, username={clients[0].username}, password={CLIENT_PASSWORD}')
    self.stdout.write(f'Featured client token: {client_token.key}')
    featured_entry_count = TrackingEntry.objects.filter(client=clients[0], template__in=templates).count()
    reminder_count = ClientReminder.objects.filter(professional=professional).count()
    self.stdout.write(f'Created/updated: 1 professional, {len(groups)} groups, {len(clients)} clients, {len(resources)} resources, {len(templates)} templates, {reminder_count} reminders, {featured_entry_count} six-month tracking entries for {clients[0].first_name}.')

  def seed_professional(self):
    professional, _created = User.objects.get_or_create(
      username=PROFESSIONAL_USERNAME,
      defaults={'email': PROFESSIONAL_EMAIL, 'first_name': 'Nolan', 'last_name': 'Brooks'},
    )
    professional.email = PROFESSIONAL_EMAIL
    professional.first_name = 'Nolan'
    professional.last_name = 'Brooks'
    professional.set_password(PROFESSIONAL_PASSWORD)
    professional.save()

    profile, _created = ProfessionalProfile.objects.get_or_create(user=professional)
    profile.professional_id = 'coach-nolan'
    profile.profile_setup_completed = True
    profile.phone = '555-0199'
    profile.gender = 'Male'
    profile.state = 'California'
    profile.country = 'United States'
    profile.birth_month = 9
    profile.birth_year = 1985
    profile.professional_headline = 'Performance, habits, and lifestyle transformation coach'
    profile.about_me = 'Nolan coaches busy adults and recreational athletes with practical strength plans, clear nutrition targets, and high-accountability follow-up.'
    profile.professional_type = 'Performance Coach'
    profile.years_experience = 12
    profile.specializations = 'Strength and conditioning, body recomposition, habit coaching, mobility, return-to-training support'
    profile.training_style = 'Direct, supportive, structured, and metrics-driven with flexible adjustments for real life.'
    profile.languages_known = 'English'
    profile.certification_name = 'Certified Strength and Conditioning Specialist'
    profile.certification_issued_by = 'NSCA'
    profile.certification_year = 2014
    profile.intro_video_url = 'https://www.youtube.com/watch?v=ml6cT4AZdqI'
    profile.instagram_url = 'https://www.instagram.com/coachnolan.demo'
    profile.youtube_url = 'https://www.youtube.com/@coachnolandemo'
    profile.website_url = 'https://coachnolan.example.com'
    profile.profile_links = [
      {'label': 'Consultation Booking', 'url': 'https://coachnolan.example.com/book'},
      {'label': 'Nutrition Guide', 'url': 'https://coachnolan.example.com/nutrition'},
    ]
    profile.profile_images = [
      {'title': 'Coaching Floor', 'url': 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48'},
      {'title': 'Strength Session', 'url': 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438'},
    ]
    profile.profile_visibility = {
      'professional_headline': True,
      'about': True,
      'professional_summary': True,
      'specializations': True,
      'experience': True,
      'languages': True,
      'training_style': True,
      'certification': True,
      'images': True,
      'links': True,
    }
    profile.terms_accepted = True
    profile.privacy_policy_accepted = True
    self.seed_profile_uploads(profile)
    profile.save()
    return professional

  def seed_profile_uploads(self, profile):
    uploads = [
      ('profile_photo', 'nolan-brooks-profile.jpg', 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=700&h=700&fit=crop'),
      ('transformation_photo', 'client-transformation.jpg', 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1000&h=700&fit=crop'),
      ('training_photo', 'coaching-floor.jpg', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1000&h=700&fit=crop'),
    ]
    for field_name, filename, url in uploads:
      file_field = getattr(profile, field_name)
      if file_field:
        continue
      try:
        request = Request(url, headers={'User-Agent': 'RepRoot demo data seeder'})
        with urlopen(request, timeout=20) as response:
          content = response.read(2 * 1024 * 1024 + 1)
        if len(content) > 2 * 1024 * 1024:
          raise ValueError('demo image exceeded the 2 MB seed limit')
        file_field.save(filename, ContentFile(content), save=False)
      except Exception as exc:
        self.stdout.write(self.style.WARNING(f'Could not load {field_name}: {exc}'))

  def seed_groups(self, professional):
    groups = {}
    for name, description in GROUPS:
      group, _created = ProfessionalGroup.objects.update_or_create(
        professional=professional,
        name=name,
        defaults={'description': description, 'is_active': True},
      )
      ClientRegistrationForm.objects.update_or_create(
        group=group,
        defaults={'fields': default_client_registration_fields(), 'is_active': True},
      )
      groups[name] = group
    return groups

  def seed_lead_form(self, professional):
    lead_form, _created = ProfessionalLeadForm.objects.update_or_create(
      professional=professional,
      defaults={
        'public_slug': 'coach-nolan-scale-demo',
        'title': 'Coach Nolan Intake Form',
        'fields': default_client_registration_fields(),
        'is_active': True,
      },
    )
    return lead_form

  def seed_clients(self, professional, groups, lead_form):
    clients = []
    for index in range(CLIENT_COUNT):
      client_data = build_client_data(index)
      answers = registration_answers(client_data)
      lead, _created = LeadSubmission.objects.update_or_create(
        reference_id=f'DEMO-NOLAN-{index + 1:03d}',
        defaults={
          'lead_form': lead_form,
          'first_name': client_data['first_name'],
          'last_name': client_data['last_name'],
          'email': client_data['email'],
          'answers': answers,
          'status': LeadSubmission.STATUS_APPROVED,
          'is_active': True,
          'converted_at': timezone.now(),
        },
      )
      additional_info = featured_additional_info() if index == 0 else client_additional_info(client_data, index)
      client, _created = ClientAccess.objects.update_or_create(
        professional=professional,
        email=client_data['email'],
        defaults={
          'group': groups[client_data['group_name']],
          'lead_submission': lead,
          'first_name': client_data['first_name'],
          'last_name': client_data['last_name'],
          'username': client_data['username'],
          'temporary_password': make_password(CLIENT_PASSWORD),
          'photo': f'https://i.pravatar.cc/300?img={(index % 70) + 1}',
          'registration_answers': answers,
          'additional_info': additional_info,
          'additional_info_shared': index == 0,
          'professional_notes': self.featured_notes() if index == 0 else f'{client_data["goal"]} client. Keep reminders active and review weekly adherence.',
          'professional_notes_updated_at': timezone.now(),
          'must_change_password': False,
          'is_active': True,
        },
      )
      issue_client_token(client)
      clients.append(client)
    return clients

  def featured_notes(self):
    return (
      'Ava is the fully detailed demo client. Primary objective: lose 18 lb while improving lower-body strength and energy. '
      'Plan: 3 strength sessions, 2 zone-2 walks, daily habit scorecard, weekly review every Friday. '
      'Watch right knee response on lunges and running. Strong compliance when meals are planned before work.'
    )

  def seed_resources(self, professional):
    categories = {}
    for name, description, subcategories in RESOURCE_CATEGORIES:
      category, _created = ResourceCategory.objects.update_or_create(
        professional=professional,
        name=name,
        defaults={'description': description, 'subcategories': subcategories},
      )
      categories[name] = category

    resources = []
    for category_name, subcategory, title, resource_type, description, link, tags in RESOURCES:
      resource, _created = ProfessionalResource.objects.update_or_create(
        professional=professional,
        title=title,
        defaults={
          'category': categories[category_name],
          'subcategory': subcategory,
          'resource_type': resource_type,
          'description': description,
          'link': link,
          'tags': tags,
        },
      )
      resources.append(resource)
    return resources

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

  def seed_assignments(self, clients, templates, resources):
    for client in clients:
      for template in templates:
        assignment, _created = TemplateAssignment.objects.get_or_create(client=client, template=template)
        assignment.resources.set(resources[:8] if template.name != 'Nutrition Reflection' else resources[8:14])

  def seed_featured_tracking(self, client, templates):
    end_date = date.today()
    start_month = end_date.month - 6
    start_year = end_date.year
    if start_month <= 0:
      start_month += 12
      start_year -= 1
    start_date = date(start_year, start_month, min(end_date.day, calendar.monthrange(start_year, start_month)[1]))
    TrackingEntry.objects.filter(client=client, template__in=templates, entry_date__gte=start_date, entry_date__lte=end_date).delete()

    entries = []
    day_count = (end_date - start_date).days + 1
    for day_index in range(day_count):
      entry_date = start_date + timedelta(days=day_index)
      for template_index, template in enumerate(templates):
        if template.cadence == 'weekly' and day_index % 7 != 0:
          continue
        if template.cadence == 'monthly' and entry_date.day != start_date.day:
          continue

        entries.append(
          TrackingEntry(
            client=client,
            template=template,
            template_name=template.name,
            entry_date=entry_date,
            entry_time=time(hour=7 + template_index),
            answers=tracking_answers(template.name, day_index),
            note='Detailed scale-demo history for the featured client.',
            edited_by_professional=False,
          )
        )
    TrackingEntry.objects.bulk_create(entries)

  def seed_reminders(self, professional, clients):
    ClientReminder.objects.filter(professional=professional).delete()
    today = date.today()
    titles = ['Progress review', 'Workout form check', 'Nutrition follow-up', 'Payment/check-in note', 'Recovery audit']
    reminders = []
    for index, client in enumerate(clients):
      for offset in (index % 14, 14 + index % 21):
        reminders.append(
          ClientReminder(
            professional=professional,
            client=client,
            title=titles[index % len(titles)],
            date=today + timedelta(days=offset),
            time=time(hour=9 + index % 8, minute=30 if index % 2 else 0),
            notes=f'Scheduled demo follow-up for {client.first_name}: review adherence, notes, and next action.',
            status=ClientReminder.STATUS_PENDING,
            notify_professional=True,
          )
        )
    ClientReminder.objects.bulk_create(reminders)

  def seed_progress(self, professional, client):
    ProgressEntry.objects.filter(professional=professional, client=client).delete()
    today = date.today()
    entries = [
      ('Initial Assessment', today - timedelta(days=180), 'Baseline intake completed. Knee note captured. Training starts with controlled lower-body volume.', 'Baseline', 'Start daily habit scorecard and three strength days.'),
      ('Month 1 Review', today - timedelta(days=150), 'Check-in rhythm established. Sleep and hydration are the first consistency targets.', 'Building', 'Keep the same training days and add a Sunday meal plan.'),
      ('Month 2 Review', today - timedelta(days=120), 'Lower-body technique is more stable and average steps are trending upward.', 'Improving', 'Progress goblet squat while keeping bike intervals low impact.'),
      ('Quarter Review', today - timedelta(days=90), 'Weight is trending down without a drop in strength. Office-day dinners remain the main barrier.', 'On Track', 'Prep two dinners before Tuesday and protect Friday review time.'),
      ('Month 4 Review', today - timedelta(days=60), 'Workout completion and protein consistency improved. Knee remains calm.', 'On Track', 'Add one upper-body progression and a longer weekend walk.'),
      ('Month 5 Review', today - timedelta(days=30), 'Energy and resting heart rate are improving. Nutrition is consistent through most weekends.', 'On Track', 'Practice one restaurant meal strategy before the hiking trip.'),
      ('Current Week Focus', today, 'Ava is ready for the next phase with slightly higher lower-body load and a tighter Friday review.', 'Active', 'Increase goblet squat load only if knee feedback stays green.'),
    ]
    ProgressEntry.objects.bulk_create(
      [
        ProgressEntry(
          professional=professional,
          client=client,
          title=title,
          date=entry_date,
          notes=notes,
          status=status,
          next_step=next_step,
          created_by='Coach Nolan',
        )
        for title, entry_date, notes, status, next_step in entries
      ]
    )

  def seed_chat(self, professional, client):
    ChatMessage.objects.filter(professional=professional, client=client).delete()
    messages = [
      (ChatMessage.SENDER_PROFESSIONAL, 'Ava, your full 90-day dashboard is loaded. Start with today\'s scorecard and Friday review.'),
      (ChatMessage.SENDER_CLIENT, 'Got it. I checked the meal prep notes and will log after my lower-body session.'),
      (ChatMessage.SENDER_PROFESSIONAL, 'Perfect. Keep knee feedback honest and choose bike intervals instead of running if anything feels sharp.'),
    ]
    ChatMessage.objects.bulk_create(
      [
        ChatMessage(
          professional=professional,
          client=client,
          sender=sender,
          text=text,
          is_read=sender == ChatMessage.SENDER_PROFESSIONAL,
        )
        for sender, text in messages
      ]
    )
