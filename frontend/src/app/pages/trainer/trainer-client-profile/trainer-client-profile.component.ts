import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ClientAccessDetailResponse,
  ClientAccessRecord,
  FormsGroupsApiService
} from '../../../core/api/forms-groups-api.service';
import {
  TemplateAssignmentRecord,
  TemplatesApiService,
  TrackingEntryRecord,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';
import { ChatPanelComponent } from '../../../shared/chat-panel/chat-panel.component';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

@Component({
  selector: 'app-trainer-client-profile',
  standalone: true,
  imports: [ChatPanelComponent, DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-client-profile.component.html',
  styleUrl: './trainer-client-profile.component.scss'
})
export class TrainerClientProfileComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);

  clientId = 0;
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

  entries: TrackingEntryRecord[] = [];

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
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

  unassignTemplate(assignment: TemplateAssignmentRecord, event: Event): void {
    event.stopPropagation();

    const confirmed = window.confirm(
      `Remove ${assignment.template_name} from this client? Past entries are kept, so nothing is lost.`
    );

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
