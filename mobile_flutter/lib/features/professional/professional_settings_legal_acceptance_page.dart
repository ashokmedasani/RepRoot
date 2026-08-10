import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models/legal_models.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Legal Acceptance — what this account last accepted, plus the
/// account-deletion informational card.
/// Renamed/trimmed from the former professional_settings_privacy_legal_page.dart
/// (ProfessionalSettingsPrivacyLegalPage): the Terms/Privacy document links
/// that used to live here moved to professional_support_legal_page.dart
/// (More ▸ About & Legal), which is now the only way to reach this page.
class ProfessionalSettingsLegalAcceptancePage extends ConsumerStatefulWidget {
  const ProfessionalSettingsLegalAcceptancePage({super.key});

  @override
  ConsumerState<ProfessionalSettingsLegalAcceptancePage> createState() =>
      _ProfessionalSettingsLegalAcceptancePageState();
}

class _ProfessionalSettingsLegalAcceptancePageState
    extends ConsumerState<ProfessionalSettingsLegalAcceptancePage> {
  ProfessionalProfile? _profile;

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
        'Legal acceptance details load failed '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
  }

  /// Newest acceptance record, falling back to `terms_accepted_at` for accounts
  /// that predate the acceptance-record table — the same fallback the web
  /// template uses.
  String get _lastLegalAcceptance {
    final history = _profile?.legalAcceptanceHistory ?? const [];
    if (history.isNotEmpty && history.first.acceptedAt.isNotEmpty) {
      return dateTimeLabel(history.first.acceptedAt);
    }
    final accepted = _profile?.termsAcceptedAt ?? '';
    return accepted.isEmpty ? 'Not recorded' : dateTimeLabel(accepted);
  }

  String get _acceptedLegalVersion {
    final history = _profile?.legalAcceptanceHistory ?? const [];
    if (history.isNotEmpty && history.first.legalDocumentVersion.isNotEmpty) {
      return history.first.legalDocumentVersion;
    }
    final version = _profile?.legalDocumentVersion ?? '';
    return version.isEmpty ? 'Not recorded' : version;
  }

  /// Full acceptance history, newest first, beyond just the latest record.
  List<LegalAcceptanceEntry> get _history =>
      _profile?.legalAcceptanceHistory ?? const [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal Acceptance'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          const SettingsHeroCard(
            icon: Icons.verified_user_outlined,
            title: 'Legal Acceptance',
            subtitle: 'Stay updated with our legal documents.',
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Legal Acceptance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KvList(
                  rows: [
                    ('Last legal acceptance', _lastLegalAcceptance),
                    ('Accepted document version', _acceptedLegalVersion),
                  ],
                ),
                if (_history.length > 1) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'ACCEPTANCE HISTORY',
                    style: context.text.labelSmall?.copyWith(
                      color: context.tokens.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final record in _history.skip(1))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              record.acceptedAt.isEmpty
                                  ? 'Not recorded'
                                  : dateTimeLabel(record.acceptedAt),
                              style: context.text.bodySmall,
                            ),
                          ),
                          Text(
                            record.legalDocumentVersion.isEmpty
                                ? '—'
                                : record.legalDocumentVersion,
                            style: context.text.bodySmall?.copyWith(
                              color: context.tokens.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _Card(
            title: 'Account deletion',
            child: Text(
              'Professional accounts are deleted through support so your client data '
              'is handled safely. Open Help and Support from the More tab to '
              'request deletion.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Titled surface — the .card rule.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Label/value rows — the .kv-list rule.
class _KvList extends StatelessWidget {
  const _KvList({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(label, style: context.text.bodySmall),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    value.trim().isEmpty ? '—' : value,
                    style: context.text.titleSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
