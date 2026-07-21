import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  DynamicField,
  FormsGroupsApiService,
  GroupRegistrationSubmission,
  ProfessionalGroup
} from '@core/api/forms-groups-api.service';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-professional-manual-client-create',
  standalone: true,
  imports: [FormsModule, PasswordInputComponent, RouterLink, ProfessionalPageShellComponent],
  templateUrl: './professional-manual-client-create.component.html',
  styleUrl: './professional-manual-client-create.component.scss'
})
export class ProfessionalManualClientCreateComponent implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly api = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  groups: ProfessionalGroup[] = [];
  selectedGroupId: number | null = null;
  registrationSubmission: GroupRegistrationSubmission | null = null;
  answers: Record<string, string> = {};
  username = '';
  temporaryPassword = '';
  sendCredentials = true;
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';
  createdReferenceId = '';
  createdClientId = 0;
  private routeGroupId: number | null = null;
  private registrationSubmissionId: number | null = null;

  ngOnInit(): void {
    this.routeGroupId = Number(this.route.snapshot.paramMap.get('groupId')) ||
      Number(this.route.snapshot.queryParamMap.get('groupId')) || null;
    this.registrationSubmissionId = Number(this.route.snapshot.queryParamMap.get('registrationSubmissionId')) || null;
    this.generatePassword();
    this.api.getOverview().subscribe({
      next: (overview) => {
        this.groups = overview.groups.filter((group) => group.has_registration_form);
        this.selectedGroupId = this.routeGroupId || (this.groups.length === 1 ? this.groups[0].id : null);
        this.isLoading = false;
        this.loadRegistrationSubmission();
      },
      error: (error: unknown) => {
        this.isLoading = false;
        this.messageType = 'error';
        this.message = formatApiError(error, 'Groups could not be loaded.');
      }
    });
  }

  get selectedGroup(): ProfessionalGroup | null {
    return this.groups.find((group) => group.id === this.selectedGroupId) || null;
  }

  get fields(): DynamicField[] {
    return this.selectedGroup?.registration_form?.fields || [];
  }

  get groupLocked(): boolean {
    return Boolean(this.routeGroupId || this.registrationSubmissionId);
  }

  onGroupChange(): void {
    this.answers = {};
    this.registrationSubmission = null;
    this.createdReferenceId = '';
  }

  generatePassword(): void {
    const random = crypto.getRandomValues(new Uint32Array(2));
    this.temporaryPassword = `Cf!${random[0].toString(36)}${random[1].toString(36)}`.slice(0, 14);
  }

  fieldOptions(field: DynamicField): string[] {
    return field.options || [];
  }

  inputType(field: DynamicField): string {
    return ({ email: 'email', phone: 'tel', number: 'number', date: 'date' } as Record<string, string>)[field.field_type] || 'text';
  }

  async createClient(): Promise<void> {
    const group = this.selectedGroup;
    const email = String(this.answers['email'] || '').trim();

    if (!group || !this.username.trim() || !this.temporaryPassword || !email) {
      this.messageType = 'error';
      this.message = 'Group, client details, username, and temporary password are required.';
      return;
    }

    const confirmed = await this.confirmation.confirm({
      kind: this.sendCredentials ? 'send' : 'warning',
      title: this.sendCredentials ? 'Create client and send login credentials to' : 'Create client without emailing',
      target: email,
      impact: this.sendCredentials
        ? 'The client account will be created and the username and temporary password will be emailed.'
        : 'The account will be created, but you must deliver the temporary credentials separately.',
      confirmLabel: this.sendCredentials ? 'Create & Send' : 'Create Client'
    });

    if (!confirmed) {
      return;
    }

    this.isSaving = true;
    this.api.createManualClient({
      group_id: group.id,
      username: this.username.trim().toLowerCase(),
      password: this.temporaryPassword,
      confirm_password: this.temporaryPassword,
      registration_answers: this.answers,
      send_credentials: this.sendCredentials,
      registration_submission_id: this.registrationSubmission?.id || null
    }).subscribe({
      next: (response) => {
        this.createdReferenceId = response.client_access.reference_id;
        this.createdClientId = response.client_access.id;
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client account could not be created.');
        this.isSaving = false;
      }
    });
  }

  private loadRegistrationSubmission(): void {
    if (!this.registrationSubmissionId || !this.selectedGroupId) {
      return;
    }

    this.api.getGroupUsers(this.selectedGroupId).subscribe({
      next: (response) => {
        this.registrationSubmission = response.registration_submissions.find(
          (submission) => submission.id === this.registrationSubmissionId
        ) || null;

        if (this.registrationSubmission) {
          this.answers = { ...this.registrationSubmission.answers };
          this.username = this.suggestUsername(this.registrationSubmission.first_name, this.registrationSubmission.last_name);
        }
      }
    });
  }

  private suggestUsername(firstName: string, lastName: string): string {
    return `${firstName}.${lastName}`.toLowerCase().replace(/[^a-z0-9.]/g, '').slice(0, 24);
  }
}
