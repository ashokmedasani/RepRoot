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
  ClientReminder,
  LeadSubmission,
  ProgressEntry,
  ReferenceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  TrainerGroup,
  TrainerLeadForm,
  TrainerProfile,
  TrainerReference,
  default_client_registration_fields,
)


User = get_user_model()

TRAINER_USERNAME = 'nolan_performance'
TRAINER_EMAIL = 'nolan.performance@example.com'
TRAINER_PASSWORD = 'TrainerScale!2026'
CLIENT_PASSWORD = 'ClientScale!2026'
FEATURED_CLIENT_USERNAME = 'ava_martinez'


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


REFERENCE_CATEGORIES = [
  ('Movement Library', 'Exercise demos, regressions, and form checkpoints.', ['Squat', 'Hinge', 'Push', 'Pull', 'Core']),
  ('Conditioning', 'Cardio, intervals, zone work, and conditioning plans.', ['Intervals', 'Zone 2', 'Warm-up']),
  ('Nutrition Coaching', 'Food quality, portions, protein, hydration, and planning.', ['Protein', 'Meal Prep', 'Hydration']),
  ('Recovery', 'Sleep, stress, soreness, and readiness routines.', ['Sleep', 'Stress', 'Mobility']),
  ('Mindset and Planning', 'Weekly planning, habit tracking, and reflection prompts.', ['Habits', 'Weekly Review']),
]


REFERENCES = [
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
]


def build_client_data(index):
  first = FIRST_NAMES[index]
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
    'phone': f'555-02{index + 1:02d}',
  }


def registration_answers(client_data):
  return {
    'first_name': client_data['first_name'],
    'last_name': client_data['last_name'],
    'email': client_data['email'],
    'phone_number': client_data['phone'],
    'primary_goal': client_data['goal'],
    'training_experience': client_data['experience'],
    'medical_conditions': 'None reported in demo intake.' if client_data['username'] != FEATURED_CLIENT_USERNAME else 'Past right knee irritation during running; no current pain. Prefers low-impact conditioning.',
    'preferred_training_mode': client_data['mode'],
    'height': '5 ft 6 in' if client_data['username'] == FEATURED_CLIENT_USERNAME else 'Demo height on file',
    'current_weight': '168 lb' if client_data['username'] == FEATURED_CLIENT_USERNAME else 'Demo weight on file',
    'target_weight': '150 lb' if client_data['username'] == FEATURED_CLIENT_USERNAME else '',
    'sleep_average': '6.5 hours' if client_data['username'] == FEATURED_CLIENT_USERNAME else '',
    'nutrition_preference': 'High-protein Mediterranean style, no shellfish' if client_data['username'] == FEATURED_CLIENT_USERNAME else '',
  }


def featured_additional_info():
  return [
    {'label': 'Emergency Contact', 'value': 'Mia Martinez, sister, 555-2010'},
    {'label': 'Preferred Training Days', 'value': 'Monday, Wednesday, Friday, Saturday'},
    {'label': 'Equipment Access', 'value': 'Apartment gym, dumbbells to 40 lb, cable stack, treadmill, yoga mat'},
    {'label': 'Work Schedule', 'value': 'Hybrid office, busiest Tuesday and Thursday afternoons'},
    {'label': 'Nutrition Target', 'value': '135 g protein, 2.7 L water, 25 g fiber most days'},
    {'label': 'Primary Barrier', 'value': 'Late meetings lead to skipped dinners and low evening energy'},
    {'label': 'Coach Focus', 'value': 'Build lower-body strength without knee flare-ups and improve weekend meal planning'},
    {'label': 'Measurements', 'value': 'Waist 34 in, hips 41 in, resting HR 68 bpm'},
    {'label': 'Communication Preference', 'value': 'Text-style check-in after workouts, deeper review on Fridays'},
    {'label': 'Motivation', 'value': 'Feel strong for hiking trip in October and build a sustainable routine'},
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

  return {
    'weekly_win': 'Completed key sessions and kept nutrition notes current.',
    'barrier': 'Evening schedule was the main friction point.',
    'next_focus': 'Prep two dinners ahead and keep walks after lunch.',
  }


class Command(BaseCommand):
  help = 'Seed a second trainer account with 50 clients, schedules, references, and detailed client data.'

  def handle(self, *args, **options):
    with transaction.atomic():
      trainer = self.seed_trainer()
      groups = self.seed_groups(trainer)
      lead_form = self.seed_lead_form(trainer)
      clients = self.seed_clients(trainer, groups, lead_form)
      references = self.seed_references(trainer)
      templates = self.seed_templates(trainer)
      self.seed_assignments(clients, templates, references)
      self.seed_featured_tracking(clients[0], templates)
      self.seed_reminders(trainer, clients)
      self.seed_progress(trainer, clients[0])
      self.seed_chat(trainer, clients[0])

    trainer_token, _created = Token.objects.get_or_create(user=trainer)
    client_token = issue_client_token(clients[0])

    self.stdout.write(self.style.SUCCESS('Scale demo fitness data seeded successfully.'))
    self.stdout.write(f'Trainer login: {TRAINER_USERNAME} / {TRAINER_PASSWORD}')
    self.stdout.write(f'Trainer email: {TRAINER_EMAIL}')
    self.stdout.write(f'Trainer token: {trainer_token.key}')
    self.stdout.write(f'Featured client login: trainer_id=coach-nolan, username={clients[0].username}, password={CLIENT_PASSWORD}')
    self.stdout.write(f'Featured client token: {client_token.key}')
    featured_entry_count = TrackingEntry.objects.filter(client=clients[0], template__in=templates).count()
    self.stdout.write(f'Created/updated: 1 trainer, {len(groups)} groups, {len(clients)} clients, {len(references)} references, {len(templates)} templates, 100 reminders, {featured_entry_count} tracking entries for {clients[0].first_name}.')

  def seed_trainer(self):
    trainer, _created = User.objects.get_or_create(
      username=TRAINER_USERNAME,
      defaults={'email': TRAINER_EMAIL, 'first_name': 'Nolan', 'last_name': 'Brooks'},
    )
    trainer.email = TRAINER_EMAIL
    trainer.first_name = 'Nolan'
    trainer.last_name = 'Brooks'
    trainer.set_password(TRAINER_PASSWORD)
    trainer.save()

    profile, _created = TrainerProfile.objects.get_or_create(user=trainer)
    profile.trainer_id = 'coach-nolan'
    profile.profile_setup_completed = True
    profile.phone = '555-0199'
    profile.gender = 'Male'
    profile.state = 'California'
    profile.country = 'United States'
    profile.birth_month = 9
    profile.birth_year = 1985
    profile.professional_headline = 'Performance, habits, and lifestyle transformation coach'
    profile.about_me = 'Nolan coaches busy adults and recreational athletes with practical strength plans, clear nutrition targets, and high-accountability follow-up.'
    profile.trainer_type = 'Performance Coach'
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
      'phone': True,
      'social_links': True,
      'certifications': True,
      'gallery': True,
      'about': True,
    }
    profile.terms_accepted = True
    profile.privacy_policy_accepted = True
    profile.save()
    return trainer

  def seed_groups(self, trainer):
    groups = {}
    for name, description in GROUPS:
      group, _created = TrainerGroup.objects.update_or_create(
        trainer=trainer,
        name=name,
        defaults={'description': description, 'is_active': True},
      )
      ClientRegistrationForm.objects.update_or_create(
        group=group,
        defaults={'fields': default_client_registration_fields(), 'is_active': True},
      )
      groups[name] = group
    return groups

  def seed_lead_form(self, trainer):
    lead_form, _created = TrainerLeadForm.objects.update_or_create(
      trainer=trainer,
      defaults={
        'public_slug': 'coach-nolan-scale-demo',
        'title': 'Coach Nolan Intake Form',
        'fields': default_client_registration_fields(),
        'is_active': True,
      },
    )
    return lead_form

  def seed_clients(self, trainer, groups, lead_form):
    clients = []
    for index in range(50):
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
      additional_info = featured_additional_info() if index == 0 else [
        {'label': 'Goal Priority', 'value': client_data['goal']},
        {'label': 'Preferred Mode', 'value': client_data['mode']},
        {'label': 'Experience', 'value': client_data['experience']},
      ]
      client, _created = ClientAccess.objects.update_or_create(
        trainer=trainer,
        email=client_data['email'],
        defaults={
          'group': groups[client_data['group_name']],
          'lead_submission': lead,
          'first_name': client_data['first_name'],
          'last_name': client_data['last_name'],
          'username': client_data['username'],
          'temporary_password': make_password(CLIENT_PASSWORD),
          'registration_answers': answers,
          'additional_info': additional_info,
          'additional_info_shared': index == 0,
          'trainer_notes': self.featured_notes() if index == 0 else f'{client_data["goal"]} client. Keep reminders active and review weekly adherence.',
          'trainer_notes_updated_at': timezone.now(),
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

  def seed_references(self, trainer):
    categories = {}
    for name, description, subcategories in REFERENCE_CATEGORIES:
      category, _created = ReferenceCategory.objects.update_or_create(
        trainer=trainer,
        name=name,
        defaults={'description': description, 'subcategories': subcategories},
      )
      categories[name] = category

    references = []
    for category_name, subcategory, title, reference_type, description, link, tags in REFERENCES:
      reference, _created = TrainerReference.objects.update_or_create(
        trainer=trainer,
        title=title,
        defaults={
          'category': categories[category_name],
          'subcategory': subcategory,
          'reference_type': reference_type,
          'description': description,
          'link': link,
          'tags': tags,
        },
      )
      references.append(reference)
    return references

  def seed_templates(self, trainer):
    templates = []
    for data in TEMPLATES:
      template, _created = TrackingTemplate.objects.update_or_create(
        trainer=trainer,
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

  def seed_assignments(self, clients, templates, references):
    for client in clients:
      for template in templates:
        assignment, _created = TemplateAssignment.objects.get_or_create(client=client, template=template)
        assignment.references.set(references[:8] if template.name != 'Nutrition Reflection' else references[8:14])

  def seed_featured_tracking(self, client, templates):
    end_date = date.today()
    start_date = end_date - timedelta(days=89)
    TrackingEntry.objects.filter(client=client, template__in=templates, entry_date__gte=start_date, entry_date__lte=end_date).delete()

    entries = []
    for day_index in range(90):
      entry_date = start_date + timedelta(days=day_index)
      for template_index, template in enumerate(templates):
        if template.cadence == 'weekly' and day_index % 7 != 0:
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
            edited_by_trainer=False,
          )
        )
    TrackingEntry.objects.bulk_create(entries)

  def seed_reminders(self, trainer, clients):
    ClientReminder.objects.filter(trainer=trainer).delete()
    today = date.today()
    titles = ['Progress review', 'Workout form check', 'Nutrition follow-up', 'Payment/check-in note', 'Recovery audit']
    reminders = []
    for index, client in enumerate(clients):
      for offset in (index % 14, 14 + index % 21):
        reminders.append(
          ClientReminder(
            trainer=trainer,
            client=client,
            title=titles[index % len(titles)],
            date=today + timedelta(days=offset),
            time=time(hour=9 + index % 8, minute=30 if index % 2 else 0),
            notes=f'Scheduled demo follow-up for {client.first_name}: review adherence, notes, and next action.',
            status=ClientReminder.STATUS_PENDING,
            notify_trainer=True,
          )
        )
    ClientReminder.objects.bulk_create(reminders)

  def seed_progress(self, trainer, client):
    ProgressEntry.objects.filter(trainer=trainer, client=client).delete()
    today = date.today()
    entries = [
      ('Initial Assessment', today - timedelta(days=84), 'Baseline intake completed. Knee note captured. Training starts with controlled lower-body volume.', 'Baseline', 'Start daily habit scorecard and three strength days.'),
      ('First Month Review', today - timedelta(days=56), 'Strong check-in consistency. Energy improving. Need better dinner planning on office days.', 'Improving', 'Prep two dinners before Tuesday.'),
      ('Midpoint Review', today - timedelta(days=28), 'Strength sessions consistent. Weight trending down steadily. Knee remains calm with low-impact conditioning.', 'On Track', 'Add one upper-body progression and keep zone-2 walks.'),
      ('Current Week Focus', today, 'Ava is ready for the next phase with slightly higher lower-body load and a tighter Friday review.', 'Active', 'Increase goblet squat load only if knee feedback stays green.'),
    ]
    ProgressEntry.objects.bulk_create(
      [
        ProgressEntry(
          trainer=trainer,
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

  def seed_chat(self, trainer, client):
    ChatMessage.objects.filter(trainer=trainer, client=client).delete()
    messages = [
      (ChatMessage.SENDER_TRAINER, 'Ava, your full 90-day dashboard is loaded. Start with today\'s scorecard and Friday review.'),
      (ChatMessage.SENDER_CLIENT, 'Got it. I checked the meal prep notes and will log after my lower-body session.'),
      (ChatMessage.SENDER_TRAINER, 'Perfect. Keep knee feedback honest and choose bike intervals instead of running if anything feels sharp.'),
    ]
    ChatMessage.objects.bulk_create(
      [
        ChatMessage(
          trainer=trainer,
          client=client,
          sender=sender,
          text=text,
          is_read=sender == ChatMessage.SENDER_TRAINER,
        )
        for sender, text in messages
      ]
    )
