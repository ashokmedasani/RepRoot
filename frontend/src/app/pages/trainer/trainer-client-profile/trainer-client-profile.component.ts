import { DatePipe } from '@angular/common';
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
import { ChatPanelComponent } from '../../../shared/chat-panel/chat-panel.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

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
  selector: 'app-trainer-client-profile',
  standalone: true,
  imports: [ChatPanelComponent, DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-profile.component.html',
  styleUrl: './trainer-client-profile.component.scss'
})
export class TrainerClientProfileComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly referencesApi = inject(ReferencesApiService);

  readonly today = new Date();

  profile: ClientAccessDetailResponse | null = null;
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  resetPasswordResult = '';
  isAccountDialogOpen = false;

  trainerNotes = '';
  notesUpdatedAt: string | null = null;
  isEditingNotes = false;
  notesDraft = '';
  isSavingNotes = false;

  assignments: TemplateAssignmentRecord[] = [];
  templates: TrackingTemplateRecord[] = [];
  selectedTemplateId: number | null = null;
  isAssigning = false;

  referenceCategories: ReferenceCategoryRecord[] = [];
  referenceLibrary: TrainerReferenceRecord[] = [];
  sharingAssignment: TemplateAssignmentRecord | null = null;
  shareSelectedIds = new Set<number>();
  referenceSearch = '';
  isSavingShare = false;

  entries: TrackingEntryRecord[] = [];
  selectedAssignment: TemplateAssignmentRecord | null = null;
  detailTab: DetailTab = 'overview';

  editingEntry: TrackingEntryRecord | null = null;
  entryDraftAnswers: EntryAnswerDraft[] = [];
  entryDraftNote = '';
  isSavingEntry = false;

  isAddEntryOpen = false;
  addEntryDate = '';
  addEntryAnswers: Record<string, string> = {};
  addEntryNote = '';

  ngOnInit(): void {
    this.loadProfile();
  }

  get client(): ClientAccessRecord | null {
    return this.profile?.client || null;
  }

  get availableTemplates(): TrackingTemplateRecord[] {
    const assignedIds = new Set(this.assignments.map((assignment) => assignment.template_id));
    return this.templates.filter((template) => !assignedIds.has(template.id));
  }

  initials(client: ClientAccessRecord): string {
    return initialsFor(client.first_name, client.last_name);
  }

  contactValue(keywords: string[]): string {
    const sources = [this.client?.registration_answers || {}, this.profile?.lead_submission?.answers || {}];

    for (const source of sources) {
      for (const [key, value] of Object.entries(source)) {
        const normalizedKey = key.toLowerCase();

        if (keywords.some((keyword) => normalizedKey.includes(keyword)) && String(value ?? '').trim()) {
          return String(value).trim();
        }
      }
    }

    return '';
  }

  // ----- account dialog -----

  openAccountDialog(): void {
    this.isAccountDialogOpen = true;
  }

  closeAccountDialog(): void {
    this.isAccountDialogOpen = false;
  }

  resetClientPassword(): void {
    const client = this.client;

    if (!client) {
      return;
    }

    const confirmed = window.confirm(`Reset password for ${client.first_name} ${client.last_name}?`);

    if (!confirmed) {
      return;
    }

    this.formsGroupsApi.resetClientPassword(client.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.resetPasswordResult = response.temporary_password;
        client.must_change_password = true;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client password could not be reset.');
      }
    });
  }

  // ----- trainer notes -----

  startEditNotes(): void {
    this.notesDraft = this.trainerNotes;
    this.isEditingNotes = true;
  }

  cancelEditNotes(): void {
    this.isEditingNotes = false;
  }

  saveNotes(): void {
    const client = this.client;

    if (!client || this.isSavingNotes) {
      return;
    }

    this.isSavingNotes = true;
    this.formsGroupsApi.saveTrainerNotes(client.id, this.notesDraft.trim()).subscribe({
      next: (response) => {
        this.trainerNotes = response.trainer_notes;
        this.notesUpdatedAt = response.trainer_notes_updated_at;
        this.isEditingNotes = false;
        this.isSavingNotes = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Notes could not be saved.');
        this.isSavingNotes = false;
      }
    });
  }

  // ----- assignments -----

  assignTemplate(): void {
    const client = this.client;

    if (!client || !this.selectedTemplateId || this.isAssigning) {
      return;
    }

    this.isAssigning = true;
    this.templatesApi.assignTemplate(client.id, this.selectedTemplateId).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.selectedTemplateId = null;
        this.isAssigning = false;
        this.loadAssignments(client.id, response.assignment.id);
        this.openShareDialog(response.assignment);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be assigned.');
        this.isAssigning = false;
      }
    });
  }

  unassignTemplate(assignment: TemplateAssignmentRecord): void {
    const client = this.client;

    if (!client) {
      return;
    }

    const confirmed = window.confirm(
      `Remove ${assignment.template_name} from this client? Past entries are kept, so nothing is lost.`
    );

    if (!confirmed) {
      return;
    }

    this.templatesApi.unassignTemplate(client.id, assignment.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;

        if (this.selectedAssignment?.id === assignment.id) {
          this.selectedAssignment = null;
        }

        this.loadAssignments(client.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be unassigned.');
      }
    });
  }

  // ----- template detail panel -----

  openTemplateDetail(assignment: TemplateAssignmentRecord): void {
    this.selectedAssignment = assignment;
    this.detailTab = 'overview';
  }

  setDetailTab(tab: DetailTab): void {
    this.detailTab = tab;
  }

  get detailTemplate(): TrackingTemplateRecord | null {
    const assignment = this.selectedAssignment;

    if (!assignment) {
      return null;
    }

    return this.templates.find((template) => template.id === assignment.template_id) || null;
  }

  get detailEntries(): TrackingEntryRecord[] {
    const assignment = this.selectedAssignment;

    if (!assignment) {
      return [];
    }

    return this.entries.filter((entry) => entry.template === assignment.template_id);
  }

  get trendRows(): TrendRow[] {
    const template = this.detailTemplate;

    if (!template) {
      return [];
    }

    const today = this.todayIso();
    const todayEntry = this.detailEntries.find((entry) => entry.entry_date === today);
    const lastWeek = [...this.detailEntries]
      .sort((first, second) => first.entry_date.localeCompare(second.entry_date))
      .slice(-7);

    return template.fields
      .filter((field) => field.field_type === 'number')
      .map((field) => {
        const key = field.key || field.label;
        const values = lastWeek
          .map((entry) => Number(String(entry.answers?.[key] ?? '').trim()))
          .filter((value) => !Number.isNaN(value) && String(value) !== 'NaN');

        return {
          label: field.label,
          today: String(todayEntry?.answers?.[key] ?? '-') || '-',
          points: values.length >= 2 ? this.sparklinePoints(values) : '',
          hasTrend: values.length >= 2
        };
      });
  }

  // ----- add entry (trainer records for the client) -----

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
    const client = this.client;
    const assignment = this.selectedAssignment;

    if (!client || !assignment || !this.addEntryDate || this.isSavingEntry) {
      return;
    }

    this.isSavingEntry = true;
    this.templatesApi
      .createClientEntry(client.id, {
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
          this.loadEntries(client.id);
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = formatApiError(error, 'Entry could not be recorded.');
          this.isSavingEntry = false;
        }
      });
  }

  // ----- share references -----

  openShareDialog(assignment: TemplateAssignmentRecord): void {
    this.sharingAssignment = assignment;
    this.shareSelectedIds = new Set((assignment.references || []).map((reference) => reference.id));
    this.referenceSearch = '';
  }

  closeShareDialog(): void {
    this.sharingAssignment = null;
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
    const client = this.client;
    const assignment = this.sharingAssignment;

    if (!client || !assignment || this.isSavingShare) {
      return;
    }

    this.isSavingShare = true;
    this.templatesApi.updateAssignmentReferences(client.id, assignment.id, Array.from(this.shareSelectedIds)).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isSavingShare = false;
        this.closeShareDialog();
        this.loadAssignments(client.id, this.selectedAssignment?.id);
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
      label: this.fieldLabelFor(entry, key),
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
    const client = this.client;

    if (!entry || !client || this.isSavingEntry) {
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
        this.loadEntries(client.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Entry could not be updated.');
        this.isSavingEntry = false;
      }
    });
  }

  fieldLabelFor(entry: TrackingEntryRecord, key: string): string {
    const template = this.templates.find((item) => item.id === entry.template);
    const field = template?.fields.find((item) => item.key === key);

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

  // ----- activity stats -----

  get entriesThisMonth(): number {
    const monthPrefix = this.todayIso().slice(0, 7);
    return this.entries.filter((entry) => entry.entry_date.startsWith(monthPrefix)).length;
  }

  get lastEntry(): TrackingEntryRecord | null {
    return this.entries.length ? this.entries[0] : null;
  }

  get streak(): number {
    const entryDates = new Set(this.entries.map((entry) => entry.entry_date));
    let streak = 0;
    const cursor = new Date();

    if (!entryDates.has(this.todayIso())) {
      cursor.setDate(cursor.getDate() - 1);
    }

    while (entryDates.has(cursor.toISOString().slice(0, 10))) {
      streak += 1;
      cursor.setDate(cursor.getDate() - 1);
    }

    return streak;
  }

  get completionPercent(): number {
    const dayOfMonth = new Date().getDate();
    const monthPrefix = this.todayIso().slice(0, 7);
    const daysWithEntries = new Set(
      this.entries.filter((entry) => entry.entry_date.startsWith(monthPrefix)).map((entry) => entry.entry_date)
    ).size;

    return Math.min(100, Math.round((daysWithEntries / dayOfMonth) * 100));
  }

  get recentEntries(): TrackingEntryRecord[] {
    return this.entries.slice(0, 3);
  }

  openEntryFromActivity(entry: TrackingEntryRecord): void {
    const assignment = this.assignments.find((item) => item.template_id === entry.template);

    if (assignment) {
      this.openTemplateDetail(assignment);
      this.detailTab = 'entries';
    }
  }

  // ----- insights (progress tab) -----

  get consistencyDays(): ConsistencyDay[] {
    const entryDates = new Set(this.detailEntries.map((entry) => entry.entry_date));
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
    const sortedEntries = [...this.detailEntries].sort((first, second) =>
      first.entry_date.localeCompare(second.entry_date)
    );

    for (const entry of sortedEntries) {
      for (const [key, rawValue] of Object.entries(entry.answers || {})) {
        const value = Number(String(rawValue).trim());

        if (!String(rawValue).trim() || Number.isNaN(value)) {
          continue;
        }

        const existing = series.get(key) || { label: this.fieldLabelFor(entry, key), values: [] };
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
    return this.detailEntries.filter((entry) => entry.note.trim()).slice(0, 6);
  }

  // ----- loading -----

  private loadProfile(): void {
    const clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.isLoading = true;

    this.formsGroupsApi.getClientProfile(clientId).subscribe({
      next: (profile) => {
        this.profile = profile;
        this.trainerNotes = profile.trainer_notes || '';
        this.notesUpdatedAt = profile.trainer_notes_updated_at;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load client profile.');
        this.isLoading = false;
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
    this.loadAssignments(clientId, undefined, true);
    this.loadEntries(clientId);
    this.loadReferenceLibrary();
  }

  private loadAssignments(clientId: number, keepSelectedId?: number, selectFirst = false): void {
    this.templatesApi.getAssignments(clientId).subscribe({
      next: (response) => {
        this.assignments = response.assignments;
        const selectedId = keepSelectedId ?? this.selectedAssignment?.id;
        const selected = this.assignments.find((assignment) => assignment.id === selectedId);
        this.selectedAssignment = selected || (selectFirst ? this.assignments[0] || null : this.selectedAssignment);

        if (this.selectedAssignment && !this.assignments.some((item) => item.id === this.selectedAssignment?.id)) {
          this.selectedAssignment = this.assignments[0] || null;
        }
      },
      error: () => {
        this.assignments = [];
      }
    });
  }

  private loadEntries(clientId: number): void {
    this.templatesApi.getClientEntries(clientId).subscribe({
      next: (response) => {
        this.entries = response.entries;
      },
      error: () => {
        this.entries = [];
      }
    });
  }

  private loadReferenceLibrary(): void {
    this.referencesApi.getCategories().subscribe({
      next: (response) => (this.referenceCategories = response.categories),
      error: () => (this.referenceCategories = [])
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => (this.referenceLibrary = response.references),
      error: () => (this.referenceLibrary = [])
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
