import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Shared building blocks for every screen — the Flutter equivalents of the
/// .page-pad / .kpi-tile / .row-item / .section-row / .pill rules in
/// mobile/src/global.scss. Sizing follows the tightened scale (see AppSize).

/// Standard screen padding, with room at the bottom so the last row clears
/// the nav bar (the .bottom-space rule in global.scss).
class PagePad extends StatelessWidget {
  const PagePad({super.key, required this.children, this.onRefresh});

  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.xxl + AppSpacing.lg,
      ),
      children: children,
    );
    if (onRefresh == null) return list;
    return RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// Section title with an optional trailing action — the .section-row rule.
///
/// Weight w800 with tight tracking, matching the web's `.panel h2`. That is
/// deliberately heavier than any card or row title (w700 at 13–14pt), so a
/// heading never reads as just another item in the list below it.
///
/// [infoBody] adds an `i` button directly beside the title. Long explanations
/// of drag-ordering and plan locking live in there rather than as grey prose
/// on the page: the rules matter when you go looking for them, not on every
/// visit.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.infoBody,
    this.infoTitle,
    this.topSpace = AppSpacing.xl,
    this.subheading = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Body of the `i` popup. Null hides the icon entirely.
  final String? infoBody;

  /// Popup heading; falls back to [title].
  final String? infoTitle;
  final double topSpace;

  /// Renders one level down — smaller and lighter than a top-level heading.
  /// Needed wherever a section has named parts inside it (Schedule &
  /// Follow-Ups → Reminders, Meetings); at the same weight the children
  /// looked like siblings of their own parent.
  final bool subheading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: topSpace,
        bottom: subheading ? AppSpacing.sm : AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title and its info dot travel together as one unit, so the dot
          // sits against the end of the text rather than drifting off to the
          // far edge of the row.
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: subheading
                        ? context.text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )
                        : context.text.titleLarge?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                  ),
                ),
                if (infoBody != null)
                  InfoDot(title: infoTitle ?? title, body: infoBody!),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                minimumSize: const Size(0, 34),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.pillAll,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!, style: context.text.labelMedium),
            ),
        ],
      ),
    );
  }
}

/// The eyebrow + title block at the top of every tab.
///
/// Replaces the eyebrow/title/**subtitle** trio. The subtitle was a full
/// sentence describing the page, permanently occupying two lines near the top
/// of a phone screen to say something that is only useful once. It moved into
/// the [info] popup; the page itself now opens on content.
///
/// [trailing] takes the notification bell where a page has one.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.info,
    this.trailing,
  });

  final String eyebrow;
  final String title;

  /// Body of the `i` popup — what this page is for.
  final String info;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(title, style: context.text.displaySmall),
                    ),
                    InfoDot(title: title, body: info),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A small `i` button that opens an explanation.
///
/// Deliberately an `i` and not a `?`: a question mark reads as "get help,
/// something has gone wrong", while these popups are reference material about
/// how a feature works. It sits inline beside a heading, so it is sized to the
/// text rather than to a default 48pt IconButton, which would have pushed the
/// heading's baseline around.
class InfoDot extends StatelessWidget {
  const InfoDot({super.key, required this.title, required this.body});

  final String title;

  /// Blank lines separate paragraphs.
  final String body;

  Future<void> _open(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body, style: Theme.of(dialogContext).textTheme.bodyMedium),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'About $title',
      child: InkWell(
        onTap: () => _open(context),
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Icon(
            Icons.info_outline,
            size: AppSize.iconRow,
            color: context.tokens.muted,
          ),
        ),
      ),
    );
  }
}

/// The base surface for tiles, rows, and charts.
///
/// **Every card carries a hairline border**, as the web's `.panel` does
/// (`border: 1px solid var(--app-border)` *plus* a shadow). An earlier mobile
/// pass dropped borders on the theory that the shadow alone was the edge —
/// on a phone, against a near-white page, that shadow is nearly invisible and
/// sections dissolved into the background. Border and shadow together is what
/// the website does and what actually reads outdoors.
///
/// Two looks, chosen automatically by whether [color] is given — this is the
/// theme's central rule, so it lives here rather than at each call site:
///
///   * **No [color]** → white, bordered, shadowed. The *section* surface: a
///     card, a list row, something you tap. It floats above the page.
///   * **[color] given** → that colour, bordered, flat. The *content* surface
///     used inside a section: a KPI tile, a callout, a summary band.
///
/// That gives the three levels the design asks for: page wash → white
/// bordered section → tinted bordered element inside it → plain text for
/// individual values.
///
/// A tinted card with a drop shadow reads as a mistake — the wash already
/// separates it, so the shadow is suppressed rather than layered on top. Pass
/// [elevated] to override when a tinted surface genuinely needs to lift (a
/// floating action panel over content, for instance).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.onTap,
    this.color,
    this.radius = AppRadius.card,
    this.elevated,
    this.bordered = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  /// Corner radius. Defaults to [AppRadius.card]; drop to [AppRadius.tile] for
  /// anything narrow, or the corners swallow the content.
  final double radius;

  /// Forces the shadow on or off. Defaults to "on when untinted".
  final bool? elevated;

  /// Hairline border. On by default; set false only where a card is already
  /// inside another bordered container and a second line would double up.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final isElevated = elevated ?? color == null;

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.colors.surface,
        borderRadius: borderRadius,
        border: bordered
            ? Border.all(color: context.tokens.border, width: AppSize.hairline)
            : null,
        boxShadow: isElevated ? context.tokens.shadowSm : null,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      // clipBehavior keeps the ripple inside the rounded corners; without it
      // the splash paints square and spills past a 24pt radius.
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: content,
      ),
    );
  }
}

/// Metric tile — the .kpi-tile rule. Two per row on a phone.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.iconColor,
    this.valueColor,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  /// Tints the icon and gives it a soft matching background chip. Null keeps
  /// the plain muted icon — existing call sites are unaffected.
  final Color? iconColor;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                if (iconColor != null)
                  Container(
                    width: AppSize.iconRow,
                    height: AppSize.iconRow,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: iconColor!.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: AppSize.iconRow - 7, color: iconColor),
                  )
                else
                  Icon(icon, size: AppSize.iconRow, color: tokens.muted),
                const SizedBox(width: AppSpacing.xs + 2),
              ],
              Expanded(
                child: Text(
                  label,
                  // w700 muted, matching the web's `.overview-cards span`.
                  // The label is the quiet half of the pair; the value below
                  // carries the weight.
                  style: context.text.labelMedium?.copyWith(
                    color: tokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: context.text.displaySmall?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w800,
              // Tabular figures so a column of KPI values lines up digit for
              // digit instead of shifting with the glyph widths.
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
          ),
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: context.text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-column tile grid — the .kpi-grid rule.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      // Tuned to the tightened type scale: at 1.65 the tiles kept the height
      // they needed for the old larger text and sat half empty. 2.15 was too
      // far — tiles with a caption line (label + value + caption) overflowed by
      // ~4px. 1.95 fits the tallest variant with a little slack.
      childAspectRatio: 1.95,
      children: children,
    );
  }
}

/// A row of tinted-icon-chip stat tiles, tighter than [KpiGrid] so 4 fit on
/// one line — the colorful KPI treatment already used on the Dashboard's
/// Payments/Schedule tabs, promoted here so other pages (e.g. the client
/// detail page's Client Activity section) can reuse it too.
class CompactStatRow extends StatelessWidget {
  const CompactStatRow({super.key, required this.stats});

  final List<CompactStat> stats;

  @override
  Widget build(BuildContext context) {
    // Two across, not four. Four tiles on a ~390pt phone leave each about
    // 85pt wide, which forces the value down to title size and wraps every
    // label onto two lines — the number, which is the whole point of a KPI,
    // ends up the smallest thing in the tile. Pairs give it room to be
    // display-sized. An odd final tile takes the left half rather than
    // stretching wide, so the grid still reads as a grid.
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      final right = i + 1 < stats.length ? stats[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: stats[i]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
      if (i + 2 < stats.length) rows.add(const SizedBox(height: AppSpacing.sm));
    }
    return Column(children: rows);
  }
}

/// One tile inside a [CompactStatRow] — a tinted [MenuAccent] icon chip above
/// a value/label pair.
class CompactStat extends StatelessWidget {
  const CompactStat({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accent,
    this.valueColor,
    this.onTap,
    this.caption,
  });

  final String value;
  final String label;
  final IconData? icon;
  final ({Color fg, Color bg})? accent;
  final Color? valueColor;
  final VoidCallback? onTap;
  /// Optional third line under the label — the website's tiles often carry a
  /// second bit of context under the value ("This month", a template name,
  /// "Keep it up!"/"No current streak"). Null by default so existing call
  /// sites that don't have a caption to show are unaffected.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final effectiveValueColor = valueColor ?? accent?.fg;

    // A KPI tile is read, not acted on, so it takes the tinted/flat treatment:
    // washed in its own accent at low alpha when it has one, otherwise the
    // neutral soft surface. Four white shadowed boxes in a row looked busy —
    // the wash groups them as one band of numbers instead.
    final tint = accent == null
        ? tokens.surfaceSoft
        : Color.alphaBlend(accent!.bg.withValues(alpha: 0.55), tokens.surfaceSoft);

    // Icon sits beside the text, not above it. Stacking it added a whole row
    // of height to every tile for no extra information — the same tiles on the
    // Dashboard put it alongside and read just as clearly while being
    // noticeably shorter.
    return AppCard(
      onTap: onTap,
      color: tint,
      radius: AppRadius.tile,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: context.text.headlineSmall?.copyWith(
                    color: effectiveValueColor,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 3),
                // Uppercase + tracked out. At 11pt this is the detail that
                // makes a number tile read as a considered stat rather than a
                // stray label. Hard newlines from older call sites are
                // stripped — at half-width they no longer need to wrap early.
                Text(
                  label.replaceAll('\n', ' ').toUpperCase(),
                  style: context.text.labelSmall?.copyWith(
                    color: tokens.muted,
                    height: 1.25,
                    letterSpacing: 0.5,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                ),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.muted,
                      fontSize: 11,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (icon != null && accent != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(icon, size: AppSize.iconButton, color: accent!.fg),
          ],
        ],
      ),
    );
  }
}

/// List row with a title/subtitle on the left and a value or pill on the right
/// — the .row-item rule.
class RowItem extends StatelessWidget {
  const RowItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailingValue,
    this.trailingCaption,
    this.trailing,
    this.leading,
    this.onTap,
    this.accentColor,
  });

  final String title;
  final String? subtitle;
  final String? trailingValue;
  final String? trailingCaption;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  /// Paints a full-height accent stripe flush against the card's left edge —
  /// the web's `border-left: 4px solid <accent>` on `.template-row`. Passing
  /// the colour here rather than as a [leading] widget keeps it read as a
  /// property of the row itself instead of as another item in the content.
  final Color? accentColor;

  /// Wraps [row] with the left accent stripe when [accentColor] is set.
  ///
  /// IntrinsicHeight is what lets a zero-height stripe match whatever height
  /// the row's text ends up being; a fixed-height bar drifted out of
  /// alignment as soon as a subtitle wrapped to a second line.
  Widget _withAccent(BuildContext context, Widget row) {
    final accent = accentColor;
    if (accent == null) return row;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.card),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.card - 4),
          Expanded(child: row),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      // stack, not sm — the gap has to clear the card's shadow blur or
      // consecutive rows smudge into each other instead of reading as stacked.
      padding: const EdgeInsets.only(bottom: AppSpacing.stack),
      child: AppCard(
        onTap: onTap,
        padding: EdgeInsets.only(
          // The stripe supplies the left inset when present, so the content
          // does not end up double-padded away from the edge.
          left: accentColor == null ? AppSpacing.card : 0,
          right: AppSpacing.card,
          top: AppSpacing.card - 2,
          bottom: AppSpacing.card - 2,
        ),
        child: _withAccent(
          context,
          Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: context.text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (trailingValue != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(trailingValue!, style: context.text.titleSmall),
                  if (trailingCaption != null && trailingCaption!.isNotEmpty)
                    Text(trailingCaption!, style: context.text.bodySmall),
                ],
              ),
            if (onTap != null && trailing == null && trailingValue == null)
              Icon(Icons.chevron_right, size: AppSize.iconRow, color: tokens.muted),
          ],
          ),
        ),
      ),
    );
  }
}

enum PillTone { neutral, info, good, warn, bad }

/// Small status chip — the .pill rule.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    final (bg, fg) = switch (tone) {
      PillTone.info => (tokens.primarySoft, colors.primary),
      PillTone.good => (tokens.success.withValues(alpha: 0.14), tokens.success),
      PillTone.warn => (tokens.warningSoft, tokens.warningStrong),
      PillTone.bad => (colors.error.withValues(alpha: 0.12), colors.error),
      PillTone.neutral => (tokens.surfaceSoft, tokens.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillAll),
      child: Text(
        label,
        // w600 not w700: against a soft tinted capsule the heavier weight read
        // as a warning badge even for neutral statuses.
        style: context.text.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Icon + one-line guidance + optional action — the empty-state pattern.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = true,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Compact renders as an inline note (the .empty-note rule); full renders a
  /// centred icon + message for whole-screen emptiness.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          message,
          style: context.text.bodySmall,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: tokens.primarySoft,
              borderRadius: AppRadius.lgAll,
            ),
            child: Icon(icon, color: context.colors.primary, size: 24),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.text.bodyMedium?.copyWith(color: tokens.muted),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(160, AppSize.buttonHeight),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly error + Retry, for a failed load.
class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        color: context.colors.error.withValues(alpha: 0.06),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.colors.error, size: AppSize.iconRow),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: context.text.bodySmall?.copyWith(color: context.colors.error),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shimmer-free skeleton block for loading states — a calm pulse rather than a
/// spinner, matching the "no decorative motion" rule.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 72, this.width});

  final double height;
  final double? width;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(_controller),
      child: Container(
        height: widget.height,
        width: widget.width,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.tokens.surfaceSoft,
          borderRadius: AppRadius.mdAll,
        ),
      ),
    );
  }
}

/// Circular avatar with initials fallback.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.initials,
    this.imageUrl = '',
    this.size = 44,
  });

  final String initials;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.colors.primary, tokens.accent],
        ),
      ),
      child: Text(
        initials,
        // Scales with the avatar instead of sitting at a fixed 12pt: the
        // client-detail header renders this at 72px, where fixed-size initials
        // looked like a typo floating in a circle. 0.36 keeps two characters
        // comfortably inside the circle at every size in use.
        style: context.text.labelMedium?.copyWith(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
    );

    if (imageUrl.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // A broken photo URL must never blank the screen.
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// Accent tints for menu-row icon chips only — a small fixed palette,
/// intentionally separate from the brand tokens in app_tokens.dart (which
/// must not change per its own "do not change them here" comment). Do not
/// reuse these for buttons, text, or backgrounds outside of
/// [ColorfulMenuCard] icon chips.
class MenuAccent {
  const MenuAccent._();

  // Reuses the real brand primary/primarySoft — not a new color.
  static const blue = (fg: Color(0xFF2563EB), bg: Color(0xFFE8F0FF));
  // Reuses the real brand accent.
  static const teal = (fg: Color(0xFF0F9F9D), bg: Color(0xFFE1F5F4));
  // Reuses the real brand success.
  static const green = (fg: Color(0xFF159567), bg: Color(0xFFE3F6EC));
  static const orange = (fg: Color(0xFFD97706), bg: Color(0xFFFDF0DC));
  static const purple = (fg: Color(0xFF7C3AED), bg: Color(0xFFF1E9FE));
  static const pink = (fg: Color(0xFFDB2777), bg: Color(0xFFFCE4F1));
}

/// One row in a [ColorfulMenuCard] — a tinted icon chip (see [MenuAccent]),
/// a label with an optional muted subtitle, and either a chevron or
/// [trailingText] on the right.
class ColorfulMenuItem {
  const ColorfulMenuItem({
    required this.icon,
    required this.accent,
    required this.label,
    this.subtitle,
    this.trailingText,
    required this.onTap,
  });

  final IconData icon;
  final ({Color fg, Color bg}) accent;
  final String label;
  final String? subtitle;
  final String? trailingText;
  final VoidCallback onTap;
}

/// Grouped, colorful menu rows — the restyled replacement for the old plain
/// grey-icon menu-card rows. Each row gets a soft circular icon chip tinted
/// with its own [MenuAccent] instead of a flat muted glyph; hairline
/// dividers between rows (tokens.border) match the previous menu-card look.
class ColorfulMenuCard extends StatelessWidget {
  const ColorfulMenuCard({super.key, required this.items});

  final List<ColorfulMenuItem> items;

  static const double _chipSize = 38;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            InkWell(
              onTap: items[i].onTap,
              // Matches the card's own corner so the first/last row's ripple
              // doesn't paint square into a 24pt rounded corner.
              borderRadius: i == 0
                  ? const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.card),
                    )
                  : i == items.length - 1
                  ? const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.card),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.card - 2,
                ),
                child: Row(
                  children: [
                    Container(
                      width: _chipSize,
                      height: _chipSize,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: items[i].accent.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        items[i].icon,
                        size: AppSize.iconRow,
                        color: items[i].accent.fg,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(items[i].label, style: context.text.bodyLarge),
                          if (items[i].subtitle != null &&
                              items[i].subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              items[i].subtitle!,
                              style: context.text.bodySmall?.copyWith(
                                color: tokens.muted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (items[i].trailingText != null)
                      Text(
                        items[i].trailingText!,
                        style: context.text.labelSmall?.copyWith(
                          color: tokens.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      Icon(
                        Icons.chevron_right,
                        size: AppSize.iconRow,
                        color: tokens.muted,
                      ),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.border,
                indent: AppSpacing.card + _chipSize + AppSpacing.md,
              ),
          ],
        ],
      ),
    );
  }
}

/// Hero header for Settings-style landing pages — a soft-tinted circular
/// icon, bold title, muted subtitle. Always brand blue (context.colors.primary
/// / tokens.primarySoft) — the reference mockup's hero used purple, but
/// app_tokens.dart's palette must not change, so this stays blue by design.
class SettingsHeroCard extends StatelessWidget {
  const SettingsHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.primarySoft,
              borderRadius: AppRadius.lgAll,
            ),
            child: Icon(icon, color: context.colors.primary, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: context.text.titleLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.text.bodySmall?.copyWith(color: tokens.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The notification bell, as a distinct circular control.
///
/// Previously a bare [IconButton] sitting flush in the header, where it read
/// as part of the page's own text block rather than as a separate place to
/// go. Giving it a filled circle separates it from the dashboard content and
/// makes the unread state legible at a glance: the circle itself turns
/// primary-tinted and the icon fills in when something is waiting, so the
/// state survives even if the badge digits are missed.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.unread,
    required this.onTap,
  });

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;
    final hasUnread = unread > 0;

    return Semantics(
      button: true,
      label: hasUnread
          ? '$unread unread notifications'
          : 'Notifications, none unread',
      child: Tooltip(
        message: 'Notifications',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: AppSize.touchTarget,
            height: AppSize.touchTarget,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasUnread ? tokens.primarySoft : tokens.surfaceSoft,
            ),
            child: Badge(
              isLabelVisible: hasUnread,
              backgroundColor: colors.error,
              label: Text(unread > 99 ? '99+' : '$unread'),
              child: Icon(
                hasUnread ? Icons.notifications : Icons.notifications_outlined,
                size: AppSize.iconButton,
                color: hasUnread ? colors.primary : tokens.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
