import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/password_field.dart';

/// Replica of mobile/src/app/pages/professional/login/professional-login.page.ts.
class ProfessionalLoginPage extends ConsumerStatefulWidget {
  const ProfessionalLoginPage({super.key});

  @override
  ConsumerState<ProfessionalLoginPage> createState() => _ProfessionalLoginPageState();
}

class _ProfessionalLoginPageState extends ConsumerState<ProfessionalLoginPage> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _isSubmitting = false;
  String _message = '';

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Enter your username/email and password.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = '';
    });

    final api = ref.read(professionalAuthApiProvider);
    try {
      final response = await api.login(_identifier.text.trim(), _password.text);
      await api.storeToken(response.token);

      // Same rule as the web portal: incomplete profiles finish setup
      // (name + professional code) before reaching the dashboard. Without this a
      // professional can reach the dashboard with no professional code, and their
      // clients could never log in.
      bool setupComplete;
      try {
        setupComplete = await api.getProfileStatus();
      } catch (_) {
        // Don't strand a signed-in professional on the login screen if this
        // secondary check fails — the dashboard re-checks anyway.
        setupComplete = true;
      }

      if (!mounted) return;
      context.go(setupComplete ? Routes.professionalDashboard : Routes.professionalProfileSetup);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Professional Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AutofillGroup(
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    const AuthBrand(
                      title: 'Welcome back',
                      subtitle: 'Sign in to your professional workspace',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _identifier,
                      enabled: !_isSubmitting,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Username or email',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _password,
                      enabled: !_isSubmitting,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: _isSubmitting ? null : _login,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _login,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.push(Routes.professionalSignup),
                      child: const Text('New professional? Create an account'),
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
