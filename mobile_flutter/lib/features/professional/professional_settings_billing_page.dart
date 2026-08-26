import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models/account_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Plan comparison and membership management. Plan limits and prices are read
/// from the backend billing response so this screen never becomes a second
/// source of truth.
class ProfessionalSettingsBillingPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsBillingPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsBillingPage> createState() =>
      _ProfessionalSettingsBillingPageState();
}

class _ProfessionalSettingsBillingPageState
    extends ConsumerState<ProfessionalSettingsBillingPage> {
  ProfessionalBillingStatus? _billing;
  String _loadError = '';
  String _selectedCycle = 'monthly';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadError = '');
    try {
      final billing = await ref
          .read(professionalAuthApiProvider)
          .getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (error, stackTrace) {
      debugPrint(
        'Could not load billing details (${error.runtimeType}).\n$stackTrace',
      );
      if (mounted) {
        setState(() => _loadError = 'Billing details could not be loaded.');
      }
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _choosePlan(String _) async {
    if (_billing?.paymentsEnabled != true) {
      _toast('Subscription plan changes are unavailable during testing.');
      return;
    }
    final opened = await launchUrl(
      Uri.parse(
        Env.webUrl('/professional/account-settings?section=billing'),
      ),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) _toast('Could not open Plan and Billing on the website.');
  }

  Future<void> _cancelPlan() async {
    final billing = _billing;
    if (billing == null) return;
    if (!billing.paymentsEnabled) {
      _toast('Membership changes are unavailable during testing.');
      return;
    }
    if (!billing.storageDowngradeEligible) {
      _toast(
        'Cancellation is blocked because storage is '
        '${billing.freeStoragePercent}% of the Free allowance. Contact '
        '${billing.supportEmail.isNotEmpty ? billing.supportEmail : 'support'}.',
      );
      return;
    }

    final lockLines = <String>[];
    const labels = {
      'lead_forms': 'lead form',
      'groups': 'group',
      'templates': 'template',
      'resources': 'resource',
      'categories': 'category',
    };
    for (final entry in billing.downgradeLocks.entries) {
      final lockedCount = (entry.value['locked_count'] as num?)?.toInt() ?? 0;
      if (lockedCount == 0) continue;
      final names = (entry.value['locked_names'] as List<dynamic>? ?? [])
          .take(5)
          .join(', ');
      final label = labels[entry.key] ?? entry.key;
      lockLines.add(
        '$lockedCount $label${lockedCount == 1 ? '' : 's'} would lock'
        '${names.isEmpty ? '' : ' ($names)'}.',
      );
    }
    if (billing.categoryCascadeResourceCount > 0) {
      lockLines.add(
        '${billing.categoryCascadeResourceCount} resource(s) would lock '
        'because their category would lock.',
      );
    }
    if (billing.clientsLosingAccess.isNotEmpty) {
      final names = billing.clientsLosingAccess
          .take(5)
          .map((client) => '${client['client_name']} (${client['group_name']})')
          .join(', ');
      lockLines.add(
        '${billing.clientsLosingAccess.length} client(s) would lose portal '
        'access until you upgrade again: $names.',
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel plan?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paid access remains active until expiry, then the account '
                'moves to Free. Nothing is deleted.',
              ),
              for (final line in lockLines) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(line),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Keep plan'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Cancel plan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final message = await ref
          .read(professionalAuthApiProvider)
          .cancelBillingPlan();
      _toast(message.isNotEmpty ? message : 'Cancellation scheduled.');
      await _load();
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not cancel the plan.',
      );
    }
  }

  Future<void> _openBillingPortal() async {
    if (_billing?.paymentsEnabled != true) {
      _toast('The billing portal is unavailable during testing.');
      return;
    }
    try {
      final url = await ref
          .read(professionalAuthApiProvider)
          .createBillingPortal();
      if (url.isEmpty) {
        _toast('Billing portal is not available yet.');
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      _toast(
        error is ApiException
            ? error.message
            : 'Could not open billing portal.',
      );
    }
  }

  List<String> _availableCycles(ProfessionalBillingStatus billing) {
    final trainer = billing.catalog['trainer'] as Map<dynamic, dynamic>? ?? {};
    const supported = ['monthly', 'six_months', 'yearly'];
    final cycles = supported.where((cycle) {
      return trainer.values.any(
        (prices) => prices is Map && prices.containsKey(cycle),
      );
    }).toList();
    return cycles.isEmpty ? const ['monthly'] : cycles;
  }

  String _priceFor(ProfessionalPlanTier tier) {
    final billing = _billing;
    if (billing == null) return '—';
    final currency = billing.billingCurrency.isEmpty
        ? 'USD'
        : billing.billingCurrency;
    final symbol = currency == 'INR' ? '₹' : r'$';
    if (tier.code == 'starter_free' || tier.code == 'starter') {
      return '${symbol}0.00';
    }
    final trainer = billing.catalog['trainer'] as Map<dynamic, dynamic>?;
    final prices = trainer?[tier.code] as Map<dynamic, dynamic>?;
    final cycle = prices?[_selectedCycle] as Map<dynamic, dynamic>?;
    final value = cycle?[currency];
    return value == null ? '—' : '$symbol$value';
  }

  String _cycleLabel(String cycle) => switch (cycle) {
    'six_months' => '6 Months',
    'yearly' => 'Yearly',
    _ => 'Monthly',
  };

  String _cycleSuffix() => switch (_selectedCycle) {
    'six_months' => '/6 months',
    'yearly' => '/year',
    _ => '/month',
  };

  @override
  Widget build(BuildContext context) {
    final billing = _billing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan and Billing'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          Text(
            'Compare and choose the plan that fits your work.',
            style: context.text.bodyMedium?.copyWith(
              color: context.tokens.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loadError.isNotEmpty) ...[
            ErrorNote(message: _loadError, onRetry: _load),
          ] else if (billing == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Center(child: CircularProgressIndicator()),
            ),
          ] else ...[
            if (!billing.paymentsEnabled) ...[
              const AppCard(
                child: Text(
                  'Subscription plan and membership changes are unavailable during testing. Your current plan details remain visible below.',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            _BillingControls(
              cycles: _availableCycles(billing),
              selectedCycle: _selectedCycle,
              region: billing.billingRegion,
              currency: billing.billingCurrency,
              onCycleChanged: (cycle) {
                setState(() => _selectedCycle = cycle);
              },
              cycleLabel: _cycleLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            _PlanComparison(
              plans: billing.plans,
              currentPlanCode: billing.planCode,
              priceFor: _priceFor,
              cycleSuffix: _cycleSuffix(),
              paymentsEnabled: billing.paymentsEnabled,
              onChoosePlan: _choosePlan,
            ),
            if (_showsMembershipManagement(billing)) ...[
              const SizedBox(height: AppSpacing.md),
              _MembershipCard(
                billing: billing,
                onOpenPortal: _openBillingPortal,
                onCancel: _cancelPlan,
              ),
            ],
          ],
        ],
      ),
    );
  }

  bool _showsMembershipManagement(ProfessionalBillingStatus billing) {
    final isPaid =
        billing.planCode != 'starter_free' && billing.planCode != 'starter';
    return isPaid || billing.billingConfigured;
  }
}

class _BillingControls extends StatelessWidget {
  const _BillingControls({
    required this.cycles,
    required this.selectedCycle,
    required this.region,
    required this.currency,
    required this.onCycleChanged,
    required this.cycleLabel,
  });

  final List<String> cycles;
  final String selectedCycle;
  final String region;
  final String currency;
  final ValueChanged<String> onCycleChanged;
  final String Function(String) cycleLabel;

  @override
  Widget build(BuildContext context) {
    final value = cycles.contains(selectedCycle) ? selectedCycle : cycles.first;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: const InputDecoration(
              labelText: 'Billing period',
              prefixIcon: Icon(Icons.calendar_month_outlined),
            ),
            items: cycles
                .map(
                  (cycle) => DropdownMenuItem(
                    value: cycle,
                    child: Text(cycleLabel(cycle)),
                  ),
                )
                .toList(),
            onChanged: (cycle) {
              if (cycle != null) onCycleChanged(cycle);
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            height: AppSize.fieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: context.tokens.surfaceSoft,
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: context.tokens.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.public_outlined,
                  size: AppSize.iconRow,
                  color: context.tokens.muted,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${region.isEmpty ? 'International' : region} · '
                    '${currency.isEmpty ? 'USD' : currency}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge,
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

class _PlanComparison extends StatelessWidget {
  const _PlanComparison({
    required this.plans,
    required this.currentPlanCode,
    required this.priceFor,
    required this.cycleSuffix,
    required this.paymentsEnabled,
    required this.onChoosePlan,
  });

  final List<ProfessionalPlanTier> plans;
  final String currentPlanCode;
  final String Function(ProfessionalPlanTier) priceFor;
  final String cycleSuffix;
  final bool paymentsEnabled;
  final ValueChanged<String> onChoosePlan;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const AppCard(child: Text('Plan information is not available.'));
    }
    final rows = <(IconData, String, String Function(ProfessionalPlanTier))>[
      (Icons.view_module_outlined, 'Templates', (tier) => '${tier.templates}'),
      (Icons.description_outlined, 'Lead forms', (tier) => '${tier.leadForms}'),
      (
        Icons.people_outline,
        'Clients',
        (tier) => tier.clients == null ? 'Unlimited' : '${tier.clients}',
      ),
      (
        Icons.storage_outlined,
        'Storage',
        (tier) => formatBytes(tier.storageBytes),
      ),
      (Icons.groups_outlined, 'Groups', (tier) => '${tier.groups}'),
      (Icons.folder_copy_outlined, 'Resources', (tier) => '${tier.resources}'),
      (Icons.category_outlined, 'Categories', (tier) => '${tier.categories}'),
      (
        Icons.account_tree_outlined,
        'Subcategories',
        (tier) => '${tier.subcategoriesPerCategory}/category',
      ),
      (
        Icons.history_outlined,
        'Client history',
        (tier) => '${tier.clientDataRetentionDays} days',
      ),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.cardAll,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the complete comparison visible on a phone. The previous
            // fixed 486 px table forced horizontal scrolling on every common
            // mobile width and hid Premium values off-screen.
            final featureWidth = (constraints.maxWidth * 0.29).clamp(
              88.0,
              124.0,
            );
            final planWidth =
                (constraints.maxWidth - featureWidth) / plans.length;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ComparisonLabelCell(
                        width: featureWidth,
                        label: 'Features',
                        header: true,
                      ),
                      for (final plan in plans)
                        _PlanHeaderCell(
                          width: planWidth,
                          tier: plan,
                          price: priceFor(plan),
                          cycleSuffix: cycleSuffix,
                          isCurrent: plan.code == currentPlanCode,
                          paymentsEnabled: paymentsEnabled,
                          onChoose: () => onChoosePlan(plan.code),
                        ),
                    ],
                  ),
                ),
                for (var index = 0; index < rows.length; index++)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ComparisonLabelCell(
                          width: featureWidth,
                          icon: rows[index].$1,
                          label: rows[index].$2,
                          shaded: index.isEven,
                        ),
                        for (final plan in plans)
                          _ComparisonValueCell(
                            width: planWidth,
                            value: rows[index].$3(plan),
                            shaded: index.isEven,
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlanHeaderCell extends StatelessWidget {
  const _PlanHeaderCell({
    required this.width,
    required this.tier,
    required this.price,
    required this.cycleSuffix,
    required this.isCurrent,
    required this.paymentsEnabled,
    required this.onChoose,
  });

  final double width;
  final ProfessionalPlanTier tier;
  final String price;
  final String cycleSuffix;
  final bool isCurrent;
  final bool paymentsEnabled;
  final VoidCallback onChoose;

  bool get _isFree => tier.code == 'starter_free' || tier.code == 'starter';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? context.tokens.primarySoft : context.colors.surface,
        border: Border(
          left: BorderSide(color: context.tokens.border),
          bottom: BorderSide(color: context.tokens.border),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isFree
                ? Icons.play_arrow_rounded
                : tier.code == 'pro'
                ? Icons.star_outline_rounded
                : Icons.workspace_premium_outlined,
            size: AppSize.iconRow,
            color: tier.code == 'premium_unlimited'
                ? context.tokens.warningStrong
                : context.colors.primary,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            tier.name.isEmpty ? tier.code : tier.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(price, style: context.text.titleSmall),
          ),
          Text(
            cycleSuffix,
            style: context.text.bodySmall?.copyWith(
              color: context.tokens.muted,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? FilledButton.tonal(
                    onPressed: null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      textStyle: context.text.labelSmall,
                    ),
                    child: const Text('Current'),
                  )
                : _isFree
                ? const SizedBox(height: AppSize.buttonHeightSm)
                : OutlinedButton(
                    onPressed: paymentsEnabled ? onChoose : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      textStyle: context.text.labelSmall,
                    ),
                    child: Text(paymentsEnabled ? 'Choose' : 'Unavailable'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonLabelCell extends StatelessWidget {
  const _ComparisonLabelCell({
    required this.width,
    required this.label,
    this.icon,
    this.header = false,
    this.shaded = false,
  });

  final double width;
  final String label;
  final IconData? icon;
  final bool header;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: header || shaded
            ? context.tokens.surfaceSoft
            : context.colors.surface,
        border: Border(bottom: BorderSide(color: context.tokens.border)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: context.tokens.muted),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: header ? context.text.labelLarge : context.text.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonValueCell extends StatelessWidget {
  const _ComparisonValueCell({
    required this.width,
    required this.value,
    required this.shaded,
  });

  final double width;
  final String value;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 46),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: shaded ? context.tokens.surfaceSoft : context.colors.surface,
        border: Border(
          left: BorderSide(color: context.tokens.border),
          bottom: BorderSide(color: context.tokens.border),
        ),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.text.labelSmall,
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.billing,
    required this.onOpenPortal,
    required this.onCancel,
  });

  final ProfessionalBillingStatus billing;
  final VoidCallback onOpenPortal;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isPaid =
        billing.planCode != 'starter_free' && billing.planCode != 'starter';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Membership', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _MembershipRow(label: 'Current plan', value: billing.planName),
          if (billing.planRenewsAt != null)
            _MembershipRow(
              label: 'Expires or renews',
              value: shortDate(billing.planRenewsAt!),
            ),
          if (billing.cancellationEffectiveAt != null)
            _MembershipRow(
              label: 'Cancellation effective',
              value: shortDate(billing.cancellationEffectiveAt!),
            ),
          if (billing.paymentsEnabled &&
              (billing.billingConfigured || isPaid)) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (billing.billingConfigured)
                  OutlinedButton(
                    onPressed: onOpenPortal,
                    child: const Text('Billing portal'),
                  ),
                if (isPaid)
                  OutlinedButton(
                    onPressed: billing.cancellationEffectiveAt == null
                        ? onCancel
                        : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    child: Text(
                      billing.cancellationEffectiveAt == null
                          ? 'Cancel membership'
                          : 'Cancellation scheduled',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MembershipRow extends StatelessWidget {
  const _MembershipRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(
                color: context.tokens.muted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: context.text.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
