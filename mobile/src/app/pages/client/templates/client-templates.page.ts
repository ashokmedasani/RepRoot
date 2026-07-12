import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import {
  IonButton,
  IonContent,
  IonHeader,
  IonInput,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonRefresher,
  IonRefresherContent,
  IonSelect,
  IonSelectOption,
  IonTextarea,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { ClientApiService } from '../../../core/api/client-api.service';
import { TemplateField, TrackingEntryRecord, TrackingTemplateRecord } from '../../../core/api/templates-api.service';

/**
 * My Templates (Phase 1 slice): pick a template, submit an entry, see recent
 * entries. Phase 3 adds Overview charts, References, and Progress screens.
 */
@Component({
  selector: 'app-client-templates',
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
    IonList,
    IonListHeader,
    IonItem,
    IonLabel,
    IonInput,
    IonTextarea,
    IonSelect,
    IonSelectOption,
    IonButton
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-title>My Templates</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>

      <div class="page-pad">
        @if (message) {
          <p [class]="messageType === 'error' ? 'error-text' : 'empty-note'">{{ message }}</p>
        }

        @if (templates.length > 1) {
          <ion-item lines="none">
            <ion-select
              label="Template"
              interface="popover"
              [(ngModel)]="selectedTemplateId"
              name="templatePick"
              (ionChange)="resetDraft()"
            >
              @for (template of templates; track template.id) {
                <ion-select-option [value]="template.id">{{ template.name }}</ion-select-option>
              }
            </ion-select>
          </ion-item>
        }

        @if (selectedTemplate; as template) {
          <h2 class="section-title">{{ template.name }}</h2>
          @if (template.purpose) {
            <p class="empty-note">{{ template.purpose }}</p>
          }

          <ion-list inset>
            <ion-list-header><ion-label>New Entry</ion-label></ion-list-header>
            <ion-item>
              <ion-input label="Date" labelPlacement="stacked" type="date" name="entryDate" [(ngModel)]="entryDate" />
            </ion-item>
            <ion-item>
              <ion-input label="Time" labelPlacement="stacked" type="time" name="entryTime" [(ngModel)]="entryTime" />
            </ion-item>

            @for (field of template.fields; track field.key || field.label) {
              <ion-item>
                @if (field.field_type === 'long_text') {
                  <ion-textarea [label]="field.label" labelPlacement="stacked" rows="3" [name]="'f' + fieldKey(field)" [(ngModel)]="answers[fieldKey(field)]" />
                } @else if (field.field_type === 'yes_no') {
                  <ion-select [label]="field.label" interface="popover" [name]="'f' + fieldKey(field)" [(ngModel)]="answers[fieldKey(field)]">
                    <ion-select-option value="Yes">Yes</ion-select-option>
                    <ion-select-option value="No">No</ion-select-option>
                  </ion-select>
                } @else if (field.field_type === 'dropdown') {
                  <ion-select [label]="field.label" interface="popover" [name]="'f' + fieldKey(field)" [(ngModel)]="answers[fieldKey(field)]">
                    @for (option of field.options || []; track option) {
                      <ion-select-option [value]="option">{{ option }}</ion-select-option>
                    }
                  </ion-select>
                } @else if (field.field_type === 'rating') {
                  <ion-select [label]="field.label" interface="popover" [name]="'f' + fieldKey(field)" [(ngModel)]="answers[fieldKey(field)]">
                    @for (step of ratingSteps(field); track step) {
                      <ion-select-option [value]="String(step)">{{ step }}</ion-select-option>
                    }
                  </ion-select>
                } @else {
                  <ion-input
                    [label]="field.label"
                    labelPlacement="stacked"
                    [type]="field.field_type === 'number' ? 'number' : 'text'"
                    [placeholder]="field.placeholder || ''"
                    [name]="'f' + fieldKey(field)"
                    [(ngModel)]="answers[fieldKey(field)]"
                  />
                }
              </ion-item>
            }

            <ion-item>
              <ion-textarea label="Note (optional)" labelPlacement="stacked" rows="2" name="entryNote" [(ngModel)]="note" />
            </ion-item>
          </ion-list>

          <ion-button expand="block" [disabled]="isSaving" (click)="submitEntry()">
            {{ isSaving ? 'Submitting...' : 'Submit Entry' }}
          </ion-button>

          <h2 class="section-title">Recent Entries</h2>
          @if (recentEntries.length) {
            <ion-list inset>
              @for (entry of recentEntries; track entry.id) {
                <ion-item>
                  <ion-label>
                    <h3>{{ entry.entry_date | date: 'dd MMM yyyy' }} {{ entry.entry_time || '' }}</h3>
                    <p>{{ summary(entry) }}</p>
                  </ion-label>
                </ion-item>
              }
            </ion-list>
          } @else {
            <p class="empty-note">No entries yet. Submit your first one above.</p>
          }
        } @else if (!message) {
          <p class="empty-note">No templates assigned yet. Your trainer will assign one soon.</p>
        }
      </div>
    </ion-content>
  `
})
export class ClientTemplatesPage implements OnInit {
  private readonly clientApi = inject(ClientApiService);

  readonly String = String;

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

  get recentEntries(): TrackingEntryRecord[] {
    const template = this.selectedTemplate;
    return template ? this.entries.filter((entry) => entry.template === template.id).slice(0, 5) : [];
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
    this.clientApi
      .submitEntry({
        template_id: template.id,
        entry_date: this.entryDate,
        entry_time: this.entryTime || this.nowTime(),
        answers: this.answers,
        note: this.note.trim()
      })
      .subscribe({
        next: (response) => {
          this.messageType = 'success';
          this.message = response.message;
          this.isSaving = false;
          this.resetDraft();
          this.loadEntries();
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
    return values.slice(0, 3).join(' | ') || 'Submitted';
  }

  private load(done?: () => void): void {
    this.clientApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.selectedTemplateId = this.selectedTemplateId || this.templates[0]?.id || null;
        this.message = '';
        done?.();
      },
      error: () => {
        this.messageType = 'error';
        this.message = 'Could not load templates. Check the backend URL in environment.ts.';
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
