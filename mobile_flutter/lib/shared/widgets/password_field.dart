import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// Password input with a show/hide toggle.
/// Port of mobile/src/app/shared/password-input.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.enabled = true,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      enabled: widget.enabled,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _visible = !_visible),
          icon: Icon(_visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          iconSize: AppSize.iconRow,
          tooltip: _visible ? 'Hide password' : 'Show password',
        ),
      ),
    );
  }
}
