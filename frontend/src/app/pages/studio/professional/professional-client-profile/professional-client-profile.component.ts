import { DatePipe } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { finalize } from 'rxjs';

import {
  AdditionalInfoItem,
  AdditionalInfoType,
  ClientAccessDetailResponse,
  ClientAccessRecord,
  ClientReminder,
  FormsGroupsApiService
} from '../../../core/api/forms-groups-api.service';
import { ReferencesApiService, TrainerReferenceRecord } from '../../../core/api/references-api.service';
import {
  TemplateAssignmentRecord,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { ChatPanelComponent } from '../../../shared/chat-panel/chat-panel.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { readImageAsDataUrl } from '../../../shared/utils/image-helpers';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';
import { ConfirmationDialogService } from '../../../shared/confirmation-dialog/confirmation-dialog.service';
import { ChatApiService } from '../../../core/api/chat-api.service';

@Component({
  selector: 'app-trainer-client-profile',
  standalone: true,
  imports: [ChatPanelComponent, DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-profile.component.html',
  styleUrl: './trainer-client-profile.component.scss'
})
export class TrainerClientProfileComponent implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly referencesApi = inject(ReferencesApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly changeDetector = inject(ChangeDetectorRef);
  private readonly chatApi = inject(ChatApiService);

  clientId = 0;
  profile: ClientAccessDetailResponse | null = null;
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  resetPasswordResult = '';
  isAccountDialogOpen = false;
  isEditingClientInfo = false;
  isSavingClientInfo = false;
  clientInfoDraft = {
    first_name: '',
    last_name: '',
    email: '',
    username: '',
    is_active: true,
    registration_answers: {} as Record<string, string>
  };

  trainerNotes = '';
  notesUpdatedAt: string | null = null;
  isEditingNotes = false;
  notesDraft = '';
  isSavingNotes = false;

  assignments: TemplateAssignmentRecord[] = [];
  templates: TrackingTemplateRecord[] = [];
  selectedTemplateId: number | null = null;
  isAssigning = false;

  entries: TrackingEntryRecord[] = [];

  changeReviewNote = '';
  isReviewingChange = false;

  referenceLibrary: TrainerReferenceRecord[] = [];
  isSavingAdditional = false;
  newInfo: {
    title: string;
    type: AdditionalInfoType;
    visibility: 'private' | 'client';
    text: string;
    link: string;
    reference_id: string;
  } = {
    title: '',
    type: 'text',
    visibility: 'private',
    text: '',
    link: '',
    reference_id: ''
  };

  workspaceTab: 'workspace' | 'chat' | 'actions' = 'workspace';
  chatUnreadCount = 0;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  reminders: ClientReminder[] = [];
  isSavingReminder = false;
  reminderDraft = { title: '', date: '', time: '', notes: '', notify_trainer: true };

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.loadProfile();
    this.loadReminders();
    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  selectWorkspaceTab(tab: 'workspace' | 'chat' | 'actions'): void {
    this.workspaceTab = tab;
    if (tab === 'chat') {
      this.chatUnreadCount = 0;
    }
  }

  chatBadgeLabel(): string {
    return this.chatUnreadCount > 99 ? '99+' : String(this.chatUnreadCount);
  }

  private loadUnreadMessages(): void {
    this.chatApi.getTrainerUnreadCounts().subscribe({
      next: (summary) => (this.chatUnreadCount = summary.by_client[String(this.clientId)] || 0),
      error: () => (this.chatUnreadCount = 0)
    });
  }

  // ----- follow-up scheduler -----

  loadReminders(): void {
    this.formsGroupsApi.getClientReminders(this.clientId).subscribe({
      next: (response) => (this.reminders = response.reminders),
      error: () => (this.reminders = [])
    });
  }

  addReminder(): void {
    if (!this.reminderDraft.title.trim() || !this.reminderDraft.date || this.isSavingReminder) {
      this.messageType = 'error';
      this.message = 'A reminder needs a title and date.';
      return;
    }

    this.isSavingReminder = true;
    this.formsGroupsApi
      .createClientReminder(this.clientId, {
        title: this.reminderDraft.title.trim(),
        date: this.reminderDraft.date,
        time: this.reminderDraft.time || null,
        notes: this.reminderDraft.notes.trim(),
        notify_trainer: this.reminderDraft.notify_trainer
      })
      .subscribe({
        next: (response) => {
          this.messageType = 'success';
          this.message = response.message;
          this.isSavingReminder = false;
          this.reminderDraft = { title: '', date: '', time: '', notes: '', notify_trainer: true };
          this.loadReminders();
        },
        error: (error: unknown) => {
          this.messageType = 'error';
          this.message = formatApiError(error, 'Reminder could not be saved.');
          this.isSavingReminder = false;
        }
      });
  }

  async completeReminder(reminder: ClientReminder): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'complete',
      title: 'Mark schedule complete',
      target: reminder.title,
      impact: 'This schedule will move to the completed history for this client.',
      confirmLabel: 'Mark Complete'
    });
    if (!confirmed) return;

    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => this.loadReminders(),
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Reminder could not be updated.');
      }
    });
  }

  async deleteReminder(reminder: ClientReminder): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete schedule',
      target: reminder.title,
      impact: 'This scheduled item will be permanently removed.',
      confirmLabel: 'Delete Schedule'
    });
    if (!confirmed) return;

    this.formsGroupsApi.deleteReminder(reminder.id).subscribe({
      next: () => this.loadReminders(),
      error: () => this.loadReminders()
    });
  }

  // ----- additional information visibility (section-level) -----

  get additionalShared(): boolean {
    return this.client?.additional_info_shared || false;
  }

  setAdditionalShared(shared: boolean): void {
    if (this.additionalShared === shared || this.isSavingAdditional) {
      return;
    }

    const previousClient = this.client;
    if (!previousClient) {
      return;
    }

    this.replaceClient({ ...previousClient, additional_info_shared: shared });
    this.isSavingAdditional = true;
    this.formsGroupsApi.updateClientAdditionalInfo(this.clientId, this.additionalItems, shared).pipe(
      finalize(() => (this.isSavingAdditional = false))
    ).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
      },
      error: (error: unknown) => {
        this.replaceClient(previousClient);
        this.messageType = 'error';
        this.message = formatApiError(error, 'Visibility could not be updated.');
      }
    });
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

  onPhotoSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    const client = this.client;

    if (!file || !client) {
      return;
    }

    readImageAsDataUrl(file)
      .then((dataUrl) => this.saveClientPhoto(dataUrl))
      .catch(() => {
        this.messageType = 'error';
        this.message = 'That image could not be used. Try a different photo.';
      });
  }

  private saveClientPhoto(photo: string): void {
    this.formsGroupsApi.updateClientPhoto(this.clientId, photo).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client photo could not be updated.');
      }
    });
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

  clientInformationRows(): { label: string; value: string; readonly?: boolean }[] {
    const client = this.client;
    const profile = this.profile;

    if (!client || !profile) {
      return [];
    }

    const rows = [
      { label: 'First Name', value: client.first_name },
      { label: 'Middle Name', value: this.registrationValue(['middle']) },
      { label: 'Last Name', value: client.last_name },
      { label: 'Email Address', value: client.email },
      { label: 'Username', value: client.username },
      { label: 'Trainer Code', value: client.trainer_name },
      { label: 'Group', value: client.group_name },
      { label: 'Client Status', value: client.is_active ? 'Active' : 'Inactive' },
      { label: 'Joined Date', value: new Date(client.created_at).toLocaleDateString(), readonly: true },
      { label: 'Reference ID', value: client.reference_id, readonly: true }
    ];

    for (const field of profile.registration_fields || []) {
      if (field.is_core) {
        continue;
      }

      const key = field.key || field.label;
      rows.push({ label: field.label, value: String(client.registration_answers?.[key] ?? '') || 'Not added' });
    }

    return rows.filter((row) => row.label !== 'Middle Name' || row.value);
  }

  showAllClientInfo = false;

  /** Compact top section: a handful of key fields unless expanded. */
  visibleClientInfoRows(): { label: string; value: string; readonly?: boolean }[] {
    const rows = this.clientInformationRows();

    if (this.showAllClientInfo) {
      return rows;
    }

    const priority = ['Email Address', 'Username', 'Group', 'Client Status', 'Phone Number', 'Joined Date'];
    const prioritized = rows.filter((row) => priority.includes(row.label));
    return prioritized.length ? prioritized : rows.slice(0, 6);
  }

  get hiddenClientInfoCount(): number {
    return Math.max(0, this.clientInformationRows().length - this.visibleClientInfoRows().length);
  }

  toggleAllClientInfo(): void {
    this.showAllClientInfo = !this.showAllClientInfo;
  }

  startClientInfoEdit(): void {
    const client = this.client;

    if (!client) {
      return;
    }

    this.clientInfoDraft = {
      first_name: client.first_name,
      last_name: client.last_name,
      email: client.email,
      username: client.username,
      is_active: client.is_active,
      registration_answers: { ...(client.registration_answers || {}) }
    };
    this.isEditingClientInfo = true;
  }

  cancelClientInfoEdit(): void {
    this.isEditingClientInfo = false;
  }

  saveClientInfo(): void {
    if (this.isSavingClientInfo) {
      return;
    }

    this.isSavingClientInfo = true;
    this.formsGroupsApi.updateClientProfile(this.clientId, this.clientInfoDraft).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
        this.messageType = 'success';
        this.message = response.message;
        this.isEditingClientInfo = false;
        this.isSavingClientInfo = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client information could not be saved.');
        this.isSavingClientInfo = false;
      }
    });
  }

  editableRegistrationFields() {
    return (this.profile?.registration_fields || []).filter((field) => !field.is_core);
  }

  fieldOptions(field: { field_type: string; options?: string[] }): string[] {
    if (field.field_type === 'yes_no') {
      return ['Yes', 'No'];
    }

    if (['dropdown', 'radio', 'checkbox'].includes(field.field_type)) {
      return field.options || [];
    }

    return [];
  }

  inputType(field: { field_type: string }): string {
    if (field.field_type === 'number') return 'number';
    if (field.field_type === 'date') return 'date';
    if (field.field_type === 'phone') return 'tel';
    if (field.field_type === 'email') return 'email';
    return 'text';
  }

  private registrationValue(keywords: string[]): string {
    const answers = this.client?.registration_answers || {};

    for (const [key, value] of Object.entries(answers)) {
      if (keywords.some((keyword) => key.toLowerCase().includes(keyword)) && String(value ?? '').trim()) {
        return String(value).trim();
      }
    }

    return '';
  }

  // ----- detail change requests -----

  get pendingChangeRequest() {
    return this.profile?.pending_change_request || null;
  }

  changeRequestRows(): { label: string; oldValue: string; newValue: string }[] {
    const request = this.pendingChangeRequest;

    if (!request) {
      return [];
    }

    const current = this.client?.registration_answers || {};
    const fields = this.profile?.registration_fields || [];
    const labelByKey = new Map<string, string>();

    for (const field of fields) {
      labelByKey.set(field.key || field.label, field.label);
    }

    const rows: { label: string; oldValue: string; newValue: string }[] = [];

    for (const [key, value] of Object.entries(request.proposed_answers || {})) {
      if (['first_name', 'last_name', 'email'].includes(key)) {
        continue;
      }

      const oldValue = String(current[key] ?? '').trim();
      const newValue = String(value ?? '').trim();

      if (oldValue !== newValue) {
        rows.push({ label: labelByKey.get(key) || key.replace(/_/g, ' '), oldValue: oldValue || 'Not added', newValue: newValue || 'Not added' });
      }
    }

    return rows;
  }

  async reviewChangeRequest(action: 'approve' | 'reject'): Promise<void> {
    const request = this.pendingChangeRequest;

    if (!request || this.isReviewingChange) {
      return;
    }

    const clientName = `${this.client?.first_name || ''} ${this.client?.last_name || ''}`.trim();
    const confirmed = await this.confirmation.confirm({
      kind: action === 'approve' ? 'approve' : 'warning',
      title: action === 'approve' ? 'Approve changes for' : 'Reject changes for',
      target: clientName,
      impact: action === 'approve'
        ? 'The submitted profile changes will replace the current registration details.'
        : 'The submitted changes will be declined and the current details will remain.',
      confirmLabel: action === 'approve' ? 'Approve Changes' : 'Reject Changes'
    });
    if (!confirmed) return;

    this.isReviewingChange = true;
    this.formsGroupsApi.reviewChangeRequest(this.clientId, request.id, action, this.changeReviewNote.trim()).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.changeReviewNote = '';
        this.isReviewingChange = false;
        this.loadProfile();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Change request could not be processed.');
        this.isReviewingChange = false;
      }
    });
  }

  // ----- client account actions -----

  isUpdatingStatus = false;

  get isClientActive(): boolean {
    return this.client?.is_active ?? true;
  }

  async toggleClientStatus(): Promise<void> {
    const client = this.client;

    if (!client || this.isUpdatingStatus) {
      return;
    }

    const next = !client.is_active;
    const verb = next ? 'reactivate' : 'suspend';
    const confirmed = await this.confirmation.confirm({
      kind: next ? 'approve' : 'warning',
      title: next ? 'Reactivate' : 'Suspend',
      target: `${client.first_name} ${client.last_name}`,
      impact: next
        ? 'The client will be able to log in again.'
        : 'The client will lose login access until reactivated. No client data is deleted.',
      confirmLabel: next ? 'Reactivate Client' : 'Suspend Client'
    });

    if (!confirmed) {
      return;
    }

    this.isUpdatingStatus = true;
    this.formsGroupsApi.updateClientStatus(client.id, next).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
        this.messageType = 'success';
        this.message = response.message;
        this.isUpdatingStatus = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, `Could not ${verb} this client.`);
        this.isUpdatingStatus = false;
      }
    });
  }

  isResettingClient = false;
  isDeletingClient = false;

  async resetClient(): Promise<void> {
    const client = this.client;

    if (!client || this.isResettingClient) {
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Reset client data for',
      target: `${client.first_name} ${client.last_name}`,
      impact: 'Assignments, entries, chat, schedules, progress, additional information, and trainer notes will be cleared. Identity and registration details remain.',
      confirmLabel: 'Reset Client Data'
    });

    if (!confirmed) {
      return;
    }

    this.isResettingClient = true;
    this.formsGroupsApi.resetClient(client.id).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
        this.trainerNotes = '';
        this.notesUpdatedAt = null;
        this.messageType = 'success';
        this.message = response.message;
        this.isResettingClient = false;
        this.loadProfile();
        this.loadReminders();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client could not be reset.');
        this.isResettingClient = false;
      }
    });
  }

  async deleteClient(): Promise<void> {
    const client = this.client;

    if (!client || this.isDeletingClient) {
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Permanently delete',
      target: `${client.first_name} ${client.last_name}`,
      impact: 'Login, profile, templates, entries, chat, schedules, and notes will be erased. This cannot be undone.',
      confirmLabel: 'Delete Client'
    });

    if (!confirmed) {
      return;
    }

    this.isDeletingClient = true;
    this.formsGroupsApi.deleteClient(client.id).subscribe({
      next: () => {
        void this.router.navigate(['/trainer/clients']);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client could not be deleted.');
        this.isDeletingClient = false;
      }
    });
  }

  // ----- additional information -----

  get additionalItems(): AdditionalInfoItem[] {
    return this.client?.additional_info || [];
  }

  addAdditionalItem(): void {
    const title = this.newInfo.title.trim();

    if (!title) {
      this.messageType = 'error';
      this.message = 'Add a title for this item.';
      return;
    }

    const item: AdditionalInfoItem = {
      id: `item-${Date.now()}`,
      title,
      type: this.newInfo.type,
      visibility: this.newInfo.visibility
    };

    if (this.newInfo.type === 'text') {
      item.text = this.newInfo.text.trim();
    } else if (this.newInfo.type === 'link') {
      item.link = this.newInfo.link.trim();
    } else {
      const reference = this.referenceLibrary.find((ref) => ref.id === Number(this.newInfo.reference_id));

      if (!reference) {
        this.messageType = 'error';
        this.message = 'Pick a reference from your library.';
        return;
      }

      item.reference_id = reference.id;
      item.reference_title = reference.title;
      item.link = reference.link || reference.file_url || '';
    }

    this.persistAdditional([...this.additionalItems, item]);
    this.newInfo = { title: '', type: 'text', visibility: 'private', text: '', link: '', reference_id: '' };
  }

  async removeAdditionalItem(item: AdditionalInfoItem): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete additional information',
      target: item.title,
      impact: 'This item will be removed from the client profile.',
      confirmLabel: 'Delete Item'
    });
    if (!confirmed) return;

    this.persistAdditional(this.additionalItems.filter((current) => current.id !== item.id));
  }

  setAdditionalVisibility(item: AdditionalInfoItem, visibility: 'private' | 'client'): void {
    this.persistAdditional(
      this.additionalItems.map((current) => (current.id === item.id ? { ...current, visibility } : current))
    );
  }

  openInfoLink(item: AdditionalInfoItem): void {
    if (item.link) {
      window.open(item.link, '_blank', 'noopener,noreferrer');
    }
  }

  private persistAdditional(items: AdditionalInfoItem[]): void {
    if (this.isSavingAdditional) {
      return;
    }

    const previousClient = this.client;
    if (!previousClient) {
      return;
    }

    this.replaceClient({ ...previousClient, additional_info: items });
    this.isSavingAdditional = true;
    this.formsGroupsApi.updateClientAdditionalInfo(this.clientId, items).pipe(
      finalize(() => (this.isSavingAdditional = false))
    ).subscribe({
      next: (response) => {
        this.replaceClient(response.client);
        this.messageType = 'success';
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.replaceClient(previousClient);
        this.messageType = 'error';
        this.message = formatApiError(error, 'Additional information could not be saved.');
      }
    });
  }

  private replaceClient(client: ClientAccessRecord): void {
    if (this.profile) {
      this.profile = { ...this.profile, client };
      this.changeDetector.detectChanges();
    }
  }

  // ----- account dialog -----

  openAccountDialog(): void {
    this.isAccountDialogOpen = true;
  }

  closeAccountDialog(): void {
    this.isAccountDialogOpen = false;
  }

  async resetClientPassword(): Promise<void> {
    const client = this.client;

    if (!client) {
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: 'send',
      title: 'Reset password and send credentials to',
      target: client.email,
      impact: 'The client will receive a new temporary password and must change it at next login.',
      confirmLabel: 'Reset & Send'
    });

    if (!confirmed) {
      return;
    }

    // Option A: the trainer defines the temporary password, exactly like
    // manual client creation. A generated suggestion is offered as default.
    const suggested = this.generateTemporaryPassword();
    const entered = window.prompt(
      'Set the temporary password for this client (min 8 characters, 1 special character):',
      suggested
    );

    if (entered === null) {
      return;
    }

    const temporaryPassword = entered.trim() || suggested;

    this.formsGroupsApi.resetClientPassword(client.id, temporaryPassword).subscribe({
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

  private generateTemporaryPassword(): string {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    const random = new Uint32Array(9);
    crypto.getRandomValues(random);
    let value = '';
    random.forEach((n) => (value += alphabet[n % alphabet.length]));
    return `${value.slice(0, 8)}!${value.slice(8)}`;
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
    if (!this.client || this.isSavingNotes) {
      return;
    }

    this.isSavingNotes = true;
    this.formsGroupsApi.saveTrainerNotes(this.clientId, this.notesDraft.trim()).subscribe({
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

  openTemplatePage(assignment: TemplateAssignmentRecord, extras: Record<string, string> = {}): void {
    void this.router.navigate(['/trainer/clients', this.clientId, 'templates', assignment.id], {
      queryParams: extras
    });
  }

  assignTemplate(): void {
    if (!this.client || !this.selectedTemplateId || this.isAssigning) {
      return;
    }

    this.isAssigning = true;
    this.templatesApi.assignTemplate(this.clientId, this.selectedTemplateId).subscribe({
      next: (response) => {
        this.isAssigning = false;
        this.selectedTemplateId = null;
        this.openTemplatePage(response.assignment, { share: '1' });
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be assigned.');
        this.isAssigning = false;
      }
    });
  }

  async unassignTemplate(assignment: TemplateAssignmentRecord, event: Event): Promise<void> {
    event.stopPropagation();

    const confirmed = await this.confirmation.confirm({
      kind: 'archive',
      title: 'Remove assigned template',
      target: assignment.template_name,
      impact: 'The client will stop seeing this template. Past entries will be retained.',
      confirmLabel: 'Remove Template'
    });

    if (!confirmed) {
      return;
    }

    this.templatesApi.unassignTemplate(this.clientId, assignment.id).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = response.message;
        this.loadAssignments();
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Template could not be unassigned.');
      }
    });
  }

  // ----- activity -----

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
      this.openTemplatePage(assignment, { tab: 'entries' });
    }
  }

  // ----- loading -----

  private loadProfile(): void {
    this.isLoading = true;
    this.formsGroupsApi.getClientProfile(this.clientId).subscribe({
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
    this.loadAssignments();
    this.templatesApi.getClientEntries(this.clientId).subscribe({
      next: (response) => {
        this.entries = response.entries;
      },
      error: () => {
        this.entries = [];
      }
    });
    this.referencesApi.getReferences().subscribe({
      next: (response) => {
        this.referenceLibrary = response.references;
      },
      error: () => {
        this.referenceLibrary = [];
      }
    });
  }

  private loadAssignments(): void {
    this.templatesApi.getAssignments(this.clientId).subscribe({
      next: (response) => {
        this.assignments = response.assignments;
      },
      error: () => {
        this.assignments = [];
      }
    });
  }

  private todayIso(): string {
    return new Date().toISOString().slice(0, 10);
  }
}
