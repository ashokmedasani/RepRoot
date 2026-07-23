import { Component, ElementRef, OnDestroy, OnInit, ViewChild, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

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
export class ProfessionalManualClientCreateComponent implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly api = inject(FormsGroupsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  // The message banner renders at the top of a long, scrollable form while
  // the submit button is at the bottom — without this, a professional
  // watching the bottom of the screen sees no reaction to clicking submit
  // and may assume it silently failed (or, on success, not notice the
  // confirmation at all). Scrolling it into view on every result fixes both.
  @ViewChild('messageBanner') private messageBannerRef?: ElementRef<HTMLElement>;
  private redirectTimer?: ReturnType<typeof setTimeout>;

  groups: ProfessionalGroup[] = [];
  selectedGroupId: number | null = null;
  registrationSubmission: GroupRegistrationSubmission | null = null;
  answers: Record<string, string> = {};
  username = '';
  temporaryPassword = '';
  /**
   * 'send'   - create with portal access, email login details to the client
   * 'manual' - create with portal access, don't email (professional shares manually)
   * 'none'   - no portal access, just store the client's info
   */
  portalAccessMode: 'send' | 'manual' | 'none' = 'send';
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

  get hasPortalAccess(): boolean {
    return this.portalAccessMode !== 'none';
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

    if (!group || !email) {
      this.messageType = 'error';
      this.message = 'Group and client details are required.';
      return;
    }

    if (this.hasPortalAccess && (!this.username.trim() || !this.temporaryPassword)) {
      this.messageType = 'error';
      this.message = 'Username and temporary password are required to create portal access.';
      return;
    }

    const confirmed = await this.confirmation.confirm(
      this.portalAccessMode === 'send'
        ? {
            kind: 'send',
            title: 'Create client and send login credentials to',
            target: email,
            impact: 'The client account will be created and the username and temporary password will be emailed.',
            confirmLabel: 'Create & Send'
          }
        : this.portalAccessMode === 'manual'
        ? {
            kind: 'warning',
            title: 'Create client without emailing',
            target: email,
            impact: 'The account will be created, but you must deliver the temporary credentials separately.',
            confirmLabel: 'Create Client'
          }
        : {
            kind: 'warning',
            title: 'Create client record without portal access for',
            target: email,
            impact: 'Only the client’s info will be stored - no login will be created. You can grant portal access later from the client’s profile.',
            confirmLabel: 'Create Client'
          }
    );

    if (!confirmed) {
      return;
    }

    this.isSaving = true;
    this.api.createManualClient({
      group_id: group.id,
      has_portal_access: this.hasPortalAccess,
      ...(this.hasPortalAccess
        ? {
            username: this.username.trim().toLowerCase(),
            password: this.temporaryPassword,
            confirm_password: this.temporaryPassword,
            send_credentials: this.portalAccessMode === 'send'
          }
        : {}),
      registration_answers: this.answers,
      registration_submission_id: this.registrationSubmission?.id || null
    }).subscribe({
      next: (response) => {
        this.createdReferenceId = response.client_access.reference_id;
        this.createdClientId = response.client_access.id;
        this.messageType = 'success';
        this.message = response.message;
        this.isSaving = false;
        this.scrollToMessage();
        // Give the professional a moment to actually read the confirmation,
        // then move on to the new client's profile — leaving this page is
        // what actually prevents an accidental duplicate submission (the
        // submit button being disabled only helps if you're still here).
        this.redirectTimer = setTimeout(() => {
          this.router.navigate(['/professional/clients', this.createdClientId]);
        }, 1800);
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = formatApiError(error, 'Client account could not be created.');
        this.isSaving = false;
        this.scrollToMessage();
      }
    });
  }

  ngOnDestroy(): void {
    if (this.redirectTimer) {
      clearTimeout(this.redirectTimer);
    }
  }

  private scrollToMessage(): void {
    // behavior: 'auto' (not 'smooth') deliberately — the app's global smooth
    // scroll can jank badly on some pages, so error/success scrolling always
    // jumps instantly instead of animating.
    setTimeout(() => {
      this.messageBannerRef?.nativeElement?.scrollIntoView({ behavior: 'auto', block: 'start' });
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
