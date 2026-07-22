import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// More tab — profile header + menu rows (Shop deferred, as in the Ionic app).
/// Replica of mobile/src/app/pages/professional/more/professional-more.page.ts.
class ProfessionalMorePage extends ConsumerStatefulWidget {
  const ProfessionalMorePage({super.key});

  @override
  ConsumerState<ProfessionalMorePage> createState() =>
      _ProfessionalMorePageState();
}

class _ProfessionalMorePageState extends ConsumerState<ProfessionalMorePage> {
  ProfessionalProfile? _profile;
  ProfessionalDataUsage? _usage;
  bool _isSigningOut = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    try {
      final profile = await api.getProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      /* header falls back to 'Professional' */
    }
    try {
      final usage = await api.getDataUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {
      /* the usage row just shows 0% */
    }
  }

  String get _fullName {
    final profile = _profile;
    if (profile == null) return 'Professional';
    final name = profile.displayName;
    return name.isNotEmpty ? name : profile.username;
  }

  String get _initials {
    final letters = _fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    if (letters.isEmpty) return 'T';
    return letters.length > 2 ? letters.substring(0, 2) : letters;
  }

  double get _usagePercent => ((_usage?.usagePercent ?? 0) * 10).round() / 10;

  Future<void> _logout() async {
    setState(() => _isSigningOut = true);
    final api = ref.read(professionalAuthApiProvider);
    // Best effort: a failed server logout must still clear the local session.
    try {
      await api.logout();
    } catch (_) {}
    await api.clearSession();
    if (mounted) context.go(Routes.roleChooser);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need your password to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
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
    if (confirmed == true) await _logout();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: PagePad(
        onRefresh: _load,
        children: [
          AppCard(
            onTap: () => context.go(Routes.professionalProfile),
            child: Row(
              children: [
                AppAvatar(
                  initials: _initials,
                  imageUrl: Env.mediaUrl(_profile?.profilePhotoUrl ?? ''),
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
                        _profile?.professionalHeadline.isNotEmpty ?? false
                            ? _profile!.professionalHeadline
                            : 'Personal Professional',
                        style: context.text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: tokens.muted,
                  size: AppSize.iconRow,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.person_outline,
                label: 'Professional Profile',
                onTap: () => context.go(Routes.professionalProfile),
              ),
              _MenuItem(
                icon: Icons.folder_open_outlined,
                label: 'Reference Library',
                onTap: () => context.go(Routes.professionalReferences),
              ),
              _MenuItem(
                icon: Icons.storage_outlined,
                label: 'Plan & Storage',
                trailingText: '$_usagePercent% used',
                onTap: () => context.go(Routes.professionalSettings),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          _MenuCard(
            items: [
              _MenuItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                onTap: () => context.go(Routes.professionalSettings),
              ),
              _MenuItem(
                icon: Icons.help_outline,
                label: 'Help & Support',
                onTap: () => context.go(Routes.professionalSupport),
              ),
              _MenuItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                onTap: () => context.go(Routes.professionalNotifications),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          AppCard(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: _isSigningOut ? null : _confirmLogout,
              borderRadius: AppRadius.mdAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.md + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.logout,
                      size: AppSize.iconRow,
                      color: context.colors.error,
                    ),
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
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;
}

/// Grouped menu rows with hairline dividers — the .menu-card rule.
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
              borderRadius: i == 0
                  ? const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.md),
                    )
                  : i == items.length - 1
                  ? const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.md),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.md + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      items[i].icon,
                      size: AppSize.iconRow,
                      color: tokens.muted,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        items[i].label,
                        style: context.text.bodyLarge,
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
              Divider(height: 1, thickness: 1, color: tokens.border),
          ],
        ],
      ),
    );
  }
}
