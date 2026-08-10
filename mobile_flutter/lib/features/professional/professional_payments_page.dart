import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/payment_models.dart';
import '../../core/api/payments_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

enum _PaymentSection {
  reporting,
  transactions,
  methods,
  integrated,
  disclosures,
}

/// Professional payment workspace, aligned with the website's payment page.
class ProfessionalPaymentsPage extends ConsumerStatefulWidget {
  const ProfessionalPaymentsPage({super.key});

  @override
  ConsumerState<ProfessionalPaymentsPage> createState() =>
      _ProfessionalPaymentsPageState();
}

class _ProfessionalPaymentsPageState
    extends ConsumerState<ProfessionalPaymentsPage> {
  PaymentSettingsRecord? _settings;
  List<String> _currencyOptions = [];
  List<ManualPaymentMethodRecord> _methods = [];
  int _maxActive = 0;
  bool _loading = true;
  String _message = '';
  bool _savingSettings = false;
  _PaymentSection _section = _PaymentSection.reporting;
  List<FinancialTransactionRecord> _transactions = [];
  String _transactionsMessage = '';

  RevenueSummaryResponse? _revenue;
  String _revenuePeriod = '30';
  PaymentReconciliationSummary? _reconciliation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = '';
    });
    try {
      final api = ref.read(paymentsApiProvider);
      final settings = await api.getPaymentSettings();
      final methods = await api.getPaymentMethods();
      if (!mounted) return;
      setState(() {
        _settings = settings.settings;
        _currencyOptions = settings.currencyOptions;
        _methods = methods.methods;
        _maxActive = methods.maxActive;
        _loading = false;
      });
      _loadRevenue();
      _loadReconciliation();
      _loadTransactions();
    } catch (error, stackTrace) {
      debugPrint(
        'Payment settings load failed (${error.runtimeType})\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _message = 'Could not load payment settings.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadRevenue() async {
    try {
      final revenue = await ref
          .read(paymentsApiProvider)
          .getRevenueSummary(_revenuePeriod);
      if (mounted) setState(() => _revenue = revenue);
    } catch (error, stackTrace) {
      debugPrint(
        'Payment revenue load failed (${error.runtimeType})\n$stackTrace',
      );
    }
  }

  Future<void> _loadReconciliation() async {
    try {
      final recon = await ref
          .read(paymentsApiProvider)
          .getPaymentReconciliation();
      if (mounted) setState(() => _reconciliation = recon);
    } catch (error, stackTrace) {
      debugPrint(
        'Payment reconciliation load failed (${error.runtimeType})\n$stackTrace',
      );
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final transactions = await ref
          .read(paymentsApiProvider)
          .getTransactionLedger();
      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _transactionsMessage = '';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Payment transaction load failed (${error.runtimeType})\n$stackTrace',
      );
      if (mounted) {
        setState(
          () =>
              _transactionsMessage = 'Could not load the transaction history.',
        );
      }
    }
  }

  Future<void> _setReportingCurrency(String currency) async {
    if (_savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      final response = await ref
          .read(paymentsApiProvider)
          .updatePaymentSettings(
            reportingCurrency: currency,
            confirmReportingCurrency: true,
          );
      if (mounted) {
        setState(() {
          _settings = response.settings;
          _currencyOptions = response.currencyOptions;
        });
      }
      _toast('Reporting currency saved. It is now locked.');
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not update settings.',
      );
    }
    if (mounted) setState(() => _savingSettings = false);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addOrEditMethod([ManualPaymentMethodRecord? existing]) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MethodSheet(existing: existing),
    );
    if (result == true) _load();
  }

  Future<void> _toggleMethodStatus(ManualPaymentMethodRecord method) async {
    try {
      final updated = await ref
          .read(paymentsApiProvider)
          .setPaymentMethodStatus(
            method.id,
            method.isActive ? 'inactive' : 'active',
          );
      if (!mounted) return;
      setState(
        () => _methods = _methods
            .map((m) => m.id == method.id ? updated : m)
            .toList(),
      );
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not update the method.',
      );
    }
  }

  Future<void> _deleteMethod(ManualPaymentMethodRecord method) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${method.name}?'),
        content: const Text('Clients will no longer see this payment method.'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(paymentsApiProvider).deletePaymentMethod(method.id);
      if (mounted) {
        setState(
          () => _methods = _methods.where((m) => m.id != method.id).toList(),
        );
      }
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not delete the method.',
      );
    }
  }

  Future<void> _confirmCurrency(String currency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Use $currency for reporting?'),
        content: const Text(
          'This currency is used for payment totals and reporting. Once saved, '
          'it is locked to keep financial records consistent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _setReportingCurrency(currency);
  }

  Widget _reportingSection(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return ErrorNote(
        message: 'Payment settings are unavailable.',
        onRetry: _load,
      );
    }
    if (settings.reportingCurrencyLocked) {
      return AppCard(
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: context.colors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reporting currency', style: context.text.labelMedium),
                  Text(
                    settings.reportingCurrency,
                    style: context.text.headlineSmall,
                  ),
                  Text(
                    'Locked to keep payment records consistent.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.tokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            const StatusPill(label: 'Locked', tone: PillTone.good),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose reporting currency', style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Check your normal billing currency before confirming. It cannot be '
            'changed after financial records are created.',
            style: context.text.bodySmall?.copyWith(
              color: context.tokens.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _currencyOptions.contains(settings.reportingCurrency)
                ? settings.reportingCurrency
                : null,
            decoration: const InputDecoration(labelText: 'Reporting currency'),
            items: [
              for (final currency in _currencyOptions)
                DropdownMenuItem(value: currency, child: Text(currency)),
            ],
            onChanged: _savingSettings
                ? null
                : (currency) {
                    if (currency != null) _confirmCurrency(currency);
                  },
          ),
        ],
      ),
    );
  }

  Widget _transactionsSection(BuildContext context) {
    final revenue = _revenue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSegmentedFilter<String>(
          value: _revenuePeriod,
          options: const [
            ('7', '7 days'),
            ('30', '30 days'),
            ('90', '90 days'),
            ('lifetime', 'All time'),
          ],
          onChanged: (period) {
            setState(() => _revenuePeriod = period);
            _loadRevenue();
          },
        ),
        const SizedBox(height: AppSpacing.md),
        if (revenue == null)
          const SkeletonBox(height: 112)
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Revenue overview', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Selected period',
                        value:
                            '${revenue.reportingCurrency} ${revenue.totalRevenue}',
                      ),
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: 'This month',
                        value:
                            '${revenue.reportingCurrency} ${revenue.thisMonthTotal}',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if ((_reconciliation?.unloggedCount ?? 0) > 0) ...[
          const SectionHeader(
            title: 'Needs reconciliation',
            topSpace: AppSpacing.md,
          ),
          AppCard(
            color: context.tokens.warningSoft,
            child: Text(
              '${_reconciliation!.unloggedCount} acknowledged '
              'payment${_reconciliation!.unloggedCount == 1 ? '' : 's'} '
              'still need a payment record.',
              style: context.text.bodyMedium,
            ),
          ),
        ],
        const SectionHeader(
          title: 'Transaction history',
          topSpace: AppSpacing.md,
        ),
        if (_transactionsMessage.isNotEmpty)
          ErrorNote(message: _transactionsMessage, onRetry: _loadTransactions)
        else if (_transactions.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.receipt_long_outlined,
            message: 'No payment transactions have been recorded yet.',
          )
        else
          for (final transaction in _transactions)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                radius: AppRadius.tile,
                elevated: false,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: context.tokens.primarySoft,
                      child: Icon(
                        Icons.receipt_outlined,
                        color: context.colors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${transaction.currency} ${transaction.amount}',
                            style: context.text.titleSmall,
                          ),
                          Text(
                            transaction.description.isNotEmpty
                                ? transaction.description
                                : transaction.source,
                            style: context.text.bodySmall,
                          ),
                          if (transaction.paymentRequestReference.isNotEmpty)
                            Text(
                              transaction.paymentRequestReference,
                              style: context.text.labelSmall?.copyWith(
                                color: context.tokens.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: transaction.status.isEmpty
                          ? 'Recorded'
                          : transaction.status,
                      tone: transaction.status.toLowerCase() == 'completed'
                          ? PillTone.good
                          : PillTone.neutral,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _methodsSection(BuildContext context) {
    final activeCount = _methods.where((method) => method.isActive).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: _maxActive > 0
              ? 'Manual methods ($activeCount / $_maxActive active)'
              : 'Manual payment methods',
          topSpace: 0,
          actionLabel: 'Add method',
          onAction: () => _addOrEditMethod(),
        ),
        Text(
          'Share payment instructions with clients. Payments still happen '
          'outside RepRoot Studio.',
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_methods.isEmpty)
          EmptyState(
            compact: false,
            icon: Icons.account_balance_wallet_outlined,
            message: 'No payment methods yet.',
            actionLabel: 'Add payment method',
            onAction: () => _addOrEditMethod(),
          )
        else
          for (final method in _methods)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                onTap: () => _addOrEditMethod(method),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(method.name, style: context.text.titleSmall),
                          Text(
                            ManualPaymentCategory.label(method.category),
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: method.isActive,
                      onChanged: (_) => _toggleMethodStatus(method),
                    ),
                    IconButton(
                      tooltip: 'Delete method',
                      onPressed: () => _deleteMethod(method),
                      icon: const Icon(Icons.delete_outline),
                      color: context.colors.error,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _disclosuresSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment disclosures', style: context.text.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Manual payment methods are supplied by the professional. Payments '
            'made through them happen outside RepRoot Studio.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Clients submit transaction details or proof for review. A payment '
            'is complete only after the professional acknowledges it.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Integrated payments are not currently available.'),
        ],
      ),
    );
  }

  Widget _currentSection(BuildContext context) => switch (_section) {
    _PaymentSection.reporting => _reportingSection(context),
    _PaymentSection.transactions => _transactionsSection(context),
    _PaymentSection.methods => _methodsSection(context),
    _PaymentSection.integrated => const EmptyState(
      compact: false,
      icon: Icons.link_off_outlined,
      message:
          'Integrated payments are coming later.\n'
          'No provider is connected now.',
    ),
    _PaymentSection.disclosures => _disclosuresSection(context),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        leading: BackButton(
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(Routes.professionalMore),
        ),
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 120), SkeletonBox(height: 120)],
            )
          : PagePad(
              onRefresh: _load,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Review transactions, reporting currency, and the '
                        'payment methods shared with clients.',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.tokens.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const InfoDot(
                      title: 'About client payments',
                      body:
                          'Payments recorded here are separate from your '
                          'RepRoot Studio subscription.',
                    ),
                  ],
                ),
                if (_message.isNotEmpty)
                  ErrorNote(message: _message, onRetry: _load),
                AppSegmentedFilter<_PaymentSection>(
                  value: _section,
                  options: const [
                    (_PaymentSection.reporting, 'Currency'),
                    (_PaymentSection.transactions, 'Transactions'),
                    (_PaymentSection.methods, 'Methods'),
                    (_PaymentSection.integrated, 'Integrated'),
                    (_PaymentSection.disclosures, 'Disclosures'),
                  ],
                  onChanged: (section) => setState(() => _section = section),
                ),
                const SizedBox(height: AppSpacing.md),
                _currentSection(context),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        Text(value, style: context.text.titleMedium),
      ],
    );
  }
}

/// Add/edit sheet for a manual payment method.
class _MethodSheet extends ConsumerStatefulWidget {
  const _MethodSheet({this.existing});

  final ManualPaymentMethodRecord? existing;

  @override
  ConsumerState<_MethodSheet> createState() => _MethodSheetState();
}

class _MethodSheetState extends ConsumerState<_MethodSheet> {
  late final TextEditingController _name;
  late final TextEditingController _instructions;
  late final TextEditingController _fields; // "key: value" per line
  late String _category;
  XFile? _qrFile;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _instructions = TextEditingController(
      text: existing?.clientInstructions ?? '',
    );
    _category = existing?.category ?? 'upi';
    _fields = TextEditingController(
      text: (existing?.clientVisibleFields.entries ?? [])
          .map((e) => '${e.key}: ${e.value}')
          .join('\n'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _instructions.dispose();
    _fields.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the method a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = '';
    });
    // Parse "key: value" lines into the client-visible fields map.
    final fields = <String, String>{};
    for (final line in _fields.text.split('\n')) {
      final idx = line.indexOf(':');
      if (idx > 0) {
        fields[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
    final form = FormData.fromMap({
      'name': _name.text.trim(),
      'category': _category,
      'client_instructions': _instructions.text.trim(),
      'client_visible_fields': jsonEncode(fields),
      if (_qrFile != null)
        'qr_code': await MultipartFile.fromFile(
          _qrFile!.path,
          filename: _qrFile!.name,
        ),
    });
    try {
      final api = ref.read(paymentsApiProvider);
      if (widget.existing == null) {
        await api.createPaymentMethod(form);
      } else {
        await api.updatePaymentMethod(widget.existing!.id, form);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException
              ? error.message
              : 'Could not save the method.';
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
            Text(
              widget.existing == null
                  ? 'Add payment method'
                  : 'Edit payment method',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. My UPI)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final c in ManualPaymentCategory.all)
                  DropdownMenuItem(
                    value: c,
                    child: Text(ManualPaymentCategory.label(c)),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'upi'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _fields,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Details clients see',
                helperText:
                    'One per line, "Label: value" (e.g. UPI ID: me@bank)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _instructions,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await ImagePicker().pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1000,
                  imageQuality: 85,
                );
                if (picked != null) setState(() => _qrFile = picked);
              },
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: Text(
                _qrFile == null
                    ? 'Attach QR code (optional)'
                    : 'QR code selected',
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save method'),
            ),
          ],
        ),
      ),
    );
  }
}
