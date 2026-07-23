import 'package:flutter/material.dart';

/// RepRoot design tokens. Colors are ported 1:1 from
/// mobile/src/theme/variables.scss so the Flutter app matches the web + Ionic
/// brand exactly — do not change them here.
///
/// Sizing is deliberately much tighter than the Ionic app, in two passes:
///   1. an initial step down (button 52 -> 46) because the Ionic UI read large;
///   2. a second, requested pass making everything noticeably smaller
///      (button 46 -> 42, body 14.5 -> 13.5, screen padding 16 -> 12).
/// Visible sizes shrink; invisible tap targets stay at 44px — see
/// AppSize.touchTarget.
class AppColors {
  const AppColors._();

  // Light palette — :root in variables.scss
  static const lightBg = Color(0xFFF4F7FB);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSoft = Color(0xFFEDF3F9);
  static const lightText = Color(0xFF14213D);
  static const lightMuted = Color(0xFF64748B);
  static const lightBorder = Color(0xFFDBE5EF);
  static const lightPrimary = Color(0xFF2563EB);
  static const lightPrimaryStrong = Color(0xFF1D4ED8);
  static const lightPrimarySoft = Color(0xFFE8F0FF);
  static const lightAccent = Color(0xFF0F9F9D);
  static const lightSuccess = Color(0xFF159567);

  // Dark palette — @media (prefers-color-scheme: dark) in variables.scss
  static const darkBg = Color(0xFF0E1624);
  static const darkSurface = Color(0xFF172235);
  static const darkSurfaceSoft = Color(0xFF202E43);
  static const darkText = Color(0xFFF4F7FB);
  static const darkMuted = Color(0xFFA9B7C8);
  static const darkBorder = Color(0xFF304158);
  static const darkPrimary = Color(0xFF72A2FF);
  static const darkPrimaryStrong = Color(0xFFA7C4FF);
  static const darkPrimarySoft = Color(0xFF203B68);
  static const darkAccent = Color(0xFF62D4CE);
  static const darkSuccess = Color(0xFF67D49B);

  // Shared
  static const danger = Color(0xFFD92D20);
  static const dangerDark = Color(0xFFBF281C);
  static const onPrimary = Color(0xFFFFFFFF);
}

/// 4-pt spacing grid.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double screen = 12;
  static const double card = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}

/// Radii — variables.scss --app-radius-*, converted from rem at 16px root.
class AppRadius {
  const AppRadius._();

  static const double sm = 10; // 0.625rem
  static const double md = 12; // 0.75rem
  static const double lg = 16; // 1rem
  static const double xl = 20; // 1.25rem

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Control and icon sizing — the tightened scale.
class AppSize {
  const AppSize._();

  static const double buttonHeight = 42; // Ionic large was ~52; first pass 46
  static const double buttonHeightSm = 34;
  static const double fieldHeight = 44;
  static const double iconRow = 18;
  static const double iconButton = 20;
  static const double iconNav = 22;
  static const double rowHeight = 52;

  /// The one size that does NOT shrink. Icon glyphs get smaller, but their
  /// invisible hit area stays 44px — below that, taps start missing. Costs
  /// nothing visually since the padding is transparent.
  static const double touchTarget = 44;
}

/// Tokens Material's ColorScheme has no slot for. Read via `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surfaceSoft,
    required this.muted,
    required this.border,
    required this.primarySoft,
    required this.primaryStrong,
    required this.accent,
    required this.success,
    required this.shadowSm,
    required this.shadowMd,
  });

  final Color surfaceSoft;
  final Color muted;
  final Color border;
  final Color primarySoft;
  final Color primaryStrong;
  final Color accent;
  final Color success;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;

  static const light = AppTokens(
    surfaceSoft: AppColors.lightSurfaceSoft,
    muted: AppColors.lightMuted,
    border: AppColors.lightBorder,
    primarySoft: AppColors.lightPrimarySoft,
    primaryStrong: AppColors.lightPrimaryStrong,
    accent: AppColors.lightAccent,
    success: AppColors.lightSuccess,
    shadowSm: [
      BoxShadow(
        color: Color(0x0F14213D),
        blurRadius: 16,
        offset: Offset(0, 6),
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x1714213D),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  static const dark = AppTokens(
    surfaceSoft: AppColors.darkSurfaceSoft,
    muted: AppColors.darkMuted,
    border: AppColors.darkBorder,
    primarySoft: AppColors.darkPrimarySoft,
    primaryStrong: AppColors.darkPrimaryStrong,
    accent: AppColors.darkAccent,
    success: AppColors.darkSuccess,
    shadowSm: [
      BoxShadow(
        color: Color(0x2E000000),
        blurRadius: 16,
        offset: Offset(0, 6),
      ),
    ],
    shadowMd: [
      BoxShadow(
        color: Color(0x3D000000),
        blurRadius: 32,
        offset: Offset(0, 14),
      ),
    ],
  );

  @override
  AppTokens copyWith({
    Color? surfaceSoft,
    Color? muted,
    Color? border,
    Color? primarySoft,
    Color? primaryStrong,
    Color? accent,
    Color? success,
    List<BoxShadow>? shadowSm,
    List<BoxShadow>? shadowMd,
  }) {
    return AppTokens(
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      shadowSm: shadowSm ?? this.shadowSm,
      shadowMd: shadowMd ?? this.shadowMd,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      primaryStrong: Color.lerp(primaryStrong, other.primaryStrong, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      shadowSm: BoxShadow.lerpList(shadowSm, other.shadowSm, t)!,
      shadowMd: BoxShadow.lerpList(shadowMd, other.shadowMd, t)!,
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>()!;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

/// Each tracking template carries its own professional-picked accent
/// ("#rrggbb", see professional_templates_page.dart's swatch picker) — reused here
/// rather than inventing new colors for template rows/lists.
Color parseAccentColor(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6) return AppColors.lightPrimary;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? AppColors.lightPrimary : Color(0xFF000000 | value);
}
