import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/password_field.dart';

enum UsernameStatus { idle, checking, available, taken }

enum EmailStatus { idle, sending, sent, verifying, verified }

/// Replica of mobile/src/app/pages/professional/signup/professional-signup.page.ts.
/// Username check -> email OTP -> verify -> create account.
class ProfessionalSignupPage extends ConsumerStatefulWidget {
  const ProfessionalSignupPage({super.key});

  @override
  ConsumerState<ProfessionalSignupPage> createState() => _ProfessionalSignupPageState();
}

class _ProfessionalSignupPageState extends ConsumerState<ProfessionalSignupPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  UsernameStatus _usernameStatus = UsernameStatus.idle;
  EmailStatus _emailStatus = EmailStatus.idle;
  String _usernameMessage = '';
  String _emailMessage = '';
  bool _emailError = false;
  String _verificationToken = '';
  String _debugOtp = '';
  String _message = '';
  bool _agreed = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _usernameValidation(String username) {
    if (username.length < 5 || username.length > 10) {
      return 'Username must be 5 to 10 characters.';
    }
    if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(username)) {
      return "Only letters, numbers, '.' and '-' are allowed.";
    }
    return '';
  }

  Future<void> _verifyUsername() async {
    final username = _username.text.trim().toLowerCase();
    final validation = _usernameValidation(username);
    if (validation.isNotEmpty) {
      setState(() {
        _usernameStatus = UsernameStatus.taken;
        _usernameMessage = validation;
      });
      return;
    }

    setState(() => _usernameStatus = UsernameStatus.checking);
    try {
      final result = await ref.read(professionalAuthApiProvider).checkUsername(username);
      if (!mounted) return;
      setState(() {
        _usernameStatus =
            result.available ? UsernameStatus.available : UsernameStatus.taken;
        _usernameMessage = result.message;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _usernameStatus = UsernameStatus.taken;
        _usernameMessage = error.message;
      });
    }
  }

  Future<void> _sendOtp() async {
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      setState(() {
        _emailError = true;
        _emailMessage = 'Enter a valid email address.';
      });
      return;
    }

    setState(() {
      _emailStatus = EmailStatus.sending;
      _emailError = false;
    });
    try {
      final result = await ref.read(professionalAuthApiProvider).requestEmailOtp(email);
      if (!mounted) return;
      setState(() {
        // available == false means the email is already registered.
        if (result.available == false) {
          _emailStatus = EmailStatus.idle;
          _emailError = true;
        } else {
          _emailStatus = EmailStatus.sent;
        }
        _emailMessage = result.message;
        _debugOtp = result.devOtp;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _emailStatus = EmailStatus.idle;
        _emailError = true;
        _emailMessage = error.message;
      });
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _emailStatus = EmailStatus.verifying;
      _emailError = false;
    });
    try {
      final result = await ref
          .read(professionalAuthApiProvider)
          .verifyEmailOtp(_email.text.trim().toLowerCase(), _otp.text.trim());
      if (!mounted) return;
      setState(() {
        _verificationToken = result.emailVerificationToken;
        _emailStatus = EmailStatus.verified;
        _emailMessage = result.message;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _emailStatus = EmailStatus.sent;
        _emailError = true;
        _emailMessage = error.message;
      });
    }
  }

  Future<void> _createAccount() async {
    setState(() => _message = '');

    if (_usernameStatus != UsernameStatus.available) {
      setState(() => _message = 'Verify an available username first.');
      return;
    }
    if (_emailStatus != EmailStatus.verified || _verificationToken.isEmpty) {
      setState(() => _message = 'Verify your email first.');
      return;
    }
    if (_password.text.length < 8 ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(_password.text)) {
      setState(() => _message =
          'Password must be at least 8 characters with one special character.');
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() => _message = 'Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);
    final api = ref.read(professionalAuthApiProvider);
    try {
      final response = await api.signup(
        ProfessionalSignupPayload(
          username: _username.text.trim().toLowerCase(),
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
          confirmPassword: _confirmPassword.text,
          emailVerificationToken: _verificationToken,
        ),
      );
      await api.storeToken(response.token);
      if (!mounted) return;
      // New accounts always need profile setup (name + professional code) before
      // the dashboard, matching the web portal's first-login step.
      context.go(Routes.professionalProfileSetup);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final busy = _usernameStatus == UsernameStatus.checking;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const AuthBrand(
                    title: 'Join RepRoot',
                    subtitle: 'Set up your professional account',
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // --- Username ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _username,
                          enabled: !_isSubmitting,
                          autocorrect: false,
                          onChanged: (_) => setState(() {
                            _usernameStatus = UsernameStatus.idle;
                            _usernameMessage = '';
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            helperText: '5-10 characters, letters/numbers/.-',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: OutlinedButton(
                          onPressed: busy || _isSubmitting ? null : _verifyUsername,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(88, AppSize.buttonHeightSm),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Check'),
                        ),
                      ),
                    ],
                  ),
                  _StatusLine(
                    message: _usernameMessage,
                    isError: _usernameStatus == UsernameStatus.taken,
                    isSuccess: _usernameStatus == UsernameStatus.available,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // --- Email + OTP ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _email,
                          enabled: !_isSubmitting &&
                              _emailStatus != EmailStatus.verified,
                          autocorrect: false,
                          keyboardType: TextInputType.emailAddress,
                          onChanged: (_) => setState(() {
                            _emailStatus = EmailStatus.idle;
                            _emailMessage = '';
                            _verificationToken = '';
                            _debugOtp = '';
                          }),
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: OutlinedButton(
                          onPressed: _emailStatus == EmailStatus.sending ||
                                  _emailStatus == EmailStatus.verified ||
                                  _isSubmitting
                              ? null
                              : _sendOtp,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(88, AppSize.buttonHeightSm),
                          ),
                          child: _emailStatus == EmailStatus.sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_emailStatus == EmailStatus.sent
                                  ? 'Resend'
                                  : 'Send code'),
                        ),
                      ),
                    ],
                  ),
                  _StatusLine(
                    message: _emailMessage,
                    isError: _emailError,
                    isSuccess: _emailStatus == EmailStatus.verified,
                  ),
                  if (_debugOtp.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Dev code: $_debugOtp',
                        style: context.text.bodySmall?.copyWith(color: tokens.accent),
                      ),
                    ),
                  if (_emailStatus == EmailStatus.sent ||
                      _emailStatus == EmailStatus.verifying) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otp,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Verification code',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: OutlinedButton(
                            onPressed: _emailStatus == EmailStatus.verifying
                                ? null
                                : _verifyOtp,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(88, AppSize.buttonHeightSm),
                            ),
                            child: _emailStatus == EmailStatus.verifying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Verify'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),

                  // --- Password ---
                  PasswordField(
                    controller: _password,
                    enabled: !_isSubmitting,
                    label: 'Password',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PasswordField(
                    controller: _confirmPassword,
                    enabled: !_isSubmitting,
                    label: 'Confirm password',
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // --- Terms ---
                  InkWell(
                    onTap: () => setState(() => _agreed = !_agreed),
                    borderRadius: AppRadius.smAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreed,
                            onChanged: (value) =>
                                setState(() => _agreed = value ?? false),
                            visualDensity: VisualDensity.compact,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                'I agree to the Terms & Conditions and Privacy Policy.',
                                style: context.text.bodySmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _isSubmitting || !_agreed ? null : _createAccount,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Create account'),
                  ),
                  FormMessage(message: _message),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.message,
    required this.isError,
    required this.isSuccess,
  });

  final String message;
  final bool isError;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final color = isError
        ? context.colors.error
        : isSuccess
            ? context.tokens.success
            : context.tokens.muted;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(message, style: context.text.bodySmall?.copyWith(color: color)),
    );
  }
}
