import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export interface PaymentSettingsRecord {
  payment_tracking_enabled: boolean;
  /** False while the payments gateway flag is off: every write on the payment
   *  settings screen is refused with 503 until it is turned on. */
  payments_enabled?: boolean;
  reporting_currency: string;
  // Gates the payments dashboard/summary only — toggleable anytime, not a
  // one-way lock. Manual payment method setup is unaffected by this.
  reporting_currency_locked: boolean;
  reporting_currency_locked_at: string | null;
  client_payment_history_enabled: boolean;
  updated_at: string;
}

export type RevenuePeriod = '7' | '30' | '90' | 'lifetime' | 'custom';

export interface RevenueSeriesPoint {
  label: string;
  total: string;
}

export interface RevenueTransaction {
  payment_record_id: string;
  client_id: number;
  client_name: string;
  amount: string;
  currency: string;
  status: 'completed' | 'partially_paid' | 'refunded';
  received_date: string;
}

export interface RevenueSummaryResponse {
  reporting_currency: string;
  this_month_total: string;
  period: RevenuePeriod;
  period_start: string;
  period_end: string;
  total_revenue: string;
  manual_logged_total: string;
  integrated_total: string;
  total_logged: string;
  // Backend picks the chart shape to match the span: <=30 days is a bar
  // chart, longer spans switch to a line chart (weekly/monthly buckets).
  chart_kind: 'bar' | 'line';
  series: RevenueSeriesPoint[];
  recent_transactions: RevenueTransaction[];
}

export interface PaymentSettingsResponse {
  settings: PaymentSettingsRecord;
  currency_options: string[];
  message?: string;
}

export interface FinancialTransactionRecord {
  entry_id: string;
  entry_type: string;
  source: string;
  status: string;
  amount: string;
  currency: string;
  client_reference: string;
  payment_request_reference: string;
  payment_record_reference: string;
  external_reference: string;
  provider: string;
  description: string;
  occurred_at: string;
}

export type ManualPaymentCategory =
  | 'upi'
  | 'google_pay'
  | 'phonepe'
  | 'paytm'
  | 'bank_transfer'
  | 'zelle'
  | 'venmo'
  | 'cash_app'
  | 'paypal_manual'
  | 'cash'
  | 'other';

export interface ManualPaymentMethodRecord {
  id: number;
  name: string;
  category: ManualPaymentCategory;
  display_label: string;
  supported_currencies: string[];
  country: string;
  private_fields: Record<string, string>;
  client_visible_fields: Record<string, string>;
  qr_code: string | null;
  internal_notes: string;
  client_instructions: string;
  status: 'active' | 'inactive';
  created_at: string;
  updated_at: string;
}

export interface ManualPaymentMethodListResponse {
  methods: ManualPaymentMethodRecord[];
  max_active: number;
}

export interface ManualPaymentMethodResponse {
  method: ManualPaymentMethodRecord;
  message: string;
}

export interface ManualPaymentMethodClientView {
  id: number;
  category: ManualPaymentCategory;
  display_label: string;
  supported_currencies: string[];
  client_visible_fields: Record<string, string>;
  qr_code: string | null;
  client_instructions: string;
}

export type PaymentRequestStatus =
  | 'draft'
  | 'sent'
  | 'viewed'
  | 'proof_submitted'
  | 'under_review'
  | 'acknowledged'
  | 'completed'
  | 'partially_paid'
  | 'overpaid'
  | 'rejected'
  | 'cancelled'
  | 'overdue'
  | 'refunded';

export interface PaymentRequestRecord {
  id: number;
  request_id: string;
  client: number;
  client_name: string;
  payment_plan: number | null;
  title: string;
  description: string;
  requested_amount: string;
  requested_currency: string;
  accepted_amount: string;
  remaining_amount: string;
  overpaid_amount: string;
  due_date: string | null;
  payment_type: 'manual' | 'integrated' | 'both';
  status: PaymentRequestStatus;
  client_visibility: 'private' | 'visible';
  notes: string;
  allowed_method_labels: string[];
  created_at: string;
  sent_at: string | null;
  viewed_at: string | null;
  completed_at: string | null;
  correction_deadline: string | null;
  is_locked: boolean;
  updated_at: string;
}

export interface CreatePaymentRequestPayload {
  title: string;
  description: string;
  requested_amount: string;
  requested_currency: string;
  due_date: string | null;
  payment_type: 'manual' | 'integrated' | 'both';
  client_visibility: 'private' | 'visible';
  notes: string;
  allowed_method_ids: number[];
}

export interface ClientPaymentRequestRecord {
  request_id: string;
  professional_name: string;
  title: string;
  description: string;
  requested_amount: string;
  requested_currency: string;
  accepted_amount: string;
  remaining_amount: string;
  overpaid_amount: string;
  due_date: string | null;
  payment_type: 'manual' | 'integrated' | 'both';
  status: PaymentRequestStatus;
  available_methods: ManualPaymentMethodClientView[];
  proofs: PaymentProofRecord[];
  created_at: string;
  sent_at: string | null;
  correction_deadline: string | null;
  is_locked: boolean;
}

export interface PaymentProofRecord {
  id: number;
  transaction_reference: string;
  reported_amount: string;
  reported_currency: string;
  reported_payment_date: string;
  payment_method: number | null;
  payment_method_label: string;
  has_file: boolean;
  payment_record_id: string;
  note: string;
  status: 'submitted' | 'under_review' | 'accepted' | 'rejected';
  review_note: string;
  submitted_by: string;
  submitted_at: string;
  reviewed_at: string | null;
}

export interface PaymentRecordRow {
  id: number;
  payment_record_id: string;
  client_name: string;
  request_reference: string;
  original_amount: string;
  original_currency: string;
  reporting_amount: string;
  reporting_currency: string;
  payment_method_label: string;
  transaction_reference: string;
  received_date: string;
  status: 'completed' | 'partially_paid' | 'refunded';
  client_visibility: 'private' | 'visible';
  internal_note: string;
  client_note: string;
  verified_at: string | null;
  editable_until: string;
  is_locked: boolean;
  record_type: 'manual_log' | 'acknowledged_payment';
}

export interface PaymentRequestDetailResponse {
  request: PaymentRequestRecord;
  proofs: PaymentProofRecord[];
  records: PaymentRecordRow[];
}

export interface SubmitProofPayload {
  transaction_reference: string;
  reported_amount: string;
  reported_currency: string;
  reported_payment_date: string;
  payment_method: number | null;
  note: string;
  confirmed_accurate: boolean;
}

export interface PaymentActionItem {
  request_id: string;
  client_id: number;
  client_name: string;
  title: string;
  requested_amount: string;
  requested_currency: string;
  due_date: string | null;
  status: PaymentRequestStatus;
  updated_at: string;
}

export interface PaymentActionsResponse {
  items: PaymentActionItem[];
  review_count: number;
  overdue_count: number;
  action_count: number;
}

export interface PaymentNotificationItem {
  id: number;
  notif_type: string;
  title: string;
  body: string;
  payload: { request_id?: string; [key: string]: unknown };
  is_read: boolean;
  created_at: string;
}

export interface PaymentNotificationsResponse {
  unread_count: number;
  items: PaymentNotificationItem[];
}

export interface PaymentConfirmation {
  payment_record_id: string;
  request_reference: string;
  professional_name: string;
  client_name: string;
  amount_recorded: string;
  original_currency: string;
  reporting_amount: string;
  reporting_currency: string;
  payment_method_label: string;
  transaction_reference: string;
  received_date: string;
  confirmed_date: string;
  status: string;
  professional_note: string;
}

export interface RecordReceivedPayload {
  client: number;
  payment_request_id?: string;
  original_amount: string;
  original_currency: string;
  reporting_amount: string;
  reporting_currency: string;
  payment_method?: number | null;
  transaction_reference: string;
  received_date: string;
  status: 'completed' | 'partially_paid';
  client_visibility: 'private' | 'visible';
  internal_note: string;
  client_note: string;
}

export interface AcknowledgeProofPayload {
  acknowledgement_note?: string;
  settlement_status: 'partial' | 'full' | 'overpaid';
}

export interface PaymentActivityItem {
  id: number;
  action: string;
  action_label: string;
  request_id: string;
  record_id: string;
  changed_by: string;
  reason: string;
  created_at: string;
}

export interface PaymentReconciliationSummary {
  acknowledged_count: number;
  logged_count: number;
  unlogged_count: number;
  unlogged_requests: {
    request_id: string;
    client_id: number;
    client_name: string;
    title: string;
    requested_amount: string;
    requested_currency: string;
    updated_at: string;
  }[];
}

/**
 * Client Payments — money professionals collect from their own clients.
 * Completely separate from ProfessionalAuthApiService's billing methods,
 * which cover the professional's own RepRoot subscription.
 */
@Injectable({ providedIn: 'root' })
export class PaymentsApiService {
  private readonly apiBaseUrl = this.getApiBaseUrl();

  constructor(private readonly http: HttpClient) {}

  getPaymentSettings(): Observable<PaymentSettingsResponse> {
    return this.http.get<PaymentSettingsResponse>(`${this.apiBaseUrl}/professional/payments/settings/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  updatePaymentSettings(changes: Partial<PaymentSettingsRecord> & { confirm_reporting_currency?: boolean }): Observable<PaymentSettingsResponse> {
    return this.http.put<PaymentSettingsResponse>(`${this.apiBaseUrl}/professional/payments/settings/`, changes, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  getTransactionLedger(): Observable<{ transactions: FinancialTransactionRecord[] }> {
    return this.http.get<{ transactions: FinancialTransactionRecord[] }>(`${this.apiBaseUrl}/professional/payments/transactions/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  getRevenueSummary(period: RevenuePeriod, customStart?: string, customEnd?: string): Observable<RevenueSummaryResponse> {
    const params: Record<string, string> = { period };
    if (period === 'custom' && customStart && customEnd) {
      params['start'] = customStart;
      params['end'] = customEnd;
    }
    return this.http.get<RevenueSummaryResponse>(`${this.apiBaseUrl}/professional/payments/revenue-summary/`, {
      headers: this.getProfessionalAuthHeaders(),
      params
    });
  }

  getPaymentMethods(): Observable<ManualPaymentMethodListResponse> {
    return this.http.get<ManualPaymentMethodListResponse>(`${this.apiBaseUrl}/professional/payments/methods/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  createPaymentMethod(payload: FormData): Observable<ManualPaymentMethodResponse> {
    return this.http.post<ManualPaymentMethodResponse>(`${this.apiBaseUrl}/professional/payments/methods/`, payload, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  updatePaymentMethod(methodId: number, payload: FormData): Observable<ManualPaymentMethodResponse> {
    return this.http.put<ManualPaymentMethodResponse>(
      `${this.apiBaseUrl}/professional/payments/methods/${methodId}/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  setPaymentMethodStatus(methodId: number, statusValue: 'active' | 'inactive'): Observable<ManualPaymentMethodResponse> {
    return this.http.put<ManualPaymentMethodResponse>(
      `${this.apiBaseUrl}/professional/payments/methods/${methodId}/`,
      { status: statusValue },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  deletePaymentMethod(methodId: number): Observable<{ message: string }> {
    return this.http.delete<{ message: string }>(`${this.apiBaseUrl}/professional/payments/methods/${methodId}/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  previewPaymentMethod(methodId: number): Observable<{ preview: ManualPaymentMethodClientView }> {
    return this.http.get<{ preview: ManualPaymentMethodClientView }>(
      `${this.apiBaseUrl}/professional/payments/methods/${methodId}/preview/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getClientMethodAccess(clientId: number): Observable<{ methods: (ManualPaymentMethodRecord & { shared: boolean })[] }> {
    return this.http.get<{ methods: (ManualPaymentMethodRecord & { shared: boolean })[] }>(
      `${this.apiBaseUrl}/professional/payments/clients/${clientId}/methods/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  updateClientMethodAccess(clientId: number, methodIds: number[]): Observable<{ message: string }> {
    return this.http.put<{ message: string }>(
      `${this.apiBaseUrl}/professional/payments/clients/${clientId}/methods/`,
      { method_ids: methodIds },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getClientPaymentRequests(clientId: number): Observable<{ requests: PaymentRequestRecord[] }> {
    return this.http.get<{ requests: PaymentRequestRecord[] }>(
      `${this.apiBaseUrl}/professional/payments/clients/${clientId}/requests/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  createPaymentRequest(
    clientId: number,
    payload: CreatePaymentRequestPayload
  ): Observable<{ request: PaymentRequestRecord; message: string }> {
    return this.http.post<{ request: PaymentRequestRecord; message: string }>(
      `${this.apiBaseUrl}/professional/payments/clients/${clientId}/requests/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  cancelPaymentRequest(requestId: string, reason = ''): Observable<{ request: PaymentRequestRecord; message: string }> {
    return this.http.post<{ request: PaymentRequestRecord; message: string }>(
      `${this.apiBaseUrl}/professional/payments/requests/${requestId}/cancel/`,
      { reason },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getPaymentRequestDetail(requestId: string): Observable<PaymentRequestDetailResponse> {
    return this.http.get<PaymentRequestDetailResponse>(
      `${this.apiBaseUrl}/professional/payments/requests/${requestId}/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  acknowledgePaymentProof(proofId: number, payload: AcknowledgeProofPayload): Observable<{ message: string; needs_logging: boolean }> {
    return this.http.post<{ message: string; needs_logging: boolean }>(
      `${this.apiBaseUrl}/professional/payments/proofs/${proofId}/acknowledge/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getPaymentReconciliation(): Observable<PaymentReconciliationSummary> {
    return this.http.get<PaymentReconciliationSummary>(`${this.apiBaseUrl}/professional/payments/reconciliation/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  rejectPaymentProof(proofId: number, reason: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/professional/payments/proofs/${proofId}/reject/`,
      { reason },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  requestProofInfo(proofId: number, note: string): Observable<{ message: string }> {
    return this.http.post<{ message: string }>(
      `${this.apiBaseUrl}/professional/payments/proofs/${proofId}/request-info/`,
      { note },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  submitPaymentProof(requestId: string, payload: FormData): Observable<{ message: string; proof: PaymentProofRecord; request: ClientPaymentRequestRecord }> {
    return this.http.post<{ message: string; proof: PaymentProofRecord; request: ClientPaymentRequestRecord }>(
      `${this.apiBaseUrl}/client/payments/requests/${requestId}/proof/`,
      payload,
      { headers: this.getClientAuthHeaders() }
    );
  }

  getClientPaymentRecords(clientId: number): Observable<{ records: PaymentRecordRow[] }> {
    return this.http.get<{ records: PaymentRecordRow[] }>(
      `${this.apiBaseUrl}/professional/payments/records/`,
      { headers: this.getProfessionalAuthHeaders(), params: { client_id: String(clientId) } }
    );
  }

  recordReceivedPayment(payload: RecordReceivedPayload): Observable<{ record: PaymentRecordRow; message: string }> {
    return this.http.post<{ record: PaymentRecordRow; message: string }>(
      `${this.apiBaseUrl}/professional/payments/records/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  editPaymentRecord(
    recordId: string,
    changes: Partial<RecordReceivedPayload> & { reason: string }
  ): Observable<{ record: PaymentRecordRow; message: string }> {
    return this.http.put<{ record: PaymentRecordRow; message: string }>(
      `${this.apiBaseUrl}/professional/payments/records/${recordId}/`,
      changes,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getPaymentConfirmation(recordId: string): Observable<{ confirmation: PaymentConfirmation }> {
    return this.http.get<{ confirmation: PaymentConfirmation }>(
      `${this.apiBaseUrl}/professional/payments/records/${recordId}/confirmation/`,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getClientPaymentConfirmation(recordId: string): Observable<{ confirmation: PaymentConfirmation }> {
    return this.http.get<{ confirmation: PaymentConfirmation }>(
      `${this.apiBaseUrl}/client/payments/records/${recordId}/confirmation/`,
      { headers: this.getClientAuthHeaders() }
    );
  }

  getPaymentActions(): Observable<PaymentActionsResponse> {
    return this.http.get<PaymentActionsResponse>(`${this.apiBaseUrl}/professional/payments/actions/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  updatePaymentRequest(requestId: string, payload: CreatePaymentRequestPayload): Observable<{ request: PaymentRequestRecord; message: string }> {
    return this.http.put<{ request: PaymentRequestRecord; message: string }>(
      `${this.apiBaseUrl}/professional/payments/requests/${requestId}/`,
      payload,
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getProfessionalPaymentActivity(clientId?: number): Observable<{ items: PaymentActivityItem[] }> {
    return this.http.get<{ items: PaymentActivityItem[] }>(`${this.apiBaseUrl}/professional/payments/activity/`, {
      headers: this.getProfessionalAuthHeaders(),
      params: clientId ? { client_id: String(clientId) } : {}
    });
  }

  getClientPaymentActivity(): Observable<{ items: PaymentActivityItem[] }> {
    return this.http.get<{ items: PaymentActivityItem[] }>(`${this.apiBaseUrl}/client/payments/activity/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  getProfessionalPaymentUnread(): Observable<PaymentNotificationsResponse> {
    return this.http.get<PaymentNotificationsResponse>(`${this.apiBaseUrl}/professional/payments/notifications/`, {
      headers: this.getProfessionalAuthHeaders()
    });
  }

  /** Pass a requestId to clear just that request's unread notifications (the
   * normal path, called when its detail page is opened); omit it and pass
   * markAll=true only for an explicit "mark all as read" action. */
  markProfessionalPaymentNotificationsRead(requestId?: string, markAll = false): Observable<{ unread_count: number }> {
    return this.http.post<{ unread_count: number }>(
      `${this.apiBaseUrl}/professional/payments/notifications/`,
      requestId ? { request_id: requestId } : { mark_all: markAll || true },
      { headers: this.getProfessionalAuthHeaders() }
    );
  }

  getMyPaymentRequests(): Observable<{ requests: ClientPaymentRequestRecord[] }> {
    return this.http.get<{ requests: ClientPaymentRequestRecord[] }>(`${this.apiBaseUrl}/client/payments/requests/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  getMyPaymentRequestDetail(requestId: string): Observable<{ request: ClientPaymentRequestRecord }> {
    return this.http.get<{ request: ClientPaymentRequestRecord }>(
      `${this.apiBaseUrl}/client/payments/requests/${requestId}/`,
      { headers: this.getClientAuthHeaders() }
    );
  }

  getClientPaymentUnread(): Observable<PaymentNotificationsResponse> {
    return this.http.get<PaymentNotificationsResponse>(`${this.apiBaseUrl}/client/payments/notifications/`, {
      headers: this.getClientAuthHeaders()
    });
  }

  /** Pass a requestId to clear just that request's unread notifications (the
   * normal path, called when its detail page is opened); omit it and pass
   * markAll=true only for an explicit "mark all as read" action. */
  markClientPaymentNotificationsRead(requestId?: string, markAll = false): Observable<{ unread_count: number }> {
    return this.http.post<{ unread_count: number }>(
      `${this.apiBaseUrl}/client/payments/notifications/`,
      requestId ? { request_id: requestId } : { mark_all: markAll || true },
      { headers: this.getClientAuthHeaders() }
    );
  }

  private getProfessionalAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('professional-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `Token ${token}` } : {});
  }

  private getClientAuthHeaders(): HttpHeaders {
    const token = window.sessionStorage.getItem('client-auth-token') || '';
    return new HttpHeaders(token ? { Authorization: `ClientToken ${token}` } : {});
  }

  private getApiBaseUrl(): string {
    const configuredBaseUrl = window.APP_CONFIG?.apiBaseUrl?.trim();

    if (configuredBaseUrl) {
      return `${configuredBaseUrl.replace(/\/$/, '')}/api/accounts`;
    }

    if (['localhost', '127.0.0.1', '10.0.2.2'].includes(window.location.hostname)) {
      return `http://${window.location.hostname}:8000/api/accounts`;
    }
    throw new Error('RepRoot API configuration is missing. Set APP_CONFIG.apiBaseUrl for this deployment.');
  }
}
