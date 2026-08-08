import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
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

  /// Display fallback only — the real plan name comes from `_usage.planName`
  /// whenever the data-usage call succeeds.
  String get _planDisplayName {
    final planName = _usage?.planName ?? '';
    return planName.isNotEmpty ? planName : 'Free Plan';
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

  Widget _buildHero(BuildContext context) {
    final tokens = context.tokens;
    final primary = context.colors.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, tokens.primaryStrong],
        ),
        borderRadius: AppRadius.lgAll,
        boxShadow: tokens.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(
                initials: _initials,
                imageUrl: Env.mediaUrl(_profile?.profilePhotoUrl ?? ''),
                size: 52,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fullName,
                      style: context.text.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profile?.professionalHeadline.isNotEmpty ?? false
                          ? _profile!.professionalHeadline
                          : 'Personal Professional',
                      style: context.text.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
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
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Text(
                        _planDisplayName,
                        style: context.text.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Storage used',
                style: context.text.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              Text(
                '$_usagePercent%',
                style: context.text.bodySmall?.copyWith(
                  color: Colors.white,
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
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () => context.go(Routes.professionalProfile),
            borderRadius: AppRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'View Profile',
                    style: context.text.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: AppSize.iconRow,
                  ),
                ],
              ),
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
            info: 'Your own account, rather than your clients\'.\n\n'
                'SETTINGS\n'
                'Your public profile, sign-in security, notification '
                'preferences, how you take payments, and your plan.\n\n'
                'SUPPORT & LEGAL\n'
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
                onTap: () => context.go(Routes.professionalProfile),
              ),
              ColorfulMenuItem(
                icon: Icons.lock_outline,
                accent: MenuAccent.orange,
                label: 'Security',
                onTap: () => context.push(Routes.professionalSettingsSecurity),
              ),
              ColorfulMenuItem(
                icon: Icons.notifications_outlined,
                accent: MenuAccent.purple,
                label: 'Notifications',
                onTap: () =>
                    context.push('${Routes.professionalNotifications}/preferences'),
              ),
              ColorfulMenuItem(
                icon: Icons.payments_outlined,
                accent: MenuAccent.green,
                label: 'Payment Settings',
                onTap: () => context.push(Routes.professionalSettingsPayment),
              ),
              ColorfulMenuItem(
                icon: Icons.credit_card_outlined,
                accent: MenuAccent.teal,
                label: 'Plan & Billing',
                onTap: () => context.push(Routes.professionalSettingsBilling),
              ),
            ],
          ),

          const _Eyebrow('SUPPORT & LEGAL'),
          ColorfulMenuCard(
            items: [
              ColorfulMenuItem(
                icon: Icons.help_outline,
                accent: MenuAccent.blue,
                label: 'Support',
                onTap: () => context.go(Routes.professionalSupport),
              ),
              ColorfulMenuItem(
                icon: Icons.gavel_outlined,
                accent: MenuAccent.pink,
                label: 'About & Legal',
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
