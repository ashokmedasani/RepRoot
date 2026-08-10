import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/password_field.dart';

/// Where the recovery flow currently stands. Mirrors the `ResetOtpStatus` union
/// in the web component so the two apps branch identically.
enum ResetOtpStatus { idle, sent, verified, failed }

/// One line of the live password checklist. The rules are the mobile copy of
/// `password-requirements.util.ts`, which itself mirrors
/// `validate_strong_password` in backend/accounts/serializers.py — keep all
/// three in sync.
class _PasswordRule {
  const _PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String value) test;
}

final _passwordRules = <_PasswordRule>[
  _PasswordRule('At least 8 characters', (value) => value.length >= 8),
  _PasswordRule(
    'One uppercase letter',
    (value) => RegExp(r'[A-Z]').hasMatch(value),
  ),
  _PasswordRule(
    'One lowercase letter',
    (value) => RegExp(r'[a-z]').hasMatch(value),
  ),
  _PasswordRule('One number', (value) => RegExp(r'[0-9]').hasMatch(value)),
  _PasswordRule(
    'One special character',
    (value) => RegExp(r'[^A-Za-z0-9]').hasMatch(value),
  ),
];

final _otpPattern = RegExp(r'^\d{6}$');

/// Professional password recovery.
///
/// Port of frontend/src/app/pages/studio/professional/professional-forgot-password —
/// email -> reset OTP -> verify -> new password, all unauthenticated. Without it
/// a professional who forgets their password has no way back in on mobile.
class ProfessionalForgotPasswordPage extends ConsumerStatefulWidget {
  const ProfessionalForgotPasswordPage({super.key});

  @override
  ConsumerState<ProfessionalForgotPasswordPage> createState() =>
      _ProfessionalForgotPasswordPageState();
}

class _ProfessionalForgotPasswordPageState
    extends ConsumerState<ProfessionalForgotPasswordPage> {
  /// Matches `startResendCountdown()` in the web component.
  static const int _resendSeconds = 30;

  final _email = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  ResetOtpStatus _status = ResetOtpStatus.idle;
  Timer? _resendTimer;
  int _resendCountdown = 0;

  bool _isRequestingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isResettingPassword = false;
  bool _isEmailMissing = false;

  String _resetToken = '';
  String _otpMessage = '';
  String _debugOtp = '';
  String _formMessage = '';

  String _emailError = '';
  String _otpError = '';
  String _passwordError = '';
  String _confirmPasswordError = '';
  String _generalError = '';

  @override
  void initState() {
    super.initState();
    _password.addListener(_handlePasswordChanged);
    _confirmPassword.addListener(_handleConfirmPasswordChanged);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _password.removeListener(_handlePasswordChanged);
    _confirmPassword.removeListener(_handleConfirmPasswordChanged);
    _email.dispose();
    _otp.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // ----- derived state -----

  bool get _canSendOtp =>
      !_isRequestingOtp &&
      _status != ResetOtpStatus.sent &&
      _status != ResetOtpStatus.verified;

  bool get _canResendOtp =>
      !_isRequestingOtp &&
      _resendCountdown == 0 &&
      _status == ResetOtpStatus.sent;

  bool get _canVerifyOtp =>
      !_isVerifyingOtp &&
      _status != ResetOtpStatus.verified &&
      _status != ResetOtpStatus.idle &&
      _otpPattern.hasMatch(_otp.text.trim());

  bool get _isPasswordStrong =>
      _passwordRules.every((rule) => rule.test(_password.text));

  bool get _canSubmitNewPassword =>
      !_isResettingPassword &&
      _isPasswordStrong &&
      _password.text == _confirmPassword.text;

  String get _otpHelpText {
    switch (_status) {
      case ResetOtpStatus.verified:
        return 'Email verified successfully.';
      case ResetOtpStatus.sent:
        return 'OTP sent to your email. Please submit your OTP and verify.';
      case ResetOtpStatus.failed:
      case ResetOtpStatus.idle:
        return '';
    }
  }

  // ----- field handlers -----

  void _handleEmailChanged(String _) {
    if (_emailError.isEmpty && !_isEmailMissing) return;
    setState(() {
      _emailError = '';
      _isEmailMissing = false;
    });
  }

  void _handleOtpChanged(String _) {
    setState(() {
      _otpError = '';
      if (_status == ResetOtpStatus.failed) {
        _status = ResetOtpStatus.sent;
      }
    });
  }

  void _handlePasswordChanged() {
    setState(() {
      _passwordError = '';
      _confirmPasswordError =
          _confirmPassword.text.isNotEmpty &&
              _password.text != _confirmPassword.text
          ? 'Confirm password must match Password.'
          : '';
    });
  }

  void _handleConfirmPasswordChanged() {
    setState(() {
      _confirmPasswordError =
          _confirmPassword.text.isNotEmpty &&
              _password.text != _confirmPassword.text
          ? 'Confirm password must match Password.'
          : '';
    });
  }

  void _clearFieldErrors() {
    _emailError = '';
    _otpError = '';
    _passwordError = '';
    _confirmPasswordError = '';
    _generalError = '';
  }

  // ----- actions -----

  Future<void> _requestOtp({bool isResend = false}) async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _emailError = 'Email is required.');
      return;
    }
    if ((!isResend && !_canSendOtp) || (isResend && !_canResendOtp)) return;

    setState(() {
      _resetToken = '';
      _isRequestingOtp = true;
      _isEmailMissing = false;
      _status = isResend ? ResetOtpStatus.sent : ResetOtpStatus.idle;
      _formMessage = '';
      _debugOtp = '';
      _clearFieldErrors();
      _otpMessage = 'Sending password reset code...';
    });

    try {
      final result = await ref
          .read(professionalAuthApiProvider)
          .requestPasswordResetOtp(email);
      if (!mounted) return;

      // `available: true` means no professional account owns this email, so
      // the backend deliberately sent nothing.
      if (result.available == true) {
        setState(() {
          _isRequestingOtp = false;
          _isEmailMissing = true;
          _status = ResetOtpStatus.idle;
          _otpMessage = 'No professional account found for this email.';
        });
        return;
      }

      _otp.clear();
      setState(() {
        _isRequestingOtp = false;
        _status = ResetOtpStatus.sent;
        _otpMessage = result.message;
        _debugOtp = result.devOtp;
      });
      _startResendCountdown();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isRequestingOtp = false;
        _status = ResetOtpStatus.failed;
        _otpMessage = error.message;
      });
    }
  }

  Future<void> _verifyOtp() async {
    final email = _email.text.trim().toLowerCase();
    final otp = _otp.text.trim();
    if (email.isEmpty || !_otpPattern.hasMatch(otp)) {
      setState(
        () => _otpError = 'Enter the complete 6-digit verification code.',
      );
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
      _otpError = '';
      _otpMessage = 'Verifying reset code...';
    });

    try {
      final result = await ref
          .read(professionalAuthApiProvider)
          .verifyPasswordResetOtp(email, otp);
      if (!mounted) return;
      _stopResendCountdown();
      setState(() {
        _isVerifyingOtp = false;
        _resetToken = result.resetToken;
        _status = ResetOtpStatus.verified;
        _otpMessage = result.message;
        _otpError = '';
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _isVerifyingOtp = false;
        _resetToken = '';
        _status = ResetOtpStatus.failed;
        _otpError = 'OTP is not verified. Please try again.';
        _otpMessage = '';
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim().toLowerCase();

    setState(() {
      _passwordError = '';
      _confirmPasswordError = '';
      _generalError = '';
    });

    if (email.isEmpty ||
        _resetToken.isEmpty ||
        _password.text.isEmpty ||
        _confirmPassword.text.isEmpty) {
      setState(() {
        if (email.isEmpty) {
          _emailError = 'Email is required.';
        }
        if (_resetToken.isEmpty) {
          _otpError = 'Please verify OTP before resetting password.';
        }
        if (_password.text.isEmpty) {
          _passwordError = 'Password is required.';
        }
        if (_confirmPassword.text.isEmpty) {
          _confirmPasswordError = 'Confirm password is required.';
        }
      });
      return;
    }

    if (!_isPasswordStrong) {
      setState(
        () => _passwordError = 'Password does not meet all requirements below.',
      );
      return;
    }

    if (_password.text != _confirmPassword.text) {
      setState(
        () => _confirmPasswordError = 'Confirm password must match Password.',
      );
      return;
    }

    setState(() {
      _isResettingPassword = true;
      _formMessage = 'Resetting password...';
    });

    try {
      final message = await ref
          .read(professionalAuthApiProvider)
          .confirmPasswordReset(
            email,
            _resetToken,
            _password.text,
            _confirmPassword.text,
          );
      if (!mounted) return;
      _stopResendCountdown();
      // The web portal parks this notice in sessionStorage for the login page;
      // a snack bar is the mobile equivalent.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty
                ? 'Password reset successfully. Please login now.'
                : '$message Please login now.',
          ),
        ),
      );
      context.go(Routes.professionalLogin);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isResettingPassword = false;
        _formMessage = '';
        _applyApiErrors(error);
      });
    }
  }

  /// Same field mapping as `applyResetApiErrors()` in the web component.
  void _applyApiErrors(ApiException error) {
    if (error.fieldErrors.isEmpty) {
      _generalError = error.message.isEmpty
          ? 'Please refresh and try again.'
          : error.message;
      return;
    }

    for (final entry in error.fieldErrors.entries) {
      final message = entry.value.isEmpty
          ? 'Please refresh and try again.'
          : entry.value.first;
      switch (entry.key) {
        case 'email':
          _emailError = message;
        case 'reset_token':
          _otpError = message;
        case 'password':
          _passwordError = message;
        case 'confirm_password':
          _confirmPasswordError = message;
        default:
          _generalError = message;
      }
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = _resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown = _resendCountdown > 0 ? _resendCountdown - 1 : 0;
      });
      if (_resendCountdown == 0) {
        timer.cancel();
        _resendTimer = null;
      }
    });
  }

  void _stopResendCountdown() {
    _resendTimer?.cancel();
    _resendTimer = null;
    _resendCountdown = 0;
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showOtpStep =
        _status == ResetOtpStatus.sent ||
        _status == ResetOtpStatus.failed ||
        _status == ResetOtpStatus.verified;
    final showPasswordStep = _status == ResetOtpStatus.verified;
    final busy = _isRequestingOtp || _isVerifyingOtp || _isResettingPassword;

    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
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
                    title: 'Reset your password',
                    subtitle:
                        'Complete email verification before choosing a new '
                        'password.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _RecoverySteps(status: _status),
                  const SizedBox(height: AppSpacing.lg),

                  // --- Step 1: email + send code ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _email,
                          enabled: !busy && _status != ResetOtpStatus.verified,
                          autocorrect: false,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onChanged: _handleEmailChanged,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: OutlinedButton(
                          onPressed: _canSendOtp ? () => _requestOtp() : null,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(88, AppSize.buttonHeightSm),
                          ),
                          child: _isRequestingOtp
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Send code'),
                        ),
                      ),
                    ],
                  ),
                  _HelpText(message: _emailError, isError: true),

                  if (_isEmailMissing) ...[
                    const _HelpText(
                      message:
                          'No professional account found. Try Sign up or Login.',
                      isError: true,
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => context.push(Routes.professionalSignup),
                          child: const Text('Sign up'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => context.go(Routes.professionalLogin),
                          child: const Text('Login'),
                        ),
                      ],
                    ),
                  ] else if (_otpHelpText.isNotEmpty)
                    _HelpText(
                      message: _otpHelpText,
                      isError: _status == ResetOtpStatus.failed,
                      isSuccess: _status == ResetOtpStatus.verified,
                    )
                  else if (_otpMessage.isNotEmpty)
                    _HelpText(
                      message: _otpMessage,
                      isError: _status == ResetOtpStatus.failed,
                    ),

                  if (_debugOtp.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Dev code: $_debugOtp',
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.accent,
                        ),
                      ),
                    ),

                  if (_status == ResetOtpStatus.sent)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: _resendCountdown > 0
                          ? Text(
                              'If not received, resend code enables in '
                              '${_resendCountdown}s.',
                              style: context.text.bodySmall?.copyWith(
                                color: tokens.muted,
                              ),
                            )
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _canResendOtp
                                    ? () => _requestOtp(isResend: true)
                                    : null,
                                child: const Text('Resend code'),
                              ),
                            ),
                    ),

                  // --- Step 2: OTP + verify ---
                  if (showOtpStep) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _otp,
                            enabled:
                                !_isVerifyingOtp &&
                                _status != ResetOtpStatus.verified,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            onChanged: _handleOtpChanged,
                            decoration: const InputDecoration(
                              labelText: 'OTP',
                              hintText: 'Enter 6-digit code',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: OutlinedButton(
                            onPressed: _canVerifyOtp ? _verifyOtp : null,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(
                                88,
                                AppSize.buttonHeightSm,
                              ),
                            ),
                            child: _isVerifyingOtp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _status == ResetOtpStatus.verified
                                        ? 'Verified'
                                        : _status == ResetOtpStatus.failed
                                        ? 'Retry'
                                        : 'Verify',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    _HelpText(message: _otpError, isError: true),
                  ],

                  // --- Step 3: new password ---
                  if (showPasswordStep) ...[
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _password,
                      label: 'New password',
                      enabled: !_isResettingPassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    _PasswordRequirements(password: _password.text),
                    _HelpText(message: _passwordError, isError: true),
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _confirmPassword,
                      label: 'Confirm password',
                      enabled: !_isResettingPassword,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: _canSubmitNewPassword
                          ? _resetPassword
                          : null,
                    ),
                    _HelpText(message: _confirmPasswordError, isError: true),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _canSubmitNewPassword ? _resetPassword : null,
                      child: _isResettingPassword
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Reset password'),
                    ),
                  ],

                  if (_formMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        _formMessage,
                        textAlign: TextAlign.center,
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.muted,
                        ),
                      ),
                    ),
                  FormMessage(message: _generalError),

                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => context.go(Routes.professionalLogin),
                    child: const Text('Remembered it? Back to login'),
                  ),
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

/// Inline helper/error line under a field — the `.field-help` spans in the web
/// template.
class _HelpText extends StatelessWidget {
  const _HelpText({
    required this.message,
    this.isError = false,
    this.isSuccess = false,
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
      child: Text(
        message,
        style: context.text.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

/// The three-step progress row — `.recovery-steps` in the web template.
class _RecoverySteps extends StatelessWidget {
  const _RecoverySteps({required this.status});

  final ResetOtpStatus status;

  @override
  Widget build(BuildContext context) {
    final verified = status == ResetOtpStatus.verified;
    final otpReached =
        status == ResetOtpStatus.sent ||
        status == ResetOtpStatus.failed ||
        verified;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _StepChip(
            index: 1,
            label: 'Email',
            active: true,
            complete: otpReached,
          ),
        ),
        Expanded(
          child: _StepChip(
            index: 2,
            label: 'Verify OTP',
            active: otpReached,
            complete: verified,
          ),
        ),
        Expanded(
          child: _StepChip(
            index: 3,
            label: 'New password',
            active: verified,
            complete: false,
          ),
        ),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.index,
    required this.label,
    required this.active,
    required this.complete,
  });

  final int index;
  final String label;
  final bool active;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final highlighted = active || complete;
    final tint = complete
        ? tokens.success
        : active
        ? context.colors.primary
        : tokens.muted;

    return Column(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlighted
                ? tint.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(color: highlighted ? tint : tokens.border),
          ),
          child: complete
              ? Icon(Icons.check, size: 14, color: tint)
              : Text(
                  '$index',
                  style: context.text.labelSmall?.copyWith(color: tint),
                ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          textAlign: TextAlign.center,
          style: context.text.bodySmall?.copyWith(color: tint),
        ),
      ],
    );
  }
}

/// Live checklist under the new-password field — `app-password-requirements`.
class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements({required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in _passwordRules)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    rule.test(password)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: AppSize.iconRow,
                    color: rule.test(password) ? tokens.success : tokens.muted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      rule.label,
                      style: context.text.bodySmall?.copyWith(
                        color: rule.test(password)
                            ? tokens.success
                            : tokens.muted,
                      ),
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
