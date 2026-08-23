import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/theme_mode_controller.dart';
import '../../shared/widgets/app_widgets.dart';

/// More tab — blue hero profile card + colorful menu rows (Shop and a
/// standalone "Workspace" section deferred by design; Workspace would just
/// duplicate what the Manage tab and Dashboard quick actions already cover).
/// Replica of mobile/src/app/pages/professional/more/professional-more.page.ts,
/// restyled to match the colorful Notion/iOS-style reference mockup while
/// keeping the app's real blue brand (see app_tokens.dart).
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
    } catch (error, stackTrace) {
      debugPrint(
        'Could not load the professional summary (${error.runtimeType}).\n'
        '$stackTrace',
      );
    }
    try {
      final usage = await api.getDataUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (error, stackTrace) {
      debugPrint(
        'Could not load the data-usage summary (${error.runtimeType}).\n'
        '$stackTrace',
      );
    }
  }

  Future<void> _openProfile() async {
    await context.push<void>(Routes.professionalProfile);
    if (!mounted) return;
    await _load();
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

  /// Display fallback only — the real plan name comes from `_usage.planName`
  /// whenever the data-usage call succeeds.
  String get _planDisplayName {
    final planName = _usage?.planName ?? '';
    return planName.isNotEmpty ? planName : 'Free Plan';
  }

  double get _usagePercent => ((_usage?.usagePercent ?? 0) * 10).round() / 10;

  Color _usageHeatColor() {
    if (_usagePercent >= 90) return Colors.redAccent.shade100;
    if (_usagePercent >= 75) return Colors.orangeAccent.shade100;
    if (_usagePercent >= 50) return Colors.amberAccent.shade100;
    return Colors.lightGreenAccent.shade100;
  }

  Future<void> _showAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final selected = ref.read(themeModeProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.card,
              0,
              AppSpacing.card,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance', style: sheetContext.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Choose how RepRoot looks on this device.',
                  style: sheetContext.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (final option in const [
                  (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
                  (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                  (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(option.$3),
                    title: Text(option.$2),
                    trailing: selected == option.$1
                        ? Icon(
                            Icons.check_circle,
                            color: sheetContext.colors.primary,
                          )
                        : const Icon(Icons.circle_outlined),
                    onTap: () async {
                      await ref
                          .read(themeModeProvider.notifier)
                          .setMode(option.$1);
                      if (sheetContext.mounted) sheetContext.pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    setState(() => _isSigningOut = true);
    final api = ref.read(professionalAuthApiProvider);
    // Best effort: a failed server logout must still clear the local session.
    try {
      await api.logout();
    } catch (error, stackTrace) {
      debugPrint(
        'Professional logout request failed; clearing the local session '
        '(${error.runtimeType}).\n$stackTrace',
      );
    }
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

  Widget _buildHero(BuildContext context) {
    final tokens = context.tokens;
    final primary = context.colors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? context.colors.onSurface : Colors.white;
    final mutedForeground = isDark
        ? tokens.muted
        : Colors.white.withValues(alpha: 0.85);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [context.colors.surface, tokens.surfaceSoft]
              : [primary, tokens.primaryStrong],
        ),
        borderRadius: AppRadius.lgAll,
        border: isDark
            ? Border.all(color: primary.withValues(alpha: 0.3))
            : null,
        boxShadow: tokens.shadowMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(
            initials: _initials,
            imageUrl: Env.mediaUrl(_profile?.profilePhotoUrl ?? ''),
            size: 144,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fullName,
                  style: context.text.titleMedium?.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _profile?.professionalHeadline.isNotEmpty ?? false
                      ? _profile!.professionalHeadline
                      : 'Personal Professional',
                  style: context.text.bodySmall?.copyWith(
                    color: mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? tokens.primarySoft
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    _planDisplayName,
                    style: context.text.labelSmall?.copyWith(
                      color: isDark ? tokens.primaryStrong : Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Storage used',
                      style: context.text.bodySmall?.copyWith(
                        color: mutedForeground,
                      ),
                    ),
                    Text(
                      '$_usagePercent%',
                      style: context.text.bodySmall?.copyWith(
                        color: _usageHeatColor(),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_usagePercent / 100).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: isDark
                        ? tokens.border
                        : Colors.white.withValues(alpha: 0.22),
                    color: _usageHeatColor(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: _openProfile,
                  borderRadius: AppRadius.smAll,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'View Profile',
                        style: context.text.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: foreground,
                        size: AppSize.iconRow,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar — same header shape as every other tab; the bare 52px
      // toolbar here had nothing in it.
      body: SafeArea(
        child: PagePad(
          onRefresh: _load,
          children: [
            // Same eyebrow/title/subtitle header pattern as every other tab.
            // More is mobile-only (profile/settings/support combined into one
            // tab, unlike the web's separate Profile/Settings sidebar items),
            // so the copy describes what it aggregates rather than quoting a
            // specific web string.
            PageHeader(
              eyebrow: 'PROFESSIONAL WORKSPACE',
              title: 'More',
              info:
                  'Your own account, rather than your clients\'.\n\n'
                  'SETTINGS\n'
                  'Your public profile, sign-in security, notification '
                  'preferences, how you take payments, and your plan.\n\n'
                  'SUPPORT AND LEGAL\n'
                  'Getting help, and the terms and policies you have '
                  'accepted.\n\n'
                  'On mobile these are gathered here; on the website they sit '
                  'in the sidebar.',
            ),
            _buildHero(context),

            const _Eyebrow('SETTINGS'),
            ColorfulMenuCard(
              items: [
                ColorfulMenuItem(
                  icon: Icons.person_outline,
                  accent: MenuAccent.blue,
                  label: 'My Profile',
                  onTap: _openProfile,
                ),
                ColorfulMenuItem(
                  icon: Icons.lock_outline,
                  accent: MenuAccent.orange,
                  label: 'Security',
                  onTap: () =>
                      context.push(Routes.professionalSettingsSecurity),
                ),
                ColorfulMenuItem(
                  icon: Icons.notifications_outlined,
                  accent: MenuAccent.purple,
                  label: 'Notifications',
                  onTap: () => context.push(
                    '${Routes.professionalNotifications}/preferences',
                  ),
                ),
                ColorfulMenuItem(
                  icon: Icons.payments_outlined,
                  accent: MenuAccent.green,
                  label: 'Payments',
                  onTap: () => context.push(Routes.professionalPayments),
                ),
                ColorfulMenuItem(
                  icon: Icons.credit_card_outlined,
                  accent: MenuAccent.teal,
                  label: 'Plan and Billing',
                  onTap: () => context.push(Routes.professionalSettingsBilling),
                ),
                ColorfulMenuItem(
                  icon: Icons.data_usage_outlined,
                  accent: MenuAccent.orange,
                  label: 'Data Usage',
                  onTap: () =>
                      context.push(Routes.professionalSettingsPlanStorage),
                ),
                ColorfulMenuItem(
                  icon: Icons.palette_outlined,
                  accent: MenuAccent.pink,
                  label: 'Appearance',
                  onTap: _showAppearance,
                ),
              ],
            ),

            const _Eyebrow('SUPPORT AND LEGAL'),
            ColorfulMenuCard(
              items: [
                ColorfulMenuItem(
                  icon: Icons.gavel_outlined,
                  accent: MenuAccent.blue,
                  label: 'Support and Legal',
                  onTap: () => context.push(Routes.professionalSupportLegal),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            AppCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: _isSigningOut ? null : _confirmLogout,
                borderRadius: AppRadius.mdAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.card,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.error.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.logout,
                          size: AppSize.iconRow,
                          color: context.colors.error,
                        ),
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
      ),
    );
  }
}

/// Small bold muted-color eyebrow section label — matches the "STORAGE
/// BREAKDOWN" / "ONE-TIME SETUP" all-caps label pattern already used on
/// professional_settings_plan_storage_page.dart and the dashboard's
/// reporting-currency card.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Text(
        label,
        style: context.text.labelSmall?.copyWith(
          color: context.tokens.muted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
