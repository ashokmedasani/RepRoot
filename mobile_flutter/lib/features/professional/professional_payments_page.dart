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

/// Professional payment settings + manual payment methods.
/// Replica of mobile/src/app/pages/professional/professional-payment-settings.
class ProfessionalPaymentsPage extends ConsumerStatefulWidget {
  const ProfessionalPaymentsPage({super.key});

  @override
  ConsumerState<ProfessionalPaymentsPage> createState() =>
      _ProfessionalPaymentsPageState();
}

class _ProfessionalPaymentsPageState extends ConsumerState<ProfessionalPaymentsPage> {
  PaymentSettingsRecord? _settings;
  List<String> _currencyOptions = [];
  List<ManualPaymentMethodRecord> _methods = [];
  int _maxActive = 0;
  bool _loading = true;
  String _message = '';
  bool _savingSettings = false;

  RevenueSummaryResponse? _revenue;
  String _revenuePeriod = '30';
  PaymentReconciliationSummary? _reconciliation;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _message = ''; });
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
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not load payment settings.'; _loading = false; });
    }
  }

  Future<void> _loadRevenue() async {
    try {
      final revenue = await ref.read(paymentsApiProvider).getRevenueSummary(_revenuePeriod);
      if (mounted) setState(() => _revenue = revenue);
    } catch (_) {/* revenue is optional; the rest of the page still works */}
  }

  Future<void> _loadReconciliation() async {
    try {
      final recon = await ref.read(paymentsApiProvider).getPaymentReconciliation();
      if (mounted) setState(() => _reconciliation = recon);
    } catch (_) {}
  }

  Future<void> _updateSettings({
    bool? trackingEnabled,
    String? currency,
    bool? historyEnabled,
  }) async {
    if (_savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      final response = await ref.read(paymentsApiProvider).updatePaymentSettings(
            paymentTrackingEnabled: trackingEnabled,
            reportingCurrency: currency,
            clientPaymentHistoryEnabled: historyEnabled,
          );
      if (mounted) {
        setState(() {
          _settings = response.settings;
          _currencyOptions = response.currencyOptions;
        });
      }
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not update settings.');
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
      final updated = await ref.read(paymentsApiProvider).setPaymentMethodStatus(
            method.id,
            method.isActive ? 'inactive' : 'active',
          );
      if (!mounted) return;
      setState(() =>
          _methods = _methods.map((m) => m.id == method.id ? updated : m).toList());
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not update the method.');
    }
  }

  Future<void> _deleteMethod(ManualPaymentMethodRecord method) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${method.name}?'),
        content: const Text('Clients will no longer see this payment method.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
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
      if (mounted) setState(() => _methods = _methods.where((m) => m.id != method.id).toList());
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not delete the method.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final activeCount = _methods.where((m) => m.isActive).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalManage)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditMethod(),
        icon: const Icon(Icons.add),
        label: const Text('Method'),
      ),
      body: _loading
          ? const PagePad(children: [SkeletonBox(height: 120), SkeletonBox(height: 120)])
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

                if (_revenue != null && (_settings?.paymentTrackingEnabled ?? false)) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Revenue', style: context.text.titleSmall),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            for (final period in const [
                              ('7', '7d'),
                              ('30', '30d'),
                              ('90', '90d'),
                              ('lifetime', 'All'),
                            ])
                              ChoiceChip(
                                label: Text(period.$2),
                                selected: _revenuePeriod == period.$1,
                                onSelected: (_) {
                                  setState(() => _revenuePeriod = period.$1);
                                  _loadRevenue();
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                label: 'This period',
                                value: '${_revenue!.reportingCurrency} ${_revenue!.totalRevenue}',
                              ),
                            ),
                            Expanded(
                              child: _MiniStat(
                                label: 'This month',
                                value: '${_revenue!.reportingCurrency} ${_revenue!.thisMonthTotal}',
                              ),
                            ),
                          ],
                        ),
                        if (_revenue!.recentTransactions.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text('Recent', style: context.text.labelMedium),
                          for (final txn in _revenue!.recentTransactions.take(5))
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Row(
                                children: [
                                  Expanded(child: Text(txn.clientName, style: context.text.bodySmall)),
                                  Text('${txn.currency} ${txn.amount}',
                                      style: context.text.bodySmall),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings', style: context.text.titleSmall),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Payment tracking'),
                        subtitle: const Text('Show the revenue dashboard and summaries'),
                        value: settings?.paymentTrackingEnabled ?? false,
                        onChanged: _savingSettings
                            ? null
                            : (value) => _updateSettings(trackingEnabled: value),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Client payment history'),
                        subtitle: const Text('Let clients see their own payment records'),
                        value: settings?.clientPaymentHistoryEnabled ?? false,
                        onChanged: _savingSettings
                            ? null
                            : (value) => _updateSettings(historyEnabled: value),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        initialValue: (settings != null &&
                                _currencyOptions.contains(settings.reportingCurrency))
                            ? settings.reportingCurrency
                            : null,
                        decoration: const InputDecoration(labelText: 'Reporting currency'),
                        items: [
                          for (final c in _currencyOptions)
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: _savingSettings
                            ? null
                            : (value) {
                                if (value != null) _updateSettings(currency: value);
                              },
                      ),
                    ],
                  ),
                ),

                SectionHeader(
                  title: _maxActive > 0
                      ? 'Payment methods ($activeCount / $_maxActive active)'
                      : 'Payment methods',
                ),
                if (_methods.isEmpty)
                  const EmptyState(
                    compact: false,
                    icon: Icons.account_balance_wallet_outlined,
                    message: 'No payment methods yet.\nAdd one so clients know how to pay you.',
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
                              onPressed: () => _deleteMethod(method),
                              icon: const Icon(Icons.delete_outline),
                              iconSize: AppSize.iconRow,
                              color: context.colors.error,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ),

                if ((_reconciliation?.unloggedCount ?? 0) > 0) ...[
                  const SectionHeader(title: 'To reconcile'),
                  AppCard(
                    color: context.tokens.primarySoft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_reconciliation!.unloggedCount} acknowledged '
                          'payment${_reconciliation!.unloggedCount == 1 ? '' : 's'} not yet logged',
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        for (final req in _reconciliation!.unloggedRequests)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${req.clientName} · ${req.title}',
                                    style: context.text.bodySmall,
                                  ),
                                ),
                                Text('${req.requestedCurrency} ${req.requestedAmount}',
                                    style: context.text.bodySmall),
                              ],
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Open a client\'s Payments to log these against a record.',
                          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 72),
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
        Text(label, style: context.text.bodySmall?.copyWith(color: context.tokens.muted)),
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
    _instructions = TextEditingController(text: existing?.clientInstructions ?? '');
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
    setState(() { _saving = true; _error = ''; });
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
          _error = error is ApiException ? error.message : 'Could not save the method.';
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
              widget.existing == null ? 'Add payment method' : 'Edit payment method',
              style: context.text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name (e.g. My UPI)'),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final c in ManualPaymentCategory.all)
                  DropdownMenuItem(value: c, child: Text(ManualPaymentCategory.label(c))),
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
                helperText: 'One per line, "Label: value" (e.g. UPI ID: me@bank)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _instructions,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Instructions (optional)'),
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
              label: Text(_qrFile == null ? 'Attach QR code (optional)' : 'QR code selected'),
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
