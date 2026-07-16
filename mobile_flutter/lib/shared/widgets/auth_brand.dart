import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// The "CF" gradient mark + heading used across the auth screens.
/// Port of the .login-brand block in the Ionic login/signup pages.
class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = context.colors;

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, tokens.accent],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.22),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'CF',
            style: context.text.titleLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: context.text.displaySmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: context.text.bodyMedium?.copyWith(
            color: tokens.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Inline form error text — the .error-text rule in the Ionic pages.
class FormMessage extends StatelessWidget {
  const FormMessage({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.text.labelMedium?.copyWith(
          color: isError ? context.colors.error : context.tokens.success,
        ),
      ),
    );
  }
}
