import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute } from '@angular/router';
import { AlertController, ToastController } from '@ionic/angular';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonLabel,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';

import { FormsGroupsApiService } from '../../../core/api/forms-groups-api.service';
import {
  TemplateAssignmentRecord,
  TemplateField,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { ChartSpec, DateRange } from '../../../shared/analytics/analytics.types';
import { buildFieldCharts, buildOverviewCards, sortByTime } from '../../../shared/analytics/graph-engine';
import { ChartCardComponent } from '../../../shared/chart-card.component';

/** Trainer analytics for one client template assignment: shareable graphs, entries, and data entry. */
@Component({
  selector: 'app-client-template',
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
    IonContent,
    IonSegment,
    IonSegmentButton,
    IonLabel,
    ChartCardComponent
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button [defaultHref]="'/trainer/tabs/clients/' + clientId" /></ion-buttons>
        <ion-title>{{ template?.name || 'Template' }}</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        <ion-segment [(ngModel)]="range" (ionChange)="rebuild()" mode="md">
          <ion-segment-button [value]="7"><ion-label>7d</ion-label></ion-segment-button>
          <ion-segment-button [value]="30"><ion-label>30d</ion-label></ion-segment-button>
          <ion-segment-button [value]="90"><ion-label>90d</ion-label></ion-segment-button>
          <ion-segment-button [value]="0"><ion-label>All</ion-label></ion-segment-button>
        </ion-segment>

        @if (overviewCards.length) {
          <div class="kpi-grid">
            @for (card of overviewCards; track card.title) {
              <div class="kpi-tile">
                <span>{{ card.title }}</span>
                <strong>{{ card.meta?.valueText || (card.meta?.value ?? 0) }}{{ card.meta?.unit && !card.meta?.valueText ? ' ' + card.meta?.unit : '' }}</strong>
                @if (card.meta?.deltaText) {
                  <small>{{ card.meta?.deltaText }}</small>
                }
              </div>
            }
          </div>
        }

        @for (chart of charts; track chart.title) {
          <app-chart-card [spec]="chart" [shareContext]="shareContext" />
        } @empty {
          <p class="empty-note" style="margin-top:1rem">No graphable data in this period yet.</p>
        }

        <div class="section-row">
          <h2>Entries</h2>
          <button type="button" class="linklike" (click)="showEntryForm = !showEntryForm">
            {{ showEntryForm ? 'Close' : 'Add entry' }}
          </button>
        </div>

        @if (showEntryForm && template) {
          <div class="card">
            <h3>New entry for {{ clientName }}</h3>
            <div class="form-grid">
              <label><span>Date</span><input type="date" [(ngModel)]="entryDate" /></label>
              @for (field of template.fields; track field.label) {
                <label>
                  <span>{{ field.label }}</span>
                  @if (field.field_type === 'number' || field.field_type === 'rating') {
                    <input type="number" [(ngModel)]="entryAnswers[fieldKeyOf(field)]" [placeholder]="field.placeholder" />
                  } @else if (field.field_type === 'yes_no') {
                    <select [(ngModel)]="entryAnswers[fieldKeyOf(field)]">
                      <option value="">—</option>
                      <option value="yes">Yes</option>
                      <option value="no">No</option>
                    </select>
                  } @else if (field.field_type === 'dropdown') {
                    <select [(ngModel)]="entryAnswers[fieldKeyOf(field)]">
                      <option value="">—</option>
                      @for (option of field.options || []; track option) {
                        <option [value]="option">{{ option }}</option>
                      }
                    </select>
                  } @else if (field.field_type === 'long_text') {
                    <textarea [(ngModel)]="entryAnswers[fieldKeyOf(field)]" [placeholder]="field.placeholder"></textarea>
                  } @else {
                    <input [(ngModel)]="entryAnswers[fieldKeyOf(field)]" [placeholder]="field.placeholder" />
                  }
                </label>
              }
              <label><span>Note</span><input [(ngModel)]="entryNote" placeholder="Optional note" /></label>
            </div>
            <ion-button size="small" style="margin-top:.6rem" (click)="saveEntry()" [disabled]="isSavingEntry || !entryDate">
              {{ isSavingEntry ? 'Saving…' : 'Save entry' }}
            </ion-button>
          </div>
        }

        <div class="row-list" style="margin-top:.5rem">
          @for (entry of visibleEntries; track entry.id) {
            <div class="row-item">
              <div class="row-main">
                <h3>{{ entry.entry_date | date: 'dd MMM yyyy' }}{{ entry.entry_time ? ' · ' + entry.entry_time.slice(0, 5) : '' }}</h3>
                <p>{{ entrySummary(entry) }}</p>
              </div>
              @if (entry.edited_by_trainer) {
                <div class="row-side"><span class="pill info">Trainer edit</span></div>
              }
            </div>
          } @empty {
            <p class="empty-note">No entries submitted.</p>
          }
        </div>

        <ion-button expand="block" color="danger" fill="outline" style="margin-top:1.25rem" (click)="unassign()">
          Unassign template
        </ion-button>
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class ClientTemplatePage implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  clientId = 0;
  assignmentId = 0;
  clientName = '';
  assignment: TemplateAssignmentRecord | null = null;
  template: TrackingTemplateRecord | null = null;
  entries: TrackingEntryRecord[] = [];
  charts: ChartSpec[] = [];
  overviewCards: ChartSpec[] = [];
  range: DateRange = 30;
  message = '';
  showEntryForm = false;
  entryDate = new Date().toISOString().slice(0, 10);
  entryAnswers: Record<string, string> = {};
  entryNote = '';
  isSavingEntry = false;

  get shareContext(): string {
    return `${this.clientName || 'Client'} · ${this.template?.name || ''}`.trim();
  }

  get visibleEntries(): TrackingEntryRecord[] {
    return sortByTime(this.templateEntries()).slice().reverse().slice(0, 25) as TrackingEntryRecord[];
  }

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.assignmentId = Number(this.route.snapshot.paramMap.get('assignmentId'));
    this.load();
  }

  fieldKeyOf(field: TemplateField): string {
    return field.key || field.label;
  }

  rebuild(): void {
    if (!this.template) {
      this.charts = [];
      this.overviewCards = [];
      return;
    }

    const entries = this.templateEntries();
    this.charts = buildFieldCharts(this.template.fields, entries, Number(this.range) as DateRange);
    this.overviewCards = buildOverviewCards(this.template.fields, entries).slice(0, 4);
  }

  entrySummary(entry: TrackingEntryRecord): string {
    const parts = Object.entries(entry.answers)
      .slice(0, 3)
      .map(([key, value]) => `${key.replace(/_/g, ' ')}: ${value}`);
    return parts.join(' · ') || entry.note || '—';
  }

  saveEntry(): void {
    if (!this.template) {
      return;
    }

    this.isSavingEntry = true;
    const answers: Record<string, string> = {};
    Object.entries(this.entryAnswers).forEach(([key, value]) => {
      if (String(value ?? '').trim() !== '') {
        answers[key] = String(value);
      }
    });

    this.templatesApi
      .createClientEntry(this.clientId, {
        template_id: this.template.id,
        entry_date: this.entryDate,
        answers,
        note: this.entryNote.trim()
      })
      .subscribe({
        next: (response) => {
          this.entries = [...this.entries, response.entry];
          this.entryAnswers = {};
          this.entryNote = '';
          this.showEntryForm = false;
          this.isSavingEntry = false;
          this.rebuild();
        },
        error: () => {
          this.isSavingEntry = false;
          void this.toast('Could not save the entry.');
        }
      });
  }

  async unassign(): Promise<void> {
    const alert = await this.alertController.create({
      header: 'Unassign template?',
      message: 'The client will no longer see this template. Past entries stay saved.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Unassign',
          role: 'destructive',
          handler: () => {
            this.templatesApi.unassignTemplate(this.clientId, this.assignmentId).subscribe({
              next: () => window.history.back(),
              error: () => void this.toast('Could not unassign.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  private templateEntries(): TrackingEntryRecord[] {
    const templateId = this.assignment?.template_id || this.template?.id;
    return this.entries.filter((entry) => !templateId || entry.template === templateId);
  }

  private load(): void {
    this.formsGroupsApi.getClientProfile(this.clientId).subscribe({
      next: (detail) => (this.clientName = `${detail.client.first_name} ${detail.client.last_name}`),
      error: () => undefined
    });

    this.templatesApi.getAssignments(this.clientId).subscribe({
      next: (response) => {
        this.assignment = response.assignments.find((item) => item.id === this.assignmentId) || null;

        if (this.assignment) {
          this.templatesApi.getTemplate(this.assignment.template_id).subscribe({
            next: (templateResponse) => {
              this.template = templateResponse.template;
              this.rebuild();
            },
            error: () => (this.message = 'Could not load the template.')
          });
        } else {
          this.message = 'Assignment not found.';
        }
      },
      error: () => (this.message = 'Could not load the assignment.')
    });

    this.templatesApi.getClientEntries(this.clientId).subscribe({
      next: (response) => {
        this.entries = response.entries;
        this.rebuild();
      },
      error: () => (this.entries = [])
    });
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
