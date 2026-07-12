import { DynamicField } from '../api/forms-groups-api.service';

/**
 * Universal client creation form template.
 *
 * Mirrors UNIVERSAL_CLIENT_FORM_FIELDS on the backend. Every new group is
 * seeded with these personal-information fields so a client creation form
 * always exists. This copy is used to pre-populate the builder for legacy
 * groups that were created before the form was auto-seeded.
 *
 * The three core fields (First Name, Last Name, Email) are added separately
 * and are not part of this template.
 */
export const UNIVERSAL_CLIENT_FORM_FIELDS: DynamicField[] = [
  {
    key: 'phone_number',
    label: 'Phone Number',
    field_type: 'phone',
    required: true,
    placeholder: 'Mobile number',
    help_text: 'Best contact number for the client.',
    options: []
  },
  {
    key: 'primary_goal',
    label: 'Primary Goal',
    field_type: 'dropdown',
    required: true,
    placeholder: 'Select primary goal',
    help_text: 'Capture the client goal before assigning a program.',
    options: ['Weight Loss', 'Muscle Gain', 'Strength', 'General Fitness', 'Mobility', 'Sports Performance']
  },
  {
    key: 'training_experience',
    label: 'Training Experience',
    field_type: 'dropdown',
    required: false,
    placeholder: 'Select experience level',
    help_text: 'Beginner, intermediate, or advanced training history.',
    options: ['Beginner', 'Intermediate', 'Advanced']
  },
  {
    key: 'medical_conditions',
    label: 'Medical Conditions or Injuries',
    field_type: 'long_text',
    required: false,
    placeholder: 'List any medical conditions or past injuries',
    help_text: 'Important health context before training begins.',
    options: []
  },
  {
    key: 'preferred_training_mode',
    label: 'Preferred Training Mode',
    field_type: 'dropdown',
    required: false,
    placeholder: 'Select mode',
    help_text: 'Online, in person, or hybrid coaching preference.',
    options: ['Online', 'In Person', 'Hybrid']
  }
];

/** Returns a deep copy of the universal template so callers can edit freely. */
export function buildUniversalClientFormFields(): DynamicField[] {
  return UNIVERSAL_CLIENT_FORM_FIELDS.map((field) => ({
    ...field,
    options: [...(field.options || [])]
  }));
}
