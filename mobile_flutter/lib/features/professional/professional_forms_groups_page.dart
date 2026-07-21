import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'trainer_format.dart';

enum FormsTab { form, groups, requests }

/// Forms & Groups — the lead form builder, groups, and lead requests.
/// Replica of mobile/src/app/pages/trainer/forms-groups/trainer-forms-groups.page.ts.
class TrainerFormsGroupsPage extends ConsumerStatefulWidget {
  const TrainerFormsGroupsPage({super.key, this.initialTab});

  /// From ?tab=groups|requests, as the Manage hub links deep into a tab.
  final String? initialTab;

  @override
  ConsumerState<TrainerFormsGroupsPage> createState() =>
      _TrainerFormsGroupsPageState();
}

/// Mutable field row for the builder — DynamicField is immutable.
class _DraftField {
  _DraftField({
    this.label = '',
    this.fieldType = DynamicFieldType.shortText,
    this.required = false,
    this.placeholder = '',
    this.helpText = '',
    List<String>? options,
  }) : options = options ?? [];

  String label;
  String fieldType;
  bool required;
  String placeholder;
  String helpText;
  List<String> options;

  DynamicField toField() => DynamicField(
        label: label.trim(),
        fieldType: fieldType,
        required: required,
        placeholder: placeholder,
        helpText: helpText,
        options: DynamicFieldType.withOptions.contains(fieldType)
            ? options
            : const [],
      );

  static _DraftField from(DynamicField field) => _DraftField(
        label: field.label,
        fieldType: field.fieldType,
        required: field.required,
        placeholder: field.placeholder,
        helpText: field.helpText,
        options: [...field.options],
      );
}

class _TrainerFormsGroupsPageState
    extends ConsumerState<TrainerFormsGroupsPage> {
  FormsTab _tab = FormsTab.form;
  FormsGroupsOverview? _overview;
  String _message = '';
  bool _loading = true;
  int _expandedId = 0;

  // Lead form editor
  bool _isEditingForm = false;
  bool _isSavingForm = false;
  final _formTitle = TextEditingController();
  List<_DraftField> _customFields = [];

  // Approval
  int _approvingId = 0;
  bool _isApproving = false;
  int _approveGroupId = 0;
  final _approveUsername = TextEditingController();
  final _approvePassword = TextEditingController();
  bool _approveSendCredentials = true;

  // Group form
  bool _showGroupForm = false;
  bool _isSavingGroup = false;
  final _groupName = TextEditingController();
  final _groupDescription = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = switch (widget.initialTab) {
      'groups' => FormsTab.groups,
      'requests' => FormsTab.requests,
      _ => FormsTab.form,
    };
    _load();
  }

  @override
  void dispose() {
    _formTitle.dispose();
    _approveUsername.dispose();
    _approvePassword.dispose();
    _groupName.dispose();
    _groupDescription.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final overview = await ref.read(formsGroupsApiProvider).getOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load forms & groups.';
        _loading = false;
      });
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 2400)),
    );
  }

  Future<void> _shareLink(String url, String title) async {
    if (url.isEmpty) return;
    try {
      await SharePlus.instance.share(
        ShareParams(title: title, uri: Uri.parse(url)),
      );
    } catch (_) {
      // Fall back to the clipboard if no share target handles it.
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Link copied to clipboard.');
    }
  }

  // ----- lead form -----

  void _startFormEdit() {
    final leadForm = _overview?.leadForm;
    setState(() {
      _formTitle.text = leadForm?.title ?? 'Training Enquiry';
      // Core fields are built in and not editable — only custom ones show.
      _customFields = (leadForm?.fields ?? [])
          .where((field) => !field.isCore)
          .map(_DraftField.from)
          .toList();
      _isEditingForm = true;
    });
  }

  Future<void> _saveForm() async {
    setState(() => _isSavingForm = true);
    try {
      await ref.read(formsGroupsApiProvider).saveLeadForm(
            _formTitle.text.trim(),
            _customFields
                .where((field) => field.label.trim().isNotEmpty)
                .map((field) => field.toField())
                .toList(),
          );
      if (!mounted) return;
      setState(() {
        _isSavingForm = false;
        _isEditingForm = false;
      });
      await _load();
      _toast('Form saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingForm = false;
        _message = error.message;
      });
    }
  }

  // ----- approval -----

  String _generatePassword() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    final value =
        List.generate(10, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '${value.substring(0, 8)}!${value.substring(8)}';
  }

  void _startApprove(LeadSubmission submission) {
    setState(() {
      _approvingId = submission.id;
      // Pre-select when there is no real choice to make.
      _approveGroupId =
          _overview?.groups.length == 1 ? _overview!.groups.first.id : 0;
      _approveUsername.text =
          '${submission.firstName}.${submission.lastName}'.toLowerCase().replaceAll(
                RegExp(r'[^a-z0-9.-]+'),
                '',
              );
      _approvePassword.text = _generatePassword();
      _approveSendCredentials = true;
    });
  }

  Future<void> _approve(LeadSubmission submission) async {
    if (_approveGroupId == 0) {
      setState(() => _message = 'Choose a group for this client.');
      return;
    }
    setState(() => _isApproving = true);
    final password = _approvePassword.text.trim();
    try {
      await ref.read(formsGroupsApiProvider).createClientAccess(
            submission.id,
            ClientAccessPayload(
              groupId: _approveGroupId,
              username: _approveUsername.text.trim(),
              password: password,
              confirmPassword: password,
              registrationAnswers: submission.answers,
              sendCredentials: _approveSendCredentials,
            ),
          );
      if (!mounted) return;
      setState(() {
        _isApproving = false;
        _approvingId = 0;
      });
      await _load();
      // The password is only shown once — surface it so it can be copied.
      if (mounted) await _showCredentials(_approveUsername.text.trim(), password);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isApproving = false;
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
            SelectableText('Username: $username', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
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

  Future<void> _deletePending(LeadSubmission submission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${submission.applicantName}?'),
        content: const Text('This enquiry will be removed from your requests.'),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(formsGroupsApiProvider).deletePendingForm(submission.id);
      await _load();
    } catch (_) {
      _toast('Could not delete the request.');
    }
  }

  // ----- groups -----

  Future<void> _createGroup() async {
    setState(() => _isSavingGroup = true);
    try {
      await ref.read(formsGroupsApiProvider).createGroup(
            _groupName.text.trim(),
            _groupDescription.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _isSavingGroup = false;
        _showGroupForm = false;
        _groupName.clear();
        _groupDescription.clear();
      });
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingGroup = false;
        _message = error.message;
      });
    }
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forms & Groups'),
        leading: BackButton(onPressed: () => context.go(Routes.trainerManage)),
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 44), SkeletonBox(height: 180)],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.sm,
                    AppSpacing.screen,
                    AppSpacing.sm,
                  ),
                  child: SegmentedButton<FormsTab>(
                    segments: [
                      const ButtonSegment(value: FormsTab.form, label: Text('Form')),
                      const ButtonSegment(value: FormsTab.groups, label: Text('Groups')),
                      ButtonSegment(
                        value: FormsTab.requests,
                        label: Text(
                          'Requests${(_overview?.pendingForms.length ?? 0) > 0 ? ' (${_overview!.pendingForms.length})' : ''}',
                        ),
                      ),
                    ],
                    selected: {_tab},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                    style: SegmentedButton.styleFrom(
                      textStyle: context.text.labelMedium,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    FormsTab.form => _formTab(),
                    FormsTab.groups => _groupsTab(),
                    FormsTab.requests => _requestsTab(),
                  },
                ),
              ],
            ),
    );
  }

  Widget _formTab() {
    final leadForm = _overview?.leadForm;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

        if (!_isEditingForm) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        leadForm?.title ?? 'No lead form yet',
                        style: context.text.titleSmall,
                      ),
                    ),
                    if (leadForm != null)
                      const StatusPill(label: 'Live', tone: PillTone.good),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  leadForm == null
                      ? 'Create a public form so people can enquire.'
                      : 'Updated ${shortDate(leadForm.updatedAt)} · ${leadForm.fields.length} fields',
                  style: context.text.bodySmall,
                ),
                if (leadForm != null && leadForm.publicLink.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          leadForm.publicLink,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: leadForm.publicLink),
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
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _startFormEdit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                        ),
                        child: Text(leadForm == null ? 'Create form' : 'Edit form'),
                      ),
                    ),
                    if (leadForm != null && leadForm.publicLink.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _shareLink(leadForm.publicLink, leadForm.title),
                        icon: const Icon(Icons.share, size: AppSize.iconRow),
                        label: const Text('Share'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (leadForm != null) ...[
            const SectionHeader(title: 'Fields'),
            for (final field in leadForm.fields)
              RowItem(
                title: field.label,
                subtitle: [
                  DynamicFieldType.label(field.fieldType),
                  if (field.required) 'Required',
                  if (field.isCore) 'Core',
                ].join(' · '),
              ),
          ],
        ] else
          _formEditor(),
      ],
    );
  }

  Widget _formEditor() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit lead form', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _formTitle,
            decoration: const InputDecoration(labelText: 'Form title'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Core fields (name, email, phone) are always included and are not '
            'editable. Add your own below.',
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
                  onPressed: _isSavingForm ? null : _saveForm,
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
    );
  }

  Widget _groupsTab() {
    final overview = _overview;
    final groups = overview?.groups ?? const <TrainerGroup>[];

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Groups used',
                      style: context.text.labelMedium?.copyWith(
                        color: context.tokens.muted,
                      ),
                    ),
                    Text(
                      '${groups.length} / ${overview?.maxGroups ?? '—'}',
                      style: context.text.displaySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: overview?.atGroupLimit ?? false
                    ? null
                    : () => setState(() => _showGroupForm = !_showGroupForm),
                icon: Icon(_showGroupForm ? Icons.close : Icons.add,
                    size: AppSize.iconRow),
                label: Text(_showGroupForm ? 'Close' : 'New group'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppSize.buttonHeightSm),
                ),
              ),
            ],
          ),
        ),
        if (overview?.atGroupLimit ?? false)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Group limit reached on your plan.',
              style: context.text.bodySmall?.copyWith(color: context.colors.error),
            ),
          ),

        if (_showGroupForm) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _groupName,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _groupDescription,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _isSavingGroup || _groupName.text.trim().isEmpty
                      ? null
                      : _createGroup,
                  child: Text(_isSavingGroup ? 'Creating…' : 'Create group'),
                ),
              ],
            ),
          ),
        ],

        const SectionHeader(title: 'Your groups'),
        if (groups.isEmpty)
          const EmptyState(message: 'No groups yet.')
        else
          for (final group in groups)
            RowItem(
              title: group.name,
              subtitle: group.description.isNotEmpty
                  ? group.description
                  : (group.hasRegistrationForm
                      ? 'Registration link active'
                      : 'No registration form'),
              trailing: group.hasRegistrationForm
                  ? const StatusPill(label: 'Form', tone: PillTone.good)
                  : null,
              onTap: () => context.go('${Routes.trainerGroups}/${group.id}'),
            ),
      ],
    );
  }

  Widget _requestsTab() {
    final overview = _overview;
    final pending = overview?.pendingForms ?? const <LeadSubmission>[];
    final approved = overview?.approvedForms ?? const <LeadSubmission>[];

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        SectionHeader(title: 'Pending (${pending.length})', topSpace: 0),
        if (pending.isEmpty)
          const EmptyState(message: 'No enquiries waiting.')
        else
          for (final submission in pending) _pendingCard(submission),

        SectionHeader(title: 'Approved (${approved.length})'),
        if (approved.isEmpty)
          const EmptyState(message: 'No approved enquiries yet.')
        else
          for (final submission in approved.take(10))
            RowItem(
              title: submission.applicantName,
              subtitle:
                  '${submission.email}${submission.clientAccess != null ? ' · ${submission.clientAccess!.groupName}' : ''}',
              trailing: const StatusPill(label: 'Client', tone: PillTone.good),
            ),
      ],
    );
  }

  Widget _pendingCard(LeadSubmission submission) {
    final expanded = _expandedId == submission.id;
    final approving = _approvingId == submission.id;
    final groups = _overview?.groups ?? const <TrainerGroup>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _expandedId = expanded ? 0 : submission.id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(submission.applicantName, style: context.text.titleSmall),
                        Text(
                          '${submission.email} · ${shortDate(submission.submittedAt)}',
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconRow,
                    color: context.tokens.muted,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: AppSpacing.md),
              for (final entry in submission.answers.entries)
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

            if (approving) ...[
              const Divider(height: AppSpacing.xl),
              Text('Create client access', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<int>(
                initialValue: _approveGroupId > 0 ? _approveGroupId : null,
                decoration: const InputDecoration(labelText: 'Group'),
                hint: const Text('Choose a group'),
                items: groups
                    .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                    .toList(),
                onChanged: (value) => setState(() => _approveGroupId = value ?? 0),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _approveUsername,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _approvePassword,
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
                      onPressed: () => setState(
                        () => _approvePassword.text = _generatePassword(),
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
                  () => _approveSendCredentials = !_approveSendCredentials,
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _approveSendCredentials,
                      onChanged: (v) =>
                          setState(() => _approveSendCredentials = v ?? false),
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
                      onPressed: _isApproving ? null : () => _approve(submission),
                      child: Text(_isApproving ? 'Creating…' : 'Create client'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: () => setState(() => _approvingId = 0),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _startApprove(submission),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, AppSize.buttonHeightSm),
                      ),
                      child: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => _deletePending(submission),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      side: BorderSide(color: context.colors.error),
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
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
            onChanged: (value) {
              field.label = value;
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
            onChanged: (value) {
              field.fieldType = value ?? DynamicFieldType.shortText;
              onChanged();
            },
          ),
          if (DynamicFieldType.withOptions.contains(field.fieldType)) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: field.options.join(', '),
              onChanged: (value) {
                field.options = value
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
                onChanged: (value) {
                  field.required = value ?? false;
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
