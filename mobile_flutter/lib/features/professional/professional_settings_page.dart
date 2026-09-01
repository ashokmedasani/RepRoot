import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/account_models.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/password_field.dart';
import 'professional_format.dart';

/// Settings — My Account, Plan & Storage, Security (professional code + password).
/// Replica of mobile/src/app/pages/professional/settings/professional-settings.page.ts.
class ProfessionalSettingsPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsPage> createState() =>
      _ProfessionalSettingsPageState();
}

class _ProfessionalSettingsPageState
    extends ConsumerState<ProfessionalSettingsPage> {
  final _professionalCode = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  ProfessionalProfile? _profile;
  ProfessionalDataUsage? _usage;
  ProfessionalBillingStatus? _billing;
  List<RecycleBinItem> _recycleBin = [];
  bool _billingBusy = false;
  String _originalCode = '';
  bool _isSavingCode = false;
  String _codeMessage = '';
  bool _codeError = false;
  bool _isChangingPassword = false;
  String _passwordMessage = '';
  bool _passwordError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _professionalCode.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    var partialLoadFailed = false;
    try {
      final profile = await api.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _professionalCode.text = profile.professionalId.isNotEmpty
            ? profile.professionalId
            : profile.professionalCode;
        _originalCode = _professionalCode.text;
      });
    } catch (error) {
      debugPrint('Could not load professional profile: $error');
      partialLoadFailed = true;
    }
    try {
      final usage = await api.getDataUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (error) {
      debugPrint('Could not load professional data usage: $error');
      partialLoadFailed = true;
    }
    try {
      final billing = await api.getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (error) {
      debugPrint('Could not load professional billing status: $error');
      partialLoadFailed = true;
    }
    try {
      final bin = await api.getRecycleBin();
      if (mounted) setState(() => _recycleBin = bin);
    } catch (error) {
      debugPrint('Could not load professional recycle bin: $error');
      partialLoadFailed = true;
    }
    if (partialLoadFailed) {
      _toast('Some account details could not be loaded. Pull down to retry.');
    }
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
      final url = await ref
          .read(professionalAuthApiProvider)
          .createBillingCheckout(
            tier,
            billingCycle: billingCycle,
            currency: currency,
          );
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _toast('Plan updated.');
      }
      final billing = await ref
          .read(professionalAuthApiProvider)
          .getBillingStatus();
      if (mounted) setState(() => _billing = billing);
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not update the plan.',
      );
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
                  DropdownMenuItem(
                    value: 'six_months',
                    child: Text('6 Months · pay for 5'),
                  ),
                  DropdownMenuItem(
                    value: 'yearly',
                    child: Text('Yearly · pay for 10'),
                  ),
                ],
                onChanged: (value) =>
                    setDialogState(() => cycle = value ?? cycle),
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
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => context.pop(true),
              child: const Text('Continue to checkout'),
            ),
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
      final names = (entry.value['locked_names'] as List<dynamic>? ?? [])
          .take(5)
          .join(', ');
      final label = labels[entry.key] ?? entry.key;
      lockLines.add(
        '$lockedCount $label${lockedCount == 1 ? '' : 's'} would lock ($names)',
      );
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
      lockLines.add(
        '${billing.clientsLosingAccess.length} client(s) would lose portal access until you upgrade again: $names',
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel plan?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paid access remains active until expiry, then the account moves to Free. Nothing is ever deleted.',
            ),
            for (final line in lockLines) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(line),
            ],
          ],
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
      final refreshed = await ref
          .read(professionalAuthApiProvider)
          .getBillingStatus();
      if (mounted) setState(() => _billing = refreshed);
    } catch (error) {
      _toast(
        error is ApiException ? error.message : 'Could not cancel the plan.',
      );
    }
  }

  Future<void> _openBillingPortal() async {
    try {
      final url = await ref
          .read(professionalAuthApiProvider)
          .createBillingPortal();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _toast('Billing portal is not available yet.');
      }
    } catch (error) {
      _toast(
        error is ApiException
            ? error.message
            : 'Could not open billing portal.',
      );
    }
  }

  Future<void> _restoreBinItem(RecycleBinItem item) async {
    try {
      await ref
          .read(professionalAuthApiProvider)
          .restoreRecycleBinItem(item.id);
      if (mounted) {
        setState(
          () =>
              _recycleBin = _recycleBin.where((i) => i.id != item.id).toList(),
        );
      }
      _toast('Restored.');
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not restore.');
    }
  }

  Future<void> _deleteBinItem(RecycleBinItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${item.title}" forever?'),
        content: const Text('This cannot be undone.'),
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
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(professionalAuthApiProvider)
          .deleteRecycleBinItemPermanently(item.id);
      if (mounted) {
        setState(
          () =>
              _recycleBin = _recycleBin.where((i) => i.id != item.id).toList(),
        );
      }
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not delete.');
    }
  }

  double get _usagePercent => ((_usage?.usagePercent ?? 0) * 10).round() / 10;

  bool get _canSaveCode =>
      !_isSavingCode &&
      _professionalCode.text.trim().isNotEmpty &&
      _professionalCode.text != _originalCode;

  bool get _canChangePassword =>
      !_isChangingPassword &&
      _currentPassword.text.isNotEmpty &&
      _newPassword.text.length >= 8 &&
      _newPassword.text == _confirmPassword.text;

  Future<void> _saveProfessionalCode() async {
    setState(() {
      _isSavingCode = true;
      _codeMessage = '';
    });
    try {
      final code = await ref
          .read(professionalAuthApiProvider)
          .updateProfessionalCode(_professionalCode.text.trim());
      if (!mounted) return;
      setState(() {
        _isSavingCode = false;
        _professionalCode.text = code;
        _originalCode = code;
        _codeError = false;
        _codeMessage = 'Professional code updated.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingCode = false;
        _codeError = true;
        _codeMessage = error.message;
      });
    }
  }

  Future<void> _changePassword() async {
    setState(() {
      _isChangingPassword = true;
      _passwordMessage = '';
    });
    try {
      final message = await ref
          .read(professionalAuthApiProvider)
          .changePassword(
            _currentPassword.text,
            _newPassword.text,
            _confirmPassword.text,
          );
      if (!mounted) return;
      setState(() {
        _isChangingPassword = false;
        _passwordError = false;
        _passwordMessage = message.isNotEmpty ? message : 'Password changed.';
        _currentPassword.clear();
        _newPassword.clear();
        _confirmPassword.clear();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isChangingPassword = false;
        _passwordError = true;
        _passwordMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(
          onPressed: () => context.go(Routes.professionalMore),
        ),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          _Card(
            title: 'My Account',
            child: _KvList(
              rows: [
                ('Name', profile?.displayName ?? '—'),
                ('Username', profile?.username ?? '—'),
                ('Email', profile?.email ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _Card(
            title: 'Plan & Storage',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KvList(
                  rows: [
                    (
                      'Plan',
                      _usage?.planName.isNotEmpty ?? false
                          ? _usage!.planName
                          : '—',
                    ),
                    ('Storage used', '$_usagePercent%'),
                    if ((_usage?.usageLabel ?? '').isNotEmpty)
                      ('Capacity', titleCase(_usage!.usageLabel)),
                    (
                      'Records',
                      '${_usage?.recordCount ?? 0}'
                          '${_usage != null && _usage!.totalBytes > 0 ? ' · ${formatBytes(_usage!.totalBytes)}' : ''}',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_usagePercent / 100).clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: tokens.surfaceSoft,
                    color: _usage?.isDanger ?? false
                        ? context.colors.error
                        : _usage?.isWarning ?? false
                        ? tokens.accent
                        : context.colors.primary,
                  ),
                ),
                if (_usage?.isLocked ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _usage!.lockReason.isNotEmpty
                        ? _usage!.lockReason
                        : 'Uploads are paused — you are over your storage quota.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.error,
                    ),
                  ),
                ] else if (_usage?.gracePeriodEndsAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Grace period ends ${shortDate(_usage!.gracePeriodEndsAt!)}.',
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.accent,
                    ),
                  ),
                ],
              ],
            ),
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
                      (
                        'Current plan',
                        _billing!.planName.isNotEmpty
                            ? _billing!.planName
                            : '—',
                      ),
                      if (_billing!.planRenewsAt != null)
                        (
                          'Expires / renews',
                          shortDate(_billing!.planRenewsAt!),
                        ),
                      if (_billing!.cancellationEffectiveAt != null)
                        (
                          'Cancellation effective',
                          shortDate(_billing!.cancellationEffectiveAt!),
                        ),
                      (
                        'Free storage usage',
                        '${_billing!.freeStoragePercent}%',
                      ),
                    ],
                  ),
                  if (_billing!.testMode) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Test mode — plan changes apply instantly with no charge.',
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  for (final tier in _billing!.upgradeTiers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _billingBusy
                              ? null
                              : () => _choosePlan(tier),
                          child: Text(
                            'Switch to ${ProfessionalUpgradeTier.label(tier)}',
                          ),
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
                        if (_billing!.billingConfigured)
                          const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _billing!.cancellationEffectiveAt == null
                                ? _cancelPlan
                                : null,
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

          _Card(
            title: 'Notifications',
            child: InkWell(
              onTap: () => context.push(
                '${Routes.professionalNotifications}/preferences',
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose how you\'re notified per category (website, email, digest).',
                        style: context.text.bodySmall,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: AppSize.iconRow,
                      color: tokens.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          if (_recycleBin.isNotEmpty) ...[
            _Card(
              title: 'Recycle bin',
              child: Column(
                children: [
                  for (final item in _recycleBin)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title.isNotEmpty
                                      ? item.title
                                      : item.categoryLabel,
                                  style: context.text.bodyMedium,
                                ),
                                Text(
                                  '${item.categoryLabel} · ${item.daysRemaining}d left',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => _restoreBinItem(item),
                            child: const Text('Restore'),
                          ),
                          IconButton(
                            onPressed: () => _deleteBinItem(item),
                            icon: const Icon(Icons.delete_forever_outlined),
                            iconSize: AppSize.iconRow,
                            color: context.colors.error,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          _Card(
            title: 'Security',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _professionalCode,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _codeMessage = ''),
                        decoration: const InputDecoration(
                          labelText: 'Professional code',
                          helperText: 'Clients log in with this',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: FilledButton(
                        onPressed: _canSaveCode ? _saveProfessionalCode : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(84, AppSize.buttonHeightSm),
                        ),
                        child: _isSavingCode
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Update'),
                      ),
                    ),
                  ],
                ),
                if (_codeMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _codeMessage,
                      style: context.text.bodySmall?.copyWith(
                        color: _codeError
                            ? context.colors.error
                            : tokens.success,
                      ),
                    ),
                  ),

                const SizedBox(height: AppSpacing.lg),
                PasswordField(
                  controller: _currentPassword,
                  label: 'Current password',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordField(
                  controller: _newPassword,
                  label: 'New password',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordField(
                  controller: _confirmPassword,
                  label: 'Confirm new password',
                  autofillHints: const [AutofillHints.newPassword],
                ),
                if (_passwordMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      _passwordMessage,
                      style: context.text.bodySmall?.copyWith(
                        color: _passwordError
                            ? context.colors.error
                            : tokens.success,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _canChangePassword ? _changePassword : null,
                  child: Text(
                    _isChangingPassword ? 'Updating…' : 'Change password',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _Card(
            title: 'Account deletion',
            child: Text(
              'Professional accounts are deleted through support so your client data '
              'is handled safely. Open Help & Support from the More tab to '
              'request deletion.',
              style: context.text.bodySmall,
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
