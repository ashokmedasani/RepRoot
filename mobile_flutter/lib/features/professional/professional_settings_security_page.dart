import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/password_field.dart';

/// Security — professional code update + change password.
/// Split out of the former single-scroll professional_settings_page.dart.
class ProfessionalSettingsSecurityPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsSecurityPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsSecurityPage> createState() =>
      _ProfessionalSettingsSecurityPageState();
}

class _ProfessionalSettingsSecurityPageState
    extends ConsumerState<ProfessionalSettingsSecurityPage> {
  final _professionalCode = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

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
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    try {
      final profile = await api.getProfile();
      if (!mounted) return;
      setState(() {
        _professionalCode.text = profile.professionalId.isNotEmpty
            ? profile.professionalId
            : profile.professionalCode;
        _originalCode = _professionalCode.text;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Professional code load failed (${error.runtimeType})\n$stackTrace',
      );
    }
  }

  bool get _canSaveCode =>
      !_isSavingCode &&
      _professionalCode.text.trim().isNotEmpty &&
      _professionalCode.text != _originalCode;

  bool get _canChangePassword =>
      !_isChangingPassword &&
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
          .changePassword(_newPassword.text, _confirmPassword.text);
      if (!mounted) return;
      setState(() {
        _isChangingPassword = false;
        _passwordError = false;
        _passwordMessage = message.isNotEmpty ? message : 'Password changed.';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        children: [
          const SettingsHeroCard(
            icon: Icons.lock_outline,
            title: 'Security',
            subtitle: 'Update your password and professional code.',
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Account security',
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
                // No current-password field. The backend's
                // ProfessionalPasswordChangeSerializer has never had one, so
                // this box was accepting input and discarding it — worse than
                // absent, because it looked like a check that was happening.
                // It also cannot work for Google accounts, which have no
                // password to re-enter.
                //
                // Changing the password still signs every session out (the
                // view deletes all tokens), so an attacker cannot use this
                // quietly.
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
