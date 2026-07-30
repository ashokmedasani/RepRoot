import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/scheduling_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/scheduling_api.dart';
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
  List<ScheduledMeetingRecord> _meetings = [];

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

  bool _isSavingClientInfo = false;
  bool _isSavingAdditional = false;
  bool _isUploadingPhoto = false;
  bool _isExportingClient = false;
  bool _isResettingClient = false;
  bool _isDeletingClient = false;

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
      () async {
        try {
          final response = await ref
              .read(schedulingApiProvider)
              .getMeetings(clientId: widget.clientId);
          if (mounted) setState(() => _meetings = response.meetings);
        } catch (_) {
          if (mounted) setState(() => _meetings = []);
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

  Future<void> _setAccessLevel(TemplateAssignmentRecord assignment, String level) async {
    if (assignment.clientAccessLevel == level) return;
    try {
      final updated = await ref
          .read(templatesApiProvider)
          .updateAssignmentAccessLevel(widget.clientId, assignment.id, level);
      if (!mounted) return;
      setState(() => _assignments =
          _assignments.map((a) => a.id == assignment.id ? updated : a).toList());
      _toast('Client access updated.');
    } catch (_) {
      _toast('Could not update access level.');
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

  Future<void> _scheduleMeeting() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    final notesCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    var durationMinutes = 30;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule video meeting'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: durationMinutes,
                decoration: const InputDecoration(labelText: 'Meeting length'),
                items: const [
                  DropdownMenuItem(value: 15, child: Text('15 minutes')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => durationMinutes = value);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: 'Title (optional)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => context.pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      titleCtrl.dispose();
      notesCtrl.dispose();
      return;
    }
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      final meeting = await ref.read(schedulingApiProvider).createMeeting(
            client: widget.clientId,
            start: start.toIso8601String(),
            durationMinutes: durationMinutes,
            title: titleCtrl.text.trim(),
            notes: notesCtrl.text.trim(),
          );
      if (mounted) setState(() => _meetings = [..._meetings, meeting]);
      _toast('Meeting scheduled.');
    } on ApiException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Could not schedule the meeting.');
    }
    titleCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _cancelMeeting(ScheduledMeetingRecord meeting) async {
    final confirmed = await _confirm(
      title: 'Cancel this meeting?',
      body: 'The client will be notified.',
      confirmLabel: 'Cancel meeting',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      final updated = await ref.read(schedulingApiProvider).cancelMeeting(meeting.id);
      if (!mounted) return;
      setState(() =>
          _meetings = _meetings.map((m) => m.id == meeting.id ? updated : m).toList());
    } catch (_) {
      _toast('Could not cancel the meeting.');
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

  /// The phrase the professional must type back exactly, matching the web's
  /// destructive-action verification (client username, or reference ID for
  /// info-only clients with no login).
  String get _expectedConfirmation {
    final client = _client;
    if (client == null) return '';
    return client.username.isNotEmpty ? client.username : client.referenceId;
  }

  Future<void> _resetClient() async {
    final client = _client;
    if (client == null || _isResettingClient) return;
    final verification = await _verifyDangerousAction(
      title: 'Clear client history',
      impact:
          'Assignments, entries, chat, schedules, progress, additional '
          'information, and professional notes will be cleared. Identity and '
          'registration details remain. This is unrelated to their login '
          'password.',
      confirmLabel: 'Clear client history',
    );
    if (verification == null) return;
    setState(() => _isResettingClient = true);
    try {
      final updated = await ref.read(formsGroupsApiProvider).resetClient(
            widget.clientId,
            currentPassword: verification.password,
            confirmation: verification.confirmation,
            reason: verification.reason,
          );
      if (!mounted) return;
      setState(() {
        _client = updated;
        _notes.clear();
        _isResettingClient = false;
      });
      _toast('Client history cleared.');
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _isResettingClient = false);
      _toast(error.message);
    } catch (_) {
      if (mounted) setState(() => _isResettingClient = false);
      _toast('Could not clear the client history.');
    }
  }

  Future<void> _deleteClient() async {
    final client = _client;
    if (client == null || _isDeletingClient) return;
    final verification = await _verifyDangerousAction(
      title: 'Move account to Recycle Bin',
      impact:
          'Login access stops immediately. The bundled client account can be '
          'restored from the Recycle Bin during its retention period.',
      confirmLabel: 'Move to Recycle Bin',
    );
    if (verification == null) return;
    setState(() => _isDeletingClient = true);
    try {
      await ref.read(formsGroupsApiProvider).deleteClient(
            widget.clientId,
            currentPassword: verification.password,
            confirmation: verification.confirmation,
            reason: verification.reason,
          );
      if (mounted) context.go(Routes.professionalClients);
    } on ApiException catch (error) {
      if (mounted) setState(() => _isDeletingClient = false);
      _toast(error.message);
    } catch (_) {
      if (mounted) setState(() => _isDeletingClient = false);
      _toast('Could not delete the client.');
    }
  }

  Future<void> _exportClientData() async {
    if (_isExportingClient) return;
    setState(() => _isExportingClient = true);
    try {
      final bytes =
          await ref.read(formsGroupsApiProvider).exportClientData(widget.clientId);
      final refId = _client?.referenceId ?? widget.clientId.toString();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reproot-$refId-export.zip');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          subject: 'RepRoot client data export',
        ),
      );
    } on ApiException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Client data export could not be created.');
    }
    if (mounted) setState(() => _isExportingClient = false);
  }

  /// Shared verification form for the two destructive actions: current
  /// password + typed confirmation phrase + a reason. Returns null if the
  /// professional cancels or the fields don't validate.
  Future<({String password, String confirmation, String reason})?>
      _verifyDangerousAction({
    required String title,
    required String impact,
    required String confirmLabel,
  }) async {
    final expected = _expectedConfirmation;
    final passwordCtrl = TextEditingController();
    final confirmationCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String? error;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(impact, style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Your current password',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: confirmationCtrl,
                  decoration: InputDecoration(
                    labelText: 'Type $expected to confirm',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: reasonCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error!, style: TextStyle(color: context.colors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (passwordCtrl.text.isEmpty ||
                    confirmationCtrl.text.trim() != expected ||
                    reasonCtrl.text.trim().isEmpty) {
                  setDialogState(() => error =
                      'Enter your password, type $expected exactly, and give a reason.');
                  return;
                }
                context.pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.error,
                minimumSize: const Size(0, AppSize.buttonHeightSm),
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );

    final ok = result == true &&
        passwordCtrl.text.isNotEmpty &&
        confirmationCtrl.text.trim() == expected &&
        reasonCtrl.text.trim().isNotEmpty;
    final verification = ok
        ? (
            password: passwordCtrl.text,
            confirmation: confirmationCtrl.text.trim(),
            reason: reasonCtrl.text.trim(),
          )
        : null;
    passwordCtrl.dispose();
    confirmationCtrl.dispose();
    reasonCtrl.dispose();
    return verification;
  }

  // ----- client profile / additional info / photo (professional-editable) -----

  Future<void> _editClientInfo() async {
    final client = _client;
    if (client == null) return;
    final firstNameCtrl = TextEditingController(text: client.firstName);
    final lastNameCtrl = TextEditingController(text: client.lastName);
    final emailCtrl = TextEditingController(text: client.email);
    final usernameCtrl = TextEditingController(text: client.username);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit client information'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameCtrl,
                decoration: const InputDecoration(labelText: 'First name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: lastNameCtrl,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              if (client.username.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      setState(() => _isSavingClientInfo = true);
      try {
        final updated = await ref.read(formsGroupsApiProvider).updateClientProfile(
              widget.clientId,
              firstName: firstNameCtrl.text.trim(),
              lastName: lastNameCtrl.text.trim(),
              email: emailCtrl.text.trim(),
              username: client.username.isNotEmpty ? usernameCtrl.text.trim() : null,
            );
        if (mounted) setState(() => _client = updated);
        _toast('Client information updated.');
      } on ApiException catch (error) {
        _toast(error.message);
      } catch (_) {
        _toast('Client information could not be saved.');
      }
      if (mounted) setState(() => _isSavingClientInfo = false);
    }
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    emailCtrl.dispose();
    usernameCtrl.dispose();
  }

  Future<void> _pickClientPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _isUploadingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final mime = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
      final updated = await ref
          .read(formsGroupsApiProvider)
          .updateClientPhoto(widget.clientId, dataUrl);
      if (mounted) setState(() => _client = updated);
      _toast('Client photo updated.');
    } on ApiException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Could not update the client photo.');
    }
    if (mounted) setState(() => _isUploadingPhoto = false);
  }

  Future<void> _persistAdditionalInfo(List<AdditionalInfoItem> items, {bool? shared}) async {
    if (_isSavingAdditional) return;
    final previous = _client;
    setState(() => _isSavingAdditional = true);
    try {
      final updated = await ref.read(formsGroupsApiProvider).updateClientAdditionalInfo(
            widget.clientId,
            items,
            shared: shared,
          );
      if (mounted) setState(() => _client = updated);
    } on ApiException catch (error) {
      if (mounted) setState(() => _client = previous);
      _toast(error.message);
    } catch (_) {
      if (mounted) setState(() => _client = previous);
      _toast('Additional information could not be saved.');
    }
    if (mounted) setState(() => _isSavingAdditional = false);
  }

  Future<void> _toggleAdditionalShared(bool shared) async {
    final client = _client;
    if (client == null || client.additionalInfoShared == shared) return;
    setState(() => _client = ClientAccessRecord(
          id: client.id,
          group: client.group,
          groupName: client.groupName,
          professionalName: client.professionalName,
          referenceId: client.referenceId,
          onboardingMethod: client.onboardingMethod,
          firstName: client.firstName,
          lastName: client.lastName,
          email: client.email,
          username: client.username,
          photo: client.photo,
          registrationAnswers: client.registrationAnswers,
          additionalInfo: client.additionalInfo,
          additionalInfoShared: shared,
          mustChangePassword: client.mustChangePassword,
          isActive: client.isActive,
          createdAt: client.createdAt,
          updatedAt: client.updatedAt,
          leadSubmission: client.leadSubmission,
          registrationSubmission: client.registrationSubmission,
        ));
    await _persistAdditionalInfo(client.additionalInfo, shared: shared);
  }

  Future<void> _addAdditionalInfoItem() async {
    final titleCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    String type = AdditionalInfoType.text;
    String visibility = 'private';

    final add = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add additional information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: AdditionalInfoType.text, child: Text('Text')),
                    DropdownMenuItem(value: AdditionalInfoType.link, child: Text('Link')),
                  ],
                  onChanged: (value) => setDialogState(() => type = value ?? AdditionalInfoType.text),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (type == AdditionalInfoType.text)
                  TextField(
                    controller: textCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Text'),
                  )
                else
                  TextField(
                    controller: linkCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'URL'),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shared with client'),
                  value: visibility == 'client',
                  onChanged: (value) =>
                      setDialogState(() => visibility = value ? 'client' : 'private'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty ? null : () => context.pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (add == true && titleCtrl.text.trim().isNotEmpty) {
      final item = AdditionalInfoItem(
        id: 'item-${DateTime.now().millisecondsSinceEpoch}',
        title: titleCtrl.text.trim(),
        type: type,
        visibility: visibility,
        text: type == AdditionalInfoType.text ? textCtrl.text.trim() : '',
        link: type == AdditionalInfoType.link ? linkCtrl.text.trim() : '',
      );
      final client = _client;
      if (client != null) {
        await _persistAdditionalInfo([...client.additionalInfo, item]);
      }
    }
    titleCtrl.dispose();
    textCtrl.dispose();
    linkCtrl.dispose();
  }

  Future<void> _toggleAdditionalItemVisibility(AdditionalInfoItem item) async {
    final client = _client;
    if (client == null) return;
    final nextVisibility = item.visibility == 'client' ? 'private' : 'client';
    final items = client.additionalInfo
        .map((i) => i.id == item.id
            ? AdditionalInfoItem(
                id: i.id,
                title: i.title,
                type: i.type,
                visibility: nextVisibility,
                text: i.text,
                link: i.link,
                referenceId: i.referenceId,
                referenceTitle: i.referenceTitle,
              )
            : i)
        .toList();
    await _persistAdditionalInfo(items);
  }

  Future<void> _removeAdditionalInfoItem(AdditionalInfoItem item) async {
    final client = _client;
    if (client == null) return;
    final confirmed = await _confirm(
      title: 'Delete "${item.title}"?',
      body: 'This item will be removed from the client profile.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    final items = client.additionalInfo.where((i) => i.id != item.id).toList();
    await _persistAdditionalInfo(items);
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
              Row(
                children: [
                  Expanded(
                    child: Text('Client information', style: context.text.titleSmall),
                  ),
                  IconButton(
                    onPressed: _isUploadingPhoto ? null : _pickClientPhoto,
                    icon: _isUploadingPhoto
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    tooltip: 'Update photo',
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: _isSavingClientInfo ? null : _editClientInfo,
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              _infoRow('First name', _client?.firstName ?? ''),
              _infoRow('Last name', _client?.lastName ?? ''),
              _infoRow('Email', _client?.email ?? ''),
              if ((_client?.username ?? '').isNotEmpty)
                _infoRow('Username', _client!.username),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

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
              Row(
                children: [
                  Expanded(
                    child: Text('Additional information', style: context.text.titleSmall),
                  ),
                  IconButton(
                    onPressed: _isSavingAdditional ? null : _addAdditionalInfoItem,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add item',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Share this section with the client'),
                value: _client?.additionalInfoShared ?? false,
                onChanged: _isSavingAdditional ? null : _toggleAdditionalShared,
              ),
              if ((_client?.additionalInfo ?? []).isEmpty)
                const EmptyState(message: 'No additional information yet.')
              else
                for (final item in _client!.additionalInfo)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title, style: context.text.bodyMedium),
                              Text(
                                item.type == AdditionalInfoType.link
                                    ? item.link
                                    : item.text,
                                style: context.text.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _isSavingAdditional
                              ? null
                              : () => _toggleAdditionalItemVisibility(item),
                          icon: Icon(
                            item.isSharedWithClient
                                ? Icons.visibility
                                : Icons.visibility_off_outlined,
                            color: item.isSharedWithClient
                                ? context.colors.primary
                                : context.tokens.muted,
                          ),
                          tooltip: item.isSharedWithClient
                              ? 'Shared with client'
                              : 'Private',
                          iconSize: AppSize.iconRow,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: _isSavingAdditional
                              ? null
                              : () => _removeAdditionalInfoItem(item),
                          icon: const Icon(Icons.delete_outline),
                          iconSize: AppSize.iconRow,
                          color: context.colors.error,
                          visualDensity: VisualDensity.compact,
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

  Widget _infoRow(String label, String value) => Padding(
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
              child: Text(
                value.trim().isNotEmpty ? value : '—',
                style: context.text.titleSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );

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

        SectionHeader(
          title: 'Meetings',
          actionLabel: 'Schedule',
          onAction: _scheduleMeeting,
        ),
        if (_meetings.isEmpty)
          const EmptyState(message: 'No meetings scheduled with this client.')
        else
          for (final meeting in _meetings)
            RowItem(
              title: meeting.title.isNotEmpty ? meeting.title : 'Meeting',
              subtitle: [
                if (meeting.startAt != null)
                  dateTimeLabel(meeting.startAt!.toIso8601String()),
                meeting.status,
                'Response: ${meeting.clientResponseStatus}',
              ].join(' · '),
              trailing: meeting.status == MeetingStatus.scheduled
                  ? IconButton(
                      onPressed: () => _cancelMeeting(meeting),
                      icon: const Icon(Icons.event_busy),
                      iconSize: AppSize.iconRow,
                      color: context.colors.error,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Cancel meeting',
                    )
                  : null,
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
                  '${TemplateCadence.label(assignment.templateCadence)}'
                  '${assignment.resources.isNotEmpty ? ' · ${assignment.resources.length} resources' : ''}'
                  ' · ${TemplateClientAccessLevel.label(assignment.clientAccessLevel)}',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Client access',
                    icon: const Icon(Icons.lock_outline, size: AppSize.iconRow),
                    initialValue: assignment.clientAccessLevel,
                    onSelected: (value) => _setAccessLevel(assignment, value),
                    itemBuilder: (context) => [
                      for (final level in TemplateClientAccessLevel.all)
                        PopupMenuItem(
                          value: level,
                          child: Text(TemplateClientAccessLevel.label(level)),
                        ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => _unassign(assignment),
                    icon: const Icon(Icons.link_off),
                    iconSize: AppSize.iconRow,
                    color: context.colors.error,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                  ),
                ],
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
          icon: Icons.payments_outlined,
          title: 'Payments',
          subtitle: 'Send payment requests and review proofs.',
          onTap: () => context.go(
            '${Routes.professionalClients}/${widget.clientId}/payments'
            '?name=${Uri.encodeQueryComponent(client?.displayName ?? 'Client')}',
          ),
        ),

        const SectionHeader(title: 'Destructive data actions'),
        _ActionRow(
          icon: Icons.download_outlined,
          title: _isExportingClient ? 'Preparing export…' : 'Download client data',
          subtitle: 'Export everything before clearing history or deleting.',
          onTap: _isExportingClient ? () {} : _exportClientData,
        ),
        _ActionRow(
          icon: Icons.restart_alt,
          title: _isResettingClient ? 'Clearing…' : 'Clear client history',
          subtitle:
              'Clears tracking, chat, schedules, and notes. Identity and '
              'registration details stay. Requires your password.',
          destructive: true,
          onTap: _isResettingClient ? () {} : _resetClient,
        ),
        _ActionRow(
          icon: Icons.delete_forever_outlined,
          title: _isDeletingClient ? 'Moving to Recycle Bin…' : 'Delete client',
          subtitle:
              'Moves the account to your Recycle Bin (restorable). Requires '
              'your password.',
          destructive: true,
          onTap: _isDeletingClient ? () {} : _deleteClient,
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
