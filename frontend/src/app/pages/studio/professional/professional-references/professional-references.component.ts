import { DatePipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';

import {
  ReferenceCategoryRecord,
  ReferencePayload,
  ReferenceType,
  ReferencesApiService,
  ProfessionalReferenceRecord
} from '@core/api/references-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';

type ReferenceTypeLabel = 'Video Link' | 'PDF Link' | 'Text' | 'Image';

const TYPE_LABELS: Record<ReferenceType, ReferenceTypeLabel> = {
  video_link: 'Video Link',
  pdf: 'PDF Link',
  image: 'Image',
  text_note: 'Text'
};

const TYPE_VALUES: Record<ReferenceTypeLabel, ReferenceType> = {
  'Video Link': 'video_link',
  'PDF Link': 'pdf',
  'Image': 'image',
  'Text': 'text_note'
};

interface ProfessionalReferenceView {
  id: number;
  title: string;
  category: string;
  categoryId: number;
  subcategory: string;
  type: ReferenceTypeLabel;
  description: string;
  link: string;
  fileName: string;
  fileUrl: string;
  tags: string[];
  createdAt: string;
}

interface ReferenceForm {
  id: number;
  title: string;
  categoryId: number | null;
  subcategory: string;
  type: ReferenceTypeLabel;
  description: string;
  link: string;
  tagsText: string;
  fileName: string;
  file: File | null;
}

interface CategoryForm {
  name: string;
  description: string;
  subcategoriesText: string;
  categoryId: number;
}

@Component({
  selector: 'app-professional-references',
  standalone: true,
  imports: [DatePipe, FormsModule, ProfessionalPageShellComponent],
  templateUrl: './professional-references.component.html',
  styleUrl: './professional-references.component.scss'
})
export class ProfessionalReferencesComponent implements OnInit {
  private readonly sanitizer = inject(DomSanitizer);
  private readonly referencesApi = inject(ReferencesApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  readonly types: ReferenceTypeLabel[] = ['Video Link', 'PDF Link', 'Text', 'Image'];
  readonly references = signal<ProfessionalReferenceView[]>([]);
  readonly categories = signal<ReferenceCategoryRecord[]>([]);
  readonly selectedCategory = signal('All References');
  readonly selectedReferenceId = signal(0);
  readonly expandedCategory = signal('');
  readonly expandedReferenceId = signal(0);
  readonly query = signal('');
  readonly message = signal('');
  readonly isEditorOpen = signal(false);
  readonly isCategoryEditorOpen = signal(false);
  readonly isSaving = signal(false);
  readonly categoryEditorMode = signal<'create' | 'edit' | 'subcategory'>('create');
  readonly referenceUsage = signal({ used: 0, limit: null as number | null });
  readonly referenceLimitReached = computed(() => {
    const usage = this.referenceUsage();
    return usage.limit !== null && usage.used >= usage.limit;
  });

  readonly categoryNames = computed(() => this.categories().map((category) => category.name));
  subcategoriesFor(categoryId: number | null): string[] {
    return this.categories().find((category) => category.id === categoryId)?.subcategories || [];
  }

  form: ReferenceForm = this.emptyForm();
  categoryForm: CategoryForm = this.emptyCategoryForm();

  readonly filteredReferences = computed(() => {
    const selectedCategory = this.selectedCategory();
    const search = this.query().trim().toLowerCase();

    return this.references().filter((reference) => {
      const matchesCategory = selectedCategory === 'All References' || reference.category === selectedCategory;
      const searchable = [
        reference.title,
        reference.category,
        reference.subcategory,
        reference.type,
        reference.description,
        reference.tags.join(' ')
      ]
        .join(' ')
        .toLowerCase();

      return matchesCategory && (!search || searchable.includes(search));
    });
  });

  readonly selectedReference = computed(() => {
    const selectedId = this.selectedReferenceId();
    const references = this.filteredReferences();

    return references.find((reference) => reference.id === selectedId) || references[0] || null;
  });

  ngOnInit(): void {
    this.loadLibrary();
  }

  selectCategory(category: string): void {
    this.selectedCategory.set(category);
    this.selectedReferenceId.set(0);
  }

  setSearch(value: string): void {
    this.query.set(value);
  }

  selectReference(reference: ProfessionalReferenceView): void {
    this.selectedReferenceId.set(reference.id);
  }

  toggleCategory(name: string): void {
    this.expandedCategory.set(this.expandedCategory() === name ? '' : name);
    this.expandedReferenceId.set(0);
  }

  toggleReference(id: number): void {
    this.expandedReferenceId.set(this.expandedReferenceId() === id ? 0 : id);
  }

  isCategoryOpen(name: string): boolean {
    return this.expandedCategory() === name || Boolean(this.query().trim());
  }

  referencesForCategory(name: string): ProfessionalReferenceView[] {
    const search = this.query().trim().toLowerCase();

    return this.references().filter((reference) => {
      if (reference.category !== name) {
        return false;
      }

      if (!search) {
        return true;
      }

      return [reference.title, reference.subcategory, reference.type, reference.description, reference.tags.join(' ')]
        .join(' ')
        .toLowerCase()
        .includes(search);
    });
  }

  addReference(type: ReferenceTypeLabel = 'Video Link', category?: ReferenceCategoryRecord, subcategory = ''): void {
    if (this.referenceLimitReached()) {
      this.message.set('You have reached the Version 1 reference limit.');
      return;
    }

    if (!this.categories().length) {
      this.addCategory();
      this.message.set('Create a category first, then add references inside it.');
      return;
    }

    this.form = this.emptyForm(type, category, subcategory);
    this.isEditorOpen.set(true);
    this.message.set('');
  }

  addCategory(): void {
    this.categoryEditorMode.set('create');
    this.categoryForm = this.emptyCategoryForm();
    this.isCategoryEditorOpen.set(true);
    this.message.set('');
  }

  addSubcategory(category: ReferenceCategoryRecord): void {
    this.categoryEditorMode.set('subcategory');
    this.categoryForm = {
      categoryId: category.id,
      name: category.name,
      description: category.description || '',
      subcategoriesText: ''
    };
    this.isCategoryEditorOpen.set(true);
    this.message.set('');
  }

  editCategory(category: ReferenceCategoryRecord): void {
    this.categoryEditorMode.set('edit');
    this.categoryForm = {
      categoryId: category.id,
      name: category.name,
      description: category.description || '',
      subcategoriesText: category.subcategories.join('\n')
    };
    this.isCategoryEditorOpen.set(true);
    this.message.set('');
  }

  saveCategory(): void {
    const name = this.categoryForm.name.trim();

    if (!name) {
      this.message.set('Add a category name.');
      return;
    }

    this.isSaving.set(true);
    const existingCategory = this.categories().find((category) => category.id === this.categoryForm.categoryId);
    const subcategories = existingCategory && this.categoryEditorMode() === 'subcategory'
      ? [...existingCategory.subcategories, ...this.parseSubcategories(this.categoryForm.subcategoriesText)]
      : this.parseSubcategories(this.categoryForm.subcategoriesText);
    const uniqueSubcategories = Array.from(new Set(subcategories.map((item) => item.trim()).filter(Boolean)));
    const request = existingCategory
      ? this.referencesApi.updateCategory(existingCategory.id, name, this.categoryForm.description.trim(), uniqueSubcategories)
      : this.referencesApi.createCategory(name, this.categoryForm.description.trim(), uniqueSubcategories);

    request.subscribe({
      next: (response) => {
        this.categories.set(
          existingCategory
            ? this.categories().map((category) => (category.id === response.category.id ? response.category : category))
            : [...this.categories(), response.category]
        );
        this.selectedCategory.set(response.category.name);
        this.expandedCategory.set(response.category.name);
        this.isCategoryEditorOpen.set(false);
        this.isSaving.set(false);
        this.message.set(response.message);
      },
      error: (error: unknown) => {
        this.isSaving.set(false);
        this.message.set(formatApiError(error, 'Category could not be saved.'));
      }
    });
  }

  editReference(reference: ProfessionalReferenceView): void {
    this.form = {
      id: reference.id,
      title: reference.title,
      categoryId: reference.categoryId,
      subcategory: reference.subcategory,
      type: reference.type,
      description: reference.description,
      link: reference.link,
      tagsText: reference.tags.join(', '),
      fileName: reference.fileName,
      file: null
    };
    this.isEditorOpen.set(true);
    this.message.set('');
  }

  duplicateReference(reference: ProfessionalReferenceView): void {
    if (this.referenceLimitReached()) {
      this.message.set('You have reached the Version 1 reference limit.');
      return;
    }

    const payload: ReferencePayload = {
      category: reference.categoryId,
      subcategory: reference.subcategory,
      title: `${reference.title} Copy`,
      reference_type: TYPE_VALUES[reference.type],
      description: reference.description,
      link: reference.link || reference.fileUrl,
      tags: reference.tags
    };

    this.referencesApi.createReference(payload).subscribe({
      next: (response) => {
        this.references.set([this.toView(response.reference), ...this.references()]);
        this.referenceUsage.update((usage) => ({ ...usage, used: usage.used + 1 }));
        this.selectedReferenceId.set(response.reference.id);
        this.message.set('Reference duplicated.');
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Reference could not be duplicated.'));
      }
    });
  }

  async deleteReference(reference: ProfessionalReferenceView): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete',
      target: reference.title,
      impact: 'This reference will be removed from the library and may no longer be available to connected templates. This action may not be reversible.',
      confirmLabel: 'Delete Reference'
    });

    if (!confirmed) {
      return;
    }

    this.referencesApi.deleteReference(reference.id).subscribe({
      next: () => {
        const remaining = this.references().filter((item) => item.id !== reference.id);
        this.references.set(remaining);
        this.referenceUsage.update((usage) => ({ ...usage, used: Math.max(0, usage.used - 1) }));
        this.selectedReferenceId.set(remaining[0]?.id || 0);
        this.message.set('Reference deleted.');
        this.loadCategoriesOnly();
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Reference could not be deleted.'));
      }
    });
  }

  async deleteCategory(category: ReferenceCategoryRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete',
      target: category.name,
      impact: 'This category can only be deleted when it contains no references. Connected content may be affected.',
      confirmLabel: 'Delete Category'
    });

    if (!confirmed) {
      return;
    }

    this.referencesApi.deleteCategory(category.id).subscribe({
      next: (response) => {
        this.categories.set(this.categories().filter((item) => item.id !== category.id));
        this.message.set(response.message);
      },
      error: (error: unknown) => this.message.set(formatApiError(error, 'Category could not be deleted.'))
    });
  }

  async deleteSubcategory(category: ReferenceCategoryRecord, subcategory: string): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete subcategory',
      target: subcategory,
      impact: 'The subcategory can only be removed safely when its references have been moved or deleted.',
      confirmLabel: 'Delete Subcategory'
    });

    if (!confirmed) {
      return;
    }

    const subcategories = category.subcategories.filter((item) => item !== subcategory);
    this.referencesApi.updateCategory(category.id, category.name, category.description, subcategories).subscribe({
      next: (response) => {
        this.categories.set(this.categories().map((item) => item.id === category.id ? response.category : item));
        this.message.set(response.message);
      },
      error: (error: unknown) => this.message.set(formatApiError(error, 'Subcategory could not be deleted.'))
    });
  }

  saveReference(): void {
    const validationError = this.validateForm();

    if (validationError) {
      this.message.set(validationError);
      return;
    }

    const payload: ReferencePayload = {
      category: this.form.categoryId as number,
      subcategory: this.form.subcategory.trim(),
      title: this.form.title.trim(),
      reference_type: TYPE_VALUES[this.form.type],
      description: this.form.description.trim(),
      link: this.form.link.trim(),
      tags: this.form.tagsText
        .split(',')
        .map((tag) => tag.trim())
        .filter(Boolean),
      file: this.form.file
    };
    const isUpdate = Boolean(this.form.id);
    const request = isUpdate
      ? this.referencesApi.updateReference(this.form.id, payload)
      : this.referencesApi.createReference(payload);

    this.isSaving.set(true);
    request.subscribe({
      next: (response) => {
        const view = this.toView(response.reference);
        const references = this.references();
        this.references.set(
          isUpdate ? references.map((reference) => (reference.id === view.id ? view : reference)) : [view, ...references]
        );
        if (!isUpdate) {
          this.referenceUsage.update((usage) => ({ ...usage, used: usage.used + 1 }));
        }
        this.selectedCategory.set('All References');
        this.selectedReferenceId.set(view.id);
        this.isEditorOpen.set(false);
        this.isSaving.set(false);
        this.message.set(response.message);
        this.loadCategoriesOnly();
      },
      error: (error: unknown) => {
        this.isSaving.set(false);
        this.message.set(formatApiError(error, 'Reference could not be saved.'));
      }
    });
  }

  handleFileUpload(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    if (this.form.type === 'PDF Link') {
      if (file.type !== 'application/pdf') {
        this.message.set('Only PDF uploads are supported for PDF references.');
        input.value = '';
        return;
      }
    } else if (!file.type.startsWith('image/')) {
      this.message.set('Only image uploads are supported for image references.');
      input.value = '';
      return;
    }

    this.form.file = file;
    this.form.fileName = file.name;
    if (this.form.type !== 'PDF Link') {
      this.form.type = 'Image';
    }
  }

  openReference(reference: ProfessionalReferenceView): void {
    const url = reference.fileUrl || reference.link;

    if (!url) {
      return;
    }

    window.open(url, '_blank', 'noopener,noreferrer');
  }

  categoryCount(category: string): number {
    return this.references().filter((reference) => reference.category === category).length;
  }

  youtubeEmbedUrl(link: string): string {
    const videoId = this.youtubeId(link);

    return videoId ? `https://www.youtube.com/embed/${videoId}` : '';
  }

  youtubeEmbedResourceUrl(link: string): SafeResourceUrl | null {
    const embedUrl = this.youtubeEmbedUrl(link);

    return embedUrl ? this.sanitizer.bypassSecurityTrustResourceUrl(embedUrl) : null;
  }

  resourceInitial(reference: ProfessionalReferenceView): string {
    return reference.title.trim().charAt(0).toUpperCase() || 'R';
  }

  private loadLibrary(): void {
    this.referencesApi.getCategories().subscribe({
      next: (response) => this.categories.set(response.categories),
      error: (error: unknown) => this.message.set(formatApiError(error, 'Categories could not be loaded.'))
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => {
        const views = response.references.map((reference) => this.toView(reference));
        this.references.set(views);
        this.referenceUsage.set(response.usage);
        this.selectedReferenceId.set(views[0]?.id || 0);
      },
      error: (error: unknown) => this.message.set(formatApiError(error, 'References could not be loaded.'))
    });
  }

  private loadCategoriesOnly(): void {
    this.referencesApi.getCategories().subscribe({
      next: (response) => this.categories.set(response.categories)
    });
  }

  private toView(reference: ProfessionalReferenceRecord): ProfessionalReferenceView {
    return {
      id: reference.id,
      title: reference.title,
      category: reference.category_name,
      categoryId: reference.category,
      subcategory: reference.subcategory,
      type: TYPE_LABELS[reference.reference_type],
      description: reference.description,
      link: reference.link,
      fileName: reference.file_name,
      fileUrl: reference.file_url,
      tags: reference.tags,
      createdAt: reference.created_at
    };
  }

  private validateForm(): string {
    if (!this.form.title.trim()) {
      return 'Add a title for this reference.';
    }

    if (!this.form.categoryId) {
      return 'Choose a category.';
    }

    if (this.form.type === 'Video Link') {
      if (!this.form.link.trim()) {
        return 'Paste a video URL.';
      }

      if (this.form.file) {
        return 'Video uploads are not supported. Keep videos as YouTube links only.';
      }

      if (!this.youtubeId(this.form.link.trim())) {
        return 'Videos must be YouTube links so they can be streamed in-app.';
      }
    }

    if (this.form.type === 'PDF Link' && !this.form.link.trim() && !this.form.file && !this.form.fileName) {
      return 'Upload a PDF or paste a PDF URL.';
    }

    if (this.form.type === 'Text' && !this.form.description.trim()) {
      return 'Add text for this reference.';
    }

    if (this.form.type === 'Image' && !this.form.file && !this.form.fileName) {
      return 'Upload an image.';
    }

    return '';
  }

  private emptyForm(type: ReferenceTypeLabel = 'Video Link', providedCategory?: ReferenceCategoryRecord, subcategory = ''): ReferenceForm {
    const selectedCategory = this.selectedCategory();
    const category =
      providedCategory ||
      (selectedCategory !== 'All References'
        ? this.categories().find((item) => item.name === selectedCategory)
        : this.categories()[0]);

    return {
      id: 0,
      title: '',
      categoryId: category?.id || null,
      subcategory: subcategory || category?.subcategories[0] || '',
      type,
      description: '',
      link: '',
      tagsText: '',
      fileName: '',
      file: null
    };
  }

  private emptyCategoryForm(): CategoryForm {
    return {
      name: '',
      description: '',
      subcategoriesText: '',
      categoryId: 0
    };
  }

  private parseSubcategories(value: string): string[] {
    return Array.from(
      new Set(
        value
          .split(/\r?\n|,/)
          .map((item) => item.trim())
          .filter(Boolean)
      )
    );
  }

  private youtubeId(link: string): string {
    const patterns = [/youtu\.be\/([^?&/]+)/, /youtube\.com\/watch\?v=([^?&]+)/, /youtube\.com\/embed\/([^?&/]+)/];
    const match = patterns.map((pattern) => link.match(pattern)?.[1]).find(Boolean);

    return match || '';
  }
}
