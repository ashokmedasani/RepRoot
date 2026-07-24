/// Client Payments — money professionals collect from their own clients.
/// 1:1 port of the interfaces in
/// mobile/src/app/core/api/payments-api.service.ts.
/// Field names match the Django payloads exactly; do not rename them.
library;

class PaymentSettingsRecord {
  const PaymentSettingsRecord({
    required this.paymentTrackingEnabled,
    required this.reportingCurrency,
    required this.reportingCurrencyLocked,
    required this.clientPaymentHistoryEnabled,
    required this.updatedAt,
  });

  final bool paymentTrackingEnabled;
  final String reportingCurrency;
  final bool reportingCurrencyLocked;
  final bool clientPaymentHistoryEnabled;
  final String updatedAt;

  factory PaymentSettingsRecord.fromJson(Map<String, dynamic> json) =>
      PaymentSettingsRecord(
        paymentTrackingEnabled: json['payment_tracking_enabled'] as bool? ?? false,
        reportingCurrency: json['reporting_currency'] as String? ?? 'USD',
        reportingCurrencyLocked: json['reporting_currency_locked'] as bool? ?? false,
        clientPaymentHistoryEnabled:
            json['client_payment_history_enabled'] as bool? ?? false,
        updatedAt: json['updated_at'] as String? ?? '',
      );
}

class PaymentSettingsResponse {
  const PaymentSettingsResponse({
    required this.settings,
    required this.currencyOptions,
  });

  final PaymentSettingsRecord settings;
  final List<String> currencyOptions;

  factory PaymentSettingsResponse.fromJson(Map<String, dynamic> json) =>
      PaymentSettingsResponse(
        settings: PaymentSettingsRecord.fromJson(
          json['settings'] as Map<String, dynamic>? ?? {},
        ),
        currencyOptions: (json['currency_options'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .toList(),
      );
}

/// Manual payment method categories the backend accepts.
class ManualPaymentCategory {
  const ManualPaymentCategory._();
  static const all = [
    'upi', 'google_pay', 'phonepe', 'paytm', 'bank_transfer', 'zelle',
    'venmo', 'cash_app', 'paypal_manual', 'cash', 'other',
  ];
  static String label(String category) => switch (category) {
        'upi' => 'UPI',
        'google_pay' => 'Google Pay',
        'phonepe' => 'PhonePe',
        'paytm' => 'Paytm',
        'bank_transfer' => 'Bank transfer',
        'zelle' => 'Zelle',
        'venmo' => 'Venmo',
        'cash_app' => 'Cash App',
        'paypal_manual' => 'PayPal (manual)',
        'cash' => 'Cash',
        'other' => 'Other',
        _ => category,
      };
}

class ManualPaymentMethodRecord {
  const ManualPaymentMethodRecord({
    required this.id,
    required this.name,
    required this.category,
    required this.displayLabel,
    required this.supportedCurrencies,
    required this.country,
    required this.clientVisibleFields,
    required this.qrCode,
    required this.internalNotes,
    required this.clientInstructions,
    required this.status,
    this.shared = false,
  });

  final int id;
  final String name;
  final String category;
  final String displayLabel;
  final List<String> supportedCurrencies;
  final String country;
  final Map<String, String> clientVisibleFields;
  final String? qrCode;
  final String internalNotes;
  final String clientInstructions;
  final String status; // 'active' | 'inactive'
  final bool shared; // only present in per-client access listing

  bool get isActive => status == 'active';

  factory ManualPaymentMethodRecord.fromJson(Map<String, dynamic> json) =>
      ManualPaymentMethodRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'other',
        displayLabel: json['display_label'] as String? ?? '',
        supportedCurrencies: (json['supported_currencies'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .toList(),
        country: json['country'] as String? ?? '',
        clientVisibleFields:
            (json['client_visible_fields'] as Map<dynamic, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ),
        qrCode: json['qr_code'] as String?,
        internalNotes: json['internal_notes'] as String? ?? '',
        clientInstructions: json['client_instructions'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        shared: json['shared'] as bool? ?? false,
      );
}

/// The method as a client sees it (subset).
class ManualPaymentMethodClientView {
  const ManualPaymentMethodClientView({
    required this.id,
    required this.category,
    required this.displayLabel,
    required this.supportedCurrencies,
    required this.clientVisibleFields,
    required this.qrCode,
    required this.clientInstructions,
  });

  final int id;
  final String category;
  final String displayLabel;
  final List<String> supportedCurrencies;
  final Map<String, String> clientVisibleFields;
  final String? qrCode;
  final String clientInstructions;

  factory ManualPaymentMethodClientView.fromJson(Map<String, dynamic> json) =>
      ManualPaymentMethodClientView(
        id: (json['id'] as num?)?.toInt() ?? 0,
        category: json['category'] as String? ?? 'other',
        displayLabel: json['display_label'] as String? ?? '',
        supportedCurrencies: (json['supported_currencies'] as List<dynamic>? ?? [])
            .map((c) => c.toString())
            .toList(),
        clientVisibleFields:
            (json['client_visible_fields'] as Map<dynamic, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        ),
        qrCode: json['qr_code'] as String?,
        clientInstructions: json['client_instructions'] as String? ?? '',
      );
}

/// Human labels for the many payment-request statuses.
class PaymentRequestStatus {
  const PaymentRequestStatus._();
  static String label(String status) => switch (status) {
        'draft' => 'Draft',
        'sent' => 'Sent',
        'viewed' => 'Viewed',
        'proof_submitted' => 'Proof submitted',
        'under_review' => 'Under review',
        'acknowledged' => 'Acknowledged',
        'completed' => 'Completed',
        'partially_paid' => 'Partially paid',
        'rejected' => 'Rejected',
        'cancelled' => 'Cancelled',
        'overdue' => 'Overdue',
        'refunded' => 'Refunded',
        _ => status,
      };

  /// Statuses where the professional still owes an action.
  static const openForProfessional = {
    'proof_submitted', 'under_review', 'overdue',
  };
}

class PaymentRequestRecord {
  const PaymentRequestRecord({
    required this.id,
    required this.requestId,
    required this.client,
    required this.clientName,
    required this.title,
    required this.description,
    required this.requestedAmount,
    required this.requestedCurrency,
    required this.dueDate,
    required this.paymentType,
    required this.status,
    required this.clientVisibility,
    required this.notes,
    required this.allowedMethodLabels,
    required this.createdAt,
  });

  final int id;
  final String requestId;
  final int client;
  final String clientName;
  final String title;
  final String description;
  final String requestedAmount;
  final String requestedCurrency;
  final String? dueDate;
  final String paymentType; // 'manual' | 'integrated' | 'both'
  final String status;
  final String clientVisibility; // 'private' | 'visible'
  final String notes;
  final List<String> allowedMethodLabels;
  final String createdAt;

  factory PaymentRequestRecord.fromJson(Map<String, dynamic> json) =>
      PaymentRequestRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        requestId: json['request_id'] as String? ?? '',
        client: (json['client'] as num?)?.toInt() ?? 0,
        clientName: json['client_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        requestedAmount: json['requested_amount']?.toString() ?? '0',
        requestedCurrency: json['requested_currency'] as String? ?? 'USD',
        dueDate: json['due_date'] as String?,
        paymentType: json['payment_type'] as String? ?? 'manual',
        status: json['status'] as String? ?? 'sent',
        clientVisibility: json['client_visibility'] as String? ?? 'visible',
        notes: json['notes'] as String? ?? '',
        allowedMethodLabels: (json['allowed_method_labels'] as List<dynamic>? ?? [])
            .map((l) => l.toString())
            .toList(),
        createdAt: json['created_at'] as String? ?? '',
      );
}

class PaymentProofRecord {
  const PaymentProofRecord({
    required this.id,
    required this.transactionReference,
    required this.reportedAmount,
    required this.reportedCurrency,
    required this.reportedPaymentDate,
    required this.paymentMethodLabel,
    required this.hasFile,
    required this.note,
    required this.status,
    required this.reviewNote,
    required this.submittedBy,
    required this.submittedAt,
  });

  final int id;
  final String transactionReference;
  final String reportedAmount;
  final String reportedCurrency;
  final String reportedPaymentDate;
  final String paymentMethodLabel;
  final bool hasFile;
  final String note;
  final String status; // 'submitted' | 'under_review' | 'accepted' | 'rejected'
  final String reviewNote;
  final String submittedBy;
  final String submittedAt;

  factory PaymentProofRecord.fromJson(Map<String, dynamic> json) =>
      PaymentProofRecord(
        id: (json['id'] as num?)?.toInt() ?? 0,
        transactionReference: json['transaction_reference'] as String? ?? '',
        reportedAmount: json['reported_amount']?.toString() ?? '0',
        reportedCurrency: json['reported_currency'] as String? ?? 'USD',
        reportedPaymentDate: json['reported_payment_date'] as String? ?? '',
        paymentMethodLabel: json['payment_method_label'] as String? ?? '',
        hasFile: json['has_file'] as bool? ?? false,
        note: json['note'] as String? ?? '',
        status: json['status'] as String? ?? 'submitted',
        reviewNote: json['review_note'] as String? ?? '',
        submittedBy: json['submitted_by'] as String? ?? '',
        submittedAt: json['submitted_at'] as String? ?? '',
      );
}

class PaymentRecordRow {
  const PaymentRecordRow({
    required this.id,
    required this.paymentRecordId,
    required this.clientName,
    required this.requestReference,
    required this.originalAmount,
    required this.originalCurrency,
    required this.reportingAmount,
    required this.reportingCurrency,
    required this.paymentMethodLabel,
    required this.transactionReference,
    required this.receivedDate,
    required this.status,
    required this.clientVisibility,
    required this.internalNote,
    required this.clientNote,
  });

  final int id;
  final String paymentRecordId;
  final String clientName;
  final String requestReference;
  final String originalAmount;
  final String originalCurrency;
  final String reportingAmount;
  final String reportingCurrency;
  final String paymentMethodLabel;
  final String transactionReference;
  final String receivedDate;
  final String status; // 'completed' | 'partially_paid' | 'refunded'
  final String clientVisibility;
  final String internalNote;
  final String clientNote;

  factory PaymentRecordRow.fromJson(Map<String, dynamic> json) => PaymentRecordRow(
        id: (json['id'] as num?)?.toInt() ?? 0,
        paymentRecordId: json['payment_record_id'] as String? ?? '',
        clientName: json['client_name'] as String? ?? '',
        requestReference: json['request_reference'] as String? ?? '',
        originalAmount: json['original_amount']?.toString() ?? '0',
        originalCurrency: json['original_currency'] as String? ?? 'USD',
        reportingAmount: json['reporting_amount']?.toString() ?? '0',
        reportingCurrency: json['reporting_currency'] as String? ?? 'USD',
        paymentMethodLabel: json['payment_method_label'] as String? ?? '',
        transactionReference: json['transaction_reference'] as String? ?? '',
        receivedDate: json['received_date'] as String? ?? '',
        status: json['status'] as String? ?? 'completed',
        clientVisibility: json['client_visibility'] as String? ?? 'visible',
        internalNote: json['internal_note'] as String? ?? '',
        clientNote: json['client_note'] as String? ?? '',
      );
}

/// Professional-side payment-request detail (request + proofs + records).
class PaymentRequestDetailResponse {
  const PaymentRequestDetailResponse({
    required this.request,
    required this.proofs,
    required this.records,
  });

  final PaymentRequestRecord request;
  final List<PaymentProofRecord> proofs;
  final List<PaymentRecordRow> records;

  factory PaymentRequestDetailResponse.fromJson(Map<String, dynamic> json) =>
      PaymentRequestDetailResponse(
        request: PaymentRequestRecord.fromJson(
          json['request'] as Map<String, dynamic>? ?? {},
        ),
        proofs: (json['proofs'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PaymentProofRecord.fromJson)
            .toList(),
        records: (json['records'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PaymentRecordRow.fromJson)
            .toList(),
      );
}

/// Client-side view of a payment request they owe.
class ClientPaymentRequestRecord {
  const ClientPaymentRequestRecord({
    required this.requestId,
    required this.professionalName,
    required this.title,
    required this.description,
    required this.requestedAmount,
    required this.requestedCurrency,
    required this.dueDate,
    required this.paymentType,
    required this.status,
    required this.availableMethods,
    required this.proofs,
    required this.createdAt,
  });

  final String requestId;
  final String professionalName;
  final String title;
  final String description;
  final String requestedAmount;
  final String requestedCurrency;
  final String? dueDate;
  final String paymentType;
  final String status;
  final List<ManualPaymentMethodClientView> availableMethods;
  final List<PaymentProofRecord> proofs;
  final String createdAt;

  factory ClientPaymentRequestRecord.fromJson(Map<String, dynamic> json) =>
      ClientPaymentRequestRecord(
        requestId: json['request_id'] as String? ?? '',
        professionalName: json['professional_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        requestedAmount: json['requested_amount']?.toString() ?? '0',
        requestedCurrency: json['requested_currency'] as String? ?? 'USD',
        dueDate: json['due_date'] as String?,
        paymentType: json['payment_type'] as String? ?? 'manual',
        status: json['status'] as String? ?? 'sent',
        availableMethods: (json['available_methods'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ManualPaymentMethodClientView.fromJson)
            .toList(),
        proofs: (json['proofs'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PaymentProofRecord.fromJson)
            .toList(),
        createdAt: json['created_at'] as String? ?? '',
      );
}

// ----- revenue summary -----

class RevenueSeriesPoint {
  const RevenueSeriesPoint({required this.label, required this.total});
  final String label;
  final double total;

  factory RevenueSeriesPoint.fromJson(Map<String, dynamic> json) => RevenueSeriesPoint(
        label: json['label']?.toString() ?? '',
        total: double.tryParse(json['total']?.toString() ?? '') ?? 0,
      );
}

class RevenueTransaction {
  const RevenueTransaction({
    required this.paymentRecordId,
    required this.clientName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.receivedDate,
  });

  final String paymentRecordId;
  final String clientName;
  final String amount;
  final String currency;
  final String status;
  final String receivedDate;

  factory RevenueTransaction.fromJson(Map<String, dynamic> json) => RevenueTransaction(
        paymentRecordId: json['payment_record_id'] as String? ?? '',
        clientName: json['client_name'] as String? ?? '',
        amount: json['amount']?.toString() ?? '0',
        currency: json['currency'] as String? ?? 'USD',
        status: json['status'] as String? ?? '',
        receivedDate: json['received_date'] as String? ?? '',
      );
}

class RevenueSummaryResponse {
  const RevenueSummaryResponse({
    required this.reportingCurrency,
    required this.thisMonthTotal,
    required this.period,
    required this.totalRevenue,
    required this.chartKind,
    required this.series,
    required this.recentTransactions,
  });

  final String reportingCurrency;
  final String thisMonthTotal;
  final String period;
  final String totalRevenue;
  final String chartKind; // 'bar' | 'line'
  final List<RevenueSeriesPoint> series;
  final List<RevenueTransaction> recentTransactions;

  factory RevenueSummaryResponse.fromJson(Map<String, dynamic> json) =>
      RevenueSummaryResponse(
        reportingCurrency: json['reporting_currency'] as String? ?? 'USD',
        thisMonthTotal: json['this_month_total']?.toString() ?? '0',
        period: json['period'] as String? ?? '30',
        totalRevenue: json['total_revenue']?.toString() ?? '0',
        chartKind: json['chart_kind'] as String? ?? 'bar',
        series: (json['series'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RevenueSeriesPoint.fromJson)
            .toList(),
        recentTransactions: (json['recent_transactions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(RevenueTransaction.fromJson)
            .toList(),
      );
}

/// Reconciliation: proofs acknowledged but not yet logged as records.
class PaymentReconciliationSummary {
  const PaymentReconciliationSummary({
    required this.acknowledgedCount,
    required this.loggedCount,
    required this.unloggedCount,
    required this.unloggedRequests,
  });

  final int acknowledgedCount;
  final int loggedCount;
  final int unloggedCount;
  final List<PaymentActionRef> unloggedRequests;

  factory PaymentReconciliationSummary.fromJson(Map<String, dynamic> json) =>
      PaymentReconciliationSummary(
        acknowledgedCount: (json['acknowledged_count'] as num?)?.toInt() ?? 0,
        loggedCount: (json['logged_count'] as num?)?.toInt() ?? 0,
        unloggedCount: (json['unlogged_count'] as num?)?.toInt() ?? 0,
        unloggedRequests: (json['unlogged_requests'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PaymentActionRef.fromJson)
            .toList(),
      );
}

class PaymentActionRef {
  const PaymentActionRef({
    required this.requestId,
    required this.clientId,
    required this.clientName,
    required this.title,
    required this.requestedAmount,
    required this.requestedCurrency,
  });

  final String requestId;
  final int clientId;
  final String clientName;
  final String title;
  final String requestedAmount;
  final String requestedCurrency;

  factory PaymentActionRef.fromJson(Map<String, dynamic> json) => PaymentActionRef(
        requestId: json['request_id'] as String? ?? '',
        clientId: (json['client_id'] as num?)?.toInt() ?? 0,
        clientName: json['client_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        requestedAmount: json['requested_amount']?.toString() ?? '0',
        requestedCurrency: json['requested_currency'] as String? ?? 'USD',
      );
}

/// Payload to log a received payment as a record.
class RecordReceivedPayload {
  const RecordReceivedPayload({
    required this.client,
    this.paymentRequestId,
    required this.originalAmount,
    required this.originalCurrency,
    required this.reportingAmount,
    required this.reportingCurrency,
    this.paymentMethod,
    required this.transactionReference,
    required this.receivedDate,
    this.status = 'completed',
    this.clientVisibility = 'visible',
    this.internalNote = '',
    this.clientNote = '',
  });

  final int client;
  final String? paymentRequestId;
  final String originalAmount;
  final String originalCurrency;
  final String reportingAmount;
  final String reportingCurrency;
  final int? paymentMethod;
  final String transactionReference;
  final String receivedDate;
  final String status; // 'completed' | 'partially_paid'
  final String clientVisibility;
  final String internalNote;
  final String clientNote;

  Map<String, dynamic> toJson() => {
        'client': client,
        if (paymentRequestId != null) 'payment_request_id': paymentRequestId,
        'original_amount': originalAmount,
        'original_currency': originalCurrency,
        'reporting_amount': reportingAmount,
        'reporting_currency': reportingCurrency,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        'transaction_reference': transactionReference,
        'received_date': receivedDate,
        'status': status,
        'client_visibility': clientVisibility,
        'internal_note': internalNote,
        'client_note': clientNote,
      };
}

/// Payload the professional sends to create a new payment request.
class CreatePaymentRequestPayload {
  const CreatePaymentRequestPayload({
    required this.title,
    required this.description,
    required this.requestedAmount,
    required this.requestedCurrency,
    this.dueDate,
    this.paymentType = 'manual',
    this.clientVisibility = 'visible',
    this.notes = '',
    this.allowedMethodIds = const [],
  });

  final String title;
  final String description;
  final String requestedAmount;
  final String requestedCurrency;
  final String? dueDate;
  final String paymentType;
  final String clientVisibility;
  final String notes;
  final List<int> allowedMethodIds;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'requested_amount': requestedAmount,
        'requested_currency': requestedCurrency,
        'due_date': dueDate,
        'payment_type': paymentType,
        'client_visibility': clientVisibility,
        'notes': notes,
        'allowed_method_ids': allowedMethodIds,
      };
}
