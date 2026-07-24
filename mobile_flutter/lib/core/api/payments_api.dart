import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models/payment_models.dart';

/// Client Payments — money professionals collect from their own clients.
/// 1:1 port of mobile/src/app/core/api/payments-api.service.ts. Separate from
/// the professional's own RepRoot subscription billing.
class PaymentsApi {
  PaymentsApi(this._dio);

  final Dio _dio;

  static final _auth = authOptions(AuthScheme.professional);
  static final _clientAuth = authOptions(AuthScheme.client);

  // ----- settings -----

  Future<PaymentSettingsResponse> getPaymentSettings() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/settings/',
        options: _auth,
      );
      return PaymentSettingsResponse.fromJson(res.data ?? {});
    });
  }

  Future<PaymentSettingsResponse> updatePaymentSettings({
    bool? paymentTrackingEnabled,
    String? reportingCurrency,
    bool? clientPaymentHistoryEnabled,
    bool? confirmReportingCurrency,
  }) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/payments/settings/',
        data: {
          'payment_tracking_enabled': ?paymentTrackingEnabled,
          'reporting_currency': ?reportingCurrency,
          'client_payment_history_enabled': ?clientPaymentHistoryEnabled,
          'confirm_reporting_currency': ?confirmReportingCurrency,
        },
        options: _auth,
      );
      return PaymentSettingsResponse.fromJson(res.data ?? {});
    });
  }

  // ----- manual payment methods -----

  Future<({List<ManualPaymentMethodRecord> methods, int maxActive})> getPaymentMethods() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/methods/',
        options: _auth,
      );
      return (
        methods: (res.data?['methods'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ManualPaymentMethodRecord.fromJson)
            .toList(),
        maxActive: (res.data?['max_active'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<ManualPaymentMethodRecord> createPaymentMethod(FormData payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/methods/',
        data: payload,
        options: _auth,
      );
      return ManualPaymentMethodRecord.fromJson(
        res.data?['method'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ManualPaymentMethodRecord> updatePaymentMethod(int methodId, FormData payload) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/payments/methods/$methodId/',
        data: payload,
        options: _auth,
      );
      return ManualPaymentMethodRecord.fromJson(
        res.data?['method'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<ManualPaymentMethodRecord> setPaymentMethodStatus(int methodId, String status) {
    return runApi(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/professional/payments/methods/$methodId/',
        data: {'status': status},
        options: _auth,
      );
      return ManualPaymentMethodRecord.fromJson(
        res.data?['method'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<void> deletePaymentMethod(int methodId) {
    return runApi(() async {
      await _dio.delete<Map<String, dynamic>>(
        '/professional/payments/methods/$methodId/',
        options: _auth,
      );
    });
  }

  // ----- per-client method access -----

  Future<List<ManualPaymentMethodRecord>> getClientMethodAccess(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/clients/$clientId/methods/',
        options: _auth,
      );
      return (res.data?['methods'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ManualPaymentMethodRecord.fromJson)
          .toList();
    });
  }

  Future<void> updateClientMethodAccess(int clientId, List<int> methodIds) {
    return runApi(() async {
      await _dio.put<Map<String, dynamic>>(
        '/professional/payments/clients/$clientId/methods/',
        data: {'method_ids': methodIds},
        options: _auth,
      );
    });
  }

  // ----- payment requests (professional) -----

  Future<List<PaymentRequestRecord>> getClientPaymentRequests(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/clients/$clientId/requests/',
        options: _auth,
      );
      return (res.data?['requests'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PaymentRequestRecord.fromJson)
          .toList();
    });
  }

  Future<PaymentRequestRecord> createPaymentRequest(
    int clientId,
    CreatePaymentRequestPayload payload,
  ) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/clients/$clientId/requests/',
        data: payload.toJson(),
        options: _auth,
      );
      return PaymentRequestRecord.fromJson(
        res.data?['request'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<PaymentRequestRecord> cancelPaymentRequest(String requestId, {String reason = ''}) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/requests/$requestId/cancel/',
        data: {'reason': reason},
        options: _auth,
      );
      return PaymentRequestRecord.fromJson(
        res.data?['request'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  Future<PaymentRequestDetailResponse> getPaymentRequestDetail(String requestId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/requests/$requestId/',
        options: _auth,
      );
      return PaymentRequestDetailResponse.fromJson(res.data ?? {});
    });
  }

  // ----- proof review (professional) -----

  Future<({String message, bool needsLogging})> acknowledgePaymentProof(
    int proofId, {
    String acknowledgementNote = '',
  }) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/proofs/$proofId/acknowledge/',
        data: {'acknowledgement_note': acknowledgementNote},
        options: _auth,
      );
      return (
        message: res.data?['message'] as String? ?? '',
        needsLogging: res.data?['needs_logging'] as bool? ?? false,
      );
    });
  }

  Future<String> rejectPaymentProof(int proofId, String reason) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/proofs/$proofId/reject/',
        data: {'reason': reason},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<String> requestProofInfo(int proofId, String note) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/proofs/$proofId/request-info/',
        data: {'note': note},
        options: _auth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  // ----- reconciliation / actions / unread (professional) -----

  Future<PaymentActionsResponse> getPaymentActions() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/actions/',
        options: _auth,
      );
      return PaymentActionsResponse.fromJson(res.data ?? {});
    });
  }

  Future<int> getProfessionalPaymentUnread() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/notifications/',
        options: _auth,
      );
      return (res.data?['unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> markProfessionalPaymentNotificationsRead() {
    return runApi(() async {
      await _dio.post<Map<String, dynamic>>(
        '/professional/payments/notifications/',
        data: const {},
        options: _auth,
      );
    });
  }

  // ----- revenue / records / reconciliation (professional) -----

  Future<RevenueSummaryResponse> getRevenueSummary(
    String period, {
    String? customStart,
    String? customEnd,
  }) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/revenue-summary/',
        queryParameters: {
          'period': period,
          if (period == 'custom' && customStart != null) 'start': customStart,
          if (period == 'custom' && customEnd != null) 'end': customEnd,
        },
        options: _auth,
      );
      return RevenueSummaryResponse.fromJson(res.data ?? {});
    });
  }

  Future<PaymentReconciliationSummary> getPaymentReconciliation() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/reconciliation/',
        options: _auth,
      );
      return PaymentReconciliationSummary.fromJson(res.data ?? {});
    });
  }

  Future<List<PaymentRecordRow>> getClientPaymentRecords(int clientId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professional/payments/records/',
        queryParameters: {'client_id': clientId},
        options: _auth,
      );
      return (res.data?['records'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PaymentRecordRow.fromJson)
          .toList();
    });
  }

  Future<PaymentRecordRow> recordReceivedPayment(RecordReceivedPayload payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professional/payments/records/',
        data: payload.toJson(),
        options: _auth,
      );
      return PaymentRecordRow.fromJson(
        res.data?['record'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  // ----- client side -----

  Future<List<ClientPaymentRequestRecord>> getMyPaymentRequests() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/payments/requests/',
        options: _clientAuth,
      );
      return (res.data?['requests'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ClientPaymentRequestRecord.fromJson)
          .toList();
    });
  }

  Future<ClientPaymentRequestRecord> getMyPaymentRequestDetail(String requestId) {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/payments/requests/$requestId/',
        options: _clientAuth,
      );
      return ClientPaymentRequestRecord.fromJson(
        res.data?['request'] as Map<String, dynamic>? ?? {},
      );
    });
  }

  /// [payload] is multipart: proof fields plus an optional screenshot file.
  Future<String> submitPaymentProof(String requestId, FormData payload) {
    return runApi(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/client/payments/requests/$requestId/proof/',
        data: payload,
        options: _clientAuth,
      );
      return res.data?['message'] as String? ?? '';
    });
  }

  Future<int> getClientPaymentUnread() {
    return runApi(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/client/payments/notifications/',
        options: _clientAuth,
      );
      return (res.data?['unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  Future<void> markClientPaymentNotificationsRead() {
    return runApi(() async {
      await _dio.post<Map<String, dynamic>>(
        '/client/payments/notifications/',
        data: const {},
        options: _clientAuth,
      );
    });
  }
}

/// Professional "money owed to me" action summary.
class PaymentActionItem {
  const PaymentActionItem({
    required this.requestId,
    required this.clientId,
    required this.clientName,
    required this.title,
    required this.requestedAmount,
    required this.requestedCurrency,
    required this.status,
  });

  final String requestId;
  final int clientId;
  final String clientName;
  final String title;
  final String requestedAmount;
  final String requestedCurrency;
  final String status;

  factory PaymentActionItem.fromJson(Map<String, dynamic> json) => PaymentActionItem(
        requestId: json['request_id'] as String? ?? '',
        clientId: (json['client_id'] as num?)?.toInt() ?? 0,
        clientName: json['client_name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        requestedAmount: json['requested_amount']?.toString() ?? '0',
        requestedCurrency: json['requested_currency'] as String? ?? 'USD',
        status: json['status'] as String? ?? '',
      );
}

class PaymentActionsResponse {
  const PaymentActionsResponse({
    required this.items,
    required this.reviewCount,
    required this.overdueCount,
    required this.actionCount,
  });

  final List<PaymentActionItem> items;
  final int reviewCount;
  final int overdueCount;
  final int actionCount;

  factory PaymentActionsResponse.fromJson(Map<String, dynamic> json) =>
      PaymentActionsResponse(
        items: (json['items'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PaymentActionItem.fromJson)
            .toList(),
        reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
        overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
        actionCount: (json['action_count'] as num?)?.toInt() ?? 0,
      );
}

final paymentsApiProvider =
    Provider<PaymentsApi>((ref) => PaymentsApi(ref.watch(dioProvider)));
