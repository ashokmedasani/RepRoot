import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

/// Google Identity Services' own sign-in button.
///
/// The GIS SDK will not accept a click from arbitrary UI, so on the web this
/// widget replaces our styled [GoogleSignInButton]. The result does not come
/// back from this call — it arrives on
/// `GoogleSignIn.instance.authenticationEvents`, which the login and signup
/// pages subscribe to.
Widget renderGoogleSignInButton({
  bool forSignup = false,
  double preferredWidth = 400,
}) => LayoutBuilder(
  builder: (context, constraints) {
    final availableWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : preferredWidth;
    final buttonWidth = availableWidth.clamp(1.0, preferredWidth).toDouble();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return web_only.renderButton(
      configuration: web_only.GSIButtonConfiguration(
        type: web_only.GSIButtonType.standard,
        theme: isDark
            ? web_only.GSIButtonTheme.filledBlack
            : web_only.GSIButtonTheme.outline,
        size: web_only.GSIButtonSize.large,
        text: forSignup
            ? web_only.GSIButtonText.signupWith
            : web_only.GSIButtonText.signinWith,
        shape: web_only.GSIButtonShape.pill,
        logoAlignment: web_only.GSIButtonLogoAlignment.left,
        minimumWidth: buttonWidth,
      ),
    );
  },
);
