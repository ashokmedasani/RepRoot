import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'widgets/client_payments_panel.dart';

enum DetailTab { workspace, templates, payments, actions }

/// Client detail — Workspace / Templates / Chat / Payments / Actions,
/// matching the website's professional-client-profile page: an
/// always-visible header card (identity, edit, details) above the tab strip.
/// Templates (Progress + assign/assigned) has its own tab per the user's
/// latest request, rather than living inside Workspace.
class ProfessionalClientDetailPage extends ConsumerStatefulWidget {
  const ProfessionalClientDetailPage({super.key, required this.clientId});

  final int clientId;

  @override
  ConsumerState<ProfessionalClientDetailPage> createState() =>
      _ProfessionalClientDetailPageState();
}

class _ProfessionalClientDetailPageState
    extends ConsumerState<ProfessionalClientDetailPage> {
  DetailTab _tab = DetailTab.workspace;

  ClientAccessDetailResponse? _detail;
  ClientAccessRecord? _client;
  List<DynamicField> _registrationFields = [];
  List<ClientReminder> _reminders = [];
  List<TemplateAssignmentRecord> _assignments = [];
  List<TrackingTemplateRecord> _allTemplates = [];
  List<ScheduledMeetingRecord> _meetings = [];

  /// Newest-first (defensively sorted in [_load]) — feeds the Client Activity
  /// KPI row exactly the way templatesApi.getClientEntries feeds the web's
  /// professional-client-profile.component.ts.
  List<TrackingEntryRecord> _entries = [];

  final _notes = TextEditingController();
  final _reminderTitle = TextEditingController();

  /// Optional note sent back to the client with an approve/reject decision —
  /// the web's `changeReviewNote` textarea.
  final _changeReviewNote = TextEditingController();

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

  /// Registration fields shown in the View-profile sheet —
  /// additional information, collapsed by default (the web's `showAllClientInfo`).

  bool _isSavingClientInfo = false;
  bool _isSavingAdditional = false;
  bool _isExportingClient = false;
  bool _isResettingClient = false;
  bool _isDeletingClient = false;
  bool _isGrantingAccess = false;
  bool _isRevokingAccess = false;


  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    // Only the unread count is needed here now; the conversation itself
    // polls inside ProfessionalClientChatPage.
    _unreadPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _notes.dispose();
    _reminderTitle.dispose();
    _changeReviewNote.dispose();
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

  List<TrackingTemplateRecord> get _assignableTemplates {
    final assigned = _assignments.map((a) => a.templateId).toSet();
    return _allTemplates.where((t) => !assigned.contains(t.id)).toList();
  }

  // ----- Client Activity KPIs — ported 1:1 from
  // professional-client-profile.component.ts's entriesThisMonth/lastEntry/
  // streak/completionPercent getters. _entries is sorted newest-first
  // defensively in [_load]. -----

  /// The web's "Total Entries" tile is labelled as a total but is actually
  /// `entriesThisMonth` (its own "This month" caption confirms it) — count of
  /// entries whose date falls in the current month, not the all-time count.
  /// Was `_entries.length` here, which showed a much bigger (all-time) number
  /// than the website for the same client.
  int get _totalEntries {
    final monthPrefix = isoDate(DateTime.now()).substring(0, 7);
    return _entries.where((e) => e.entryDate.startsWith(monthPrefix)).length;
  }

  TrackingEntryRecord? get _lastEntry => _entries.isNotEmpty ? _entries.first : null;

  int get _currentStreak {
    final entryDates = _entries.map((e) => e.entryDate).toSet();
    var streak = 0;
    var cursor = DateTime.now();
    if (!entryDates.contains(isoDate(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    while (entryDates.contains(isoDate(cursor))) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get _completionPercent {
    final now = DateTime.now();
    final monthPrefix = isoDate(now).substring(0, 7);
    final daysWithEntries = _entries
        .where((e) => e.entryDate.startsWith(monthPrefix))
        .map((e) => e.entryDate)
        .toSet()
        .length;
    return min(100, ((daysWithEntries / now.day) * 100).round());
  }

  String _labelFor(String key) {
    final field = _registrationFields.where((f) => f.answerKey == key).firstOrNull;
    return field?.label ?? key.replaceAll('_', ' ');
  }

  /// The web's Field / Current / Requested diff rows: identity fields are shown
  /// in the client-information card instead, and rows whose value did not
  /// actually change are dropped, so only real edits are put up for review.
  List<({String label, String from, String to})> get _proposedChanges {
    final request = _detail?.pendingChangeRequest;
    final client = _client;
    if (request == null || client == null) return [];

    const identityKeys = ['first_name', 'last_name', 'email'];
    final rows = <({String label, String from, String to})>[];

    for (final entry in request.proposedAnswers.entries) {
      if (identityKeys.contains(entry.key)) continue;

      final from = (client.registrationAnswers[entry.key] ?? '').trim();
      final to = entry.value.trim();
      if (from == to) continue;

      rows.add((
        label: _labelFor(entry.key),
        from: from.isEmpty ? 'Not added' : from,
        to: to.isEmpty ? 'Not added' : to,
      ));
    }

    return rows;
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
      () async {
        try {
          final entries = await templatesApi.getClientEntries(widget.clientId);
          // The web assumes its API response arrives newest-first; sort
          // defensively here rather than assuming the same of this endpoint.
          final sorted = [...entries]..sort((a, b) {
              final byDate = b.entryDate.compareTo(a.entryDate);
              return byDate != 0 ? byDate : b.id.compareTo(a.id);
            });
          if (mounted) setState(() => _entries = sorted);
        } catch (_) {
          if (mounted) setState(() => _entries = []);
        }
      }(),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  /// Polls incrementally: only messages newer than the last one seen.
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
      final result = await ref.read(formsGroupsApiProvider).reviewChangeRequest(
            widget.clientId,
            request.id,
            action,
            note: _changeReviewNote.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _client = result.client;
        _changeReviewNote.clear();
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
            date: isoDate(date),
            time: _reminderTime == null ? null : isoTime(_reminderTime!),
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

  // ----- portal access -----

  /// Grants a manually-created client their own login. The professional picks
  /// the username and an initial password (prefilled with a generated
  /// suggestion, same as the create-client flow) and can have the credentials
  /// emailed instead of reading them out.
  ///
  /// The password fields are collected in a sheet and posted straight to the
  /// backend, which is what validates them — matching the web, whose dialog
  /// also defers the match/strength check to the API so both platforms surface
  /// the identical message.
  Future<void> _grantPortalAccess() async {
    final client = _client;
    if (client == null || _isGrantingAccess) return;

    final suggested = _generateTemporaryPassword();
    final usernameCtrl = TextEditingController(
      text: client.email.isNotEmpty ? client.email.split('@').first : '',
    );
    final passwordCtrl = TextEditingController(text: suggested);
    final confirmCtrl = TextEditingController(text: suggested);
    var sendCredentials = client.email.isNotEmpty;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screen,
          AppSpacing.screen,
          AppSpacing.screen,
          MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.screen,
        ),
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Grant portal access', style: context.text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Creates a login for ${client.firstName} ${client.lastName}. '
                'They must change the password the first time they sign in.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: usernameCtrl,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: passwordCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  helperText: 'Min 8 characters, 1 special character.',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: confirmCtrl,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Confirm password'),
              ),
              if (client.email.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: sendCredentials,
                  onChanged: (value) =>
                      setSheetState(() => sendCredentials = value ?? false),
                  title: const Text('Email the credentials to the client'),
                  subtitle: Text(client.email, style: context.text.bodySmall),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => sheetContext.pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => sheetContext.pop(true),
                      child: const Text('Grant access'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    final username = usernameCtrl.text.trim().toLowerCase();
    final password = passwordCtrl.text;
    final confirmPassword = confirmCtrl.text;
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    confirmCtrl.dispose();

    if (confirmed != true) return;
    if (username.isEmpty || password.isEmpty) {
      _toast('Enter a username and password.');
      return;
    }

    setState(() => _isGrantingAccess = true);
    try {
      final result = await ref.read(formsGroupsApiProvider).grantPortalAccess(
            widget.clientId,
            username: username,
            password: password,
            confirmPassword: confirmPassword,
            sendCredentials: sendCredentials,
          );
      if (!mounted) return;
      setState(() {
        _client = result.client;
        // Surfaced in the same banner the reset-password flow uses, so the
        // professional can still read the password out when the email either
        // wasn't requested or didn't send.
        _temporaryPassword =
            result.credentialsSent ? '' : result.temporaryPassword;
        _isGrantingAccess = false;
      });
      _toast(result.message.isNotEmpty ? result.message : 'Portal access granted.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _isGrantingAccess = false);
      _toast(error.message);
    } catch (_) {
      if (mounted) setState(() => _isGrantingAccess = false);
      _toast('Could not grant portal access.');
    }
  }

  Future<void> _revokePortalAccess() async {
    final client = _client;
    if (client == null || _isRevokingAccess) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke portal access?'),
        content: Text(
          '${client.firstName} ${client.lastName} will no longer be able to '
          'sign in. Their record, tracking history and chat are all kept, and '
          'you can grant access again later.',
          style: context.text.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Revoke access'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRevokingAccess = true);
    try {
      final result =
          await ref.read(formsGroupsApiProvider).revokePortalAccess(widget.clientId);
      if (!mounted) return;
      setState(() {
        _client = result.client;
        _temporaryPassword = '';
        _isRevokingAccess = false;
      });
      _toast(result.message.isNotEmpty ? result.message : 'Portal access revoked.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _isRevokingAccess = false);
      _toast(error.message);
    } catch (_) {
      if (mounted) setState(() => _isRevokingAccess = false);
      _toast('Could not revoke portal access.');
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
          hasPortalAccess: client.hasPortalAccess,
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
        actions: [
          // Top-right of the page, in brand blue, labelled as well as
          // iconned — chat is the single most-used action on a client and
          // shouldn't be hunted for among the tabs.
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TextButton.icon(
              onPressed: _openChat,
              style: TextButton.styleFrom(
                foregroundColor: context.colors.primary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              icon: Badge(
                isLabelVisible: _chatUnreadCount > 0,
                backgroundColor: context.colors.error,
                label: Text(_chatUnreadCount > 99 ? '99+' : '$_chatUnreadCount'),
                child: Icon(
                  _chatUnreadCount > 0
                      ? Icons.chat_bubble
                      : Icons.chat_bubble_outline,
                  size: AppSize.iconRow,
                ),
              ),
              label: const Text('Chat'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const PagePad(
              children: [
                SkeletonBox(height: 90),
                SkeletonBox(height: 44),
                SkeletonBox(height: 160),
              ],
            )
          // Header and tab bar scroll away with the content instead of being
          // pinned above a separate scroll region. Pinned, they cost ~180pt of
          // a phone screen permanently — on the Workspace tab that left barely
          // half the viewport for the thing you actually came to read.
          : NestedScrollView(
              headerSliverBuilder: (context, innerScrolled) => [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.sm,
                      AppSpacing.screen,
                      AppSpacing.md,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _headerCard(),
                        if (_detail?.pendingChangeRequest != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _changeRequestCard(),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      0,
                      AppSpacing.screen,
                      AppSpacing.sm,
                    ),
                    child: _TabBar(
                      tab: _tab,
                      unread: _chatUnreadCount,
                      onSelect: (tab) => setState(() => _tab = tab),
                    ),
                  ),
                ),
              ],
              body: _body(),
            ),
    );
  }

  Widget _body() {
    if (_message.isNotEmpty) {
      return PagePad(children: [ErrorNote(message: _message, onRetry: _load)]);
    }
    return switch (_tab) {
      DetailTab.workspace => _workspaceTab(),
      DetailTab.templates => _templatesTab(),
      DetailTab.payments => _paymentsTab(),
      DetailTab.actions => _actionsTab(),
    };
  }

  /// Always-visible header — photo, name, status, group, and a "View profile"
  /// entry point. Deliberately identity-only: the full record (info grid,
  /// registration answers, additional information, editing) lives in
  /// [_openClientProfileSheet] so it costs nothing on the tabs where you
  /// aren't reading it.
  Widget _headerCard() {
    final client = _client;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Read-only. A client's photo is theirs to set from their own
              // account — a professional overwriting someone's picture isn't
              // a permission this app should hand out, so the camera overlay
              // that used to sit here is gone.
              AppAvatar(
                initials: _initials,
                imageUrl: Env.mediaUrl(client?.photo ?? ''),
                size: 64,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.xs,
                      runSpacing: 4,
                      children: [
                        Text(client?.displayName ?? '', style: context.text.titleMedium),
                        StatusPill(
                          label: (client?.isActive ?? true) ? 'Active' : 'Inactive',
                          tone: (client?.isActive ?? true) ? PillTone.good : PillTone.bad,
                        ),
                        if (!(client?.hasPortalAccess ?? true))
                          const StatusPill(label: 'No portal access'),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Identity only: name, status, group. Everything else
                    // moved into the View-profile sheet.
                    if ((client?.groupName ?? '').isNotEmpty)
                      Text(client!.groupName, style: context.text.bodySmall),
                  ],
                ),
              ),
              // "View profile" rather than "Edit Profile": everything that
              // used to sit in an always-visible info grid plus a "Show all
              // details" expander now lives one tap away in a sheet. That grid
              // cost ~200pt on every tab of this page — including Chat, where
              // it left about three message bubbles visible. Editing moves
              // into the sheet, below the details it edits.
              // Both actions live here: View profile opens the full record,
              // Edit goes straight to editing without the extra hop through
              // the sheet. Stacked rather than side-by-side so neither label
              // truncates next to a long client name.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _openClientProfileSheet,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.badge_outlined, size: 15),
                    label: const Text('View profile'),
                  ),
                  TextButton.icon(
                    onPressed: _isSavingClientInfo ? null : _editClientInfo,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(_isSavingClientInfo ? 'Saving…' : 'Edit profile'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }


  /// Everything about the client that used to crowd the page header: the info
  /// grid, registration answers, and the Additional Information editor.
  ///
  /// Presented as a sheet rather than a route so it can be dismissed straight
  /// back to whichever tab you were on. Mutating actions (add/remove/share an
  /// additional-info item, edit the profile) update the page's own state, so
  /// the sheet is rebuilt through [setSheetState] after each one to avoid
  /// showing a stale copy of `_client`.
  Future<void> _openClientProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetContext, scrollController) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final client = _client;
            final phoneField = _registrationFields
                .where((f) => f.fieldType == DynamicFieldType.phone)
                .firstOrNull;
            final phoneValue = phoneField == null
                ? ''
                : (client?.registrationAnswers[phoneField.answerKey] ?? '').trim();

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screen,
                0,
                AppSpacing.screen,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  client?.displayName ?? 'Client profile',
                  style: context.text.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                // 2-column info grid, laid out the way the website's
                // client-info-grid does rather than as stacked full-width
                // label/value rows.
                _infoGrid([
                  ('Email', client?.email ?? ''),
                  (
                    'Username',
                    (client?.username.isNotEmpty ?? false)
                        ? client!.username
                        : ((client?.hasPortalAccess ?? true) ? '' : 'No portal access'),
                  ),
                  ('Group', client?.groupName ?? ''),
                  ('Status', (client?.isActive ?? true) ? 'Active' : 'Inactive'),
                  if (phoneValue.isNotEmpty) (phoneField!.label, phoneValue),
                ]),
                const SizedBox(height: AppSpacing.md),
                Divider(color: context.tokens.border, height: 1),
                const SizedBox(height: AppSpacing.md),
                // Joined date, Professional Code and Reference ID are real
                // fields on the record — mirrors the web's
                // clientInformationRows().
            if ((client?.createdAt ?? '').isNotEmpty)
              _infoRow('Joined date', shortDate(client!.createdAt)),
            if ((client?.professionalName ?? '').isNotEmpty)
              _infoRow('Professional Code', client!.professionalName),
            if ((client?.referenceId ?? '').isNotEmpty)
              _infoRow('Reference ID', client!.referenceId),
            Text('Registration details', style: context.text.titleSmall),
            const SizedBox(height: AppSpacing.md),
            if (_registrationFields.isEmpty)
              const EmptyState(message: 'No registration fields.')
            else
              for (final field in _registrationFields)
                _infoRow(
                  field.label,
                  client?.registrationAnswers[field.answerKey]?.trim().isNotEmpty ?? false
                      ? client!.registrationAnswers[field.answerKey]!
                      : '',
                ),
                const SizedBox(height: AppSpacing.lg),
                // Edit sits at the bottom, under the details it edits.
                FilledButton.icon(
                  onPressed: _isSavingClientInfo
                      ? null
                      : () async {
                          await _editClientInfo();
                          setSheetState(() {});
                        },
                  icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
                  label: Text(_isSavingClientInfo ? 'Saving…' : 'Edit profile'),
                ),
              ],
            );
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// "Profile change requested" / "Account deletion requested" review card —
  /// relocated verbatim from the old Info tab into the always-visible header
  /// area, since a pending request needing review should not be hidden
  /// behind a tab choice. All review logic (_review/_proposedChanges/_DiffLine)
  /// is unchanged.
  Widget _changeRequestCard() {
    final changes = _proposedChanges;

    return AppCard(
      color: context.tokens.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rate_review_outlined, size: 20, color: context.colors.primary),
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
          if (_detail!.pendingChangeRequest!.createdAt.isNotEmpty)
            Text(
              'Requested ${dateTimeLabel(_detail!.pendingChangeRequest!.createdAt)}',
              style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
            ),
          if (_detail!.pendingChangeRequest!.clientNote.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Client note: "${_detail!.pendingChangeRequest!.clientNote}"',
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Field / Current / Requested, as three stacked lines per row —
          // the web's diff table does not fit a phone width.
          if (changes.isEmpty)
            Text(
              'This request does not change any details.',
              style: context.text.bodySmall,
            )
          else
            for (final change in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
                    const SizedBox(height: 2),
                    _DiffLine(label: 'Current', value: change.from),
                    _DiffLine(
                      label: 'Requested',
                      value: change.to,
                      highlight: true,
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _changeReviewNote,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note to the client (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isReviewing ? null : () => _review('approve'),
                  child: Text(_isReviewing ? 'Saving…' : 'Approve'),
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

  /// The header's always-visible 2-column info grid — each field's label
  /// small/muted above its value, two per row (mirrors the website's
  /// `client-info-grid`, minus its dark theme). [fields] is a flat list of
  /// (label, value) pairs; blank values render as '—'.
  Widget _infoGrid(List<(String, String)> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, value) in fields)
              SizedBox(
                width: cellWidth,
                child: _GridInfoField(label: label, value: value),
              ),
          ],
        );
      },
    );
  }

  /// Opens the conversation as its own screen, then refreshes the unread
  /// badge on return — reading the thread clears it server-side.
  Future<void> _openChat() async {
    final name = _client?.displayName ?? '';
    await context.push(
      '${Routes.professionalClients}/${widget.clientId}/chat'
      '${name.isEmpty ? '' : '?name=${Uri.encodeQueryComponent(name)}'}',
    );
    if (mounted) _loadUnread();
  }

  /// Full-screen editor for the private notes.
  ///
  /// The draft lives in [_notes] either way, so opening and closing without
  /// saving leaves whatever was typed intact — the same controller the inline
  /// field used.
  Future<void> _openNotesEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screen,
            0,
            AppSpacing.screen,
            MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.screen,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Professional notes', style: context.text.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Private to you. The client never sees these.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                maxLines: 8,
                minLines: 5,
                autofocus: true,
                onChanged: (_) => setSheetState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Anything worth remembering about this client…',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => sheetContext.pop(),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSavingNotes
                          ? null
                          : () async {
                              await _saveNotes();
                              if (sheetContext.mounted) sheetContext.pop();
                            },
                      child: Text(_isSavingNotes ? 'Saving…' : 'Save notes'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    // Refresh the preview line on the collapsed card.
    if (mounted) setState(() {});
  }

  /// "Workspace" — Client Activity KPIs, Professional Notes, and Follow-up
  /// Scheduler + Meetings. Progress and Templates now live in their own
  /// Private professional notes — the web's `.notes-card`.
  ///
  /// Warning wash, warning border, amber heading, a lock glyph and an
  /// explicit "(Private)" suffix. Every other card on this tab is neutral
  /// white; this one deliberately is not, because it is the only content
  /// here that the client can never see, and a professional needs to know
  /// that at a glance before typing.
  Widget _privateNotesCard() {
    final tokens = context.tokens;
    final body = _notes.text.trim();

    return Container(
      decoration: BoxDecoration(
        color: tokens.warningSoft,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: tokens.warningBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.cardAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _openNotesEditor,
          borderRadius: AppRadius.cardAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: AppSize.iconRow, color: tokens.warningStrong),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Professional Notes ',
                          style: context.text.titleSmall?.copyWith(
                            color: tokens.warningStrong,
                            fontWeight: FontWeight.w800,
                          ),
                          children: [
                            TextSpan(
                              text: '(Private)',
                              style: context.text.bodySmall?.copyWith(
                                color: tokens.warningStrong,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      body.isEmpty ? 'Add' : 'Edit',
                      style: context.text.labelMedium?.copyWith(
                        color: tokens.warningStrong,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body.isEmpty
                      ? 'No notes yet. Only you can see what you write here.'
                      : body,
                  style: context.text.bodySmall?.copyWith(
                    color: body.isEmpty ? tokens.muted : context.colors.onSurface,
                    height: 1.5,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Compact Private / Shared-with-Client control for the whole Additional
  /// Information section.
  ///
  /// A menu rather than a segmented pair: it now sits inline beside the
  /// heading, where "Shared with Client" spelled out across two segments
  /// would not fit on a phone. Closed it states the current setting; open it
  /// names both options in full, so neither is guessed at.
  Widget _additionalVisibilityToggle(bool shared) {
    final tokens = context.tokens;

    return PopupMenuButton<bool>(
      enabled: !_isSavingAdditional,
      tooltip: 'Who can see this section',
      initialValue: shared,
      onSelected: (value) {
        if (value != shared) _toggleAdditionalShared(value);
      },
      itemBuilder: (menuContext) => [
        const PopupMenuItem(
          value: false,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline),
            title: Text('Private'),
            subtitle: Text('Only you'),
          ),
        ),
        const PopupMenuItem(
          value: true,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.visibility_outlined),
            title: Text('Shared with Client'),
            subtitle: Text('Visible in their portal'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: shared ? tokens.primarySoft : tokens.surfaceSoft,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: shared ? context.colors.primary : tokens.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              shared ? Icons.visibility_outlined : Icons.lock_outline,
              size: AppSize.iconRow - 2,
              color: shared ? context.colors.primary : tokens.muted,
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Text(
              shared ? 'Shared' : 'Private',
              style: context.text.labelMedium?.copyWith(
                color: shared ? context.colors.primary : tokens.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: AppSize.iconRow,
              color: shared ? context.colors.primary : tokens.muted,
            ),
          ],
        ),
      ),
    );
  }

  /// Templates tab (see [_templatesTab]).
  Widget _workspaceTab() {
    final client = _client;
    return PagePad(
      onRefresh: _load,
      children: [
        const SectionHeader(
          title: 'Client Activity',
          topSpace: 0,
          infoBody: 'How consistently this client is logging against the '
              'templates you assigned them.\n\n'
              'TOTAL ENTRIES\n'
              'Everything they submitted this calendar month.\n\n'
              'LAST ENTRY\n'
              'When they last logged anything, and against which '
              'template.\n\n'
              'STREAK\n'
              'Consecutive days with at least one entry. It resets on a '
              'missed day.\n\n'
              'COMPLETION\n'
              'Share of expected entries actually submitted this month, based '
              'on each template\'s cadence.',
        ),
        CompactStatRow(
          stats: [
            CompactStat(
              icon: Icons.fact_check_outlined,
              accent: MenuAccent.blue,
              value: '$_totalEntries',
              label: 'Total Entries',
              caption: 'This month',
            ),
            CompactStat(
              icon: Icons.event_outlined,
              accent: MenuAccent.purple,
              value: _lastEntry != null ? shortDate(_lastEntry!.entryDate) : '—',
              label: 'Last Entry',
              caption: (_lastEntry?.templateName.isNotEmpty ?? false)
                  ? _lastEntry!.templateName
                  : 'No entries yet',
            ),
            CompactStat(
              icon: Icons.local_fire_department_outlined,
              accent: MenuAccent.orange,
              value: '$_currentStreak ${_currentStreak == 1 ? 'day' : 'days'}',
              label: 'Streak',
              caption: _currentStreak > 0 ? 'Keep it up!' : 'No current streak',
            ),
            CompactStat(
              icon: Icons.donut_large_outlined,
              accent: MenuAccent.green,
              value: '$_completionPercent%',
              label: 'Completion',
              caption: 'This month',
            ),
          ],
        ),

        // Recent Entries removed: the Client Activity KPIs directly above
        // already carry Last Entry, and the full history lives under each
        // assigned template's Entries tab, which is where you go to read it.
        const SizedBox(height: AppSpacing.md),

        // Private notes, styled as on the web's `.notes-card`: the warning
        // wash with its own border and the amber heading (#b54708), plus an
        // explicit lock and "(Private)" in the title. This is the one surface
        // on the page the client must never see, so it is the one surface
        // that does not look like every other card.
        _privateNotesCard(),

        // Additional Information lives here on the Workspace tab, not behind
        // View profile: it's working material — payments, agreements,
        // documents — that gets referred to while you're looking at the
        // client, unlike the static registration record.
        // Heading, its `i`, and the visibility control on one row. Visibility
        // is a property of the whole section — one switch for all of it, not
        // a control repeated on every item inside.
        Row(
          children: [
            const Expanded(
              child: SectionHeader(
                title: 'Additional Information',
                topSpace: AppSpacing.xl,
                infoBody: 'Payments, membership, agreements, documents, or '
                    'anything else you want on file about this client.\n\n'
                    'VISIBILITY\n'
                    'The Private / Shared with Client switch applies to this '
                    'whole section, not to individual items.\n\n'
                    'On Private, only you can see any of it. On Shared with '
                    'Client, every item here appears in the client\'s own '
                    'portal.\n\n'
                    'Anything you never want a client to read belongs in '
                    'Professional Notes instead, which is always private.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _additionalVisibilityToggle(
                client?.additionalInfoShared ?? false,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _isSavingAdditional ? null : _addAdditionalInfoItem,
            icon: const Icon(Icons.add, size: AppSize.iconRow),
            label: const Text('Add item'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if ((client?.additionalInfo ?? []).isEmpty)
          const EmptyState(message: 'No additional information yet.')
        else
          for (final item in client!.additionalInfo)
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
                          item.type == AdditionalInfoType.link ? item.link : item.text,
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
                    tooltip: item.isSharedWithClient ? 'Shared with client' : 'Private',
                    iconSize: AppSize.iconRow,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed:
                        _isSavingAdditional ? null : () => _removeAdditionalInfoItem(item),
                    icon: const Icon(Icons.delete_outline),
                    iconSize: AppSize.iconRow,
                    color: context.colors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

        // One heading covers both: a reminder and a meeting are different
        // things, but they are the same job — planning what happens next with
        // this client. As two peer top-level sections they read as unrelated
        // features that happened to land next to each other.
        SectionHeader(
          title: 'Schedule and Follow-Ups',
          infoBody: 'Two different things, kept apart on purpose.\n\n'
              'REMINDERS / FOLLOW-UPS\n'
              'Private nudges for you about this client — check in on an '
              'injury, chase a missing entry, review progress. The client '
              'never sees these.\n\n'
              'MEETINGS\n'
              'Real appointments with a date and time that the client is part '
              'of and can see.',
        ),
        SectionHeader(
          title: 'Reminders / Follow-Ups',
          subheading: true,
          actionLabel: _showReminderForm ? 'Close' : 'Add',
          onAction: () => setState(() => _showReminderForm = !_showReminderForm),
          topSpace: AppSpacing.sm,
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
                              : shortDate(isoDate(_reminderDate!)),
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
                              : isoTime(_reminderTime!),
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
          subheading: true,
          actionLabel: 'Schedule',
          onAction: _scheduleMeeting,
          topSpace: AppSpacing.lg,
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
      ],
    );
  }

  /// "Templates" — Progress log + template assign/assigned list, split out
  /// of Workspace into its own tab per the user's request.
  Widget _templatesTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        const SectionHeader(title: 'Templates', topSpace: 0),
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

  Widget _paymentsTab() {
    return ClientPaymentsPanel(
      clientId: widget.clientId,
      clientName: _client?.displayName ?? 'Client',
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

        const SectionHeader(title: 'Account Actions', topSpace: 0),
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

        // Portal access — a manually-added client has a record but no login
        // until this is granted, so without it the "add client" flow dead-ends
        // on mobile. Mirrors the web client profile's account dialog.
        const SectionHeader(title: 'Portal access'),
        if (client?.hasPortalAccess ?? false)
          _ActionRow(
            icon: Icons.link_off,
            title: _isRevokingAccess ? 'Revoking…' : 'Revoke portal access',
            subtitle:
                'Removes ${client?.username.isNotEmpty ?? false ? client!.username : 'their login'}. '
                'The client record and all history are kept.',
            destructive: true,
            onTap: _isRevokingAccess ? () {} : _revokePortalAccess,
          )
        else
          _ActionRow(
            icon: Icons.person_add_alt_1_outlined,
            title: _isGrantingAccess ? 'Granting…' : 'Grant portal access',
            subtitle: 'Create a username and password so this client can sign in.',
            onTap: _isGrantingAccess ? () {} : _grantPortalAccess,
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

/// One label/value cell inside [_ProfessionalClientDetailPageState._infoGrid].
class _GridInfoField extends StatelessWidget {
  const _GridInfoField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: 2),
        Text(
          value.trim().isNotEmpty ? value : '—',
          style: context.text.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Workspace | Templates | Chat | Payments | Actions switcher — the same
/// SegmentedButton pattern already used by Dashboard/Clients/Schedule/Forms &
/// Groups (see _DashboardTabBar in professional_dashboard_page.dart), so this
/// page's tab strip matches the rest of the app instead of the old hand-rolled
/// pill row. The chat-unread badge is embedded in the segment's label Row,
/// same technique as that reference implementation. Full-width, same as
/// every other tab bar in the app — short one-word labels at labelSmall
/// keep 5 segments comfortable without needing to scroll.
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
      DetailTab.workspace: 'Workspace',
      DetailTab.templates: 'Templates',
      DetailTab.payments: 'Payments',
      DetailTab.actions: 'Account',
    };

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<DetailTab>(
        segments: [
          for (final entry in labels.entries)
            ButtonSegment(
              value: entry.key,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.value),
                ],
              ),
            ),
        ],
        selected: {tab},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onSelect(selection.first),
        // labelMedium (12) rather than labelSmall (11) at compact density.
        // Five tabs had been squeezed until the labels were the smallest text
        // on a screen whose KPI values are 24 — a 2x contradiction sitting a
        // few pixels apart. Losing the header's info grid freed the width to
        // set them at a normal size.
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

/// One "Current" / "Requested" line of a profile change request — the mobile
/// stand-in for a column of the web's diff table.
class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;

  /// The requested value is the one being decided on, so it reads stronger.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: highlight
                  ? context.text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.colors.primary,
                    )
                  : context.text.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
