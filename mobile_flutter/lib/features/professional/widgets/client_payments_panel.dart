import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/models/payment_models.dart';
import '../../../core/api/payments_api.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../professional_format.dart';

/// Payments splits by tense: what's live now, and the settled record.
enum _PaymentsView { overview, records }

/// Manual vs. integrated toggle inside the Transactions sub-tab.
enum TransactionView { manual, integrated }

/// Active for the professional (owes them attention / money), used by the
/// Summary tab's request-count tiles — mirrors the web's `ACTIVE_STATUSES`.
const _activeRequestStatuses = {
  'sent', 'viewed', 'proof_submitted', 'under_review', 'overdue', 'partially_paid',
};

/// The full per-client payments experience — Summary / Methods / Requests /
/// Transactions / Activity — as one embeddable widget with no Scaffold/AppBar
/// of its own, so it can be dropped straight into the client-detail page's
/// Payments tab body. [ProfessionalClientPaymentsPage] wraps this in its own
/// Scaffold for the standalone deep-link route reached from the Dashboard.
class ClientPaymentsPanel extends ConsumerStatefulWidget {
  const ClientPaymentsPanel({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  final int clientId;
  final String clientName;

  @override
  ConsumerState<ClientPaymentsPanel> createState() => _ClientPaymentsPanelState();
}

class _ClientPaymentsPanelState extends ConsumerState<ClientPaymentsPanel> {
  _PaymentsView _view = _PaymentsView.overview;
  TransactionView _transactionView = TransactionView.manual;

  bool _loading = true;
  String _message = '';

  PaymentSettingsRecord? _settings;
  List<PaymentRequestRecord> _requests = [];
  List<ManualPaymentMethodRecord> _methods = [];
  List<ManualPaymentMethodRecord> _clientMethods = [];
  List<PaymentRecordRow> _records = [];

  List<PaymentActivityItem> _activity = [];
  String _activityError = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadActivity();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _message = ''; });
    try {
      final api = ref.read(paymentsApiProvider);
      final requests = await api.getClientPaymentRequests(widget.clientId);
      final settings = await api.getPaymentSettings();
      final methods = await api.getPaymentMethods();
      final clientMethods = await api.getClientMethodAccess(widget.clientId);
      final records = await api.getClientPaymentRecords(widget.clientId);
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _settings = settings.settings;
        _methods = methods.methods.where((m) => m.isActive).toList();
        _clientMethods = clientMethods;
        _records = records;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not load payments.'; _loading = false; });
    }
  }

  Future<void> _loadActivity() async {
    setState(() => _activityError = '');
    try {
      final items = await ref.read(paymentsApiProvider).getProfessionalPaymentActivity(widget.clientId);
      if (mounted) setState(() => _activity = items);
    } catch (_) {
      if (mounted) setState(() => _activityError = 'Payment activity could not be loaded.');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ----- methods sharing -----

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

  // ----- requests -----

  Future<void> _createRequest() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CreateRequestSheet(
        clientId: widget.clientId,
        defaultCurrency: _settings?.reportingCurrency ?? 'USD',
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

  // ----- summary: log received payment -----

  Future<void> _logReceivedPayment() async {
    final settings = _settings;
    if (settings == null) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LogReceivedPaymentSheet(
        clientId: widget.clientId,
        defaultCurrency: settings.reportingCurrency,
      ),
    );
    if (result == true) {
      _toast('Payment logged.');
      _load();
    }
  }

  // ----- derived summary numbers -----

  double get _manualLoggedTotal {
    final currency = _settings?.reportingCurrency ?? '';
    return _records
        .where((r) => r.recordType == 'manual_log' && r.reportingCurrency == currency)
        .fold<double>(0, (sum, r) => sum + (double.tryParse(r.reportingAmount) ?? 0));
  }

  // Integrated payment collection isn't built yet — this stays hardcoded to
  // 0 rather than fabricating a fake data source, matching the web exactly.
  double get _integratedTotal => 0;

  double get _totalLoggedAmount => _manualLoggedTotal + _integratedTotal;

  int get _awaitingAckCount =>
      _requests.where((r) => r.status == 'proof_submitted' || r.status == 'under_review').length;

  int get _overdueCount => _requests.where((r) => r.status == 'overdue').length;

  String _fmtAmount(double value, String currency) => '${value.toStringAsFixed(2)} $currency';

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PagePad(children: [SkeletonBox(height: 80), SkeletonBox(height: 80)]);
    }
    final settings = _settings;
    if (settings == null || !settings.reportingCurrencyLocked) {
      return PagePad(
        onRefresh: _load,
        children: [
          if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
          _currencySetupCard(),
        ],
      );
    }

    final currency = settings.reportingCurrency;
    final openRequests = _requests
        .where((r) => _activeRequestStatuses.contains(r.status))
        .toList();

    // Two views, not five and not one long scroll. The split is by tense:
    // Overview is what is live and what you might do about it; Records is the
    // settled ledger.
    //
    // Rendered as two labelled cards rather than another SegmentedButton: the
    // client tabs directly above this panel are already a segmented bar, and
    // a second identical one immediately below read as one confusing
    // four-item row rather than as a nested control.
    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        Row(
          children: [
            Expanded(
              child: _viewCard(
                view: _PaymentsView.overview,
                icon: Icons.account_balance_wallet_outlined,
                label: 'Overview',
                caption: 'Live · actions',
                badge: _needsAttentionCount,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _viewCard(
                view: _PaymentsView.records,
                icon: Icons.receipt_long_outlined,
                label: 'Records',
                caption: 'Past · logged',
                badge: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (_view == _PaymentsView.overview)
          ..._nowView(currency, openRequests)
        else
          ..._historyView(),
      ],
    );
  }

  /// One of the two selectable view cards. Selected state is carried by fill,
  /// border, and icon colour together — on a two-item control a subtle tint
  /// alone is easy to misread as "neither".
  Widget _viewCard({
    required _PaymentsView view,
    required IconData icon,
    required String label,
    required String caption,
    required int badge,
  }) {
    final tokens = context.tokens;
    final selected = _view == view;

    return InkWell(
      onTap: selected ? null : () => setState(() => _view = view),
      borderRadius: AppRadius.tileAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? tokens.primarySoft : tokens.surfaceSoft,
          borderRadius: AppRadius.tileAll,
          border: Border.all(
            color: selected ? context.colors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: AppSize.iconButton,
                  color: selected ? context.colors.primary : tokens.muted,
                ),
                const Spacer(),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.error,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      '$badge',
                      style: context.text.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: context.text.titleSmall?.copyWith(
                color: selected ? context.colors.primary : null,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              caption,
              style: context.text.bodySmall?.copyWith(color: tokens.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// "Overview" — live state: what you've been paid, what needs you, what
  /// you can do, and the requests that are still open.
  List<Widget> _nowView(
    String currency,
    List<PaymentRequestRecord> openRequests,
  ) {
    return [
      _moneyCard(currency),
      if (_needsAttentionCount > 0) ...[
        const SizedBox(height: AppSpacing.stack),
        _needsAttentionCard(),
      ],
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _createRequest,
              icon: const Icon(Icons.request_quote_outlined, size: AppSize.iconRow),
              label: const Text('Request'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _logReceivedPayment,
              icon: const Icon(Icons.add, size: AppSize.iconRow),
              label: const Text('Log payment'),
            ),
          ),
        ],
      ),
      SectionHeader(
        title: openRequests.isEmpty
            ? 'Requests'
            : 'Open requests (${openRequests.length})',
      ),
      if (_requests.isEmpty)
        const EmptyState(
          message: 'No payment requests yet. Send one with Request above.',
        )
      else
        for (final request in _previewRequests) _requestCard(request),
      if (_requests.length > _requestPreviewCount)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _view = _PaymentsView.records),
            child: Text('View all ${_requests.length} requests'),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      Text(
        'RepRoot Studio records information you enter here. It does not '
        'receive, hold, or transfer these payments, and does not verify '
        'ownership of external payment accounts.',
        style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
      ),
    ];
  }

  /// The settled record, plus the reference material that used to own a tab
  /// each — methods and the activity log are read rarely, so they sit at the
  /// bottom here rather than competing for the top of the panel.
  /// "Records" — the settled ledger: completed requests, logged payments,
  /// and the saved references behind them.
  List<Widget> _historyView() {
    return [
      const SectionHeader(title: 'All requests', topSpace: 0),
      if (_requests.isEmpty)
        const EmptyState(message: 'No payment requests yet.')
      else
        for (final request in _requests) _requestCard(request),
      const SectionHeader(title: 'Payments received'),
      if (_records.isEmpty)
        const EmptyState(message: 'Nothing logged yet.')
      else
        _transactionsTab(),
      const SectionHeader(title: 'Reference'),
      RowItem(
        title: 'Payment methods',
        subtitle: _clientMethods.where((m) => m.shared).isEmpty
            ? 'Nothing shared with this client yet'
            : '${_clientMethods.where((m) => m.shared).length} shared with this client',
        leading: Icon(Icons.account_balance_wallet_outlined,
            size: AppSize.iconButton, color: context.colors.primary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openReferenceSheet('Payment methods', _methodsTab()),
      ),
      RowItem(
        title: 'Activity log',
        subtitle: 'Every change to this client\'s payments',
        leading: Icon(Icons.history,
            size: AppSize.iconButton, color: context.tokens.muted),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openReferenceSheet('Activity log', _activityTab()),
      ),
    ];
  }

  static const _requestPreviewCount = 4;

  List<PaymentRequestRecord> get _previewRequests {
    // Anything still open first — those are the ones you came here for —
    // then the most recent settled ones to fill the preview.
    final open = _requests
        .where((r) => _activeRequestStatuses.contains(r.status))
        .toList();
    final rest = _requests
        .where((r) => !_activeRequestStatuses.contains(r.status))
        .toList();
    return [...open, ...rest].take(_requestPreviewCount).toList();
  }

  int get _needsAttentionCount => _awaitingAckCount + _overdueCount;

  /// Total received, as one figure rather than three KPI tiles.
  ///
  /// The old summary spent a whole tile on "Integrated Payments — Coming
  /// later", which is a roadmap note occupying prime screen space; the split
  /// now rides along as a caption and disappears entirely when it's zero.
  Widget _moneyCard(String currency) {
    final tokens = context.tokens;
    return AppCard(
      color: Color.alphaBlend(
        MenuAccent.green.bg.withValues(alpha: 0.55),
        tokens.surfaceSoft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'RECEIVED',
                  style: context.text.labelSmall?.copyWith(
                    color: tokens.muted,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _fmtAmount(_totalLoggedAmount, currency),
                  style: context.text.headlineSmall?.copyWith(
                    color: tokens.success,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                ),
                if (_integratedTotal > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Manual ${_fmtAmount(_manualLoggedTotal, currency)} · '
                    'Integrated ${_fmtAmount(_integratedTotal, currency)}',
                    style: context.text.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.payments_outlined,
              size: AppSize.iconButton, color: tokens.success),
        ],
      ),
    );
  }

  /// The one thing worth interrupting for: proofs waiting on a decision, and
  /// requests that have gone overdue.
  Widget _needsAttentionCard() {
    final parts = <String>[
      if (_awaitingAckCount > 0)
        '$_awaitingAckCount ${_awaitingAckCount == 1 ? 'proof' : 'proofs'} to review',
      if (_overdueCount > 0) '$_overdueCount overdue',
    ];
    return AppCard(
      color: Color.alphaBlend(
        MenuAccent.orange.bg.withValues(alpha: 0.55),
        context.tokens.surfaceSoft,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: AppSize.iconButton, color: MenuAccent.orange.fg),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: context.text.titleSmall
                  ?.copyWith(color: MenuAccent.orange.fg),
            ),
          ),
        ],
      ),
    );
  }

  /// Reference sections (methods, full request list, transactions, activity)
  /// reuse their existing builders verbatim — only where they're presented
  /// changed, not what they show.
  Future<void> _openReferenceSheet(String title, Widget body) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            AppSpacing.xl,
          ),
          children: [
            Text(title, style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.md),
            body,
          ],
        ),
      ),
    );
    if (mounted) _load();
  }


  /// Shown until a reporting currency is confirmed — every figure on this
  /// panel is denominated in it, so there is nothing meaningful to render
  /// before it exists. Lifted out of the old Summary tab unchanged.
  Widget _currencySetupCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Unlock your payment summary', style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('1. Open Settings → Payments.', style: context.text.bodySmall),
          const SizedBox(height: 4),
          Text('2. Choose and confirm your reporting currency.',
              style: context.text.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This setup message disappears after confirmation.',
            style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push(Routes.professionalSettingsPayment),
              child: const Text('Set Reporting Currency'),
            ),
          ),
        ],
      ),
    );
  }

  /// A single payment request row. Same content as the old Requests tab card,
  /// extracted so the main page and the full-list sheet render it identically.
  Widget _requestCard(PaymentRequestRecord request) {
    final accepted = double.tryParse(request.acceptedAmount) ?? 0;
    final overpaid = double.tryParse(request.overpaidAmount) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.stack),
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
                  if (accepted > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Paid ${request.acceptedAmount} ${request.requestedCurrency} · '
                      'Remaining ${request.remainingAmount} ${request.requestedCurrency}',
                      style: context.text.labelSmall
                          ?.copyWith(color: context.tokens.muted),
                    ),
                    if (overpaid > 0)
                      Text(
                        'Overpaid by ${request.overpaidAmount} ${request.requestedCurrency}',
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
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
    );
  }

  // ----- Methods -----

  Widget _methodsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Available Payment Methods', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (_clientMethods.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.payments_outlined,
            message: 'No payment methods set up yet.',
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
      ],
    );
  }

  // ----- Transactions -----

  Widget _transactionsTab() {
    final manualRecords = _records.where((r) => r.recordType == 'manual_log').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TransactionView>(
            segments: const [
              ButtonSegment(value: TransactionView.manual, label: Text('Manual Payment Log')),
              ButtonSegment(value: TransactionView.integrated, label: Text('Integrated Payments')),
            ],
            selected: {_transactionView},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() => _transactionView = selection.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_transactionView == TransactionView.manual)
          _manualLogSection(manualRecords)
        else
          _integratedPlaceholder(),
      ],
    );
  }

  Widget _manualLogSection(List<PaymentRecordRow> records) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Manual Payment Log', style: context.text.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Private bookkeeping for payments you record yourself. A log may '
          'reference a payment request, but it is never shown to the client.',
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (records.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.receipt_long_outlined,
            message: 'No payments have been recorded for this client yet.',
          )
        else
          for (final record in records)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record.originalAmount} ${record.originalCurrency}',
                            style: context.text.titleSmall,
                          ),
                          if (record.paymentMethodLabel.isNotEmpty)
                            Text(record.paymentMethodLabel, style: context.text.bodySmall),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                record.paymentRecordId,
                                style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (record.requestReference.isNotEmpty)
                                Text(' · ${record.requestReference}', style: context.text.bodySmall),
                            ],
                          ),
                          if (record.receivedDate.isNotEmpty)
                            Text(
                              shortDate(record.receivedDate),
                              style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
                            ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: switch (record.status) {
                        'partially_paid' => 'Partial',
                        'refunded' => 'Refunded',
                        _ => 'Completed',
                      },
                      tone: switch (record.status) {
                        'partially_paid' => PillTone.warn,
                        'refunded' => PillTone.bad,
                        _ => PillTone.good,
                      },
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _integratedPlaceholder() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RESERVED WORKFLOW',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text('Integrated Payments', style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Provider-collected transactions will appear here after payment '
            'processing is configured. Manual logs and client-submitted '
            'payment proofs remain separate.',
            style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
          ),
        ],
      ),
    );
  }

  // ----- Activity -----

  Widget _activityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Activity', style: context.text.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Every payment action for this client, newest first.',
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_activityError.isNotEmpty)
          ErrorNote(message: _activityError, onRetry: _loadActivity)
        else if (_activity.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.history,
            message: 'No payment activity yet.',
          )
        else
          for (final item in _activity)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 6, right: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: context.colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.actionLabel, style: context.text.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (item.requestId.isNotEmpty) item.requestId,
                              dateTimeLabel(item.createdAt),
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                          ),
                          if (item.reason.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.reason,
                              style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

// ----- Create request sheet -----

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

  /// Nullable wrapper over the shared [isoDate] — an unset optional date has to
  /// travel as `null`, not as an empty string, so the backend leaves the field
  /// alone rather than trying to parse "".
  String? _isoDateOrNull(DateTime? d) => d == null ? null : isoDate(d);

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
              dueDate: _isoDateOrNull(_dueDate),
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
              label: Text(_dueDate == null
                  ? 'Due date (optional)'
                  : 'Due ${isoDate(_dueDate!)}'),
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

// ----- Request review sheet -----

/// Mirrors the web's `verifyMode` — which face of the verification modal is
/// showing. `review` is the default landing state with the three action
/// buttons; the other three are single-purpose follow-up forms.
enum _ReviewMode { review, acknowledge, reject, info }

class _RequestReviewSheet extends ConsumerStatefulWidget {
  const _RequestReviewSheet({required this.requestId});

  final String requestId;

  @override
  ConsumerState<_RequestReviewSheet> createState() => _RequestReviewSheetState();
}

class _RequestReviewSheetState extends ConsumerState<_RequestReviewSheet> {
  PaymentRequestDetailResponse? _detail;
  bool _loading = true;

  _ReviewMode _mode = _ReviewMode.review;
  String _settlementStatus = 'partial';
  final _ackNote = TextEditingController();
  final _rejectReason = TextEditingController();
  final _infoNote = TextEditingController();
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ackNote.dispose();
    _rejectReason.dispose();
    _infoNote.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await ref.read(paymentsApiProvider).getPaymentRequestDetail(widget.requestId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _settlementStatus = _recommendedSettlement;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Newest still-open proof — ports the web's
  /// `proofs.find(p => status is submitted/under_review) || proofs[0] || null`.
  PaymentProofRecord? get _selectedProof {
    final proofs = _detail?.proofs ?? const <PaymentProofRecord>[];
    if (proofs.isEmpty) return null;
    return proofs.firstWhere(
      (p) => p.status == 'submitted' || p.status == 'under_review',
      orElse: () => proofs.first,
    );
  }

  double get _acceptedAfterCurrentProof {
    final detail = _detail;
    final proof = _selectedProof;
    if (detail == null || proof == null) return 0;
    final accepted = double.tryParse(detail.request.acceptedAmount) ?? 0;
    final sameCurrency = proof.reportedCurrency == detail.request.requestedCurrency;
    final reported = sameCurrency ? (double.tryParse(proof.reportedAmount) ?? 0) : 0;
    return accepted + reported;
  }

  String get _recommendedSettlement {
    final detail = _detail;
    if (detail == null) return 'partial';
    final requested = double.tryParse(detail.request.requestedAmount) ?? 0;
    final total = _acceptedAfterCurrentProof;
    if (total > requested) return 'overpaid';
    if (total == requested) return 'full';
    return 'partial';
  }

  double get _remainingAfterCurrentProof {
    final detail = _detail;
    if (detail == null) return 0;
    final requested = double.tryParse(detail.request.requestedAmount) ?? 0;
    final remaining = requested - _acceptedAfterCurrentProof;
    return remaining < 0 ? 0 : remaining;
  }

  double get _overpaidAfterCurrentProof {
    final detail = _detail;
    if (detail == null) return 0;
    final requested = double.tryParse(detail.request.requestedAmount) ?? 0;
    final overpaid = _acceptedAfterCurrentProof - requested;
    return overpaid < 0 ? 0 : overpaid;
  }

  Future<void> _submitAcknowledge() async {
    final proof = _selectedProof;
    if (proof == null) return;
    setState(() { _saving = true; _error = ''; });
    try {
      final result = await ref.read(paymentsApiProvider).acknowledgePaymentProof(
            proof.id,
            acknowledgementNote: _ackNote.text.trim(),
            settlementStatus: _settlementStatus,
          );
      if (!mounted) return;
      _toast(result.message.isNotEmpty ? result.message : 'Proof acknowledged.');
      if (result.needsLogging && mounted) {
        await _logRecord(proof);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Acknowledgement could not be saved.';
        });
      }
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

  Future<void> _submitReject() async {
    final proof = _selectedProof;
    if (proof == null) return;
    setState(() { _saving = true; _error = ''; });
    try {
      await ref.read(paymentsApiProvider).rejectPaymentProof(proof.id, _rejectReason.text.trim());
      if (!mounted) return;
      _toast('Proof rejected.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Could not reject this proof.';
        });
      }
    }
  }

  Future<void> _submitInfo() async {
    final proof = _selectedProof;
    if (proof == null) return;
    setState(() { _saving = true; _error = ''; });
    try {
      await ref.read(paymentsApiProvider).requestProofInfo(proof.id, _infoNote.text.trim());
      if (!mounted) return;
      _toast('Requested more info.');
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Could not send the request.';
        });
      }
    }
  }

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: context.text.labelSmall?.copyWith(color: context.tokens.muted)),
            Text(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _comparisonColumns(PaymentRequestDetailResponse detail, PaymentProofRecord proof) {
    final requestColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Requested', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        _kv('Amount', '${detail.request.requestedAmount} ${detail.request.requestedCurrency}'),
        if (detail.request.dueDate != null) _kv('Due', detail.request.dueDate!),
      ],
    );
    final proofColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Client reported', style: context.text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        _kv('Amount', '${proof.reportedAmount} ${proof.reportedCurrency}'),
        _kv('Date', proof.reportedPaymentDate),
        if (proof.transactionReference.isNotEmpty) _kv('Txn', proof.transactionReference),
        if (proof.paymentMethodLabel.isNotEmpty) _kv('Method', proof.paymentMethodLabel),
        if (proof.note.isNotEmpty) _kv('Note', proof.note),
        if (proof.hasFile) _kv('Proof', 'File attached'),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: requestColumn),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: proofColumn),
      ],
    );
  }

  Widget _installmentSummary(PaymentRequestDetailResponse detail) {
    Widget block(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.labelSmall?.copyWith(color: context.tokens.muted)),
              const SizedBox(height: 2),
              Text(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return AppCard(
      child: Row(
        children: [
          block('Requested', '${detail.request.requestedAmount} ${detail.request.requestedCurrency}'),
          block('Accepted so far', '${detail.request.acceptedAmount} ${detail.request.requestedCurrency}'),
          block('Remaining', '${detail.request.remainingAmount} ${detail.request.requestedCurrency}'),
        ],
      ),
    );
  }

  Widget _reviewButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: () => setState(() => _mode = _ReviewMode.acknowledge),
          child: const Text('Acknowledge Payment'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => setState(() => _mode = _ReviewMode.info),
          child: const Text('Request More Info'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => setState(() => _mode = _ReviewMode.reject),
          style: OutlinedButton.styleFrom(foregroundColor: context.colors.error),
          child: const Text('Reject Proof'),
        ),
      ],
    );
  }

  Widget _acknowledgeForm(PaymentRequestDetailResponse detail) {
    final currency = detail.request.requestedCurrency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settlement result', style: context.text.titleSmall),
        RadioGroup<String>(
          groupValue: _settlementStatus,
          onChanged: (v) => setState(() => _settlementStatus = v ?? 'partial'),
          child: const Column(
            children: [
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: 'partial',
                title: Text('Partially paid'),
                subtitle: Text('Keep open for the remaining balance.'),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: 'full',
                title: Text('Fully paid'),
                subtitle: Text('Close with no balance remaining.'),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: 'overpaid',
                title: Text('Overpaid'),
                subtitle: Text('Close and preserve the extra amount.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accepted after this proof',
                style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
              ),
              const SizedBox(height: 2),
              Text(
                '${_acceptedAfterCurrentProof.toStringAsFixed(2)} $currency',
                style: context.text.titleMedium,
              ),
              const SizedBox(height: 2),
              if (_overpaidAfterCurrentProof > 0)
                Text(
                  'Overpaid by ${_overpaidAfterCurrentProof.toStringAsFixed(2)} $currency',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.error,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Text(
                  'Remaining ${_remainingAfterCurrentProof.toStringAsFixed(2)} $currency',
                  style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _ackNote,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error, style: TextStyle(color: context.colors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _mode = _ReviewMode.review),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _submitAcknowledge,
                child: Text(_saving ? 'Saving…' : 'Acknowledge Payment'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _rejectForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reason for rejection', style: context.text.bodySmall),
        const SizedBox(height: 4),
        TextField(
          controller: _rejectReason,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            hintText: 'The client will see this and can resubmit.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error, style: TextStyle(color: context.colors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _mode = _ReviewMode.review),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: (_saving || _rejectReason.text.trim().isEmpty) ? null : _submitReject,
                style: FilledButton.styleFrom(backgroundColor: context.colors.error),
                child: Text(_saving ? 'Rejecting…' : 'Reject Proof'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _infoNote,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'What do you need?',
            hintText: 'e.g. Please attach a clearer screenshot.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error, style: TextStyle(color: context.colors.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => setState(() => _mode = _ReviewMode.review),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: (_saving || _infoNote.text.trim().isEmpty) ? null : _submitInfo,
                child: Text(_saving ? 'Sending…' : 'Send Request'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _body(PaymentRequestDetailResponse detail) {
    final proof = _selectedProof;
    if (proof == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('No proof has been submitted for this request yet.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _comparisonColumns(detail, proof),
        const SizedBox(height: AppSpacing.md),
        _installmentSummary(detail),
        const SizedBox(height: AppSpacing.md),
        switch (_mode) {
          _ReviewMode.review => _reviewButtons(),
          _ReviewMode.acknowledge => _acknowledgeForm(detail),
          _ReviewMode.reject => _rejectForm(),
          _ReviewMode.info => _infoForm(),
        },
      ],
    );
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
                      Text(
                        'REVIEW PAYMENT',
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(detail.request.title, style: context.text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${detail.request.requestId} · requested '
                        '${detail.request.requestedAmount} ${detail.request.requestedCurrency}',
                        style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _body(detail),
                    ],
                  ),
                ),
    );
  }
}

// ----- Log received payment sheet (Summary tab) -----

class _LogReceivedPaymentSheet extends ConsumerStatefulWidget {
  const _LogReceivedPaymentSheet({
    required this.clientId,
    required this.defaultCurrency,
  });

  final int clientId;
  final String defaultCurrency;

  @override
  ConsumerState<_LogReceivedPaymentSheet> createState() => _LogReceivedPaymentSheetState();
}

class _LogReceivedPaymentSheetState extends ConsumerState<_LogReceivedPaymentSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  late String _currency;
  DateTime _receivedDate = DateTime.now();
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _currency = widget.defaultCurrency;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }


  Future<void> _save() async {
    if (_amount.text.trim().isEmpty) {
      setState(() => _error = 'Enter an amount.');
      return;
    }
    setState(() { _saving = true; _error = ''; });
    try {
      // No currency-conversion UI exists in this port, so the reporting
      // fields simply mirror the original amount/currency the professional
      // entered, per the ported spec.
      await ref.read(paymentsApiProvider).recordReceivedPayment(
            RecordReceivedPayload(
              client: widget.clientId,
              originalAmount: _amount.text.trim(),
              originalCurrency: _currency,
              reportingAmount: _amount.text.trim(),
              reportingCurrency: _currency,
              transactionReference: _reference.text.trim(),
              receivedDate: isoDate(_receivedDate),
              internalNote: _note.text.trim(),
            ),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Could not log the payment.';
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
            Text('Log received payment', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Original amount'),
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
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Transaction reference (optional)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _receivedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _receivedDate = picked);
              },
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Received ${isoDate(_receivedDate)}'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Internal note (optional)'),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Log payment'),
            ),
          ],
        ),
      ),
    );
  }
}
