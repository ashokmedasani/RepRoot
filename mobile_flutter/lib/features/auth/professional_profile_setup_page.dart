import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';

/// Required first-login step, matching the web portal and the setup mode added
/// to the Ionic profile page (`/professional/tabs/more/profile?setup=1`).
///
/// This gate exists for a reason: a professional who reaches the dashboard without a
/// professional code has clients who can never log in, since the client login form
/// requires that code.
class ProfessionalProfileSetupPage extends ConsumerStatefulWidget {
  const ProfessionalProfileSetupPage({super.key});

  @override
  ConsumerState<ProfessionalProfileSetupPage> createState() =>
      _ProfessionalProfileSetupPageState();
}

class _ProfessionalProfileSetupPageState
    extends ConsumerState<ProfessionalProfileSetupPage> {
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _professionalCode = TextEditingController();
  final _country = TextEditingController();
  final _state = TextEditingController();

  String _gender = '';
  int? _birthMonth;
  int? _birthYear;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String _message = '';
  String _codeMessage = '';
  bool _codeAvailable = false;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  List<int> get _years {
    final now = DateTime.now().year;
    // 18+ down to a 100-year window, newest first.
    return List.generate(83, (i) => now - 18 - i);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _professionalCode.dispose();
    _country.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ref.read(professionalAuthApiProvider).getProfile();
      if (!mounted) return;
      setState(() {
        _firstName.text = profile.firstName;
        _middleName.text = profile.middleName;
        _lastName.text = profile.lastName;
        _professionalCode.text =
            profile.professionalId.isNotEmpty ? profile.professionalId : profile.professionalCode;
        _country.text = profile.country;
        _state.text = profile.state;
        _gender = _genders.contains(profile.gender) ? profile.gender : '';
        _birthMonth = profile.birthMonth;
        _birthYear = profile.birthYear;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkCode() async {
    final code = _professionalCode.text.trim();
    if (code.isEmpty) {
      setState(() {
        _codeMessage = 'Enter a professional code first.';
        _codeAvailable = false;
      });
      return;
    }
    try {
      final available = await ref.read(professionalAuthApiProvider).checkProfessionalCode(code);
      if (!mounted) return;
      setState(() {
        _codeAvailable = available;
        _codeMessage = available
            ? 'That code is available.'
            : 'That code is already taken.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _codeAvailable = false;
        _codeMessage = error.message;
      });
    }
  }

  /// Client-side required-field messages, mirroring the Ionic setup mode.
  String _validate() {
    if (_firstName.text.trim().isEmpty) return 'First name is required.';
    if (_lastName.text.trim().isEmpty) return 'Last name is required.';
    if (_professionalCode.text.trim().isEmpty) {
      return 'Professional code is required — your clients use it to sign in.';
    }
    if (_gender.isEmpty) return 'Gender is required.';
    if (_birthMonth == null || _birthYear == null) {
      return 'Birth month and year are required.';
    }
    if (_country.text.trim().isEmpty) return 'Country is required.';
    if (_state.text.trim().isEmpty) return 'State is required.';
    return '';
  }

  Future<void> _save() async {
    final validation = _validate();
    if (validation.isNotEmpty) {
      setState(() => _message = validation);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = '';
    });

    // Multipart PUT with the same keys the Ionic profile page sends.
    final form = FormData.fromMap({
      'professional_id': _professionalCode.text.trim(),
      'first_name': _firstName.text.trim(),
      'middle_name': _middleName.text.trim(),
      'last_name': _lastName.text.trim(),
      'gender': _gender,
      'country': _country.text.trim(),
      'state': _state.text.trim(),
      'birth_month': '$_birthMonth',
      'birth_year': '$_birthYear',
    });

    try {
      await ref.read(professionalAuthApiProvider).saveProfile(form);
      if (!mounted) return;
      context.go(Routes.professionalDashboard);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finish your profile'),
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
                  const SizedBox(height: AppSpacing.sm),
                  const AuthBrand(
                    title: 'Almost there',
                    subtitle:
                        'Your clients need these details before they can sign in',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextField(
                    controller: _firstName,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _middleName,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(labelText: 'Middle name (optional)'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _lastName,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _professionalCode,
                          enabled: !_isSubmitting,
                          autocorrect: false,
                          onChanged: (_) => setState(() {
                            _codeMessage = '';
                            _codeAvailable = false;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Professional code',
                            helperText: 'Clients type this to reach you',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : _checkCode,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(88, AppSize.buttonHeightSm),
                          ),
                          child: const Text('Check'),
                        ),
                      ),
                    ],
                  ),
                  if (_codeMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        _codeMessage,
                        style: context.text.bodySmall?.copyWith(
                          color: _codeAvailable
                              ? context.tokens.success
                              : context.colors.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: _gender.isEmpty ? null : _gender,
                    decoration: const InputDecoration(labelText: 'Gender'),
                    items: _genders
                        .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _gender = value ?? ''),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _birthMonth,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Birth month'),
                          items: [
                            for (var i = 0; i < _months.length; i++)
                              DropdownMenuItem(
                                value: i + 1,
                                child: Text(_months[i]),
                              ),
                          ],
                          onChanged: _isSubmitting
                              ? null
                              : (value) => setState(() => _birthMonth = value),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _birthYear,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Birth year'),
                          items: _years
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y'),
                                  ))
                              .toList(),
                          onChanged: _isSubmitting
                              ? null
                              : (value) => setState(() => _birthYear = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _country,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _state,
                    enabled: !_isSubmitting,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _save,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save and continue'),
                  ),
                  FormMessage(message: _message),
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
