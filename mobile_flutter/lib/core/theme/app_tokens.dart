import 'package:flutter/material.dart';

/// RepRoot design tokens. Colors are ported 1:1 from
/// mobile/src/theme/variables.scss so the Flutter app matches the web + Ionic
/// brand exactly — do not change them here.
///
/// ## "Soft tinted" theme
///
/// The palette above is fixed; everything below it — radius, spacing, weight,
/// elevation — is the theme. Its rules:
///
///   * **No borders on cards.** Separation comes from a soft shadow (for white
///     surfaces) or a colour wash (for tinted ones). A hairline *and* a shadow
///     on the same edge reads as belt-and-braces; pick one. [AppTokens.border]
///     survives for the places that still genuinely need a line — inputs,
///     dividers, table rules.
///   * **Two kinds of surface, and they mean different things.** White +
///     shadow = a thing you can act on (a card, a row, a sheet). Tinted, flat,
///     shadowless = a thing you read (a KPI tile, a callout, a summary band).
///     Keeping that split is most of what makes it feel designed.
///   * **Shadows are tinted with the brand ink** (#14213D), never black — a
///     black shadow over the blue-grey page reads as grime. Two layers: a
///     tight contact shadow to seat the card, a wide diffuse one for air.
///   * **Corners scale with the surface.** 24 on a full-width card is elegant;
///     the same 24 on a 78pt KPI tile turns it into a lozenge. Hence
///     [AppRadius.tile] and [AppRadius.control] — pick by width, not by habit.
///   * **Buttons are pills.** At 46pt tall a capsule reads friendly where a
///     14pt-radius rectangle reads like a form control.
///
/// An earlier revision shrank everything for density. This reverses that:
/// padding, touch targets and line-height all grow back. Less content per
/// screen, more calm — the intended trade, not an oversight.
class AppColors {
  const AppColors._();

  // Light palette — :root in variables.scss
  // Exact web values (--app-bg / --app-surface-soft / --app-border) so the
  // two products read as one. The differences were small but they were
  // differences, and they compounded across every screen.
  static const lightBg = Color(0xFFF8FAFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceSoft = Color(0xFFEEF4FD);
  static const lightText = Color(0xFF14213D);
  static const lightMuted = Color(0xFF64748B);
  static const lightBorder = Color(0xFFDBE4F3);
  static const lightPrimary = Color(0xFF2563EB);
  static const lightPrimaryStrong = Color(0xFF1D4ED8);
  static const lightPrimarySoft = Color(0xFFE8F0FF);
  static const lightAccent = Color(0xFF0F9F9D);
  static const lightSuccess = Color(0xFF159567);

  /// Warning family, matching the web's --app-warning-* triplet. Used for the
  /// private-notes card and for anything on hold (plan-locked rows). Mobile
  /// previously had no warning colour at all and borrowed the teal accent,
  /// which read as decoration rather than as caution.
  static const lightWarningSoft = Color(0xFFFFF8E6);
  static const lightWarningBorder = Color(0xFFF3DFA8);
  static const lightWarningStrong = Color(0xFFB54708);

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
  static const darkWarningSoft = Color(0xFF2D2613);
  static const darkWarningBorder = Color(0xFF4D3F18);
  static const darkWarningStrong = Color(0xFFF5B544);

  // Shared
  static const danger = Color(0xFFD92D20);
  static const dangerDark = Color(0xFFBF281C);
  static const onPrimary = Color(0xFFFFFFFF);
}

/// 4-pt spacing grid, opened up for the soft-tinted theme.
///
/// [screen] and [card] carry the look: 14pt page gutters and 16pt card
/// interiors. The small end (xs/sm) stays tight — gaps *inside* a control,
/// icon to label or value to caption, shouldn't grow just because the page did.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double screen = 14;
  static const double card = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double xxl = 36;

  /// Vertical gap between sibling cards. Has to clear the shadow's blur or the
  /// diffuse layer of one card bleeds onto the next and they look smudged
  /// together rather than stacked.
  static const double stack = 10;
}

/// Radii for the soft-tinted theme.
///
/// Radius scales with the surface rather than being one number everywhere: 24
/// on a full-width card is elegant, but the same 24 on a 78pt-wide KPI tile
/// eats the corners and looks like a lozenge. Pick by surface width:
///   * [card] (24) — full-width cards, rows, dialogs
///   * [tile] (20) — narrow tiles in a row of 3–4, rounded-square avatars
///   * [control] (16) — inputs, chips, segmented buttons
///   * [pill] — buttons and status pills, fully round ends
class AppRadius {
  const AppRadius._();

  static const double control = 16;
  static const double tile = 20;
  static const double card = 24;
  static const double sheet = 30;

  /// Effectively a capsule; large enough that any control height rounds fully.
  static const double pill = 999;

  // Legacy names kept so the ~200 existing call sites keep compiling and pick
  // up the new theme automatically. sm/md/lg/xl now map onto the scale above
  // rather than the old 10/12/16/20. New code should use the named sizes.
  static const double sm = control;
  static const double md = tile;
  static const double lg = card;
  static const double xl = sheet;

  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius tileAll = BorderRadius.all(Radius.circular(tile));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetAll = BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius smAll = controlAll;
  static const BorderRadius mdAll = tileAll;
  static const BorderRadius lgAll = cardAll;
  static const BorderRadius xlAll = sheetAll;
}

/// Control and icon sizing.
///
/// Grown back from the previous density pass: a 46pt primary button and 48pt
/// field are what stop generous padding from looking like a mistake. Icons
/// stay modest — oversized glyphs fight the calm.
class AppSize {
  const AppSize._();

  static const double buttonHeight = 46;
  static const double buttonHeightSm = 36;
  static const double fieldHeight = 48;
  static const double iconRow = 18;
  static const double iconButton = 20;
  static const double iconNav = 24;
  static const double rowHeight = 58;

  /// Never below 44 — the Material/HIG floor for a reliable tap. Visible
  /// glyphs may be smaller; the transparent hit area is not.
  static const double touchTarget = 44;

  /// Hairline. 1.0 physical pixel would disappear on high-density screens and
  /// 1.5 starts to read as a drawn line rather than an edge.
  static const double hairline = 1;
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
    required this.warningSoft,
    required this.warningBorder,
    required this.warningStrong,
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
  final Color warningSoft;
  final Color warningBorder;
  final Color warningStrong;
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
    warningSoft: AppColors.lightWarningSoft,
    warningBorder: AppColors.lightWarningBorder,
    warningStrong: AppColors.lightWarningStrong,
    // Two layers, both tinted with the brand ink (#14213D) rather than black —
    // a black shadow over the blue-grey page reads as grime. The tight contact
    // layer seats the card against the page; the wide diffuse layer gives it
    // air. These carry more weight than they would in a bordered theme because
    // here the shadow *is* the edge — there is no hairline behind it.
    shadowSm: [
      BoxShadow(color: Color(0x0F14213D), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x1414213D), blurRadius: 20, offset: Offset(0, 6)),
    ],
    shadowMd: [
      BoxShadow(color: Color(0x1414213D), blurRadius: 6, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x1F14213D),
        blurRadius: 40,
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
    warningSoft: AppColors.darkWarningSoft,
    warningBorder: AppColors.darkWarningBorder,
    warningStrong: AppColors.darkWarningStrong,
    // Dark mode carries elevation with surface lightness, not shadow — a dark
    // card on a dark page separates by being lighter. So these stay subtle and
    // mostly supply the contact edge; going heavier just muddies the surface.
    shadowSm: [
      BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 8)),
    ],
    shadowMd: [
      BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2)),
      BoxShadow(
        color: Color(0x30000000),
        blurRadius: 48,
        offset: Offset(0, 18),
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
    Color? warningSoft,
    Color? warningBorder,
    Color? warningStrong,
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
      warningSoft: warningSoft ?? this.warningSoft,
      warningBorder: warningBorder ?? this.warningBorder,
      warningStrong: warningStrong ?? this.warningStrong,
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
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      warningBorder: Color.lerp(warningBorder, other.warningBorder, t)!,
      warningStrong: Color.lerp(warningStrong, other.warningStrong, t)!,
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

/// Tracking-template accents.
///
/// The backend stores `accent` as a **name** — 'green' | 'blue' | 'orange' |
/// 'purple' (`TrackingTemplate.accent`, default 'green'), and the web matches
/// on those names to pick a left-border colour. Mobile used to write
/// "#rrggbb" here instead, which meant a template created on the phone
/// matched none of the web's classes, and — worse — every name-valued
/// template coming *from* the backend failed mobile's 6-char hex parse and
/// fell back to brand blue. Seeded libraries rendered as four identical blue
/// rows on the phone while showing four distinct colours on the web.
///
/// Green and blue resolve through the theme (success / primary) so they track
/// light and dark mode, exactly as the web's `var(--app-success)` and
/// `var(--app-primary)` do. Orange and purple are fixed on both platforms.
class TemplateAccent {
  const TemplateAccent._();

  static const green = 'green';
  static const blue = 'blue';
  static const orange = 'orange';
  static const purple = 'purple';

  /// The web offers exactly these four; mobile must not invent more, or the
  /// extra ones render as an unstyled default border there.
  static const all = [green, blue, orange, purple];

  static const _orangeColor = Color(0xFFF79009);
  static const _purpleColor = Color(0xFF7A5AF8);

  static String label(String accent) => switch (accent) {
    green => 'Green',
    blue => 'Blue',
    orange => 'Orange',
    purple => 'Purple',
    _ => 'Blue',
  };

  /// Normalises anything already stored — including the legacy hex values
  /// mobile wrote — onto one of [all].
  static String normalize(String accent) {
    final value = accent.trim().toLowerCase();
    if (all.contains(value)) return value;
    return switch (value.replaceAll('#', '')) {
      '159567' || '1f9d63' || '16a34a' => green,
      'd97706' || 'f79009' => orange,
      '7c3aed' || '7a5af8' => purple,
      _ => blue,
    };
  }

  static Color of(BuildContext context, String accent) =>
      switch (normalize(accent)) {
        green => context.tokens.success,
        orange => _orangeColor,
        purple => _purpleColor,
        _ => context.colors.primary,
      };
}
