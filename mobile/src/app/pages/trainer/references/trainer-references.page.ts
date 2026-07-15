import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AlertController, ToastController } from '@ionic/angular';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  addOutline,
  chevronDownOutline,
  chevronForwardOutline,
  closeOutline,
  copyOutline,
  createOutline,
  openOutline,
  searchOutline,
  trashOutline
} from 'ionicons/icons';

import {
  ReferenceCategoryRecord,
  ReferencePayload,
  ReferenceType,
  ReferencesApiService,
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';

type CategoryEditorMode = 'create' | 'edit' | 'subcategory';

@Component({
  selector: 'app-trainer-references',
  standalone: true,
  imports: [
    DatePipe,
    FormsModule,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonBackButton,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage" /></ion-buttons>
        <ion-title>References / Resources</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)"><ion-refresher-content /></ion-refresher>
      <div class="page-pad references-page">
        <div class="library-head">
          <div>
            <p class="eyebrow">Trainer library</p>
            <h1>Reusable resources</h1>
            <p>Exercises, plans, documents, images, links, and notes.</p>
          </div>
          <span class="usage-pill">{{ usage.used }} / {{ usage.limit === null ? '∞' : usage.limit }}</span>
        </div>

        @if (message) { <p class="library-message">{{ message }}</p> }
        @if (atLimit) { <p class="limit-message">Reference limit reached. Delete an unused item to add another.</p> }

        <div class="search-actions">
          <label class="search-box">
            <ion-icon name="search-outline" />
            <input type="search" [(ngModel)]="query" placeholder="Search references…" />
          </label>
          <ion-button size="small" (click)="openCategoryEditor('create')"><ion-icon slot="start" name="add-outline" />Category</ion-button>
        </div>

        <div class="category-list">
          @for (category of visibleCategories; track category.id) {
            <section class="cat-accordion">
              <div class="cat-header">
                <button type="button" class="cat-expand" (click)="toggleCategory(category.id)" [attr.aria-expanded]="isCategoryOpen(category.id)">
                  <ion-icon [name]="isCategoryOpen(category.id) ? 'chevron-down-outline' : 'chevron-forward-outline'" />
                  <span>
                    <strong>{{ category.name }}</strong>
                    @if (category.description) { <small>{{ category.description }}</small> }
                  </span>
                </button>
                <div class="category-metrics">
                  <span>{{ category.subcategories.length }} subcategories</span>
                  <span>{{ referencesForCategory(category.name).length }} references</span>
                </div>
              </div>

              @if (isCategoryOpen(category.id)) {
                <div class="cat-body">
                  <div class="category-actions">
                    <ion-button size="small" fill="outline" (click)="openCategoryEditor('subcategory', category)"><ion-icon slot="start" name="add-outline" />Subcategory</ion-button>
                    <ion-button size="small" fill="clear" (click)="openCategoryEditor('edit', category)">Edit</ion-button>
                    <ion-button size="small" fill="clear" color="danger" (click)="removeCategory(category)">Delete</ion-button>
                  </div>

                  @for (subcategory of subcategoriesOf(category); track subcategory) {
                    <section class="subcat-block">
                      <div class="subcat-header">
                        <div>
                          <h2>{{ subcategory || 'General' }}</h2>
                          <small>{{ referencesFor(category.name, subcategory).length }} references</small>
                        </div>
                        <div class="subcat-actions">
                          @if (subcategory) {
                            <ion-button size="small" fill="clear" color="danger" aria-label="Delete subcategory" (click)="removeSubcategory(category, subcategory)">
                              <ion-icon slot="icon-only" name="trash-outline" />
                            </ion-button>
                          }
                          <ion-button size="small" [disabled]="atLimit" (click)="startCreateReference(category, subcategory)"><ion-icon slot="start" name="add-outline" />Reference</ion-button>
                        </div>
                      </div>

                      <div class="reference-list">
                        @for (reference of referencesFor(category.name, subcategory); track reference.id) {
                          <article class="ref-item" [class.open]="expandedReferenceId === reference.id">
                            <button type="button" class="ref-header" (click)="toggleReference(reference.id)">
                              <ion-icon [name]="expandedReferenceId === reference.id ? 'chevron-down-outline' : 'chevron-forward-outline'" />
                              <span class="ref-title">{{ reference.title }}</span>
                              <span class="type-pill">{{ typeLabel(reference.reference_type) }}</span>
                            </button>

                            @if (expandedReferenceId === reference.id) {
                              <div class="ref-detail">
                                @if (reference.reference_type === 'image' && reference.file_url) {
                                  <img class="reference-image" [src]="reference.file_url" [alt]="reference.title" />
                                } @else {
                                  <div class="preview-box">
                                    <span>{{ resourceInitial(reference) }}</span>
                                    <strong>{{ reference.file_name || reference.link || (reference.reference_type === 'text_note' ? 'Text note' : 'Resource') }}</strong>
                                  </div>
                                }

                                @if (reference.description) { <p class="reference-description">{{ reference.description }}</p> }
                                <dl class="ref-meta">
                                  <div><dt>Subcategory</dt><dd>{{ reference.subcategory || 'General' }}</dd></div>
                                  <div><dt>Created</dt><dd>{{ reference.created_at | date: 'mediumDate' }}</dd></div>
                                </dl>
                                @if (reference.tags.length) {
                                  <div class="ref-tags">@for (tag of reference.tags; track tag) { <span>{{ tag }}</span> }</div>
                                }
                                <div class="ref-actions">
                                  @if (reference.link || reference.file_url) {
                                    <ion-button size="small" (click)="open(reference)"><ion-icon slot="start" name="open-outline" />Open</ion-button>
                                  }
                                  <ion-button size="small" fill="outline" (click)="startEditReference(reference)"><ion-icon slot="start" name="create-outline" />Edit</ion-button>
                                  <ion-button size="small" fill="outline" [disabled]="atLimit" (click)="duplicateReference(reference)"><ion-icon slot="start" name="copy-outline" />Duplicate</ion-button>
                                  <ion-button size="small" fill="clear" color="danger" (click)="removeReference(reference)">Delete</ion-button>
                                </div>
                              </div>
                            }
                          </article>
                        } @empty {
                          <p class="empty-subcategory">No references in this subcategory yet.</p>
                        }
                      </div>
                    </section>
                  } @empty {
                    <div class="empty-category">
                      <p>Add a subcategory before adding references.</p>
                      <ion-button size="small" fill="outline" (click)="openCategoryEditor('subcategory', category)">Add subcategory</ion-button>
                    </div>
                  }
                </div>
              }
            </section>
          } @empty {
            <div class="empty-library">
              <strong>{{ query.trim() ? 'No matching references' : 'No categories yet' }}</strong>
              <p>{{ query.trim() ? 'Try another search.' : 'Create a category to start your resource library.' }}</p>
            </div>
          }
        </div>
        <div class="bottom-space"></div>
      </div>
    </ion-content>

    @if (referenceFormOpen) {
      <div class="editor-backdrop">
        <form class="editor-panel" (ngSubmit)="saveReference()">
          <div class="editor-header">
            <div><p class="eyebrow">Reference</p><h2>{{ editingReferenceId ? 'Edit reference' : 'Add reference' }}</h2></div>
            <button type="button" class="close-button" aria-label="Close" (click)="referenceFormOpen = false"><ion-icon name="close-outline" /></button>
          </div>
          <div class="form-grid">
            <label><span>Title</span><input name="referenceTitle" [(ngModel)]="referenceDraft.title" /></label>
            <label><span>Type</span>
              <select name="referenceType" [(ngModel)]="referenceDraft.reference_type">
                <option value="video_link">Video link</option><option value="pdf">PDF</option><option value="text_note">Text</option><option value="image">Image</option>
              </select>
            </label>
            <label><span>Category</span>
              <select name="referenceCategory" [(ngModel)]="referenceDraft.category" (ngModelChange)="categoryChanged()">
                @for (category of categories; track category.id) { <option [ngValue]="category.id">{{ category.name }}</option> }
              </select>
            </label>
            <label><span>Subcategory</span>
              <select name="referenceSubcategory" [(ngModel)]="referenceDraft.subcategory">
                @for (sub of subcategoriesFor(referenceDraft.category); track sub) { <option [value]="sub">{{ sub }}</option> }
              </select>
            </label>
            @if (referenceDraft.reference_type === 'video_link' || referenceDraft.reference_type === 'pdf') {
              <label><span>{{ referenceDraft.reference_type === 'video_link' ? 'Video URL' : 'PDF URL' }}</span><input name="referenceLink" inputmode="url" [(ngModel)]="referenceDraft.link" placeholder="https://" /></label>
            }
            @if (referenceDraft.reference_type === 'image' || referenceDraft.reference_type === 'pdf') {
              <label><span>{{ referenceDraft.reference_type === 'image' ? 'Image upload' : 'PDF upload (optional)' }}</span><input class="file-input" type="file" [accept]="referenceDraft.reference_type === 'image' ? 'image/*' : 'application/pdf'" (change)="onFile($event)" /></label>
            }
            <label><span>{{ referenceDraft.reference_type === 'text_note' ? 'Text' : 'Description' }}</span><textarea name="referenceDescription" rows="4" [(ngModel)]="referenceDraft.description"></textarea></label>
            <label><span>Tags</span><input name="referenceTags" [(ngModel)]="tagsText" placeholder="strength, beginner" /></label>
          </div>
          <div class="editor-actions">
            <ion-button type="button" fill="clear" (click)="referenceFormOpen = false">Cancel</ion-button>
            <ion-button type="submit" [disabled]="isSavingReference">{{ isSavingReference ? 'Saving…' : 'Save reference' }}</ion-button>
          </div>
        </form>
      </div>
    }

    @if (categoryFormOpen) {
      <div class="editor-backdrop">
        <form class="editor-panel" (ngSubmit)="saveCategory()">
          <div class="editor-header">
            <div><p class="eyebrow">Organization</p><h2>{{ categoryEditorTitle }}</h2></div>
            <button type="button" class="close-button" aria-label="Close" (click)="categoryFormOpen = false"><ion-icon name="close-outline" /></button>
          </div>
          <div class="form-grid">
            <label><span>Category name</span><input name="categoryName" [(ngModel)]="categoryName" [readonly]="categoryEditorMode === 'subcategory'" /></label>
            <label><span>Description</span><textarea name="categoryDescription" rows="3" [(ngModel)]="categoryDescription" [readonly]="categoryEditorMode === 'subcategory'"></textarea></label>
            @if (categoryEditorMode !== 'create') {
              <label><span>{{ categoryEditorMode === 'subcategory' ? 'New subcategories' : 'Subcategories' }}</span><textarea name="categorySubs" rows="4" [(ngModel)]="categorySubs" placeholder="One per line or comma separated"></textarea></label>
            }
          </div>
          <div class="editor-actions">
            <ion-button type="button" fill="clear" (click)="categoryFormOpen = false">Cancel</ion-button>
            <ion-button type="submit" [disabled]="isSavingCategory || !categoryName.trim()">{{ isSavingCategory ? 'Saving…' : 'Save category' }}</ion-button>
          </div>
        </form>
      </div>
    }
  `,
  styles: [`
    .references-page { max-width: 46rem; margin: 0 auto; }
    .library-head { display:flex; align-items:flex-start; justify-content:space-between; gap:1rem; margin:.2rem 0 1rem; }
    .library-head h1 { margin:.15rem 0 .25rem; color:var(--app-text); font-size:1.45rem; }
    .library-head > div > p:last-child { margin:0; color:var(--app-muted); font-size:.8rem; line-height:1.45; }
    .usage-pill { flex:0 0 auto; border-radius:var(--app-radius-md); padding:.45rem .65rem; background:var(--app-primary-soft); color:var(--app-primary-strong); font-size:.76rem; font-weight:800; }
    .library-message, .limit-message { border-radius:var(--app-radius-md); padding:.7rem .8rem; margin:.6rem 0; font-size:.8rem; font-weight:700; }
    .library-message { background:var(--app-primary-soft); color:var(--app-primary-strong); }
    .limit-message { background:color-mix(in srgb, var(--ion-color-danger) 10%, var(--app-surface)); color:var(--ion-color-danger); }
    .search-actions { display:grid; grid-template-columns:minmax(0,1fr) auto; gap:.6rem; align-items:center; margin-bottom:.8rem; }
    .search-box { display:flex; align-items:center; gap:.5rem; min-height:2.75rem; border:1px solid var(--app-border); border-radius:var(--app-radius-md); padding:0 .75rem; background:var(--app-surface); box-shadow:var(--app-shadow-sm); }
    .search-box ion-icon { color:var(--app-muted); }
    .search-box input { width:100%; border:0; outline:0; background:transparent; color:var(--app-text); font:inherit; font-size:.85rem; }
    .category-list { display:grid; gap:.7rem; }
    .cat-accordion { overflow:hidden; border:1px solid var(--app-border); border-radius:var(--app-radius-lg); background:var(--app-surface); box-shadow:var(--app-shadow-sm); }
    .cat-header { padding:.85rem; }
    .cat-expand { display:flex; width:100%; align-items:center; gap:.55rem; border:0; padding:0; background:none; color:var(--app-text); text-align:left; }
    .cat-expand ion-icon { flex:0 0 auto; color:var(--app-primary); }
    .cat-expand span { min-width:0; }
    .cat-expand strong, .cat-expand small { display:block; }
    .cat-expand strong { font-size:.95rem; }
    .cat-expand small { margin-top:.15rem; color:var(--app-muted); font-size:.72rem; line-height:1.4; }
    .category-metrics { display:flex; flex-wrap:wrap; gap:.35rem; margin:.55rem 0 0 1.55rem; }
    .category-metrics span { border-radius:var(--app-radius-sm); padding:.2rem .45rem; background:var(--app-surface-soft); color:var(--app-muted); font-size:.66rem; font-weight:750; }
    .cat-body { display:grid; gap:.75rem; border-top:1px solid var(--app-border); padding:.75rem; background:color-mix(in srgb, var(--app-surface-soft) 55%, var(--app-surface)); }
    .category-actions, .subcat-actions, .ref-actions, .editor-actions { display:flex; flex-wrap:wrap; gap:.4rem; }
    .subcat-block { overflow:hidden; border:1px solid var(--app-border); border-radius:var(--app-radius-md); background:var(--app-surface); }
    .subcat-header { display:flex; align-items:center; justify-content:space-between; gap:.6rem; padding:.65rem .7rem; }
    .subcat-header h2 { margin:0; color:var(--app-text); font-size:.88rem; }
    .subcat-header small { color:var(--app-muted); font-size:.66rem; }
    .reference-list { border-top:1px solid var(--app-border); }
    .ref-item + .ref-item { border-top:1px solid var(--app-border); }
    .ref-header { display:grid; grid-template-columns:auto minmax(0,1fr) auto; width:100%; align-items:center; gap:.45rem; border:0; padding:.65rem .7rem; background:none; color:var(--app-text); text-align:left; }
    .ref-header ion-icon { color:var(--app-muted); }
    .ref-title { overflow:hidden; font-size:.8rem; font-weight:750; text-overflow:ellipsis; white-space:nowrap; }
    .type-pill, .ref-tags span { border-radius:var(--app-radius-sm); padding:.2rem .45rem; background:var(--app-primary-soft); color:var(--app-primary-strong); font-size:.62rem; font-weight:800; }
    .ref-detail { display:grid; gap:.65rem; border-top:1px solid var(--app-border); padding:.7rem; }
    .reference-image { width:100%; max-height:13rem; border-radius:var(--app-radius-md); object-fit:cover; }
    .preview-box { display:grid; min-height:6.5rem; place-items:center; gap:.4rem; border-radius:var(--app-radius-md); padding:.8rem; background:linear-gradient(145deg, #14213d, #22375f); color:#fff; text-align:center; }
    .preview-box span { display:grid; width:2.7rem; height:2.7rem; place-items:center; border-radius:var(--app-radius-md); background:var(--app-primary); font-size:1.15rem; font-weight:800; }
    .preview-box strong { max-width:100%; overflow-wrap:anywhere; font-size:.72rem; }
    .reference-description { margin:0; color:var(--app-text); font-size:.78rem; line-height:1.5; white-space:pre-wrap; }
    .ref-meta { display:grid; grid-template-columns:1fr 1fr; gap:.5rem; margin:0; }
    .ref-meta div { border-radius:var(--app-radius-sm); padding:.5rem; background:var(--app-surface-soft); }
    .ref-meta dt { color:var(--app-muted); font-size:.62rem; font-weight:750; }
    .ref-meta dd { margin:.12rem 0 0; color:var(--app-text); font-size:.72rem; font-weight:750; }
    .ref-tags { display:flex; flex-wrap:wrap; gap:.3rem; }
    .empty-subcategory, .empty-category, .empty-library { margin:0; padding:.8rem; color:var(--app-muted); font-size:.76rem; text-align:center; }
    .empty-category, .empty-library { display:grid; justify-items:center; gap:.5rem; border:1px dashed var(--app-border); border-radius:var(--app-radius-md); background:var(--app-surface); }
    .empty-library { padding:1.5rem; }
    .empty-library p { margin:0; }
    .editor-backdrop { position:fixed; inset:0; z-index:100; display:grid; align-items:end; background:rgba(14,22,36,.55); }
    .editor-panel { width:100%; max-height:88vh; overflow:auto; border-radius:var(--app-radius-xl) var(--app-radius-xl) 0 0; padding:1rem 1rem calc(1rem + env(safe-area-inset-bottom)); background:var(--app-bg); box-shadow:var(--app-shadow-md); }
    .editor-header { display:flex; align-items:flex-start; justify-content:space-between; gap:1rem; margin-bottom:.8rem; }
    .editor-header h2 { margin:.15rem 0 0; color:var(--app-text); font-size:1.2rem; }
    .close-button { display:grid; width:2.35rem; height:2.35rem; place-items:center; border:1px solid var(--app-border); border-radius:var(--app-radius-sm); background:var(--app-surface); color:var(--app-text); }
    .file-input { padding:.55rem !important; }
    .editor-actions { justify-content:flex-end; margin-top:.8rem; }
  `]
})
export class TrainerReferencesPage implements OnInit {
  private readonly api = inject(ReferencesApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  categories: ReferenceCategoryRecord[] = [];
  references: TrainerReferenceRecord[] = [];
  usage: { used: number; limit: number | null } = { used: 0, limit: null };
  query = '';
  message = '';
  expandedCategoryId = 0;
  expandedReferenceId = 0;

  referenceFormOpen = false;
  editingReferenceId = 0;
  isSavingReference = false;
  referenceDraft: ReferencePayload = this.emptyReference();
  pickedFile: File | null = null;
  tagsText = '';

  categoryFormOpen = false;
  categoryEditorMode: CategoryEditorMode = 'create';
  editingCategoryId = 0;
  isSavingCategory = false;
  categoryName = '';
  categoryDescription = '';
  categorySubs = '';

  constructor() {
    addIcons({ addOutline, chevronDownOutline, chevronForwardOutline, closeOutline, copyOutline, createOutline, openOutline, searchOutline, trashOutline });
  }

  get atLimit(): boolean {
    return this.usage.limit !== null && this.usage.used >= this.usage.limit;
  }

  get visibleCategories(): ReferenceCategoryRecord[] {
    const term = this.query.trim().toLowerCase();
    if (!term) return this.categories;
    return this.categories.filter((category) =>
      [category.name, category.description, ...this.referencesForCategory(category.name).flatMap((reference) => [reference.title, reference.subcategory, reference.description, reference.tags.join(' ')])]
        .join(' ').toLowerCase().includes(term)
    );
  }

  get categoryEditorTitle(): string {
    return this.categoryEditorMode === 'create' ? 'Create category' : this.categoryEditorMode === 'edit' ? 'Edit category' : 'Add subcategory';
  }

  ngOnInit(): void { this.load(); }

  refresh(event: CustomEvent): void { this.load(() => (event.target as HTMLIonRefresherElement).complete()); }

  toggleCategory(id: number): void {
    this.expandedCategoryId = this.expandedCategoryId === id ? 0 : id;
    this.expandedReferenceId = 0;
  }

  isCategoryOpen(id: number): boolean { return this.expandedCategoryId === id || Boolean(this.query.trim()); }
  toggleReference(id: number): void { this.expandedReferenceId = this.expandedReferenceId === id ? 0 : id; }
  referencesForCategory(name: string): TrainerReferenceRecord[] { return this.references.filter((reference) => reference.category_name === name); }
  referencesFor(name: string, subcategory: string): TrainerReferenceRecord[] { return this.referencesForCategory(name).filter((reference) => reference.subcategory === subcategory); }

  subcategoriesOf(category: ReferenceCategoryRecord): string[] {
    const values = [...category.subcategories];
    if (this.referencesFor(category.name, '').length) values.push('');
    return values;
  }

  subcategoriesFor(categoryId: number): string[] { return this.categories.find((category) => category.id === categoryId)?.subcategories || []; }

  typeLabel(type: ReferenceType): string {
    return ({ video_link: 'Video', pdf: 'PDF', image: 'Image', text_note: 'Text' } as Record<ReferenceType, string>)[type];
  }

  resourceInitial(reference: TrainerReferenceRecord): string { return reference.title.trim().charAt(0).toUpperCase() || 'R'; }

  open(reference: TrainerReferenceRecord): void {
    const url = reference.file_url || reference.link;
    if (url) window.open(url, '_blank', 'noopener,noreferrer');
  }

  openCategoryEditor(mode: CategoryEditorMode, category?: ReferenceCategoryRecord): void {
    this.categoryEditorMode = mode;
    this.editingCategoryId = category?.id || 0;
    this.categoryName = category?.name || '';
    this.categoryDescription = category?.description || '';
    this.categorySubs = mode === 'edit' ? (category?.subcategories || []).join('\n') : '';
    this.categoryFormOpen = true;
  }

  saveCategory(): void {
    const current = this.categories.find((category) => category.id === this.editingCategoryId);
    const entered = this.parseSubcategories(this.categorySubs);
    const subcategories = this.categoryEditorMode === 'subcategory' && current ? Array.from(new Set([...current.subcategories, ...entered])) : entered;
    const request = current
      ? this.api.updateCategory(current.id, this.categoryName.trim(), this.categoryDescription.trim(), subcategories)
      : this.api.createCategory(this.categoryName.trim(), this.categoryDescription.trim(), []);

    this.isSavingCategory = true;
    request.subscribe({
      next: (response) => {
        this.isSavingCategory = false;
        this.categoryFormOpen = false;
        this.expandedCategoryId = response.category.id;
        this.load();
        void this.toast(response.message || 'Category saved.');
      },
      error: () => { this.isSavingCategory = false; this.message = 'Category could not be saved.'; }
    });
  }

  async removeCategory(category: ReferenceCategoryRecord): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete ${category.name}?`,
      message: category.reference_count ? 'Move or delete the references in this category first.' : 'This category will be removed.',
      buttons: [{ text: 'Cancel', role: 'cancel' }, { text: 'Delete', role: 'destructive', handler: () => this.api.deleteCategory(category.id).subscribe({ next: () => this.load(), error: () => (this.message = 'Category could not be deleted.') }) }]
    });
    await alert.present();
  }

  async removeSubcategory(category: ReferenceCategoryRecord, subcategory: string): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete ${subcategory}?`,
      message: 'Move or delete references in this subcategory first.',
      buttons: [{ text: 'Cancel', role: 'cancel' }, { text: 'Delete', role: 'destructive', handler: () => this.api.updateCategory(category.id, category.name, category.description, category.subcategories.filter((item) => item !== subcategory)).subscribe({ next: () => this.load(), error: () => (this.message = 'Subcategory could not be deleted.') }) }]
    });
    await alert.present();
  }

  startCreateReference(category: ReferenceCategoryRecord, subcategory: string): void {
    if (this.atLimit) return;
    this.editingReferenceId = 0;
    this.referenceDraft = { ...this.emptyReference(), category: category.id, subcategory };
    this.tagsText = '';
    this.pickedFile = null;
    this.referenceFormOpen = true;
  }

  startEditReference(reference: TrainerReferenceRecord): void {
    this.editingReferenceId = reference.id;
    this.referenceDraft = { category: reference.category, subcategory: reference.subcategory, title: reference.title, reference_type: reference.reference_type, description: reference.description, link: reference.link, tags: reference.tags || [] };
    this.tagsText = (reference.tags || []).join(', ');
    this.pickedFile = null;
    this.referenceFormOpen = true;
  }

  categoryChanged(): void { this.referenceDraft.subcategory = this.subcategoriesFor(this.referenceDraft.category)[0] || ''; }
  onFile(event: Event): void { this.pickedFile = (event.target as HTMLInputElement).files?.[0] || null; }

  saveReference(): void {
    const validation = this.validateReference();
    if (validation) { this.message = validation; return; }
    const payload: ReferencePayload = { ...this.referenceDraft, title: this.referenceDraft.title.trim(), description: this.referenceDraft.description.trim(), link: this.referenceDraft.link.trim(), tags: this.parseTags(), file: this.pickedFile };
    const request = this.editingReferenceId ? this.api.updateReference(this.editingReferenceId, payload) : this.api.createReference(payload);
    this.isSavingReference = true;
    request.subscribe({
      next: (response) => { this.isSavingReference = false; this.referenceFormOpen = false; this.expandedReferenceId = response.reference.id; this.load(); void this.toast(response.message || 'Reference saved.'); },
      error: () => { this.isSavingReference = false; this.message = 'Reference could not be saved.'; }
    });
  }

  duplicateReference(reference: TrainerReferenceRecord): void {
    if (this.atLimit) return;
    this.api.createReference({ category: reference.category, subcategory: reference.subcategory, title: `${reference.title} Copy`, reference_type: reference.reference_type, description: reference.description, link: reference.link || reference.file_url, tags: reference.tags || [] }).subscribe({
      next: (response) => { this.expandedReferenceId = response.reference.id; this.load(); void this.toast('Reference duplicated.'); },
      error: () => (this.message = 'Reference could not be duplicated.')
    });
  }

  async removeReference(reference: TrainerReferenceRecord): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete “${reference.title}”?`,
      message: 'This removes the reference from the trainer library.',
      buttons: [{ text: 'Cancel', role: 'cancel' }, { text: 'Delete', role: 'destructive', handler: () => this.api.deleteReference(reference.id).subscribe({ next: () => this.load(), error: () => (this.message = 'Reference could not be deleted.') }) }]
    });
    await alert.present();
  }

  private validateReference(): string {
    if (!this.referenceDraft.title.trim()) return 'Add a title for the reference.';
    if (!this.referenceDraft.category) return 'Choose a category.';
    if (this.referenceDraft.reference_type === 'video_link' && !this.referenceDraft.link.trim()) return 'Add a video URL.';
    if (this.referenceDraft.reference_type === 'pdf' && !this.referenceDraft.link.trim() && !this.pickedFile) return 'Add a PDF URL or upload a PDF.';
    if (this.referenceDraft.reference_type === 'image' && !this.pickedFile && !this.editingReferenceId) return 'Upload an image.';
    if (this.referenceDraft.reference_type === 'text_note' && !this.referenceDraft.description.trim()) return 'Add text for this reference.';
    return '';
  }

  private parseTags(): string[] { return this.tagsText.split(',').map((tag) => tag.trim()).filter(Boolean); }
  private parseSubcategories(value: string): string[] { return Array.from(new Set(value.split(/\r?\n|,/).map((item) => item.trim()).filter(Boolean))).slice(0, 5); }
  private emptyReference(): ReferencePayload { return { category: 0, subcategory: '', title: '', reference_type: 'video_link', description: '', link: '', tags: [] }; }

  private load(done?: () => void): void {
    this.api.getCategories().subscribe({ next: (response) => (this.categories = response.categories), error: () => (this.categories = []) });
    this.api.getReferences().subscribe({
      next: (response) => { this.references = response.references; this.usage = response.usage; this.message = ''; done?.(); },
      error: () => { this.message = 'Could not load references.'; done?.(); }
    });
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
