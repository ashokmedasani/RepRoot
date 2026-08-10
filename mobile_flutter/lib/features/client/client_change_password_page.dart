import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/password_field.dart';

/// Forced first-login password change.
///
/// DELIBERATE DIFFERENCE from the Ionic app: mobile never enforced this — it
/// sent every client straight to the dashboard, so a professional-issued temporary
/// password stayed valid indefinitely. The web portal gates on
/// `must_change_password` at login, and this matches the web.
///
/// The backend rotates the token on success, so the new one must replace the
/// stored session or every later call 401s.
class ClientChangePasswordPage extends ConsumerStatefulWidget {
  const ClientChangePasswordPage({super.key});

  @override
  ConsumerState<ClientChangePasswordPage> createState() =>
      _ClientChangePasswordPageState();
}

class _ClientChangePasswordPageState
    extends ConsumerState<ClientChangePasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _isSaving = false;
  String _message = '';

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_isSaving &&
      _current.text.isNotEmpty &&
      _next.text.length >= 8 &&
      _next.text == _confirm.text;

  String _validate() {
    if (_current.text.isEmpty) {
      return 'Enter the password your professional gave you.';
    }
    if (_next.text.length < 8) {
      return 'New password must be at least 8 characters.';
    }
    if (_next.text == _current.text) {
      return 'Choose a different password from the temporary one.';
    }
    if (_next.text != _confirm.text) return 'Passwords do not match.';
    return '';
  }

  Future<void> _save() async {
    final validation = _validate();
    if (validation.isNotEmpty) {
      setState(() => _message = validation);
      return;
    }

    setState(() {
      _isSaving = true;
      _message = '';
    });

    final api = ref.read(clientApiProvider);
    try {
      final response = await api.changePassword(
        _current.text,
        _next.text,
        _confirm.text,
      );
      // The token rotated — store the new session or the next call 401s.
      final client = response.client;
      if (client != null && response.token.isNotEmpty) {
        await api.storeSession(response.token, client);
      }
      if (!mounted) return;
      // Legal consent is the next gate once the password is dealt with, the
      // same handoff the web component makes with `needsLegalAcceptance`.
      context.go(
        client != null && !client.legalAccepted
            ? Routes.clientLegalConsent
            : Routes.clientDashboard,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _message = error.message;
      });
    }
  }

  Future<void> _signOut() async {
    final api = ref.read(clientApiProvider);
    try {
      await api.logout();
    } catch (error, stackTrace) {
      debugPrint(
        'Client logout request failed; clearing the local session '
        '(${error.runtimeType}).\n$stackTrace',
      );
    }
    await api.clearSession();
    if (mounted) context.go(Routes.roleChooser);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set your password'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(onPressed: _signOut, child: const Text('Sign out')),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    const AuthBrand(
                      title: 'Choose a password',
                      subtitle:
                          'Your professional gave you a temporary one. Pick your own '
                          'to continue.',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PasswordField(
                      controller: _current,
                      label: 'Temporary password',
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      onSubmitted: null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _next,
                      label: 'New password',
                      enabled: !_isSaving,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _confirm,
                      label: 'Confirm new password',
                      enabled: !_isSaving,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: _canSave ? _save : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'At least 8 characters.',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Save and continue'),
                    ),
                    FormMessage(message: _message),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
