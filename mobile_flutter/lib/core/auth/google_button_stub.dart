import 'package:flutter/widgets.dart';

/// Non-web stub. Native platforms support `authenticate()`, so they never ask
/// for Google's rendered widget — this exists only to satisfy the conditional
/// export in `google_button_platform.dart`.
Widget renderGoogleSignInButton({
  bool forSignup = false,
  double preferredWidth = 400,
}) => const SizedBox.shrink();
