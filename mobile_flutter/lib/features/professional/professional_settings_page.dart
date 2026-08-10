import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Settings — lightweight menu/landing page that fans out into the
/// per-category Settings pages (Security, Notifications, Payment Settings,
/// Plan & Billing, Data Usage), mirroring the grouping on the web's
/// professional-account-settings component. Each row pushes a dedicated page
/// that owns its own state/logic, rather than one giant single-scroll page.
///
/// "My Account" points to the full profile viewer/editor so account identity
/// and professional details live in one place on mobile, as they do on web.
/// "Recycle Bin" and "Privacy & Legal" also moved off this landing page — the
/// former now lives inside Data Usage, the latter inside More ▸ About & Legal.
class ProfessionalSettingsPage extends StatelessWidget {
  const ProfessionalSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(
          onPressed: () => context.go(Routes.professionalMore),
        ),
      ),
      body: PagePad(
        children: [
          const SettingsHeroCard(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Manage your account, preferences and configurations.',
          ),
          const SizedBox(height: AppSpacing.lg),
          ColorfulMenuCard(
            items: [
              ColorfulMenuItem(
                icon: Icons.person_outline,
                accent: MenuAccent.blue,
                label: 'My Account',
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
                onTap: () => context.push(
                  '${Routes.professionalNotifications}/preferences',
                ),
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
                label: 'Plan and Billing',
                onTap: () => context.push(Routes.professionalSettingsBilling),
              ),
              ColorfulMenuItem(
                icon: Icons.storage_outlined,
                accent: MenuAccent.pink,
                label: 'Data Usage',
                onTap: () =>
                    context.push(Routes.professionalSettingsPlanStorage),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
