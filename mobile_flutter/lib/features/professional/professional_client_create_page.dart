import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Manual client creation — pick a group, enter identity + username, optionally
/// email the temporary credentials; shows the generated password on success.
/// Replica of mobile/src/app/pages/trainer/client-create/client-create.page.ts.
class TrainerClientCreatePage extends ConsumerStatefulWidget {
  const TrainerClientCreatePage({super.key});

  @override
  ConsumerState<TrainerClientCreatePage> createState() =>
      _TrainerClientCreatePageState();
}

class _TrainerClientCreatePageState
    extends ConsumerState<TrainerClientCreatePage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  List<TrainerGroup> _groups = [];
  int _groupId = 0;
  bool _sendCredentials = true;
  bool _isSaving = false;
  String _message = '';

  String _createdPassword = '';
  String _createdUsername = '';
  bool _credentialsSent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final overview = await ref.read(formsGroupsApiProvider).getOverview();
      if (!mounted) return;
      setState(() {
        _groups = overview.groups;
        // Pre-select when there is no real choice to make.
        if (overview.groups.length == 1) _groupId = overview.groups.first.id;
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not load groups.');
    }
  }

  bool get _canSave =>
      _groupId > 0 &&
      _firstName.text.trim().isNotEmpty &&
      _lastName.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      _password.text.trim().length >= 8;

  /// Mirrors the TS generator: an unambiguous alphabet (no O/0, l/1) so a
  /// password read aloud or copied by hand still works, plus a guaranteed
  /// special character to satisfy the backend's strength rule.
  void _generatePassword() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    final value = List.generate(
      10,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    setState(() {
      _password.text = '${value.substring(0, 8)}!${value.substring(8)}';
    });
  }

  Future<void> _save() async {
    if (!_canSave || _isSaving) return;

    setState(() {
      _isSaving = true;
      _message = '';
    });

    final answers = <String, String>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'email': _email.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone_number': _phone.text.trim(),
    };

    try {
      final result = await ref.read(formsGroupsApiProvider).createManualClient(
            ClientAccessPayload(
              groupId: _groupId,
              username: _username.text.trim(),
              password: _password.text.trim(),
              confirmPassword: _password.text.trim(),
              registrationAnswers: answers,
              sendCredentials: _sendCredentials,
            ),
          );
      if (!mounted) return;
      setState(() {
        _createdPassword = result.temporaryPassword;
        _createdUsername = result.clientAccess.username.isNotEmpty
            ? result.clientAccess.username
            : _username.text.trim();
        _credentialsSent = result.credentialsSent;
        _isSaving = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.message;
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Client'),
        leading: BackButton(onPressed: () => context.go(Routes.trainerClients)),
      ),
      body: PagePad(
        children: [
          if (_createdPassword.isNotEmpty)
            _CreatedCard(
              username: _createdUsername,
              password: _createdPassword,
              credentialsSent: _credentialsSent,
              onDone: () => context.go(Routes.trainerClients),
            )
          else
            _Form(
              groups: _groups,
              groupId: _groupId,
              firstName: _firstName,
              lastName: _lastName,
              email: _email,
              phone: _phone,
              username: _username,
              password: _password,
              sendCredentials: _sendCredentials,
              isSaving: _isSaving,
              canSave: _canSave,
              message: _message,
              onGroup: (value) => setState(() => _groupId = value),
              onSendCredentials: (value) =>
                  setState(() => _sendCredentials = value),
              onChanged: () => setState(() {}),
              onGenerate: _generatePassword,
              onSave: _save,
            ),
        ],
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.groups,
    required this.groupId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.username,
    required this.password,
    required this.sendCredentials,
    required this.isSaving,
    required this.canSave,
    required this.message,
    required this.onGroup,
    required this.onSendCredentials,
    required this.onChanged,
    required this.onGenerate,
    required this.onSave,
  });

  final List<TrainerGroup> groups;
  final int groupId;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController email;
  final TextEditingController phone;
  final TextEditingController username;
  final TextEditingController password;
  final bool sendCredentials;
  final bool isSaving;
  final bool canSave;
  final String message;
  final ValueChanged<int> onGroup;
  final ValueChanged<bool> onSendCredentials;
  final VoidCallback onChanged;
  final VoidCallback onGenerate;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New client', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),

          DropdownButtonFormField<int>(
            initialValue: groupId > 0 ? groupId : null,
            decoration: const InputDecoration(labelText: 'Group'),
            hint: const Text('Select a group'),
            items: groups
                .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                .toList(),
            onChanged: (value) => onGroup(value ?? 0),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: firstName,
                  onChanged: (_) => onChanged(),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: lastName,
                  onChanged: (_) => onChanged(),
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: email,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: username,
            onChanged: (_) => onChanged(),
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Username'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: password,
                  onChanged: (_) => onChanged(),
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: OutlinedButton(
                  onPressed: onGenerate,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(92, AppSize.buttonHeightSm),
                  ),
                  child: const Text('Generate'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: () => onSendCredentials(!sendCredentials),
            borderRadius: AppRadius.smAll,
            child: Row(
              children: [
                Checkbox(
                  value: sendCredentials,
                  onChanged: (value) => onSendCredentials(value ?? false),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Text(
                    'Email the temporary credentials to the client',
                    style: context.text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Minimum 8 characters. The client must change this password on '
            'first login. The group needs an active registration form.',
            style: context.text.bodySmall,
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: message),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: canSave && !isSaving ? onSave : null,
            child: Text(isSaving ? 'Creating…' : 'Create Client'),
          ),
        ],
      ),
    );
  }
}

class _CreatedCard extends StatelessWidget {
  const _CreatedCard({
    required this.username,
    required this.password,
    required this.credentialsSent,
    required this.onDone,
  });

  final String username;
  final String password;
  final bool credentialsSent;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, color: tokens.success, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text('Client created', style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Share these one-time credentials. The client must change the '
            'password on first login.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          _Kv(label: 'Username', value: username),
          _Kv(label: 'Temporary password', value: password, mono: true),
          _Kv(
            label: 'Credentials emailed',
            value: credentialsSent ? 'Yes' : 'No',
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            flex: 3,
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: mono
                  ? context.text.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 0.5,
                    )
                  : context.text.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
