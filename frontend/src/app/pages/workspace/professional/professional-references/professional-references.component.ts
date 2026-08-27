import { DatePipe } from '@angular/common';
import { Component, OnInit, computed, signal } from '@angular/core';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';
import { CdkDragDrop, DragDropModule, moveItemInArray } from '@angular/cdk/drag-drop';

import {
  ResourceCategoryRecord,
  ResourcePayload,
  ResourceType,
  ResourcesApiService,
  ProfessionalResourceRecord
} from '@core/api/resources-api.service';
import { PlanLockApiService, PlanLockStatus } from '@core/api/plan-lock-api.service';
import { ProfessionalPageShellComponent } from '@workspace-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { SkeletonComponent } from '@workspace-shared/skeleton/skeleton.component';
import { assertPdfWithinLimit, compressImageFile } from '@shared/utils/image-compression';
import { InfoHintComponent } from '@shared/info-hint/info-hint.component';

type ReferenceTypeLabel = 'Video Link' | 'PDF' | 'Text' | 'Image';

const TYPE_LABELS: Record<ResourceType, ReferenceTypeLabel> = {
  video_link: 'Video Link',
  pdf: 'PDF',
  image: 'Image',
  text_note: 'Text'
};

const TYPE_VALUES: Record<ReferenceTypeLabel, ResourceType> = {
  'Video Link': 'video_link',
  'PDF': 'pdf',
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
  imports: [DatePipe, FormsModule, DragDropModule, ProfessionalPageShellComponent, SkeletonComponent, InfoHintComponent],
  templateUrl: './professional-references.component.html',
  styleUrl: './professional-references.component.scss'
})
export class ProfessionalReferencesComponent implements OnInit {
  private readonly sanitizer = inject(DomSanitizer);
  private readonly referencesApi = inject(ResourcesApiService);
  private readonly planLockApi = inject(PlanLockApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  // Plan-limit lock system: a category/resource beyond the current plan's
  // count limit is "locked" (never deleted). Locked categories lock every
  // resource inside them too, regardless of the resource's own rank. Only
  // currently-active items can be reordered or edited; locked ones can
  // still be deleted (which frees a slot and promotes the next one).
  readonly lockStatus = signal<PlanLockStatus | null>(null);

  isCategoryLocked(categoryId: number): boolean {
    return this.lockStatus()?.categories.locked_ids.includes(categoryId) ?? false;
  }

  isResourceLocked(resourceId: number): boolean {
    return this.lockStatus()?.resources.locked_ids.includes(resourceId) ?? false;
  }

  // Categories are a flat, professional-wide list, so display order is
  // always derived straight from lockStatus.categories.active_ids -- never a
  // separately-tracked local array -- so dragging can never drift out of
  // sync with what the backend thinks the order is.
  orderedActiveCategories(): ResourceCategoryRecord[] {
    const activeIds = this.lockStatus()?.categories.active_ids ?? [];
    const byId = new Map(this.categories().map((category) => [category.id, category]));
    return activeIds.map((id) => byId.get(id)).filter((category): category is ResourceCategoryRecord => !!category);
  }

  lockedCategoriesList(): ResourceCategoryRecord[] {
    const lockedIds = new Set(this.lockStatus()?.categories.locked_ids ?? []);
    return this.categories().filter((category) => lockedIds.has(category.id));
  }

  dropCategory(event: CdkDragDrop<ResourceCategoryRecord[]>): void {
    if (event.previousIndex === event.currentIndex) return;

    const reordered = this.orderedActiveCategories();
    moveItemInArray(reordered, event.previousIndex, event.currentIndex);
    const orderedIds = reordered.map((category) => category.id);

    const current = this.lockStatus();
    if (current) {
      this.lockStatus.set({ ...current, categories: { ...current.categories, active_ids: orderedIds } });
    }

    this.planLockApi.reorder('categories', orderedIds).subscribe({
      next: (response) => this.lockStatus.set(response.lock_status),
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Could not reorder categories.'));
        this.loadLockStatus();
      }
    });
  }

  // Resources are ranked professional-wide (not per subcategory), but the
  // library only shows one subcategory's worth at a time. Dragging within a
  // subcategory reorders just that visible subset while preserving the
  // exact slots those resources occupy in the full ranking, so priority
  // between resources in other categories/subcategories is untouched.
  orderedActiveResourcesFor(categoryName: string, subcategory: string): ProfessionalReferenceView[] {
    const activeIds = this.lockStatus()?.resources.active_ids ?? [];
    const byId = new Map(this.references().map((reference) => [reference.id, reference]));
    return activeIds
      .map((id) => byId.get(id))
      .filter(
        (reference): reference is ProfessionalReferenceView =>
          !!reference &&
          reference.category === categoryName &&
          reference.subcategory === subcategory &&
          this.matchesQuery(reference)
      );
  }

  lockedResourcesFor(categoryName: string, subcategory: string): ProfessionalReferenceView[] {
    const lockedIds = new Set(this.lockStatus()?.resources.locked_ids ?? []);
    return this.references().filter(
      (reference) =>
        reference.category === categoryName &&
        reference.subcategory === subcategory &&
        lockedIds.has(reference.id) &&
        this.matchesQuery(reference)
    );
  }

  /** Whether a resource matches the search box.
   *
   *  The two functions above are the only ones the template actually renders,
   *  and neither used to consult `query()` at all -- so typing in the search
   *  box filtered nothing. Its only visible effect was `isCategoryOpen()`
   *  returning true for every category, which expanded all of them and showed
   *  *more* rows than before searching. */
  private matchesQuery(reference: ProfessionalReferenceView): boolean {
    const search = this.query().trim().toLowerCase();
    if (!search) {
      return true;
    }

    return [reference.title, reference.category, reference.subcategory, reference.type, reference.description, reference.tags.join(' ')]
      .join(' ')
      .toLowerCase()
      .includes(search);
  }

  /** True while the user is searching, so the template can hide categories and
   *  subcategories that contain no matches instead of rendering empty shells. */
  isSearching(): boolean {
    return Boolean(this.query().trim());
  }

  /** Subcategories worth rendering: all of them normally, and only the ones
   *  holding a match while searching. */
  visibleSubcategoriesFor(category: ResourceCategoryRecord): string[] {
    if (!this.isSearching()) {
      return category.subcategories;
    }

    return category.subcategories.filter(
      (subcategory) =>
        this.orderedActiveResourcesFor(category.name, subcategory).length > 0 ||
        this.lockedResourcesFor(category.name, subcategory).length > 0
    );
  }

  categoryHasVisibleResources(category: ResourceCategoryRecord): boolean {
    return !this.isSearching() || this.visibleSubcategoriesFor(category).length > 0;
  }

  /** Total matches across every category, for the "nothing found" message. */
  searchMatchCount(): number {
    if (!this.isSearching()) {
      return this.references().length;
    }
    return this.references().filter((reference) => this.matchesQuery(reference)).length;
  }

  dropResource(event: CdkDragDrop<ProfessionalReferenceView[]>, categoryName: string, subcategory: string): void {
    if (event.previousIndex === event.currentIndex) return;

    const scoped = this.orderedActiveResourcesFor(categoryName, subcategory);
    moveItemInArray(scoped, event.previousIndex, event.currentIndex);
    const scopedIds = scoped.map((reference) => reference.id);
    const scopedIdSet = new Set(scopedIds);

    const fullActiveIds = this.lockStatus()?.resources.active_ids ?? [];
    let cursor = 0;
    const mergedIds = fullActiveIds.map((id) => (scopedIdSet.has(id) ? scopedIds[cursor++] : id));

    const current = this.lockStatus();
    if (current) {
      this.lockStatus.set({ ...current, resources: { ...current.resources, active_ids: mergedIds } });
    }

    this.planLockApi.reorder('resources', mergedIds).subscribe({
      next: (response) => this.lockStatus.set(response.lock_status),
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Could not reorder resources.'));
        this.loadLockStatus();
      }
    });
  }

  private loadLockStatus(): void {
    this.planLockApi.getLockStatus().subscribe({
      next: (response) => this.lockStatus.set(response.lock_status)
    });
  }

  readonly types: ReferenceTypeLabel[] = ['Video Link', 'PDF', 'Text', 'Image'];
  readonly references = signal<ProfessionalReferenceView[]>([]);
  readonly categories = signal<ResourceCategoryRecord[]>([]);
  readonly selectedCategory = signal('All References');
  readonly selectedReferenceId = signal(0);
  readonly expandedCategory = signal('');
  readonly expandedReferenceId = signal(0);
  readonly query = signal('');
  readonly message = signal('');
  readonly isEditorOpen = signal(false);
  readonly isCategoryEditorOpen = signal(false);
  readonly isSaving = signal(false);
  /** Both library requests are in flight. Without this the template rendered
   *  its "No categories yet." empty state on every load. */
  readonly isLoading = signal(true);
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
    this.loadLockStatus();
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

  addReference(type: ReferenceTypeLabel = 'Video Link', category?: ResourceCategoryRecord, subcategory = ''): void {
    if (this.referenceLimitReached()) {
      this.message.set('You have reached the Version 1 resource limit.');
      return;
    }

    if (!this.categories().length) {
      this.addCategory();
      this.message.set('Create a category first, then add resources inside it.');
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

  addSubcategory(category: ResourceCategoryRecord): void {
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

  editCategory(category: ResourceCategoryRecord): void {
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

  async saveCategory(): Promise<void> {
    const name = this.categoryForm.name.trim();

    if (!name) {
      this.message.set('Add a category name.');
      return;
    }

    const existingCategory = this.categories().find((category) => category.id === this.categoryForm.categoryId);
    const subcategories = existingCategory && this.categoryEditorMode() === 'subcategory'
      ? [...existingCategory.subcategories, ...this.parseSubcategories(this.categoryForm.subcategoriesText)]
      : this.parseSubcategories(this.categoryForm.subcategoriesText);
    const uniqueSubcategories = Array.from(new Set(subcategories.map((item) => item.trim()).filter(Boolean)));

    // Editing the list is a delete path too: any subcategory the professional
    // removed from the textarea still owns resources, and those resources match
    // no rendered block afterwards -- they vanish from the library while still
    // counting against the plan's resource limit. The explicit Delete button
    // already warns about this; the edit path did not.
    if (existingCategory && this.categoryEditorMode() === 'edit') {
      const removed = existingCategory.subcategories.filter((item) => !uniqueSubcategories.includes(item));
      const orphaned = removed.filter(
        (item) =>
          this.orderedActiveResourcesFor(existingCategory.name, item).length > 0 ||
          this.lockedResourcesFor(existingCategory.name, item).length > 0
      );

      if (orphaned.length) {
        const confirmed = await this.confirmation.confirm({
          kind: 'delete',
          title: 'Remove subcategories that still hold resources',
          target: orphaned.join(', '),
          impact:
            'The resources filed under them stay in your library and keep using resource slots, but they will no longer appear anywhere. Move or delete those resources first if you want to keep them reachable.',
          confirmLabel: 'Remove Anyway'
        });

        if (!confirmed) {
          return;
        }
      }
    }

    this.isSaving.set(true);
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
        this.loadLockStatus();
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
      this.message.set('You have reached the Version 1 resource limit.');
      return;
    }

    const payload: ResourcePayload = {
      category: reference.categoryId,
      subcategory: reference.subcategory,
      title: `${reference.title} Copy`,
      resource_type: TYPE_VALUES[reference.type],
      description: reference.description,
      link: reference.link || reference.fileUrl,
      tags: reference.tags
    };

    this.referencesApi.createResource(payload).subscribe({
      next: (response) => {
        this.references.set([this.toView(response.resource), ...this.references()]);
        this.referenceUsage.update((usage) => ({ ...usage, used: usage.used + 1 }));
        this.selectedReferenceId.set(response.resource.id);
        this.message.set('Resource duplicated.');
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Resource could not be duplicated.'));
      }
    });
  }

  async deleteReference(reference: ProfessionalReferenceView): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete',
      target: reference.title,
      impact: 'This resource will be removed from the library and may no longer be available to connected templates. This action may not be reversible.',
      confirmLabel: 'Delete Resource'
    });

    if (!confirmed) {
      return;
    }

    this.referencesApi.deleteResource(reference.id).subscribe({
      next: () => {
        const remaining = this.references().filter((item) => item.id !== reference.id);
        this.references.set(remaining);
        this.referenceUsage.update((usage) => ({ ...usage, used: Math.max(0, usage.used - 1) }));
        this.selectedReferenceId.set(remaining[0]?.id || 0);
        this.message.set('Resource deleted.');
        this.loadCategoriesOnly();
        this.loadLockStatus();
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Resource could not be deleted.'));
      }
    });
  }

  async deleteCategory(category: ResourceCategoryRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete',
      target: category.name,
      impact: 'This category can only be deleted when it contains no resources. Connected content may be affected.',
      confirmLabel: 'Delete Category'
    });

    if (!confirmed) {
      return;
    }

    this.referencesApi.deleteCategory(category.id).subscribe({
      next: (response) => {
        this.categories.set(this.categories().filter((item) => item.id !== category.id));
        this.message.set(response.message);
        this.loadLockStatus();
      },
      error: (error: unknown) => this.message.set(formatApiError(error, 'Category could not be deleted.'))
    });
  }

  async deleteSubcategory(category: ResourceCategoryRecord, subcategory: string): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete subcategory',
      target: subcategory,
      impact: 'The subcategory can only be removed safely when its resources have been moved or deleted.',
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

    const payload: ResourcePayload = {
      category: this.form.categoryId as number,
      subcategory: this.form.subcategory.trim(),
      title: this.form.title.trim(),
      resource_type: TYPE_VALUES[this.form.type],
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
      ? this.referencesApi.updateResource(this.form.id, payload)
      : this.referencesApi.createResource(payload);

    this.isSaving.set(true);
    request.subscribe({
      next: (response) => {
        const view = this.toView(response.resource);
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
        this.loadLockStatus();
      },
      error: (error: unknown) => {
        this.isSaving.set(false);
        this.message.set(formatApiError(error, 'Resource could not be saved.'));
      }
    });
  }

  handleFileUpload(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    if (this.form.type === 'PDF') {
      if (file.type !== 'application/pdf') {
        this.message.set('Only PDF uploads are supported for PDF resources.');
        input.value = '';
        return;
      }

      // The resource library had no size check at all, so a large scan was
      // uploaded whole and then counted against the plan's storage.
      try {
        assertPdfWithinLimit(file);
      } catch (error: unknown) {
        this.message.set(error instanceof Error ? error.message : 'That PDF could not be used.');
        input.value = '';
        return;
      }

      this.form.file = file;
      this.form.fileName = file.name;
      return;
    }

    if (!file.type.startsWith('image/')) {
      this.message.set('Only image uploads are supported for image resources.');
      input.value = '';
      return;
    }

    void compressImageFile(file)
      .then((result) => {
        this.form.file = result.file;
        this.form.fileName = result.file.name;
        this.form.type = 'Image';
        this.message.set('');
      })
      .catch((error: unknown) => {
        input.value = '';
        this.message.set(error instanceof Error ? error.message : 'That image could not be used.');
      });
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
    this.isLoading.set(true);
    let outstanding = 2;
    const settle = () => {
      outstanding -= 1;
      if (outstanding === 0) {
        this.isLoading.set(false);
      }
    };

    this.referencesApi.getCategories().subscribe({
      next: (response) => {
        this.categories.set(response.categories);
        settle();
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Categories could not be loaded.'));
        settle();
      }
    });
    this.referencesApi.getResources().subscribe({
      next: (response) => {
        const views = response.resources.map((reference) => this.toView(reference));
        this.references.set(views);
        this.referenceUsage.set(response.usage);
        this.selectedReferenceId.set(views[0]?.id || 0);
        settle();
      },
      error: (error: unknown) => {
        this.message.set(formatApiError(error, 'Resources could not be loaded.'));
        settle();
      }
    });
  }

  private loadCategoriesOnly(): void {
    this.referencesApi.getCategories().subscribe({
      next: (response) => this.categories.set(response.categories)
    });
  }

  private toView(reference: ProfessionalResourceRecord): ProfessionalReferenceView {
    return {
      id: reference.id,
      title: reference.title,
      category: reference.category_name,
      categoryId: reference.category,
      subcategory: reference.subcategory,
      type: TYPE_LABELS[reference.resource_type],
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
      return 'Add a title for this resource.';
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

    if (this.form.type === 'PDF' && !this.form.link.trim() && !this.form.file && !this.form.fileName) {
      return 'Upload a PDF or paste a PDF URL.';
    }

    if (this.form.type === 'Text' && !this.form.description.trim()) {
      return 'Add text for this resource.';
    }

    if (this.form.type === 'Image' && !this.form.file && !this.form.fileName) {
      return 'Upload an image.';
    }

    return '';
  }

  private emptyForm(type: ReferenceTypeLabel = 'Video Link', providedCategory?: ResourceCategoryRecord, subcategory = ''): ReferenceForm {
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
