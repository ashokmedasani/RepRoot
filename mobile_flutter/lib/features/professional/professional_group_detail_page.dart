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
import '../../core/api/plan_lock_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// [overview] is the landing tab — a real-data summary (name, description,
/// status, member count, registration-form readiness, and the registration
/// link) that future group-wide actions (broadcast messaging, bulk actions)
/// will build on. Those actions aren't built yet; this tab is only the
/// foundation the professional asked for.
enum GroupTab { overview, members, registrations, settings }

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
  GroupTab _tab = GroupTab.overview;
  GroupUsersResponse? _data;
  ProfessionalGroup? _group;
  String _message = '';
  bool _loading = true;
  String _registrationLinkBase = '';

  /// Plan-limit lock system (see professional_forms_groups_page.dart):
  /// a group beyond the current plan's count limit locks — every client
  /// inside it loses portal access until it unlocks. Loaded here too so the
  /// Overview tab can show real active/locked status for this one group.
  PlanLockStatus _lockStatus = const PlanLockStatus();

  bool get _isLocked =>
      _lockStatus.section(PlanLockModelKey.groups).isLocked(widget.groupId);

  bool _selectionMode = false;
  final Set<int> _selectedMembers = {};
  bool _bulkBusy = false;

  bool _formMandatory = false;
  List<_DraftField> _customFields = [];

  int _convertingId = 0;
  bool _isConverting = false;
  final _convertUsername = TextEditingController();
  final _convertPassword = TextEditingController();
  bool _convertSendCredentials = true;

  final _editName = TextEditingController();
  final _editDescription = TextEditingController();

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

    try {
      final status = await ref.read(planLockApiProvider).getLockStatus();
      if (mounted) setState(() => _lockStatus = status);
    } catch (_) {/* the Overview tab just shows no lock status */}
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
      _formMandatory = _group?.registrationForm?.isMandatory ?? false;
      // Core fields are built in and not editable — only custom ones show.
      _customFields = (_group?.registrationForm?.fields ?? [])
          .where((f) => !f.isCore)
          .map(_DraftField.from)
          .toList();
    });
  }

  /// The form builder opens as its own full-screen page rather than swapping
  /// the card in place. Building a form is a task with a start and an end —
  /// inline editing gave no sense of entering or leaving it, and the Cancel
  /// button sat below however many fields you'd added.
  Future<void> _openFormBuilder() async {
    _startFormEdit();
    // Local: the page's setState does not rebuild a separate dialog route.
    var saving = false;

    await showDialog<bool>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (dialogContext, setPageState) => Scaffold(
            appBar: AppBar(
              title: Text(_group?.registrationForm == null
                  ? 'Create registration form'
                  : 'Edit registration form'),
              leading: IconButton(
                onPressed: saving ? null : () => dialogContext.pop(false),
                icon: const Icon(Icons.close),
                tooltip: 'Cancel',
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setPageState(() => saving = true);
                          final ok = await _saveRegistrationForm();
                          if (!dialogContext.mounted) return;
                          if (ok) {
                            dialogContext.pop(true);
                          } else {
                            setPageState(() => saving = false);
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
            body: PagePad(
              children: [
                Text(
                  'Core fields (name, email, phone) are always included and '
                  'are not editable.',
                  style: context.text.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < _customFields.length; i++)
                  _FieldEditor(
                    field: _customFields[i],
                    onChanged: () => setPageState(() {}),
                    onRemove: () =>
                        setPageState(() => _customFields.removeAt(i)),
                  ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () =>
                      setPageState(() => _customFields.add(_DraftField())),
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: const Text('Add field'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Require before adding a client'),
                  subtitle:
                      const Text('Clients must complete this form first'),
                  value: _formMandatory,
                  onChanged: (value) =>
                      setPageState(() => _formMandatory = value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Returns whether the save succeeded, so the builder dialog only closes
  /// on success — a failed save used to close anyway and silently discard
  /// every field the professional had just added.
  Future<bool> _saveRegistrationForm() async {
    try {
      await ref.read(formsGroupsApiProvider).saveRegistrationForm(
            widget.groupId,
            _customFields
                .where((f) => f.label.trim().isNotEmpty)
                .map((f) => f.toField())
                .toList(),
            isMandatory: _formMandatory,
          );
      if (!mounted) return false;
      await _load();
      _toast('Registration form saved.');
      return true;
    } on ApiException catch (error) {
      if (!mounted) return false;
      setState(() => _message = error.message);
      _toast(error.message);
      return false;
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

  /// Rejects a pending registration without creating a client — the other half
  /// of the approve/decline pair the web's group-users page offers.
  Future<void> _decline(GroupRegistrationSubmission submission) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline registration?'),
        content: Text(
          '${submission.applicantName.isNotEmpty ? submission.applicantName : 'This applicant'} '
          'will not be added to the group. Their submission is kept for your '
          'records but moves out of the pending list.',
          style: context.text.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final message = await ref
          .read(formsGroupsApiProvider)
          .declineRegistrationSubmission(widget.groupId, submission.id);
      if (!mounted) return;
      setState(() => _message = message.isNotEmpty ? message : 'Registration declined.');
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
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
    try {
      await ref.read(formsGroupsApiProvider).updateGroup(
            widget.groupId,
            _editName.text.trim(),
            _editDescription.text.trim(),
          );
      if (!mounted) return;
      await _load();
      _toast('Group updated.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
      _toast(error.message);
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
        title: Text('Group: ${_group?.name ?? ''}'.trimRight()),
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
            // Full width, so the four tabs split the row into equal quarters
            // and each one stays put as the sign-up count appears and
            // disappears. Left to size itself, the bar shrank to its content
            // and the tabs shifted sideways whenever a sign-up arrived.
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<GroupTab>(
                segments: [
                  const ButtonSegment(
                    value: GroupTab.overview,
                    label: Text('Overview', maxLines: 1),
                  ),
                  const ButtonSegment(
                    value: GroupTab.members,
                    label: Text('Members', maxLines: 1),
                  ),
                  ButtonSegment(
                    value: GroupTab.registrations,
                    label: Text(
                      'Sign Ups${_pendingSubmissions.isNotEmpty ? ' (${_pendingSubmissions.length})' : ''}',
                      maxLines: 1,
                    ),
                  ),
                  const ButtonSegment(
                    value: GroupTab.settings,
                    label: Text('Settings', maxLines: 1),
                  ),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              GroupTab.overview => _overviewTab(members),
              GroupTab.members => _membersTab(members),
              GroupTab.registrations => _registrationsTab(),
              GroupTab.settings => _settingsTab(),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _bulkSetStatus(List<ClientAccessRecord> members, bool active) async {
    if (_bulkBusy || _selectedMembers.isEmpty) return;
    setState(() => _bulkBusy = true);
    final api = ref.read(formsGroupsApiProvider);
    var failures = 0;
    for (final id in _selectedMembers) {
      try {
        await api.updateClientStatus(id, active);
      } catch (_) {
        failures++;
      }
    }
    if (mounted) {
      setState(() {
        _bulkBusy = false;
        _selectionMode = false;
        _selectedMembers.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failures == 0
            ? (active ? 'Members activated.' : 'Members deactivated.')
            : '$failures update(s) failed.')),
      );
    }
    _load();
  }

  Widget _overviewTab(List<ClientAccessRecord> members) {
    final group = _group;
    final locked = _isLocked;
    // Mirrors the web's `activeClients` / `pendingInvites` getters.
    final approvedCount = members.where((m) => m.isActive).length;
    final pendingInvites = members.where((m) => m.mustChangePassword).length;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      group?.name ?? 'Group',
                      style: context.text.titleMedium,
                    ),
                  ),
                  StatusPill(
                    label: locked ? 'Locked' : 'Active',
                    tone: locked ? PillTone.warn : PillTone.good,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                (group?.description ?? '').isNotEmpty
                    ? group!.description
                    : 'No description added yet.',
                style: context.text.bodySmall,
              ),
              if (locked) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Over your current plan\'s group limit. Clients in this group '
                  'lose portal access — their data is kept — until you upgrade '
                  'or free a slot.',
                  style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
                ),
              ],
            ],
          ),
        ),
        // The same four counts the web's Overview panel shows. The old
        // "Registration form: Ready" tile was a restatement of the Sign Ups
        // tab, and it spent half the row on a value that never moves.
        const SectionHeader(title: 'At a glance'),
        KpiGrid(
          children: [
            KpiTile(
              label: 'Total users',
              value: '${members.length}',
              caption: 'Everyone added to this group',
            ),
            KpiTile(
              label: 'Approved',
              value: '$approvedCount',
              caption: 'With active portal access',
            ),
            KpiTile(
              label: 'Pending sign-ups',
              value: '${_pendingSubmissions.length}',
              caption: 'Awaiting your review',
              valueColor: _pendingSubmissions.isEmpty
                  ? null
                  : context.colors.primary,
            ),
            KpiTile(
              label: 'Pending invites',
              value: '$pendingInvites',
              caption: 'Still on a temporary password',
            ),
          ],
        ),
        // The registration link used to be repeated here as well. It belongs
        // with the form that generates it, in Sign Ups — this tab is the
        // group's health check, not a place to do sign-up setup.
      ],
    );
  }

  Widget _membersTab(List<ClientAccessRecord> members) {
    final allSelected =
        members.isNotEmpty && _selectedMembers.length == members.length;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        if (members.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectionMode
                      ? '${_selectedMembers.length} selected'
                      : '${members.length} ${members.length == 1 ? 'member' : 'members'}',
                  style: context.text.bodySmall,
                ),
              ),
              if (_selectionMode)
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selectedMembers.clear();
                    } else {
                      _selectedMembers
                        ..clear()
                        ..addAll(members.map((m) => m.id));
                    }
                  }),
                  child: Text(allSelected ? 'Clear' : 'Select all'),
                ),
              TextButton(
                onPressed: () => setState(() {
                  _selectionMode = !_selectionMode;
                  _selectedMembers.clear();
                }),
                child: Text(_selectionMode ? 'Cancel' : 'Select'),
              ),
            ],
          ),
        // Bulk actions appear only once something is selected — an always-on
        // pair of disabled buttons was taking a row of height on a screen
        // whose job is showing the member list.
        if (_selectionMode && _selectedMembers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _bulkBusy ? null : () => _bulkSetStatus(members, true),
                    child: const Text('Activate'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _bulkBusy ? null : () => _bulkSetStatus(members, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    child: const Text('Deactivate'),
                  ),
                ),
              ],
            ),
          ),
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
              leading: _selectionMode
                  ? Checkbox(
                      value: _selectedMembers.contains(client.id),
                      onChanged: (value) => setState(() {
                        if (value ?? false) {
                          _selectedMembers.add(client.id);
                        } else {
                          _selectedMembers.remove(client.id);
                        }
                      }),
                    )
                  : AppAvatar(
                      initials: _initialsOf(client),
                      imageUrl: Env.mediaUrl(client.photo),
                      size: 40,
                    ),
              trailing: client.isActive
                  ? null
                  : const StatusPill(label: 'Inactive', tone: PillTone.bad),
              onTap: _selectionMode
                  ? () => setState(() {
                        if (_selectedMembers.contains(client.id)) {
                          _selectedMembers.remove(client.id);
                        } else {
                          _selectedMembers.add(client.id);
                        }
                      })
                  : () => context.go('${Routes.professionalClients}/${client.id}'),
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

  /// Read-only look at the live registration form, with Edit as a deliberate
  /// second step. Previously the only way to see what the form asked was to
  /// open the builder, which meant every check put you one stray tap away
  /// from changing a form people are actively submitting.
  Future<void> _openFormPreview() async {
    final form = _group?.registrationForm;
    if (form == null) return;
    final custom = form.fields.where((f) => !f.isCore).toList();

    final edit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (sheetContext, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.card,
            0,
            AppSpacing.card,
            AppSpacing.xl,
          ),
          children: [
            Text('Registration form', style: context.text.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              form.isMandatory
                  ? 'Required before a client can be added.'
                  : 'Optional — clients can be added without it.',
              style: context.text.bodySmall
                  ?.copyWith(color: context.tokens.muted),
            ),
            const SectionHeader(title: 'Always collected', topSpace: AppSpacing.lg),
            Text(
              'Name, email, and phone are built in and cannot be removed.',
              style: context.text.bodySmall,
            ),
            SectionHeader(
              title: 'Your questions (${custom.length})',
              topSpace: AppSpacing.lg,
            ),
            if (custom.isEmpty)
              Text(
                'None yet — the form collects the built-in fields only.',
                style: context.text.bodySmall
                    ?.copyWith(color: context.tokens.muted),
              )
            else
              for (final field in custom)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.tokens.surfaceSoft,
                      borderRadius: AppRadius.tileAll,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(field.label, style: context.text.titleSmall),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  DynamicFieldType.label(field.fieldType),
                                  if (field.options.isNotEmpty)
                                    field.options.join(', '),
                                ].join(' · '),
                                style: context.text.bodySmall
                                    ?.copyWith(color: context.tokens.muted),
                              ),
                            ],
                          ),
                        ),
                        if (field.required)
                          const StatusPill(
                            label: 'Required',
                            tone: PillTone.neutral,
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
              label: const Text('Edit this form'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSize.buttonHeight),
              ),
            ),
          ],
        ),
      ),
    );

    if (edit == true && mounted) await _openFormBuilder();
  }

  Widget _registrationsTab() {
    final hasForm = _group?.registrationForm != null;
    final pending = _pendingSubmissions;
    final converted = (_data?.registrationSubmissions ?? [])
        .where((s) => s.status == 'converted')
        .toList();

    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

        // One "Registration Details" section instead of two stacked cards.
        // The form and the link it generates are one setup job; splitting
        // them meant the link card sat there explaining itself even when
        // there was no form yet to produce a link.
        const SectionHeader(title: 'Registration Details', topSpace: 0),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Registration form',
                        style: context.text.titleSmall),
                  ),
                  StatusPill(
                    label: hasForm ? 'Active' : 'Not set up',
                    tone: hasForm ? PillTone.good : PillTone.neutral,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                hasForm
                    ? '${_group!.registrationForm!.fields.length} fields · '
                        '${_group!.registrationForm!.isMandatory ? 'Required before adding a client' : 'Optional'}'
                    : 'Add a registration form so people can join this group.',
                style: context.text.bodySmall,
              ),

              if (!hasForm) ...[
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _openFormBuilder,
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: const Text('Create form'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
              ] else ...[
                if (_registrationLink.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.tokens.surfaceSoft,
                      borderRadius: AppRadius.tileAll,
                    ),
                    child: Row(
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
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                // Three peers on one row. Edit Form used to be a full-width
                // primary button of its own, which made rebuilding the form
                // look like the main thing to do here — it isn't, sharing the
                // link is.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openFormPreview,
                        icon: const Icon(Icons.visibility_outlined,
                            size: AppSize.iconRow),
                        label: const Text('View'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openFormBuilder,
                        icon: const Icon(Icons.edit_outlined,
                            size: AppSize.iconRow),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, AppSize.buttonHeightSm),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_registrationLink.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _shareRegistrationLink,
                          icon: const Icon(Icons.share, size: AppSize.iconRow),
                          label: const Text('Share'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, AppSize.buttonHeightSm),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

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
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _startConvert(submission),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, AppSize.buttonHeightSm),
                      ),
                      child: const Text('Convert to client'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: () => _decline(submission),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: const Text('Decline'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: context.text.bodySmall),
            ),
            Expanded(
              flex: 3,
              child: Text(value, style: context.text.bodyMedium),
            ),
          ],
        ),
      );

  /// Editing happens in a dialog with an explicit Save, never inline. An
  /// always-open field has no moment of commitment — you can't tell whether
  /// what you typed was kept, and a stray tap edits a live record.
  Future<void> _openGroupDetailsDialog() async {
    _editName.text = _group?.name ?? '';
    _editDescription.text = _group?.description ?? '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _editName,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _editDescription,
                // Four lines, not two: a group description is a sentence or
                // three, and at two lines it scrolled inside a box barely
                // taller than the label above it.
                minLines: 4,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
          // Equal halves rather than the default right-hugging action row, so
          // Cancel and Save are the same size and land where the eye expects
          // on a phone: dismiss left, confirm right.
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => dialogContext.pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeight),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: _editName.text.trim().isEmpty
                        ? null
                        : () => dialogContext.pop(true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeight),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (saved == true) await _saveGroup();
  }

  Widget _settingsTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Group details', style: context.text.titleSmall),
                  ),
                  TextButton.icon(
                    onPressed: _openGroupDetailsDialog,
                    icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _detailRow('Name', _group?.name ?? '—'),
              _detailRow(
                'Description',
                (_group?.description ?? '').trim().isEmpty
                    ? '—'
                    : _group!.description,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Per-field editor row used by the registration-form builder — label,
/// type, options (for choice types), Required, and Remove. Same widget the
/// lead-form builder uses on professional_forms_groups_page.dart.
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
        borderRadius: AppRadius.tileAll,
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
