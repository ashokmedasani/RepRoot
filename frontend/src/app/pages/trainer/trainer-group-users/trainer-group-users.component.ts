import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessRecord,
  DynamicField,
  FormsGroupsApiService,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

type GroupTab = 'overview' | 'approved-users' | 'registration-form' | 'tracking-templates' | 'settings';

interface TrackingTemplateField {
  id?: string;
  label: string;
  type?: string;
  fieldType?: 'number' | 'short_text' | 'long_text' | 'yes_no' | 'image';
  required: boolean;
  placeholder?: string;
}

interface TrackingTemplate {
  id?: string;
  name: string;
  title?: string;
  cadence: string;
  purpose?: string;
  accent: string;
  fields: TrackingTemplateField[];
}

@Component({
  selector: 'app-trainer-group-users',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-group-users.component.html',
  styleUrl: './trainer-group-users.component.scss'
})
export class TrainerGroupUsersComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);

  group: TrainerGroup | null = null;
  clients: ClientAccessRecord[] = [];
  isLoading = true;
  message = '';
  messageType: 'success' | 'error' = 'success';
  activeTab: GroupTab = 'overview';
  searchTerm = '';
  statusFilter = 'all';
  groupDraft = {
    name: '',
    description: ''
  };
  resetPasswordResult = '';
  readonly tabs: { id: GroupTab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'approved-users', label: 'Approved Users' },
    { id: 'registration-form', label: 'Client Registration Form' },
    { id: 'tracking-templates', label: 'Tracking Templates' },
    { id: 'settings', label: 'Settings' }
  ];
  trackingTemplates: TrackingTemplate[] = [
    {
      name: 'Daily Tracking',
      cadence: 'Every day',
      accent: 'green',
      fields: [
        { label: 'Protein Intake (g)', type: 'Number', required: true },
        { label: 'Calories Intake', type: 'Number', required: true },
        { label: 'Water Intake (L)', type: 'Number', required: true },
        { label: 'Workout Completed', type: 'Yes / No', required: true },
        { label: 'Sleep Hours', type: 'Number', required: false },
        { label: 'Body Weight (kg)', type: 'Number', required: false }
      ]
    },
    {
      name: 'Weekly Tracking',
      cadence: 'Every week',
      accent: 'orange',
      fields: [
        { label: 'Weight Change (kg)', type: 'Number', required: false },
        { label: 'Progress Photo', type: 'Image', required: false },
        { label: 'Workout Performance', type: 'Short Text', required: false },
        { label: 'Strength Progress', type: 'Short Text', required: false },
        { label: 'Trainer Notes', type: 'Long Text', required: false }
      ]
    },
    {
      name: 'Monthly Tracking',
      cadence: 'Every month',
      accent: 'purple',
      fields: [
        { label: 'Body Measurements', type: 'Short Text', required: false },
        { label: 'Goal Review', type: 'Short Text', required: true },
        { label: 'Plan Adjustment', type: 'Long Text', required: false },
        { label: 'Monthly Photo', type: 'Image', required: false }
      ]
    }
  ];

  ngOnInit(): void {
    const groupId = Number(this.route.snapshot.paramMap.get('groupId'));
    const requestedTab = this.route.snapshot.queryParamMap.get('tab') as GroupTab | null;

    if (requestedTab && this.tabs.some((tab) => tab.id === requestedTab)) {
      this.activeTab = requestedTab;
    }

    this.loadGroup(groupId);
  }

  get activeClients(): ClientAccessRecord[] {
    return this.clients.filter((client) => client.is_active);
  }

  get pendingInvites(): number {
    return this.clients.filter((client) => client.must_change_password).length;
  }

  get filteredClients(): ClientAccessRecord[] {
    const searchTerm = this.searchTerm.trim().toLowerCase();

    return this.clients.filter((client) => {
      const matchesSearch =
        !searchTerm ||
        `${client.first_name} ${client.last_name}`.toLowerCase().includes(searchTerm) ||
        client.email.toLowerCase().includes(searchTerm) ||
        client.username.toLowerCase().includes(searchTerm);
      const matchesStatus =
        this.statusFilter === 'all' ||
        (this.statusFilter === 'active' && client.is_active) ||
        (this.statusFilter === 'pending' && client.must_change_password);

      return matchesSearch && matchesStatus;
    });
  }

  get registrationFields(): DynamicField[] {
    return this.group?.registration_form?.fields || [];
  }

  get customRegistrationFields(): DynamicField[] {
    return this.registrationFields.filter((field) => !field.is_core);
  }

  loadGroup(groupId: number): void {
    this.isLoading = true;
    this.formsGroupsApi.getGroupUsers(groupId).subscribe({
      next: (response) => {
        this.group = response.group;
        this.clients = response.clients;
        this.groupDraft = {
          name: response.group.name,
          description: response.group.description || ''
        };
        this.loadTrackingTemplates(response.group.id);
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.group = this.createFallbackGroup(groupId);
        this.clients = [];
        this.groupDraft = {
          name: this.group.name,
          description: ''
        };
        this.loadTrackingTemplates(groupId);
        this.messageType = 'error';
        this.message = `${this.formatApiError(error, 'Could not load live group details.')} Template preview is available offline.`;
        this.isLoading = false;
      }
    });
  }

  setTab(tab: GroupTab): void {
    this.activeTab = tab;
    this.resetPasswordResult = '';
  }

  saveGroup(): void {
    if (!this.group) {
      return;
    }

    this.formsGroupsApi.updateGroup(this.group.id, this.groupDraft.name, this.groupDraft.description).subscribe({
      next: (response) => {
        this.group = response.group;
        this.groupDraft = {
          name: response.group.name,
          description: response.group.description || ''
        };
        this.messageType = 'success';
        this.message = 'Group updated successfully.';
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Group could not be updated.');
      }
    });
  }

  resetClientPassword(client: ClientAccessRecord): void {
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
        this.message = this.formatApiError(error, 'Client password could not be reset.');
      }
    });
  }

  initials(client: ClientAccessRecord): string {
    return `${client.first_name.charAt(0)}${client.last_name.charAt(0)}`.toUpperCase();
  }

  fieldTypeLabel(field: TrackingTemplateField): string {
    const fieldType = field.fieldType || field.type?.toLowerCase().replace(/\s+/g, '_');
    const labels: Record<string, string> = {
      number: 'Number',
      short_text: 'Short Text',
      long_text: 'Long Text',
      yes_no: 'Yes / No',
      image: 'Image Upload'
    };

    return labels[fieldType || ''] || field.type || 'Field';
  }

  private loadTrackingTemplates(groupId: number): void {
    const savedTemplate = window.localStorage.getItem(`coachflow-tracking-template-${groupId}`);

    if (!savedTemplate) {
      return;
    }

    try {
      const parsedTemplate = JSON.parse(savedTemplate) as {
        sections?: Array<{
          id?: string;
          title?: string;
          name?: string;
          cadence: string;
          purpose?: string;
          accent: string;
          fields: TrackingTemplateField[];
        }>;
      };

      if (parsedTemplate.sections?.length) {
        this.trackingTemplates = parsedTemplate.sections.map((section) => ({
          id: section.id,
          name: section.title || section.name || 'Tracking Targets',
          title: section.title,
          cadence: section.cadence,
          purpose: section.purpose,
          accent: section.accent,
          fields: section.fields
        }));
      }
    } catch {
      window.localStorage.removeItem(`coachflow-tracking-template-${groupId}`);
    }
  }

  private createFallbackGroup(groupId: number): TrainerGroup {
    return {
      id: groupId,
      name: `Group ${groupId}`,
      description: '',
      has_registration_form: false,
      registration_form: null,
      created_at: '',
      updated_at: ''
    };
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
