import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/scheduling_models.dart';
import '../../core/api/scheduling_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

enum _ScheduleSegment { reminders, meetings, availability }

/// Full schedule overview: reminders, meetings, and weekly availability.
/// Replica of mobile/src/app/pages/professional/schedule/professional-schedule.page.ts
/// plus the scheduling (meetings/availability) surface ported from the web's
/// professional-schedule component, previously missing from mobile.
class ProfessionalSchedulePage extends ConsumerStatefulWidget {
  const ProfessionalSchedulePage({super.key});

  @override
  ConsumerState<ProfessionalSchedulePage> createState() => _ProfessionalSchedulePageState();
}

class _ProfessionalSchedulePageState extends ConsumerState<ProfessionalSchedulePage> {
  _ScheduleSegment _segment = _ScheduleSegment.reminders;

  // Reminders
  List<ClientReminder> _reminders = [];
  ScheduleSummary? _summary;
  String _message = '';
  bool _loading = true;

  // Meetings
  List<ScheduledMeetingRecord> _meetings = [];
  List<LeadFormMeetingRecord> _leadMeetings = [];
  bool _meetingsLoading = true;
  String _meetingsMessage = '';

  // Availability
  List<AvailabilityWindowRecord> _windows = [];
  SchedulingSettingsRecord? _settings;
  bool _availabilityLoading = true;
  String _availabilityMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
    _loadMeetings();
    _loadAvailability();
  }

  Future<void> _load() async {
    try {
      final upcoming = await ref.read(formsGroupsApiProvider).getUpcomingReminders();
      if (!mounted) return;
      setState(() {
        _reminders = upcoming.reminders;
        _summary = upcoming.summary;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load schedules.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMeetings() async {
    setState(() => _meetingsLoading = true);
    try {
      final response = await ref.read(schedulingApiProvider).getMeetings();
      if (!mounted) return;
      setState(() {
        _meetings = response.meetings;
        _leadMeetings = response.leadMeetings;
        _meetingsMessage = '';
        _meetingsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _meetingsMessage = 'Could not load meetings.';
        _meetingsLoading = false;
      });
    }
  }

  Future<void> _loadAvailability() async {
    setState(() => _availabilityLoading = true);
    try {
      final response = await ref.read(schedulingApiProvider).getSchedulingSettings();
      if (!mounted) return;
      setState(() {
        _windows = response.availabilityWindows;
        _settings = response.settings;
        _availabilityMessage = '';
        _availabilityLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _availabilityMessage = 'Could not load availability.';
        _availabilityLoading = false;
      });
    }
  }

  Future<void> _complete(ClientReminder reminder) async {
    try {
      await ref
          .read(formsGroupsApiProvider)
          .updateReminder(reminder.id, status: ReminderStatus.done);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${reminder.title} marked done.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not update the schedule.');
    }
  }

  Future<void> _remove(ClientReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: Text('"${reminder.title}" for ${reminder.clientName} will be removed.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(formsGroupsApiProvider).deleteReminder(reminder.id);
      if (!mounted) return;
      // Drop locally rather than refetching, matching the Ionic page.
      setState(() => _reminders =
          _reminders.where((item) => item.id != reminder.id).toList());
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not delete the schedule.');
    }
  }

  // ----- meetings actions -----

  Future<void> _cancelMeeting(ScheduledMeetingRecord meeting) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel meeting with ${meeting.clientName}?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Back')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Cancel meeting'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref
            .read(schedulingApiProvider)
            .cancelMeeting(meeting.id, reason: reasonCtrl.text.trim());
        await _loadMeetings();
      } catch (_) {
        if (mounted) setState(() => _meetingsMessage = 'Could not cancel the meeting.');
      }
    }
    reasonCtrl.dispose();
  }

  Future<void> _rescheduleMeeting(ScheduledMeetingRecord meeting) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: meeting.startAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: meeting.startAt != null
          ? TimeOfDay.fromDateTime(meeting.startAt!)
          : TimeOfDay.now(),
    );
    if (time == null) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await ref.read(schedulingApiProvider).rescheduleMeeting(meeting.id, start.toIso8601String());
      await _loadMeetings();
    } catch (_) {
      if (mounted) setState(() => _meetingsMessage = 'Could not reschedule the meeting.');
    }
  }

  // ----- availability actions -----

  Future<void> _addWindow() async {
    int weekday = 0;
    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 17, minute: 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add availability window'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(labelText: 'Day'),
                items: [
                  for (var i = 0; i < AvailabilityWindowRecord.weekdayLabels.length; i++)
                    DropdownMenuItem(value: i, child: Text(AvailabilityWindowRecord.weekdayLabels[i])),
                ],
                onChanged: (value) => setDialogState(() => weekday = value ?? 0),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: start);
                        if (picked != null) setDialogState(() => start = picked);
                      },
                      child: Text('From ${start.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: end);
                        if (picked != null) setDialogState(() => end = picked);
                      },
                      child: Text('To ${end.format(context)}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => context.pop(true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, AppSize.buttonHeightSm)),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      String hhmm(TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      try {
        final window = await ref.read(schedulingApiProvider).addAvailabilityWindow(
              weekday: weekday,
              startTime: hhmm(start),
              endTime: hhmm(end),
            );
        if (mounted) setState(() => _windows = [..._windows, window]);
      } catch (_) {
        if (mounted) setState(() => _availabilityMessage = 'Could not add the window.');
      }
    }
  }

  Future<void> _toggleWindow(AvailabilityWindowRecord window) async {
    try {
      final updated = await ref
          .read(schedulingApiProvider)
          .updateAvailabilityWindow(window.id, isActive: !window.isActive);
      if (!mounted) return;
      setState(() => _windows = _windows.map((w) => w.id == window.id ? updated : w).toList());
    } catch (_) {
      if (mounted) setState(() => _availabilityMessage = 'Could not update the window.');
    }
  }

  Future<void> _deleteWindow(AvailabilityWindowRecord window) async {
    try {
      await ref.read(schedulingApiProvider).deleteAvailabilityWindow(window.id);
      if (!mounted) return;
      setState(() => _windows = _windows.where((w) => w.id != window.id).toList());
    } catch (_) {
      if (mounted) setState(() => _availabilityMessage = 'Could not delete the window.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalManage)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              0,
            ),
            child: SegmentedButton<_ScheduleSegment>(
              segments: const [
                ButtonSegment(value: _ScheduleSegment.reminders, label: Text('Reminders')),
                ButtonSegment(value: _ScheduleSegment.meetings, label: Text('Meetings')),
                ButtonSegment(value: _ScheduleSegment.availability, label: Text('Availability')),
              ],
              selected: {_segment},
              onSelectionChanged: (value) => setState(() => _segment = value.first),
            ),
          ),
          Expanded(
            child: switch (_segment) {
              _ScheduleSegment.reminders => _remindersView(),
              _ScheduleSegment.meetings => _meetingsView(),
              _ScheduleSegment.availability => _availabilityView(),
            },
          ),
        ],
      ),
    );
  }

  Widget _remindersView() {
    final summary = _summary;
    final tokens = context.tokens;

    return PagePad(
      onRefresh: _load,
      children: [
        KpiGrid(
          children: [
            KpiTile(label: 'Pending', value: '${summary?.totalPending ?? 0}'),
            KpiTile(
              label: 'Due 24 hours',
              value: '${summary?.due24Hours ?? 0}',
              valueColor: context.colors.primary,
            ),
            KpiTile(label: 'Due 7 days', value: '${summary?.due7Days ?? 0}'),
            KpiTile(
              label: 'Completed (7d)',
              value: '${summary?.completedLast7Days ?? 0}',
              valueColor: tokens.success,
            ),
          ],
        ),
        if (_message.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorNote(message: _message, onRetry: _load),
        ],

        const SectionHeader(title: 'Upcoming'),
        if (_loading)
          for (var i = 0; i < 4; i++) const SkeletonBox(height: 70)
        else if (_reminders.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.event_available_outlined,
            message: "Nothing scheduled.\nAdd follow-ups from a client's page.",
          )
        else
          for (final reminder in _reminders)
            _ReminderRow(
              reminder: reminder,
              onComplete: () => _complete(reminder),
              onDelete: () => _remove(reminder),
              onOpenClient: () =>
                  context.go('${Routes.professionalClients}/${reminder.client}'),
            ),
      ],
    );
  }

  Widget _meetingsView() {
    return PagePad(
      onRefresh: _loadMeetings,
      children: [
        if (_meetingsMessage.isNotEmpty)
          ErrorNote(message: _meetingsMessage, onRetry: _loadMeetings),

        if (_leadMeetings.isNotEmpty) ...[
          const SectionHeader(title: 'Intro meeting requests', topSpace: 0),
          for (final lead in _leadMeetings)
            RowItem(
              title: lead.applicantName,
              subtitle: lead.requestedStart != null
                  ? dateTimeLabel(lead.requestedStart!.toIso8601String())
                  : 'Time pending',
            ),
        ],

        SectionHeader(title: 'Meetings', topSpace: _leadMeetings.isEmpty ? 0 : AppSpacing.md),
        if (_meetingsLoading)
          for (var i = 0; i < 3; i++) const SkeletonBox(height: 70)
        else if (_meetings.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.event_outlined,
            message: 'No meetings scheduled.\nCreate one from a client\'s Overview tab.',
          )
        else
          for (final meeting in _meetings)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${meeting.title.isNotEmpty ? meeting.title : 'Meeting'} · ${meeting.clientName}',
                            style: context.text.titleSmall,
                          ),
                        ),
                        StatusPill(
                          label: meeting.status,
                          tone: meeting.status == MeetingStatus.cancelled
                              ? PillTone.bad
                              : meeting.status == MeetingStatus.completed
                                  ? PillTone.neutral
                                  : PillTone.good,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meeting.startAt != null
                          ? dateTimeLabel(meeting.startAt!.toIso8601String())
                          : '',
                      style: context.text.bodySmall,
                    ),
                    Text(
                      'Client response: ${meeting.clientResponseStatus}',
                      style: context.text.bodySmall,
                    ),
                    if (meeting.status == MeetingStatus.scheduled) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _rescheduleMeeting(meeting),
                              child: const Text('Reschedule'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _cancelMeeting(meeting),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.error,
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _editSchedulingSettings(SchedulingSettingsRecord settings) async {
    final timezoneCtrl = TextEditingController(text: settings.timezone);
    final durationCtrl = TextEditingController(text: '${settings.defaultDurationMinutes}');
    final intervalCtrl = TextEditingController(text: '${settings.slotIntervalMinutes}');
    final bufferCtrl = TextEditingController(text: '${settings.bufferMinutes}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scheduling settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: timezoneCtrl,
                decoration: const InputDecoration(labelText: 'Timezone (e.g. America/New_York)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: durationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Default duration (min)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: intervalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Slot interval (min)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: bufferCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Buffer between meetings (min)'),
              ),
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
      try {
        final updated = await ref.read(schedulingApiProvider).saveSchedulingSettings(
              timezone: timezoneCtrl.text.trim(),
              defaultDurationMinutes: int.tryParse(durationCtrl.text.trim()),
              slotIntervalMinutes: int.tryParse(intervalCtrl.text.trim()),
              bufferMinutes: int.tryParse(bufferCtrl.text.trim()),
            );
        if (mounted) setState(() => _settings = updated);
      } catch (_) {
        if (mounted) setState(() => _availabilityMessage = 'Could not save settings.');
      }
    }
    timezoneCtrl.dispose();
    durationCtrl.dispose();
    intervalCtrl.dispose();
    bufferCtrl.dispose();
  }

  Widget _availabilityView() {
    final settings = _settings;
    return PagePad(
      onRefresh: _loadAvailability,
      children: [
        if (_availabilityMessage.isNotEmpty)
          ErrorNote(message: _availabilityMessage, onRetry: _loadAvailability),
        if (settings != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Scheduling settings', style: context.text.titleSmall),
                    ),
                    IconButton(
                      onPressed: () => _editSchedulingSettings(settings),
                      icon: const Icon(Icons.edit_outlined),
                      iconSize: AppSize.iconRow,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit',
                    ),
                  ],
                ),
                Text('Timezone: ${settings.timezone}', style: context.text.bodySmall),
                Text(
                  'Default duration: ${settings.defaultDurationMinutes} min · '
                  'Slot interval: ${settings.slotIntervalMinutes} min · '
                  'Buffer: ${settings.bufferMinutes} min',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        SectionHeader(
          title: 'Weekly availability',
          actionLabel: 'Add',
          onAction: _addWindow,
        ),
        if (_availabilityLoading)
          for (var i = 0; i < 3; i++) const SkeletonBox(height: 60)
        else if (_windows.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.calendar_month_outlined,
            message: 'No availability windows yet.\nAdd one so clients can request meetings.',
          )
        else
          for (final window in _windows)
            RowItem(
              title: '${window.weekdayLabel} · ${window.startTime}–${window.endTime}',
              subtitle: window.isActive ? 'Active' : 'Inactive',
              leading: Switch(
                value: window.isActive,
                onChanged: (_) => _toggleWindow(window),
              ),
              trailing: IconButton(
                onPressed: () => _deleteWindow(window),
                icon: const Icon(Icons.delete_outline),
                iconSize: AppSize.iconRow,
                color: context.colors.error,
                visualDensity: VisualDensity.compact,
              ),
            ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onComplete,
    required this.onDelete,
    required this.onOpenClient,
  });

  final ClientReminder reminder;
  final VoidCallback onComplete;
  final VoidCallback onDelete;
  final VoidCallback onOpenClient;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final when = [
      weekdayDate(reminder.date),
      if (reminder.time.isNotEmpty) hhmm(reminder.time),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.card,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reminder.title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: onOpenClient,
                          child: Text(
                            reminder.clientName,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Text(' · $when', style: context.text.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onComplete,
              icon: const Icon(Icons.check),
              iconSize: AppSize.iconRow,
              color: tokens.success,
              tooltip: 'Mark done',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              iconSize: AppSize.iconRow,
              color: context.colors.error,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
