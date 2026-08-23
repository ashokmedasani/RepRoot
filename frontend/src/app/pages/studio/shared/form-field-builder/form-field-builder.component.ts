import { Component, ElementRef, Input, ViewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Country, State } from 'country-state-city';

import { DynamicField, DynamicFieldType } from '@core/api/forms-groups-api.service';

interface FieldTypeOption {
  value: DynamicFieldType;
  label: string;
}

export interface ExternalSuggestionGroup {
  /** e.g. "Lead Form 1 Fields" -- only groups with at least one field should be passed in. */
  title: string;
  fields: DynamicField[];
}

interface FitnessFieldTemplate {
  icon: string;
  label: string;
  category: string;
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
  @Input() formPurpose: 'lead' | 'group' = 'lead';
  @Input() allowRequiredSelection = true;
  /** Additional labeled suggestion sections, e.g. one per existing lead form,
   *  shown below the standard suggestions -- never auto-inserted, same
   *  click-to-add pattern as the built-in recommended fields. Only sections
   *  with at least one field should be included by the caller. */
  @Input() externalSuggestionGroups: ExternalSuggestionGroup[] = [];

  @ViewChild('customBuilder') private readonly customBuilder?: ElementRef<HTMLElement>;

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
      category: 'Contact',
      field_type: 'phone',
      placeholder: 'Mobile number',
      help_text: 'Country code selector plus mobile number input.',
      // Matches UNIVERSAL_CLIENT_FORM_FIELDS on the backend and the manual
      // Add Client form, which both always require a phone number — this
      // suggested-fields chip must stay in sync or a professional adding
      // "Phone Number" from here ends up with a field that's silently
      // optional here but rejected as required everywhere else.
      required: false
    },
    {
      icon: 'GO',
      label: 'Primary Goal',
      category: 'Fitness Profile',
      field_type: 'dropdown',
      placeholder: 'Select primary goal',
      help_text: 'Capture the client goal before assigning a program.',
      options: ['Weight Loss', 'Muscle Gain', 'Strength', 'General Fitness', 'Mobility', 'Sports Performance'],
      required: false
    },
    {
      icon: 'EX',
      label: 'Training Experience',
      category: 'Fitness Profile',
      field_type: 'dropdown',
      placeholder: 'Select experience level',
      help_text: 'Beginner, intermediate, or advanced training history.',
      options: ['Beginner', 'Intermediate', 'Advanced']
    },
    {
      icon: 'MC',
      label: 'Medical Conditions or Injuries',
      category: 'Health',
      field_type: 'long_text',
      placeholder: 'List medical conditions or past injuries',
      help_text: 'Important health context before training begins.'
    },
    {
      icon: 'TM',
      label: 'Preferred Training Mode',
      category: 'Preferences',
      field_type: 'dropdown',
      placeholder: 'Select mode',
      help_text: 'Online, in person, or hybrid coaching preference.',
      options: ['Online', 'In Person', 'Hybrid']
    }
  ];

  get visibleRecommended(): FitnessFieldTemplate[] {
    return this.recommendedFields;
  }

  addField(): void {
    this.customFields.push({ ...this.createEmptyField(), isEditing: true });
  }

  /** The "+" chip that sits after the suggestions.
   *
   *  Someone who scanned the suggestions and did not find what they wanted is
   *  exactly the person who needs a custom field, so the option belongs here
   *  rather than only in the builder heading further down. The new card
   *  renders below the fold on most screens, so scroll to it — otherwise the
   *  chip reads as broken. */
  addFieldFromSuggestions(): void {
    this.addField();
    setTimeout(() => {
      const host = this.customBuilder?.nativeElement;
      if (!host) {
        return;
      }
      const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      host.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'start' });
      const cards = host.querySelectorAll<HTMLElement>('.field-card');
      cards[cards.length - 1]?.querySelector('input')?.focus({ preventScroll: true });
    });
  }

  isRecommendedFieldAdded(template: FitnessFieldTemplate): boolean {
    return this.isFieldLabelAdded(template.label);
  }

  addRecommendedField(template: FitnessFieldTemplate): void {
    // Suggested fields are opt-in. If one was already added, do not insert a
    // duplicate when its suggestion is selected again.
    if (this.isRecommendedFieldAdded(template)) {
      return;
    }
    // Insert the suggested field and open its settings panel immediately.
    this.customFields.push(this.createFieldFromTemplate(template, true));
  }

  isFieldLabelAdded(label: string): boolean {
    const normalized = label.trim().toLowerCase();
    return this.customFields.some((field) => (field.label || '').trim().toLowerCase() === normalized);
  }

  addExternalSuggestedField(field: DynamicField): void {
    if (this.isFieldLabelAdded(field.label)) {
      return;
    }

    this.customFields.push({
      ...field,
      options: [...(field.options || [])],
      required: this.allowRequiredSelection ? Boolean(field.required) : false,
      is_core: false,
      isEditing: true
    });
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
      required: this.allowRequiredSelection ? Boolean(template.required) : false,
      placeholder: template.placeholder,
      help_text: template.help_text,
      options: [...(template.options || [])],
      isEditing
    };
  }
}
