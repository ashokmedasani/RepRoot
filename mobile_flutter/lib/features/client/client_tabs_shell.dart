import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/client_api.dart';
import '../../shared/widgets/app_bottom_nav.dart';

/// Client bottom-tab shell: Dashboard | Programs | Professional | More.
/// The unread badge sits on Professional, since chat lives there as a segment
/// (Profile | Chat). Progress no longer has its own tab — its charts moved
/// onto the Dashboard.
///
/// The forced password change is NOT gated here — it is gated at login and on
/// session restore (see ClientChangePasswordPage), matching the web portal.
class ClientTabsShell extends ConsumerStatefulWidget {
  const ClientTabsShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<ClientTabsShell> createState() => _ClientTabsShellState();
}

class _ClientTabsShellState extends ConsumerState<ClientTabsShell> {
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadUnread();
    // Same 5s cadence as the Ionic tabs page.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final count = await ref.read(clientApiProvider).getChatUnreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: AppBottomNavBar(
        selectedIndex: widget.navigationShell.currentIndex,
        onSelect: (index) => widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
        items: [
          const AppNavItem(icon: Icons.grid_view_rounded, label: 'Dashboard'),
          const AppNavItem(icon: Icons.list_alt_rounded, label: 'Programs'),
          AppNavItem(
            icon: Icons.badge_rounded,
            label: 'Professional',
            badgeCount: _unread,
          ),
          const AppNavItem(icon: Icons.more_horiz_rounded, label: 'More'),
        ],
      ),
    );
  }
}
