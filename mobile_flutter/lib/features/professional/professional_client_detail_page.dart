import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/templates_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

enum DetailTab { info, overview, tracking, chat, actions }

/// Client detail — Info / Overview / Tracking / Chat / Actions.
/// Replica of mobile/src/app/pages/professional/client-detail/client-detail.page.ts.
class ProfessionalClientDetailPage extends ConsumerStatefulWidget {
  const ProfessionalClientDetailPage({super.key, required this.clientId});

  final int clientId;

  @override
  ConsumerState<ProfessionalClientDetailPage> createState() =>
      _ProfessionalClientDetailPageState();
}

class _ProfessionalClientDetailPageState
    extends ConsumerState<ProfessionalClientDetailPage> {
  DetailTab _tab = DetailTab.info;

  ClientAccessDetailResponse? _detail;
  ClientAccessRecord? _client;
  List<DynamicField> _registrationFields = [];
  List<ClientReminder> _reminders = [];
  List<ProgressEntry> _progress = [];
  List<TemplateAssignmentRecord> _assignments = [];
  List<TrackingTemplateRecord> _allTemplates = [];
  List<ChatMessageRecord> _chatMessages = [];

  final _chatDraft = TextEditingController();
  final _chatScroll = ScrollController();
  final _notes = TextEditingController();
  final _reminderTitle = TextEditingController();

  int _chatUnreadCount = 0;
  String _message = '';
  bool _loading = true;
  bool _isSavingNotes = false;
  bool _isReviewing = false;
  bool _isAssigning = false;
  int _templateToAssign = 0;
  String _temporaryPassword = '';
  bool _showReminderForm = false;
  DateTime? _reminderDate;
  TimeOfDay? _reminderTime;

  Timer? _chatPoll;
  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    // Same cadences as the Ionic page: chat only polls while its tab is open.
    _chatPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_tab == DetailTab.chat) _loadChat();
    });
    _unreadPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _chatPoll?.cancel();
    _unreadPoll?.cancel();
    _chatDraft.dispose();
    _chatScroll.dispose();
    _notes.dispose();
    _reminderTitle.dispose();
    super.dispose();
  }

  String get _initials {
    final first = _client?.firstName ?? '';
    final last = _client?.lastName ?? '';
    final letters =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'
            .toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  String get _onboardingLabel => switch (_client?.onboardingMethod) {
        'manual' => 'Added manually',
        'group_registration' => 'Group registration',
        _ => 'Public enquiry',
      };

  List<TrackingTemplateRecord> get _assignableTemplates {
    final assigned = _assignments.map((a) => a.templateId).toSet();
    return _allTemplates.where((t) => !assigned.contains(t.id)).toList();
  }

  String _labelFor(String key) {
    final field = _registrationFields.where((f) => f.answerKey == key).firstOrNull;
    return field?.label ?? key.replaceAll('_', ' ');
  }

  List<({String label, String from, String to})> get _proposedChanges {
    final request = _detail?.pendingChangeRequest;
    if (request == null || _client == null) return [];
    return request.proposedAnswers.entries
        .map((entry) => (
              label: _labelFor(entry.key),
              from: _client!.registrationAnswers[entry.key] ?? '',
              to: entry.value,
            ))
        .toList();
  }

  Future<void> _load() async {
    final formsGroups = ref.read(formsGroupsApiProvider);
    final templatesApi = ref.read(templatesApiProvider);

    await Future.wait([
      () async {
        try {
          final detail = await formsGroups.getClientProfile(widget.clientId);
          if (!mounted) return;
          setState(() {
            _detail = detail;
            _client = detail.client;
            _registrationFields = detail.registrationFields;
            _notes.text = detail.professionalNotes;
          });
        } catch (_) {
          if (mounted) setState(() => _message = 'Could not load this client.');
        }
      }(),
      () async {
        try {
          final reminders = await formsGroups.getClientReminders(widget.clientId);
          if (mounted) setState(() => _reminders = reminders);
        } catch (_) {
          if (mounted) setState(() => _reminders = []);
        }
      }(),
      () async {
        try {
          final progress = await formsGroups.getClientProgress(widget.clientId);
          if (mounted) setState(() => _progress = progress);
        } catch (_) {
          if (mounted) setState(() => _progress = []);
        }
      }(),
      () async {
        try {
          final assignments = await templatesApi.getAssignments(widget.clientId);
          if (mounted) setState(() => _assignments = assignments);
        } catch (_) {
          if (mounted) setState(() => _assignments = []);
        }
      }(),
      () async {
        try {
          final response = await templatesApi.getTemplates();
          if (mounted) setState(() => _allTemplates = response.templates);
        } catch (_) {
          if (mounted) setState(() => _allTemplates = []);
        }
      }(),
      _loadChat(),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  /// Polls incrementally: only messages newer than the last one seen.
  Future<void> _loadChat() async {
    try {
      final lastId = _chatMessages.isNotEmpty ? _chatMessages.last.id : null;
      final messages = await ref
          .read(chatApiProvider)
          .getProfessionalMessages(widget.clientId, afterId: lastId);
      if (!mounted || messages.isEmpty) return;
      setState(() => _chatMessages = [..._chatMessages, ...messages]);
      _scrollChatToEnd();
    } catch (_) {/* a failed poll must not disturb the screen */}
  }

  Future<void> _loadUnread() async {
    try {
      final summary = await ref.read(chatApiProvider).getProfessionalUnreadCounts();
      if (mounted) {
        setState(() => _chatUnreadCount = summary.forClient(widget.clientId));
      }
    } catch (_) {
      if (mounted) setState(() => _chatUnreadCount = 0);
    }
  }

  void _scrollChatToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.jumpTo(_chatScroll.position.maxScrollExtent);
      }
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 1800)),
    );
  }

  // ----- actions -----

  Future<void> _saveNotes() async {
    setState(() => _isSavingNotes = true);
    try {
      await ref
          .read(formsGroupsApiProvider)
          .saveProfessionalNotes(widget.clientId, _notes.text);
      _toast('Notes saved.');
    } catch (_) {
      _toast('Could not save notes.');
    }
    if (mounted) setState(() => _isSavingNotes = false);
  }

  Future<void> _review(String action) async {
    final request = _detail?.pendingChangeRequest;
    if (request == null) return;
    setState(() => _isReviewing = true);
    try {
      final result = await ref
          .read(formsGroupsApiProvider)
          .reviewChangeRequest(widget.clientId, request.id, action);
      if (!mounted) return;
      setState(() {
        _client = result.client;
        _isReviewing = false;
      });
      // Reload so the cleared pending request is reflected from the source.
      await _load();
      _toast(action == 'approve' ? 'Changes approved.' : 'Request rejected.');
    } catch (_) {
      if (mounted) setState(() => _isReviewing = false);
      _toast('Could not complete the review.');
    }
  }

  Future<void> _assign() async {
    if (_templateToAssign == 0) return;
    setState(() => _isAssigning = true);
    try {
      final assignment = await ref
          .read(templatesApiProvider)
          .assignTemplate(widget.clientId, _templateToAssign);
      if (!mounted) return;
      setState(() {
        _assignments = [..._assignments, assignment];
        _templateToAssign = 0;
        _isAssigning = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isAssigning = false);
      _toast('Could not assign the template.');
    }
  }

  Future<void> _unassign(TemplateAssignmentRecord assignment) async {
    final confirmed = await _confirm(
      title: 'Remove ${assignment.templateName}?',
      body: 'The client stops seeing this tracker. Past entries stay saved.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(templatesApiProvider)
          .unassignTemplate(widget.clientId, assignment.id);
      if (!mounted) return;
      setState(() => _assignments =
          _assignments.where((a) => a.id != assignment.id).toList());
    } catch (_) {
      _toast('Could not remove the template.');
    }
  }

  Future<void> _sendChat() async {
    final text = _chatDraft.text.trim();
    if (text.isEmpty) return;
    _chatDraft.clear();
    try {
      final sent =
          await ref.read(chatApiProvider).sendProfessionalMessage(widget.clientId, text);
      if (!mounted) return;
      setState(() => _chatMessages = [..._chatMessages, sent]);
      _scrollChatToEnd();
    } catch (_) {
      _toast('Message failed to send.');
    }
  }

  Future<void> _toggleReminder(ClientReminder reminder) async {
    final status = reminder.isDone ? ReminderStatus.pending : ReminderStatus.done;
    try {
      final updated = await ref
          .read(formsGroupsApiProvider)
          .updateReminder(reminder.id, status: status);
      if (!mounted) return;
      setState(() => _reminders =
          _reminders.map((r) => r.id == reminder.id ? updated : r).toList());
    } catch (_) {
      _toast('Could not update the schedule.');
    }
  }

  Future<void> _removeReminder(ClientReminder reminder) async {
    try {
      await ref.read(formsGroupsApiProvider).deleteReminder(reminder.id);
      if (!mounted) return;
      setState(() =>
          _reminders = _reminders.where((r) => r.id != reminder.id).toList());
    } catch (_) {
      _toast('Could not delete the schedule.');
    }
  }

  Future<void> _addReminder() async {
    final date = _reminderDate;
    if (_reminderTitle.text.trim().isEmpty || date == null) return;
    try {
      final reminder = await ref.read(formsGroupsApiProvider).createClientReminder(
            widget.clientId,
            title: _reminderTitle.text.trim(),
            date: _isoDate(date),
            time: _reminderTime == null ? null : _isoTime(_reminderTime!),
            notifyProfessional: true,
          );
      if (!mounted) return;
      setState(() {
        _reminders = [..._reminders, reminder];
        _showReminderForm = false;
        _reminderTitle.clear();
        _reminderDate = null;
        _reminderTime = null;
      });
    } catch (_) {
      _toast('Could not save the schedule.');
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _isoTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _toggleActive() async {
    final client = _client;
    if (client == null) return;
    final target = !client.isActive;
    final confirmed = await _confirm(
      title: target ? 'Activate account?' : 'Deactivate account?',
      body: target
          ? 'The client will be able to log in again.'
          : 'The client will no longer be able to log in.',
      confirmLabel: target ? 'Activate' : 'Deactivate',
      destructive: !target,
    );
    if (!confirmed) return;
    try {
      final updated = await ref
          .read(formsGroupsApiProvider)
          .updateClientStatus(widget.clientId, target);
      if (mounted) setState(() => _client = updated);
    } catch (_) {
      _toast('Could not update the account.');
    }
  }

  /// Unambiguous alphabet (no O/0, l/1) so a password read aloud still works,
  /// plus a guaranteed special character for the backend's strength rule.
  String _generateTemporaryPassword() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    final value =
        List.generate(9, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '${value.substring(0, 8)}!${value.substring(8)}';
  }

  Future<void> _resetPassword() async {
    // Option A: the professional defines the temporary password, prefilled with a
    // suggestion — same as manual creation.
    final controller = TextEditingController(text: _generateTemporaryPassword());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Set the temporary password (min 8 characters, 1 special). The '
              'current password stops working immediately.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Temporary password'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }

    final password = controller.text.trim();
    controller.dispose();
    try {
      final temporary = await ref
          .read(formsGroupsApiProvider)
          .resetClientPassword(widget.clientId, password: password);
      if (mounted) setState(() => _temporaryPassword = temporary);
    } on ApiException catch (error) {
      _toast(error.message);
    }
  }

  Future<void> _resetClient() async {
    final confirmed = await _confirm(
      title: 'Reset client data?',
      body: "This clears the client's tracking history. Their account and "
          'profile stay.',
      confirmLabel: 'Reset data',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(formsGroupsApiProvider).resetClient(widget.clientId);
      _toast('Client data reset.');
      await _load();
    } catch (_) {
      _toast('Could not reset the client.');
    }
  }

  Future<void> _deleteClient() async {
    final name = _client?.displayName ?? 'This client';
    final confirmed = await _confirm(
      title: 'Delete client permanently?',
      body: '$name and all their data will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(formsGroupsApiProvider).deleteClient(widget.clientId);
      if (mounted) context.go(Routes.professionalClients);
    } catch (_) {
      _toast('Could not delete the client.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: destructive ? context.colors.error : null,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    final client = _client;

    return Scaffold(
      appBar: AppBar(
        title: Text(client?.displayName.isNotEmpty ?? false
            ? client!.displayName
            : 'Client'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalClients)),
      ),
      body: _loading
          ? const PagePad(
              children: [
                SkeletonBox(height: 90),
                SkeletonBox(height: 44),
                SkeletonBox(height: 160),
              ],
            )
          : Column(
              children: [
                _Header(
                  client: client,
                  initials: _initials,
                  onboarding: _onboardingLabel,
                ),
                _TabBar(
                  tab: _tab,
                  unread: _chatUnreadCount,
                  onSelect: (tab) {
                    setState(() => _tab = tab);
                    if (tab == DetailTab.chat) _loadChat();
                  },
                ),
                Expanded(child: _body()),
              ],
            ),
    );
  }

  Widget _body() {
    if (_message.isNotEmpty) {
      return PagePad(children: [ErrorNote(message: _message, onRetry: _load)]);
    }
    return switch (_tab) {
      DetailTab.info => _infoTab(),
      DetailTab.overview => _overviewTab(),
      DetailTab.tracking => _trackingTab(),
      DetailTab.chat => _chatTab(),
      DetailTab.actions => _actionsTab(),
    };
  }

  Widget _infoTab() {
    final changes = _proposedChanges;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_detail?.pendingChangeRequest != null) ...[
          AppCard(
            color: context.tokens.primarySoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.rate_review_outlined,
                        size: 20, color: context.colors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _detail!.pendingChangeRequest!.isDeletion
                            ? 'Account deletion requested'
                            : 'Profile change requested',
                        style: context.text.titleSmall,
                      ),
                    ),
                  ],
                ),
                if (_detail!.pendingChangeRequest!.clientNote.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '"${_detail!.pendingChangeRequest!.clientNote}"',
                    style: context.text.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                for (final change in changes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          change.label,
                          style: context.text.labelSmall?.copyWith(
                            color: context.tokens.muted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${change.from.isEmpty ? '—' : change.from}  →  ${change.to}',
                          style: context.text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _isReviewing ? null : () => _review('approve'),
                        child: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isReviewing ? null : () => _review('reject'),
                        child: const Text('Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Registration details', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              if (_registrationFields.isEmpty)
                const EmptyState(message: 'No registration fields.')
              else
                for (final field in _registrationFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(field.label, style: context.text.bodySmall),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            _client?.registrationAnswers[field.answerKey]
                                    ?.trim()
                                    .isNotEmpty ??
                                    false
                                ? _client!.registrationAnswers[field.answerKey]!
                                : '—',
                            style: context.text.titleSmall,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Professional notes', style: context.text.titleSmall),
              Text(
                'Private to you.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Anything worth remembering about this client…',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _isSavingNotes ? null : _saveNotes,
                child: Text(_isSavingNotes ? 'Saving…' : 'Save notes'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _overviewTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        SectionHeader(
          title: 'Schedule',
          actionLabel: _showReminderForm ? 'Close' : 'Add',
          onAction: () => setState(() => _showReminderForm = !_showReminderForm),
          topSpace: 0,
        ),
        if (_showReminderForm) ...[
          AppCard(
            child: Column(
              children: [
                TextField(
                  controller: _reminderTitle,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Progress review',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: now,
                            firstDate: now.subtract(const Duration(days: 365)),
                            lastDate: now.add(const Duration(days: 365 * 2)),
                          );
                          if (picked != null) setState(() => _reminderDate = picked);
                        },
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: AppSize.iconRow),
                        label: Text(
                          _reminderDate == null
                              ? 'Date'
                              : shortDate(_isoDate(_reminderDate!)),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked != null) setState(() => _reminderTime = picked);
                        },
                        icon: const Icon(Icons.schedule, size: AppSize.iconRow),
                        label: Text(
                          _reminderTime == null
                              ? 'Any time'
                              : _isoTime(_reminderTime!),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _reminderTitle.text.trim().isEmpty ||
                          _reminderDate == null
                      ? null
                      : _addReminder,
                  child: const Text('Add schedule'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_reminders.isEmpty)
          const EmptyState(message: 'No schedules for this client.')
        else
          for (final reminder in _reminders)
            RowItem(
              title: reminder.title,
              subtitle:
                  '${weekdayDate(reminder.date)}${reminder.time.isNotEmpty ? ' · ${hhmm(reminder.time)}' : ''}',
              leading: IconButton(
                onPressed: () => _toggleReminder(reminder),
                icon: Icon(
                  reminder.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: reminder.isDone
                      ? context.tokens.success
                      : context.tokens.muted,
                ),
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                tooltip: reminder.isDone ? 'Mark pending' : 'Mark done',
              ),
              trailing: IconButton(
                onPressed: () => _removeReminder(reminder),
                icon: const Icon(Icons.delete_outline),
                iconSize: AppSize.iconRow,
                color: context.colors.error,
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete',
              ),
            ),

        const SectionHeader(title: 'Progress'),
        if (_progress.isEmpty)
          const EmptyState(message: 'No progress records yet.')
        else
          for (final entry in _progress)
            RowItem(
              title: entry.title,
              subtitle: [
                shortDate(entry.date),
                if (entry.status.isNotEmpty) entry.status,
                if (entry.nextStep.isNotEmpty) 'Next: ${entry.nextStep}',
              ].join(' · '),
            ),
      ],
    );
  }

  Widget _trackingTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assign a template', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              if (_assignableTemplates.isEmpty)
                Text(
                  _allTemplates.isEmpty
                      ? 'No templates exist yet.'
                      : 'Every template is already assigned.',
                  style: context.text.bodySmall,
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _templateToAssign > 0 ? _templateToAssign : null,
                        decoration: const InputDecoration(labelText: 'Template'),
                        hint: const Text('Choose'),
                        items: _assignableTemplates
                            .map((t) => DropdownMenuItem(
                                  value: t.id,
                                  child: Text(
                                    t.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _templateToAssign = value ?? 0),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton(
                      onPressed: _templateToAssign == 0 || _isAssigning
                          ? null
                          : _assign,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(80, AppSize.buttonHeightSm),
                      ),
                      child: Text(_isAssigning ? '…' : 'Assign'),
                    ),
                  ],
                ),
            ],
          ),
        ),

        const SectionHeader(title: 'Assigned templates'),
        if (_assignments.isEmpty)
          const EmptyState(message: 'No templates assigned yet.')
        else
          for (final assignment in _assignments)
            RowItem(
              title: assignment.templateName,
              subtitle:
                  '${TemplateCadence.label(assignment.templateCadence)}${assignment.references.isNotEmpty ? ' · ${assignment.references.length} refs' : ''}',
              trailing: IconButton(
                onPressed: () => _unassign(assignment),
                icon: const Icon(Icons.link_off),
                iconSize: AppSize.iconRow,
                color: context.colors.error,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove',
              ),
              onTap: () => context.go(
                '${Routes.professionalClients}/${widget.clientId}/templates/${assignment.id}',
              ),
            ),
      ],
    );
  }

  Widget _chatTab() {
    return Column(
      children: [
        Expanded(
          child: _chatMessages.isEmpty
              ? const EmptyState(
                  compact: false,
                  icon: Icons.chat_bubble_outline,
                  message: 'No messages yet.\nSay hello to start the conversation.',
                )
              : ListView.builder(
                  controller: _chatScroll,
                  padding: const EdgeInsets.all(AppSpacing.screen),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) =>
                      _ChatBubble(message: _chatMessages[index]),
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatDraft,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChat(),
                    decoration: const InputDecoration(hintText: 'Message…'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filled(
                  onPressed: _sendChat,
                  icon: const Icon(Icons.send),
                  iconSize: AppSize.iconRow,
                  tooltip: 'Send',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionsTab() {
    final client = _client;

    return PagePad(
      children: [
        if (_temporaryPassword.isNotEmpty) ...[
          AppCard(
            color: context.tokens.success.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Temporary password set', style: context.text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                SelectableText(
                  _temporaryPassword,
                  style: context.text.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Share it with the client. They must change it on next login.',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        _ActionRow(
          icon: client?.isActive ?? true ? Icons.pause_circle_outline : Icons.play_circle_outline,
          title: client?.isActive ?? true ? 'Deactivate account' : 'Activate account',
          subtitle: client?.isActive ?? true
              ? 'Stops the client logging in. Data is kept.'
              : 'Lets the client log in again.',
          onTap: _toggleActive,
        ),
        _ActionRow(
          icon: Icons.key_outlined,
          title: 'Reset password',
          subtitle: 'Set a new temporary password.',
          onTap: _resetPassword,
        ),
        _ActionRow(
          icon: Icons.restart_alt,
          title: 'Reset client data',
          subtitle: 'Clears tracking history. Account and profile stay.',
          destructive: true,
          onTap: _resetClient,
        ),
        _ActionRow(
          icon: Icons.delete_forever_outlined,
          title: 'Delete client',
          subtitle: 'Removes the client and all their data. Cannot be undone.',
          destructive: true,
          onTap: _deleteClient,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.client,
    required this.initials,
    required this.onboarding,
  });

  final ClientAccessRecord? client;
  final String initials;
  final String onboarding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.sm,
        AppSpacing.screen,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          AppAvatar(
            initials: initials,
            imageUrl: Env.mediaUrl(client?.photo ?? ''),
            size: 48,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client?.displayName ?? '',
                  style: context.text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${client?.groupName ?? ''} · $onboarding',
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!(client?.isActive ?? true))
            const StatusPill(label: 'Inactive', tone: PillTone.bad),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tab,
    required this.unread,
    required this.onSelect,
  });

  final DetailTab tab;
  final int unread;
  final ValueChanged<DetailTab> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = {
      DetailTab.info: 'Info',
      DetailTab.overview: 'Overview',
      DetailTab.tracking: 'Tracking',
      DetailTab.chat: 'Chat',
      DetailTab.actions: 'Actions',
    };
    final tokens = context.tokens;

    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screen),
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: InkWell(
                onTap: () => onSelect(entry.key),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tab == entry.key
                        ? context.colors.primary
                        : context.colors.surface,
                    border: Border.all(
                      color: tab == entry.key
                          ? context.colors.primary
                          : tokens.border,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    children: [
                      Text(
                        entry.value,
                        style: context.text.labelMedium?.copyWith(
                          color: tab == entry.key
                              ? context.colors.onPrimary
                              : tokens.muted,
                        ),
                      ),
                      if (entry.key == DetailTab.chat && unread > 0) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: context.text.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessageRecord message;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final mine = message.isProfessional;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: mine ? context.colors.primary : tokens.surfaceSoft,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(AppRadius.md),
            topRight: const Radius.circular(AppRadius.md),
            bottomLeft: Radius.circular(mine ? AppRadius.md : 2),
            bottomRight: Radius.circular(mine ? 2 : AppRadius.md),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: context.text.bodyMedium?.copyWith(
                color: mine ? context.colors.onPrimary : context.colors.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateTimeLabel(message.createdAt),
              style: context.text.labelSmall?.copyWith(
                color: mine
                    ? context.colors.onPrimary.withValues(alpha: 0.75)
                    : tokens.muted,
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.colors.error : context.colors.onSurface;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall?.copyWith(color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: AppSize.iconRow,
              color: context.tokens.muted,
            ),
          ],
        ),
      ),
    );
  }
}
