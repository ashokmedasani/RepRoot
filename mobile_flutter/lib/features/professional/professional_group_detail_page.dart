import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

enum GroupTab { members, registrations, settings }

/// Group detail — members, group registrations, and the group's settings +
/// registration form.
/// Replica of mobile/src/app/pages/professional/group-detail/group-detail.page.ts.
class ProfessionalGroupDetailPage extends ConsumerStatefulWidget {
  const ProfessionalGroupDetailPage({super.key, required this.groupId});

  final int groupId;

  @override
  ConsumerState<ProfessionalGroupDetailPage> createState() =>
      _ProfessionalGroupDetailPageState();
}

/// Mutable field row for the builder — DynamicField is immutable.
class _DraftField {
  _DraftField({
    this.label = '',
    this.fieldType = DynamicFieldType.shortText,
    this.required = false,
    List<String>? options,
  }) : options = options ?? [];

  String label;
  String fieldType;
  bool required;
  List<String> options;

  DynamicField toField() => DynamicField(
        label: label.trim(),
        fieldType: fieldType,
        required: required,
        options:
            DynamicFieldType.withOptions.contains(fieldType) ? options : const [],
      );

  static _DraftField from(DynamicField f) => _DraftField(
        label: f.label,
        fieldType: f.fieldType,
        required: f.required,
        options: [...f.options],
      );
}

class _ProfessionalGroupDetailPageState
    extends ConsumerState<ProfessionalGroupDetailPage> {
  GroupTab _tab = GroupTab.members;
  GroupUsersResponse? _data;
  ProfessionalGroup? _group;
  String _message = '';
  bool _loading = true;
  String _registrationLinkBase = '';

  bool _isEditingForm = false;
  bool _isSavingForm = false;
  List<_DraftField> _customFields = [];

  int _convertingId = 0;
  bool _isConverting = false;
  final _convertUsername = TextEditingController();
  final _convertPassword = TextEditingController();
  bool _convertSendCredentials = true;

  final _editName = TextEditingController();
  final _editDescription = TextEditingController();
  bool _isSavingGroup = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _convertUsername.dispose();
    _convertPassword.dispose();
    _editName.dispose();
    _editDescription.dispose();
    super.dispose();
  }

  List<GroupRegistrationSubmission> get _pendingSubmissions =>
      (_data?.registrationSubmissions ?? [])
          .where((s) => s.status == 'pending')
          .toList();

  String get _registrationLink {
    final slug = _group?.registrationForm?.publicSlug;
    if (slug == null || slug.isEmpty) return '';
    return '$_registrationLinkBase/public/group-registration/$slug';
  }

  Future<void> _load() async {
    final api = ref.read(formsGroupsApiProvider);
    try {
      final data = await api.getGroupUsers(widget.groupId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _group = data.group;
        _editName.text = data.group.name;
        _editDescription.text = data.group.description;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load this group.';
        _loading = false;
      });
    }

    // The registration link shares the lead form's host; there is no dedicated
    // endpoint for it, so derive the base from the lead form's public link.
    try {
      final overview = await api.getOverview();
      final publicLink = overview.leadForm?.publicLink ?? '';
      if (mounted) {
        setState(() => _registrationLinkBase = publicLink.contains('/public/')
            ? publicLink.split('/public/').first
            : Env.apiBaseUrl);
      }
    } catch (_) {
      if (mounted) setState(() => _registrationLinkBase = Env.apiBaseUrl);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 2400)),
    );
  }

  Future<void> _shareRegistrationLink() async {
    final url = _registrationLink;
    if (url.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(title: 'Join ${_group?.name ?? ''}', uri: Uri.parse(url)),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Link copied to clipboard.');
    }
  }

  void _startFormEdit() {
    setState(() {
      // Core fields are built in and not editable — only custom ones show.
      _customFields = (_group?.registrationForm?.fields ?? [])
          .where((f) => !f.isCore)
          .map(_DraftField.from)
          .toList();
      _isEditingForm = true;
    });
  }

  Future<void> _saveRegistrationForm() async {
    setState(() => _isSavingForm = true);
    try {
      await ref.read(formsGroupsApiProvider).saveRegistrationForm(
            widget.groupId,
            _customFields
                .where((f) => f.label.trim().isNotEmpty)
                .map((f) => f.toField())
                .toList(),
          );
      if (!mounted) return;
      setState(() {
        _isSavingForm = false;
        _isEditingForm = false;
      });
      await _load();
      _toast('Registration form saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingForm = false;
        _message = error.message;
      });
    }
  }

  String _generatePassword() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    final value =
        List.generate(10, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '${value.substring(0, 8)}!${value.substring(8)}';
  }

  void _startConvert(GroupRegistrationSubmission submission) {
    setState(() {
      _convertingId = submission.id;
      _convertUsername.text =
          '${submission.firstName}.${submission.lastName}'.toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9.-]+'),
                '',
              );
      _convertPassword.text = _generatePassword();
      _convertSendCredentials = true;
    });
  }

  Future<void> _convert(GroupRegistrationSubmission submission) async {
    setState(() => _isConverting = true);
    final password = _convertPassword.text.trim();
    try {
      final result = await ref.read(formsGroupsApiProvider).createManualClient(
            ClientAccessPayload(
              groupId: widget.groupId,
              username: _convertUsername.text.trim(),
              password: password,
              confirmPassword: password,
              // The backend copies the answers from the linked submission.
              registrationAnswers: const {},
              sendCredentials: _convertSendCredentials,
              registrationSubmissionId: submission.id,
            ),
          );
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _convertingId = 0;
      });
      await _load();
      if (mounted) {
        await _showCredentials(
          _convertUsername.text.trim(),
          result.temporaryPassword.isNotEmpty ? result.temporaryPassword : password,
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _message = error.message;
      });
    }
  }

  Future<void> _showCredentials(String username, String password) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Client created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share these one-time credentials. The client must change the '
              'password on first login.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Username: $username', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Password: $password',
              style: context.text.titleSmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '$username / $password'));
              context.pop();
              _toast('Credentials copied.');
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => context.pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGroup() async {
    setState(() => _isSavingGroup = true);
    try {
      await ref.read(formsGroupsApiProvider).updateGroup(
            widget.groupId,
            _editName.text.trim(),
            _editDescription.text.trim(),
          );
      if (!mounted) return;
      setState(() => _isSavingGroup = false);
      await _load();
      _toast('Group updated.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingGroup = false;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const PagePad(
          children: [SkeletonBox(height: 44), SkeletonBox(height: 180)],
        ),
      );
    }

    final members = _data?.clients ?? const <ClientAccessRecord>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_group?.name ?? 'Group'),
        leading: BackButton(
          onPressed: () => context.go('${Routes.professionalFormsGroups}?tab=groups'),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: SegmentedButton<GroupTab>(
              segments: [
                ButtonSegment(
                  value: GroupTab.members,
                  label: Text('Members (${members.length})'),
                ),
                ButtonSegment(
                  value: GroupTab.registrations,
                  label: Text(
                    'Sign-ups${_pendingSubmissions.isNotEmpty ? ' (${_pendingSubmissions.length})' : ''}',
                  ),
                ),
                const ButtonSegment(value: GroupTab.settings, label: Text('Settings')),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.first),
              style: SegmentedButton.styleFrom(
                textStyle: context.text.labelSmall,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              GroupTab.members => _membersTab(members),
              GroupTab.registrations => _registrationsTab(),
              GroupTab.settings => _settingsTab(),
            },
          ),
        ],
      ),
    );
  }

  Widget _membersTab(List<ClientAccessRecord> members) {
    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        if (members.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.people_outline,
            message: 'No clients in this group yet.',
          )
        else
          for (final client in members)
            RowItem(
              title: client.displayName.isEmpty ? client.username : client.displayName,
              subtitle: client.email.isEmpty ? client.username : client.email,
              leading: AppAvatar(
                initials: _initialsOf(client),
                imageUrl: Env.mediaUrl(client.photo),
                size: 40,
              ),
              trailing: client.isActive
                  ? null
                  : const StatusPill(label: 'Inactive', tone: PillTone.bad),
              onTap: () => context.go('${Routes.professionalClients}/${client.id}'),
            ),
      ],
    );
  }

  String _initialsOf(ClientAccessRecord client) {
    final first = client.firstName.isNotEmpty ? client.firstName[0] : '';
    final last = client.lastName.isNotEmpty ? client.lastName[0] : '';
    final letters = '$first$last'.toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  Widget _registrationsTab() {
    final pending = _pendingSubmissions;
    final converted = (_data?.registrationSubmissions ?? [])
        .where((s) => s.status == 'converted')
        .toList();

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

        if (_registrationLink.isNotEmpty) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Registration link', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Share this so people can join ${_group?.name ?? 'this group'} directly.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _registrationLink,
                        style: context.text.bodySmall
                            ?.copyWith(color: context.colors.primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _registrationLink),
                        );
                        _toast('Link copied.');
                      },
                      icon: const Icon(Icons.copy_outlined),
                      iconSize: AppSize.iconRow,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Copy link',
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _shareRegistrationLink,
                  icon: const Icon(Icons.share, size: AppSize.iconRow),
                  label: const Text('Share link'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        SectionHeader(title: 'Pending (${pending.length})', topSpace: 0),
        if (pending.isEmpty)
          const EmptyState(message: 'No sign-ups waiting.')
        else
          for (final submission in pending) _submissionCard(submission),

        if (converted.isNotEmpty) ...[
          SectionHeader(title: 'Converted (${converted.length})'),
          for (final submission in converted.take(10))
            RowItem(
              title: submission.applicantName,
              subtitle: submission.email,
              trailing: const StatusPill(label: 'Client', tone: PillTone.good),
            ),
        ],
      ],
    );
  }

  Widget _submissionCard(GroupRegistrationSubmission submission) {
    final converting = _convertingId == submission.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(submission.applicantName, style: context.text.titleSmall),
            Text(
              '${submission.email} · ${shortDate(submission.submittedAt)}',
              style: context.text.bodySmall,
            ),
            if (submission.answers.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final entry in submission.answers.entries.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.key.replaceAll('_', ' '),
                          style: context.text.bodySmall,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          entry.value.isEmpty ? '—' : entry.value,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            if (converting) ...[
              const Divider(height: AppSpacing.xl),
              Text('Create client access', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _convertUsername,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _convertPassword,
                      autocorrect: false,
                      decoration:
                          const InputDecoration(labelText: 'Temporary password'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: OutlinedButton(
                      onPressed: () => setState(
                        () => _convertPassword.text = _generatePassword(),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(88, AppSize.buttonHeightSm),
                      ),
                      child: const Text('Generate'),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => setState(
                  () => _convertSendCredentials = !_convertSendCredentials,
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _convertSendCredentials,
                      onChanged: (v) =>
                          setState(() => _convertSendCredentials = v ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: Text(
                        'Email the credentials to the client',
                        style: context.text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _isConverting ? null : () => _convert(submission),
                      child: Text(_isConverting ? 'Creating…' : 'Create client'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () => setState(() => _convertingId = 0),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: () => _startConvert(submission),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
                child: const Text('Convert to client'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _settingsTab() {
    final form = _group?.registrationForm;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Group details', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _editName,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _editDescription,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _isSavingGroup || _editName.text.trim().isEmpty
                    ? null
                    : _saveGroup,
                child: Text(_isSavingGroup ? 'Saving…' : 'Save group'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (!_isEditingForm)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Registration form', style: context.text.titleSmall),
                    ),
                    if (form != null)
                      const StatusPill(label: 'Active', tone: PillTone.good),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  form == null
                      ? 'Add a registration form so people can join this group.'
                      : '${form.fields.length} fields',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _startFormEdit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                  child: Text(form == null ? 'Create form' : 'Edit form'),
                ),
                if (form != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  for (final field in form.fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(field.label, style: context.text.bodyMedium),
                          ),
                          Text(
                            [
                              DynamicFieldType.label(field.fieldType),
                              if (field.required) 'Required',
                              if (field.isCore) 'Core',
                            ].join(' · '),
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          )
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit registration form', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Core fields (name, email, phone) are always included and are '
                  'not editable.',
                  style: context.text.bodySmall,
                ),
                for (var i = 0; i < _customFields.length; i++)
                  _FieldEditor(
                    field: _customFields[i],
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() => _customFields.removeAt(i)),
                  ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _customFields.add(_DraftField())),
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: const Text('Add field'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _isSavingForm ? null : _saveRegistrationForm,
                        child: Text(_isSavingForm ? 'Saving…' : 'Save form'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => setState(() => _isEditingForm = false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.field,
    required this.onChanged,
    required this.onRemove,
  });

  final _DraftField field;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.smAll,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          TextFormField(
            initialValue: field.label,
            onChanged: (v) {
              field.label = v;
              onChanged();
            },
            decoration: const InputDecoration(labelText: 'Label'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: field.fieldType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: DynamicFieldType.all
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(DynamicFieldType.label(t)),
                    ))
                .toList(),
            onChanged: (v) {
              field.fieldType = v ?? DynamicFieldType.shortText;
              onChanged();
            },
          ),
          if (DynamicFieldType.withOptions.contains(field.fieldType)) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: field.options.join(', '),
              onChanged: (v) {
                field.options = v
                    .split(',')
                    .map((o) => o.trim())
                    .where((o) => o.isNotEmpty)
                    .toList();
              },
              decoration: const InputDecoration(
                labelText: 'Options',
                helperText: 'Comma separated',
              ),
            ),
          ],
          Row(
            children: [
              Checkbox(
                value: field.required,
                onChanged: (v) {
                  field.required = v ?? false;
                  onChanged();
                },
                visualDensity: VisualDensity.compact,
              ),
              Text('Required', style: context.text.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: AppSize.iconRow),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
