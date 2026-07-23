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
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.topSpace = AppSpacing.xl,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double topSpace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topSpace, bottom: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: context.text.titleLarge)),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!, style: context.text.labelMedium),
            ),
        ],
      ),
    );
  }
}

/// Bordered surface container — the base card look (radius 12, hairline border,
/// no elevation) used by tiles, rows, and charts.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.card),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: context.tokens.border),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: content,
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
                  style: context.text.labelMedium?.copyWith(color: tokens.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: context.text.displaySmall?.copyWith(color: valueColor),
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
  });

  final String title;
  final String? subtitle;
  final String? trailingValue;
  final String? trailingCaption;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.card,
          vertical: AppSpacing.md,
        ),
        child: Row(
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
      PillTone.warn => (tokens.accent.withValues(alpha: 0.14), tokens.accent),
      PillTone.bad => (colors.error.withValues(alpha: 0.12), colors.error),
      PillTone.neutral => (tokens.surfaceSoft, tokens.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.smAll),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
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
        style: context.text.labelMedium?.copyWith(color: Colors.white),
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
