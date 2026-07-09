import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  TemplateCadence,
  TemplateField,
  TemplateFieldType,
  TemplatesApiService
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

interface BuilderField extends TemplateField {
  localId: string;
}

@Component({
  selector: 'app-trainer-tracking-template-create',
  standalone: true,
  imports: [FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-tracking-template-create.component.html',
  styleUrl: './trainer-tracking-template-create.component.scss'
})
export class TrainerTrackingTemplateCreateComponent implements OnInit {
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  templateId = 0;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  fieldErrors: Record<string, string> = {};

  templateInfo: { name: string; purpose: string; cadence: TemplateCadence; accent: string } = {
    name: '',
    purpose: '',
    cadence: 'daily',
    accent: 'green'
  };
  fields: BuilderField[] = [];

  readonly fieldTypes: { value: TemplateFieldType; label: string }[] = [
    { value: 'number', label: 'Number' },
    { value: 'short_text', label: 'Short Text' },
    { value: 'long_text', label: 'Long Text' },
    { value: 'yes_no', label: 'Yes / No' },
    { value: 'image', label: 'Image Upload' }
  ];

  readonly cadences: { value: TemplateCadence; label: string }[] = [
    { value: 'daily', label: 'Daily' },
    { value: 'weekly', label: 'Weekly' },
    { value: 'monthly', label: 'Monthly' }
  ];

  readonly accents = ['green', 'blue', 'orange', 'purple'];

  ngOnInit(): void {
    this.templateId = Number(this.route.snapshot.paramMap.get('templateId')) || 0;

    if (this.templateId) {
      this.loadTemplate();
    } else {
      this.fields = [this.createField('New Target')];
      this.isLoading = false;
    }
  }

  get isEditMode(): boolean {
    return this.templateId > 0;
  }

  addField(): void {
    this.fields = [...this.fields, this.createField('New Target')];
  }

  removeField(field: BuilderField): void {
    this.fields = this.fields.filter((currentField) => currentField.localId !== field.localId);
    delete this.fieldErrors[field.localId];
  }

  moveField(fieldIndex: number, direction: -1 | 1): void {
    const targetIndex = fieldIndex + direction;

    if (targetIndex < 0 || targetIndex >= this.fields.length) {
      return;
    }

    const reordered = [...this.fields];
    const [field] = reordered.splice(fieldIndex, 1);
    reordered.splice(targetIndex, 0, field);
    this.fields = reordered;
  }

  fieldTypeLabel(fieldType: TemplateFieldType): string {
    return this.fieldTypes.find((type) => type.value === fieldType)?.label || 'Field';
  }

  saveTemplate(): void {
    const name = this.templateInfo.name.trim();
    this.fieldErrors = {};

    if (!name) {
      this.messageType = 'error';
      this.message = 'Add a template name.';
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }

    if (!this.fields.length) {
      this.messageType = 'error';
      this.message = 'Add at least one field for clients to fill in.';
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }

    const invalidField = this.fields.find((field) => !field.label.trim());

    if (invalidField) {
      this.fieldErrors = {
        [invalidField.localId]: 'Add a label for this field.'
      };
      this.messageType = 'error';
      this.message = 'Every field needs a label before saving.';
      window.scrollTo({ top: 0, behavior: 'smooth' });
      return;
    }

    const payload = {
      name,
      purpose: this.templateInfo.purpose.trim(),
      cadence: this.templateInfo.cadence,
      accent: this.templateInfo.accent,
      custom_fields: this.fields.map((field, index) => ({
        key: field.key || this.createFieldKey(field.label, index),
        label: field.label.trim(),
        field_type: field.field_type,
        placeholder: field.placeholder.trim()
      }))
    };
    const request = this.isEditMode
      ? this.templatesApi.updateTemplate(this.templateId, payload)
      : this.templatesApi.createTemplate(payload);

    this.isSaving = true;
    request.subscribe({
      next: () => {
        this.isSaving = false;
        void this.router.navigate(['/trainer/templates']);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be saved.');
        this.isSaving = false;
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }
    });
  }

  private loadTemplate(): void {
    this.templatesApi.getTemplate(this.templateId).subscribe({
      next: (response) => {
        const template = response.template;
        this.templateInfo = {
          name: template.name,
          purpose: template.purpose,
          cadence: template.cadence,
          accent: template.accent || 'green'
        };
        this.fields = template.fields.map((field) => ({ ...field, localId: this.createLocalId() }));
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  private createField(label: string): BuilderField {
    return {
      localId: this.createLocalId(),
      label,
      field_type: 'number',
      placeholder: 'Client enters an update'
    };
  }

  private createLocalId(): string {
    return `field-${Date.now()}-${Math.round(Math.random() * 100000)}`;
  }

  private createFieldKey(label: string, index: number): string {
    const normalizedLabel = label
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_+|_+$/g, '');

    return normalizedLabel || `field_${index + 1}`;
  }
}
