import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  ClientAccessRecord,
  DynamicField,
  FormsGroupsApiService,
  GroupRegistrationSubmission,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';
import { ConfirmationDialogService } from '../../../shared/confirmation-dialog/confirmation-dialog.service';
import { FixedHeightListComponent } from '../../../shared/fixed-height-list/fixed-height-list.component';
import { formatApiError, initialsFor } from '../../../shared/utils/ui-helpers';

type GroupTab = 'overview' | 'approved-users' | 'registration-form' | 'settings';

@Component({
  selector: 'app-trainer-group-users',
  standalone: true,
  imports: [DatePipe, FormsModule, RouterLink, TrainerPageShellComponent, FixedHeightListComponent],
  templateUrl: './trainer-group-users.component.html',
  styleUrl: './trainer-group-users.component.scss'
})
export class TrainerGroupUsersComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  group: TrainerGroup | null = null;
  clients: ClientAccessRecord[] = [];
  registrationSubmissions: GroupRegistrationSubmission[] = [];
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
  isSettingsOpen = true;
  readonly tabs: { id: GroupTab; label: string }[] = [
    { id: 'overview', label: 'Overview' },
    { id: 'approved-users', label: 'Approved Users' },
    { id: 'registration-form', label: 'Client Registration Form' },
    { id: 'settings', label: 'Settings' }
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

  get recentApprovedUsers(): ClientAccessRecord[] {
    return this.activeClients.slice(0, 5);
  }

  get registrationFields(): DynamicField[] {
    return this.group?.registration_form?.fields || [];
  }

  get customRegistrationFields(): DynamicField[] {
    return this.registrationFields.filter((field) => !field.is_core);
  }

  get registrationLink(): string {
    const slug = this.group?.registration_form?.public_slug;
    return slug ? `${window.location.origin}/public/group-registration/${slug}` : '';
  }

  loadGroup(groupId: number): void {
    this.isLoading = true;
    this.formsGroupsApi.getGroupUsers(groupId).subscribe({
      next: (response) => {
        this.group = response.group;
        this.clients = response.clients;
        this.registrationSubmissions = response.registration_submissions || [];
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

  toggleSettings(): void {
    this.isSettingsOpen = !this.isSettingsOpen;
  }

  async resetClientPassword(client: ClientAccessRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Reset password for',
      target: `${client.first_name} ${client.last_name}`,
      impact: `You will set a new temporary password, which is emailed to ${client.email}. The client must change it at next login.`,
      confirmLabel: 'Reset Password'
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

    this.formsGroupsApi.resetClientPassword(client.id, entered.trim() || suggested).subscribe({
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

  copyRegistrationLink(): void {
    if (!this.registrationLink) {
      return;
    }

    void navigator.clipboard.writeText(this.registrationLink);
    this.messageType = 'success';
    this.message = 'Group registration form link copied.';
  }

  initials(client: ClientAccessRecord): string {
    return initialsFor(client.first_name, client.last_name);
  }
}
