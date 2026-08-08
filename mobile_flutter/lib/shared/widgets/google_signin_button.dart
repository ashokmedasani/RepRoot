import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Which of the web's three button labels to show — mirrors
/// GoogleSigninButtonComponent.variant in the Angular frontend.
enum GoogleButtonVariant { login, signup, continueFlow }

/// Google sign-in trigger button. Rendering only — callers decide whether to
/// show it at all via `GoogleAuthService.instance.isConfigured`, the same gate
/// the web button uses (`isAvailable`/`unavailable`) when no client ID is
/// configured for the build.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.variant,
    required this.onPressed,
    this.enabled = true,
    this.busy = false,
  });

  final GoogleButtonVariant variant;
  final VoidCallback onPressed;
  final bool enabled;
  final bool busy;

  String get _label {
    switch (variant) {
      case GoogleButtonVariant.signup:
        return 'Sign up with Google';
      case GoogleButtonVariant.login:
        return 'Sign in with Google';
      case GoogleButtonVariant.continueFlow:
        return 'Continue with Google';
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled && !busy ? onPressed : null,
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const _GoogleGlyph(),
      label: Text(_label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSize.buttonHeightSm),
      ),
    );
  }
}

/// No brand SVG bundled — a plain multicolor "G" avoids pulling in a new
/// asset/package for a single glyph while still reading as "Google" next to
/// the button label.
class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      height: 16,
      child: Center(
        child: Text(
          'G',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}

/// "or" divider between the password form and the Google button — the
/// `.auth-divider` element in the web templates.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Divider(color: tokens.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              'or',
              style: context.text.bodySmall?.copyWith(color: tokens.muted),
            ),
          ),
          Expanded(child: Divider(color: tokens.border)),
        ],
      ),
    );
  }
}
