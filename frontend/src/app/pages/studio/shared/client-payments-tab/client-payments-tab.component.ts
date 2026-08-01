import { DatePipe, DecimalPipe } from '@angular/common';
import { Component, Input, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  CreatePaymentRequestPayload,
  ManualPaymentMethodRecord,
  PaymentActivityItem,
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
  overpaid: 'Overpaid',
  rejected: 'Rejected',
  cancelled: 'Cancelled',
  overdue: 'Overdue',
  refunded: 'Refunded'
};

type PaymentsSubTab = 'summary' | 'requests' | 'transactions' | 'methods' | 'activity';
type TransactionView = 'manual' | 'integrated';
type RequestListMode = 'active' | 'completed';

@Component({
  selector: 'app-client-payments-tab',
  standalone: true,
  imports: [DatePipe, DecimalPipe, FormsModule, RouterLink],
  templateUrl: './client-payments-tab.component.html',
  styleUrl: './client-payments-tab.component.scss'
})
export class ClientPaymentsTabComponent implements OnInit {
  private readonly paymentsApi = inject(PaymentsApiService);
  private readonly confirmation = inject(ConfirmationDialogService);
  private readonly route = inject(ActivatedRoute);

  @Input({ required: true }) clientId = 0;
  @Input() clientName = '';

  requests: PaymentRequestRecord[] = [];
  isLoadingRequests = true;
  requestsMessage = '';
  requestsMessageType: 'success' | 'error' = 'success';
  showRequestForm = false;
  editingRequestId = '';
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
  settlementStatus: 'partial' | 'full' | 'overpaid' = 'partial';
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
  activityItems: PaymentActivityItem[] = [];
  activityLoadError = '';

  readonly subTabs: { id: PaymentsSubTab; label: string }[] = [
    { id: 'summary', label: 'Summary' },
    { id: 'methods', label: 'Available Payment Methods' },
    { id: 'requests', label: 'Payment Requests' },
    { id: 'transactions', label: 'Transactions' },
    { id: 'activity', label: 'Payment Activity' }
  ];

  activeSubTab: PaymentsSubTab = 'summary';
  transactionView: TransactionView = 'manual';
  requestListMode: RequestListMode = 'active';
  targetedRequestId = '';

  methods: (ManualPaymentMethodRecord & { shared: boolean })[] = [];
  methodsMessage = '';
  methodsMessageType: 'success' | 'error' = 'success';
  isSavingMethods = false;
  private originalSharedIds: number[] = [];

  ngOnInit(): void {
    const requestedValue = this.route.snapshot.queryParamMap.get('paymentTab');
    if (requestedValue === 'history' || requestedValue === 'integrated') {
      this.activeSubTab = 'transactions';
      this.transactionView = requestedValue === 'integrated' ? 'integrated' : 'manual';
    }
    const requestedSubTab = requestedValue as PaymentsSubTab | null;
    if (requestedSubTab && this.subTabs.some((tab) => tab.id === requestedSubTab)) {
      this.activeSubTab = requestedSubTab;
    }
    this.targetedRequestId = this.route.snapshot.queryParamMap.get('request') || '';
    this.loadMethods();
    this.loadRequests();
    this.loadRecords();
    this.loadReconciliation();
    this.loadActivity();
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
    return this.manualRecords
      .filter((r) => r.reporting_currency === this.reportingCurrency)
      .reduce((sum, r) => sum + Number(r.reporting_amount), 0);
  }

  loadActivity(): void {
    this.paymentsApi.getProfessionalPaymentActivity(this.clientId).subscribe({
      next: (response) => (this.activityItems = response.items),
      error: (error: unknown) => (this.activityLoadError = formatApiError(error, 'Payment activity could not be loaded.'))
    });
  }

  get manualRecords(): PaymentRecordRow[] {
    return this.records.filter((record) => record.record_type === 'manual_log');
  }

  showReportingAmount(record: PaymentRecordRow): boolean {
    return record.original_currency !== record.reporting_currency || Number(record.original_amount) !== Number(record.reporting_amount);
  }

  get manualLoggedTotal(): number {
    return this.manualRecords
      .filter((record) => record.reporting_currency === this.reportingCurrency)
      .reduce((sum, record) => sum + Number(record.reporting_amount), 0);
  }

  get integratedTotal(): number { return 0; }

  get totalLoggedAmount(): number { return this.manualLoggedTotal + this.integratedTotal; }

  get activeRequests(): PaymentRequestRecord[] {
    return this.requests.filter((request) => this.isOpenStatus(request.status));
  }

  get completedRequests(): PaymentRequestRecord[] {
    return this.requests.filter((request) => !this.isOpenStatus(request.status));
  }

  get displayedRequests(): PaymentRequestRecord[] {
    return this.requestListMode === 'active' ? this.activeRequests : this.completedRequests;
  }

  get reviewRequestCount(): number {
    return this.requests.filter((request) => this.needsReview(request.status)).length;
  }

  get overdueRequestCount(): number {
    return this.requests.filter((request) => request.status === 'overdue').length;
  }

  get overpaidRequests(): PaymentRequestRecord[] {
    return this.requests.filter((request) => Number(request.overpaid_amount) > 0);
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
      client_visibility: 'private',
      internal_note: this.recordForm.internal_note,
      client_note: ''
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
      internal_note: ''
    };
  }

  get sharedMethods(): (ManualPaymentMethodRecord & { shared: boolean })[] {
    return this.methods.filter((method) => method.shared && method.status === 'active');
  }

  /** Distinguishes "no payment method configured anywhere" (go create one in
   *  Settings) from "methods exist but none are shared with this client yet"
   *  (go share one, further down this same tab) -- Request Payment must not
   *  open a broken form in either case. */
  get hasAnyActivePaymentMethod(): boolean {
    return this.methods.some((method) => method.status === 'active');
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
      next: (response) => {
        this.requests = response.requests;
        this.isLoadingRequests = false;
        this.focusTargetedRequest();
      },
      error: (error: unknown) => {
        this.requestsMessageType = 'error';
        this.requestsMessage = formatApiError(error, 'Payment requests could not be loaded.');
        this.isLoadingRequests = false;
      }
    });
  }

  private focusTargetedRequest(): void {
    if (!this.targetedRequestId) return;
    this.activeSubTab = 'requests';
    setTimeout(() => {
      document.getElementById(`payment-request-${this.targetedRequestId}`)?.scrollIntoView({
        behavior: 'smooth',
        block: 'center'
      });
    });
  }

  openRequestForm(): void {
    // Use the professional's locked reporting currency as the convenient
    // default. The form's currency selector remains editable for requests
    // that intentionally use another currency.
    this.requestForm = this.blankRequestForm(this.reportingCurrency);
    this.allowedMethodSelection = {};
    for (const method of this.sharedMethods) {
      this.allowedMethodSelection[method.id] = true;
    }
    this.requestFormMessage = '';
    this.editingRequestId = '';
    this.showRequestForm = true;
  }

  openEditRequest(request: PaymentRequestRecord): void {
    this.editingRequestId = request.request_id;
    this.requestForm = {
      title: request.title,
      description: request.description,
      requested_amount: request.requested_amount,
      requested_currency: request.requested_currency,
      due_date: request.due_date || '',
      notes: request.notes
    };
    this.allowedMethodSelection = {};
    for (const method of this.sharedMethods) {
      this.allowedMethodSelection[method.id] = request.allowed_method_labels.includes(method.display_label);
    }
    this.requestFormMessage = '';
    this.showRequestForm = true;
  }

  canEditRequest(request: PaymentRequestRecord): boolean {
    return !request.is_locked && !['cancelled', 'refunded', 'rejected'].includes(request.status);
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

    const saveRequest$ = this.editingRequestId
      ? this.paymentsApi.updatePaymentRequest(this.editingRequestId, payload)
      : this.paymentsApi.createPaymentRequest(this.clientId, payload);
    saveRequest$.subscribe({
      next: (response) => {
        this.isSavingRequest = false;
        this.showRequestForm = false;
        this.editingRequestId = '';
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
    this.settlementStatus = 'partial';
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
        this.settlementStatus = this.recommendedSettlementStatus;
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
      .acknowledgePaymentProof(this.verifyingProof.id, {
        acknowledgement_note: this.acknowledgementNote,
        settlement_status: this.settlementStatus
      })
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

  get acceptedAfterCurrentProof(): number {
    if (!this.verifyingRequest || !this.verifyingProof) return 0;
    return Number(this.verifyingRequest.accepted_amount) +
      (this.verifyingProof.reported_currency === this.verifyingRequest.requested_currency
        ? Number(this.verifyingProof.reported_amount)
        : 0);
  }

  get recommendedSettlementStatus(): 'partial' | 'full' | 'overpaid' {
    if (!this.verifyingRequest) return 'partial';
    const total = this.acceptedAfterCurrentProof;
    const requested = Number(this.verifyingRequest.requested_amount);
    if (total > requested) return 'overpaid';
    if (total === requested) return 'full';
    return 'partial';
  }

  get remainingAfterCurrentProof(): number {
    if (!this.verifyingRequest) return 0;
    return Math.max(0, Number(this.verifyingRequest.requested_amount) - this.acceptedAfterCurrentProof);
  }

  get overpaidAfterCurrentProof(): number {
    if (!this.verifyingRequest) return 0;
    return Math.max(0, this.acceptedAfterCurrentProof - Number(this.verifyingRequest.requested_amount));
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

  private blankRequestForm(requestedCurrency = 'USD') {
    return {
      title: '',
      description: '',
      requested_amount: '',
      requested_currency: requestedCurrency,
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
