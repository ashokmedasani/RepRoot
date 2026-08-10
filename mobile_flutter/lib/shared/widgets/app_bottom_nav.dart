import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// One destination in [AppBottomNavBar].
class AppNavItem {
  const AppNavItem({required this.icon, required this.label, this.badgeCount});

  final IconData icon;
  final String label;

  /// Shown as a small red dot/count in the top-right of the icon when > 0.
  final int? badgeCount;
}

/// Bottom nav bar: icon above label, flush to the bottom edge with softly
/// rounded top corners. The active destination is highlighted by tinting
/// both its icon and label the brand primary color — no raised bubble, no
/// icon-only mode. Reskinned to match the reference layout the user
/// approved; brand colors are untouched (see AppTokens doc comment — do not
/// fork the palette here), only the shape/label treatment changed from the
/// earlier icon-only floating-bubble version.
///
/// Same destinations, same [onSelect] contract as before — this is a visual
/// reskin, not a navigation change.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<AppNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  static const double _barHeight = 60;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: tokens.shadowMd,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTapTarget(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelect(i),
                    activeColor: scheme.primary,
                    mutedColor: tokens.muted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTapTarget extends StatelessWidget {
  const _NavTapTarget({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.activeColor,
    required this.mutedColor,
  });

  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final badge = item.badgeCount ?? 0;
    final color = selected ? activeColor : mutedColor;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _withBadge(
              Icon(item.icon, color: color, size: AppSize.iconNav),
              badge,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _withBadge(Widget child, int count) {
  if (count <= 0) return child;
  return Stack(
    clipBehavior: Clip.none,
    children: [
      child,
      Positioned(
        top: -2,
        right: -8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
          decoration: const BoxDecoration(
            color: Color(0xFFE11D48),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            count > 99 ? '99+' : '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    ],
  );
}
