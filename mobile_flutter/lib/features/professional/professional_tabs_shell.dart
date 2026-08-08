import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/app_bottom_nav.dart';

/// Professional bottom-tab shell: Dashboard | Manage | Clients | Schedule | More.
/// Shop is deferred by design, same as the Ionic app.
class ProfessionalTabsShell extends StatelessWidget {
  const ProfessionalTabsShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        selectedIndex: navigationShell.currentIndex,
        onSelect: (index) => navigationShell.goBranch(
          index,
          // Tapping the active tab pops back to its root, matching Ionic.
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: const [
          AppNavItem(icon: Icons.grid_view_rounded, label: 'Dashboard'),
          // Was Icons.tune_rounded — sliders read as "settings/filters", but
          // this tab is the hub for forms, groups, templates and resources.
          // category_rounded (three distinct shapes) says "your collections"
          // and stays visually distinct from Dashboard's grid_view. Revert to
          // tune_rounded if this reads worse in situ.
          AppNavItem(icon: Icons.category_rounded, label: 'Manage'),
          AppNavItem(icon: Icons.people_rounded, label: 'Clients'),
          AppNavItem(icon: Icons.calendar_month_rounded, label: 'Schedule'),
          AppNavItem(icon: Icons.more_horiz_rounded, label: 'More'),
        ],
      ),
    );
  }
}
