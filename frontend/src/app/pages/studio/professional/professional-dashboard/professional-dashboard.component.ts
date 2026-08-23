import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { ChatApiService } from '@core/api/chat-api.service';
import {
  PaymentActionItem,
  PaymentNotificationItem,
  PaymentsApiService,
  RevenuePeriod,
  RevenueSummaryResponse
} from '@core/api/payments-api.service';
import {
  ClientProfileEditActivity,
  ClientReminder,
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadSubmission
} from '@core/api/forms-groups-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';
import { FixedHeightListComponent } from '@studio-shared/fixed-height-list/fixed-height-list.component';
import { ChartSpec } from '@studio-shared/analytics/analytics.types';
import { ChartRendererComponent } from '@studio-shared/analytics/chart-renderer.component';
import { chartTheme } from '@studio-shared/analytics/charts/chart-theme';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError, initialsFor } from '@shared/utils/ui-helpers';
import {
  ProfessionalAuthApiService,
  ProfessionalDataUsageResponse,
  ProfessionalOnboardingStatus
} from '@core/api/professional-auth-api.service';
import { SkeletonComponent } from '@studio-shared/skeleton/skeleton.component';

type DashboardTab = 'activity' | 'payments' | 'schedules';

interface MessageRow {
  clientId: number;
  clientName: string;
  unreadCount: number;
  lastAt: string;
}

interface OnboardingChecklistItem {
  code: string;
  label: string;
  route: string;
  completed: boolean;
}

@Component({
  selector: 'app-professional-dashboard',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, RouterLink, ProfessionalPageShellComponent, FixedHeightListComponent, ChartRendererComponent, SkeletonComponent],
  templateUrl: './professional-dashboard.component.html',
  styleUrl: './professional-dashboard.component.scss'
})
export class ProfessionalDashboardComponent implements OnInit, OnDestroy {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly chatApi = inject(ChatApiService);
  private readonly paymentsApi = inject(PaymentsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);

  activeTab: DashboardTab = 'activity';
  isLoading = true;
  message = '';
  planUsage: ProfessionalDataUsageResponse | null = null;
  onboarding: ProfessionalOnboardingStatus | null = null;

  // Activity
  overview: FormsGroupsOverview | null = null;
  pendingProfileEdits: ClientProfileEditActivity[] = [];
  unreadByClient: Record<string, number> = {};
  lastUnreadAtByClient: Record<string, string> = {};
  private clientNameById: Record<number, string> = {};
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  // Payments
  paymentsEnabled = false;
  paymentActions: PaymentActionItem[] = [];
  paymentReviewCount = 0;
  paymentOverdueCount = 0;
  // Unread payment *notifications* (new request/proof/approval/etc events) -
  // a distinct concept from paymentReviewCount/paymentOverdueCount above,
  // which reflect live request status. Folded into a single `paymentsBadgeCount`
  // (see getter below) alongside paymentsActionCount rather than shown as its
  // own badge - two separate numbers on one tab pill was confusing.
  paymentsUnreadCount = 0;
  paymentNotifications: PaymentNotificationItem[] = [];
  private paymentUnreadPoll: ReturnType<typeof setInterval> | null = null;

  // Revenue dashboard — only meaningful once a reporting currency is chosen,
  // Revenue is shown only after the professional permanently confirms a reporting currency.
  revenueUnlocked = false;
  revenue: RevenueSummaryResponse | null = null;
  revenuePeriod: RevenuePeriod = '7';
  readonly revenuePeriodOptions: { id: RevenuePeriod; label: string }[] = [
    { id: '7', label: 'Last 7 days' },
    { id: '30', label: 'Last 30 days' },
    { id: '90', label: 'Last 90 days' },
    { id: 'lifetime', label: 'Lifetime' },
    { id: 'custom', label: 'Custom range' }
  ];
  revenueCustomStart = '';
  revenueCustomEnd = '';
  isLoadingRevenue = false;

  // Schedules
  upcomingReminders: ClientReminder[] = [];
  scheduleSummary = {
    total_pending: 0,
    overdue: 0,
    due_24_hours: 0,
    due_7_days: 0,
    total_completed: 0,
    completed_last_7_days: 0,
    pending_profile_edits: 0,
    nearest_date: ''
  };

  get onboardingChecklist(): OnboardingChecklistItem[] {
    if (!this.onboarding) return [];

    return [
      { code: 'form', label: 'Lead Form', route: '/professional/forms/create', completed: this.onboarding.form_created },
      { code: 'group', label: 'Group', route: '/professional/groups/create', completed: this.onboarding.group_created },
      { code: 'template', label: 'Template', route: '/professional/templates/create', completed: this.onboarding.template_created },
      { code: 'resource', label: 'Resources', route: '/professional/resource', completed: this.onboarding.resource_created },
      { code: 'meeting_setup', label: 'Meeting Setup', route: '/professional/schedule', completed: this.onboarding.meeting_setup_complete }
    ];
  }

  get onboardingCompletedCount(): number {
    return this.onboardingChecklist.filter((item) => item.completed).length;
  }

  ngOnInit(): void {
    this.professionalAuthApi.getDataUsage().subscribe({
      next: (usage) => (this.planUsage = usage),
      error: () => (this.planUsage = null)
    });
    this.professionalAuthApi.getOnboardingStatus().subscribe({
      next: (status) => (this.onboarding = status),
      error: () => (this.onboarding = null)
    });
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.isLoading = false;
        for (const submission of overview.approved_forms) {
          if (submission.client_access) {
            this.clientNameById[submission.client_access.id] = submission.applicant_name;
          }
        }
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Dashboard could not be loaded.');
        this.isLoading = false;
      }
    });

    this.formsGroupsApi.getUpcomingReminders().subscribe({
      next: (response) => {
        this.upcomingReminders = response.reminders;
        this.pendingProfileEdits = response.profile_edits;
        this.scheduleSummary = response.summary;
      },
      error: () => {
        this.upcomingReminders = [];
        this.pendingProfileEdits = [];
      }
    });

    this.loadUnreadMessages();
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);

    this.paymentsApi.getPaymentSettings().subscribe({
      next: (response) => {
        this.paymentsEnabled = response.settings.payment_tracking_enabled;
        this.revenueUnlocked = response.settings.reporting_currency_locked;
        if (this.paymentsEnabled) {
          this.loadPaymentActions();
          this.loadPaymentUnread();
          this.paymentUnreadPoll = setInterval(() => this.loadPaymentUnread(), 10000);
          if (this.revenueUnlocked) {
            this.loadRevenueSummary();
          }
        } else if (this.activeTab === 'payments') {
          this.activeTab = 'activity';
        }
      },
      error: () => (this.paymentsEnabled = false)
    });
  }

  private loadRevenueSummary(): void {
    if (this.revenuePeriod === 'custom' && (!this.revenueCustomStart || !this.revenueCustomEnd)) {
      return;
    }
    this.isLoadingRevenue = true;
    this.paymentsApi.getRevenueSummary(this.revenuePeriod, this.revenueCustomStart, this.revenueCustomEnd).subscribe({
      next: (response) => {
        this.revenue = response;
        this.isLoadingRevenue = false;
      },
      error: () => {
        this.revenue = null;
        this.isLoadingRevenue = false;
      }
    });
  }

  onRevenuePeriodChange(period: RevenuePeriod): void {
    this.revenuePeriod = period;
    if (period === 'custom') {
      if (!this.revenueCustomStart || !this.revenueCustomEnd) {
        const today = new Date();
        const monthAgo = new Date(today);
        monthAgo.setDate(monthAgo.getDate() - 29);
        this.revenueCustomEnd = today.toISOString().slice(0, 10);
        this.revenueCustomStart = monthAgo.toISOString().slice(0, 10);
      }
      this.loadRevenueSummary();
    } else {
      this.loadRevenueSummary();
    }
  }

  applyCustomRevenueRange(): void {
    if (!this.revenueCustomStart || !this.revenueCustomEnd) return;
    this.loadRevenueSummary();
  }

  ngOnDestroy(): void {
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
    if (this.paymentUnreadPoll) {
      clearInterval(this.paymentUnreadPoll);
    }
  }

  selectTab(tab: DashboardTab): void {
    this.activeTab = tab;
  }

  // ----- Activity -----

  get pendingRequests(): LeadSubmission[] {
    return this.overview?.pending_forms || [];
  }

  get messageRows(): MessageRow[] {
    return Object.entries(this.unreadByClient)
      .filter(([, count]) => count > 0)
      .map(([clientId, count]) => ({
        clientId: Number(clientId),
        clientName: this.clientNameById[Number(clientId)] || 'Client',
        unreadCount: count,
        lastAt: this.lastUnreadAtByClient[clientId] || ''
      }))
      .sort((a, b) => new Date(b.lastAt).getTime() - new Date(a.lastAt).getTime());
  }

  get unreadMessagesTotal(): number {
    return Object.values(this.unreadByClient).reduce((sum, count) => sum + count, 0);
  }

  get activityActionCount(): number {
    return this.unreadMessagesTotal + this.pendingRequests.length + this.pendingProfileEdits.length;
  }

  get activityChart(): ChartSpec {
    const theme = chartTheme();
    return {
      kind: 'bar',
      title: 'Activity breakdown',
      data: [
        { label: 'Unread messages', value: this.unreadMessagesTotal, color: theme.primary },
        { label: 'Pending requests', value: this.pendingRequests.length, color: theme.accent },
        { label: 'Account requests', value: this.pendingProfileEdits.length, color: theme.warning }
      ],
      meta: { subtitle: `${this.activityActionCount} items waiting on you` }
    };
  }

  /**
   * Card headings carry their count -- "12 Messages" -- but an empty card
   * headed "0 Messages" reads as a broken number rather than as nothing to
   * do, so at zero the heading is just the plain noun.
   */
  headingCount(count: number, singular: string, plural: string): string {
    if (!count) {
      return plural;
    }
    return `${count} ${count === 1 ? singular : plural}`;
  }

  initialsForSubmission(submission: LeadSubmission): string {
    return initialsFor(submission.first_name, submission.last_name);
  }

  initialsForName(name: string): string {
    const [first, ...rest] = name.split(' ');
    return initialsFor(first || '', rest.join(' '));
  }

  /** "Unlimited" when the backend reports no cap for this resource (plan_limits
   *  is always the source of truth -- never hard-code a limit on the frontend). */
  resourceUsageDisplay(resourceKey: string): string {
    const usage = this.planUsage?.resource_usage?.[resourceKey];

    if (!usage) {
      return '—';
    }

    return usage.limit === null || usage.limit === undefined ? `${usage.used}` : `${usage.used} / ${usage.limit}`;
  }

  resourceUsageCaption(resourceKey: string): string {
    const usage = this.planUsage?.resource_usage?.[resourceKey];
    return usage && (usage.limit === null || usage.limit === undefined) ? 'Unlimited' : 'Used';
  }

  private loadUnreadMessages(): void {
    this.chatApi.getProfessionalUnreadCounts().subscribe({
      next: (summary) => {
        this.unreadByClient = summary.by_client;
        this.lastUnreadAtByClient = summary.last_unread_at || {};
        Object.assign(this.clientNameById, summary.client_names || {});
      },
      error: () => {
        this.unreadByClient = {};
        this.lastUnreadAtByClient = {};
      }
    });
  }

  async reviewClientRequest(request: ClientProfileEditActivity, action: 'approve' | 'reject'): Promise<void> {
    const isDeletion = request.request_type === 'account_deletion';
    const confirmed = await this.confirmation.confirm({
      kind: action === 'approve' ? (isDeletion ? 'delete' : 'complete') : 'warning',
      title: action === 'approve' ? (isDeletion ? 'Approve account deletion for' : 'Approve request for') : 'Decline request for',
      target: request.client_name,
      impact: isDeletion && action === 'approve'
        ? 'The client account will be deactivated immediately and all active client sessions will be revoked.'
        : `The ${isDeletion ? 'account deletion' : 'profile edit'} request will be ${action === 'approve' ? 'approved' : 'declined'}.`,
      confirmLabel: action === 'approve' ? 'Approve' : 'Decline'
    });
    if (!confirmed) return;

    this.formsGroupsApi.reviewChangeRequest(request.client, request.id, action).subscribe({
      next: (response) => {
        this.pendingProfileEdits = this.pendingProfileEdits.filter((item) => item.id !== request.id);
        this.scheduleSummary = {
          ...this.scheduleSummary,
          pending_profile_edits: Math.max(0, this.scheduleSummary.pending_profile_edits - 1)
        };
        this.message = response.message;
      },
      error: (error: unknown) => {
        this.message = formatApiError(error, 'Client request could not be reviewed.');
      }
    });
  }

  // ----- Payments -----

  private loadPaymentActions(): void {
    this.paymentsApi.getPaymentActions().subscribe({
      next: (response) => {
        this.paymentActions = response.items;
        this.paymentReviewCount = response.review_count;
        this.paymentOverdueCount = response.overdue_count;
      },
      error: () => {
        this.paymentActions = [];
        this.paymentReviewCount = 0;
        this.paymentOverdueCount = 0;
      }
    });
  }

  private loadPaymentUnread(): void {
    this.paymentsApi.getProfessionalPaymentUnread().subscribe({
      next: (response) => {
        this.paymentsUnreadCount = response.unread_count;
        this.paymentNotifications = response.items;
      },
      error: () => {
        this.paymentsUnreadCount = 0;
        this.paymentNotifications = [];
      }
    });
  }

  get paymentsActionCount(): number {
    return this.paymentReviewCount + this.paymentOverdueCount;
  }

  /** Single number shown on the Payments tab pill - combines "needs review or
   *  overdue" with "unread updates" so the trainer sees one count instead of
   *  two side-by-side badges. Each underlying item (Needs Action table row,
   *  or a notification below) has its own link straight to the specific
   *  client/request, so nothing is lost by not splitting the number. */
  get paymentsBadgeCount(): number {
    return this.paymentsActionCount;
  }

  /** A payment notification's payload carries a specific action_url (set by
   *  the backend per notification type) pointing at the exact client/request
   *  that triggered it - e.g. /professional/clients/5?tab=payments. Falls
   *  back to the Payments tab if an older notification predates that field. */
  openPaymentNotification(item: PaymentNotificationItem): void {
    const requestId = typeof item.payload?.['request_id'] === 'string' ? (item.payload['request_id'] as string) : undefined;
    this.paymentsApi.markProfessionalPaymentNotificationsRead(requestId).subscribe({
      next: () => this.loadPaymentUnread(),
      error: () => this.loadPaymentUnread()
    });

    let actionUrl = typeof item.payload?.['action_url'] === 'string' ? (item.payload['action_url'] as string) : '';
    const clientId = actionUrl.match(/\/professional\/clients\/(\d+)/)?.[1];
    if (requestId && clientId) {
      actionUrl = `/professional/clients/${clientId}?tab=payments&paymentTab=requests&request=${requestId}`;
    }
    if (actionUrl) {
      void this.router.navigateByUrl(actionUrl);
    } else {
      this.activeTab = 'payments';
    }
  }

  get paymentsChart(): ChartSpec {
    const theme = chartTheme();
    return {
      kind: 'bar',
      title: 'Payments needing action',
      data: [
        { label: 'Awaiting review', value: this.paymentReviewCount, color: theme.primary },
        { label: 'Overdue', value: this.paymentOverdueCount, color: theme.danger }
      ],
      meta: { subtitle: `${this.paymentsActionCount} total` }
    };
  }

  get revenueChart(): ChartSpec {
    const theme = chartTheme();
    const points = this.revenue?.series || [];
    return {
      // Backend picks bar vs line to match the selected span — bar for
      // 30 days or less, line once it gets long enough that daily bars
      // would just be noise.
      kind: this.revenue?.chart_kind || 'bar',
      title: `Revenue (${this.revenue?.reporting_currency || ''})`,
      data: points.map((point) => ({ label: point.label, value: Number(point.total), color: theme.primary })),
      meta: { subtitle: 'By date received' }
    };
  }

  paymentStatusLabel(statusValue: string): string {
    const labels: Record<string, string> = {
      proof_submitted: 'Proof Submitted',
      under_review: 'Under Review',
      overdue: 'Overdue'
    };
    return labels[statusValue] || statusValue;
  }

  // ----- Schedules -----

  get organizedScheduleReminders(): ClientReminder[] {
    return [...this.upcomingReminders].sort((left, right) =>
      `${left.date}T${left.time || '23:59'}`.localeCompare(`${right.date}T${right.time || '23:59'}`)
    );
  }

  get scheduleActionCount(): number {
    return this.scheduleSummary.overdue + this.scheduleSummary.due_24_hours;
  }

  get scheduleChart(): ChartSpec {
    const theme = chartTheme();
    return {
      kind: 'bar',
      title: 'Schedule status',
      data: [
        { label: 'Overdue', value: this.scheduleSummary.overdue, color: theme.danger },
        { label: 'Due in 24 hrs', value: this.scheduleSummary.due_24_hours, color: theme.warning },
        { label: 'Due in 7 days', value: this.scheduleSummary.due_7_days, color: theme.primary },
        { label: 'Completed in last 7 days', value: this.scheduleSummary.completed_last_7_days, color: theme.success }
      ],
      meta: { subtitle: `${this.scheduleSummary.total_pending} pending, ${this.scheduleSummary.total_completed} completed overall` }
    };
  }

  get upcomingScheduleCount(): number {
    return Math.max(0, this.organizedScheduleReminders.length - this.scheduleSummary.overdue);
  }

  relativeTime(dateStr: string, timeStr: string | null): string {
    const target = this.reminderTimestamp(dateStr, timeStr);
    if (Number.isNaN(target)) {
      return '';
    }
    const diffMs = target - Date.now();
    if (diffMs < 0) {
      return 'Overdue';
    }
    const hours = Math.round(diffMs / (60 * 60 * 1000));
    if (hours < 24) {
      return hours <= 1 ? 'Within 1 hour' : `In ${hours} hours`;
    }
    const days = Math.round(hours / 24);
    return days === 1 ? 'In 1 day' : `In ${days} days`;
  }

  isReminderSoon(dateStr: string, timeStr: string | null): boolean {
    const target = this.reminderTimestamp(dateStr, timeStr);
    const difference = target - Date.now();
    return !Number.isNaN(target) && difference >= 0 && difference <= 24 * 60 * 60 * 1000;
  }

  isReminderOverdue(reminder: ClientReminder): boolean {
    const target = this.reminderTimestamp(reminder.date, reminder.time);
    return !Number.isNaN(target) && target < Date.now();
  }

  showScheduleGroupHeader(reminder: ClientReminder, index: number): boolean {
    if (index === 0) {
      return true;
    }
    return this.isReminderOverdue(reminder) !== this.isReminderOverdue(this.organizedScheduleReminders[index - 1]);
  }

  scheduleGroupTitle(reminder: ClientReminder): string {
    return this.isReminderOverdue(reminder) ? 'Overdue schedules' : 'Upcoming schedules';
  }

  scheduleGroupCount(reminder: ClientReminder): number {
    return this.isReminderOverdue(reminder) ? this.scheduleSummary.overdue : this.upcomingScheduleCount;
  }

  async completeReminder(reminder: ClientReminder): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'complete',
      title: 'Mark schedule complete for',
      target: `${reminder.client_name} - ${reminder.title}`,
      impact: 'This schedule will move from pending to completed and update the dashboard totals.',
      confirmLabel: 'Mark Complete'
    });
    if (!confirmed) return;

    this.formsGroupsApi.updateReminder(reminder.id, { status: 'done' }).subscribe({
      next: () => {
        const dueAt = this.reminderTimestamp(reminder.date, reminder.time);
        const difference = dueAt - Date.now();
        this.upcomingReminders = this.upcomingReminders.filter((item) => item.id !== reminder.id);
        this.scheduleSummary.total_pending = Math.max(0, this.scheduleSummary.total_pending - 1);
        if (difference < 0) {
          this.scheduleSummary.overdue = Math.max(0, this.scheduleSummary.overdue - 1);
        } else {
          if (difference <= 24 * 60 * 60 * 1000) {
            this.scheduleSummary.due_24_hours = Math.max(0, this.scheduleSummary.due_24_hours - 1);
          }
          if (difference <= 7 * 24 * 60 * 60 * 1000) {
            this.scheduleSummary.due_7_days = Math.max(0, this.scheduleSummary.due_7_days - 1);
          }
        }
        this.scheduleSummary.total_completed += 1;
        this.scheduleSummary.completed_last_7_days += 1;
        this.scheduleSummary.nearest_date = this.organizedScheduleReminders.find(
          (item) => !this.isReminderOverdue(item)
        )?.date || '';
      }
    });
  }

  private reminderTimestamp(dateStr: string, timeStr: string | null): number {
    return new Date(`${dateStr}T${timeStr || '23:59'}`).getTime();
  }
}
