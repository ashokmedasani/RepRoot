import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/session/session_store.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/legal/legal_documents.dart';
import '../../shared/widgets/app_widgets.dart';
import '../../shared/widgets/auth_brand.dart';
import '../professional/professional_format.dart';

/// Client consent gate — first login and after a published version bump.
///
/// Port of frontend/src/app/pages/studio/client/client-legal-consent. Sits next
/// to [ClientChangePasswordPage] rather than under features/auth because, like
/// that screen, it runs with a valid client session and gates the portal.
///
/// IsAuthenticatedClient refuses every client endpoint that is not marked
/// `allow_outdated_legal` until the stored version matches
/// `REPROOT_CLIENT_LEGAL_VERSION`.
class ClientLegalConsentPage extends ConsumerStatefulWidget {
  const ClientLegalConsentPage({super.key});

  @override
  ConsumerState<ClientLegalConsentPage> createState() =>
      _ClientLegalConsentPageState();
}

class _ClientLegalConsentPageState
    extends ConsumerState<ClientLegalConsentPage> {
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
      final configuration = await ref
          .read(clientApiProvider)
          .getLegalConfiguration();
      if (!mounted) return;
      setState(() {
        _version = configuration.clientVersion;
        _effectiveDate = configuration.effectiveDate;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Client legal configuration load failed (${error.runtimeType})\n$stackTrace',
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_accepted) {
      setState(
        () => _message =
            'Review and accept the Client Terms and Conditions and Privacy Notice '
            'to continue.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _message = '';
    });

    final api = ref.read(clientApiProvider);
    try {
      final client = await api.acceptLegalDocuments();
      // The web writes the response back to sessionStorage here; the cached
      // record is what the router's consent gate reads, so it must be
      // refreshed or the gate would bounce straight back to this page.
      await api.storeClient(client);
      // Clears the mid-session 403 flag so the router stops redirecting here.
      ref.read(sessionStoreProvider).clearLegalConsentFlag();
      if (!mounted) return;
      context.go(Routes.clientDashboard);
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

  /// Not in the web component — see the note on the professional consent page.
  /// A mobile gate needs an exit that is not "accept".
  Future<void> _signOut() async {
    final api = ref.read(clientApiProvider);
    try {
      await api.logout();
    } catch (error, stackTrace) {
      debugPrint(
        'Client server logout failed; clearing local session '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
    await api.clearSession();
    if (!mounted) return;
    context.go(Routes.clientLogin);
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
                    title: 'Review how RepRoot Studio works',
                    subtitle:
                        'Before entering the client portal, review the '
                        'documents that apply specifically to clients.',
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

                  // The `.relationship-note` callout in the web template.
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your professional manages your coaching relationship.',
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'RepRoot Studio provides the software. Your '
                          'professional decides what information and activities '
                          'to request.',
                          style: context.text.bodySmall?.copyWith(
                            color: tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  const LegalDocumentLinks(audience: LegalAudience.client),
                  const SizedBox(height: AppSpacing.md),
                  LegalConsentCheckbox(
                    value: _accepted,
                    enabled: !_submitting,
                    label: LegalAudience.client.consentLabel,
                    onChanged: (value) => setState(() {
                      _accepted = value;
                      if (value) _message = '';
                    }),
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
