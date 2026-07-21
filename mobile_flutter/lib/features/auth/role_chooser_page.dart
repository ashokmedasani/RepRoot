import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';

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

  void _redirectIfSignedIn() {
    if (!mounted) return;
    if (ref.read(professionalAuthApiProvider).hasSession()) {
      context.go(Routes.professionalDashboard);
      return;
    }

    final clientApi = ref.read(clientApiProvider);
    if (!clientApi.hasSession()) return;

    // Restoring a session must honour the password gate too, otherwise a client
    // could skip it by relaunching the app.
    final stored = clientApi.storedClient();
    context.go(
      stored?.mustChangePassword ?? false
          ? Routes.clientChangePassword
          : Routes.clientDashboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;
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
                  _Brand(tokens: tokens, colors: colors, text: text),
                  const SizedBox(height: AppSpacing.xxl + AppSpacing.sm), // 2.5rem
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
  const _Brand({required this.tokens, required this.colors, required this.text});

  final AppTokens tokens;
  final ColorScheme colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: AppRadius.xlAll,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, tokens.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.22),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'CF',
            style: text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('RepRoot', style: text.displaySmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Professional & Client Management',
          style: text.bodyMedium?.copyWith(
            color: tokens.muted,
            fontWeight: FontWeight.w600,
          ),
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
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: tokens.border),
        boxShadow: tokens.shadowMd,
      ),
      child: Column(
        children: [
          Text(
            'CONTINUE AS',
            style: text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.08 * 11,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => context.push(Routes.professionalLogin),
            icon: const Icon(Icons.fitness_center),
            label: const Text('Professional'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.clientLogin),
            icon: const Icon(Icons.person_outline),
            label: const Text('Client'),
          ),
        ],
      ),
    );
  }
}
