import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/trainer_models.dart';
import '../../core/api/trainer_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/password_field.dart';
import 'trainer_format.dart';

/// Settings — My Account, Plan & Storage, Security (trainer code + password).
/// Replica of mobile/src/app/pages/trainer/settings/trainer-settings.page.ts.
class TrainerSettingsPage extends ConsumerStatefulWidget {
  const TrainerSettingsPage({super.key});

  @override
  ConsumerState<TrainerSettingsPage> createState() => _TrainerSettingsPageState();
}

class _TrainerSettingsPageState extends ConsumerState<TrainerSettingsPage> {
  final _trainerCode = TextEditingController();
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  TrainerProfile? _profile;
  TrainerDataUsage? _usage;
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
    _trainerCode.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(trainerAuthApiProvider);
    try {
      final profile = await api.getProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _trainerCode.text = profile.trainerId.isNotEmpty
            ? profile.trainerId
            : profile.trainerCode;
        _originalCode = _trainerCode.text;
      });
    } catch (_) {/* the account card just shows blanks */}
    try {
      final usage = await api.getDataUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {}
  }

  double get _usagePercent => ((_usage?.usagePercent ?? 0) * 10).round() / 10;

  bool get _canSaveCode =>
      !_isSavingCode &&
      _trainerCode.text.trim().isNotEmpty &&
      _trainerCode.text != _originalCode;

  bool get _canChangePassword =>
      !_isChangingPassword &&
      _currentPassword.text.isNotEmpty &&
      _newPassword.text.length >= 8 &&
      _newPassword.text == _confirmPassword.text;

  Future<void> _saveTrainerCode() async {
    setState(() {
      _isSavingCode = true;
      _codeMessage = '';
    });
    try {
      final code = await ref
          .read(trainerAuthApiProvider)
          .updateTrainerCode(_trainerCode.text.trim());
      if (!mounted) return;
      setState(() {
        _isSavingCode = false;
        _trainerCode.text = code;
        _originalCode = code;
        _codeError = false;
        _codeMessage = 'Trainer code updated.';
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
      final message = await ref.read(trainerAuthApiProvider).changePassword(
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
        leading: BackButton(onPressed: () => context.go(Routes.trainerMore)),
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
              children: [
                _KvList(
                  rows: [
                    ('Plan', _usage?.planName.isNotEmpty ?? false ? _usage!.planName : '—'),
                    ('Storage used', '$_usagePercent%'),
                    (
                      'Records',
                      '${_usage?.recordCount ?? 0}'
                          '${_usage != null && _usage!.totalBytes > 0 ? ' · ${formatBytes(_usage!.totalBytes)}' : ''}'
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
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

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
                        controller: _trainerCode,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _codeMessage = ''),
                        decoration: const InputDecoration(
                          labelText: 'Trainer code',
                          helperText: 'Clients log in with this',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: FilledButton(
                        onPressed: _canSaveCode ? _saveTrainerCode : null,
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
                        color: _codeError ? context.colors.error : tokens.success,
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
                        color:
                            _passwordError ? context.colors.error : tokens.success,
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
              'Trainer accounts are deleted through support so your client data '
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
