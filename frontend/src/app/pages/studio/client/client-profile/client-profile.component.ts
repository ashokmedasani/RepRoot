import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import { ClientApiService, ClientMeResponse } from '@core/api/client-api.service';
import {
  AdditionalInfoItem,
  ClientAccessRecord,
  ClientDetailChangeRequest,
  DynamicField,
  ProgressEntry
} from '@core/api/forms-groups-api.service';
import {
  TemplateField,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '@core/api/templates-api.service';
import { ChatPanelComponent } from '@studio-shared/chat-panel/chat-panel.component';
import { ClientPaymentsPanelComponent } from '@studio-shared/client-payments-panel/client-payments-panel.component';
import { ChartSpec } from '@studio-shared/analytics/analytics.types';
import { ChartRendererComponent } from '@studio-shared/analytics/chart-renderer.component';
import { buildFieldCharts, numericFieldStats, NumericFieldStat } from '@studio-shared/analytics/graph-engine';
import { ReferencesAccordionComponent } from '@studio-shared/references-accordion/references-accordion.component';
import { readImageAsDataUrl } from '@shared/utils/image-helpers';
import { formatApiError } from '@shared/utils/ui-helpers';
import { ClientPageShellComponent } from '@studio-shared/client-page-shell/client-page-shell.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { SupportIncidentsComponent } from '@studio-shared/support-incidents/support-incidents.component';

type PortalTab = 'details' | 'professional' | 'templates';
type ProfessionalTab = 'profile' | 'chat' | 'payments' | 'additional-details';
type TemplateTab = 'overview' | 'references' | 'data-entry' | 'progress';
type SettingsTab = 'account' | 'security' | 'legal' | 'support' | 'danger';

interface EntryDraft {
  entryDate: string;
  entryTime: string;
  answers: Record<string, string>;
  note: string;
}

@Component({
  selector: 'app-client-profile',
  standalone: true,
  imports: [ChartRendererComponent, ChatPanelComponent, ClientPageShellComponent, ClientPaymentsPanelComponent, DatePipe, FormsModule, PasswordInputComponent, ReferencesAccordionComponent, RouterLink, SupportIncidentsComponent],
  templateUrl: './client-profile.component.html',
  styleUrl: './client-profile.component.scss'
})
export class ClientProfileComponent implements OnInit {
  private readonly clientApi = inject(ClientApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly confirmation = inject(ConfirmationDialogService);

  client: ClientAccessRecord | null = null;
  me: ClientMeResponse | null = null;
  templates: TrackingTemplateRecord[] = [];
  entries: TrackingEntryRecord[] = [];
  progressEntries: ProgressEntry[] = [];
  drafts: Record<number, EntryDraft> = {};
  activeTab: PortalTab = 'details';
  professionalTab: ProfessionalTab = 'profile';
  templateTab: TemplateTab = 'overview';
  settingsTab: SettingsTab = 'account';
  selectedTemplateId: number | null = null;
  areTemplatesExpanded = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  savingTemplateId = 0;
  professionalPhotoFailed = false;

  changeRequest: ClientDetailChangeRequest | null = null;
  isEditingDetails = false;
  savingDetailEdit = false;
  editAnswers: Record<string, string> = {};
  editNote = '';
  deletionRequest: ClientDetailChangeRequest | null = null;
  deletionNote = '';
  isRequestingDeletion = false;
  isChangingPassword = false;
  readonly passwordForm = { currentPassword: '', password: '', confirmPassword: '' };

  readonly tabs: { id: PortalTab; label: string }[] = [
    { id: 'details', label: 'Settings' },
    { id: 'professional', label: 'Professional' },
    { id: 'templates', label: 'Templates' }
  ];
  readonly professionalTabs: { id: ProfessionalTab; label: string }[] = [
    { id: 'profile', label: 'Profile' },
    { id: 'chat', label: 'Chat' },
    { id: 'payments', label: 'Payments' }
  ];
  readonly settingsTabs: { id: SettingsTab; label: string }[] = [
    { id: 'account', label: 'Account' },
    { id: 'security', label: 'Security' },
    { id: 'legal', label: 'Privacy & Legal' },
    { id: 'support', label: 'Support' },
    { id: 'danger', label: 'Danger Zone' }
  ];
  readonly templateTabs: { id: TemplateTab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'references', label: 'References' },
    { id: 'data-entry', label: 'Data Entry' },
    { id: 'progress', label: 'Progress' }
  ];

  get professionalProfile() {
    return this.me?.professional_profile || null;
  }

  get sharedAdditionalInfo() {
    return this.me?.shared_additional_info || [];
  }

  ngOnInit(): void {
    const storedClient = window.sessionStorage.getItem('client-access');
    this.client = storedClient ? (JSON.parse(storedClient) as ClientAccessRecord) : null;

    if (this.client && window.sessionStorage.getItem('client-auth-token')) {
      this.loadPortal();
    }

    this.route.queryParamMap.subscribe((params) => {
      const tab = params.get('tab') as PortalTab | null;
      const professionalTab = params.get('professionalTab') as ProfessionalTab | null;

      if (tab && this.tabs.some((item) => item.id === tab)) {
        this.setTab(tab);
      }
      if (professionalTab && this.professionalTabs.some((item) => item.id === professionalTab)) {
        this.setProfessionalTab(professionalTab);
      }
    });
  }

  signOut(): void {
    window.sessionStorage.removeItem('client-access');
    window.sessionStorage.removeItem('client-auth-token');
    this.client = null;
    this.me = null;
    this.templates = [];
    this.entries = [];
    this.drafts = {};
  }

  setTab(tab: PortalTab): void {
    this.activeTab = tab;

    if (tab === 'templates') {
      this.areTemplatesExpanded = !this.areTemplatesExpanded || !this.selectedTemplateId;
      this.selectedTemplateId = this.selectedTemplate?.id || null;
    }
  }

  setProfessionalTab(tab: ProfessionalTab): void {
    this.professionalTab = tab;
  }

  setSettingsTab(tab: SettingsTab): void {
    this.settingsTab = tab;
  }

  setTemplateTab(tab: TemplateTab): void {
    this.templateTab = tab;
  }

  selectTemplate(template: TrackingTemplateRecord): void {
    this.activeTab = 'templates';
    this.areTemplatesExpanded = true;
    this.selectedTemplateId = template.id;
    this.templateTab = 'overview';
  }

  get selectedTemplate(): TrackingTemplateRecord | null {
    return this.templates.find((template) => template.id === this.selectedTemplateId) || this.templates[0] || null;
  }

  onPhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];

    if (!file) {
      return;
    }

    readImageAsDataUrl(file)
      .then((dataUrl) => {
        this.clientApi.updatePhoto(dataUrl).subscribe({
          next: (response) => {
            this.client = response.client;
            window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
            this.messageType = 'success';
            this.message = response.message;
          },
          error: (error: unknown) => {
            this.messageType = 'error';
            this.message = formatApiError(error, 'Photo could not be updated.');
          }
        });
      })
      .catch(() => {
        this.messageType = 'error';
        this.message = 'That image could not be used. Try a different photo.';
      });
  }

  draftFor(template: TrackingTemplateRecord): EntryDraft {
    if (!this.drafts[template.id]) {
      this.drafts[template.id] = {
        entryDate: this.todayIso(),
        entryTime: this.nowTime(),
        answers: {},
        note: ''
      };
    }

    return this.drafts[template.id];
  }

  entriesFor(template: TrackingTemplateRecord): TrackingEntryRecord[] {
    return this.entries.filter((entry) => entry.template === template.id);
  }

  recentEntriesFor(template: TrackingTemplateRecord): TrackingEntryRecord[] {
    return this.entriesFor(template).slice(0, 20);
  }

  entryCountFor(template: TrackingTemplateRecord): number {
    return this.entriesFor(template).length;
  }

  // Auto-generated charts for this template, using the shared graph engine.
  templateCharts(template: TrackingTemplateRecord): ChartSpec[] {
    const entries = this.entriesFor(template);
    return entries.length ? buildFieldCharts(template.fields, entries, 0) : [];
  }

  hasChartData(template: TrackingTemplateRecord): boolean {
    return this.templateCharts(template).length > 0;
  }

  numericStatsFor(template: TrackingTemplateRecord): NumericFieldStat[] {
    return numericFieldStats(template.fields, this.entriesFor(template)).filter((stat) => stat.hasData);
  }

  hasOverviewData(template: TrackingTemplateRecord): boolean {
    return this.numericStatsFor(template).length > 0 || this.hasChartData(template);
  }

  progressFor(_template: TrackingTemplateRecord): ProgressEntry[] {
    return this.progressEntries;
  }

  ratingSteps(field: TemplateField): number[] {
    const scale = Math.min(10, Math.max(2, field.scale || 5));
    return Array.from({ length: scale }, (_value, index) => index + 1);
  }

  // Backend never sends 'private' assignments to the client; templates are
  // editable unless the trainer has switched this one to view-only.
  isTemplateEditable(template: TrackingTemplateRecord): boolean {
    return (template.client_access_level || 'editable') !== 'view_only';
  }

  submitEntry(template: TrackingTemplateRecord): void {
    const draft = this.draftFor(template);

    if (!draft.entryDate || this.savingTemplateId || !this.isTemplateEditable(template)) {
      return;
    }

    this.savingTemplateId = template.id;

    const onSuccess = (message: string): void => {
      this.messageType = 'success';
      this.message = message;
      this.savingTemplateId = 0;
      this.editingEntryId = null;
      this.drafts[template.id] = { entryDate: this.todayIso(), entryTime: this.nowTime(), answers: {}, note: '' };
      this.loadEntries();
    };

    const onError = (error: unknown): void => {
      this.messageType = 'error';
      this.message = formatApiError(error, 'Entry could not be saved.');
      this.savingTemplateId = 0;
    };

    if (this.editingEntryId) {
      this.clientApi
        .updateEntry(this.editingEntryId, {
          answers: draft.answers,
          note: draft.note.trim(),
          entry_date: draft.entryDate,
          entry_time: draft.entryTime || this.nowTime()
        })
        .subscribe({ next: (response) => onSuccess(response.message), error: onError });
      return;
    }

    this.clientApi
      .submitEntry({
        template_id: template.id,
        entry_date: draft.entryDate,
        entry_time: draft.entryTime || this.nowTime(),
        answers: draft.answers,
        note: draft.note.trim()
      })
      .subscribe({ next: (response) => onSuccess(response.message), error: onError });
  }

  clearEntryForm(template: TrackingTemplateRecord): void {
    this.cancelEntryEdit(template);
  }

  editingEntryId: number | null = null;

  isEntryEditable(entry: TrackingEntryRecord): boolean {
    if (!entry.created_at) {
      return true;
    }

    return Date.now() - new Date(entry.created_at).getTime() <= 72 * 60 * 60 * 1000;
  }

  startEntryEdit(template: TrackingTemplateRecord, entry: TrackingEntryRecord): void {
    if (!this.isTemplateEditable(template)) {
      this.messageType = 'error';
      this.message = 'This template is view-only. You cannot edit entries.';
      return;
    }

    if (!this.isEntryEditable(entry)) {
      this.messageType = 'error';
      this.message = 'This entry is older than 72 hours and can no longer be edited.';
      return;
    }

    this.editingEntryId = entry.id;
    this.drafts[template.id] = {
      entryDate: entry.entry_date,
      entryTime: entry.entry_time || this.nowTime(),
      answers: { ...(entry.answers || {}) },
      note: entry.note || ''
    };
    this.messageType = 'success';
    this.message = 'Editing an existing entry. Update the values and submit to save.';
  }

  cancelEntryEdit(template: TrackingTemplateRecord): void {
    this.editingEntryId = null;
    this.drafts[template.id] = { entryDate: this.todayIso(), entryTime: this.nowTime(), answers: {}, note: '' };
  }

  answerSummary(entry: TrackingEntryRecord): string {
    const values = Object.values(entry.answers || {})
      .map((value) => String(value ?? '').trim())
      .filter((value) => value && !value.startsWith('data:image'));

    return values.slice(0, 3).join(' | ') || 'Submitted';
  }

  openInfoLink(item: AdditionalInfoItem): void {
    if (item.link) {
      window.open(item.link, '_blank', 'noopener,noreferrer');
    }
  }

  registrationAnswers(): { label: string; value: string }[] {
    if (!this.me) {
      return [];
    }

    return this.me.registration_fields.map((field) => {
      const key = field.key || field.label;
      const value = this.me?.client.registration_answers?.[key];

      return { label: field.label, value: value ? String(value) : 'Not added' };
    });
  }

  onProfessionalPhotoError(): void {
    this.professionalPhotoFailed = true;
  }

  otherRegistrationAnswers(): { label: string; value: string }[] {
    return this.registrationAnswers().filter((_answer, index) => !this.me?.registration_fields[index]?.is_core);
  }

  get middleName(): string {
    return String(this.client?.registration_answers?.['middle_name'] || 'Not added');
  }

  // Fields the client may propose edits to (core identity stays fixed).
  editableFields(): DynamicField[] {
    return (this.me?.registration_fields || []).filter((field) => !field.is_core);
  }

  get hasPendingChangeRequest(): boolean {
    return this.changeRequest?.status === 'pending';
  }

  startDetailEdit(): void {
    const current = this.me?.client.registration_answers || {};
    this.editAnswers = {};

    for (const field of this.editableFields()) {
      const key = field.key || field.label;
      this.editAnswers[key] = String(current[key] ?? '');
    }

    this.editNote = '';
    this.isEditingDetails = true;
  }

  cancelDetailEdit(): void {
    this.isEditingDetails = false;
    this.editAnswers = {};
    this.editNote = '';
  }

  submitDetailEdit(): void {
    if (this.savingDetailEdit) {
      return;
    }

    this.savingDetailEdit = true;
    this.clientApi.submitDetailChangeRequest(this.editAnswers, this.editNote.trim()).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.changeRequest = response.change_request;
        this.isEditingDetails = false;
        this.savingDetailEdit = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Edit request could not be submitted.');
        this.savingDetailEdit = false;
      }
    });
  }

  changePassword(): void {
    const { currentPassword, password, confirmPassword } = this.passwordForm;
    if (!currentPassword || !password || !confirmPassword) {
      this.messageType = 'error';
      this.message = 'Current password, new password, and confirmation are required.';
      return;
    }
    if (password !== confirmPassword) {
      this.messageType = 'error';
      this.message = 'New password and confirmation must match.';
      return;
    }
    this.isChangingPassword = true;
    this.clientApi.changePassword(currentPassword, password, confirmPassword).subscribe({
      next: (response) => {
        window.sessionStorage.removeItem('client-access');
        window.sessionStorage.removeItem('client-auth-token');
        window.sessionStorage.setItem('client-login-notice', response.message);
        void this.router.navigate(['/client/login']);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Password could not be changed.');
        this.isChangingPassword = false;
      }
    });
  }

  async requestAccountDeletion(): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Request account deletion for',
      target: this.client ? `${this.client.first_name} ${this.client.last_name}` : 'this account',
      impact: 'Your professional must approve this request. Approval disables login and preserves coaching records for audit and continuity.',
      confirmLabel: 'Send Request'
    });
    if (!confirmed) return;

    this.isRequestingDeletion = true;
    this.clientApi.requestAccountDeletion(this.deletionNote.trim()).subscribe({
      next: (response) => {
        this.deletionRequest = response.deletion_request;
        this.messageType = 'success';
        this.message = response.message;
        this.isRequestingDeletion = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Account deletion request could not be sent.');
        this.isRequestingDeletion = false;
      }
    });
  }

  withdrawAccountDeletionRequest(): void {
    this.clientApi.withdrawAccountDeletionRequest().subscribe({
      next: (response) => {
        this.deletionRequest = null;
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'The request could not be withdrawn.');
      }
    });
  }

  detailFieldOptions(field: DynamicField): string[] {
    if (field.field_type === 'yes_no') {
      return ['Yes', 'No'];
    }

    if (['dropdown', 'radio', 'checkbox'].includes(field.field_type)) {
      return field.options || [];
    }

    return [];
  }

  detailInputType(field: DynamicField): string {
    if (field.field_type === 'number') {
      return 'number';
    }

    if (field.field_type === 'date') {
      return 'date';
    }

    if (field.field_type === 'phone') {
      return 'tel';
    }

    if (field.field_type === 'email') {
      return 'email';
    }

    return 'text';
  }

  private loadPortal(): void {
    this.clientApi.getMe().subscribe({
      next: (response) => {
        this.me = response;
        this.client = response.client;
        this.professionalPhotoFailed = false;
        window.sessionStorage.setItem('client-access', JSON.stringify(response.client));
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Your profile could not be loaded.');
      }
    });
    this.clientApi.getTemplates().subscribe({
      next: (response) => {
        this.templates = response.templates;
        this.selectedTemplateId = response.templates[0]?.id || null;
      },
      error: () => {
        this.templates = [];
        this.selectedTemplateId = null;
      }
    });
    this.clientApi.getDetailChangeRequest().subscribe({
      next: (response) => {
        this.changeRequest = response.change_request;
      },
      error: () => {
        this.changeRequest = null;
      }
    });
    this.clientApi.getAccountDeletionRequest().subscribe({
      next: (response) => (this.deletionRequest = response.deletion_request),
      error: () => (this.deletionRequest = null)
    });
    this.loadEntries();
    this.loadProgress();
  }

  private loadEntries(): void {
    this.clientApi.getEntries().subscribe({
      next: (response) => {
        this.entries = response.entries;
      },
      error: () => {
        this.entries = [];
      }
    });
  }

  private loadProgress(): void {
    this.clientApi.getProgress().subscribe({
      next: (response) => {
        this.progressEntries = response.progress;
      },
      error: () => {
        this.progressEntries = [];
      }
    });
  }

  private todayIso(): string {
    return new Date().toISOString().slice(0, 10);
  }

  private nowTime(): string {
    const now = new Date();
    return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  }
}
