import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;

/// Google Identity Services' own sign-in button.
///
/// The GIS SDK will not accept a click from arbitrary UI, so on the web this
/// widget replaces our styled [GoogleSignInButton]. The result does not come
/// back from this call — it arrives on
/// `GoogleSignIn.instance.authenticationEvents`, which the login and signup
/// pages subscribe to.
Widget renderGoogleSignInButton() => web_only.renderButton();
