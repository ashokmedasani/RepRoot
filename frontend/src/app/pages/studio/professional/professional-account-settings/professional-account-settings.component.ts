import { DatePipe, KeyValuePipe, SlicePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
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
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { PasswordRequirementsComponent } from '@studio-shared/password-requirements/password-requirements.component';
import { isPasswordStrong } from '@studio-shared/password-requirements/password-requirements.util';
import { ThemeSwitcherComponent } from '@shared/theme-switcher/theme-switcher.component';
import { SupportIncidentsComponent } from '@studio-shared/support-incidents/support-incidents.component';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { ProfessionalPaymentSettingsComponent } from '../professional-payment-settings/professional-payment-settings.component';

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

  readonly appVersion = '1.0.0';
  readonly supportEmail = window.APP_CONFIG?.supportEmail || '';

  readonly menu: { id: SettingsSection; label: string }[] = [
    { id: 'my-account', label: 'My Account' },
    { id: 'security', label: 'Security' },
    { id: 'billing', label: 'Plan & Billing' },
    { id: 'payments', label: 'Payment Settings' },
    { id: 'notifications', label: 'Notifications' },
    { id: 'appearance', label: 'Appearance' },
    { id: 'storage', label: 'Data Usage' },
    { id: 'guide', label: 'Application Guide' },
    { id: 'support', label: 'Support' },
    { id: 'about', label: 'About' }
  ];

  activeSection: SettingsSection = 'my-account';
  isChangingPassword = false;
  accountMessage = '';
  accountMessageType: 'success' | 'error' = 'success';

  professionalCode = '';
  codeDraft = '';
  isSavingCode = false;
  codeMessage = '';
  codeMessageType: 'success' | 'error' = 'success';
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
    forms_groups: 'Forms & groups',
    clients: 'Client profiles',
    schedules_progress: 'Schedules & progress',
    resources: 'Resources',
    templates_tracking: 'Templates & tracking',
    messages: 'Messages'
  };

  readonly recycleBinItems = signal<RecycleBinItem[]>([]);
  isLoadingRecycleBin = false;
  recycleBinMessage = '';
  recycleBinMessageType: 'success' | 'error' = 'success';
  restoringItemId: number | null = null;
  deletingItemId: number | null = null;

  readonly guideItems = [
    { title: 'Dashboard', route: '/professional/dashboard', detail: 'Review business KPIs, client activity, schedules, profile edit requests, account deletion requests, and recent work that needs attention.' },
    { title: 'Forms & Groups', route: '/professional/forms-groups', detail: 'Manage the public lead form, review incoming requests, create groups, and see capacity for your current plan.' },
    { title: 'Client Creation Form', route: '/professional/forms-groups', detail: 'Each group has its own registration form. Customize intake questions, share its public link, and convert completed registrations into client accounts.' },
    { title: 'Templates', route: '/professional/templates', detail: 'Create reusable tracking templates, choose fields and cadence, then assign them to any client without losing historical entries.' },
    { title: 'Clients', route: '/professional/clients', detail: 'Search all clients, add clients manually, open a profile, assign templates, schedule follow-ups, review entries, and record progress.' },
    { title: 'Resource Library', route: '/professional/resource', detail: 'Organize PDFs, images, and YouTube resources by category. Share selected resources with each client assignment.' },
    { title: 'Profile', route: '/professional/profile', detail: 'Maintain the professional information clients can see, upload portfolio media, and control the visibility of each profile section.' },
    { title: 'Settings', route: '/professional/account-settings', detail: 'Manage your account, security, professional code, notifications, theme, plan storage, support links, and legal information.' },
    { title: 'Client Portal', route: '/client/login', detail: 'Clients use your professional code and their credentials to complete templates, review progress, message you, maintain settings, and submit approval requests.' }
  ];

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
        this.codeDraft = this.professionalCode;
      }
    });
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.dataUsage = usage),
      error: () => (this.dataUsageError = 'Storage usage is temporarily unavailable.')
    });
    this.loadRecycleBin();
    this.loadBillingStatus();

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

  selectSection(id: SettingsSection): void {
    this.activeSection = id;
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

  applyTemporaryPlan(code: ProfessionalPlanCode): void {
    if (code === this.billingStatus?.plan.code || this.isStartingCheckout) return;
    void this.router.navigate(['/professional/subscription-payment'], {
      queryParams: { plan: code, cycle: this.selectedBillingCycle }
    });
  }

  openBillingPortal(): void {
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

  saveProfessionalCode(): void {
    const code = this.codeDraft.trim();

    if (!code) {
      this.codeMessageType = 'error';
      this.codeMessage = 'Professional code is required.';
      return;
    }

    this.isSavingCode = true;
    this.codeMessage = '';
    this.professionalAuthApi.updateProfessionalCode(code).subscribe({
      next: (response) => {
        this.professionalCode = response.professional_code;
        this.codeDraft = response.professional_code;
        this.codeMessageType = 'success';
        this.codeMessage = response.message;
        this.isSavingCode = false;
      },
      error: (error: unknown) => {
        this.codeMessageType = 'error';
        this.codeMessage = this.formatApiError(error, 'Professional code could not be saved.');
        this.isSavingCode = false;
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
