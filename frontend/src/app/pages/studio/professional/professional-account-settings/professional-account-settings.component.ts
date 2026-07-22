import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';

import {
  ProfessionalAuthApiService,
  ProfessionalBillingStatus,
  ProfessionalDataUsageResponse,
  ProfessionalDataUsageSection,
  ProfessionalPlanCode,
  ProfessionalUpgradeTier,
  ProfessionalUsageLabel,
  RecycleBinItem,
  NotificationPreference
} from '@core/api/professional-auth-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { ProfessionalProfileFormComponent } from '@studio-shared/professional-profile-form/professional-profile-form.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
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
    FormsModule,
    RouterLink,
    ProfessionalPageShellComponent,
    ProfessionalProfileFormComponent,
    PasswordInputComponent,
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
  readonly supportEmail = 'support@rep-root.com';

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

  readonly professionalUsageLabels: Record<string, string> = {
    professional_profile: 'Professional profile',
    forms_groups: 'Forms & groups',
    clients: 'Client profiles',
    schedules_progress: 'Schedules & progress',
    references: 'References',
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
    { title: 'References', route: '/professional/references', detail: 'Organize PDFs, images, and YouTube resources by category. Share selected references with each client assignment.' },
    { title: 'Profile', route: '/professional/profile', detail: 'Maintain the professional information clients can see, upload portfolio media, and control the visibility of each profile section.' },
    { title: 'Settings', route: '/professional/account-settings', detail: 'Manage your account, security, professional code, notifications, theme, plan storage, support links, and legal information.' },
    { title: 'Client Portal', route: '/client/login', detail: 'Clients use your professional code and their credentials to complete templates, review progress, message you, maintain settings, and submit approval requests.' }
  ];

  readonly passwordForm = {
    currentPassword: '',
    password: '',
    confirmPassword: ''
  };

  notificationPreferences: NotificationPreference[] = [];
  notificationMessage = '';
  readonly notificationLabels: Record<string, string> = {
    chat: 'Client messages', forms: 'Form submissions', meetings: 'Meetings', clients: 'Client requests',
    templates: 'Templates', progress: 'Progress and tracking', reminders: 'Reminders', references: 'References',
    payments: 'Payments', support: 'Support', account: 'Account lifecycle', storage: 'Storage usage',
    security: 'Security', system: 'System notices'
  };

  ngOnInit(): void {
    this.loadNotificationPrefs();
    this.professionalAuthApi.getProfile().subscribe({
      next: (profile) => {
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

  private loadBillingStatus(): void {
    this.billingError = '';
    this.professionalAuthApi.getBillingStatus().subscribe({
      next: (status) => (this.billingStatus = status),
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
    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Cancel plan',
      target: 'your current plan',
      impact: 'Your account moves to Starter Free. If current storage is over the Starter allowance, a 14-day cleanup or upgrade grace period begins before the account is frozen.',
      confirmLabel: 'Cancel Plan'
    });

    if (!confirmed) {
      return;
    }

    this.billingActionMessage = '';
    this.isCancellingPlan = true;
    this.professionalAuthApi.cancelBillingPlan().subscribe({
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

  readonly upgradeTierCopy: Record<ProfessionalUpgradeTier, { name: string; blurb: string }> = {
    pro: { name: 'Pro', blurb: '1 GB included storage with a temporary 20% buffer.' },
    premium_unlimited: { name: 'Premium Unlimited', blurb: '5 GB included storage with a temporary 20% buffer.' }
  };

  isUpdatePlanOpen = false;
  selectedUpgradeTier: ProfessionalUpgradeTier | null = null;

  private readonly planRank: Record<ProfessionalPlanCode, number> = {
    starter_free: 0,
    starter: 0,
    pro: 1,
    premium_unlimited: 2,
    premium: 2
  };

  /** Tiers that are both Stripe-configured and strictly above the professional's current plan. */
  availableUpgradeTiers(billing: ProfessionalBillingStatus): ProfessionalUpgradeTier[] {
    const currentRank = this.planRank[billing.plan.code] ?? 0;
    return (['pro', 'premium_unlimited'] as ProfessionalUpgradeTier[]).filter(
      (tier) => billing.available_upgrades[tier] && this.planRank[tier] > currentRank
    );
  }

  openUpdatePlan(): void {
    this.billingActionMessage = '';
    this.selectedUpgradeTier = null;
    this.isUpdatePlanOpen = true;
  }

  closeUpdatePlan(): void {
    this.isUpdatePlanOpen = false;
  }

  selectUpgradeTier(tier: ProfessionalUpgradeTier): void {
    this.selectedUpgradeTier = tier;
  }

  confirmUpdatePlan(): void {
    if (!this.selectedUpgradeTier) return;
    this.billingActionMessage = '';
    this.isStartingCheckout = true;
    this.professionalAuthApi.createBillingCheckout(this.selectedUpgradeTier).subscribe({
      next: (response) => {
        window.location.href = response.checkout_url;
      },
      error: (error: unknown) => {
        this.billingActionMessageType = 'error';
        this.billingActionMessage = this.formatApiError(error, 'Could not start checkout.');
        this.isStartingCheckout = false;
      }
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

  /** Paid tiers that have already maxed out what an upgrade buys — Premium Unlimited plus the legacy Premium tier. */
  isTopTier(code: ProfessionalPlanCode | undefined): boolean {
    return code === 'premium_unlimited' || code === 'premium';
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

  changePassword(): void {
    this.accountMessage = '';
    const currentPassword = this.passwordForm.currentPassword;
    const password = this.passwordForm.password;
    const confirmPassword = this.passwordForm.confirmPassword;

    if (!currentPassword || !password || !confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Current Password, New Password, and Confirm New Password are required.';
      return;
    }

    if (password !== confirmPassword) {
      this.accountMessageType = 'error';
      this.accountMessage = 'Passwords must match.';
      return;
    }

    this.isChangingPassword = true;

    this.professionalAuthApi.changePassword(currentPassword, password, confirmPassword).subscribe({
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
    window.localStorage.removeItem('professional-auth-token');
    window.localStorage.removeItem('professional-account-id');
    window.localStorage.removeItem('professional-account-username');
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
