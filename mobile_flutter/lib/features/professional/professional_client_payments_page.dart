import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models/payment_models.dart';
import '../../core/api/payments_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Per-client payment requests: list, create, cancel, and review proofs.
/// Replica of the payments tab inside the web's professional-client-profile.
class ProfessionalClientPaymentsPage extends ConsumerStatefulWidget {
  const ProfessionalClientPaymentsPage({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  ConsumerState<ProfessionalClientPaymentsPage> createState() =>
      _ProfessionalClientPaymentsPageState();
}

class _ProfessionalClientPaymentsPageState
    extends ConsumerState<ProfessionalClientPaymentsPage> {
  List<PaymentRequestRecord> _requests = [];
  List<ManualPaymentMethodRecord> _methods = [];
  List<ManualPaymentMethodRecord> _clientMethods = [];
  String _reportingCurrency = 'USD';
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
      final api = ref.read(paymentsApiProvider);
      final requests = await api.getClientPaymentRequests(widget.clientId);
      final settings = await api.getPaymentSettings();
      final methods = await api.getPaymentMethods();
      final clientMethods = await api.getClientMethodAccess(widget.clientId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _reportingCurrency = settings.settings.reportingCurrency;
        _methods = methods.methods.where((m) => m.isActive).toList();
        _clientMethods = clientMethods;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not load payments.'; _loading = false; });
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _toggleMethodShared(ManualPaymentMethodRecord method, bool shared) async {
    final nextShared = _clientMethods
        .where((m) => m.id == method.id ? shared : m.shared)
        .map((m) => m.id)
        .toList();
    // Optimistic local update.
    setState(() => _clientMethods = _clientMethods
        .map((m) => m.id == method.id
            ? ManualPaymentMethodRecord(
                id: m.id,
                name: m.name,
                category: m.category,
                displayLabel: m.displayLabel,
                supportedCurrencies: m.supportedCurrencies,
                country: m.country,
                clientVisibleFields: m.clientVisibleFields,
                qrCode: m.qrCode,
                internalNotes: m.internalNotes,
                clientInstructions: m.clientInstructions,
                status: m.status,
                shared: shared,
              )
            : m)
        .toList());
    try {
      await ref.read(paymentsApiProvider).updateClientMethodAccess(widget.clientId, nextShared);
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not update method access.');
      _load();
    }
  }

  Future<void> _createRequest() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CreateRequestSheet(
        clientId: widget.clientId,
        defaultCurrency: _reportingCurrency,
        methods: _methods,
      ),
    );
    if (result == true) {
      _toast('Payment request sent.');
      _load();
    }
  }

  Future<void> _cancelRequest(PaymentRequestRecord request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel request?'),
        content: Text('"${request.title}" will be cancelled.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Back')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(paymentsApiProvider).cancelPaymentRequest(request.requestId);
      _load();
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not cancel the request.');
    }
  }

  Future<void> _openRequest(PaymentRequestRecord request) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RequestReviewSheet(requestId: request.requestId),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.clientName} · Payments')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRequest,
        icon: const Icon(Icons.add),
        label: const Text('Request'),
      ),
      body: _loading
          ? const PagePad(children: [SkeletonBox(height: 80), SkeletonBox(height: 80)])
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

                if (_clientMethods.isNotEmpty) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Methods this client can see', style: context.text.titleSmall),
                        for (final method in _clientMethods)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(method.name),
                            subtitle: Text(ManualPaymentCategory.label(method.category)),
                            value: method.shared,
                            onChanged: (value) => _toggleMethodShared(method, value),
                          ),
                      ],
                    ),
                  ),
                  const SectionHeader(title: 'Requests'),
                ],

                if (_requests.isEmpty)
                  const EmptyState(
                    compact: false,
                    icon: Icons.request_quote_outlined,
                    message: 'No payment requests yet.\nSend one with the button below.',
                  )
                else
                  for (final request in _requests)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        onTap: () => _openRequest(request),
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
                            StatusPill(
                              label: PaymentRequestStatus.label(request.status),
                              tone: PaymentRequestStatus.openForProfessional.contains(request.status)
                                  ? PillTone.warn
                                  : request.status == 'completed'
                                      ? PillTone.good
                                      : PillTone.neutral,
                            ),
                            if (!const {'completed', 'cancelled', 'refunded'}
                                .contains(request.status))
                              IconButton(
                                onPressed: () => _cancelRequest(request),
                                icon: const Icon(Icons.cancel_outlined),
                                iconSize: AppSize.iconRow,
                                color: context.colors.error,
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Cancel',
                              ),
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

class _CreateRequestSheet extends ConsumerStatefulWidget {
  const _CreateRequestSheet({
    required this.clientId,
    required this.defaultCurrency,
    required this.methods,
  });

  final int clientId;
  final String defaultCurrency;
  final List<ManualPaymentMethodRecord> methods;

  @override
  ConsumerState<_CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends ConsumerState<_CreateRequestSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  late String _currency;
  DateTime? _dueDate;
  final Set<int> _selectedMethods = {};
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _currency = widget.defaultCurrency;
    for (final m in widget.methods) {
      _selectedMethods.add(m.id);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  String? _isoDate(DateTime? d) => d == null
      ? null
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _amount.text.trim().isEmpty) {
      setState(() => _error = 'Enter a title and amount.');
      return;
    }
    setState(() { _saving = true; _error = ''; });
    try {
      await ref.read(paymentsApiProvider).createPaymentRequest(
            widget.clientId,
            CreatePaymentRequestPayload(
              title: _title.text.trim(),
              description: _description.text.trim(),
              requestedAmount: _amount.text.trim(),
              requestedCurrency: _currency,
              dueDate: _isoDate(_dueDate),
              allowedMethodIds: _selectedMethods.toList(),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Could not send the request.';
        });
      }
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
            Text('New payment request', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Amount'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _currency),
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Currency'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text(_dueDate == null ? 'Due date (optional)' : 'Due ${_isoDate(_dueDate)}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
            if (widget.methods.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('Methods the client can use', style: context.text.bodySmall),
              for (final method in widget.methods)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _selectedMethods.contains(method.id),
                  onChanged: (value) => setState(() {
                    if (value ?? false) {
                      _selectedMethods.add(method.id);
                    } else {
                      _selectedMethods.remove(method.id);
                    }
                  }),
                  title: Text(method.name),
                ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Sending…' : 'Send request'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestReviewSheet extends ConsumerStatefulWidget {
  const _RequestReviewSheet({required this.requestId});

  final String requestId;

  @override
  ConsumerState<_RequestReviewSheet> createState() => _RequestReviewSheetState();
}

class _RequestReviewSheetState extends ConsumerState<_RequestReviewSheet> {
  PaymentRequestDetailResponse? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await ref.read(paymentsApiProvider).getPaymentRequestDetail(widget.requestId);
      if (mounted) setState(() { _detail = detail; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _acknowledge(PaymentProofRecord proof) async {
    try {
      final result =
          await ref.read(paymentsApiProvider).acknowledgePaymentProof(proof.id);
      _toast(result.message.isNotEmpty ? result.message : 'Proof acknowledged.');
      if (result.needsLogging && mounted) {
        await _logRecord(proof);
      }
      _load();
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not acknowledge.');
    }
  }

  /// After acknowledging a proof the payment usually needs logging as a record
  /// so it shows in revenue — mirrors the web's reconciliation prompt.
  Future<void> _logRecord(PaymentProofRecord proof) async {
    final detail = _detail;
    if (detail == null) return;
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log this payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Record ${proof.reportedCurrency} ${proof.reportedAmount} as received so '
              'it counts toward your revenue.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Internal note (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Later')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
            child: const Text('Log payment'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(paymentsApiProvider).recordReceivedPayment(
              RecordReceivedPayload(
                client: detail.request.client,
                paymentRequestId: detail.request.requestId,
                originalAmount: proof.reportedAmount,
                originalCurrency: proof.reportedCurrency,
                reportingAmount: proof.reportedAmount,
                reportingCurrency: proof.reportedCurrency,
                transactionReference: proof.transactionReference,
                receivedDate: proof.reportedPaymentDate,
                internalNote: noteController.text.trim(),
              ),
            );
        _toast('Payment logged.');
      } catch (error) {
        _toast(error is ApiException ? error.message : 'Could not log the payment.');
      }
    }
    noteController.dispose();
  }

  Future<void> _reject(PaymentProofRecord proof) async {
    final reason = await _promptText('Reject proof', 'Reason');
    if (reason == null) return;
    try {
      await ref.read(paymentsApiProvider).rejectPaymentProof(proof.id, reason);
      _toast('Proof rejected.');
      _load();
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not reject.');
    }
  }

  Future<void> _requestInfo(PaymentProofRecord proof) async {
    final note = await _promptText('Request more info', 'What do you need?');
    if (note == null) return;
    try {
      await ref.read(paymentsApiProvider).requestProofInfo(proof.id, note);
      _toast('Requested more info.');
      _load();
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not request info.');
    }
  }

  Future<String?> _promptText(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : detail == null
              ? const SizedBox(height: 120, child: Center(child: Text('Could not load.')))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.request.title, style: context.text.titleMedium),
                      Text(
                        '${detail.request.requestedCurrency} ${detail.request.requestedAmount} · '
                        '${PaymentRequestStatus.label(detail.request.status)}',
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('Proofs', style: context.text.titleSmall),
                      if (detail.proofs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Text('No proof submitted yet.'),
                        )
                      else
                        for (final proof in detail.proofs)
                          Card(
                            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${proof.reportedCurrency} ${proof.reportedAmount} · ${proof.paymentMethodLabel}',
                                    style: context.text.bodyMedium,
                                  ),
                                  if (proof.transactionReference.isNotEmpty)
                                    Text('Ref: ${proof.transactionReference}',
                                        style: context.text.bodySmall),
                                  if (proof.note.isNotEmpty)
                                    Text(proof.note, style: context.text.bodySmall),
                                  Text('Status: ${proof.status}', style: context.text.bodySmall),
                                  if (proof.status == 'submitted' ||
                                      proof.status == 'under_review') ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    Wrap(
                                      spacing: AppSpacing.sm,
                                      children: [
                                        FilledButton(
                                          onPressed: () => _acknowledge(proof),
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(0, AppSize.buttonHeightSm),
                                          ),
                                          child: const Text('Acknowledge'),
                                        ),
                                        OutlinedButton(
                                          onPressed: () => _requestInfo(proof),
                                          child: const Text('Request info'),
                                        ),
                                        OutlinedButton(
                                          onPressed: () => _reject(proof),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: context.colors.error,
                                          ),
                                          child: const Text('Reject'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}
