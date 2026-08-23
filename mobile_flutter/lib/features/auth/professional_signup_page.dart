import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/auth/google_auth_service.dart';
import '../../core/auth/google_button_platform.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/legal/legal_documents.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/google_signin_button.dart';
import '../../shared/widgets/password_field.dart';
import '../professional/professional_format.dart';

enum UsernameStatus { idle, checking, available, taken }

enum EmailStatus { idle, sending, sent, verifying, verified }

/// Replica of mobile/src/app/pages/professional/signup/professional-signup.page.ts.
/// Username check -> email OTP -> verify -> create account.
class ProfessionalSignupPage extends ConsumerStatefulWidget {
  const ProfessionalSignupPage({super.key});

  @override
  ConsumerState<ProfessionalSignupPage> createState() =>
      _ProfessionalSignupPageState();
}

class _ProfessionalSignupPageState
    extends ConsumerState<ProfessionalSignupPage> {
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
  String _legalVersion = '';
  String _legalEffectiveDate = '';
  bool _googleSubmitting = false;

  /// See the login page: the web cannot use `authenticate()`, so it shows
  /// Google's own button and receives the result on a stream instead.
  bool _googleReady = false;
  bool _googleUsesRenderedButton = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleEvents;

  @override
  void initState() {
    super.initState();
    _loadLegalConfiguration();
    _prepareGoogle();
  }

  Future<void> _prepareGoogle() async {
    final google = GoogleAuthService.instance;
    if (!google.isConfigured) return;
    try {
      await google.ensureInitialized();
    } catch (error, stackTrace) {
      debugPrint(
        'Google authentication initialization failed '
        '(${error.runtimeType})\n$stackTrace',
      );
      return; // The button simply stays hidden.
    }
    if (!mounted) return;

    final usesRendered = !google.supportsAuthenticate;
    if (usesRendered) {
      _googleEvents = google.authEvents.listen((event) {
        final idToken = google.idTokenFrom(event);
        // Same legal gate as the native path — consent is still collected
        // before the account is created.
        if (idToken != null && idToken.isNotEmpty) _reviewThenSignup(idToken);
      });
    }
    setState(() {
      _googleReady = true;
      _googleUsesRenderedButton = usesRendered;
    });
  }

  /// Public endpoint — the version banner the web signup shows above the
  /// consent checkbox. A failure just hides the banner.
  Future<void> _loadLegalConfiguration() async {
    try {
      final configuration = await ref
          .read(professionalAuthApiProvider)
          .getLegalConfiguration();
      if (!mounted) return;
      setState(() {
        _legalVersion = configuration.professionalVersion;
        _legalEffectiveDate = configuration.effectiveDate;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Signup legal configuration load failed '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
  }

  @override
  void dispose() {
    _googleEvents?.cancel();
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
      final result = await ref
          .read(professionalAuthApiProvider)
          .checkUsername(username);
      if (!mounted) return;
      setState(() {
        _usernameStatus = result.available
            ? UsernameStatus.available
            : UsernameStatus.taken;
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
      final result = await ref
          .read(professionalAuthApiProvider)
          .requestEmailOtp(email);
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
      setState(
        () => _message =
            'Password must be at least 8 characters with one special character.',
      );
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
          // ProfessionalSignupSerializer requires both and rejects false — the
          // button is disabled until the box is ticked, so this is always true
          // by the time we get here.
          acceptTerms: _agreed,
          acceptPrivacy: _agreed,
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

  /// Starts the Google flow: authenticate with Google first, then — matching
  /// the web signup's two-step order — gate account creation behind the
  /// legal review sheet before ever calling the backend.
  Future<void> _startGoogleSignup() async {
    setState(() => _message = '');

    String idToken;
    try {
      idToken = await GoogleAuthService.instance.signInAndGetIdToken();
    } on GoogleSignInException catch (error) {
      if (!mounted) return;
      if (error.code != GoogleSignInExceptionCode.canceled) {
        setState(
          () => _message =
              'Google sign-in popup was blocked or dismissed. Please try again, or use email below.',
        );
      }
      return;
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _message =
            'Google sign-in could not be loaded. Please try again later.',
      );
      return;
    }

    await _reviewThenSignup(idToken);
  }

  /// Legal review, then account creation. Shared by both flows so the web's
  /// rendered button cannot bypass the consent step.
  Future<void> _reviewThenSignup(String idToken) async {
    if (!mounted) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GoogleSignupReviewSheet(
        legalVersion: _legalVersion,
        legalEffectiveDate: _legalEffectiveDate,
      ),
    );
    if (accepted != true || !mounted) return;
    await _completeGoogleSignup(idToken);
  }

  /// Replica of ProfessionalSignupComponent.confirmGoogleSignup — sends
  /// accept_terms/accept_privacy=true (the sheet already gated on that
  /// consent), then branches the same way the web does: an existing account
  /// matched by email is a login, not a signup, so it's surfaced as an error
  /// rather than silently signing the user in from this screen.
  Future<void> _completeGoogleSignup(String idToken) async {
    setState(() {
      _googleSubmitting = true;
      _message = '';
    });

    final api = ref.read(professionalAuthApiProvider);
    try {
      final response = await api.googleAuth(idToken, acceptLegalTerms: true);
      if (!response.isNewAccount) {
        await api.clearSession();
        if (!mounted) return;
        setState(() {
          _googleSubmitting = false;
          _message =
              'An account already exists for this Google email. Please sign in.';
        });
        return;
      }
      await api.storeToken(response.token);
      if (!mounted) return;
      // New accounts always need profile setup (name + professional code)
      // before the dashboard, matching the web portal's first-login step.
      context.go(
        response.professional?.profileSetupCompleted == true
            ? Routes.professionalDashboard
            : Routes.professionalProfileSetup,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _googleSubmitting = false;
        _message = error.message.isEmpty
            ? 'Google sign-up failed. Please try again.'
            : error.message;
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
                          onPressed: busy || _isSubmitting
                              ? null
                              : _verifyUsername,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(88, AppSize.buttonHeightSm),
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                          enabled:
                              !_isSubmitting &&
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
                          onPressed:
                              _emailStatus == EmailStatus.sending ||
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _emailStatus == EmailStatus.sent
                                      ? 'Resend'
                                      : 'Send code',
                                ),
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
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.accent,
                        ),
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
                              minimumSize: const Size(
                                88,
                                AppSize.buttonHeightSm,
                              ),
                            ),
                            child: _emailStatus == EmailStatus.verifying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
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
                  // The web signup shows the effective date, the version, and
                  // links to both documents above the checkbox; ticking a box
                  // that links to nothing is not consent.
                  if (_legalVersion.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'Effective ${_legalEffectiveDate.isEmpty ? '—' : longDate(_legalEffectiveDate)} '
                        '· Version $_legalVersion',
                        style: context.text.bodySmall?.copyWith(
                          color: context.tokens.muted,
                        ),
                      ),
                    ),
                  const LegalDocumentLinks(
                    audience: LegalAudience.professional,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LegalConsentCheckbox(
                    value: _agreed,
                    enabled: !_isSubmitting,
                    label: LegalAudience.professional.consentLabel,
                    onChanged: (value) => setState(() => _agreed = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _isSubmitting || !_agreed
                        ? null
                        : _createAccount,
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
                  if (GoogleAuthService.instance.isConfigured &&
                      _googleReady) ...[
                    const AuthOrDivider(),
                    if (_googleUsesRenderedButton)
                      Center(child: renderGoogleSignInButton(forSignup: true))
                    else
                      GoogleSignInButton(
                        variant: GoogleButtonVariant.signup,
                        enabled: !_isSubmitting,
                        busy: _googleSubmitting,
                        onPressed: _startGoogleSignup,
                      ),
                  ],
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

/// Legal review gate for Google signup — replica of the `showLegalReview`
/// dialog in professional-signup.component.html. The web keeps this modal
/// open through the network call; here it's a consent-only step that pops
/// `true` once accepted, and the caller performs the actual account-creation
/// call (and shows its own busy/error state on the page) after it closes.
class _GoogleSignupReviewSheet extends StatefulWidget {
  const _GoogleSignupReviewSheet({
    required this.legalVersion,
    required this.legalEffectiveDate,
  });

  final String legalVersion;
  final String legalEffectiveDate;

  @override
  State<_GoogleSignupReviewSheet> createState() =>
      _GoogleSignupReviewSheetState();
}

class _GoogleSignupReviewSheetState extends State<_GoogleSignupReviewSheet> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screen,
          right: AppSpacing.screen,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Account creation · Step 2 of 2',
                style: context.text.bodySmall?.copyWith(color: tokens.muted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Review how RepRoot works',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Before we create your professional account, review and accept the '
                'documents that explain your responsibilities and how your data is '
                'handled.',
                style: context.text.bodyMedium,
              ),
              if (widget.legalVersion.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Effective ${widget.legalEffectiveDate.isEmpty ? '—' : longDate(widget.legalEffectiveDate)} '
                  '· Version ${widget.legalVersion}',
                  style: context.text.bodySmall?.copyWith(color: tokens.muted),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const LegalDocumentLinks(audience: LegalAudience.professional),
              const SizedBox(height: AppSpacing.sm),
              LegalConsentCheckbox(
                value: _accepted,
                label: LegalAudience.professional.consentLabel,
                onChanged: (value) => setState(() => _accepted = value),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _accepted
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      child: const Text('Accept and Create Account'),
                    ),
                  ),
                ],
              ),
            ],
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
      child: Text(
        message,
        style: context.text.bodySmall?.copyWith(color: color),
      ),
    );
  }
}
