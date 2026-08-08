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
import 'professional_format.dart';

/// Manual client creation — pick a group, fill in that group's configured
/// registration form, then optionally email the temporary credentials; shows
/// the generated password on success.
/// Replica of frontend/src/app/pages/studio/professional/professional-manual-client-create.
class ProfessionalClientCreatePage extends ConsumerStatefulWidget {
  const ProfessionalClientCreatePage({super.key});

  @override
  ConsumerState<ProfessionalClientCreatePage> createState() =>
      _ProfessionalClientCreatePageState();
}

class _ProfessionalClientCreatePageState
    extends ConsumerState<ProfessionalClientCreatePage> {
  final _username = TextEditingController();
  final _password = TextEditingController();

  /// One controller per free-text registration field, rebuilt whenever the
  /// selected group changes (its form is a different set of fields).
  final Map<String, TextEditingController> _fieldControllers = {};

  /// The payload's registration_answers, keyed exactly as the web keys them
  /// (field.key, falling back to the label).
  final Map<String, String> _answers = {};

  List<ProfessionalGroup> _groups = [];
  int _groupId = 0;
  bool _sendCredentials = true;
  bool _loading = true;
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
    _username.dispose();
    _password.dispose();
    _disposeFieldControllers();
    super.dispose();
  }

  void _disposeFieldControllers() {
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    _fieldControllers.clear();
  }

  Future<void> _load() async {
    try {
      final overview = await ref.read(formsGroupsApiProvider).getOverview();
      if (!mounted) return;
      setState(() {
        // A group without a registration form cannot take a client — the web
        // filters them out of the picker for the same reason.
        _groups = overview.groups
            .where((group) => group.hasRegistrationForm)
            .toList();
        _loading = false;
        // Pre-select when there is no real choice to make.
        if (_groups.length == 1) _groupId = _groups.first.id;
      });
      _rebuildFieldControllers();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Could not load groups.';
          _loading = false;
        });
      }
    }
  }

  ProfessionalGroup? get _selectedGroup =>
      _groups.where((group) => group.id == _groupId).firstOrNull;

  List<DynamicField> get _fields =>
      _selectedGroup?.registrationForm?.fields ?? const [];

  /// Option-backed fields keep their value in [_answers]; everything else needs
  /// a controller so the text survives rebuilds.
  List<String> _optionsFor(DynamicField field) {
    if (field.hasOptions) return field.options;
    if (field.fieldType == DynamicFieldType.yesNo) return const ['Yes', 'No'];
    return const [];
  }

  void _rebuildFieldControllers() {
    // The outgoing controllers are still attached to the fields on screen, so
    // they are only disposed once the frame with the new ones has been built.
    final retired = _fieldControllers.values.toList();
    _fieldControllers.clear();
    _answers.clear();

    for (final field in _fields) {
      if (_optionsFor(field).isEmpty) {
        _fieldControllers[field.answerKey] = TextEditingController();
      }
    }

    if (!mounted) {
      for (final controller in retired) {
        controller.dispose();
      }
      return;
    }

    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final controller in retired) {
        controller.dispose();
      }
    });
  }

  void _onGroup(int value) {
    if (value == _groupId) return;
    setState(() {
      _groupId = value;
      _message = '';
    });
    _rebuildFieldControllers();
  }

  void _setAnswer(String key, String value) {
    _answers[key] = value;
    setState(() {});
  }

  String _answer(String key) => (_answers[key] ?? '').trim();

  /// The backend requires the three core identity answers on top of whatever
  /// the group's form asks for, so those gate the button as well.
  bool get _canSave =>
      _groupId > 0 &&
      _answer('first_name').isNotEmpty &&
      _answer('last_name').isNotEmpty &&
      _answer('email').isNotEmpty &&
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

    // Only answered fields go up, exactly as the web posts its answers map.
    final answers = <String, String>{
      for (final entry in _answers.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };

    try {
      final result = await ref.read(formsGroupsApiProvider).createManualClient(
            ClientAccessPayload(
              groupId: _groupId,
              username: _username.text.trim().toLowerCase(),
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
        leading: BackButton(onPressed: () => context.go(Routes.professionalClients)),
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 44), SkeletonBox(height: 220)],
            )
          : PagePad(
              children: [
                if (_createdPassword.isNotEmpty)
                  _CreatedCard(
                    username: _createdUsername,
                    password: _createdPassword,
                    credentialsSent: _credentialsSent,
                    onDone: () => context.go(Routes.professionalClients),
                  )
                else if (_message.isNotEmpty && _groups.isEmpty)
                  ErrorNote(message: _message, onRetry: _load)
                else if (_groups.isEmpty)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A client registration form is required.',
                          style: context.text.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Create a group registration form before adding a '
                          'client manually.',
                          style: context.text.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton(
                          onPressed: () => context.go(Routes.professionalFormsGroups),
                          child: const Text('Open Forms & Groups'),
                        ),
                      ],
                    ),
                  )
                else
                  _Form(
                    groups: _groups,
                    groupId: _groupId,
                    fields: _fields,
                    controllers: _fieldControllers,
                    answers: _answers,
                    optionsFor: _optionsFor,
                    username: _username,
                    password: _password,
                    sendCredentials: _sendCredentials,
                    isSaving: _isSaving,
                    canSave: _canSave,
                    message: _message,
                    onGroup: _onGroup,
                    onAnswer: _setAnswer,
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
    required this.fields,
    required this.controllers,
    required this.answers,
    required this.optionsFor,
    required this.username,
    required this.password,
    required this.sendCredentials,
    required this.isSaving,
    required this.canSave,
    required this.message,
    required this.onGroup,
    required this.onAnswer,
    required this.onSendCredentials,
    required this.onChanged,
    required this.onGenerate,
    required this.onSave,
  });

  final List<ProfessionalGroup> groups;
  final int groupId;
  final List<DynamicField> fields;
  final Map<String, TextEditingController> controllers;
  final Map<String, String> answers;
  final List<String> Function(DynamicField) optionsFor;
  final TextEditingController username;
  final TextEditingController password;
  final bool sendCredentials;
  final bool isSaving;
  final bool canSave;
  final String message;
  final ValueChanged<int> onGroup;
  final void Function(String key, String value) onAnswer;
  final ValueChanged<bool> onSendCredentials;
  final VoidCallback onChanged;
  final VoidCallback onGenerate;
  final VoidCallback onSave;

  TextInputType _keyboardFor(String fieldType) => switch (fieldType) {
        DynamicFieldType.email => TextInputType.emailAddress,
        DynamicFieldType.phone => TextInputType.phone,
        DynamicFieldType.number => TextInputType.number,
        DynamicFieldType.longText => TextInputType.multiline,
        DynamicFieldType.address => TextInputType.streetAddress,
        _ => TextInputType.text,
      };

  /// One registration-form field, rendered by its configured type — the mobile
  /// equivalent of the web's @if/@else chain over field_type.
  Widget _fieldInput(BuildContext context, DynamicField field) {
    final key = field.answerKey;
    final label = field.required ? '${field.label} *' : field.label;
    final helper = field.helpText.isEmpty ? null : field.helpText;
    final options = optionsFor(field);
    final widgetKey = ValueKey('$groupId:$key');

    if (options.isNotEmpty) {
      final selected = answers[key];
      return DropdownButtonFormField<String>(
        key: widgetKey,
        initialValue: (selected ?? '').isEmpty ? null : selected,
        decoration: InputDecoration(labelText: label, helperText: helper),
        hint: Text(
          field.placeholder.isEmpty ? 'Select an option' : field.placeholder,
        ),
        items: options
            .map((option) =>
                DropdownMenuItem(value: option, child: Text(option)))
            .toList(),
        onChanged: (value) => onAnswer(key, value ?? ''),
      );
    }

    final controller = controllers[key];

    if (field.fieldType == DynamicFieldType.date) {
      return TextField(
        key: widgetKey,
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        onTap: () async {
          final now = DateTime.now();
          final current = DateTime.tryParse(controller?.text ?? '');
          final picked = await showDatePicker(
            context: context,
            initialDate: current ?? now,
            firstDate: DateTime(now.year - 100),
            lastDate: DateTime(now.year + 10),
          );
          if (picked == null) return;
          final iso = isoDate(picked);
          controller?.text = iso;
          onAnswer(key, iso);
        },
      );
    }

    final multiline = field.fieldType == DynamicFieldType.longText ||
        field.fieldType == DynamicFieldType.address;

    return TextField(
      key: widgetKey,
      controller: controller,
      keyboardType: _keyboardFor(field.fieldType),
      maxLines: multiline ? 3 : 1,
      autocorrect: multiline,
      textCapitalization: multiline
          ? TextCapitalization.sentences
          : field.fieldType == DynamicFieldType.shortText
              ? TextCapitalization.words
              : TextCapitalization.none,
      onChanged: (value) => onAnswer(key, value),
      decoration: InputDecoration(
        labelText: label,
        hintText: field.placeholder.isEmpty ? null : field.placeholder,
        helperText: helper,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New client', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The selected group\'s registration form is saved with the client.',
            style: context.text.bodySmall,
          ),
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

          if (groupId > 0 && fields.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'This group\'s registration form has no fields yet.',
              style: context.text.bodySmall,
            ),
          ],
          for (final field in fields) ...[
            const SizedBox(height: AppSpacing.md),
            _fieldInput(context, field),
          ],

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
            'first login.',
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
