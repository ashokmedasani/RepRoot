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
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { addOutline, trashOutline, createOutline, openOutline, chevronDownOutline, chevronUpOutline } from 'ionicons/icons';

import {
  ReferenceCategoryRecord,
  ReferencePayload,
  ReferenceType,
  ReferencesApiService,
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';

type ReferencesTab = 'library' | 'categories';

/** Reference library: categories with subcategories, references (video/PDF/image/text), plan limits. */
@Component({
  selector: 'app-trainer-references',
  standalone: true,
  imports: [
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
    IonRefresherContent,
    IonSegment,
    IonSegmentButton,
    IonLabel
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage" /></ion-buttons>
        <ion-title>References</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <div class="kpi-grid">
          <div class="kpi-tile">
            <span>References used</span>
            <strong>{{ usage.used }}{{ usage.limit !== null ? ' / ' + usage.limit : '' }}</strong>
          </div>
          <div class="kpi-tile"><span>Categories</span><strong>{{ categories.length }}</strong></div>
        </div>

        @if (atLimit) {
          <p class="hint-note" style="margin-top:.6rem">Version 1 allows up to {{ usage.limit }} references. Delete unused ones to add more.</p>
        }
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        <ion-segment [(ngModel)]="tab" mode="md" style="margin-top:.75rem">
          <ion-segment-button value="library"><ion-label>Library</ion-label></ion-segment-button>
          <ion-segment-button value="categories"><ion-label>Categories</ion-label></ion-segment-button>
        </ion-segment>

        <!-- ============ LIBRARY ============ -->
        @if (tab === 'library') {
          @if (referenceFormOpen) {
            <div class="card">
              <h3>{{ editingReferenceId ? 'Edit reference' : 'New reference' }}</h3>
              <div class="form-grid">
                <label><span>Title</span><input [(ngModel)]="referenceDraft.title" /></label>
                <div class="form-two">
                  <label>
                    <span>Category</span>
                    <select [(ngModel)]="referenceDraft.category">
                      <option [ngValue]="0" disabled>Select</option>
                      @for (category of categories; track category.id) {
                        <option [ngValue]="category.id">{{ category.name }}</option>
                      }
                    </select>
                  </label>
                  <label>
                    <span>Subcategory</span>
                    <select [(ngModel)]="referenceDraft.subcategory">
                      <option value="">None</option>
                      @for (sub of subcategoriesFor(referenceDraft.category); track sub) {
                        <option [value]="sub">{{ sub }}</option>
                      }
                    </select>
                  </label>
                </div>
                <label>
                  <span>Type</span>
                  <select [(ngModel)]="referenceDraft.reference_type">
                    <option value="video_link">Video link</option>
                    <option value="text_note">Text note</option>
                    <option value="pdf">PDF file</option>
                    <option value="image">Image file</option>
                  </select>
                </label>
                @if (referenceDraft.reference_type === 'video_link') {
                  <label><span>Link</span><input [(ngModel)]="referenceDraft.link" inputmode="url" placeholder="https://…" /></label>
                }
                @if (referenceDraft.reference_type === 'pdf' || referenceDraft.reference_type === 'image') {
                  <label>
                    <span>File</span>
                    <input type="file" [accept]="referenceDraft.reference_type === 'pdf' ? 'application/pdf' : 'image/*'" (change)="onFile($event)" />
                  </label>
                }
                <label><span>Description / text</span><textarea [(ngModel)]="referenceDraft.description"></textarea></label>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="saveReference()" [disabled]="isSavingReference || !referenceDraft.title.trim() || !referenceDraft.category">
                  {{ isSavingReference ? 'Saving…' : 'Save reference' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="referenceFormOpen = false">Cancel</ion-button>
              </div>
            </div>
          } @else {
            <ion-button expand="block" fill="outline" (click)="startCreateReference()" [disabled]="atLimit || !categories.length">
              <ion-icon slot="start" name="add-outline" />Add reference
            </ion-button>
            @if (!categories.length) {
              <p class="hint-note">Create a category first.</p>
            }
          }

          <div class="row-list" style="margin-top:.75rem">
            @for (reference of references; track reference.id) {
              <div class="card" style="margin-top:0">
                <div style="display:flex;justify-content:space-between;gap:.5rem;align-items:flex-start">
                  <div style="min-width:0">
                    <h3 style="margin:0">{{ reference.title }}</h3>
                    <p class="sub" style="margin:.15rem 0 0">
                      {{ reference.category_name }}{{ reference.subcategory ? ' › ' + reference.subcategory : '' }} · {{ typeLabel(reference.reference_type) }}
                    </p>
                  </div>
                  <div style="display:flex;flex:0 0 auto">
                    @if (reference.link || reference.file_url) {
                      <ion-button size="small" fill="clear" (click)="open(reference)"><ion-icon slot="icon-only" name="open-outline" /></ion-button>
                    }
                    <ion-button size="small" fill="clear" (click)="startEditReference(reference)"><ion-icon slot="icon-only" name="create-outline" /></ion-button>
                    <ion-button size="small" fill="clear" color="danger" (click)="removeReference(reference)"><ion-icon slot="icon-only" name="trash-outline" /></ion-button>
                  </div>
                </div>
                @if (reference.description) {
                  <p style="margin:.5rem 0 0;font-size:.85rem;color:var(--app-text);white-space:pre-wrap">{{ reference.description }}</p>
                }
              </div>
            } @empty {
              <p class="empty-note">No references yet.</p>
            }
          </div>
        }

        <!-- ============ CATEGORIES ============ -->
        @if (tab === 'categories') {
          @if (categoryFormOpen) {
            <div class="card">
              <h3>{{ editingCategoryId ? 'Edit category' : 'New category' }}</h3>
              <div class="form-grid">
                <label><span>Name</span><input [(ngModel)]="categoryName" /></label>
                <label><span>Description</span><input [(ngModel)]="categoryDescription" /></label>
                <label><span>Subcategories (comma separated, max 5)</span><input [(ngModel)]="categorySubs" placeholder="e.g. Upper body, Lower body" /></label>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="saveCategory()" [disabled]="isSavingCategory || !categoryName.trim()">
                  {{ isSavingCategory ? 'Saving…' : 'Save category' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="categoryFormOpen = false">Cancel</ion-button>
              </div>
            </div>
          } @else {
            <ion-button expand="block" fill="outline" (click)="startCreateCategory()">
              <ion-icon slot="start" name="add-outline" />Create category
            </ion-button>
          }

          <div class="row-list" style="margin-top:.75rem">
            @for (category of categories; track category.id) {
              <div class="card" style="margin-top:0">
                <div style="display:flex;justify-content:space-between;align-items:center" (click)="expandedCategoryId = expandedCategoryId === category.id ? 0 : category.id">
                  <div>
                    <h3 style="margin:0">{{ category.name }}</h3>
                    <p class="sub" style="margin:.15rem 0 0">
                      {{ category.subcategories.length }} subcategories · {{ category.reference_count }} references
                    </p>
                  </div>
                  <ion-icon [name]="expandedCategoryId === category.id ? 'chevron-up-outline' : 'chevron-down-outline'" />
                </div>
                @if (expandedCategoryId === category.id) {
                  @if (category.description) {
                    <p style="margin:.5rem 0 0;font-size:.85rem;color:var(--app-muted)">{{ category.description }}</p>
                  }
                  @if (category.subcategories.length) {
                    <p style="margin:.4rem 0 0;font-size:.8rem;color:var(--app-text)">{{ category.subcategories.join(' · ') }}</p>
                  }
                  <div class="form-two" style="margin-top:.6rem">
                    <ion-button size="small" fill="outline" (click)="startEditCategory(category)">Edit</ion-button>
                    <ion-button size="small" color="danger" fill="outline" (click)="removeCategory(category)">Delete</ion-button>
                  </div>
                }
              </div>
            } @empty {
              <p class="empty-note">No categories yet.</p>
            }
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerReferencesPage implements OnInit {
  private readonly api = inject(ReferencesApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  tab: ReferencesTab = 'library';
  categories: ReferenceCategoryRecord[] = [];
  references: TrainerReferenceRecord[] = [];
  usage: { used: number; limit: number | null } = { used: 0, limit: null };
  message = '';
  expandedCategoryId = 0;

  referenceFormOpen = false;
  editingReferenceId = 0;
  isSavingReference = false;
  referenceDraft: ReferencePayload = this.emptyReference();
  pickedFile: File | null = null;

  categoryFormOpen = false;
  editingCategoryId = 0;
  isSavingCategory = false;
  categoryName = '';
  categoryDescription = '';
  categorySubs = '';

  constructor() {
    addIcons({ addOutline, trashOutline, createOutline, openOutline, chevronDownOutline, chevronUpOutline });
  }

  get atLimit(): boolean {
    return this.usage.limit !== null && this.usage.used >= this.usage.limit;
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  typeLabel(type: ReferenceType): string {
    switch (type) {
      case 'video_link':
        return 'Video';
      case 'pdf':
        return 'PDF';
      case 'image':
        return 'Image';
      default:
        return 'Note';
    }
  }

  subcategoriesFor(categoryId: number): string[] {
    return this.categories.find((category) => category.id === categoryId)?.subcategories || [];
  }

  open(reference: TrainerReferenceRecord): void {
    const url = reference.link || reference.file_url;

    if (url) {
      window.open(url, '_blank');
    }
  }

  onFile(event: Event): void {
    const input = event.target as HTMLInputElement;
    this.pickedFile = input.files?.[0] || null;
  }

  startCreateReference(): void {
    this.editingReferenceId = 0;
    this.referenceDraft = this.emptyReference();
    this.pickedFile = null;
    this.referenceFormOpen = true;
  }

  startEditReference(reference: TrainerReferenceRecord): void {
    this.editingReferenceId = reference.id;
    this.referenceDraft = {
      category: reference.category,
      subcategory: reference.subcategory,
      title: reference.title,
      reference_type: reference.reference_type,
      description: reference.description,
      link: reference.link,
      tags: reference.tags || []
    };
    this.pickedFile = null;
    this.referenceFormOpen = true;
  }

  saveReference(): void {
    this.isSavingReference = true;
    const payload: ReferencePayload = { ...this.referenceDraft, file: this.pickedFile };
    const request = this.editingReferenceId
      ? this.api.updateReference(this.editingReferenceId, payload)
      : this.api.createReference(payload);

    request.subscribe({
      next: () => {
        this.isSavingReference = false;
        this.referenceFormOpen = false;
        this.load();
        void this.toast('Reference saved.');
      },
      error: () => {
        this.isSavingReference = false;
        this.message = 'Could not save the reference.';
      }
    });
  }

  async removeReference(reference: TrainerReferenceRecord): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete "${reference.title}"?`,
      message: 'Clients assigned this reference lose access to it.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Delete',
          role: 'destructive',
          handler: () => {
            this.api.deleteReference(reference.id).subscribe({
              next: () => this.load(),
              error: () => (this.message = 'Could not delete the reference.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  startCreateCategory(): void {
    this.editingCategoryId = 0;
    this.categoryName = '';
    this.categoryDescription = '';
    this.categorySubs = '';
    this.categoryFormOpen = true;
  }

  startEditCategory(category: ReferenceCategoryRecord): void {
    this.editingCategoryId = category.id;
    this.categoryName = category.name;
    this.categoryDescription = category.description;
    this.categorySubs = category.subcategories.join(', ');
    this.categoryFormOpen = true;
  }

  saveCategory(): void {
    this.isSavingCategory = true;
    const subs = this.categorySubs
      .split(',')
      .map((sub) => sub.trim())
      .filter(Boolean)
      .slice(0, 5);
    const request = this.editingCategoryId
      ? this.api.updateCategory(this.editingCategoryId, this.categoryName.trim(), this.categoryDescription.trim(), subs)
      : this.api.createCategory(this.categoryName.trim(), this.categoryDescription.trim(), subs);

    request.subscribe({
      next: () => {
        this.isSavingCategory = false;
        this.categoryFormOpen = false;
        this.load();
        void this.toast('Category saved.');
      },
      error: () => {
        this.isSavingCategory = false;
        this.message = 'Could not save the category. Category limits may apply.';
      }
    });
  }

  async removeCategory(category: ReferenceCategoryRecord): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete ${category.name}?`,
      message: category.reference_count
        ? `${category.reference_count} reference(s) in this category will also be removed.`
        : 'This category will be removed.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Delete',
          role: 'destructive',
          handler: () => {
            this.api.deleteCategory(category.id).subscribe({
              next: () => this.load(),
              error: () => (this.message = 'Could not delete the category.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  private emptyReference(): ReferencePayload {
    return {
      category: 0,
      subcategory: '',
      title: '',
      reference_type: 'video_link',
      description: '',
      link: '',
      tags: []
    };
  }

  private load(done?: () => void): void {
    this.api.getCategories().subscribe({
      next: (response) => (this.categories = response.categories),
      error: () => (this.categories = [])
    });
    this.api.getReferences().subscribe({
      next: (response) => {
        this.references = response.references;
        this.usage = response.usage;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load references.';
        done?.();
      }
    });
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
