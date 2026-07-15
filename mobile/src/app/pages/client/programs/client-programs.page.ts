import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonContent,
  IonHeader,
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { ClientApiService } from '../../../core/api/client-api.service';
import { TemplateField, TemplateReference, TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';

type ProgramsTab = 'program' | 'resources';

/** Programs — assigned templates with check-in entry, plus trainer-shared resources. */
@Component({
  selector: 'app-client-programs',
  standalone: true,
  imports: [
    DatePipe,
    FormsModule,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonSegment,
    IonSegmentButton,
    IonLabel,
    IonButton
  ],
  template: `
    <ion-header>
      <ion-toolbar><ion-title>Programs</ion-title></ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad">
        <ion-segment [(ngModel)]="tab" mode="md">
          <ion-segment-button value="program"><ion-label>My Programs</ion-label></ion-segment-button>
          <ion-segment-button value="resources"><ion-label>Resources</ion-label></ion-segment-button>
        </ion-segment>

        @if (message) {
          <p [class]="messageType === 'error' ? 'error-text' : 'success-text'">{{ message }}</p>
        }

        @if (tab === 'program') {
          @if (templates.length > 1) {
            <div class="group-chips" style="display:flex;gap:.45rem;overflow-x:auto;padding-bottom:.35rem">
              @for (template of templates; track template.id) {
                <button
                  type="button"
                  (click)="selectedTemplateId = template.id; resetDraft()"
                  [style.background]="selectedTemplate?.id === template.id ? 'var(--app-primary-soft)' : 'var(--app-surface)'"
                  [style.borderColor]="selectedTemplate?.id === template.id ? 'var(--app-primary)' : 'var(--app-border)'"
                  style="flex:0 0 auto;border:1px solid;border-radius:999px;color:var(--app-text);font-size:.78rem;font-weight:700;padding:.38rem .85rem"
                >
                  {{ template.name }}
                </button>
              }
            </div>
          }

          @if (selectedTemplate; as template) {
            <div class="card" style="border-left:4px solid var(--app-primary)" [style.borderLeftColor]="template.accent || null">
              <h3 style="margin:0">{{ template.name }}</h3>
              <p class="sub" style="margin:.25rem 0 0">{{ template.cadence }} check-ins{{ template.purpose ? ' · ' + template.purpose : '' }}</p>
              <div style="margin-top:.6rem;height:.45rem;border-radius:1rem;background:var(--app-surface-soft);overflow:hidden">
                <div [style.width.%]="completionPercent" style="height:100%;background:var(--app-primary);border-radius:inherit"></div>
              </div>
              <small style="color:var(--app-muted);font-weight:600">{{ entriesForSelected.length }} check-ins recorded</small>
            </div>

            <div class="card">
              <h3>New check-in</h3>
              <div class="form-grid">
                <div class="form-two">
                  <label><span>Date</span><input type="date" [(ngModel)]="entryDate" /></label>
                  <label><span>Time</span><input type="time" [(ngModel)]="entryTime" /></label>
                </div>
                @for (field of template.fields; track field.key || field.label) {
                  <label>
                    <span>{{ field.label }}</span>
                    @if (field.field_type === 'long_text') {
                      <textarea [(ngModel)]="answers[fieldKey(field)]" [placeholder]="field.placeholder || ''"></textarea>
                    } @else if (field.field_type === 'yes_no') {
                      <select [(ngModel)]="answers[fieldKey(field)]">
                        <option value="">—</option>
                        <option value="Yes">Yes</option>
                        <option value="No">No</option>
                      </select>
                    } @else if (field.field_type === 'dropdown') {
                      <select [(ngModel)]="answers[fieldKey(field)]">
                        <option value="">—</option>
                        @for (option of field.options || []; track option) {
                          <option [value]="option">{{ option }}</option>
                        }
                      </select>
                    } @else if (field.field_type === 'rating') {
                      <select [(ngModel)]="answers[fieldKey(field)]">
                        <option value="">—</option>
                        @for (step of ratingSteps(field); track step) {
                          <option [value]="String(step)">{{ step }}</option>
                        }
                      </select>
                    } @else {
                      <input
                        [type]="field.field_type === 'number' ? 'number' : 'text'"
                        [placeholder]="field.placeholder || ''"
                        [(ngModel)]="answers[fieldKey(field)]"
                      />
                    }
                  </label>
                }
                <label><span>Note (optional)</span><input [(ngModel)]="note" /></label>
              </div>
              <ion-button expand="block" style="margin-top:.8rem" [disabled]="isSaving" (click)="submitEntry()">
                {{ isSaving ? 'Submitting…' : 'Submit Check-in' }}
              </ion-button>
            </div>

            <div class="section-row"><h2>Recent check-ins</h2></div>
            <div class="row-list">
              @for (entry of entriesForSelected.slice(0, 6); track entry.id) {
                <div class="row-item">
                  <div class="row-main">
                    <h3>{{ entry.entry_date | date: 'dd MMM yyyy' }}{{ entry.entry_time ? ' · ' + entry.entry_time.slice(0, 5) : '' }}</h3>
                    <p>{{ summary(entry) }}</p>
                  </div>
                  @if (entry.edited_by_trainer) {
                    <div class="row-side"><span class="pill info">Trainer</span></div>
                  }
                </div>
              } @empty {
                <p class="empty-note">No check-ins yet. Submit your first one above.</p>
              }
            </div>
          } @else if (!message) {
            <p class="empty-note" style="margin-top:1rem">No programs assigned yet. Your trainer will assign one soon.</p>
          }
        }

        @if (tab === 'resources') {
          @if (allReferences.length) {
            <div class="row-list" style="margin-top:.25rem">
              @for (reference of allReferences; track reference.id) {
                <div class="card" style="margin-top:0">
                  <h3 style="margin:0">{{ reference.title }}</h3>
                  <p class="sub" style="margin:.2rem 0 0">
                    {{ reference.category_name }}{{ reference.subcategory ? ' › ' + reference.subcategory : '' }}
                  </p>
                  @if (reference.description) {
                    <p style="margin:.5rem 0 0;font-size:.85rem;white-space:pre-wrap">{{ reference.description }}</p>
                  }
                  @if (reference.link || reference.file_url) {
                    <ion-button size="small" fill="outline" style="margin-top:.6rem" (click)="open(reference)">Open</ion-button>
                  }
                </div>
              }
            </div>
          } @else {
            <p class="empty-note" style="margin-top:1rem">No resources shared with your programs yet.</p>
          }
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientProgramsPage implements OnInit {
  private readonly clientApi = inject(ClientApiService);

  readonly String = String;

  tab: ProgramsTab = 'program';
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  selectedTemplateId: number | null = null;

  entryDate = new Date().toISOString().slice(0, 10);
  entryTime = this.nowTime();
  answers: Record<string, string> = {};
  note = '';
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  get selectedTemplate(): TrackingTemplateRecord | null {
    return this.templates.find((template) => template.id === this.selectedTemplateId) || this.templates[0] || null;
  }

  get entriesForSelected(): TrackingEntryRecord[] {
    const template = this.selectedTemplate;
    return template ? this.entries.filter((entry) => entry.template === template.id) : [];
  }

  get completionPercent(): number {
    const count = this.entriesForSelected.length;
    return Math.min(100, count * 10);
  }

  get allReferences(): TemplateReference[] {
    const seen = new Set<number>();
    const references: TemplateReference[] = [];

    for (const template of this.templates) {
      for (const reference of template.references || []) {
        if (!seen.has(reference.id)) {
          seen.add(reference.id);
          references.push(reference);
        }
      }
    }

    return references;
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  fieldKey(field: TemplateField): string {
    return field.key || field.label;
  }

  ratingSteps(field: TemplateField): number[] {
    const scale = Math.min(10, Math.max(2, field.scale || 5));
    return Array.from({ length: scale }, (_value, index) => index + 1);
  }

  open(reference: TemplateReference): void {
    const url = reference.link || reference.file_url;

    if (url) {
      window.open(url, '_blank');
    }
  }

  resetDraft(): void {
    this.answers = {};
    this.note = '';
    this.entryDate = new Date().toISOString().slice(0, 10);
    this.entryTime = this.nowTime();
  }

  submitEntry(): void {
    const template = this.selectedTemplate;

    if (!template || !this.entryDate || this.isSaving) {
      return;
    }

    this.isSaving = true;
    const answers: Record<string, string> = {};
    Object.entries(this.answers).forEach(([key, value]) => {
      if (String(value ?? '').trim() !== '') {
        answers[key] = String(value);
      }
    });

    this.clientApi
      .submitEntry({
        template_id: template.id,
        entry_date: this.entryDate,
        entry_time: this.entryTime || this.nowTime(),
        answers,
        note: this.note.trim()
      })
      .subscribe({
        next: (response) => {
          this.messageType = 'success';
          this.message = response.message;
          this.isSaving = false;
          this.resetDraft();
          this.loadEntries();
          setTimeout(() => (this.message = ''), 3000);
        },
        error: () => {
          this.messageType = 'error';
          this.message = 'Entry could not be submitted.';
          this.isSaving = false;
        }
      });
  }

  summary(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter(Boolean);
    return values.slice(0, 3).join(' · ') || 'Submitted';
  }

  private load(done?: () => void): void {
    this.clientApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.selectedTemplateId = this.selectedTemplateId || this.templates[0]?.id || null;
        done?.();
      },
      error: () => {
        this.messageType = 'error';
        this.message = 'Could not load your programs. Pull to retry.';
        done?.();
      }
    });
    this.loadEntries();
  }

  private loadEntries(): void {
    this.clientApi.getEntries().subscribe({
      next: (response) => (this.entries = response.entries),
      error: () => (this.entries = [])
    });
  }

  private nowTime(): string {
    const now = new Date();
    return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  }
}
