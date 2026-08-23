import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/reproot_logo.dart';

/// Entry screen: pick a role. Stored sessions skip straight to the right shell.
/// Replica of mobile/src/app/pages/role-chooser/role-chooser.page.ts.
class RoleChooserPage extends ConsumerStatefulWidget {
  const RoleChooserPage({super.key});

  @override
  ConsumerState<RoleChooserPage> createState() => _RoleChooserPageState();
}

class _RoleChooserPageState extends ConsumerState<RoleChooserPage> {
  @override
  void initState() {
    super.initState();
    // Session cache is warmed in main(), so this resolves on the first frame
    // without a visible flash of the chooser.
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfSignedIn());
  }

  Future<void> _redirectIfSignedIn() async {
    if (!mounted) return;
    final professionalApi = ref.read(professionalAuthApiProvider);
    if (professionalApi.hasSession()) {
      // A published legal-document version can change between launches, and a
      // professional who has not accepted it gets a 403 on every screen. The
      // status endpoint is one of the few that still answers in that state, so
      // ask it here — the same check the web runs after login. A failure keeps
      // the old behaviour of going straight to the dashboard rather than
      // stranding an offline user on the chooser.
      var destination = Routes.professionalDashboard;
      try {
        final status = await professionalApi.getProfileStatus();
        destination = status.legalAcceptanceRequired
            ? Routes.professionalLegalConsent
            : status.profileSetupCompleted
            ? Routes.professionalDashboard
            : Routes.professionalProfileSetup;
      } catch (error, stackTrace) {
        debugPrint(
          'Professional destination check failed; using session fallback '
          '(${error.runtimeType})\n$stackTrace',
        );
      }
      if (!mounted) return;
      context.go(destination);
      return;
    }

    final clientApi = ref.read(clientApiProvider);
    if (!clientApi.hasSession()) return;

    // Restoring a session must honour the password and consent gates too,
    // otherwise a client could skip them by relaunching the app. Both read the
    // cached record, so this stays synchronous.
    final stored = clientApi.storedClient();
    if (!mounted) return;
    context.go(
      stored?.mustChangePassword ?? false
          ? Routes.clientChangePassword
          : !(stored?.legalAccepted ?? false)
          ? Routes.clientLegalConsent
          : Routes.clientDashboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = context.text;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448), // 28rem
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Brand(text: text),
                  const SizedBox(
                    height: AppSpacing.xxl + AppSpacing.sm,
                  ), // 2.5rem
                  _Choices(tokens: tokens, text: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const RepRootLogo(size: 64),
        const SizedBox(height: AppSpacing.md),
        // STUDIO-HIDDEN 2026-08-17: this wordmark read "RepRoot Studio"; the trailing
        // " Studio" TextSpan is commented out below. Matches the website
        // `brand__text`, which now also reads "RepRoot".
        Text.rich(
          TextSpan(
            style: text.displaySmall,
            children: [
              const TextSpan(text: 'Rep'),
              TextSpan(
                text: 'Root',
                style: TextStyle(color: context.colors.primary),
              ),
              // const TextSpan(text: ' Studio'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({required this.tokens, required this.text});

  final AppTokens tokens;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.screen),
      // Borderless: the shadow already separates this from the page, and a
      // hairline on top of it reads as belt-and-braces at this radius.
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.sheetAll,
        boxShadow: tokens.shadowMd,
      ),
      child: Column(
        children: [
          Text(
            'CONTINUE AS',
            style: text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.08 * 11,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push(Routes.professionalLogin),
              icon: const Icon(Icons.business_center_outlined),
              label: const Text('Professional'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push(Routes.clientLogin),
              icon: const Icon(Icons.person_outline),
              label: const Text('Client'),
            ),
          ),
        ],
      ),
    );
  }
}
