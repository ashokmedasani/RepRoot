import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models/payment_models.dart';
import '../../core/api/payments_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../professional/professional_format.dart';

/// Client Payments — requests the professional has sent, and proof submission.
/// Replica of mobile/src/app/pages/client/client-payments + payment-request
/// detail, previously absent from the Flutter app.
class ClientPaymentsPage extends ConsumerStatefulWidget {
  const ClientPaymentsPage({super.key});

  @override
  ConsumerState<ClientPaymentsPage> createState() => _ClientPaymentsPageState();
}

class _ClientPaymentsPageState extends ConsumerState<ClientPaymentsPage> {
  List<ClientPaymentRequestRecord> _requests = [];
  bool _loading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _load();
    // Opening the list clears the unread payment badge, as on the web.
    ref.read(paymentsApiProvider).markClientPaymentNotificationsRead().ignore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final requests = await ref.read(paymentsApiProvider).getMyPaymentRequests();
      if (mounted) setState(() { _requests = requests; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not load payments.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payments')),
      body: _loading
          ? const PagePad(children: [SkeletonBox(height: 80), SkeletonBox(height: 80)])
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
                if (_requests.isEmpty)
                  const EmptyState(
                    compact: false,
                    icon: Icons.receipt_long_outlined,
                    message: 'No payment requests.\nYour professional hasn\'t sent any yet.',
                  )
                else
                  for (final request in _requests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        onTap: () async {
                          await context.push('/client/tabs/more/payments/${request.requestId}');
                          _load();
                        },
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(request.title, style: context.text.titleSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${request.requestedCurrency} ${request.requestedAmount}'
                                    '${request.dueDate != null ? ' · due ${shortDate(request.dueDate!)}' : ''}',
                                    style: context.text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            _StatusPill(status: request.status),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(Icons.chevron_right, size: AppSize.iconRow, color: context.tokens.muted),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

class ClientPaymentRequestDetailPage extends ConsumerStatefulWidget {
  const ClientPaymentRequestDetailPage({super.key, required this.requestId});

  final String requestId;

  @override
  ConsumerState<ClientPaymentRequestDetailPage> createState() =>
      _ClientPaymentRequestDetailPageState();
}

class _ClientPaymentRequestDetailPageState
    extends ConsumerState<ClientPaymentRequestDetailPage> {
  ClientPaymentRequestRecord? _request;
  bool _loading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _message = ''; });
    try {
      final request =
          await ref.read(paymentsApiProvider).getMyPaymentRequestDetail(widget.requestId);
      if (mounted) setState(() { _request = request; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not load this request.'; _loading = false; });
    }
  }

  Future<void> _submitProof() async {
    final request = _request;
    if (request == null) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SubmitProofSheet(request: request),
    );
    if (result == true) {
      _toast('Payment proof submitted.');
      _load();
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final canSubmit = request != null &&
        !const {'completed', 'cancelled', 'refunded'}.contains(request.status);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment request')),
      floatingActionButton: canSubmit
          ? FloatingActionButton.extended(
              onPressed: _submitProof,
              icon: const Icon(Icons.upload_file),
              label: const Text('Submit proof'),
            )
          : null,
      body: _loading
          ? const PagePad(children: [SkeletonBox(height: 120), SkeletonBox(height: 120)])
          : request == null
              ? PagePad(children: [ErrorNote(message: _message, onRetry: _load)])
              : PagePad(
                  onRefresh: _load,
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(request.title, style: context.text.titleMedium)),
                              _StatusPill(status: request.status),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${request.requestedCurrency} ${request.requestedAmount}',
                            style: context.text.headlineSmall,
                          ),
                          if (request.dueDate != null)
                            Text('Due ${shortDate(request.dueDate!)}', style: context.text.bodySmall),
                          Text('From ${request.professionalName}', style: context.text.bodySmall),
                          if (request.description.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(request.description, style: context.text.bodyMedium),
                          ],
                        ],
                      ),
                    ),

                    if (request.availableMethods.isNotEmpty) ...[
                      const SectionHeader(title: 'How to pay'),
                      for (final method in request.availableMethods)
                        _MethodCard(method: method),
                    ],

                    const SectionHeader(title: 'Your proofs'),
                    if (request.proofs.isEmpty)
                      const EmptyState(message: 'No proof submitted yet.')
                    else
                      for (final proof in request.proofs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${proof.reportedCurrency} ${proof.reportedAmount}',
                                        style: context.text.titleSmall,
                                      ),
                                    ),
                                    _ProofStatusPill(status: proof.status),
                                  ],
                                ),
                                if (proof.paymentMethodLabel.isNotEmpty)
                                  Text(proof.paymentMethodLabel, style: context.text.bodySmall),
                                if (proof.transactionReference.isNotEmpty)
                                  Text('Ref: ${proof.transactionReference}', style: context.text.bodySmall),
                                if (proof.reviewNote.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text('Professional: ${proof.reviewNote}',
                                      style: context.text.bodySmall?.copyWith(
                                          fontStyle: FontStyle.italic)),
                                ],
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 72),
                  ],
                ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard({required this.method});

  final ManualPaymentMethodClientView method;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              method.displayLabel.isNotEmpty
                  ? method.displayLabel
                  : ManualPaymentCategory.label(method.category),
              style: context.text.titleSmall,
            ),
            for (final entry in method.clientVisibleFields.entries)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${entry.key}: ${entry.value}',
                          style: context.text.bodySmall),
                    ),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: entry.value));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy',
                    ),
                  ],
                ),
              ),
            if (method.clientInstructions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(method.clientInstructions, style: context.text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _SubmitProofSheet extends ConsumerStatefulWidget {
  const _SubmitProofSheet({required this.request});

  final ClientPaymentRequestRecord request;

  @override
  ConsumerState<_SubmitProofSheet> createState() => _SubmitProofSheetState();
}

class _SubmitProofSheetState extends ConsumerState<_SubmitProofSheet> {
  final _reference = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  int? _methodId;
  bool _confirmed = false;
  bool _submitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _amount.text = widget.request.requestedAmount;
  }

  @override
  void dispose() {
    _reference.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (_reference.text.trim().isEmpty || _amount.text.trim().isEmpty) {
      setState(() => _error = 'Enter the transaction reference and amount.');
      return;
    }
    if (!_confirmed) {
      setState(() => _error = 'Please confirm the details are accurate.');
      return;
    }
    setState(() { _submitting = true; _error = ''; });
    try {
      // Multipart to match the web (a screenshot may be attached; here we send
      // the text fields — file attachment can be added later without a contract
      // change since the endpoint already accepts multipart).
      final form = FormDataProof(
        transactionReference: _reference.text.trim(),
        reportedAmount: _amount.text.trim(),
        reportedCurrency: widget.request.requestedCurrency,
        reportedPaymentDate: _isoDate(_date),
        paymentMethod: _methodId,
        note: _note.text.trim(),
        confirmedAccurate: _confirmed,
      ).build();
      await ref.read(paymentsApiProvider).submitPaymentProof(widget.request.requestId, form);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() { _submitting = false; _error = error.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit payment proof', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Transaction reference'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount paid (${widget.request.requestedCurrency})',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.request.availableMethods.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _methodId,
                decoration: const InputDecoration(labelText: 'Method used'),
                items: [
                  for (final m in widget.request.availableMethods)
                    DropdownMenuItem(
                      value: m.id,
                      child: Text(m.displayLabel.isNotEmpty
                          ? m.displayLabel
                          : ManualPaymentCategory.label(m.category)),
                    ),
                ],
                onChanged: (value) => setState(() => _methodId = value),
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Paid on ${_isoDate(_date)}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (value) => setState(() => _confirmed = value ?? false),
              title: const Text('I confirm these details are accurate'),
            ),
            if (_error.isNotEmpty)
              Text(_error, style: TextStyle(color: context.colors.error)),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Submitting…' : 'Submit proof'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny helper mirroring the web's SubmitProofPayload as multipart form data.
class FormDataProof {
  FormDataProof({
    required this.transactionReference,
    required this.reportedAmount,
    required this.reportedCurrency,
    required this.reportedPaymentDate,
    required this.paymentMethod,
    required this.note,
    required this.confirmedAccurate,
  });

  final String transactionReference;
  final String reportedAmount;
  final String reportedCurrency;
  final String reportedPaymentDate;
  final int? paymentMethod;
  final String note;
  final bool confirmedAccurate;

  FormData build() => FormData.fromMap({
        'transaction_reference': transactionReference,
        'reported_amount': reportedAmount,
        'reported_currency': reportedCurrency,
        'reported_payment_date': reportedPaymentDate,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        'note': note,
        'confirmed_accurate': confirmedAccurate,
      });
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'completed' => PillTone.good,
      'acknowledged' => PillTone.good,
      'rejected' || 'cancelled' => PillTone.bad,
      'overdue' => PillTone.warn,
      'proof_submitted' || 'under_review' => PillTone.info,
      _ => PillTone.neutral,
    };
    return StatusPill(label: PaymentRequestStatus.label(status), tone: tone);
  }
}

class _ProofStatusPill extends StatelessWidget {
  const _ProofStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      'accepted' => PillTone.good,
      'rejected' => PillTone.bad,
      'under_review' => PillTone.info,
      _ => PillTone.neutral,
    };
    final label = switch (status) {
      'submitted' => 'Submitted',
      'under_review' => 'Under review',
      'accepted' => 'Accepted',
      'rejected' => 'Rejected',
      _ => status,
    };
    return StatusPill(label: label, tone: tone);
  }
}

// FormData needs dio; re-export via import used above.
