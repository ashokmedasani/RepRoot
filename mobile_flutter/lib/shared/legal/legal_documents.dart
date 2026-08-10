import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';

/// Which audience's documents to show. The web app publishes a separate pair
/// per audience (/terms/professional, /privacy/client, …) — see the four legal
/// routes in frontend/src/app/app.routes.ts.
enum LegalAudience { professional, client }

extension LegalAudienceX on LegalAudience {
  String get slug =>
      this == LegalAudience.professional ? 'professional' : 'client';

  String get termsTitle => this == LegalAudience.professional
      ? 'Professional Terms and Conditions'
      : 'Client Terms and Conditions';

  String get termsSummary => this == LegalAudience.professional
      ? 'Account, client-data, payment, and platform responsibilities.'
      : 'Responsibilities, professional relationship, payments, and safety.';

  String get privacyTitle => this == LegalAudience.professional
      ? 'Professional Privacy Notice'
      : 'Client Privacy Notice';

  String get privacySummary => this == LegalAudience.professional
      ? 'How professional and client information is processed.'
      : 'What RepRoot processes, what your professional controls, and your choices.';

  /// The sentence next to the accept checkbox, copied from the web templates.
  String get consentLabel => this == LegalAudience.professional
      ? 'I have reviewed and accept the Professional Terms and Conditions and '
            'Professional Privacy Notice.'
      : 'I have reviewed and accept the Client Terms and Conditions and Client '
            'Privacy Notice.';

  String get termsUrl => Env.legalDocumentUrl('terms', slug);
  String get privacyUrl => Env.legalDocumentUrl('privacy', slug);
}

/// Opens a published legal document in the browser.
///
/// The documents are static pages in the Angular app (pages/legal/legal.component),
/// not API content, so there is nothing to render in-app without shipping a
/// second copy of the text that could drift from the published version.
Future<void> openLegalDocument(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the document. Try again.'),
        ),
      );
    }
  }
}

/// The two document cards shown on the consent screens and in signup —
/// the `.document-links` / `.legal-links` blocks in the web templates.
class LegalDocumentLinks extends StatelessWidget {
  const LegalDocumentLinks({super.key, required this.audience});

  final LegalAudience audience;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LegalLinkTile(
          title: audience.termsTitle,
          summary: audience.termsSummary,
          url: audience.termsUrl,
        ),
        const SizedBox(height: AppSpacing.sm),
        _LegalLinkTile(
          title: audience.privacyTitle,
          summary: audience.privacySummary,
          url: audience.privacyUrl,
        ),
      ],
    );
  }
}

/// The accept checkbox — the `.legal-check` label in the web templates. The
/// whole row is tappable, matching the signup screen's existing terms row.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: enabled ? (next) => onChanged(next ?? false) : null,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(label, style: context.text.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalLinkTile extends StatelessWidget {
  const _LegalLinkTile({
    required this.title,
    required this.summary,
    required this.url,
  });

  final String title;
  final String summary;
  final String url;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return InkWell(
      onTap: () => openLegalDocument(context, url),
      borderRadius: AppRadius.mdAll,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.card),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    summary,
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.open_in_new, size: AppSize.iconRow, color: tokens.muted),
          ],
        ),
      ),
    );
  }
}
