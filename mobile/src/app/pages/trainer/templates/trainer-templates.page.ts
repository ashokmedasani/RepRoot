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
import { addOutline, trashOutline, createOutline } from 'ionicons/icons';

import {
  StandardTemplateRecord,
  TemplateField,
  TemplatePayload,
  TemplatesApiService,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';

/** Tracking template library: create/edit with a field builder, adopt standards, delete. */
@Component({
  selector: 'app-trainer-templates',
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
    IonRefresherContent
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage" /></ion-buttons>
        <ion-title>Templates</ion-title>
        <ion-buttons slot="end">
          <ion-button (click)="startCreate()" aria-label="New template"><ion-icon slot="icon-only" name="add-outline" /></ion-button>
        </ion-buttons>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <div class="kpi-grid">
          <div class="kpi-tile"><span>Templates used</span><strong>{{ templates.length }} / {{ maxTemplates || '—' }}</strong></div>
          <div class="kpi-tile"><span>Assigned clients</span><strong>{{ assignedTotal }}</strong></div>
        </div>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (editorOpen) {
          <div class="card">
            <h3>{{ editingId ? 'Edit template' : 'New template' }}</h3>
            <div class="form-grid">
              <label><span>Name</span><input [(ngModel)]="draft.name" placeholder="e.g. Daily Nutrition Log" /></label>
              <label><span>Purpose</span><input [(ngModel)]="draft.purpose" placeholder="What does this track?" /></label>
              <div class="form-two">
                <label>
                  <span>Cadence</span>
                  <select [(ngModel)]="draft.cadence">
                    <option value="daily">Daily</option>
                    <option value="weekly">Weekly</option>
                    <option value="monthly">Monthly</option>
                  </select>
                </label>
                <label><span>Accent color</span><input type="color" [(ngModel)]="draft.accent" style="height:2.6rem;padding:.2rem" /></label>
              </div>
            </div>

            <p class="hint-note" style="margin-top:.6rem">Fields</p>
            @for (field of draft.custom_fields; track $index) {
              <div style="border:1px dashed var(--app-border);border-radius:.7rem;padding:.7rem;margin-top:.5rem">
                <div class="form-two">
                  <label><span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Label</span><input [(ngModel)]="field.label" placeholder="e.g. Weight (kg)" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)" /></label>
                  <label><span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Type</span>
                    <select [(ngModel)]="field.field_type" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)">
                      <option value="number">Number</option>
                      <option value="short_text">Short text</option>
                      <option value="long_text">Long text</option>
                      <option value="yes_no">Yes / No</option>
                      <option value="dropdown">Dropdown</option>
                      <option value="rating">Rating</option>
                    </select>
                  </label>
                </div>
                @if (field.field_type === 'dropdown') {
                  <label style="display:block;margin-top:.4rem">
                    <span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Options (comma separated)</span>
                    <input [ngModel]="(field.options || []).join(', ')" (ngModelChange)="setOptions(field, $event)" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)" />
                  </label>
                }
                @if (field.field_type === 'rating') {
                  <label style="display:block;margin-top:.4rem">
                    <span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Scale (2–10)</span>
                    <input type="number" min="2" max="10" [(ngModel)]="field.scale" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)" />
                  </label>
                }
                <div style="text-align:right;margin-top:.3rem">
                  <ion-button size="small" fill="clear" color="danger" (click)="draft.custom_fields.splice($index, 1)">
                    <ion-icon slot="icon-only" name="trash-outline" />
                  </ion-button>
                </div>
              </div>
            }
            <ion-button size="small" fill="outline" style="margin-top:.6rem" (click)="addField()">
              <ion-icon slot="start" name="add-outline" />Add field
            </ion-button>
            <div class="form-two" style="margin-top:.8rem">
              <ion-button size="small" (click)="save()" [disabled]="isSaving || !draft.name.trim() || !draft.custom_fields.length">
                {{ isSaving ? 'Saving…' : 'Save template' }}
              </ion-button>
              <ion-button size="small" fill="clear" (click)="editorOpen = false">Cancel</ion-button>
            </div>
          </div>
        }

        <div class="section-row"><h2>Tracking Library</h2></div>
        <div class="row-list">
          @for (template of templates; track template.id) {
            <div class="row-item">
              <span style="width:.45rem;height:2.6rem;border-radius:1rem;flex:0 0 auto" [style.background]="template.accent || 'var(--app-primary)'"></span>
              <div class="row-main">
                <h3>{{ template.name }}</h3>
                <p>{{ template.cadence }} · {{ template.fields.length }} fields · {{ template.assigned_count || 0 }} assigned</p>
              </div>
              <div class="row-side" style="display:flex;gap:.15rem">
                <ion-button size="small" fill="clear" (click)="startEdit(template)"><ion-icon slot="icon-only" name="create-outline" /></ion-button>
                <ion-button size="small" fill="clear" color="danger" (click)="remove(template)"><ion-icon slot="icon-only" name="trash-outline" /></ion-button>
              </div>
            </div>
          } @empty {
            <p class="empty-note">No templates yet. Create one or adopt a standard template below.</p>
          }
        </div>

        @if (unAdoptedStandards.length) {
          <div class="section-row"><h2>Standard templates</h2></div>
          <div class="row-list">
            @for (standard of unAdoptedStandards; track standard.key) {
              <div class="row-item">
                <div class="row-main">
                  <h3>{{ standard.name }}</h3>
                  <p>{{ standard.cadence }} · {{ standard.fields.length }} fields</p>
                </div>
                <div class="row-side">
                  <ion-button size="small" fill="outline" (click)="adopt(standard)">Adopt</ion-button>
                </div>
              </div>
            }
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerTemplatesPage implements OnInit {
  private readonly api = inject(TemplatesApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  templates: TrackingTemplateRecord[] = [];
  standards: StandardTemplateRecord[] = [];
  maxTemplates = 0;
  message = '';
  editorOpen = false;
  editingId = 0;
  isSaving = false;
  draft: TemplatePayload = { name: '', purpose: '', cadence: 'daily', accent: '#0b7de3', custom_fields: [] };

  constructor() {
    addIcons({ addOutline, trashOutline, createOutline });
  }

  get assignedTotal(): number {
    return this.templates.reduce((sum, item) => sum + Number(item.assigned_count || 0), 0);
  }

  get unAdoptedStandards(): StandardTemplateRecord[] {
    return this.standards.filter((standard) => !standard.adopted);
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  startCreate(): void {
    this.editingId = 0;
    this.draft = { name: '', purpose: '', cadence: 'daily', accent: '#0b7de3', custom_fields: [] };
    this.addField();
    this.editorOpen = true;
  }

  startEdit(template: TrackingTemplateRecord): void {
    this.editingId = template.id;
    this.draft = {
      name: template.name,
      purpose: template.purpose,
      cadence: template.cadence,
      accent: template.accent || '#0b7de3',
      custom_fields: template.fields.map((field) => ({ ...field }))
    };
    this.editorOpen = true;
  }

  addField(): void {
    this.draft.custom_fields.push({ label: '', field_type: 'number', placeholder: '' });
  }

  setOptions(field: TemplateField, raw: string): void {
    field.options = raw
      .split(',')
      .map((option) => option.trim())
      .filter(Boolean);
  }

  save(): void {
    this.isSaving = true;
    const payload: TemplatePayload = {
      ...this.draft,
      name: this.draft.name.trim(),
      purpose: this.draft.purpose.trim(),
      custom_fields: this.draft.custom_fields.filter((field) => field.label.trim())
    };
    const request = this.editingId ? this.api.updateTemplate(this.editingId, payload) : this.api.createTemplate(payload);

    request.subscribe({
      next: () => {
        this.isSaving = false;
        this.editorOpen = false;
        this.load();
        void this.toast('Template saved.');
      },
      error: () => {
        this.isSaving = false;
        this.message = 'Could not save the template.';
      }
    });
  }

  adopt(standard: StandardTemplateRecord): void {
    this.api.adoptStandardTemplate(standard.key).subscribe({
      next: () => {
        this.load();
        void this.toast(`${standard.name} added.`);
      },
      error: () => (this.message = 'Could not adopt the template.')
    });
  }

  async remove(template: TrackingTemplateRecord): Promise<void> {
    const alert = await this.alertController.create({
      header: `Delete ${template.name}?`,
      message: 'Assigned clients lose access to this template. Past entries stay saved.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Delete',
          role: 'destructive',
          handler: () => {
            this.api.deleteTemplate(template.id).subscribe({
              next: () => this.load(),
              error: () => (this.message = 'Template could not be deleted.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  private load(done?: () => void): void {
    this.api.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.maxTemplates = response.max_templates;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load templates.';
        done?.();
      }
    });
    this.api.getStandardTemplates().subscribe({
      next: (response) => (this.standards = response.standard_templates),
      error: () => (this.standards = [])
    });
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
