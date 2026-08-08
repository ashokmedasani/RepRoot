import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models/account_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Billing & Plans — current plan, upgrade buttons, billing portal / cancel
/// membership, and the plan-tier comparison table.
/// Split out of the former single-scroll professional_settings_page.dart
/// (was the "Billing" + "Compare plans" cards).
class ProfessionalSettingsBillingPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsBillingPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsBillingPage> createState() =>
      _ProfessionalSettingsBillingPageState();
}

class _ProfessionalSettingsBillingPageState
    extends ConsumerState<ProfessionalSettingsBillingPage> {
  ProfessionalBillingStatus? _billing;
  bool _billingBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    try {
      final billing = await api.getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (_) {}
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _changePlan(
    String tier, {
    String billingCycle = 'monthly',
    String currency = 'INR',
  }) async {
    if (_billingBusy) return;
    setState(() => _billingBusy = true);
    try {
      final url = await ref.read(professionalAuthApiProvider).createBillingCheckout(
            tier,
            billingCycle: billingCycle,
            currency: currency,
          );
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _toast('Plan updated.');
      }
      final billing = await ref.read(professionalAuthApiProvider).getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not update the plan.');
    }
    if (mounted) setState(() => _billingBusy = false);
  }

  Future<void> _choosePlan(String tier) async {
    var cycle = 'monthly';
    final currency = _billing?.billingCurrency ?? 'USD';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Choose ${ProfessionalUpgradeTier.label(tier)} billing'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: cycle,
                decoration: const InputDecoration(labelText: 'Billing period'),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'six_months', child: Text('6 Months · pay for 5')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly · pay for 10')),
                ],
                onChanged: (value) => setDialogState(() => cycle = value ?? cycle),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_billing?.billingRegion ?? 'International'} · $currency',
                  style: context.text.labelLarge,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => context.pop(true), child: const Text('Continue to checkout')),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _changePlan(tier, billingCycle: cycle, currency: currency);
    }
  }

  Future<void> _cancelPlan() async {
    final billing = _billing;
    if (billing == null) return;
    if (!billing.storageDowngradeEligible) {
      _toast(
        'Cancellation is blocked because storage is ${billing.freeStoragePercent}% of the Free allowance. '
        'Contact ${billing.supportEmail.isNotEmpty ? billing.supportEmail : 'support'}.',
      );
      return;
    }
    // Nothing here is ever deleted -- anything over the Free plan's limits
    // simply locks (in priority order) and unlocks automatically the moment
    // you upgrade again. The dialog spells out exactly what would lock, by
    // name, plus the category-cascade rule and which clients would lose
    // portal access -- no generic "may be deleted" copy, nothing to type.
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
      final names = (entry.value['locked_names'] as List<dynamic>? ?? []).take(5).join(', ');
      final label = labels[entry.key] ?? entry.key;
      lockLines.add('$lockedCount $label${lockedCount == 1 ? '' : 's'} would lock ($names)');
    }
    if (billing.categoryCascadeResourceCount > 0) {
      lockLines.add(
        '${billing.categoryCascadeResourceCount} resource(s) would lock because their category would lock, regardless of how many resources it contains',
      );
    }
    if (billing.clientsLosingAccess.isNotEmpty) {
      final names = billing.clientsLosingAccess
          .take(5)
          .map((c) => '${c['client_name']} (${c['group_name']})')
          .join(', ');
      lockLines.add('${billing.clientsLosingAccess.length} client(s) would lose portal access until you upgrade again: $names');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel plan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paid access remains active until expiry, then the account moves to Free. Nothing is ever deleted.'),
            for (final line in lockLines) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(line),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Keep plan')),
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
      final message = await ref.read(professionalAuthApiProvider).cancelBillingPlan();
      _toast(message.isNotEmpty ? message : 'Cancellation scheduled.');
      final refreshed = await ref.read(professionalAuthApiProvider).getBillingStatus();
      if (mounted) setState(() => _billing = refreshed);
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not cancel the plan.');
    }
  }

  Future<void> _openBillingPortal() async {
    try {
      final url = await ref.read(professionalAuthApiProvider).createBillingPortal();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _toast('Billing portal is not available yet.');
      }
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not open billing portal.');
    }
  }

  /// Monthly price for a tier from the same `catalog` the checkout dialog
  /// already reads (`catalog.trainer[code][cycle][currency]`) — Free has no
  /// catalog entry and is always free.
  String _planPrice(ProfessionalPlanTier tier) {
    if (tier.code == 'starter_free' || tier.code == 'starter') return 'Free';
    final billing = _billing;
    if (billing == null) return '—';
    final currency = billing.billingCurrency.isNotEmpty ? billing.billingCurrency : 'USD';
    final trainer = billing.catalog['trainer'] as Map<dynamic, dynamic>?;
    final tierPrices = trainer?[tier.code] as Map<dynamic, dynamic>?;
    final monthly = tierPrices?['monthly'] as Map<dynamic, dynamic>?;
    final value = monthly?[currency];
    if (value == null) return '—';
    return '$currency ${value.toString()}/mo';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing & Plans'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          const SettingsHeroCard(
            icon: Icons.credit_card_outlined,
            title: 'Billing & Plans',
            subtitle: 'View plans, usage and billing history.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (_billing != null) ...[
            _Card(
              title: 'Billing',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KvList(
                    rows: [
                      ('Current plan', _billing!.planName.isNotEmpty ? _billing!.planName : '—'),
                      if (_billing!.planRenewsAt != null)
                        ('Expires / renews', shortDate(_billing!.planRenewsAt!)),
                      if (_billing!.cancellationEffectiveAt != null)
                        ('Cancellation effective', shortDate(_billing!.cancellationEffectiveAt!)),
                      ('Free storage usage', '${_billing!.freeStoragePercent}%'),
                    ],
                  ),
                  if (_billing!.testMode) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text('Test mode — plan changes apply instantly with no charge.',
                        style: context.text.bodySmall?.copyWith(color: tokens.muted)),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  for (final tier in _billing!.upgradeTiers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _billingBusy ? null : () => _choosePlan(tier),
                          child: Text('Switch to ${ProfessionalUpgradeTier.label(tier)}'),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      if (_billing!.billingConfigured)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _openBillingPortal,
                            child: const Text('Billing portal'),
                          ),
                        ),
                      if (_billing!.planCode != 'starter_free' &&
                          _billing!.planCode != 'starter') ...[
                        if (_billing!.billingConfigured) const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _billing!.cancellationEffectiveAt == null ? _cancelPlan : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.error,
                            ),
                            child: Text(
                              _billing!.cancellationEffectiveAt == null
                                  ? 'Cancel membership'
                                  : 'Cancellation scheduled',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          if (_billing != null && _billing!.plans.isNotEmpty) ...[
            _Card(
              title: 'Compare plans',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _billing!.plans.length; i++) ...[
                    if (i > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      Divider(color: tokens.border),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    _PlanTierRow(
                      tier: _billing!.plans[i],
                      isCurrent: _billing!.plans[i].code == _billing!.planCode,
                      price: _planPrice(_billing!.plans[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
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

/// One tier in the Compare Plans card — every number comes from
/// [ProfessionalPlanTier], which is parsed straight off the API's `plans`
/// list (itself `settings.REPROOT_PLAN_TIERS`). Nothing here is hardcoded,
/// so a backend limit change needs zero changes in this file.
class _PlanTierRow extends StatelessWidget {
  const _PlanTierRow({
    required this.tier,
    required this.isCurrent,
    required this.price,
  });

  final ProfessionalPlanTier tier;
  final bool isCurrent;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tier.name.isNotEmpty ? tier.name : tier.code,
                style: context.text.titleMedium,
              ),
            ),
            Text(price, style: context.text.titleSmall),
          ],
        ),
        if (isCurrent) ...[
          const SizedBox(height: AppSpacing.xs),
          StatusPill(label: 'Current plan', tone: PillTone.good),
        ],
        const SizedBox(height: AppSpacing.sm),
        _KvList(
          rows: [
            ('Lead forms', '${tier.leadForms}'),
            ('Clients', tier.clients == null ? 'Unlimited' : '${tier.clients}'),
            ('Storage', formatBytes(tier.storageBytes)),
            ('Groups', '${tier.groups}'),
            ('Resources', '${tier.resources}'),
            ('Categories', '${tier.categories}'),
            ('Client history', '${tier.clientDataRetentionDays} days'),
          ],
        ),
      ],
    );
  }
}

/// Label/value rows — the .kv-list rule.
class _KvList extends StatelessWidget {
  const _KvList({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(label, style: context.text.bodySmall),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    value.trim().isEmpty ? '—' : value,
                    style: context.text.titleSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
