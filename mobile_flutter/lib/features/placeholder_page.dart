import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../core/api/client_api.dart';
import '../core/api/trainer_auth_api.dart';
import '../core/theme/app_tokens.dart';

/// Stand-in for a screen that has not been migrated yet.
///
/// Phase 2 only proves the auth path end to end; the real screens land in
/// Phases 4 (trainer) and 5 (client). Sign out is wired here so the login
/// flows can be tested repeatedly without reinstalling.
class PlaceholderPage extends ConsumerWidget {
  const PlaceholderPage({super.key, required this.title, required this.phase});

  final String title;
  final String phase;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final trainerApi = ref.read(trainerAuthApiProvider);
    final clientApi = ref.read(clientApiProvider);

    if (trainerApi.hasSession()) {
      // Best effort: a failed server logout must not strand the user signed in.
      try {
        await trainerApi.logout();
      } catch (_) {}
      await trainerApi.clearSession();
    } else if (clientApi.hasSession()) {
      try {
        await clientApi.logout();
      } catch (_) {}
      await clientApi.clearSession();
    }

    if (context.mounted) context.go(Routes.roleChooser);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: tokens.primarySoft,
                  borderRadius: AppRadius.lgAll,
                ),
                child: Icon(
                  Icons.construction_outlined,
                  color: context.colors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(height: AppSpacing.screen),
              Text(title, style: context.text.titleLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Signed in successfully.\nThis screen is migrated in $phase.',
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(color: tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
