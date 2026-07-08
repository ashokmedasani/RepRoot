import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessRecord,
  DynamicField,
  FormsGroupsApiService,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';
import { TemplateFieldType, TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

type GroupTab = 'overview' | 'approved-users' | 'registration-form' | 'tracking-templates' | 'settings';

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
  private readonly templatesApi = inject(TemplatesApiService);

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
  trackingTemplates: TrackingTemplateRecord[] = [];

  ngOnInit(): void {
    const groupId = Number(this.route.snapshot.paramMap.get('groupId'));
    const requestedTab = this.route.snapshot.queryParamMap.get('tab') as GroupTab | null;

    if (requestedTab && this.tabs.some((tab) => tab.id === requestedTab)) {
      this.activeTab = requestedTab;
    }

    this.loadGroup(groupId);
    this.loadTrackingTemplates();
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
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.group = null;
        this.clients = [];
        this.messageType = 'error';
        this.message = formatApiError(error, 'Could not load group details.');
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
        this.message = formatApiError(error, 'Group could not be updated.');
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
        this.message = formatApiError(error, 'Client password could not be reset.');
      }
    });
  }

  initials(client: ClientAccessRecord): string {
    return initialsFor(client.first_name, client.last_name);
  }

  fieldTypeLabel(fieldType: TemplateFieldType): string {
    const labels: Record<TemplateFieldType, string> = {
      number: 'Number',
      short_text: 'Short Text',
      long_text: 'Long Text',
      yes_no: 'Yes / No',
      image: 'Image Upload'
    };

    return labels[fieldType] || 'Field';
  }

  cadenceLabel(cadence: string): string {
    return cadence ? `${cadence.charAt(0).toUpperCase()}${cadence.slice(1)} check-in` : 'Check-in';
  }

  private loadTrackingTemplates(): void {
    this.templatesApi.getTemplates().subscribe({
      next: (response) => {
        this.trackingTemplates = response.templates;
      },
      error: () => {
        this.trackingTemplates = [];
      }
    });
  }
}
