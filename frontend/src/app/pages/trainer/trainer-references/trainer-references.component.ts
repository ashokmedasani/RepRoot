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
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

type ReferenceTypeLabel = 'Video Link' | 'PDF' | 'Image' | 'Document' | 'Text Note' | 'External Link';

const TYPE_LABELS: Record<ReferenceType, ReferenceTypeLabel> = {
  video_link: 'Video Link',
  pdf: 'PDF',
  image: 'Image',
  document: 'Document',
  text_note: 'Text Note',
  external_link: 'External Link'
};

const TYPE_VALUES: Record<ReferenceTypeLabel, ReferenceType> = {
  'Video Link': 'video_link',
  'PDF': 'pdf',
  'Image': 'image',
  'Document': 'document',
  'Text Note': 'text_note',
  'External Link': 'external_link'
};

interface TrainerReferenceView {
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
  subcategoriesText: string;
}

@Component({
  selector: 'app-trainer-references',
  standalone: true,
  imports: [DatePipe, FormsModule, TrainerPageShellComponent],
  templateUrl: './trainer-references.component.html',
  styleUrl: './trainer-references.component.scss'
})
export class TrainerReferencesComponent implements OnInit {
  private readonly sanitizer = inject(DomSanitizer);
  private readonly referencesApi = inject(ReferencesApiService);

  readonly types: ReferenceTypeLabel[] = ['Video Link', 'PDF', 'Image', 'Document', 'Text Note', 'External Link'];
  readonly references = signal<TrainerReferenceView[]>([]);
  readonly categories = signal<ReferenceCategoryRecord[]>([]);
  readonly selectedCategory = signal('All References');
  readonly selectedReferenceId = signal(0);
  readonly query = signal('');
  readonly message = signal('');
  readonly isEditorOpen = signal(false);
  readonly isCategoryEditorOpen = signal(false);
  readonly isSaving = signal(false);

  readonly categoryNames = computed(() => this.categories().map((category) => category.name));
  readonly subcategories = computed(() =>
    Array.from(new Set(this.categories().flatMap((category) => category.subcategories))).sort((first, second) =>
      first.localeCompare(second)
    )
  );

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

  selectReference(reference: TrainerReferenceView): void {
    this.selectedReferenceId.set(reference.id);
  }

  addReference(type: ReferenceTypeLabel = 'Video Link'): void {
    if (!this.categories().length) {
      this.addCategory();
      this.message.set('Create a category first, then add references inside it.');
      return;
    }

    this.form = this.emptyForm(type);
    this.isEditorOpen.set(true);
    this.message.set('');
  }

  addCategory(): void {
    this.categoryForm = this.emptyCategoryForm();
    this.isCategoryEditorOpen.set(true);
  }

  saveCategory(): void {
    const name = this.categoryForm.name.trim();

    if (!name) {
      this.message.set('Add a category name.');
      return;
    }

    this.isSaving.set(true);
    this.referencesApi.createCategory(name, this.parseSubcategories(this.categoryForm.subcategoriesText)).subscribe({
      next: (response) => {
        this.categories.set([...this.categories(), response.category]);
        this.selectedCategory.set(response.category.name);
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

  editReference(reference: TrainerReferenceView): void {
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

  duplicateReference(reference: TrainerReferenceView): void {
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
        this.selectedReferenceId.set(response.reference.id);
        this.message.set('Reference duplicated.');
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Reference could not be duplicated.'));
      }
    });
  }

  deleteReference(reference: TrainerReferenceView): void {
    const confirmed = window.confirm(`Delete ${reference.title}?`);

    if (!confirmed) {
      return;
    }

    this.referencesApi.deleteReference(reference.id).subscribe({
      next: () => {
        const remaining = this.references().filter((item) => item.id !== reference.id);
        this.references.set(remaining);
        this.selectedReferenceId.set(remaining[0]?.id || 0);
        this.message.set('Reference deleted.');
        this.loadCategoriesOnly();
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Reference could not be deleted.'));
      }
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

    if (file.type.startsWith('video/')) {
      this.message.set('Video upload is not supported. Add a YouTube video link instead.');
      input.value = '';
      return;
    }

    this.form.file = file;
    this.form.fileName = file.name;

    if (file.type === 'application/pdf') {
      this.form.type = 'PDF';
    } else if (file.type.startsWith('image/')) {
      this.form.type = 'Image';
    } else if (this.form.type === 'Video Link') {
      this.form.type = 'Document';
    }
  }

  openReference(reference: TrainerReferenceView): void {
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

  resourceInitial(reference: TrainerReferenceView): string {
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

  private toView(reference: TrainerReferenceRecord): TrainerReferenceView {
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
        return 'Paste a YouTube video link.';
      }

      if (this.form.file) {
        return 'Video uploads are not supported. Keep videos as YouTube links only.';
      }

      if (!this.youtubeId(this.form.link.trim())) {
        return 'Videos must be YouTube links so they can be streamed in-app.';
      }
    }

    if (
      this.form.type !== 'Text Note' &&
      this.form.type !== 'Video Link' &&
      !this.form.link.trim() &&
      !this.form.file &&
      !this.form.fileName
    ) {
      return 'Add a link or upload a file.';
    }

    return '';
  }

  private emptyForm(type: ReferenceTypeLabel = 'Video Link'): ReferenceForm {
    const selectedCategory = this.selectedCategory();
    const category =
      selectedCategory !== 'All References'
        ? this.categories().find((item) => item.name === selectedCategory)
        : this.categories()[0];

    return {
      id: 0,
      title: '',
      categoryId: category?.id || null,
      subcategory: category?.subcategories[0] || '',
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
      subcategoriesText: ''
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
