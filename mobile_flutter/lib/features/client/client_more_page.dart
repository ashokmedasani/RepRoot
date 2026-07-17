import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Client More tab — profile header + menu rows + sign out.
/// Replica of mobile/src/app/pages/client/more/client-more.page.ts.
class ClientMorePage extends ConsumerStatefulWidget {
  const ClientMorePage({super.key});

  @override
  ConsumerState<ClientMorePage> createState() => _ClientMorePageState();
}

class _ClientMorePageState extends ConsumerState<ClientMorePage> {
  ClientMeResponse? _me;
  int _unread = 0;
  bool _isSigningOut = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await ref.read(clientApiProvider).getMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {
      if (mounted) setState(() => _me = null);
    }
  }

  Future<void> _loadUnread() async {
    try {
      final count = await ref.read(clientApiProvider).getChatUnreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

  String get _fullName {
    final client = _me?.client;
    if (client == null) return 'Client';
    return client.displayName.isNotEmpty ? client.displayName : client.username;
  }

  String get _initials {
    final client = _me?.client;
    final first = client?.firstName ?? '';
    final last = client?.lastName ?? '';
    final letters =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'
            .toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign back in.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSigningOut = true);
    final api = ref.read(clientApiProvider);
    // Best effort: a failed server logout must still clear the local session.
    try {
      await api.logout();
    } catch (_) {}
    await api.clearSession();
    if (mounted) context.go(Routes.roleChooser);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final client = _me?.client;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: PagePad(
        onRefresh: _load,
        children: [
          AppCard(
            onTap: () => context.go(Routes.clientSettings),
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials,
                  imageUrl: Env.mediaUrl(client?.photo ?? ''),
                  size: 46,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fullName,
                        style: context.text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        client?.groupName.isNotEmpty ?? false
                            ? client!.groupName
                            : 'Your account',
                        style: context.text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.muted, size: AppSize.iconRow),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.person_outline,
                label: 'Your trainer',
                subtitle: client?.trainerName.isNotEmpty ?? false
                    ? client!.trainerName
                    : null,
                onTap: () => context.go(Routes.clientTrainer),
              ),
              _MenuItem(
                icon: Icons.chat_bubble_outline,
                label: 'Messages',
                badge: _unread > 0 ? (_unread > 99 ? '99+' : '$_unread') : null,
                onTap: () => context.go(Routes.clientChat),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => context.go(Routes.clientSettings),
              ),
              _MenuItem(
                icon: Icons.help_outline,
                label: 'Help & Support',
                onTap: () => context.go(Routes.clientSupport),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: _isSigningOut ? null : _signOut,
              borderRadius: AppRadius.mdAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.md + 2,
                ),
                child: Row(
                  children: [
                    Icon(Icons.logout, size: AppSize.iconRow, color: context.colors.error),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      _isSigningOut ? 'Signing out…' : 'Logout',
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final String? badge;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.items});

  final List<_MenuItem> items;

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
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.md + 2,
                ),
                child: Row(
                  children: [
                    Icon(items[i].icon, size: AppSize.iconRow, color: tokens.muted),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(items[i].label, style: context.text.bodyLarge),
                          if (items[i].subtitle != null)
                            Text(items[i].subtitle!, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    if (items[i].badge != null)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE11D48),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          items[i].badge!,
                          style: context.text.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right, size: AppSize.iconRow, color: tokens.muted),
                  ],
                ),
              ),
            ),
            if (i < items.length - 1)
              Divider(height: 1, thickness: 1, color: tokens.border),
          ],
        ],
      ),
    );
  }
}
