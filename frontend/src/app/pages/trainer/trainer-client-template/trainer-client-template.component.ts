import { DatePipe, Location } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessDetailResponse,
  ClientAccessRecord,
  FormsGroupsApiService
} from '../../../core/api/forms-groups-api.service';
import {
  ReferenceCategoryRecord,
  ReferencesApiService,
  TrainerReferenceRecord
} from '../../../core/api/references-api.service';
import {
  TemplateAssignmentRecord,
  TemplateField,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError } from '../../../shared/utils/ui-helpers';

type DetailTab = 'overview' | 'entries' | 'progress';

interface EntryAnswerDraft {
  key: string;
  label: string;
  value: string;
}

interface NumericTrend {
  key: string;
  label: string;
  latest: number;
  change: number;
  points: string;
}

interface TrendRow {
  label: string;
  today: string;
  points: string;
  hasTrend: boolean;
}

interface ConsistencyDay {
  date: string;
  hasEntry: boolean;
}

@Component({
  selector: 'app-trainer-client-template',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-template.component.html',
  styleUrl: './trainer-client-template.component.scss'
})
export class TrainerClientTemplateComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly location = inject(Location);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly referencesApi = inject(ReferencesApiService);

  readonly today = new Date();

  clientId = 0;
  assignmentId = 0;
  profile: ClientAccessDetailResponse | null = null;
  assignment: TemplateAssignmentRecord | null = null;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  detailTab: DetailTab = 'overview';

  referenceCategories: ReferenceCategoryRecord[] = [];
  referenceLibrary: TrainerReferenceRecord[] = [];
  isShareDialogOpen = false;
  shareSelectedIds = new Set<number>();
  referenceSearch = '';
  isSavingShare = false;

  editingEntry: TrackingEntryRecord | null = null;
  entryDraftAnswers: EntryAnswerDraft[] = [];
  entryDraftNote = '';
  isSavingEntry = false;

  isAddEntryOpen = false;
  addEntryDate = '';
  addEntryAnswers: Record<string, string> = {};
  addEntryNote = '';

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.assignmentId = Number(this.route.snapshot.paramMap.get('assignmentId'));
    const requestedTab = this.route.snapshot.queryParamMap.get('tab') as DetailTab | null;

    if (requestedTab && ['overview', 'entries', 'progress'].includes(requestedTab)) {
      this.detailTab = requestedTab;
    }

    this.loadAll(this.route.snapshot.queryParamMap.get('share') === '1');
  }

  get client(): ClientAccessRecord | null {
    return this.profile?.client || null;
  }

  get template(): TrackingTemplateRecord | null {
    const assignment = this.assignment;

    if (!assignment) {
      return null;
    }

    return this.templates.find((item) => item.id === assignment.template_id) || null;
  }

  get templateEntries(): TrackingEntryRecord[] {
    const assignment = this.assignment;

    if (!assignment) {
      return [];
    }

    return this.entries.filter((entry) => entry.template === assignment.template_id);
  }

  goBack(): void {
    this.location.back();
  }

  setDetailTab(tab: DetailTab): void {
    this.detailTab = tab;
  }

  get trendRows(): TrendRow[] {
    const template = this.template;

    if (!template) {
      return [];
    }

    const todayIso = this.todayIso();
    const todayEntry = this.templateEntries.find((entry) => entry.entry_date === todayIso);
    const lastWeek = [...this.templateEntries]
      .sort((first, second) => first.entry_date.localeCompare(second.entry_date))
      .slice(-7);

    return template.fields
      .filter((field) => field.field_type === 'number')
      .map((field) => {
        const key = field.key || field.label;
        const values = lastWeek
          .map((entry) => Number(String(entry.answers?.[key] ?? '').trim()))
          .filter((value) => !Number.isNaN(value));

        return {
          label: field.label,
          today: String(todayEntry?.answers?.[key] ?? '-') || '-',
          points: values.length >= 2 ? this.sparklinePoints(values) : '',
          hasTrend: values.length >= 2
        };
      });
  }

  // ----- add entry -----

  openAddEntry(): void {
    this.isAddEntryOpen = true;
    this.addEntryDate = this.todayIso();
    this.addEntryAnswers = {};
    this.addEntryNote = '';
  }

  closeAddEntry(): void {
    this.isAddEntryOpen = false;
  }

  detailFieldKey(field: TemplateField): string {
    return field.key || field.label;
  }

  saveAddEntry(): void {
    const assignment = this.assignment;

    if (!assignment || !this.addEntryDate || this.isSavingEntry) {
      return;
    }

    this.isSavingEntry = true;
    this.templatesApi
      .createClientEntry(this.clientId, {
        template_id: assignment.template_id,
        entry_date: this.addEntryDate,
        answers: this.addEntryAnswers,
        note: this.addEntryNote.trim()
      })
      .subscribe({
        next: (response) => {
          this.messageType = 'success';
          this.message = response.message;
          this.isSavingEntry = false;
          this.closeAddEntry();
          this.loadEntries();
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = formatApiError(error, 'Entry could not be recorded.');
          this.isSavingEntry = false;
        }
      });
  }

  // ----- share references -----

  openShareDialog(): void {
    this.isShareDialogOpen = true;
    this.shareSelectedIds = new Set((this.assignment?.references || []).map((reference) => reference.id));
    this.referenceSearch = '';
  }

  closeShareDialog(): void {
    this.isShareDialogOpen = false;
    this.shareSelectedIds = new Set<number>();
  }

  toggleSharedReference(reference: TrainerReferenceRecord): void {
    if (this.shareSelectedIds.has(reference.id)) {
      this.shareSelectedIds.delete(reference.id);
    } else {
      this.shareSelectedIds.add(reference.id);
    }
  }

  isSharedReference(reference: TrainerReferenceRecord): boolean {
    return this.shareSelectedIds.has(reference.id);
  }

  get filteredReferenceLibrary(): TrainerReferenceRecord[] {
    const search = this.referenceSearch.trim().toLowerCase();

    if (!search) {
      return this.referenceLibrary;
    }

    return this.referenceLibrary.filter((reference) =>
      [reference.title, reference.category_name, reference.subcategory, reference.tags.join(' ')]
        .join(' ')
        .toLowerCase()
        .includes(search)
    );
  }

  referencesForCategory(category: ReferenceCategoryRecord): TrainerReferenceRecord[] {
    return this.filteredReferenceLibrary.filter((reference) => reference.category === category.id);
  }

  saveSharedReferences(): void {
    const assignment = this.assignment;

    if (!assignment || this.isSavingShare) {
      return;
    }

    this.templatesApi.updateAssignmentReferences(this.clientId, assignment.id, Array.from(this.shareSelectedIds)).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.assignment = response.assignment;
        this.isSavingShare = false;
        this.closeShareDialog();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Shared references could not be updated.');
        this.isSavingShare = false;
      }
    });
  }

  referenceTypeLabel(referenceType: string): string {
    const labels: Record<string, string> = {
      video_link: 'YouTube Video',
      pdf: 'PDF Document',
      image: 'Image',
      document: 'Document',
      text_note: 'Note',
      external_link: 'Link'
    };

    return labels[referenceType] || 'Resource';
  }

  // ----- entry editing -----

  startEntryEdit(entry: TrackingEntryRecord): void {
    this.editingEntry = entry;
    this.entryDraftNote = entry.note;
    this.entryDraftAnswers = Object.entries(entry.answers || {}).map(([key, value]) => ({
      key,
      label: this.fieldLabelFor(key),
      value: String(value ?? '')
    }));
  }

  cancelEntryEdit(): void {
    this.editingEntry = null;
    this.entryDraftAnswers = [];
    this.entryDraftNote = '';
  }

  saveEntryEdit(): void {
    const entry = this.editingEntry;

    if (!entry || this.isSavingEntry) {
      return;
    }

    const answers: Record<string, string> = {};

    for (const draft of this.entryDraftAnswers) {
      answers[draft.key] = draft.value;
    }

    this.isSavingEntry = true;
    this.templatesApi.updateEntry(entry.id, { answers, note: this.entryDraftNote }).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isSavingEntry = false;
        this.cancelEntryEdit();
        this.loadEntries();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Entry could not be updated.');
        this.isSavingEntry = false;
      }
    });
  }

  fieldLabelFor(key: string): string {
    const field = this.template?.fields.find((item) => item.key === key);
    return field?.label || key.replace(/_/g, ' ');
  }

  answerPreview(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter((value) => value && !value.startsWith('data:image'));

    return values.slice(0, 3).join(' | ') || 'No values recorded';
  }

  isImageValue(value: string): boolean {
    return value.startsWith('data:image');
  }

  // ----- progress -----

  get consistencyDays(): ConsistencyDay[] {
    const entryDates = new Set(this.templateEntries.map((entry) => entry.entry_date));
    const days: ConsistencyDay[] = [];
    const today = new Date();

    for (let offset = 29; offset >= 0; offset -= 1) {
      const day = new Date(today);
      day.setDate(today.getDate() - offset);
      const isoDate = day.toISOString().slice(0, 10);
      days.push({ date: isoDate, hasEntry: entryDates.has(isoDate) });
    }

    return days;
  }

  get numericTrends(): NumericTrend[] {
    const series = new Map<string, { label: string; values: number[] }>();
    const sortedEntries = [...this.templateEntries].sort((first, second) =>
      first.entry_date.localeCompare(second.entry_date)
    );

    for (const entry of sortedEntries) {
      for (const [key, rawValue] of Object.entries(entry.answers || {})) {
        const value = Number(String(rawValue).trim());

        if (!String(rawValue).trim() || Number.isNaN(value)) {
          continue;
        }

        const existing = series.get(key) || { label: this.fieldLabelFor(key), values: [] };
        existing.values.push(value);
        series.set(key, existing);
      }
    }

    return Array.from(series.entries())
      .filter(([, data]) => data.values.length >= 2)
      .map(([key, data]) => ({
        key,
        label: data.label,
        latest: data.values[data.values.length - 1],
        change: Number((data.values[data.values.length - 1] - data.values[0]).toFixed(2)),
        points: this.sparklinePoints(data.values)
      }))
      .slice(0, 6);
  }

  get recentNotes(): TrackingEntryRecord[] {
    return this.templateEntries.filter((entry) => entry.note.trim()).slice(0, 6);
  }

  // ----- loading -----

  private loadAll(openShare: boolean): void {
    this.formsGroupsApi.getClientProfile(this.clientId).subscribe({
      next: (profile) => {
        this.profile = profile;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load the client.');
      }
    });
    this.templatesApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
      },
      error: () => {
        this.templates = [];
      }
    });
    this.templatesApi.getAssignments(this.clientId).subscribe({
      next: (response) => {
        this.assignment = response.assignments.find((item) => item.id === this.assignmentId) || null;
        this.isLoading = false;

        if (this.assignment && openShare) {
          this.openShareDialog();
        }
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load the template assignment.');
        this.isLoading = false;
      }
    });
    this.loadEntries();
    this.referencesApi.getCategories().subscribe({
      next: (response) => (this.referenceCategories = response.categories),
      error: () => (this.referenceCategories = [])
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => (this.referenceLibrary = response.references),
      error: () => (this.referenceLibrary = [])
    });
  }

  private loadEntries(): void {
    this.templatesApi.getClientEntries(this.clientId).subscribe({
      next: (response) => {
        this.entries = response.entries;
      },
      error: () => {
        this.entries = [];
      }
    });
  }

  private todayIso(): string {
    return new Date().toISOString().slice(0, 10);
  }

  private sparklinePoints(values: number[]): string {
    const width = 120;
    const height = 34;
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;

    return values
      .map((value, index) => {
        const x = values.length > 1 ? (index / (values.length - 1)) * width : width / 2;
        const y = height - 3 - ((value - min) / range) * (height - 6);

        return `${x.toFixed(1)},${y.toFixed(1)}`;
      })
      .join(' ');
  }
}
