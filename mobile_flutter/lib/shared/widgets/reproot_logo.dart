import 'package:flutter/material.dart';

/// Theme-aware RepRoot mark used inside the application.
///
/// The platform launcher icon intentionally remains unchanged. Dark mode uses
/// a dedicated high-contrast asset so the light logo's white square does not
/// appear against dark application surfaces.
class RepRootLogo extends StatelessWidget {
  const RepRootLogo({super.key, this.size = 56, this.fit = BoxFit.contain});

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final asset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/icon/icon_dark.png'
        : 'assets/icon/icon.png';

    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: fit,
      semanticLabel: 'RepRoot',
    );
  }
}
