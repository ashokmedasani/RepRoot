import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/auth_brand.dart';
import '../../shared/widgets/password_field.dart';

/// Replica of mobile/src/app/pages/client/login/client-login.page.ts.
///
/// The forced first-login password change is not gated here — same as the Ionic
/// app, login lands on the dashboard and the client tab shell enforces
/// must_change_password. That shell arrives in Phase 5.
class ClientLoginPage extends ConsumerStatefulWidget {
  const ClientLoginPage({super.key});

  @override
  ConsumerState<ClientLoginPage> createState() => _ClientLoginPageState();
}

class _ClientLoginPageState extends ConsumerState<ClientLoginPage> {
  final _professionalCode = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _directorySearch = TextEditingController();

  bool _isSubmitting = false;
  String _message = '';

  bool _showDirectory = false;
  bool _directoryLoaded = false;
  List<ProfessionalDirectoryEntry> _directory = [];

  @override
  void dispose() {
    _professionalCode.dispose();
    _username.dispose();
    _password.dispose();
    _directorySearch.dispose();
    super.dispose();
  }

  /// Filters the loaded list client-side, matching the Ionic getter.
  List<ProfessionalDirectoryEntry> get _filteredProfessionals {
    final term = _directorySearch.text.trim().toLowerCase();
    if (term.isEmpty) return _directory;
    return _directory
        .where((t) =>
            t.professionalName.toLowerCase().contains(term) ||
            t.professionalId.toLowerCase().contains(term))
        .toList();
  }

  Future<void> _toggleDirectory() async {
    setState(() => _showDirectory = !_showDirectory);
    if (!_showDirectory || _directoryLoaded) return;

    try {
      final professionals = await ref.read(clientApiProvider).getProfessionalDirectory();
      if (!mounted) return;
      setState(() {
        _directory = professionals;
        _directoryLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _directory = []);
    }
  }

  void _pickProfessional(ProfessionalDirectoryEntry professional) {
    setState(() {
      _professionalCode.text = professional.professionalId;
      _showDirectory = false;
    });
  }

  Future<void> _login() async {
    if (_professionalCode.text.trim().isEmpty ||
        _username.text.trim().isEmpty ||
        _password.text.isEmpty) {
      setState(() =>
          _message = 'Professional code, username, and password are all required.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = '';
    });

    final api = ref.read(clientApiProvider);
    try {
      final response = await api.login(
        _professionalCode.text.trim(),
        _username.text.trim().toLowerCase(),
        _password.text,
      );
      final client = response.client;
      if (client == null) {
        setState(() {
          _message = 'Login failed. Please try again.';
          _isSubmitting = false;
        });
        return;
      }
      await api.storeSession(response.token, client);
      if (!mounted) return;
      // A professional-issued temporary password must be replaced before the client
      // can use the app. The Ionic app skipped this and went straight to the
      // dashboard; the web portal gates here, and so do we.
      context.go(
        client.mustChangePassword
            ? Routes.clientChangePassword
            : Routes.clientDashboard,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Client Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screen),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 448),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    const AuthBrand(
                      title: 'Client sign in',
                      subtitle: 'Use the details your professional shared with you',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _professionalCode,
                      enabled: !_isSubmitting,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Professional code',
                        suffixIcon: IconButton(
                          onPressed: _isSubmitting ? null : _toggleDirectory,
                          icon: Icon(
                            _showDirectory
                                ? Icons.expand_less
                                : Icons.search_outlined,
                          ),
                          iconSize: AppSize.iconRow,
                          tooltip: "Find your professional's code",
                        ),
                      ),
                    ),
                    if (_showDirectory) _buildDirectory(),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _username,
                      enabled: !_isSubmitting,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PasswordField(
                      controller: _password,
                      enabled: !_isSubmitting,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: _isSubmitting ? null : _login,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _login,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    FormMessage(message: _message),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectory() {
    final tokens = context.tokens;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _directorySearch,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Search professionals by name or code',
              prefixIcon: Icon(Icons.search, size: AppSize.iconRow),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!_directoryLoaded)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_filteredProfessionals.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'No professionals found.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _filteredProfessionals.length,
                separatorBuilder: (_, _) => Divider(color: tokens.border),
                itemBuilder: (context, index) {
                  final professional = _filteredProfessionals[index];
                  return ListTile(
                    dense: true,
                    title: Text(professional.professionalName,
                        style: context.text.titleSmall),
                    subtitle: Text(
                      professional.professionalHeadline.isEmpty
                          ? professional.professionalId
                          : '${professional.professionalId} · ${professional.professionalHeadline}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _pickProfessional(professional),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
