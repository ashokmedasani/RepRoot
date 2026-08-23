import { DatePipe, KeyValuePipe, SlicePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, HostListener, OnInit, ViewChild, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  DowngradeAssessment,
  ProfessionalAuthApiService,
  ProfessionalBillingStatus,
  ProfessionalDataUsageResponse,
  ProfessionalDataUsageSection,
  ProfessionalPlanCode,
  ProfessionalProfile,
  ProfessionalUpgradeTier,
  ProfessionalUsageLabel,
  RecycleBinItem,
  NotificationPreference
} from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ProfessionalProfileFormComponent } from '@studio-shared/professional-profile-form/professional-profile-form.component';
import { DeletionImpact, ProfessionalDeletionState, SigninDetails } from '@core/api/professional-auth-api.service';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { PasswordRequirementsComponent } from '@studio-shared/password-requirements/password-requirements.component';
import { isPasswordStrong } from '@studio-shared/password-requirements/password-requirements.util';
import { ThemeSwitcherComponent } from '@shared/theme-switcher/theme-switcher.component';
import { SupportIncidentsComponent } from '@studio-shared/support-incidents/support-incidents.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { ProfessionalPaymentSettingsComponent } from '../professional-payment-settings/professional-payment-settings.component';
import { GuideService } from '@core/guide/guide.service';

type SettingsSection =
  | 'my-account'
  | 'security'
  | 'billing'
  | 'payments'
  | 'notifications'
  | 'appearance'
  | 'storage'
  | 'guide'
  | 'support'
  | 'about';

@Component({
  selector: 'app-professional-account-settings',
  standalone: true,
  imports: [
    DatePipe,
    KeyValuePipe,
    SlicePipe,
    FormsModule,
    RouterLink,
    ProfessionalPageShellComponent,
    ProfessionalProfileFormComponent,
    PasswordInputComponent,
    PasswordRequirementsComponent,
    ThemeSwitcherComponent,
    SupportIncidentsComponent,
    ProfessionalPaymentSettingsComponent
  ],
  templateUrl: './professional-account-settings.component.html',
  styleUrl: './professional-account-settings.component.scss'
})
export class ProfessionalAccountSettingsComponent implements OnInit {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);
  private readonly route = inject(ActivatedRoute);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly guide = inject(GuideService);

  readonly appVersion = '1.0.0';
  readonly supportEmail = window.APP_CONFIG?.supportEmail || '';

  readonly menu: { id: SettingsSection; label: string }[] = [
    { id: 'my-account', label: 'My Account' },
    { id: 'security', label: 'Security' },
    { id: 'billing', label: 'Plan and Billing' },
    { id: 'payments', label: 'Payment Settings' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'appearance', label: 'Appearance' },
    // "Recycle Bin" is in the label because restoring a deleted group lives
    // inside this tab, and nobody looking for it would think to open something
    // called Data Usage.
    { id: 'storage', label: 'Data Usage and Recycle Bin' },
    { id: 'guide', label: 'Application Guide' },
    { id: 'support', label: 'Support' },
    { id: 'about', label: 'About' }
  ];

  /**
   * Ten tabs no longer fit on one line, and wrapping them onto a second row
   * made the whole bar read as two ragged half-rows. The first few stay
   * visible; the rest live behind "More".
   *
   * Six is not arbitrary: it is the last tab that fits before wrapping at the
   * common laptop width this is used at.
   */
  private readonly primaryTabCount = 6;

  isMoreMenuOpen = false;

  get primaryMenu(): { id: SettingsSection; label: string }[] {
    return this.menu.slice(0, this.primaryTabCount);
  }

  get overflowMenu(): { id: SettingsSection; label: string }[] {
    return this.menu.slice(this.primaryTabCount);
  }

  /** So the button reads "More" normally but names the section when the
   *  active one is hidden inside it -- otherwise the current tab looks
   *  unselected. */
  get overflowLabel(): string {
    const active = this.overflowMenu.find((item) => item.id === this.activeSection);
    return active ? active.label : 'More';
  }

  get isOverflowActive(): boolean {
    return this.overflowMenu.some((item) => item.id === this.activeSection);
  }

  /**
   * Opened on pointerdown rather than click. A click only fires once the
   * button is released, which on a trackpad is a noticeable beat after the
   * press -- the menu felt like it was thinking. The click handler still runs
   * afterwards, so it has to know the press already opened the menu and skip
   * its own toggle, or the menu would close again in the same gesture.
   */
  private openedOnPointerDown = false;

  openMoreMenu(event: Event): void {
    event.stopPropagation();
    if (this.isMoreMenuOpen) {
      return;
    }
    this.isMoreMenuOpen = true;
    this.openedOnPointerDown = true;
  }

  toggleMoreMenu(event: Event): void {
    event.stopPropagation();
    if (this.openedOnPointerDown) {
      this.openedOnPointerDown = false;
      return;
    }
    this.isMoreMenuOpen = !this.isMoreMenuOpen;
  }

  chooseOverflowSection(section: SettingsSection): void {
    this.isMoreMenuOpen = false;
    this.selectSection(section);
  }

  @HostListener('document:click')
  closeMoreMenu(): void {
    this.isMoreMenuOpen = false;
  }

  @HostListener('document:keydown.escape')
  closeMoreMenuOnEscape(): void {
    this.isMoreMenuOpen = false;
  }

  activeSection: SettingsSection = 'my-account';

  // The profile form owns its own edit state; the Edit button lives up here in
  // the section header, so the two have to talk.
  @ViewChild(ProfessionalProfileFormComponent) private profileFormRef?: ProfessionalProfileFormComponent;

  get isProfileEditing(): boolean {
    return this.profileFormRef?.isEditing ?? false;
  }

  startProfileEdit(): void {
    this.profileFormRef?.startEditing();
  }

  /** Read by unsavedChangesGuard when navigating away from this page. */
  hasPendingChanges(): boolean {
    return this.profileFormRef?.hasUnsavedChanges ?? false;
  }

  // ----------------------------------------------------------- sign-in details
  //
  // Username and email were previously not shown anywhere and not changeable at
  // all. Each is edited on its own, because an email change is a two-step
  // verified flow while a username change applies at once -- one shared Save
  // button would have to pretend they finish at the same moment.

  signinDetails: SigninDetails | null = null;
  editingSigninField: 'none' | 'username' | 'email' = 'none';
  usernameDraft = '';
  emailDraft = '';
  emailCodeDraft = '';
  isSigninBusy = false;
  signinMessage = '';
  signinMessageType: 'info' | 'error' = 'info';

  loadSigninDetails(): void {
    this.professionalAuthApi.getSigninDetails().subscribe({
      next: (details) => (this.signinDetails = details),
      error: () => (this.signinDetails = null)
    });
  }

  startUsernameEdit(): void {
    this.editingSigninField = 'username';
    this.usernameDraft = this.signinDetails?.username || '';
    this.signinMessage = '';
  }

  startEmailEdit(): void {
    this.editingSigninField = 'email';
    this.emailDraft = '';
    this.emailCodeDraft = '';
    this.signinMessage = '';
  }

  cancelSigninEdit(): void {
    this.editingSigninField = 'none';
    this.usernameDraft = '';
    this.emailDraft = '';
    this.emailCodeDraft = '';
    this.signinMessage = '';
  }

  private applySigninResult(details: SigninDetails, message: string, closeEditor = true): void {
    this.signinDetails = details;
    this.isSigninBusy = false;
    this.signinMessageType = 'info';
    this.signinMessage = message;
    if (closeEditor) {
      this.editingSigninField = 'none';
      this.usernameDraft = '';
      this.emailDraft = '';
      this.emailCodeDraft = '';
    }
  }

  private failSignin(error: unknown, fallback: string): void {
    this.isSigninBusy = false;
    this.signinMessageType = 'error';
    this.signinMessage = this.formatApiError(error, fallback);
  }

  saveUsername(): void {
    if (this.isSigninBusy || !this.usernameDraft.trim()) {
      return;
    }
    this.isSigninBusy = true;
    this.professionalAuthApi.changeUsername(this.usernameDraft.trim()).subscribe({
      next: (details) => {
        window.sessionStorage.setItem('professional-account-username', details.username);
        this.applySigninResult(details, 'Username updated.');
      },
      error: (error: unknown) => this.failSignin(error, 'The username could not be changed.')
    });
  }

  sendEmailChangeCode(): void {
    if (this.isSigninBusy || !this.emailDraft.trim()) {
      return;
    }
    this.isSigninBusy = true;
    this.professionalAuthApi.requestEmailChange(this.emailDraft.trim()).subscribe({
      // Editor stays open: the code goes to the new address and is entered here.
      next: (details) => this.applySigninResult(details, 'We sent a code to the new address. Enter it below.', false),
      error: (error: unknown) => this.failSignin(error, 'The verification code could not be sent.')
    });
  }

  confirmEmailChange(): void {
    if (this.isSigninBusy || !this.emailCodeDraft.trim()) {
      return;
    }
    this.isSigninBusy = true;
    this.professionalAuthApi.confirmEmailChange(this.emailCodeDraft.trim()).subscribe({
      next: (details) => this.applySigninResult(details, 'Email address updated. Sign in with it from now on.'),
      error: (error: unknown) => this.failSignin(error, 'That code could not be verified.')
    });
  }

  cancelPendingEmailChange(): void {
    this.isSigninBusy = true;
    this.professionalAuthApi.cancelEmailChange().subscribe({
      next: (details) => this.applySigninResult(details, 'Email change cancelled.'),
      error: (error: unknown) => this.failSignin(error, 'The email change could not be cancelled.')
    });
  }

  // ---------------------------------------------------------------- deletion
  //
  // Deliberately a sequence of small steps rather than one dialog with
  // everything in it. Each step asks for one decision, and the counts are shown
  // before any choice is made -- "12 client accounts" is the thing most likely
  // to change someone's mind, and it should not be buried under a confirm
  // button they are already reaching for.

  deletionStep: 'idle' | 'intent' | 'impact' | 'mode' | 'immediate' = 'idle';
  deletionState: ProfessionalDeletionState | null = null;
  deletionTypedIntent = '';
  deletionTypedImmediate = '';
  deletionAcknowledged = false;
  isDeletionBusy = false;
  deletionMessage = '';
  deletionMessageType: 'info' | 'error' = 'info';

  readonly deletionImpactLabels: { key: keyof DeletionImpact; label: string }[] = [
    { key: 'clients', label: 'Client accounts' },
    { key: 'client_groups', label: 'Client groups' },
    { key: 'lead_forms', label: 'Lead forms' },
    { key: 'resources', label: 'Resources' },
    { key: 'templates', label: 'Templates' },
    { key: 'tracking_entries', label: 'Tracking entries' },
    { key: 'messages', label: 'Messages' }
  ];

  /** The exact phrase required to skip the hold period. */
  readonly immediatePhrase = 'delete my professional account immediately';

  get isIntentTyped(): boolean {
    return this.deletionTypedIntent.trim().toUpperCase() === 'YES';
  }

  get isImmediatePhraseTyped(): boolean {
    return this.deletionTypedImmediate.trim().toLowerCase() === this.immediatePhrase;
  }

  loadDeletionState(): void {
    this.professionalAuthApi.getDeletionOverview().subscribe({
      next: (state) => (this.deletionState = state),
      error: () => (this.deletionState = null)
    });
  }

  beginDeletion(): void {
    this.deletionStep = 'intent';
    this.deletionTypedIntent = '';
    this.deletionTypedImmediate = '';
    this.deletionAcknowledged = false;
    this.deletionMessage = '';
    this.loadDeletionState();
  }

  abandonDeletion(): void {
    this.deletionStep = 'idle';
    this.deletionTypedIntent = '';
    this.deletionTypedImmediate = '';
    this.deletionAcknowledged = false;
    this.deletionMessage = '';
  }

  advanceToImpact(): void {
    if (this.isIntentTyped) {
      this.deletionStep = 'impact';
    }
  }

  advanceToMode(): void {
    if (this.deletionAcknowledged) {
      this.deletionStep = 'mode';
    }
  }

  chooseImmediate(): void {
    this.deletionStep = 'immediate';
    this.deletionTypedImmediate = '';
  }

  submitDeletion(mode: 'hold' | 'immediate'): void {
    if (this.isDeletionBusy) {
      return;
    }
    this.isDeletionBusy = true;
    this.deletionMessage = '';

    this.professionalAuthApi.requestAccountDeletion({
      mode,
      confirm_intent: this.deletionTypedIntent.trim(),
      acknowledged_impact: this.deletionAcknowledged,
      ...(mode === 'immediate' ? { confirm_immediate: this.deletionTypedImmediate.trim() } : {})
    }).subscribe({
      next: (state) => {
        this.deletionState = state;
        this.isDeletionBusy = false;
        this.deletionStep = 'idle';
        this.deletionMessageType = 'info';
        this.deletionMessage = state.message || 'Your request has been recorded.';
        if (mode === 'immediate') {
          // The account is gone; staying on a settings page for it makes no sense.
          window.sessionStorage.clear();
          void this.router.navigateByUrl('/professional/login');
        }
      },
      error: (error: unknown) => {
        this.isDeletionBusy = false;
        this.deletionMessageType = 'error';
        this.deletionMessage = this.formatApiError(error, 'The deletion request could not be completed.');
      }
    });
  }

  cancelScheduledDeletion(): void {
    this.isDeletionBusy = true;
    this.professionalAuthApi.cancelAccountDeletion().subscribe({
      next: (state) => {
        this.deletionState = state;
        this.isDeletionBusy = false;
        this.deletionMessageType = 'info';
        this.deletionMessage = state.message || 'Deletion cancelled.';
      },
      error: (error: unknown) => {
        this.isDeletionBusy = false;
        this.deletionMessageType = 'error';
        this.deletionMessage = this.formatApiError(error, 'The deletion could not be cancelled.');
      }
    });
  }
  isChangingPassword = false;
  accountMessage = '';
  accountMessageType: 'success' | 'error' = 'success';

  professionalCode = '';
  codeDraft = '';
  isSavingCode = false;
  codeMessage = '';
  codeMessageType: 'success' | 'error' = 'success';
  /** idle -> review (pick and check a code) -> confirm (type the phrase). */
  codeStep: 'idle' | 'review' | 'confirm' = 'idle';
  codeTypedConfirmation = '';
  codeConfirmationPhrase = 'APPROVED';
  codeAvailability: 'idle' | 'checking' | 'available' | 'taken' = 'idle';
  codeAvailabilityMessage = '';
  /** Emailing clients the new code is the only thing that stops them being
   *  locked out with no explanation, so it defaults on. */
  notifyClientsOfCodeChange = true;
  codeImpact: { clients_total: number; clients_with_access: number; clients_contactable: number } | null = null;
  private codeCheckTimer: ReturnType<typeof setTimeout> | null = null;
  private codeCheckRequest = 0;
  dataUsage?: ProfessionalDataUsageResponse;
  dataUsageError = '';

  billingStatus?: ProfessionalBillingStatus;
  billingError = '';
  isStartingCheckout = false;
  isOpeningPortal = false;
  isCancellingPlan = false;
  billingActionMessage = '';
  billingActionMessageType: 'success' | 'error' = 'success';

  // Premium professionals can choose Pro as a softer downgrade target
  // instead of dropping straight to Free. selectedAssessment mirrors
  // whichever target is currently chosen (Free's assessment ships inline
  // with billing status; Pro's is fetched on demand since it's a less
  // common path).
  downgradeTarget: 'starter_free' | 'pro' = 'starter_free';
  selectedAssessment?: DowngradeAssessment;
  isLoadingAssessment = false;

  onDowngradeTargetChange(target: 'starter_free' | 'pro'): void {
    this.downgradeTarget = target;
    if (target === 'starter_free') {
      this.selectedAssessment = this.billingStatus?.downgrade_assessment;
      return;
    }

    this.isLoadingAssessment = true;
    this.professionalAuthApi.getDowngradeAssessment(target).subscribe({
      next: (assessment) => {
        this.selectedAssessment = assessment;
        this.isLoadingAssessment = false;
      },
      error: () => {
        this.isLoadingAssessment = false;
      }
    });
  }

  readonly professionalUsageLabels: Record<string, string> = {
    professional_profile: 'Professional profile',
    forms_groups: 'Forms and groups',
    clients: 'Client profiles',
    schedules_progress: 'Schedules and progress',
    resources: 'Resources',
    templates_tracking: 'Templates and tracking',
    messages: 'Messages'
  };

  readonly recycleBinItems = signal<RecycleBinItem[]>([]);
  isLoadingRecycleBin = false;
  recycleBinMessage = '';
  recycleBinMessageType: 'success' | 'error' = 'success';
  restoringItemId: number | null = null;
  deletingItemId: number | null = null;

  /** The Application Guide lists exactly what the in-app guide knows, so the
   *  two can never describe the product differently. */
  get guidePages() {
    return this.guide.pages;
  }

  /** Replays the tour that runs once after a professional's first sign-in. */
  playWelcomeTour(): void {
    this.guide.startFullTour();
  }

  /** Walks just this page's steps, on the page itself. */
  playPageGuide(route: string): void {
    void this.router.navigate([route], { queryParams: { guide: '1' } });
  }


  readonly passwordForm = {
    password: '',
    confirmPassword: ''
  };

  notificationPreferences: NotificationPreference[] = [];
  notificationMessage = '';
  legalProfile: ProfessionalProfile | null = null;
  readonly notificationLabels: Record<string, string> = {
    chat: 'Client messages', forms: 'Form submissions', meetings: 'Meetings', clients: 'Client requests',
    templates: 'Templates', progress: 'Progress and tracking', reminders: 'Reminders', resources: 'Resources',
    payments: 'Payments', support: 'Support', account: 'Account lifecycle', storage: 'Storage usage',
    security: 'Security', system: 'System notices'
  };

  ngOnInit(): void {
    this.loadNotificationPrefs();
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
        this.legalProfile = profile;
        this.professionalCode = profile.professional_id || '';
        // The draft starts empty: it is a *new* code, not an edit of the
        // current one. Pre-filling it with today's value is what made the old
        // form look like a harmless text field.
        this.codeDraft = '';
        this.loadProfessionalCodeState();
      }
    });
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.dataUsage = usage),
      error: () => (this.dataUsageError = 'Storage usage is temporarily unavailable.')
    });
    this.loadRecycleBin();
    this.loadBillingStatus();
    this.loadDeletionState();
    this.loadSigninDetails();

    const sectionParam = this.route.snapshot.queryParamMap.get('section') as SettingsSection | null;
    if (sectionParam && this.menu.some((item) => item.id === sectionParam)) {
      this.activeSection = sectionParam;
    }

    const billingParam = this.route.snapshot.queryParamMap.get('billing');
    if (billingParam === 'success') {
      this.activeSection = 'billing';
      this.billingActionMessageType = 'success';
      this.billingActionMessage = 'Payment received — this can take a few seconds to reflect below while Stripe confirms it.';
    } else if (billingParam === 'cancelled') {
      this.activeSection = 'billing';
      this.billingActionMessageType = 'error';
      this.billingActionMessage = 'Checkout was cancelled — no charge was made.';
    }
  }

  async selectSection(id: SettingsSection): Promise<void> {
    // Leaving My Account mid-edit silently discards everything typed -- and
    // an uploaded photo looks saved until you come back and find it gone.
    // Tab changes are local state, not routing, so no route guard would ever
    // catch this.
    if (this.activeSection === 'my-account' && id !== 'my-account' && this.profileFormRef?.hasUnsavedChanges) {
      const leave = await this.confirmation.confirm({
        kind: 'warning',
        title: 'Leave without saving?',
        target: 'Your profile changes',
        impact: 'You have unsaved profile changes, including any photo you just added. Leaving this tab discards them.',
        confirmLabel: 'Discard changes'
      });
      if (!leave) {
        return;
      }
      this.profileFormRef.cancelEditing();
    }

    this.activeSection = id;

    // The Security tab shows deletion state, which can change from elsewhere
    // (the hold lapsing, support restoring the account), so refetch on open
    // rather than trusting whatever was loaded when the page first mounted.
    if (id === 'security') {
      this.loadDeletionState();
      this.loadSigninDetails();
    }
    // Billing state can change from outside this page (checkout redirect,
    // a plan change applied elsewhere) and was previously only ever fetched
    // once in ngOnInit, so switching into these tabs could show stale data
    // until a full page reload. Refetch every time the tab is opened.
    if (id === 'billing') {
      this.loadBillingStatus();
    } else if (id === 'storage') {
      this.refreshDataUsage();
    }
  }

  loadBillingStatus(): void {
    this.billingError = '';
    this.professionalAuthApi.getBillingStatus().subscribe({
      next: (status) => {
        this.billingStatus = status;
        this.selectedCurrency = status.billing_currency;
        this.downgradeTarget = 'starter_free';
        this.selectedAssessment = status.downgrade_assessment;
      },
      error: () => (this.billingError = 'Plan and billing details are temporarily unavailable.')
    });
  }

  private refreshDataUsage(): void {
    this.professionalAuthApi.invalidateDataUsage();
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.dataUsage = usage),
      error: () => (this.dataUsageError = 'Storage usage is temporarily unavailable.')
    });
  }

  loadRecycleBin(): void {
    this.isLoadingRecycleBin = true;
    this.professionalAuthApi.getRecycleBin().subscribe({
      next: (response) => {
        this.recycleBinItems.set(response.items);
        this.isLoadingRecycleBin = false;
      },
      error: () => {
        this.recycleBinMessageType = 'error';
        this.recycleBinMessage = 'Recycle Bin is temporarily unavailable.';
        this.isLoadingRecycleBin = false;
      }
    });
  }

  restoreRecycleBinItem(item: RecycleBinItem): void {
    this.recycleBinMessage = '';
    this.restoringItemId = item.id;
    this.professionalAuthApi.restoreRecycleBinItem(item.id).subscribe({
      next: () => {
        this.recycleBinMessageType = 'success';
        this.recycleBinMessage = `Restored "${item.title}".`;
        this.restoringItemId = null;
        this.loadRecycleBin();
        this.refreshDataUsage();
      },
      error: (error: unknown) => {
        this.recycleBinMessageType = 'error';
        this.recycleBinMessage = this.formatApiError(error, 'Could not restore this item.');
        this.restoringItemId = null;
      }
    });
  }

  async deleteRecycleBinItemPermanently(item: RecycleBinItem): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Delete permanently',
      target: item.title,
      impact: 'This cannot be undone — the item will no longer be restorable.',
      confirmLabel: 'Delete Permanently'
    });

    if (!confirmed) {
      return;
    }

    this.recycleBinMessage = '';
    this.deletingItemId = item.id;
    this.professionalAuthApi.deleteRecycleBinItemPermanently(item.id).subscribe({
      next: () => {
        this.recycleBinMessageType = 'success';
        this.recycleBinMessage = `Permanently deleted "${item.title}".`;
        this.deletingItemId = null;
        this.loadRecycleBin();
      },
      error: (error: unknown) => {
        this.recycleBinMessageType = 'error';
        this.recycleBinMessage = this.formatApiError(error, 'Could not permanently delete this item.');
        this.deletingItemId = null;
      }
    });
  }

  async cancelPlan(): Promise<void> {
    const assessment = this.selectedAssessment;
    if (!assessment) return;
    const targetName = assessment.target_tier_name || (this.downgradeTarget === 'pro' ? 'Pro' : 'Free');
    if (!assessment.storage.eligible) {
      this.billingActionMessageType = 'error';
      this.billingActionMessage = `Cancellation is blocked because storage is ${assessment.storage.free_tier_percent}% of the ${targetName} allowance. Contact ${assessment.support_email || 'support'}.`;
      return;
    }

    // Nothing here is ever deleted -- anything over the target plan's
    // limits simply locks (in priority order), and reverses automatically
    // on upgrade. The confirmation dialog spells out exactly what would
    // lock, by name, plus the category-cascade rule and which clients
    // would lose portal access -- no generic "may be deleted" copy, no
    // confirmation phrase to type.
    const lockLines = Object.entries(assessment.locks)
      .filter(([, info]) => info.locked_count > 0)
      .map(([key, info]) => {
        const label = this.lockSectionLabel(key);
        const names = info.locked_names.slice(0, 5).join(', ');
        const more = info.locked_count > info.locked_names.length ? '…' : '';
        return `${info.locked_count} ${label}${info.locked_count === 1 ? '' : 's'} would lock (${names}${more})`;
      });

    if (assessment.category_cascade_resource_count > 0) {
      lockLines.push(
        `${assessment.category_cascade_resource_count} resource${assessment.category_cascade_resource_count === 1 ? '' : 's'} would lock because the category they're in would lock, regardless of how many resources are in it`
      );
    }

    if (assessment.clients_losing_access_count > 0) {
      const clientNames = assessment.clients_losing_access.slice(0, 5).map((c) => `${c.client_name} (${c.group_name})`).join(', ');
      const more = assessment.clients_losing_access_count > 5 ? '…' : '';
      lockLines.push(
        `${assessment.clients_losing_access_count} client${assessment.clients_losing_access_count === 1 ? '' : 's'} would lose portal access until you upgrade again: ${clientNames}${more}`
      );
    }

    const impact = lockLines.length
      ? `Your paid access remains active until the expiry date, then the account moves to ${targetName}. Nothing is ever deleted. At that point: ${lockLines.join('; ')}.`
      : `Your paid access remains active until the expiry date, then the account moves to ${targetName}. Nothing is deleted, and your workspace already fits within the ${targetName} plan's limits.`;

    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Cancel plan',
      target: 'your current plan',
      impact,
      confirmLabel: 'Schedule cancellation'
    });

    if (!confirmed) {
      return;
    }

    this.billingActionMessage = '';
    this.isCancellingPlan = true;
    this.professionalAuthApi.cancelBillingPlan(this.downgradeTarget).subscribe({
      next: (response) => {
        this.billingActionMessageType = 'success';
        this.billingActionMessage = response.message;
        this.isCancellingPlan = false;
        this.loadBillingStatus();
        this.refreshDataUsage();
      },
      error: (error: unknown) => {
        this.billingActionMessageType = 'error';
        this.billingActionMessage = this.formatApiError(error, 'Could not cancel the plan.');
        this.isCancellingPlan = false;
      }
    });
  }

  private lockSectionLabel(key: string): string {
    const labels: Record<string, string> = {
      lead_forms: 'lead form',
      groups: 'group',
      templates: 'template',
      resources: 'resource',
      categories: 'category',
    };
    return labels[key] || key;
  }

  selectedBillingCycle = 'monthly';
  selectedCurrency: 'INR' | 'USD' = 'INR';

  // Regional formatting per currency - Indian grouping (lakh/crore) for INR,
  // standard grouping for USD. Backend stays the source of truth for the
  // actual amount and which currency applies (visitor-country detected,
  // see ProfessionalBillingStatusView); this only controls presentation.
  private static readonly CURRENCY_LOCALES: Record<'INR' | 'USD', string> = { INR: 'en-IN', USD: 'en-US' };

  formatPlanPrice(amount: number, currency: 'INR' | 'USD'): string {
    // Prices are deliberately .99-style (e.g. $5.99, $14.99) -- rounding to
    // whole currency here would silently turn $5.99 into $6 and $14.99 into
    // $15, which is exactly the wrong impression for psychological pricing.
    // Round trip through cents first so floating-point noise (e.g.
    // 29.949999999999996 from Decimal-to-number conversion) can't produce a
    // stray extra digit.
    const cents = Math.round(amount * 100) / 100;
    return new Intl.NumberFormat(ProfessionalAccountSettingsComponent.CURRENCY_LOCALES[currency], {
      style: 'currency',
      currency,
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    }).format(cents);
  }

  planPrice(billing: ProfessionalBillingStatus, code: ProfessionalPlanCode): string {
    if (code === 'starter_free' || code === 'starter') return this.formatPlanPrice(0, this.selectedCurrency);
    const tier = code === 'premium' ? 'premium_unlimited' : code;
    const value = billing.catalog?.trainer?.[tier as ProfessionalUpgradeTier]?.[this.selectedBillingCycle]?.[this.selectedCurrency];
    if (!value) return '—';
    return this.formatPlanPrice(Number(value), this.selectedCurrency);
  }

  // How much cheaper the selected cycle is than paying the monthly rate that
  // many times over -- six_months/yearly are already discounted server-side
  // (Pro: 5x monthly for 6 months, 10x for 12; same ratio for Premium) but
  // nothing surfaced that saving to the professional before now.
  cycleSavingsPercent(billing: ProfessionalBillingStatus, code: ProfessionalPlanCode): number {
    if (this.selectedBillingCycle === 'monthly') return 0;
    if (code === 'starter_free' || code === 'starter') return 0;
    const tier = code === 'premium' ? 'premium_unlimited' : code;
    const prices = billing.catalog?.trainer?.[tier as ProfessionalUpgradeTier];
    const monthly = Number(prices?.['monthly']?.[this.selectedCurrency]);
    const cyclePrice = prices?.[this.selectedBillingCycle];
    const selected = Number(cyclePrice?.[this.selectedCurrency]);
    const months = Number(cyclePrice?.['months']);
    if (!monthly || !selected || !months) return 0;
    const fullPriceForPeriod = monthly * months;
    return Math.round((1 - selected / fullPriceForPeriod) * 100);
  }

  storageLabel(bytes: number): string {
    if (bytes >= 1024 ** 3) return `${Math.round(bytes / 1024 ** 3)} GB`;
    return `${Math.round(bytes / 1024 ** 2)} MB`;
  }

  canUpgradePlan(billing: ProfessionalBillingStatus, code: ProfessionalPlanCode): boolean {
    if (!billing.payments_enabled || code === 'starter_free' || code === 'starter' || billing.plan.code === code) {
      return false;
    }
    const tier: ProfessionalUpgradeTier = code === 'premium' ? 'premium_unlimited' : code;
    return Boolean(billing.available_upgrades[tier]);
  }

  applyTemporaryPlan(code: ProfessionalPlanCode): void {
    const billing = this.billingStatus;
    const tier = code === 'premium' ? 'premium_unlimited' : code;
    if (
      !billing?.payments_enabled ||
      !billing.available_upgrades[tier as ProfessionalUpgradeTier] ||
      code === billing.plan.code ||
      this.isStartingCheckout
    ) return;
    void this.router.navigate(['/professional/subscription-payment'], {
      queryParams: { plan: code, cycle: this.selectedBillingCycle }
    });
  }

  openBillingPortal(): void {
    if (!this.billingStatus?.payments_enabled) return;
    this.billingActionMessage = '';
    this.isOpeningPortal = true;
    this.professionalAuthApi.createBillingPortal().subscribe({
      next: (response) => {
        window.location.href = response.portal_url;
      },
      error: (error: unknown) => {
        this.billingActionMessageType = 'error';
        this.billingActionMessage = this.formatApiError(error, 'Could not open the billing portal.');
        this.isOpeningPortal = false;
      }
    });
  }

  usageRows(
    sections: Record<string, ProfessionalDataUsageSection> | undefined,
    labels: Record<string, string>
  ): { key: string; label: string; usage: ProfessionalDataUsageSection }[] {
    return Object.entries(sections || {}).map(([key, usage]) => ({
      key,
      label: labels[key] || key.replaceAll('_', ' '),
      usage
    }));
  }

  private readonly usageLabelCopy: Partial<Record<ProfessionalUsageLabel, string>> = {
    plenty_of_room: 'Plenty of room to grow',
    comfortable: 'Comfortable usage',
    filling_up: 'Filling up — worth a look',
    almost_full: 'Almost full',
    over_capacity: 'Over your plan’s capacity'
  };

  usageLabelText(label: ProfessionalUsageLabel | undefined): string {
    return label ? this.usageLabelCopy[label] || '' : '';
  }

  storageSize(bytes: number): string {
    return bytes >= 1024 ** 3 ? `${bytes / 1024 ** 3} GB` : `${Math.round(bytes / 1024 ** 2)} MB`;
  }

  gracePeriodDaysLeft(endsAt: string | null): number {
    if (!endsAt) return 0;
    const diffMs = new Date(endsAt).getTime() - Date.now();
    return Math.max(0, Math.ceil(diffMs / (24 * 60 * 60 * 1000)));
  }

  lockReasonText(reason: string): string {
    if (reason === 'overage_grace_expired' || reason === 'overage') {
      return 'your storage usage went over your plan’s limit and the grace period ended';
    }
    return reason ? reason.replaceAll('_', ' ') : 'an account issue';
  }

  /** mailto link for the Support section, pre-filled per intent. */
  supportMailto(subject: string, body = ''): string {
    const params = new URLSearchParams({ subject });
    if (body) {
      params.set('body', body);
    }
    return `mailto:${this.supportEmail}?${params.toString()}`;
  }

  private loadNotificationPrefs(): void {
    this.professionalAuthApi.getNotificationPreferences().subscribe({
      next: ({ categories }) => (this.notificationPreferences = categories),
      error: () => (this.notificationMessage = 'Notification preferences are temporarily unavailable.')
    });
  }

  saveNotificationPreference(preference: NotificationPreference): void {
    this.notificationMessage = 'Saving…';
    this.professionalAuthApi.updateNotificationPreference(preference).subscribe({
      next: (saved) => {
        this.notificationPreferences = this.notificationPreferences.map((item) => item.category === saved.category ? saved : item);
        this.notificationMessage = 'Notification preference saved.';
      },
      error: () => {
        this.notificationMessage = 'Could not save this preference.';
        this.loadNotificationPrefs();
      }
    });
  }

  setAllNotificationChannel(channel: 'in_app_enabled' | 'email_enabled', enabled: boolean): void {
    this.notificationPreferences = this.notificationPreferences.map((item) => ({ ...item, [channel]: enabled || item.mandatory_in_app && channel === 'in_app_enabled' }));
    this.notificationMessage = 'Saving notification preferences…';
    let remaining = this.notificationPreferences.length;
    for (const preference of this.notificationPreferences) {
      this.professionalAuthApi.updateNotificationPreference(preference).subscribe({
        next: () => { if (--remaining === 0) this.notificationMessage = 'All notification preferences saved.'; },
        error: () => { this.notificationMessage = 'Some preferences could not be saved. Please try again.'; }
      });
    }
  }

  isCodeCopied = false;

  copyProfessionalCode(): void {
    void navigator.clipboard.writeText(this.professionalCode).then(() => {
      this.isCodeCopied = true;
      setTimeout(() => (this.isCodeCopied = false), 2000);
    });
  }

  // --- Changing the professional code ------------------------------------
  //
  // Staged the same way account deletion is, and for the same reason: this is
  // a destructive, client-facing change that used to happen on one click.
  // Clients sign in with this code plus their own username, and nothing tells
  // them it changed -- so the old flow locked every one of them out silently.
  // Each step states a consequence, and the last one has to be typed out.

  beginCodeChange(): void {
    this.codeStep = 'review';
    this.codeDraft = '';
    this.codeTypedConfirmation = '';
    this.codeMessage = '';
    this.codeAvailability = 'idle';
    this.codeAvailabilityMessage = '';
  }

  abandonCodeChange(): void {
    this.codeStep = 'idle';
    this.codeDraft = '';
    this.codeTypedConfirmation = '';
    this.codeMessage = '';
    this.codeAvailability = 'idle';
    this.codeAvailabilityMessage = '';
  }

  /** Format rules, checked as they type rather than on submit. */
  get codeFormatError(): string {
    const code = this.codeDraft.trim();
    if (!code) {
      return '';
    }
    if (code.length < 4 || code.length > 32) {
      return 'Use between 4 and 32 characters.';
    }
    if (!/^[A-Za-z0-9_-]+$/.test(code)) {
      return 'Letters, numbers, hyphens and underscores only.';
    }
    if (code.toLowerCase() === this.professionalCode.toLowerCase()) {
      return 'That is already your code.';
    }
    return '';
  }

  get normalizedCodeDraft(): string {
    return this.codeDraft.trim().toLowerCase();
  }

  get canReviewCode(): boolean {
    return Boolean(this.codeDraft.trim()) && !this.codeFormatError && this.codeAvailability === 'available';
  }

  get isCodeConfirmationTyped(): boolean {
    return this.codeTypedConfirmation.trim().toUpperCase() === this.codeConfirmationPhrase;
  }

  onCodeDraftChange(): void {
    this.codeAvailability = 'idle';
    this.codeAvailabilityMessage = '';
    this.codeMessage = '';

    if (this.codeCheckTimer) {
      clearTimeout(this.codeCheckTimer);
    }

    if (this.codeFormatError || !this.codeDraft.trim()) {
      return;
    }

    const candidate = this.normalizedCodeDraft;
    const requestId = ++this.codeCheckRequest;
    this.codeAvailability = 'checking';
    this.codeCheckTimer = setTimeout(() => {
      this.professionalAuthApi.checkProfessionalCode(candidate).subscribe({
        next: (result) => {
          // Ignore a reply for a code they have since typed past.
          if (requestId !== this.codeCheckRequest || candidate !== this.normalizedCodeDraft) {
            return;
          }
          this.codeAvailability = result.available ? 'available' : 'taken';
          this.codeAvailabilityMessage = result.message;
        },
        error: () => {
          if (requestId !== this.codeCheckRequest) {
            return;
          }
          this.codeAvailability = 'idle';
          this.codeAvailabilityMessage = '';
        }
      });
    }, 400);
  }

  advanceToCodeConfirm(): void {
    if (!this.canReviewCode) {
      return;
    }
    this.codeStep = 'confirm';
    this.codeTypedConfirmation = '';
  }

  submitCodeChange(): void {
    if (!this.isCodeConfirmationTyped || this.isSavingCode) {
      return;
    }

    this.isSavingCode = true;
    this.codeMessage = '';
    this.professionalAuthApi
      .updateProfessionalCode(this.normalizedCodeDraft, this.codeConfirmationPhrase, this.notifyClientsOfCodeChange)
      .subscribe({
        next: (response) => {
          this.professionalCode = response.professional_code;
          this.codeMessageType = 'success';
          this.codeMessage = response.message;
          this.isSavingCode = false;
          this.codeStep = 'idle';
          this.codeDraft = '';
          this.codeTypedConfirmation = '';
          this.loadProfessionalCodeState();
        },
        error: (error: unknown) => {
          this.codeMessageType = 'error';
          this.codeMessage = this.formatApiError(error, 'Professional code could not be saved.');
          this.isSavingCode = false;
        }
      });
  }

  private loadProfessionalCodeState(): void {
    this.professionalAuthApi.getProfessionalCodeState().subscribe({
      next: (state) => {
        this.professionalCode = state.professional_code;
        this.codeImpact = state.impact;
        this.codeConfirmationPhrase = state.confirmation_phrase || 'APPROVED';
      },
      error: () => {
        // Non-fatal: the section still works, it just cannot show how many
        // clients a change would affect.
      }
    });
  }

  get isNewPasswordRequirementsMet(): boolean {
    return isPasswordStrong(this.passwordForm.password);
  }

  changePassword(): void {
    this.accountMessage = '';
    const password = this.passwordForm.password;
    const confirmPassword = this.passwordForm.confirmPassword;

    if (!password || !confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'New Password and Confirm New Password are required.';
      return;
    }

    if (!isPasswordStrong(password)) {
      this.accountMessageType = 'error';
      this.accountMessage = 'New password does not meet all requirements listed below the field.';
      return;
    }

    if (password !== confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Passwords must match.';
      return;
    }

    this.isChangingPassword = true;

    this.professionalAuthApi.changePassword(password, confirmPassword).subscribe({
      next: (response) => {
        this.clearProfessionalSession();
        window.sessionStorage.setItem('professional-login-notice', response.message);
        void this.router.navigate(['/professional/login']);
      },
      error: (error: unknown) => {
        this.accountMessageType = 'error';
        this.accountMessage = this.formatApiError(error, 'Password could not be changed.');
        this.isChangingPassword = false;
      }
    });
  }

  private clearProfessionalSession(): void {
    window.sessionStorage.removeItem('professional-auth-token');
    window.sessionStorage.removeItem('professional-account-id');
    window.sessionStorage.removeItem('professional-account-username');
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
