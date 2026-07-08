import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ReferenceCategoryRecord,
  ReferencesApiService,
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';
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
  private readonly referencesApi = inject(ReferencesApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);

  templateId = 0;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  templateInfo: { name: string; purpose: string; cadence: TemplateCadence; accent: string } = {
    name: '',
    purpose: '',
    cadence: 'daily',
    accent: 'green'
  };
  fields: BuilderField[] = [];

  categories: ReferenceCategoryRecord[] = [];
  references: TrainerReferenceRecord[] = [];
  selectedReferenceIds = new Set<number>();
  referenceSearch = '';

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
    this.loadReferenceLibrary();

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

  get filteredReferences(): TrainerReferenceRecord[] {
    const search = this.referenceSearch.trim().toLowerCase();

    if (!search) {
      return this.references;
    }

    return this.references.filter((reference) =>
      [reference.title, reference.category_name, reference.subcategory, reference.tags.join(' ')]
        .join(' ')
        .toLowerCase()
        .includes(search)
    );
  }

  referencesForCategory(category: ReferenceCategoryRecord): TrainerReferenceRecord[] {
    return this.filteredReferences.filter((reference) => reference.category === category.id);
  }

  addField(): void {
    this.fields = [...this.fields, this.createField('New Target')];
  }

  removeField(field: BuilderField): void {
    this.fields = this.fields.filter((currentField) => currentField.localId !== field.localId);
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

  toggleReference(reference: TrainerReferenceRecord): void {
    if (this.selectedReferenceIds.has(reference.id)) {
      this.selectedReferenceIds.delete(reference.id);
    } else {
      this.selectedReferenceIds.add(reference.id);
    }
  }

  isReferenceSelected(reference: TrainerReferenceRecord): boolean {
    return this.selectedReferenceIds.has(reference.id);
  }

  fieldTypeLabel(fieldType: TemplateFieldType): string {
    return this.fieldTypes.find((type) => type.value === fieldType)?.label || 'Field';
  }

  saveTemplate(): void {
    const name = this.templateInfo.name.trim();

    if (!name) {
      this.messageType = 'error';
      this.message = 'Add a template name.';
      return;
    }

    if (!this.fields.length) {
      this.messageType = 'error';
      this.message = 'Add at least one field for clients to fill in.';
      return;
    }

    const payload = {
      name,
      purpose: this.templateInfo.purpose.trim(),
      cadence: this.templateInfo.cadence,
      accent: this.templateInfo.accent,
      custom_fields: this.fields.map((field, index) => ({
        key: field.key || `field_${index + 1}`,
        label: field.label,
        field_type: field.field_type,
        placeholder: field.placeholder
      })),
      reference_ids: Array.from(this.selectedReferenceIds)
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
        this.selectedReferenceIds = new Set(template.references.map((reference) => reference.id));
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be loaded.');
        this.isLoading = false;
      }
    });
  }

  private loadReferenceLibrary(): void {
    this.referencesApi.getCategories().subscribe({
      next: (response) => (this.categories = response.categories),
      error: () => (this.categories = [])
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => (this.references = response.references),
      error: () => (this.references = [])
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
}
