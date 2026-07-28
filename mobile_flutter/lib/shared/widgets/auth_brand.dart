import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// RepRoot brand mark and heading used across authentication screens.
class AuthBrand extends StatelessWidget {
  const AuthBrand({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Column(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Image.asset(
            'assets/icon/icon.png',
            fit: BoxFit.contain,
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
