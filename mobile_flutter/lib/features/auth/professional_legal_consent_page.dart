import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/legal/legal_documents.dart';
import '../../shared/widgets/auth_brand.dart';
import '../professional/professional_format.dart';

/// Professional re-consent gate.
///
/// Port of frontend/src/app/pages/studio/professional/professional-legal-consent.
/// The backend publishes a legal version (`REPROOT_PROFESSIONAL_LEGAL_VERSION`);
/// ProfessionalAccessPermission refuses every professional endpoint that is not
/// marked `allow_outdated_legal` until the signed-in professional has accepted
/// that exact version. Without this screen a version bump would lock the mobile
/// app out with a bare 403 and no way to accept.
class ProfessionalLegalConsentPage extends ConsumerStatefulWidget {
  const ProfessionalLegalConsentPage({super.key});

  @override
  ConsumerState<ProfessionalLegalConsentPage> createState() =>
      _ProfessionalLegalConsentPageState();
}

class _ProfessionalLegalConsentPageState
    extends ConsumerState<ProfessionalLegalConsentPage> {
  bool _accepted = false;
  bool _submitting = false;
  String _message = '';
  String _version = '';
  String _effectiveDate = '';

  @override
  void initState() {
    super.initState();
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    try {
      final configuration =
          await ref.read(professionalAuthApiProvider).getLegalConfiguration();
      if (!mounted) return;
      setState(() {
        _version = configuration.professionalVersion;
        _effectiveDate = configuration.effectiveDate;
      });
    } catch (_) {
      // The version banner is informational; the accept action does not need it
      // (the web component also ignores this failure).
    }
  }

  Future<void> _submit() async {
    if (!_accepted || _submitting) return;
    setState(() {
      _submitting = true;
      _message = '';
    });

    try {
      await ref.read(professionalAuthApiProvider).acceptLegalDocuments();
      // Clears the mid-session 403 flag so the router stops redirecting here.
      ref.read(sessionStoreProvider).clearLegalConsentFlag();
      if (!mounted) return;
      context.go(Routes.professionalDashboard);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _message = error.message.isEmpty
            ? 'Legal acceptance could not be saved.'
            : error.message;
      });
    }
  }

  /// Not in the web component: on the web a professional who will not accept can
  /// simply navigate away, but a mobile gate with no exit would trap them in the
  /// app with no way to sign out. This clears the session only — it accepts
  /// nothing and changes no server state.
  Future<void> _signOut() async {
    final api = ref.read(professionalAuthApiProvider);
    try {
      await api.logout();
    } catch (_) {
      // Signing out locally matters more than the server round-trip.
    }
    await api.clearSession();
    if (!mounted) return;
    context.go(Routes.professionalLogin);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal review'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  const AuthBrand(
                    title: 'Review before continuing',
                    subtitle:
                        'RepRoot Studio has published a new legal-document '
                        'version. Your earlier acceptance remains in your '
                        'account history.',
                  ),
                  if (_version.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Effective ${_effectiveDate.isEmpty ? '—' : longDate(_effectiveDate)} '
                      '· Version $_version',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const LegalDocumentLinks(
                    audience: LegalAudience.professional,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LegalConsentCheckbox(
                    value: _accepted,
                    enabled: !_submitting,
                    label: LegalAudience.professional.consentLabel,
                    onChanged: (value) => setState(() => _accepted = value),
                  ),
                  FormMessage(message: _message),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _accepted && !_submitting ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accept and Continue'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _submitting ? null : _signOut,
                    child: const Text('Not now — sign out'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
