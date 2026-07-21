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
    { value: 'address', label: 'Address' }
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
      icon: 'EX',
      label: 'Training Experience',
      field_type: 'dropdown',
      placeholder: 'Select experience level',
      help_text: 'Beginner, intermediate, or advanced training history.',
      options: ['Beginner', 'Intermediate', 'Advanced']
    },
    {
      icon: 'MC',
      label: 'Medical Conditions or Injuries',
      field_type: 'long_text',
      placeholder: 'List medical conditions or past injuries',
      help_text: 'Important health context before training begins.'
    },
    {
      icon: 'TM',
      label: 'Preferred Training Mode',
      field_type: 'dropdown',
      placeholder: 'Select mode',
      help_text: 'Online, in person, or hybrid coaching preference.',
      options: ['Online', 'In Person', 'Hybrid']
    }
  ];

  showAllChips = false;

  private readonly primaryChips = [
    'Phone Number',
    'Primary Goal',
    'Training Experience',
    'Medical Conditions or Injuries',
    'Preferred Training Mode'
  ];

  get visibleRecommended(): FitnessFieldTemplate[] {
    const primary = this.primaryChips
      .map((label) => this.recommendedFields.find((field) => field.label === label))
      .filter((field): field is FitnessFieldTemplate => Boolean(field));

    if (!this.showAllChips) {
      return primary;
    }

    const rest = this.recommendedFields.filter((field) => !this.primaryChips.includes(field.label));
    return [...primary, ...rest];
  }

  toggleAllChips(): void {
    this.showAllChips = !this.showAllChips;
  }

  addField(): void {
    this.customFields.push({ ...this.createEmptyField(), isEditing: true });
  }

  addRecommendedField(template: FitnessFieldTemplate): void {
    // Insert the suggested field and open its settings panel immediately.
    this.customFields.push(this.createFieldFromTemplate(template, true));
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

  private createFieldFromTemplate(template: FitnessFieldTemplate, isEditing = false): DynamicField {
    return {
      label: template.label,
      field_type: template.field_type,
      required: Boolean(template.required),
      placeholder: template.placeholder,
      help_text: template.help_text,
      options: [...(template.options || [])],
      isEditing
    };
  }
}
