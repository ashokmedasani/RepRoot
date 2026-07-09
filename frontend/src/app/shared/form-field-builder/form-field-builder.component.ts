import { Component, Input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Country, State } from 'country-state-city';

import { DynamicField, DynamicFieldType } from '../../core/api/forms-groups-api.service';

interface FieldTypeOption {
  value: DynamicFieldType;
  label: string;
}

interface FitnessFieldTemplate {
  icon: string;
  label: string;
  field_type: DynamicFieldType;
  placeholder: string;
  help_text: string;
  options?: string[];
  required?: boolean;
}

@Component({
  selector: 'app-form-field-builder',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './form-field-builder.component.html',
  styleUrl: './form-field-builder.component.scss'
})
export class FormFieldBuilderComponent {
  @Input({ required: true }) customFields: DynamicField[] = [];

  readonly fieldTypes: FieldTypeOption[] = [
    { value: 'short_text', label: 'Short Text' },
    { value: 'long_text', label: 'Long Text' },
    { value: 'email', label: 'Email' },
    { value: 'phone', label: 'Phone' },
    { value: 'number', label: 'Number' },
    { value: 'dropdown', label: 'Dropdown' },
    { value: 'checkbox', label: 'Checkbox' },
    { value: 'radio', label: 'Radio' },
    { value: 'yes_no', label: 'Yes / No' },
    { value: 'date', label: 'Date' },
    { value: 'location', label: 'Location' },
    { value: 'address', label: 'Address' },
    { value: 'image', label: 'Image Upload' }
  ];
  readonly countries = Country.getAllCountries();
  readonly recommendedFields: FitnessFieldTemplate[] = [
    {
      icon: 'PH',
      label: 'Phone Number',
      field_type: 'phone',
      placeholder: 'Mobile number',
      help_text: 'Country code selector plus mobile number input.'
    },
    {
      icon: 'GO',
      label: 'Primary Goal',
      field_type: 'dropdown',
      placeholder: 'Select primary goal',
      help_text: 'Capture the client goal before assigning a program.',
      options: ['Weight Loss', 'Muscle Gain', 'Strength', 'General Fitness', 'Mobility', 'Sports Performance'],
      required: true
    },
    {
      icon: 'LO',
      label: 'Location',
      field_type: 'location',
      placeholder: 'Country and state',
      help_text: 'Country selector with state or region selector.'
    },
    {
      icon: 'SD',
      label: 'Preferred Start Date',
      field_type: 'date',
      placeholder: 'Choose start date',
      help_text: 'Calendar picker for when the client wants to begin.'
    },
    {
      icon: 'WT',
      label: 'Preferred Workout Time',
      field_type: 'dropdown',
      placeholder: 'Select workout time',
      help_text: 'Morning, afternoon, evening, or night preference.',
      options: ['Morning', 'Afternoon', 'Evening', 'Night']
    },
    {
      icon: 'EX',
      label: 'Training Experience',
      field_type: 'dropdown',
      placeholder: 'Select experience level',
      help_text: 'Beginner, intermediate, or advanced training history.',
      options: ['Beginner', 'Intermediate', 'Advanced']
    },
    {
      icon: 'KG',
      label: 'Current Weight',
      field_type: 'number',
      placeholder: 'Enter weight',
      help_text: 'Number field with kg/lbs unit selector.'
    },
    {
      icon: 'HT',
      label: 'Height',
      field_type: 'number',
      placeholder: 'Enter height',
      help_text: 'Number field with unit selector.'
    },
    {
      icon: 'AG',
      label: 'Age',
      field_type: 'number',
      placeholder: 'Enter age',
      help_text: 'Simple numeric age field.'
    },
    {
      icon: 'GE',
      label: 'Gender',
      field_type: 'dropdown',
      placeholder: 'Select gender',
      help_text: 'Dropdown for client profile context.',
      options: ['Female', 'Male', 'Non-binary', 'Prefer not to say']
    },
    {
      icon: 'DI',
      label: 'Dietary Preference',
      field_type: 'dropdown',
      placeholder: 'Select dietary preference',
      help_text: 'Useful for nutrition coaching and meal guidance.',
      options: ['Vegetarian', 'Vegan', 'Non-vegetarian', 'Pescatarian', 'Keto', 'No preference']
    },
    {
      icon: 'IN',
      label: 'Previous Injuries',
      field_type: 'long_text',
      placeholder: 'Describe previous injuries',
      help_text: 'Multi-line field for injury history.'
    },
    {
      icon: 'MC',
      label: 'Medical Conditions',
      field_type: 'long_text',
      placeholder: 'List medical conditions',
      help_text: 'Multi-line field for important health context.'
    },
    {
      icon: 'IM',
      label: 'Optional Image Folder',
      field_type: 'image',
      placeholder: 'Upload progress, posture, or reference photos',
      help_text: 'Optional image upload folder for client profile photos and visual context.'
    },
    {
      icon: 'NO',
      label: 'Additional Notes',
      field_type: 'long_text',
      placeholder: 'Anything else the trainer should know?',
      help_text: 'Large text field for extra client notes.'
    }
  ];

  addField(): void {
    this.customFields.push({ ...this.createEmptyField(), isEditing: true });
  }

  addRecommendedField(template: FitnessFieldTemplate): void {
    this.customFields.push(this.createFieldFromTemplate(template));
  }

  removeField(index: number): void {
    this.customFields.splice(index, 1);
  }

  duplicateField(index: number): void {
    const field = this.customFields[index];
    this.customFields.splice(index + 1, 0, {
      ...field,
      label: `${field.label} Copy`,
      options: [...(field.options || [])],
      isEditing: true
    });
  }

  moveField(index: number, direction: -1 | 1): void {
    const nextIndex = index + direction;

    if (nextIndex < 0 || nextIndex >= this.customFields.length) {
      return;
    }

    const [field] = this.customFields.splice(index, 1);
    this.customFields.splice(nextIndex, 0, field);
  }

  optionsText(field: DynamicField): string {
    return (field.options || []).join(', ');
  }

  updateOptions(field: DynamicField, value: string): void {
    field.options = value
      .split(',')
      .map((option) => option.trim())
      .filter(Boolean);
  }

  needsOptions(field: DynamicField): boolean {
    return ['dropdown', 'checkbox', 'radio', 'yes_no'].includes(field.field_type);
  }

  fieldTypeLabel(value: DynamicFieldType): string {
    return this.fieldTypes.find((fieldType) => fieldType.value === value)?.label || value;
  }

  coreFields(): DynamicField[] {
    return [
      {
        key: 'first_name',
        label: 'First Name',
        field_type: 'short_text',
        required: true,
        placeholder: '',
        help_text: '',
        is_core: true
      },
      {
        key: 'last_name',
        label: 'Last Name',
        field_type: 'short_text',
        required: true,
        placeholder: '',
        help_text: '',
        is_core: true
      },
      {
        key: 'email',
        label: 'Email Address',
        field_type: 'email',
        required: true,
        placeholder: '',
        help_text: '',
        is_core: true
      }
    ];
  }

  statesFor(countryIsoCode: string): string[] {
    return State.getStatesOfCountry(countryIsoCode).map((state) => state.name);
  }

  shouldShowUnit(field: DynamicField): boolean {
    const label = field.label.toLowerCase();
    return field.field_type === 'number' && (label.includes('weight') || label.includes('height'));
  }

  unitOptions(field: DynamicField): string[] {
    return field.label.toLowerCase().includes('height') ? ['cm', 'ft'] : ['kg', 'lbs'];
  }

  private createEmptyField(): DynamicField {
    return {
      label: '',
      field_type: 'short_text',
      required: false,
      placeholder: '',
      help_text: '',
      options: []
    };
  }

  private createFieldFromTemplate(template: FitnessFieldTemplate): DynamicField {
    return {
      label: template.label,
      field_type: template.field_type,
      required: Boolean(template.required),
      placeholder: template.placeholder,
      help_text: template.help_text,
      options: [...(template.options || [])],
      isEditing: false
    };
  }
}
