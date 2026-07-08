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
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { ChatPanelComponent } from '../../../shared/chat-panel/chat-panel.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

interface IntakeDetail {
  label: string;
  value: string;
  source: 'registration' | 'lead-form';
}

interface EntryAnswerDraft {
  key: string;
  label: string;
  value: string;
}

interface NumericTrend {
  key: string;
  label: string;
  values: number[];
  dates: string[];
  latest: number;
  change: number;
  points: string;
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

  profile: ClientAccessDetailResponse | null = null;
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  resetPasswordResult = '';
  isAccountDialogOpen = false;

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
  editingEntry: TrackingEntryRecord | null = null;
  entryDraftAnswers: EntryAnswerDraft[] = [];
  entryDraftNote = '';
  isSavingEntry = false;

  intakeDetails: IntakeDetail[] = [];
  numericTrends: NumericTrend[] = [];
  consistencyDays: ConsistencyDay[] = [];
  recentNotes: TrackingEntryRecord[] = [];

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
        this.loadAssignments(client.id);
        this.openShareDialog(response.assignment);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be assigned.');
        this.isAssigning = false;
      }
    });
  }

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
        this.loadAssignments(client.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Shared references could not be updated.');
        this.isSavingShare = false;
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
        this.loadAssignments(client.id);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be unassigned.');
      }
    });
  }

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

  private loadProfile(): void {
    const clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.isLoading = true;

    this.formsGroupsApi.getClientProfile(clientId).subscribe({
      next: (profile) => {
        this.profile = profile;
        this.buildIntakeDetails(profile);
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
        this.buildInsights();
      },
      error: () => {
        this.templates = [];
      }
    });
    this.loadAssignments(clientId);
    this.loadEntries(clientId);
    this.loadReferenceLibrary();
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

  private loadAssignments(clientId: number): void {
    this.templatesApi.getAssignments(clientId).subscribe({
      next: (response) => {
        this.assignments = response.assignments;
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
        this.buildInsights();
      },
      error: () => {
        this.entries = [];
      }
    });
  }

  private buildIntakeDetails(profile: ClientAccessDetailResponse): void {
    const details: IntakeDetail[] = [];
    const seenKeys = new Set<string>();

    for (const field of profile.registration_fields) {
      const key = field.key || field.label;
      const value = profile.client.registration_answers?.[key];
      seenKeys.add(key);
      details.push({
        label: field.label,
        value: value ? String(value) : 'Not added',
        source: 'registration'
      });
    }

    for (const [key, value] of Object.entries(profile.lead_submission.answers || {})) {
      if (seenKeys.has(key)) {
        continue;
      }

      details.push({
        label: key.replace(/_/g, ' '),
        value: value ? String(value) : 'Not added',
        source: 'lead-form'
      });
    }

    this.intakeDetails = details;
  }

  private buildInsights(): void {
    this.buildNumericTrends();
    this.buildConsistency();
    this.recentNotes = this.entries.filter((entry) => entry.note.trim()).slice(0, 6);
  }

  private buildNumericTrends(): void {
    const series = new Map<string, { label: string; points: { date: string; value: number }[] }>();
    const sortedEntries = [...this.entries].sort((first, second) => first.entry_date.localeCompare(second.entry_date));

    for (const entry of sortedEntries) {
      for (const [key, rawValue] of Object.entries(entry.answers || {})) {
        const value = Number(String(rawValue).trim());

        if (!String(rawValue).trim() || Number.isNaN(value)) {
          continue;
        }

        const existing = series.get(key) || { label: this.fieldLabelFor(entry, key), points: [] };
        existing.points.push({ date: entry.entry_date, value });
        series.set(key, existing);
      }
    }

    this.numericTrends = Array.from(series.entries())
      .filter(([, data]) => data.points.length >= 2)
      .map(([key, data]) => {
        const values = data.points.map((point) => point.value);

        return {
          key,
          label: data.label,
          values,
          dates: data.points.map((point) => point.date),
          latest: values[values.length - 1],
          change: Number((values[values.length - 1] - values[0]).toFixed(2)),
          points: this.sparklinePoints(values)
        };
      })
      .slice(0, 6);
  }

  private buildConsistency(): void {
    const entryDates = new Set(this.entries.map((entry) => entry.entry_date));
    const days: ConsistencyDay[] = [];
    const today = new Date();

    for (let offset = 29; offset >= 0; offset -= 1) {
      const day = new Date(today);
      day.setDate(today.getDate() - offset);
      const isoDate = day.toISOString().slice(0, 10);
      days.push({ date: isoDate, hasEntry: entryDates.has(isoDate) });
    }

    this.consistencyDays = days;
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
