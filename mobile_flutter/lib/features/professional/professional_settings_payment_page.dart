import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/account_models.dart';
import '../../core/api/models/payment_models.dart';
import '../../core/api/payments_api.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Payment Settings — read-only summary of the reporting currency and manual
/// payment methods. The real CRUD surface for both already lives in
/// professional_payments_page.dart (Manage ▸ Payments); this page exists so
/// Settings has a discoverable entry point without duplicating that UI.
class ProfessionalSettingsPaymentPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsPaymentPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsPaymentPage> createState() =>
      _ProfessionalSettingsPaymentPageState();
}

class _ProfessionalSettingsPaymentPageState
    extends ConsumerState<ProfessionalSettingsPaymentPage> {
  PaymentSettingsRecord? _settings;
  List<ManualPaymentMethodRecord> _methods = [];
  int _maxActive = 0;
  ProfessionalBillingStatus? _billing;

  /// Currency codes the backend accepts. Already returned by
  /// `getPaymentSettings` and already parsed on mobile — it was simply never
  /// shown, so the currency could only be set from the web.
  List<String> _currencyOptions = const [];
  String _currencyDraft = '';
  bool _savingCurrency = false;
  String _currencyMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paymentsApi = ref.read(paymentsApiProvider);
    try {
      final settings = await paymentsApi.getPaymentSettings();
      if (mounted) {
        setState(() {
          _settings = settings.settings;
          _currencyOptions = settings.currencyOptions;
          _currencyDraft = settings.settings.reportingCurrency;
        });
      }
    } catch (_) {
      /* the currency card just shows blanks */
    }
    try {
      final methods = await paymentsApi.getPaymentMethods();
      if (mounted) {
        setState(() {
          _methods = methods.methods;
          _maxActive = methods.maxActive;
        });
      }
    } catch (_) {
      /* the methods card just shows empty */
    }
    try {
      // Same call the Billing page already uses — only needed here for its
      // supportEmail, for the "contact support" copy below.
      final billing = await ref.read(professionalAuthApiProvider).getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (_) {
      /* falls back to the word "support" with no address */
    }
  }

  /// Confirming the currency also locks it — the backend locks on first save
  /// and only support can change it afterwards, so the button says so rather
  /// than presenting this as an ordinary editable setting.
  Future<void> _saveReportingCurrency() async {
    if (_currencyDraft.isEmpty || _savingCurrency) return;
    setState(() {
      _savingCurrency = true;
      _currencyMessage = '';
    });
    try {
      final updated = await ref
          .read(paymentsApiProvider)
          .updatePaymentSettings(reportingCurrency: _currencyDraft);
      if (!mounted) return;
      setState(() {
        _settings = updated.settings;
        _currencyOptions = updated.currencyOptions;
        _currencyDraft = updated.settings.reportingCurrency;
        _savingCurrency = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingCurrency = false;
        _currencyMessage = error is ApiException
            ? error.message
            : 'Could not save the reporting currency.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final settings = _settings;
    final activeCount = _methods.where((m) => m.isActive).length;
    final locked = settings?.reportingCurrencyLocked ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Settings'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          const SettingsHeroCard(
            icon: Icons.payments_outlined,
            title: 'Payment Settings',
            subtitle: 'Configure payment methods and options.',
          ),
          const SizedBox(height: AppSpacing.md),
          // Same structure, terminology and rules as the web's Reporting
          // Currency section. Mobile previously showed the value read-only and
          // sent you to another page to set it — but the picker only existed
          // on the website, so on mobile the currency could never be set at
          // all.
          _Card(
            title: 'Reporting Currency',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The single currency used for dashboard totals and reports. '
                  'Confirm it carefully: once locked, only support can make a '
                  'correction and that change must be audited.',
                  style: context.text.bodySmall?.copyWith(color: tokens.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      settings != null && settings.reportingCurrency.isNotEmpty
                          ? settings.reportingCurrency
                          : 'Not set',
                      style: context.text.titleMedium,
                    ),
                    // The web's exact two states — this is a one-way lock, not
                    // an on/off setting, and "Unlocked" implied otherwise.
                    StatusPill(
                      label: locked
                          ? 'Currency permanently locked'
                          : 'Confirmation required',
                      tone: locked ? PillTone.warn : PillTone.info,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (locked)
                  Text(
                    'Reporting currency: ${settings?.reportingCurrency ?? ''}. '
                    'Contact '
                    '${(_billing?.supportEmail.isNotEmpty ?? false) ? _billing!.supportEmail : 'support'} '
                    'if a correction requires an audited change.',
                    style: context.text.bodySmall?.copyWith(color: tokens.muted),
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _currencyOptions.contains(_currencyDraft)
                        ? _currencyDraft
                        : null,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Reporting currency'),
                    items: [
                      for (final code in _currencyOptions)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: _savingCurrency
                        ? null
                        : (value) =>
                            setState(() => _currencyDraft = value ?? ''),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _savingCurrency || _currencyDraft.isEmpty
                          ? null
                          : _saveReportingCurrency,
                      child: Text(_savingCurrency
                          ? 'Saving…'
                          : 'Confirm & Lock Currency'),
                    ),
                  ),
                  if (_currencyMessage.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _currencyMessage,
                      style: context.text.bodySmall
                          ?.copyWith(color: context.colors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Currency conversion values are used for reporting '
                    'purposes only. They do not represent settlement, '
                    'banking, or payment-provider exchange rates.',
                    style: context.text.bodySmall?.copyWith(color: tokens.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _Card(
            title: _maxActive > 0
                ? 'Payment Methods ($activeCount / $_maxActive active)'
                : 'Payment Methods',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_methods.isEmpty)
                  const EmptyState(
                    compact: false,
                    icon: Icons.account_balance_wallet_outlined,
                    message:
                        'No payment methods yet.\nAdd one from Payments so clients know how to pay you.',
                  )
                else
                  for (final method in _methods)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(method.name, style: context.text.titleSmall),
                                Text(
                                  ManualPaymentCategory.label(method.category),
                                  style: context.text.bodySmall?.copyWith(
                                    color: tokens.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            label: method.isActive ? 'Active' : 'Inactive',
                            tone: method.isActive ? PillTone.good : PillTone.neutral,
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go(Routes.professionalPayments),
                    child: const Text('Manage Payment Methods'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled surface — the .card rule.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
