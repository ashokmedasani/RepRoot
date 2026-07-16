import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

/// Material 3 themes built from the CoachFlow tokens.
///
/// Type scale is tighter than the Ionic app by design (see AppColors docs):
/// display 24 / title 17 / body 14.5 / label 12.5 / caption 11, in Manrope.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        tokens: AppTokens.light,
        scheme: const ColorScheme.light(
          primary: AppColors.lightPrimary,
          onPrimary: AppColors.onPrimary,
          primaryContainer: AppColors.lightPrimarySoft,
          onPrimaryContainer: AppColors.lightPrimaryStrong,
          secondary: AppColors.lightAccent,
          onSecondary: AppColors.onPrimary,
          tertiary: AppColors.lightSuccess,
          onTertiary: AppColors.onPrimary,
          error: AppColors.danger,
          onError: AppColors.onPrimary,
          surface: AppColors.lightSurface,
          onSurface: AppColors.lightText,
          surfaceContainerLowest: AppColors.lightSurface,
          surfaceContainerLow: AppColors.lightBg,
          surfaceContainer: AppColors.lightSurfaceSoft,
          onSurfaceVariant: AppColors.lightMuted,
          outline: AppColors.lightBorder,
          outlineVariant: AppColors.lightBorder,
        ),
        scaffoldBg: AppColors.lightBg,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        tokens: AppTokens.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.darkPrimary,
          onPrimary: AppColors.darkBg,
          primaryContainer: AppColors.darkPrimarySoft,
          onPrimaryContainer: AppColors.darkPrimaryStrong,
          secondary: AppColors.darkAccent,
          onSecondary: AppColors.darkBg,
          tertiary: AppColors.darkSuccess,
          onTertiary: AppColors.darkBg,
          error: AppColors.danger,
          onError: AppColors.onPrimary,
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkText,
          surfaceContainerLowest: AppColors.darkBg,
          surfaceContainerLow: AppColors.darkBg,
          surfaceContainer: AppColors.darkSurfaceSoft,
          onSurfaceVariant: AppColors.darkMuted,
          outline: AppColors.darkBorder,
          outlineVariant: AppColors.darkBorder,
        ),
        scaffoldBg: AppColors.darkBg,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppTokens tokens,
    required ColorScheme scheme,
    required Color scaffoldBg,
  }) {
    final textTheme = _textTheme(scheme.onSurface, tokens.muted);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      extensions: [tokens],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface, size: AppSize.iconNav),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: tokens.border),
        ),
      ),
      // Filled primary button — 46px tall, a step down from Ionic's large button.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          textStyle: textTheme.labelLarge,
          iconSize: AppSize.iconRow,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          side: BorderSide(color: scheme.primary, width: 1.4),
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          iconSize: AppSize.iconRow,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppSize.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
          iconSize: AppSize.iconRow,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSize.touchTarget),
          iconSize: AppSize.iconButton,
          foregroundColor: scheme.onSurface,
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: AppSize.iconRow),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.primary),
        border: _fieldBorder(tokens.border),
        enabledBorder: _fieldBorder(tokens.border),
        focusedBorder: _fieldBorder(scheme.primary, width: 1.6),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 1.6),
        errorStyle: textTheme.labelMedium?.copyWith(color: scheme.error),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.primarySoft,
        elevation: 0,
        height: 62,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: AppSize.iconNav,
            color: states.contains(WidgetState.selected) ? scheme.primary : tokens.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected) ? scheme.primary : tokens.muted,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      // Material defaults a selected segment to secondaryContainer, which is
      // the teal accent here — segments must read as brand blue.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : tokens.muted,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: tokens.border)),
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.smAll),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceSoft,
        side: BorderSide(color: tokens.border),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.muted,
        textColor: scheme.onSurface,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
        minVerticalPadding: AppSpacing.md,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.surface),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.smAll),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: tokens.surfaceSoft,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: AppRadius.smAll,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(Color onSurface, Color muted) {
    final base = GoogleFonts.manropeTextTheme();
    return base
        .copyWith(
          // display 24 — page hero / brand
          displaySmall: base.displaySmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2),
          headlineSmall: base.headlineSmall?.copyWith(fontSize: 20, fontWeight: FontWeight.w800, height: 1.25),
          // title 17 — app bar, card headers
          titleLarge: base.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3),
          titleMedium: base.titleMedium?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.3),
          titleSmall: base.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
          // body 14.5
          bodyLarge: base.bodyLarge?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.4),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.45),
          // caption 11
          bodySmall: base.bodySmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, height: 1.4, color: muted),
          // label 12.5
          labelLarge: base.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w700, height: 1.2),
          labelMedium: base.labelMedium?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2),
          labelSmall: base.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, height: 1.2),
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);
  }
}
