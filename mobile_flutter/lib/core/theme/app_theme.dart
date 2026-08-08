import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Material 3 themes built from the RepRoot tokens.
///
/// Font: Roboto, Android's system font. Chosen over the web/Ionic brand font
/// (Manrope) so the app feels native on Android and needs no font download —
/// this is a deliberate divergence from the other two apps.
///
/// Type scale is much tighter than the Ionic app by design (see AppSize docs):
/// display 22 / title 16 / body 13.5 / label 11.5 / caption 10.5.
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
    final textTheme = _textTheme(scheme.onSurface, tokens.muted, brightness);

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
      // Borderless: the card's own shadow separates it from the page. Adding a
      // hairline on top of that reads as belt-and-braces at this radius.
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
      ),
      // Pills. At 46pt a capsule reads friendly where a rounded rectangle
      // reads like a form control — this is the single biggest tell of the
      // theme, so it applies to every button variant for consistency.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          textStyle: textTheme.labelLarge,
          iconSize: AppSize.iconRow,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSize.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          // 1.2 rather than 1.4: against a pill the heavier stroke started to
          // look like a drawn outline instead of a quiet secondary action.
          side: BorderSide(color: scheme.primary, width: 1.2),
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
      // Fields are tinted and borderless at rest — the fill is what says
      // "type here", so a line around it as well is redundant. The border only
      // appears on focus and error, which makes those states unmissable
      // instead of being a subtle change of an already-present line.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceSoft,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.md + 2,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: scheme.primary),
        border: _fieldBorder(Colors.transparent),
        enabledBorder: _fieldBorder(Colors.transparent),
        focusedBorder: _fieldBorder(scheme.primary, width: 1.6),
        errorBorder: _fieldBorder(scheme.error, width: 1.2),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 1.6),
        errorStyle: textTheme.labelMedium?.copyWith(color: scheme.error),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.primarySoft,
        indicatorShape: const RoundedRectangleBorder(
          borderRadius: AppRadius.pillAll,
        ),
        elevation: 0,
        height: 64,
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
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
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
          // Height and padding live here so every tab bar in the app is the
          // same size. Pages used to set these themselves and had drifted
          // between labelSmall/labelMedium and compact/standard density, which
          // is why two tab bars on adjacent screens looked like different
          // controls. Call sites should not override this.
          minimumSize: const WidgetStatePropertyAll(
            Size(0, AppSize.buttonHeightSm),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: tokens.border, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceSoft,
        // Material selects chips with secondaryContainer, which is the teal
        // accent here — a selected chip must read as brand blue, same as the
        // segmented buttons.
        selectedColor: tokens.primarySoft,
        checkmarkColor: scheme.primary,
        // Chips sit on the tinted fill alone — the border was competing with
        // the fill for the same job and made a row of chips look caged.
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium,
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(
          color: tokens.primaryStrong,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.muted,
        textColor: scheme.onSurface,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: tokens.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.card),
        minVerticalPadding: AppSpacing.md,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.tileAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.surface),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.tileAll),
        insetPadding: const EdgeInsets.all(AppSpacing.screen),
        elevation: 0,
      ),
      // Sheets and dialogs take the largest radius in the system — they're the
      // biggest surfaces, and the extra roundness is what makes them read as
      // floating panels rather than a second page.
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetAll),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: tokens.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
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
      borderRadius: AppRadius.controlAll,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static TextTheme _textTheme(Color onSurface, Color muted, Brightness brightness) {
    // Roboto comes from Typography's Mountain View faces — Android's system
    // font, so nothing is downloaded at runtime.
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    // Two moves carry the "considered" feel, and they pull in opposite
    // directions on purpose:
    //   * Headings and numbers get *negative* tracking. Large type set at
    //     default spacing looks loose and amateurish; pulling it in makes it
    //     read as typeset rather than merely enlarged.
    //   * Small labels get *positive* tracking and drop a weight. Tracked-out
    //     11pt is legible and calm; tight bold 11pt is shouty.
    // Weights also come down across the board (w800 -> w700, w600 -> w500):
    // heavy weights fought the soft shapes and low-contrast shadows.
    return base
        .copyWith(
          // ---- The scale ----
          // Seven steps, each a deliberate jump, nothing in between. Every
          // screen draws from this and only this; a page that invents its own
          // size is what made the app feel like several different apps
          // stitched together.
          //
          //   20  displaySmall  the one big number on a card (KPI value)
          //   17  headlineSmall page title
          //   15  titleLarge    section header, app bar
          //   14  titleMedium   card title
          //   13  titleSmall    row title
          //   13  body          everything you read
          //   11  bodySmall     captions, helper text
          //
          // The top end came down from 24: a KPI value 1.7x the body text
          // still reads as the loudest thing on screen, where 24 next to a
          // 12pt tab label read as two unrelated designs. Body came down from
          // 14 to 13 so lower sections stop out-shouting the header.
          displaySmall: base.displaySmall?.copyWith(
              fontSize: 20, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4),
          headlineSmall: base.headlineSmall?.copyWith(
              fontSize: 17, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.3),
          titleLarge: base.titleLarge?.copyWith(
              fontSize: 15, fontWeight: FontWeight.w600, height: 1.3, letterSpacing: -0.1),
          titleMedium: base.titleMedium?.copyWith(
              fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
          titleSmall: base.titleSmall?.copyWith(
              fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
          bodyLarge: base.bodyLarge?.copyWith(
              fontSize: 13, fontWeight: FontWeight.w500, height: 1.45),
          bodyMedium: base.bodyMedium?.copyWith(
              fontSize: 13, fontWeight: FontWeight.w400, height: 1.5),
          bodySmall: base.bodySmall?.copyWith(
              fontSize: 11, fontWeight: FontWeight.w400, height: 1.45, color: muted),
          labelLarge: base.labelLarge?.copyWith(
              fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.1),
          labelMedium: base.labelMedium?.copyWith(
              fontSize: 12, fontWeight: FontWeight.w500, height: 1.2, letterSpacing: 0.2),
          labelSmall: base.labelSmall?.copyWith(
              fontSize: 11, fontWeight: FontWeight.w500, height: 1.2, letterSpacing: 0.4),
        )
        .apply(
          fontFamily: 'Roboto',
          bodyColor: onSurface,
          displayColor: onSurface,
        );
  }
}
