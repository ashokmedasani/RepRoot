import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/legal/legal_documents.dart';
import '../../shared/widgets/app_widgets.dart';

/// Support & Legal — help, app info, and the legal document links, split out
/// of the old single "Privacy & Legal" settings page so it can live one tap
/// from More instead of buried inside Settings. Legal *acceptance history*
/// (not the documents themselves) stays in its own page — see
/// professional_settings_legal_acceptance_page.dart.
class ProfessionalSupportLegalPage extends StatelessWidget {
  const ProfessionalSupportLegalPage({super.key});

  void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About', style: context.text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Text('RepRoot', style: context.text.titleMedium),
              const SizedBox(height: 2),
              // Straight from pubspec.yaml's version: field — no update-check
              // or changelog feature exists, so this is the only real "About"
              // content there is.
              Text(
                'Version 1.0.0 (1)',
                style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support & Legal'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        children: [
          const SettingsHeroCard(
            icon: Icons.gavel_outlined,
            title: 'Support & Legal',
            subtitle: 'Get help and review your legal documents.',
          ),
          const SizedBox(height: AppSpacing.lg),
          ColorfulMenuCard(
            items: [
              ColorfulMenuItem(
                icon: Icons.help_outline,
                accent: MenuAccent.blue,
                label: 'Support',
                onTap: () => context.go(Routes.professionalSupport),
              ),
              ColorfulMenuItem(
                icon: Icons.info_outline,
                accent: MenuAccent.teal,
                label: 'About',
                onTap: () => _showAbout(context),
              ),
              ColorfulMenuItem(
                icon: Icons.description_outlined,
                accent: MenuAccent.purple,
                label: 'Terms & Conditions',
                onTap: () =>
                    openLegalDocument(context, LegalAudience.professional.termsUrl),
              ),
              ColorfulMenuItem(
                icon: Icons.privacy_tip_outlined,
                accent: MenuAccent.green,
                label: 'Privacy Policy',
                onTap: () =>
                    openLegalDocument(context, LegalAudience.professional.privacyUrl),
              ),
              ColorfulMenuItem(
                icon: Icons.fact_check_outlined,
                accent: MenuAccent.orange,
                label: 'Legal Acceptance',
                onTap: () =>
                    context.push(Routes.professionalSettingsLegalAcceptance),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
