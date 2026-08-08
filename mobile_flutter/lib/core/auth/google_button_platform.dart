/// Platform switch for how the Google button is drawn.
///
/// On Android and iOS we draw our own button and call
/// `GoogleSignIn.instance.authenticate()`. On the web that is impossible:
/// `google_sign_in_web` returns false from `supportsAuthenticate()` and
/// **throws** if `authenticate()` is called, because the Google Identity
/// Services SDK only permits sign-in through UI that Google itself renders.
/// The web path therefore has to show Google's own widget and pick the result
/// up from `authenticationEvents`.
///
/// `dart.library.js_interop` is the web-only condition; anything else gets the
/// stub, which is never displayed.
export 'google_button_stub.dart'
    if (dart.library.js_interop) 'google_button_web.dart';
