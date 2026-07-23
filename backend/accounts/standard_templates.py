"""Standard tracking templates offered to every professional.

A professional can adopt any of these with one click instead of building a
template from scratch. Adopting creates a professional-owned copy (which counts
toward the 5-template limit) that the professional can rename or customize.
Template fields are never mandatory for clients.
"""

STANDARD_TEMPLATES = [
  {
    'key': 'nutrition_details',
    'name': 'Nutrition Details',
    'purpose': 'Track daily meals, water intake, and calories so the professional can review nutrition habits.',
    'cadence': 'daily',
    'accent': 'green',
    'fields': [
      {'key': 'meals', 'label': 'Meals eaten today', 'field_type': 'long_text', 'placeholder': 'Breakfast, lunch, dinner, snacks'},
      {'key': 'water_intake', 'label': 'Water intake (liters)', 'field_type': 'number', 'placeholder': '2.5'},
      {'key': 'calories', 'label': 'Approximate calories', 'field_type': 'number', 'placeholder': '2000'},
      {'key': 'nutrition_notes', 'label': 'Nutrition notes', 'field_type': 'long_text', 'placeholder': 'Cravings, skipped meals, anything unusual'},
    ],
  },
  {
    'key': 'vitamins_supplements',
    'name': 'Vitamins & Supplements',
    'purpose': 'Record which vitamins and supplements were taken, the dosage, and when.',
    'cadence': 'daily',
    'accent': 'blue',
    'fields': [
      {'key': 'supplements_taken', 'label': 'Vitamins / supplements taken', 'field_type': 'long_text', 'placeholder': 'Vitamin D, Omega-3, Protein'},
      {'key': 'dosage', 'label': 'Dosage', 'field_type': 'short_text', 'placeholder': '1000 IU, 2 capsules'},
      {'key': 'time_taken', 'label': 'Time taken', 'field_type': 'short_text', 'placeholder': 'Morning with breakfast'},
      {'key': 'supplement_notes', 'label': 'Notes', 'field_type': 'long_text', 'placeholder': 'Missed doses or side effects'},
    ],
  },
  {
    'key': 'daily_progress',
    'name': 'Daily Progress Check-in',
    'purpose': 'A quick daily check-in with weight, a progress photo, and how the client is feeling.',
    'cadence': 'daily',
    'accent': 'orange',
    'fields': [
      {'key': 'weight', 'label': 'Current weight (kg)', 'field_type': 'number', 'placeholder': '78.4'},
      {'key': 'energy_rating', 'label': 'Energy level', 'field_type': 'rating', 'scale': 5, 'placeholder': ''},
      {'key': 'energy_mood', 'label': 'Energy / mood today', 'field_type': 'short_text', 'placeholder': 'Energetic, tired, motivated'},
      {'key': 'progress_notes', 'label': 'How are you feeling?', 'field_type': 'long_text', 'placeholder': 'Anything your professional should know'},
    ],
  },
]


def get_standard_template(key: str):
  for template in STANDARD_TEMPLATES:
    if template['key'] == key:
      return template

  return None
