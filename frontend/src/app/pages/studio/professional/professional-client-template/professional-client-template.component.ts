import { DatePipe, Location } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessDetailResponse,
  ClientAccessRecord,
  FormsGroupsApiService,
  ProgressEntry
} from '@core/api/forms-groups-api.service';
import {
  ResourceCategoryRecord,
  ResourcesApiService,
  ProfessionalResourceRecord
} from '@core/api/resources-api.service';
import {
  TemplateAssignmentRecord,
  TemplateClientAccessLevel,
  TemplateField,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '@core/api/templates-api.service';
import { ChartSpec, DateRange } from '@studio-shared/analytics/analytics.types';
import { ChartRendererComponent } from '@studio-shared/analytics/chart-renderer.component';
import { buildFieldCharts, numericFieldStats, NumericFieldStat } from '@studio-shared/analytics/graph-engine';
import { exportCsv, exportExcel, exportPdf, toTable } from '@studio-shared/analytics/export.util';
import { ReferencesAccordionComponent } from '@studio-shared/references-accordion/references-accordion.component';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

type DetailTab = 'overview' | 'references' | 'entries' | 'progress';

interface EntryAnswerDraft {
  key: string;
  label: string;
  value: string;
}

@Component({
  selector: 'app-professional-client-template',
  standalone: true,
  imports: [ChartRendererComponent, DatePipe, FormsModule, ReferencesAccordionComponent, RouterLink, ProfessionalPageShellComponent],
  templateUrl: './professional-client-template.component.html',
  styleUrl: './professional-client-template.component.scss'
})
export class ProfessionalClientTemplateComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly location = inject(Location);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly referencesApi = inject(ResourcesApiService);

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

  referenceCategories: ResourceCategoryRecord[] = [];
  referenceLibrary: ProfessionalResourceRecord[] = [];
  isShareDialogOpen = false;
  shareSelectedIds = new Set<number>();
  referenceSearch = '';
  isSavingShare = false;

  isSavingAccessLevel = false;
  readonly accessLevelOptions: { value: TemplateClientAccessLevel; label: string }[] = [
    { value: 'private', label: 'Private' },
    { value: 'view_only', label: 'View only' },
    { value: 'editable', label: 'Editable' }
  ];

  editingEntry: TrackingEntryRecord | null = null;
  entryDraftAnswers: EntryAnswerDraft[] = [];
  entryDraftNote = '';
  entryDraftDate = '';
  entryDraftTime = '';
  isSavingEntry = false;

  isAddEntryOpen = false;
  addEntryDate = '';
  addEntryAnswers: Record<string, string> = {};
  addEntryNote = '';

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.assignmentId = Number(this.route.snapshot.paramMap.get('assignmentId'));
    const requestedTab = this.route.snapshot.queryParamMap.get('tab') as DetailTab | null;

    if (requestedTab && ['overview', 'references', 'entries', 'progress'].includes(requestedTab)) {
      this.detailTab = requestedTab;
    }

    this.loadAll(this.route.snapshot.queryParamMap.get('share') === '1');
    this.loadProgress();
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

  // ----- analytics dashboard (graph engine) -----

  dateRange: DateRange = 30;
  isExportOpen = false;
  viewingEntry: TrackingEntryRecord | null = null;

  readonly rangeOptions: { value: DateRange; label: string }[] = [
    { value: 7, label: '7 Days' },
    { value: 30, label: '30 Days' },
    { value: 90, label: '90 Days' },
    { value: 0, label: 'All time' }
  ];

  setRange(range: DateRange): void {
    this.dateRange = range;
  }

  get templateStatus(): string {
    return this.template?.is_active === false ? 'Completed' : 'Active';
  }

  get fieldCharts(): ChartSpec[] {
    return this.template ? buildFieldCharts(this.template.fields, this.templateEntries, this.dateRange) : [];
  }

  get numericStats(): NumericFieldStat[] {
    return this.template ? numericFieldStats(this.template.fields, this.templateEntries) : [];
  }

  // ----- data-entries date filter -----
  entriesFrom = '';
  entriesTo = '';

  get filteredDataEntries(): TrackingEntryRecord[] {
    return this.templateEntries.filter((entry) => {
      if (this.entriesFrom && entry.entry_date < this.entriesFrom) {
        return false;
      }

      if (this.entriesTo && entry.entry_date > this.entriesTo) {
        return false;
      }

      return true;
    });
  }

  clearEntryFilter(): void {
    this.entriesFrom = '';
    this.entriesTo = '';
  }

  entryKeyValues(entry: TrackingEntryRecord): { label: string; value: string }[] {
    return (this.template?.fields || [])
      .filter((field) => field.field_type !== 'long_text')
      .map((field) => ({
        label: field.label,
        value: String(entry.answers?.[field.key || field.label] ?? '').trim() || '-'
      }));
  }

  isEntryEditable(entry: TrackingEntryRecord): boolean {
    if (!entry.created_at) {
      return true;
    }

    const age = Date.now() - new Date(entry.created_at).getTime();
    return age <= 72 * 60 * 60 * 1000;
  }

  viewEntry(entry: TrackingEntryRecord): void {
    this.viewingEntry = entry;
  }

  closeViewEntry(): void {
    this.viewingEntry = null;
  }

  toggleExport(): void {
    this.isExportOpen = !this.isExportOpen;
  }

  exportAs(format: 'csv' | 'excel' | 'pdf'): void {
    this.isExportOpen = false;
    const template = this.template;

    if (!template) {
      return;
    }

    const name = `${template.name.replace(/\s+/g, '-').toLowerCase()}-entries`;
    const table = toTable(template.fields, this.filteredDataEntries);

    if (format === 'csv') {
      exportCsv(name, table);
    } else if (format === 'excel') {
      void exportExcel(name, table);
    } else {
      exportPdf(name, `${template.name} - ${this.client?.first_name || ''} ${this.client?.last_name || ''}`.trim(), table);
    }
  }

  // ----- progress records (professional-written) -----

  progressEntries: ProgressEntry[] = [];
  isProgressFormOpen = false;
  isSavingProgress = false;
  editingProgressId: number | null = null;
  progressDraft = { title: '', date: '', notes: '', status: '', next_step: '' };

  loadProgress(): void {
    this.formsGroupsApi.getClientProgress(this.clientId).subscribe({
      next: (response) => (this.progressEntries = response.progress),
      error: () => (this.progressEntries = [])
    });
  }

  openProgressForm(): void {
    this.editingProgressId = null;
    this.progressDraft = { title: '', date: this.todayIso(), notes: '', status: '', next_step: '' };
    this.isProgressFormOpen = true;
  }

  editProgress(entry: ProgressEntry): void {
    this.editingProgressId = entry.id;
    this.progressDraft = {
      title: entry.title,
      date: entry.date,
      notes: entry.notes,
      status: entry.status,
      next_step: entry.next_step
    };
    this.isProgressFormOpen = true;
  }

  cancelProgress(): void {
    this.isProgressFormOpen = false;
    this.editingProgressId = null;
  }

  saveProgress(): void {
    if (!this.progressDraft.title.trim() || !this.progressDraft.date || this.isSavingProgress) {
      return;
    }

    this.isSavingProgress = true;
    const payload = {
      title: this.progressDraft.title.trim(),
      date: this.progressDraft.date,
      notes: this.progressDraft.notes.trim(),
      status: this.progressDraft.status.trim(),
      next_step: this.progressDraft.next_step.trim()
    };
    const request = this.editingProgressId
      ? this.formsGroupsApi.updateProgress(this.editingProgressId, payload)
      : this.formsGroupsApi.createProgress(this.clientId, payload);

    request.subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.isSavingProgress = false;
        this.isProgressFormOpen = false;
        this.editingProgressId = null;
        this.loadProgress();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Progress record could not be saved.');
        this.isSavingProgress = false;
      }
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
    this.shareSelectedIds = new Set((this.assignment?.resources || []).map((reference) => reference.id));
    this.referenceSearch = '';
  }

  closeShareDialog(): void {
    this.isShareDialogOpen = false;
    this.shareSelectedIds = new Set<number>();
  }

  toggleSharedReference(reference: ProfessionalResourceRecord): void {
    if (this.shareSelectedIds.has(reference.id)) {
      this.shareSelectedIds.delete(reference.id);
    } else {
      this.shareSelectedIds.add(reference.id);
    }
  }

  isSharedReference(reference: ProfessionalResourceRecord): boolean {
    return this.shareSelectedIds.has(reference.id);
  }

  get filteredReferenceLibrary(): ProfessionalResourceRecord[] {
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

  referencesForCategory(category: ResourceCategoryRecord): ProfessionalResourceRecord[] {
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

  // ----- client access level -----

  setAccessLevel(level: TemplateClientAccessLevel): void {
    const assignment = this.assignment;

    if (!assignment || assignment.client_access_level === level || this.isSavingAccessLevel) {
      return;
    }

    this.isSavingAccessLevel = true;
    this.templatesApi.updateAssignmentAccessLevel(this.clientId, assignment.id, level).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.assignment = response.assignment;
        this.isSavingAccessLevel = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Access level could not be updated.');
        this.isSavingAccessLevel = false;
      }
    });
  }

  // ----- entry editing -----

  startEntryEdit(entry: TrackingEntryRecord): void {
    if (!this.isEntryEditable(entry)) {
      this.messageType = 'error';
      this.message = 'This entry is older than 72 hours and can no longer be edited.';
      return;
    }

    this.viewingEntry = null;
    this.editingEntry = entry;
    this.entryDraftNote = entry.note;
    this.entryDraftDate = entry.entry_date;
    this.entryDraftTime = entry.entry_time || '';
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
    this.entryDraftDate = '';
    this.entryDraftTime = '';
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
    this.templatesApi
      .updateEntry(entry.id, {
        answers,
        note: this.entryDraftNote,
        entry_date: this.entryDraftDate,
        entry_time: this.entryDraftTime || null
      })
      .subscribe({
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

  ratingSteps(field: TemplateField): number[] {
    const scale = Math.min(10, Math.max(2, field.scale || 5));
    return Array.from({ length: scale }, (_value, index) => index + 1);
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
    this.referencesApi.getResources().subscribe({
      next: (response) => (this.referenceLibrary = response.resources),
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
}
