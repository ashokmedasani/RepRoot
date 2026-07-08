import { DatePipe } from '@angular/common';
import { Component, computed, signal } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';

import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

type ReferenceType = 'Video Link' | 'PDF' | 'Image' | 'Document' | 'Text Note' | 'External Link';

interface TrainerReference {
  id: string;
  title: string;
  category: string;
  subcategory: string;
  type: ReferenceType;
  description: string;
  link: string;
  fileName: string;
  fileDataUrl: string;
  tags: string[];
  createdAt: string;
}

interface ReferenceCategory {
  id: string;
  name: string;
  subcategories: string[];
  createdAt: string;
}

interface ReferenceForm {
  id: string;
  title: string;
  category: string;
  subcategory: string;
  type: ReferenceType;
  description: string;
  link: string;
  tagsText: string;
  fileName: string;
  fileDataUrl: string;
}

interface CategoryForm {
  name: string;
  subcategoriesText: string;
}

const STORAGE_KEY_PREFIX = 'coachflow-trainer-references';
const CATEGORY_STORAGE_KEY_PREFIX = 'coachflow-trainer-reference-categories';

@Component({
  selector: 'app-trainer-references',
  standalone: true,
  imports: [DatePipe, FormsModule, TrainerPageShellComponent],
  templateUrl: './trainer-references.component.html',
  styleUrl: './trainer-references.component.scss'
})
export class TrainerReferencesComponent {
  constructor(private readonly sanitizer: DomSanitizer) {}

  readonly types: ReferenceType[] = ['Video Link', 'PDF', 'Image', 'Document', 'Text Note', 'External Link'];
  readonly references = signal<TrainerReference[]>(this.loadReferences());
  readonly categories = signal<ReferenceCategory[]>(this.loadCategories(this.references()));
  readonly selectedCategory = signal('All References');
  readonly selectedReferenceId = signal(this.references()[0]?.id || '');
  readonly query = signal('');
  readonly message = signal('');
  readonly isEditorOpen = signal(false);
  readonly isCategoryEditorOpen = signal(false);

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

  selectCategory(category: string): void {
    this.selectedCategory.set(category);
    this.selectedReferenceId.set('');
  }

  setSearch(value: string): void {
    this.query.set(value);
  }

  selectReference(reference: TrainerReference): void {
    this.selectedReferenceId.set(reference.id);
  }

  addReference(type: ReferenceType = 'Video Link'): void {
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

    const exists = this.categories().some((category) => category.name.toLowerCase() === name.toLowerCase());

    if (exists) {
      this.message.set('That category already exists.');
      return;
    }

    const category: ReferenceCategory = {
      id: crypto.randomUUID(),
      name,
      subcategories: this.parseSubcategories(this.categoryForm.subcategoriesText),
      createdAt: new Date().toISOString()
    };

    this.persistCategories([...this.categories(), category]);
    this.selectedCategory.set(name);
    this.isCategoryEditorOpen.set(false);
    this.message.set('Category created.');
  }

  editReference(reference: TrainerReference): void {
    this.form = {
      id: reference.id,
      title: reference.title,
      category: reference.category,
      subcategory: reference.subcategory,
      type: reference.type,
      description: reference.description,
      link: reference.link,
      tagsText: reference.tags.join(', '),
      fileName: reference.fileName,
      fileDataUrl: reference.fileDataUrl
    };
    this.isEditorOpen.set(true);
    this.message.set('');
  }

  duplicateReference(reference: TrainerReference): void {
    const copy = {
      ...reference,
      id: crypto.randomUUID(),
      title: `${reference.title} Copy`,
      createdAt: new Date().toISOString()
    };
    this.persist([copy, ...this.references()]);
    this.selectedReferenceId.set(copy.id);
    this.message.set('Reference duplicated.');
  }

  deleteReference(reference: TrainerReference): void {
    const confirmed = window.confirm(`Delete ${reference.title}?`);

    if (!confirmed) {
      return;
    }

    const remaining = this.references().filter((item) => item.id !== reference.id);
    this.persist(remaining);
    this.selectedReferenceId.set(remaining[0]?.id || '');
    this.message.set('Reference deleted.');
  }

  saveReference(): void {
    const validationError = this.validateForm();

    if (validationError) {
      this.message.set(validationError);
      return;
    }

    const tags = this.form.tagsText
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean);
    const nextReference: TrainerReference = {
      id: this.form.id || crypto.randomUUID(),
      title: this.form.title.trim(),
      category: this.form.category,
      subcategory: this.form.subcategory.trim(),
      type: this.form.type,
      description: this.form.description.trim(),
      link: this.form.link.trim(),
      fileName: this.form.fileName,
      fileDataUrl: this.form.fileDataUrl,
      tags,
      createdAt: this.form.id
        ? this.references().find((reference) => reference.id === this.form.id)?.createdAt || new Date().toISOString()
        : new Date().toISOString()
    };
    const references = this.references();
    const exists = references.some((reference) => reference.id === nextReference.id);
    const updated = exists
      ? references.map((reference) => (reference.id === nextReference.id ? nextReference : reference))
      : [nextReference, ...references];

    this.persist(updated);
    this.selectedCategory.set('All References');
    this.selectedReferenceId.set(nextReference.id);
    this.isEditorOpen.set(false);
    this.message.set(exists ? 'Reference updated.' : 'Reference added.');
  }

  handleFileUpload(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    if (file.type.startsWith('video/')) {
      this.message.set('Video upload is not supported. Add a YouTube or external video link instead.');
      input.value = '';
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      this.form.fileName = file.name;
      this.form.fileDataUrl = String(reader.result || '');

      if (file.type === 'application/pdf') {
        this.form.type = 'PDF';
      } else if (file.type.startsWith('image/')) {
        this.form.type = 'Image';
      } else if (this.form.type === 'Video Link') {
        this.form.type = 'Document';
      }
    };
    reader.readAsDataURL(file);
  }

  openReference(reference: TrainerReference): void {
    const url = reference.fileDataUrl || reference.link;

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

  resourceInitial(reference: TrainerReference): string {
    return reference.title.trim().charAt(0).toUpperCase() || 'R';
  }

  private validateForm(): string {
    if (!this.form.title.trim()) {
      return 'Add a title for this reference.';
    }

    if (!this.form.category) {
      return 'Choose a category.';
    }

    if (this.form.type === 'Video Link') {
      if (!this.form.link.trim()) {
        return 'Paste a YouTube or external video link.';
      }

      if (this.form.fileDataUrl) {
        return 'Video uploads are not supported. Keep videos as links only.';
      }
    }

    if (this.form.type !== 'Text Note' && this.form.type !== 'Video Link' && !this.form.link.trim() && !this.form.fileDataUrl) {
      return 'Add a link or upload a file.';
    }

    return '';
  }

  private emptyForm(type: ReferenceType = 'Video Link'): ReferenceForm {
    const selectedCategory = this.selectedCategory();
    const category = selectedCategory !== 'All References' ? selectedCategory : this.categoryNames()[0] || '';
    const subcategories = this.categories().find((item) => item.name === category)?.subcategories || [];

    return {
      id: '',
      title: '',
      category,
      subcategory: subcategories[0] || '',
      type,
      description: '',
      link: '',
      tagsText: '',
      fileName: '',
      fileDataUrl: ''
    };
  }

  private emptyCategoryForm(): CategoryForm {
    return {
      name: '',
      subcategoriesText: ''
    };
  }

  private loadReferences(): TrainerReference[] {
    const saved = window.localStorage.getItem(this.storageKey());

    if (saved) {
      try {
        return JSON.parse(saved) as TrainerReference[];
      } catch {
        window.localStorage.removeItem(this.storageKey());
      }
    }

    return [];
  }

  private persist(references: TrainerReference[]): void {
    this.references.set(references);
    window.localStorage.setItem(this.storageKey(), JSON.stringify(references));
  }

  private loadCategories(references: TrainerReference[]): ReferenceCategory[] {
    const saved = window.localStorage.getItem(this.categoryStorageKey());

    if (saved) {
      try {
        return JSON.parse(saved) as ReferenceCategory[];
      } catch {
        window.localStorage.removeItem(this.categoryStorageKey());
      }
    }

    const categoryNames = Array.from(new Set(references.map((reference) => reference.category).filter(Boolean)));

    return categoryNames.map((name) => ({
      id: crypto.randomUUID(),
      name,
      subcategories: Array.from(
        new Set(
          references
            .filter((reference) => reference.category === name)
            .map((reference) => reference.subcategory)
            .filter(Boolean)
        )
      ),
      createdAt: new Date().toISOString()
    }));
  }

  private persistCategories(categories: ReferenceCategory[]): void {
    this.categories.set(categories);
    window.localStorage.setItem(this.categoryStorageKey(), JSON.stringify(categories));
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

  private storageKey(): string {
    const trainerId = window.localStorage.getItem('trainer-account-id');

    if (trainerId) {
      return `${STORAGE_KEY_PREFIX}-trainer-${trainerId}`;
    }

    const username = window.localStorage.getItem('trainer-account-username');

    if (username) {
      return `${STORAGE_KEY_PREFIX}-username-${this.hashStorageIdentity(username)}`;
    }

    const token = window.localStorage.getItem('trainer-auth-token') || 'guest';

    return `${STORAGE_KEY_PREFIX}-token-${this.hashStorageIdentity(token)}`;
  }

  private categoryStorageKey(): string {
    const trainerId = window.localStorage.getItem('trainer-account-id');

    if (trainerId) {
      return `${CATEGORY_STORAGE_KEY_PREFIX}-trainer-${trainerId}`;
    }

    const username = window.localStorage.getItem('trainer-account-username');

    if (username) {
      return `${CATEGORY_STORAGE_KEY_PREFIX}-username-${this.hashStorageIdentity(username)}`;
    }

    const token = window.localStorage.getItem('trainer-auth-token') || 'guest';

    return `${CATEGORY_STORAGE_KEY_PREFIX}-token-${this.hashStorageIdentity(token)}`;
  }

  private hashStorageIdentity(value: string): string {
    let hash = 0;

    for (let index = 0; index < value.length; index += 1) {
      hash = (hash << 5) - hash + value.charCodeAt(index);
      hash |= 0;
    }

    return Math.abs(hash).toString(36);
  }

  private youtubeId(link: string): string {
    const patterns = [/youtu\.be\/([^?&/]+)/, /youtube\.com\/watch\?v=([^?&]+)/, /youtube\.com\/embed\/([^?&/]+)/];
    const match = patterns.map((pattern) => link.match(pattern)?.[1]).find(Boolean);

    return match || '';
  }
}
