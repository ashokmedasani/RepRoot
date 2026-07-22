import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, Input, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { ChartSpec } from '@studio-shared/analytics/analytics.types';
import { ChartRendererComponent } from '@studio-shared/analytics/chart-renderer.component';
import { chartTheme } from '@studio-shared/analytics/charts/chart-theme';

import {
  CreatePaymentRequestPayload,
  ManualPaymentMethodRecord,
  PaymentProofRecord,
  PaymentReconciliationSummary,
  PaymentRecordRow,
  PaymentRequestRecord,
  PaymentRequestStatus,
  PaymentsApiService,
  RecordReceivedPayload
} from '@core/api/payments-api.service';
import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';
import { formatApiError } from '@shared/utils/ui-helpers';

export const PAYMENT_STATUS_LABELS: Record<PaymentRequestStatus, string> = {
  draft: 'Draft',
  sent: 'Sent',
  viewed: 'Viewed',
  proof_submitted: 'Proof Submitted',
  under_review: 'Under Review',
  acknowledged: 'Acknowledged',
  completed: 'Completed',
  partially_paid: 'Partially Paid',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
  overdue: 'Overdue',
  refunded: 'Refunded'
};

type PaymentsSubTab = 'summary' | 'requests' | 'history' | 'methods' | 'activity';

@Component({
  selector: 'app-client-payments-tab',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, RouterLink, ChartRendererComponent],
  templateUrl: './client-payments-tab.component.html',
  styleUrl: './client-payments-tab.component.scss'
})
export class ClientPaymentsTabComponent implements OnInit {
  private readonly paymentsApi = inject(PaymentsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);

  @Input({ required: true }) clientId = 0;
  @Input() clientName = '';

  requests: PaymentRequestRecord[] = [];
  requestsMessage = '';
  requestsMessageType: 'success' | 'error' = 'success';
  showRequestForm = false;
  isSavingRequest = false;
  requestFormMessage = '';

  requestForm = this.blankRequestForm();
  allowedMethodSelection: Record<number, boolean> = {};
  currencyOptions: string[] = [];
  reportingCurrency = 'USD';
  // Earnings totals only mean something once the professional has picked a
  // reporting currency — until then this is a scheduling/follow-up tool
  // (requests, due dates, reminders), not a money dashboard.
  dashboardUnlocked = false;

  // Verification modal state
  verifyingRequest: PaymentRequestRecord | null = null;
  verifyingProof: PaymentProofRecord | null = null;
  verifyingRecords: PaymentRecordRow[] = [];
  verifyMode: 'review' | 'acknowledge' | 'reject' | 'info' = 'review';
  acknowledgementNote = '';
  rejectReason = '';
  infoNote = '';
  isVerifyLoading = false;
  isVerifySaving = false;
  verifyMessage = '';

  // Records / history
  records: PaymentRecordRow[] = [];
  recordsMessage = '';
  recordsMessageType: 'success' | 'error' = 'success';
  showRecordForm = false;
  isSavingRecord = false;
  recordFormMessage = '';
  recordForm = this.blankRecordForm();

  // Acknowledged-vs-logged reconciliation
  reconciliation: PaymentReconciliationSummary | null = null;

  readonly subTabs: { id: PaymentsSubTab; label: string }[] = [
    { id: 'summary', label: 'Summary' },
    { id: 'requests', label: 'Payment Requests' },
    { id: 'history', label: 'Payment History' },
    { id: 'methods', label: 'Available Payment Methods' },
    { id: 'activity', label: 'Payment Activity' }
  ];

  activeSubTab: PaymentsSubTab = 'summary';

  methods: (ManualPaymentMethodRecord & { shared: boolean })[] = [];
  methodsMessage = '';
  methodsMessageType: 'success' | 'error' = 'success';
  isSavingMethods = false;
  private originalSharedIds: number[] = [];

  ngOnInit(): void {
    this.loadMethods();
    this.loadRequests();
    this.loadRecords();
    this.loadReconciliation();
    this.paymentsApi.getPaymentSettings().subscribe({
      next: (response) => {
        this.currencyOptions = response.currency_options;
        this.reportingCurrency = response.settings.reporting_currency;
        this.dashboardUnlocked = response.settings.reporting_currency_locked;
        this.requestForm.requested_currency = response.settings.reporting_currency;
      },
      error: () => (this.currencyOptions = ['USD', 'INR', 'EUR', 'GBP', 'CAD', 'AUD'])
    });
  }

  // --- Records / history / summary ------------------------------------------

  loadRecords(): void {
    if (!this.clientId) return;
    this.paymentsApi.getClientPaymentRecords(this.clientId).subscribe({
      next: (response) => (this.records = response.records),
      error: (error: unknown) => {
        this.recordsMessageType = 'error';
        this.recordsMessage = formatApiError(error, 'Payment history could not be loaded.');
      }
    });
  }

  /** How many acknowledged payments haven't made it into the revenue ledger
   * yet — logging stays optional, this just surfaces the gap. */
  loadReconciliation(): void {
    this.paymentsApi.getPaymentReconciliation().subscribe({
      next: (summary) => (this.reconciliation = summary),
      error: () => (this.reconciliation = null)
    });
  }

  logUnloggedRequest(item: PaymentReconciliationSummary['unlogged_requests'][number]): void {
    this.openRecordForm({
      request_id: item.request_id,
      title: item.title,
      requested_amount: item.requested_amount,
      requested_currency: item.requested_currency
    });
  }

  get lastPaymentDate(): string | null {
    if (!this.records.length) return null;
    return this.records
      .map((r) => r.received_date)
      .sort()
      .slice(-1)[0];
  }

  get nextDueDate(): string | null {
    const open = this.requests
      .filter((r) => this.isOpenStatus(r.status) && r.due_date)
      .map((r) => r.due_date as string)
      .sort();
    return open[0] || null;
  }

  /**
   * One number per metric, in the professional's chosen reporting currency
   * only — never a per-original-currency breakdown, never two tiles saying
   * almost the same thing. Entries in a different currency are silently
   * excluded rather than converted (no auto-FX math); that's the tradeoff
   * of picking a single reporting currency.
   */
  get totalRequested(): number {
    return this.requests
      .filter((r) => r.requested_currency === this.reportingCurrency)
      .reduce((sum, r) => sum + Number(r.requested_amount), 0);
  }

  /** Everything actually logged as received — completed and partial payments together. */
  get totalReceived(): number {
    return this.records
      .filter((r) => r.reporting_currency === this.reportingCurrency)
      .reduce((sum, r) => sum + Number(r.reporting_amount), 0);
  }

  /** Same overdue/pending/completed color language as the professional dashboard. */
  get requestsChart(): ChartSpec {
    const theme = chartTheme();
    const overdueCount = this.requests.filter((r) => r.status === 'overdue').length;
    const pendingCount = this.requests.filter((r) => this.isOpenStatus(r.status) && r.status !== 'overdue').length;
    const completedCount = this.requests.filter((r) => r.status === 'completed').length;
    return {
      kind: 'bar',
      title: 'Requests by status',
      data: [
        { label: 'Overdue', value: overdueCount, color: theme.danger },
        { label: 'Pending', value: pendingCount, color: theme.warning },
        { label: 'Completed', value: completedCount, color: theme.success }
      ],
      meta: { subtitle: `${this.requests.length} total requests` }
    };
  }

  openRecordForm(request?: Pick<PaymentRequestRecord, 'request_id' | 'title' | 'requested_amount' | 'requested_currency'>): void {
    this.recordForm = this.blankRecordForm();
    this.recordForm.reporting_currency = this.reportingCurrency;
    if (request) {
      this.recordForm.payment_request_id = request.request_id;
      this.recordForm.original_amount = request.requested_amount;
      this.recordForm.original_currency = request.requested_currency;
      this.recordForm.title = request.title;
    }
    this.recordFormMessage = '';
    this.showRecordForm = true;
  }

  /**
   * Same currency: copying the amount over is a convenience, not a conversion.
   * Different currency: left blank on purpose — no automatic exchange-rate
   * estimate. The trainer logs whatever they actually received, whenever
   * they get around to it; nothing here converts money for them.
   */
  estimateReporting(): void {
    const amount = this.recordForm.original_amount;
    const from = this.recordForm.original_currency;
    const to = this.recordForm.reporting_currency;
    if (from === to && amount) {
      this.recordForm.reporting_amount = amount;
    }
  }

  async saveRecord(): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'approve',
      title: 'Record received payment',
      target: `${this.recordForm.original_amount} ${this.recordForm.original_currency}`,
      impact: 'This logs the payment as received in your dashboard totals.',
      confirmLabel: 'Record Payment'
    });
    if (!confirmed) return;

    const payload: RecordReceivedPayload = {
      client: this.clientId,
      payment_request_id: this.recordForm.payment_request_id || undefined,
      original_amount: this.recordForm.original_amount,
      original_currency: this.recordForm.original_currency,
      reporting_amount: this.recordForm.reporting_amount,
      reporting_currency: this.recordForm.reporting_currency,
      transaction_reference: this.recordForm.transaction_reference,
      received_date: this.recordForm.received_date,
      status: this.recordForm.status,
      client_visibility: 'visible',
      internal_note: this.recordForm.internal_note,
      client_note: this.recordForm.client_note
    };

    this.isSavingRecord = true;
    this.recordFormMessage = '';

    this.paymentsApi.recordReceivedPayment(payload).subscribe({
      next: (response) => {
        this.isSavingRecord = false;
        this.showRecordForm = false;
        this.recordsMessageType = 'success';
        this.recordsMessage = response.message;
        this.loadRecords();
        this.loadRequests();
        this.loadReconciliation();
      },
      error: (error: unknown) => {
        this.isSavingRecord = false;
        this.recordFormMessage = formatApiError(error, 'Payment could not be recorded.');
      }
    });
  }

  private blankRecordForm() {
    const today = new Date().toISOString().slice(0, 10);
    return {
      payment_request_id: '',
      title: '',
      original_amount: '',
      original_currency: 'USD',
      reporting_amount: '',
      reporting_currency: 'USD',
      received_date: today,
      status: 'completed' as 'completed' | 'partially_paid',
      transaction_reference: '',
      internal_note: '',
      client_note: ''
    };
  }

  get sharedMethods(): (ManualPaymentMethodRecord & { shared: boolean })[] {
    return this.methods.filter((method) => method.shared && method.status === 'active');
  }

  get selectedMethodIds(): number[] {
    return Object.entries(this.allowedMethodSelection)
      .filter(([, selected]) => selected)
      .map(([id]) => Number(id));
  }

  statusLabel(statusValue: PaymentRequestStatus): string {
    return PAYMENT_STATUS_LABELS[statusValue] || statusValue;
  }

  loadRequests(): void {
    if (!this.clientId) return;
    this.paymentsApi.getClientPaymentRequests(this.clientId).subscribe({
      next: (response) => (this.requests = response.requests),
      error: (error: unknown) => {
        this.requestsMessageType = 'error';
        this.requestsMessage = formatApiError(error, 'Payment requests could not be loaded.');
      }
    });
  }

  openRequestForm(): void {
    this.requestForm = this.blankRequestForm();
    this.allowedMethodSelection = {};
    for (const method of this.sharedMethods) {
      this.allowedMethodSelection[method.id] = true;
    }
    this.requestFormMessage = '';
    this.showRequestForm = true;
  }

  async submitRequest(): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'send',
      title: 'Send payment request',
      target: `${this.requestForm.requested_amount} ${this.requestForm.requested_currency} to ${this.clientName || 'this client'}`,
      impact: 'The client will be notified and can submit payment proof against this request.',
      confirmLabel: 'Send Request'
    });
    if (!confirmed) return;

    const payload: CreatePaymentRequestPayload = {
      title: this.requestForm.title,
      description: this.requestForm.description,
      requested_amount: this.requestForm.requested_amount,
      requested_currency: this.requestForm.requested_currency,
      due_date: this.requestForm.due_date || null,
      payment_type: 'manual',
      client_visibility: 'visible',
      notes: this.requestForm.notes,
      allowed_method_ids: this.selectedMethodIds
    };

    this.isSavingRequest = true;
    this.requestFormMessage = '';

    this.paymentsApi.createPaymentRequest(this.clientId, payload).subscribe({
      next: (response) => {
        this.isSavingRequest = false;
        this.showRequestForm = false;
        this.requestsMessageType = 'success';
        this.requestsMessage = response.message;
        this.loadRequests();
      },
      error: (error: unknown) => {
        this.isSavingRequest = false;
        this.requestFormMessage = formatApiError(error, 'Payment request could not be sent.');
      }
    });
  }

  async cancelRequest(request: PaymentRequestRecord): Promise<void> {
    const confirmed = await this.confirmation.confirm({
      kind: 'delete',
      title: 'Cancel payment request',
      target: request.request_id,
      impact: 'The client will no longer be able to act on this request.',
      confirmLabel: 'Cancel Request'
    });
    if (!confirmed) return;

    this.paymentsApi.cancelPaymentRequest(request.request_id).subscribe({
      next: (response) => {
        this.requestsMessageType = 'success';
        this.requestsMessage = response.message;
        this.loadRequests();
      },
      error: (error: unknown) => {
        this.requestsMessageType = 'error';
        this.requestsMessage = formatApiError(error, 'Request could not be cancelled.');
      }
    });
  }

  isOpenStatus(statusValue: PaymentRequestStatus): boolean {
    return ['sent', 'viewed', 'proof_submitted', 'under_review', 'overdue', 'partially_paid'].includes(statusValue);
  }

  needsReview(statusValue: PaymentRequestStatus): boolean {
    return ['proof_submitted', 'under_review'].includes(statusValue);
  }

  // --- Verification modal ---------------------------------------------------

  openVerification(request: PaymentRequestRecord): void {
    this.verifyingRequest = request;
    this.verifyingProof = null;
    this.verifyingRecords = [];
    this.verifyMode = 'review';
    this.verifyMessage = '';
    this.acknowledgementNote = '';
    this.rejectReason = '';
    this.infoNote = '';
    this.isVerifyLoading = true;

    this.paymentsApi.getPaymentRequestDetail(request.request_id).subscribe({
      next: (response) => {
        this.isVerifyLoading = false;
        this.verifyingRecords = response.records;
        // newest still-open proof
        this.verifyingProof =
          response.proofs.find((p) => p.status === 'submitted' || p.status === 'under_review') ||
          response.proofs[0] ||
          null;
      },
      error: (error: unknown) => {
        this.isVerifyLoading = false;
        this.verifyMessage = formatApiError(error, 'Could not load this request.');
      }
    });
  }

  closeVerification(): void {
    this.verifyingRequest = null;
    this.verifyingProof = null;
  }

  async submitAcknowledge(): Promise<void> {
    if (!this.verifyingProof) return;

    const confirmed = await this.confirmation.confirm({
      kind: 'approve',
      title: 'Acknowledge payment received',
      target: `${this.verifyingProof.reported_amount} ${this.verifyingProof.reported_currency}`,
      impact: "This just confirms you received it and notifies the client — it doesn't log anything to your revenue yet.",
      confirmLabel: 'Acknowledge Payment'
    });
    if (!confirmed) return;

    this.isVerifySaving = true;
    this.verifyMessage = '';

    this.paymentsApi
      .acknowledgePaymentProof(this.verifyingProof.id, { acknowledgement_note: this.acknowledgementNote })
      .subscribe({
        next: (response) => {
          this.isVerifySaving = false;
          this.requestsMessageType = 'success';
          this.requestsMessage = response.message;
          this.closeVerification();
          this.loadRequests();
          this.loadReconciliation();
        },
        error: (error: unknown) => {
          this.isVerifySaving = false;
          this.verifyMessage = formatApiError(error, 'Acknowledgement could not be saved.');
        }
      });
  }

  async submitReject(): Promise<void> {
    if (!this.verifyingProof) return;

    const confirmed = await this.confirmation.confirm({
      kind: 'warning',
      title: 'Reject payment proof',
      target: this.verifyingRequest?.request_id || 'this submission',
      impact: 'The client will be notified their proof was rejected, along with your reason, and can resubmit.',
      confirmLabel: 'Reject Proof'
    });
    if (!confirmed) return;

    this.isVerifySaving = true;
    this.verifyMessage = '';

    this.paymentsApi.rejectPaymentProof(this.verifyingProof.id, this.rejectReason).subscribe({
      next: (response) => {
        this.isVerifySaving = false;
        this.requestsMessageType = 'success';
        this.requestsMessage = response.message;
        this.closeVerification();
        this.loadRequests();
      },
      error: (error: unknown) => {
        this.isVerifySaving = false;
        this.verifyMessage = formatApiError(error, 'Could not reject this proof.');
      }
    });
  }

  submitInfoRequest(): void {
    if (!this.verifyingProof) return;
    this.isVerifySaving = true;
    this.verifyMessage = '';

    this.paymentsApi.requestProofInfo(this.verifyingProof.id, this.infoNote).subscribe({
      next: (response) => {
        this.isVerifySaving = false;
        this.requestsMessageType = 'success';
        this.requestsMessage = response.message;
        this.closeVerification();
        this.loadRequests();
      },
      error: (error: unknown) => {
        this.isVerifySaving = false;
        this.verifyMessage = formatApiError(error, 'Could not send the request.');
      }
    });
  }

  private blankRequestForm() {
    return {
      title: '',
      description: '',
      requested_amount: '',
      requested_currency: 'USD',
      due_date: '',
      notes: ''
    };
  }

  get sharedCount(): number {
    return this.methods.filter((method) => method.shared).length;
  }

  get hasSharingChanges(): boolean {
    const current = this.methods.filter((m) => m.shared).map((m) => m.id).sort();
    return JSON.stringify(current) !== JSON.stringify(this.originalSharedIds);
  }

  loadMethods(): void {
    if (!this.clientId) return;
    this.paymentsApi.getClientMethodAccess(this.clientId).subscribe({
      next: (response) => {
        this.methods = response.methods;
        this.originalSharedIds = response.methods.filter((m) => m.shared).map((m) => m.id).sort();
      },
      error: (error: unknown) => {
        this.methodsMessageType = 'error';
        this.methodsMessage = formatApiError(error, 'Payment methods could not be loaded.');
      }
    });
  }

  saveSharing(): void {
    const sharedIds = this.methods.filter((m) => m.shared).map((m) => m.id);

    this.isSavingMethods = true;
    this.methodsMessage = '';

    this.paymentsApi.updateClientMethodAccess(this.clientId, sharedIds).subscribe({
      next: (response) => {
        this.isSavingMethods = false;
        this.methodsMessageType = 'success';
        this.methodsMessage = response.message;
        this.originalSharedIds = [...sharedIds].sort();
      },
      error: (error: unknown) => {
        this.isSavingMethods = false;
        this.methodsMessageType = 'error';
        this.methodsMessage = formatApiError(error, 'Sharing could not be updated.');
        this.loadMethods();
      }
    });
  }

  categoryLabel(category: string): string {
    const labels: Record<string, string> = {
      upi: 'UPI',
      google_pay: 'Google Pay',
      phonepe: 'PhonePe',
      paytm: 'Paytm',
      bank_transfer: 'Bank Transfer',
      zelle: 'Zelle',
      venmo: 'Venmo',
      cash_app: 'Cash App',
      paypal_manual: 'PayPal (manual transfer)',
      cash: 'Cash',
      other: 'Other'
    };
    return labels[category] || category;
  }
}
