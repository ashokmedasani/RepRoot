import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/auth/google_auth_service.dart';
import '../../core/auth/google_button_platform.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/google_signin_button.dart';
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
  bool _googleSubmitting = false;
  String _message = '';

  /// True once the plugin is initialised and we know which flow this platform
  /// supports. Google's rendered button cannot be shown before then.
  bool _googleReady = false;
  bool _googleUsesRenderedButton = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleEvents;

  @override
  void initState() {
    super.initState();
    _prepareGoogle();
  }

  /// Web reports the sign-in through [GoogleAuthService.authEvents] rather
  /// than returning it, because the button is Google's own widget.
  Future<void> _prepareGoogle() async {
    final google = GoogleAuthService.instance;
    if (!google.isConfigured) return;
    try {
      await google.ensureInitialized();
    } catch (_) {
      return; // The button simply stays hidden.
    }
    if (!mounted) return;

    final usesRendered = !google.supportsAuthenticate;
    if (usesRendered) {
      _googleEvents = google.authEvents.listen((event) {
        final idToken = google.idTokenFrom(event);
        if (idToken != null && idToken.isNotEmpty) _exchangeGoogleToken(idToken);
      });
    }
    setState(() {
      _googleReady = true;
      _googleUsesRenderedButton = usesRendered;
    });
  }

  @override
  void dispose() {
    _googleEvents?.cancel();
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
      await _completeLogin(response.token);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _isSubmitting = false;
      });
    }
  }

  /// Same rules as the web portal's routeAfterLogin(): updated legal
  /// documents come first, then profile setup (name + professional code).
  /// Without the setup step a professional can reach the dashboard with no
  /// professional code, and their clients could never log in; without the
  /// legal step every other endpoint 403s after a version bump. Shared by
  /// both the password and Google sign-in flows.
  Future<void> _completeLogin(String token) async {
    final api = ref.read(professionalAuthApiProvider);
    await api.storeToken(token);

    var destination = Routes.professionalDashboard;
    try {
      final status = await api.getProfileStatus();
      destination = status.legalAcceptanceRequired
          ? Routes.professionalLegalConsent
          : status.profileSetupCompleted
              ? Routes.professionalDashboard
              : Routes.professionalProfileSetup;
    } catch (_) {
      // Don't strand a signed-in professional on the login screen if this
      // secondary check fails — the dashboard re-checks anyway.
    }

    if (!mounted) return;
    context.go(destination);
  }

  /// Native flow: our button, `authenticate()`, then the exchange.
  Future<void> _loginWithGoogle() async {
    setState(() {
      _googleSubmitting = true;
      _message = '';
    });

    String idToken;
    try {
      idToken = await GoogleAuthService.instance.signInAndGetIdToken();
    } on GoogleSignInException catch (error) {
      if (!mounted) return;
      setState(() {
        _googleSubmitting = false;
        // A dismissed prompt isn't an error worth surfacing — matches the
        // web button, which only shows a message for a blocked/failed popup.
        _message = error.code == GoogleSignInExceptionCode.canceled
            ? ''
            : 'Google sign-in popup was blocked or dismissed. Please try again, or use email below.';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _googleSubmitting = false;
        _message = 'Google sign-in could not be loaded. Please try again later.';
      });
      return;
    }

    await _exchangeGoogleToken(idToken);
  }

  /// Shared tail of both flows: trade Google's ID token for our own session.
  Future<void> _exchangeGoogleToken(String idToken) async {
    if (!mounted) return;
    setState(() {
      _googleSubmitting = true;
      _message = 'Verifying with Google...';
    });

    final api = ref.read(professionalAuthApiProvider);
    try {
      final response = await api.googleAuth(idToken);
      await _completeLogin(response.token);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _googleSubmitting = false;
        _message = error.message.isEmpty
            ? 'Google sign-in failed. Please try again.'
            : error.message;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _googleSubmitting = false);
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
                          : () =>
                                context.push(Routes.professionalForgotPassword),
                      child: const Text('Forgot password?'),
                    ),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => context.push(Routes.professionalSignup),
                      child: const Text('New professional? Create an account'),
                    ),
                    if (GoogleAuthService.instance.isConfigured &&
                        _googleReady) ...[
                      const AuthOrDivider(),
                      // Web gets Google's own widget; GIS refuses to sign in
                      // from any other button.
                      if (_googleUsesRenderedButton)
                        renderGoogleSignInButton()
                      else
                        GoogleSignInButton(
                          variant: GoogleButtonVariant.login,
                          enabled: !_isSubmitting,
                          busy: _googleSubmitting,
                          onPressed: _loginWithGoogle,
                        ),
                    ],
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
