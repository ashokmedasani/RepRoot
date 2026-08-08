import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/scheduling_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/api/scheduling_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// "yyyy-MM-dd" for the API's date-only params and for keying meetings by day.
final _isoDay = DateFormat('yyyy-MM-dd');

/// Booking durations the backend accepts for a video meeting — anything else
/// is rejected with "Video meetings must be 15 or 30 minutes."
const _meetingDurations = [15, 30];

/// The three lists that sit *under* the calendar. Availability is no longer
/// one of them — it is setup you touch occasionally, not a view of your
/// schedule, so it moved to a button (see [_openAvailabilitySheet]).
enum _ScheduleSegment { todo, reminders, meetings }

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
  _ScheduleSegment _segment = _ScheduleSegment.todo;

  // Reminders
  List<ClientReminder> _reminders = [];
  ScheduleSummary? _summary;
  String _message = '';
  bool _loading = true;
  int _notificationUnread = 0;

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

  // Calendar + days off (the web's calendar section and "Day off" dialog).
  List<DateOffRecord> _dateOffs = [];
  List<WeekdayOffRecord> _weekdayOffs = [];
  late DateTime _calendarMonth;
  String? _selectedCalendarDate;

  // Clients to book with — fetched lazily the first time the booking sheet is
  // opened, the same fan-out over groups the Clients tab does.
  List<_BookingGroup> _clientGroups = [];
  bool _clientsLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month);
    _load();
    _loadMeetings();
    _loadAvailability();
    _loadDaysOff();
    _loadNotificationCount();
  }

  /// Header badge only — fetched once on open, not polled. The notification
  /// inbox moves far more slowly than this page's meeting data.
  Future<void> _loadNotificationCount() async {
    try {
      final inbox =
          await ref.read(professionalAuthApiProvider).getNotifications(limit: 1);
      if (mounted) setState(() => _notificationUnread = inbox.unreadCount);
    } catch (_) {/* the badge just stays at zero */}
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

  /// Both flavours of day off — a specific date and a whole recurring weekday
  /// — gray out the calendar, so they load together with the meetings.
  Future<void> _loadDaysOff() async {
    try {
      final api = ref.read(schedulingApiProvider);
      final dateOffs = await api.listDateOffs();
      final weekdayOffs = await api.listWeekdayOffs();
      if (!mounted) return;
      setState(() {
        _dateOffs = dateOffs;
        _weekdayOffs = weekdayOffs;
      });
    } catch (_) {
      // Days off only shade the calendar; a failure here must not blank the
      // meetings list beside it.
    }
  }

  /// Clients live per group, so fan out and flatten — a failing group must not
  /// lose the others, matching the catchError in the web's forkJoin.
  Future<void> _loadClients() async {
    setState(() => _clientsLoading = true);
    final api = ref.read(formsGroupsApiProvider);
    try {
      final overview = await api.getOverview();
      final groups = await Future.wait(
        overview.groups.map((group) async {
          try {
            final response = await api.getGroupUsers(group.id);
            return _BookingGroup(
              id: group.id,
              name: group.name,
              clients: response.clients.where((client) => client.isActive).toList(),
            );
          } catch (_) {
            return _BookingGroup(id: group.id, name: group.name, clients: const []);
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _clientGroups = groups;
        _clientsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _clientGroups = [];
        _clientsLoading = false;
        _meetingsMessage = 'Could not load your clients.';
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

  /// Book a new meeting — the mobile shape of the web's "Schedule Meeting"
  /// modal (clients/groups, duration, title, notes, slot chips or an exact
  /// time), posting to the same /professional/scheduling/meetings/ endpoint.
  Future<void> _openBookingSheet() async {
    if (_clientGroups.isEmpty && !_clientsLoading) await _loadClients();
    if (!mounted) return;
    if (_clientGroups.every((group) => group.clients.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a client before booking a meeting.')),
      );
      return;
    }

    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BookMeetingSheet(
        groups: _clientGroups,
        defaultDurationMinutes: _settings?.defaultDurationMinutes ?? 30,
        initialDate: _selectedCalendarDate,
      ),
    );
    if (booked == true) {
      await _loadMeetings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meeting scheduled.')),
        );
      }
    }
  }

  Future<void> _openDaysOffSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DaysOffSheet(
        dateOffs: _dateOffs,
        weekdayOffs: _weekdayOffs,
      ),
    );
    await _loadDaysOff();
  }

  /// Accept or decline a time a client proposed. Accepting books it for real
  /// (video link + invites); declining is the destructive half, so only that
  /// one asks for confirmation.
  Future<void> _reviewRequest(ScheduledMeetingRecord meeting, String action) async {
    if (action == 'decline') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Decline this request?'),
          content: Text('${meeting.clientName} will be told the time does not work.'),
          actions: [
            TextButton(onPressed: () => context.pop(false), child: const Text('Back')),
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
    }

    try {
      await ref.read(schedulingApiProvider).reviewClientMeetingRequest(meeting.id, action);
      await _loadMeetings();
    } catch (error) {
      if (mounted) {
        setState(() => _meetingsMessage = error is ApiException
            ? error.message
            : 'Could not update this meeting request.');
      }
    }
  }

  // ----- calendar helpers -----

  /// Cancelled meetings are dropped so a called-off day reads as open, the
  /// same filter the web calendar applies.
  Map<String, int> get _meetingCountsByDate {
    final counts = <String, int>{};
    for (final meeting in _meetings) {
      final start = meeting.startAt;
      if (start == null || meeting.status == MeetingStatus.cancelled) continue;
      final iso = _isoDay.format(start.toLocal());
      counts[iso] = (counts[iso] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _bookedMinutesByDate {
    final minutes = <String, int>{};
    for (final meeting in _meetings) {
      final start = meeting.startAt;
      final end = meeting.endAt;
      if (start == null || meeting.status == MeetingStatus.cancelled) continue;
      final iso = _isoDay.format(start.toLocal());
      final length = end == null ? 0 : end.difference(start).inMinutes;
      minutes[iso] = (minutes[iso] ?? 0) + (length < 0 ? 0 : length);
    }
    return minutes;
  }

  /// True when that calendar date has no bookable hours — through either a
  /// recurring weekday off or a one-off date off.
  bool _isDateOff(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return false;
    // Dart weekday: Mon=1..Sun=7. Backend weekday fields: Mon=0..Sun=6.
    final backendWeekday = date.weekday - 1;
    return _weekdayOffs.any((off) => off.weekday == backendWeekday) ||
        _dateOffs.any((off) => off.date == iso);
  }

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
      // Send an absolute instant (UTC, "…Z"): a naive local string would be
      // read back in the server's own default zone and land at the wrong time.
      await ref
          .read(schedulingApiProvider)
          .rescheduleMeeting(meeting.id, start.toUtc().toIso8601String());
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
      // No AppBar — Schedule is a root bottom-nav tab, and the bare 52px
      // toolbar here had nothing in it. Same header shape as every other
      // tab now: the eyebrow/title block starts right under the status bar.
      // The header is inside the scroll, not pinned above it. Fixed, it cost
      // a permanent block of the screen on the one page where the calendar
      // wants every pixel it can get.
      body: SafeArea(child: _scheduleBody()),
    );
  }

  /// Calendar-led layout: compact KPIs, the actions that create things, the
  /// month grid, then the selected list. Previously the page opened on a
  /// Reminders list and the calendar was buried inside the Meetings tab.
  Widget _scheduleBody() {
    final selected = _selectedCalendarDate;

    return PagePad(
      onRefresh: () async {
        await _load();
        await _loadMeetings();
        await _loadDaysOff();
      },
      children: [
        PageHeader(
          eyebrow: 'PROFESSIONAL WORKSPACE',
          title: 'Schedule',
          info: 'Every upcoming meeting and follow-up across your clients, in '
              'one place.\n\n'
              'TO-DO\n'
              'The next three days only — reminders and meetings together, in '
              'the order they happen.\n\n'
              'REMINDERS\n'
              'Private follow-ups about a client. Only you see these.\n\n'
              'MEETINGS\n'
              'Real appointments your clients are part of.\n\n'
              'Tap a date on the calendar to narrow the lists to that day. '
              'Set availability and Days off control when clients can book '
              'you.',
          trailing: NotificationBell(
            unread: _notificationUnread,
            onTap: () => context.go(Routes.professionalNotifications),
          ),
        ),
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        if (_meetingsMessage.isNotEmpty)
          ErrorNote(message: _meetingsMessage, onRetry: _loadMeetings),

        _scheduleKpis(),
        const SizedBox(height: AppSpacing.md),

        // Booking and availability are the same job — deciding when you meet
        // people — so they share one segmented control instead of a
        // full-width button plus a loose icon. Days off stays separate: it is
        // the opposite instruction, blocking time rather than offering it.
        Row(
          children: [
            Expanded(
              child: _ScheduleActionGroup(
                onBook: _clientsLoading ? null : _openBookingSheet,
                onAvailability: _openAvailabilitySheet,
                bookBusy: _clientsLoading,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.outlined(
              onPressed: _openDaysOffSheet,
              icon: const Icon(Icons.event_busy_outlined, size: AppSize.iconRow),
              tooltip: 'Day off',
            ),
          ],
        ),

        const SizedBox(height: AppSpacing.md),
        _MonthCalendar(
          month: _calendarMonth,
          selectedIso: selected,
          meetingCounts: _meetingCountsByDate,
          bookedMinutes: _bookedMinutesByDate,
          isDayOff: _isDateOff,
          onPrevMonth: () => setState(() => _calendarMonth =
              DateTime(_calendarMonth.year, _calendarMonth.month - 1)),
          onNextMonth: () => setState(() => _calendarMonth =
              DateTime(_calendarMonth.year, _calendarMonth.month + 1)),
          onSelect: (iso) => setState(() =>
              _selectedCalendarDate = _selectedCalendarDate == iso ? null : iso),
        ),
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _isDateOff(selected)
                        ? "You're on a day off on $selected — no meetings."
                        : 'Showing $selected',
                    style: context.text.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedCalendarDate = null),
                  child: const Text('Show all'),
                ),
              ],
            ),
          ),

        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_ScheduleSegment>(
            segments: const [
              ButtonSegment(
                value: _ScheduleSegment.todo,
                label: Text('To-Do', maxLines: 1),
              ),
              ButtonSegment(
                value: _ScheduleSegment.reminders,
                label: Text('Reminders', maxLines: 1),
              ),
              ButtonSegment(
                value: _ScheduleSegment.meetings,
                label: Text('Meetings', maxLines: 1),
              ),
            ],
            selected: {_segment},
            showSelectedIcon: false,
            onSelectionChanged: (value) =>
                setState(() => _segment = value.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...switch (_segment) {
          _ScheduleSegment.todo => _todoSection(),
          _ScheduleSegment.reminders => _remindersSection(),
          _ScheduleSegment.meetings => _meetingsSection(),
        },
      ],
    );
  }

  /// Compact KPI strip. Four full KpiTiles took roughly a third of the phone
  /// screen before the calendar even started; these are one short row.
  Widget _scheduleKpis() {
    final summary = _summary;
    return CompactStatRow(
      stats: [
        CompactStat(
          icon: Icons.pending_actions_outlined,
          accent: MenuAccent.blue,
          value: '${summary?.totalPending ?? 0}',
          label: 'Pending',
        ),
        CompactStat(
          icon: Icons.alarm_outlined,
          accent: MenuAccent.orange,
          value: '${summary?.due24Hours ?? 0}',
          label: 'Due 24h',
        ),
        CompactStat(
          icon: Icons.date_range_outlined,
          accent: MenuAccent.purple,
          value: '${summary?.due7Days ?? 0}',
          label: 'Due 7d',
        ),
        CompactStat(
          icon: Icons.check_circle_outline,
          accent: MenuAccent.green,
          value: '${summary?.completedLast7Days ?? 0}',
          label: 'Done 7d',
        ),
      ],
    );
  }

  /// Availability is setup, not a view of the schedule — it opens over the
  /// page instead of costing a permanent tab.
  Future<void> _openAvailabilitySheet() async {
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Set availability'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: SafeArea(child: _availabilityView()),
        ),
      ),
    );
    if (mounted) await _loadAvailability();
  }

  /// Reminders — private follow-ups about a client. Never meetings: nobody
  /// else sees these and they have no attendee.
  List<Widget> _remindersSection() {
    return [
      SectionHeader(
        title: 'Reminders',
        topSpace: 0,
        infoBody: 'Private follow-ups about a client — check an injury, chase '
            'a missing entry, review progress before your next session.\n\n'
            'Only you see these. They are not meetings: there is no attendee '
            'and nothing is sent to the client.\n\n'
            'Add them from a client\'s page, under Schedule and Follow-Ups.',
      ),
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
    ];
  }

  /// Meetings — real appointments the client is part of.
  List<Widget> _meetingsSection() {
    final now = DateTime.now();
    int startMs(ScheduledMeetingRecord meeting) =>
        meeting.startAt?.millisecondsSinceEpoch ?? 0;
    bool isUpcoming(ScheduledMeetingRecord meeting) =>
        meeting.status == MeetingStatus.scheduled &&
        (meeting.startAt?.isBefore(now) == false);

    final pendingRequests = _meetings
        .where((m) => m.isPendingClientRequest)
        .toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final upcoming = _meetings.where(isUpcoming).toList()
      ..sort((a, b) => startMs(a).compareTo(startMs(b)));
    final past = _meetings
        .where((m) => m.status != MeetingStatus.pendingApproval && !isUpcoming(m))
        .toList()
      ..sort((a, b) => startMs(b).compareTo(startMs(a)));

    // Picking a day on the calendar narrows this list to that day.
    final selected = _selectedCalendarDate;
    final displayedUpcoming = selected == null
        ? upcoming
        : upcoming
            .where((m) =>
                m.startAt != null &&
                _isoDay.format(m.startAt!.toLocal()) == selected)
            .toList();

    return [
      if (pendingRequests.isNotEmpty) ...[
        const SectionHeader(
          title: 'Client meeting requests',
          topSpace: 0,
          subheading: true,
        ),
        Text(
          'Times your clients asked for. They stay here until you accept or '
          'decline.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final meeting in pendingRequests)
          _meetingCard(
            meeting,
            actions: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _reviewRequest(meeting, 'accept'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonHeightSm),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reviewRequest(meeting, 'decline'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.error,
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ),
      ],

      if (_leadMeetings.isNotEmpty) ...[
        const SectionHeader(title: 'Intro meeting requests', subheading: true),
        for (final lead in _leadMeetings)
          RowItem(
            title: lead.applicantName,
            subtitle: lead.requestedStart != null
                ? dateTimeLabel(lead.requestedStart!.toIso8601String())
                : 'Time pending',
          ),
      ],

      SectionHeader(
        title: 'Upcoming',
        subheading: true,
        topSpace: pendingRequests.isEmpty && _leadMeetings.isEmpty
            ? 0
            : AppSpacing.lg,
      ),
      if (_meetingsLoading)
        for (var i = 0; i < 3; i++) const SkeletonBox(height: 70)
      else if (displayedUpcoming.isEmpty)
        EmptyState(
          compact: false,
          icon: Icons.event_outlined,
          message: selected == null
              ? 'No meetings scheduled.\nTap "Book meeting" to set one up.'
              : 'Nothing booked on $selected.',
        )
      else
        for (final meeting in displayedUpcoming)
          _meetingCard(
            meeting,
            actions: Row(
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
          ),

      if (past.isNotEmpty) ...[
        const SectionHeader(title: 'Past & cancelled', subheading: true),
        for (final meeting in past) _meetingCard(meeting),
      ],
    ];
  }

  /// To-Do — the next 72 hours only, reminders and meetings interleaved in
  /// time order.
  ///
  /// Deliberately not a task manager: the horizon is fixed at three days so
  /// this stays the "what do I have to actually do now" list. Anything
  /// further out belongs to the Reminders and Meetings lists.
  List<Widget> _todoSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final horizon = today.add(const Duration(days: 3));

    final items = <({DateTime when, Widget row})>[];

    for (final reminder in _reminders) {
      if (reminder.status == ReminderStatus.done) continue;
      final date = DateTime.tryParse(reminder.date);
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(today) || !day.isBefore(horizon)) continue;
      items.add((
        when: day,
        row: RowItem(
          title: reminder.title.isEmpty ? 'Follow-up' : reminder.title,
          subtitle: [
            if (reminder.clientName.isNotEmpty) reminder.clientName,
            shortDate(reminder.date),
            if (reminder.time.isNotEmpty) reminder.time,
          ].join(' · '),
          leading: Icon(
            Icons.notifications_active_outlined,
            size: AppSize.iconButton,
            color: context.colors.primary,
          ),
          trailing: const StatusPill(label: 'Reminder', tone: PillTone.info),
          onTap: () =>
              context.go('${Routes.professionalClients}/${reminder.client}'),
        ),
      ));
    }

    for (final meeting in _meetings) {
      if (meeting.status != MeetingStatus.scheduled) continue;
      final start = meeting.startAt?.toLocal();
      if (start == null) continue;
      if (start.isBefore(now) || !start.isBefore(horizon)) continue;
      items.add((
        when: start,
        row: RowItem(
          title: meeting.title.isEmpty ? 'Meeting' : meeting.title,
          subtitle: [
            dateTimeLabel(start.toIso8601String()),
            if (meeting.guests.isNotEmpty)
              meeting.guests.map((g) => g.clientName).join(', '),
          ].join(' · '),
          leading: Icon(
            Icons.event_outlined,
            size: AppSize.iconButton,
            color: context.tokens.success,
          ),
          trailing: const StatusPill(label: 'Meeting', tone: PillTone.good),
        ),
      ));
    }

    items.sort((a, b) => a.when.compareTo(b.when));

    return [
      const SectionHeader(
        title: 'Next 3 days',
        topSpace: 0,
        infoBody: 'Everything due in the next three days — reminders and '
            'meetings together, in the order they happen.\n\n'
            'The window is fixed at three days on purpose. This is meant to '
            'be the short list you act on today, not a backlog. Anything '
            'further out is in Reminders or Meetings.',
      ),
      if (items.isEmpty)
        const EmptyState(
          compact: false,
          icon: Icons.task_alt_outlined,
          message: 'Nothing due in the next three days.',
        )
      else
        for (final item in items) item.row,
    ];
  }

  Widget _meetingCard(ScheduledMeetingRecord meeting, {Widget? actions}) {
    final guestNames = meeting.guests.map((guest) => guest.clientName).join(', ');
    return Padding(
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
                  label: meeting.status == MeetingStatus.pendingApproval
                      ? 'needs approval'
                      : meeting.status,
                  tone: switch (meeting.status) {
                    MeetingStatus.cancelled || MeetingStatus.declined => PillTone.bad,
                    MeetingStatus.completed => PillTone.neutral,
                    MeetingStatus.pendingApproval => PillTone.warn,
                    _ => PillTone.good,
                  },
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
            if (guestNames.isNotEmpty)
              Text('Also invited: $guestNames', style: context.text.bodySmall),
            if (meeting.notes.isNotEmpty)
              Text(meeting.notes, style: context.text.bodySmall),
            Text(
              'Client response: ${meeting.clientResponseStatus}',
              style: context.text.bodySmall,
            ),
            if (actions != null) ...[
              const SizedBox(height: AppSpacing.sm),
              actions,
            ],
          ],
        ),
      ),
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

/// One group plus its active clients, as the booking sheet needs them — the
/// mobile shape of the web's `clientGroups` array.
class _BookingGroup {
  const _BookingGroup({required this.id, required this.name, required this.clients});

  final int id;
  final String name;
  final List<ClientAccessRecord> clients;
}

/// Month grid built from plain Flutter widgets (no calendar package): six
/// rows of seven cells starting on the Sunday on or before the 1st, shaded by
/// how much of each day is already booked and grayed out on days off.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selectedIso,
    required this.meetingCounts,
    required this.bookedMinutes,
    required this.isDayOff,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onSelect,
  });

  final DateTime month;
  final String? selectedIso;
  final Map<String, int> meetingCounts;
  final Map<String, int> bookedMinutes;
  final bool Function(String iso) isDayOff;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<String> onSelect;

  static const _weekdayHeadings = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Dart weekday: Mon=1 .. Sun=7, so `weekday % 7` is how many days back the
    // Sunday before the 1st is (Sunday itself gives 0).
    final first = DateTime(month.year, month.month);
    final gridStart = DateTime(first.year, first.month, 1 - (first.weekday % 7));

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onPrevMonth,
                icon: const Icon(Icons.chevron_left),
                iconSize: AppSize.iconButton,
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous month',
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(month),
                  textAlign: TextAlign.center,
                  style: context.text.titleSmall,
                ),
              ),
              IconButton(
                onPressed: onNextMonth,
                icon: const Icon(Icons.chevron_right),
                iconSize: AppSize.iconButton,
                visualDensity: VisualDensity.compact,
                tooltip: 'Next month',
              ),
            ],
          ),
          Row(
            children: [
              for (final heading in _weekdayHeadings)
                Expanded(
                  child: Text(
                    heading,
                    textAlign: TextAlign.center,
                    style: context.text.labelSmall?.copyWith(color: tokens.muted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var day = 0; day < 7; day++)
                  _cell(
                    context,
                    DateTime(
                      gridStart.year,
                      gridStart.month,
                      gridStart.day + week * 7 + day,
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _legend(context, 0, 'Open'),
              _legend(context, 30, 'Up to 1 hr'),
              _legend(context, 120, '1–3 hrs'),
              _legend(context, 240, 'Over 3 hrs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, DateTime date) {
    final tokens = context.tokens;
    final colors = context.colors;
    final iso = _isoDay.format(date);
    final today = _isoDay.format(DateTime.now());
    final inMonth = date.month == month.month && date.year == month.year;
    final count = meetingCounts[iso] ?? 0;
    final dayOff = isDayOff(iso);
    final isSelected = selectedIso == iso;

    final background = dayOff
        ? tokens.surfaceSoft
        : colors.primary.withValues(alpha: _occupancyAlpha(bookedMinutes[iso] ?? 0));

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Semantics(
          button: true,
          selected: isSelected,
          label: '$iso: ${dayOff ? 'day off, ' : ''}'
              '${count > 0 ? '$count meeting(s)' : 'open'}',
          child: InkWell(
            onTap: () => onSelect(iso),
            borderRadius: AppRadius.smAll,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.smAll,
                border: Border.all(
                  color: isSelected
                      ? colors.primary
                      : iso == today
                          ? tokens.border
                          : Colors.transparent,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: context.text.bodySmall?.copyWith(
                      color: inMonth
                          ? (dayOff ? tokens.muted : null)
                          : tokens.muted.withValues(alpha: 0.5),
                      fontWeight: iso == today ? FontWeight.w800 : null,
                      decoration: dayOff ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(height: 2),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(BuildContext context, int minutes, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: context.colors.primary.withValues(alpha: _occupancyAlpha(minutes)),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: context.tokens.border),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: context.text.labelSmall),
      ],
    );
  }

  /// open / light (up to 1 hr) / moderate (1–3 hrs) / busy — the same four
  /// occupancy bands the web calendar shades with.
  static double _occupancyAlpha(int minutes) {
    if (minutes <= 0) return 0;
    if (minutes <= 60) return 0.12;
    if (minutes <= 180) return 0.24;
    return 0.38;
  }
}

/// The mobile form of the web's "Schedule Meeting" modal: pick one client (or
/// several for a group session), a length, an open slot or an exact time, and
/// POST it to /professional/scheduling/meetings/.
class _BookMeetingSheet extends ConsumerStatefulWidget {
  const _BookMeetingSheet({
    required this.groups,
    required this.defaultDurationMinutes,
    this.initialDate,
  });

  final List<_BookingGroup> groups;
  final int defaultDurationMinutes;

  /// "yyyy-MM-dd" the trainer already tapped on the calendar, if any.
  final String? initialDate;

  @override
  ConsumerState<_BookMeetingSheet> createState() => _BookMeetingSheetState();
}

class _BookMeetingSheetState extends ConsumerState<_BookMeetingSheet> {
  final _selectedClientIds = <int>{};
  final _searchCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late int _duration;
  late DateTime _weekStart;
  SlotsByDate _slots = {};
  String _selectedSlot = '';
  bool _loadingSlots = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // The backend only books 15- or 30-minute video meetings, so a stored
    // default outside that pair would always come back as a 400.
    _duration = _meetingDurations.contains(widget.defaultDurationMinutes)
        ? widget.defaultDurationMinutes
        : 30;
    final now = DateTime.now();
    final tapped = widget.initialDate == null
        ? null
        : DateTime.tryParse(widget.initialDate!);
    _weekStart = tapped ?? DateTime(now.year, now.month, now.day);
    _loadSlots();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  List<ClientAccessRecord> get _allClients {
    final byId = <int, ClientAccessRecord>{};
    for (final group in widget.groups) {
      for (final client in group.clients) {
        byId[client.id] = client;
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
  }

  List<ClientAccessRecord> get _filteredClients {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _allClients;
    return _allClients
        .where((client) =>
            client.displayName.toLowerCase().contains(query) ||
            client.username.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loadingSlots = true;
      _selectedSlot = '';
    });
    final end = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);
    try {
      final slots = await ref.read(schedulingApiProvider).getSlots(
            _isoDay.format(_weekStart),
            _isoDay.format(end),
            durationMinutes: _duration,
          );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = {};
        _loadingSlots = false;
      });
    }
  }

  void _toggleGroup(_BookingGroup group) {
    final ids = group.clients.map((client) => client.id).toSet();
    setState(() {
      if (ids.isNotEmpty && ids.every(_selectedClientIds.contains)) {
        _selectedClientIds.removeAll(ids);
      } else {
        _selectedClientIds.addAll(ids);
      }
    });
  }

  /// Weekly availability only governs the public lead-form page — booking
  /// directly with a client is allowed at any exact time, which is what this
  /// manual picker is for.
  Future<void> _pickExactTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _weekStart.isBefore(now) ? now : _weekStart,
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    // Send an absolute instant so the server never has to guess a zone.
    setState(() => _selectedSlot = start.toUtc().toIso8601String());
  }

  Future<void> _book() async {
    if (_selectedClientIds.isEmpty || _selectedSlot.isEmpty) return;
    final ids = _selectedClientIds.toList();
    final names = _allClients
        .where((client) => _selectedClientIds.contains(client.id))
        .map((client) => client.displayName)
        .join(', ');
    final when = DateTime.tryParse(_selectedSlot)?.toLocal();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schedule meeting'),
        content: Text(
          '$names on ${when == null ? _selectedSlot : DateFormat('EEE, MMM d · h:mm a').format(when)}.\n\n'
          'This books a real meeting with a video link and emails a calendar '
          'invite to everyone invited.',
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
    );
    if (confirmed != true) return;

    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await ref.read(schedulingApiProvider).createMeeting(
            client: ids.first,
            guestClientIds: ids.skip(1).toList(),
            start: _selectedSlot,
            durationMinutes: _duration,
            title: _titleCtrl.text.trim(),
            notes: _notesCtrl.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is ApiException
            ? error.message
            : 'Could not schedule the meeting.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final slotDays = _slots.keys.toList()..sort();
    final selectedTime = DateTime.tryParse(_selectedSlot)?.toLocal();

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Book a meeting', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick one client, several for a group session, or a whole group.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),

            if (widget.groups.isNotEmpty)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final group in widget.groups)
                    FilterChip(
                      label: Text('${group.name} (${group.clients.length})'),
                      selected: group.clients.isNotEmpty &&
                          group.clients
                              .every((c) => _selectedClientIds.contains(c.id)),
                      onSelected:
                          group.clients.isEmpty ? null : (_) => _toggleGroup(group),
                    ),
                ],
              ),

            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: AppSize.iconRow),
                labelText: 'Search clients',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: _filteredClients.isEmpty
                  ? const EmptyState(message: 'No clients match that search.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final client in _filteredClients)
                          CheckboxListTile(
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _selectedClientIds.contains(client.id),
                            title: Text(client.displayName, style: context.text.bodyMedium),
                            onChanged: (checked) => setState(() {
                              if (checked == true) {
                                _selectedClientIds.add(client.id);
                              } else {
                                _selectedClientIds.remove(client.id);
                              }
                            }),
                          ),
                      ],
                    ),
            ),
            if (_selectedClientIds.isNotEmpty)
              Text(
                '${_selectedClientIds.length} client(s) selected.',
                style: context.text.bodySmall,
              ),

            const SizedBox(height: AppSpacing.sm),
            Text('Length', style: context.text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 15, label: Text('15 min')),
                ButtonSegment(value: 30, label: Text('30 min')),
              ],
              selected: {_duration},
              onSelectionChanged: (value) {
                setState(() => _duration = value.first);
                _loadSlots();
              },
            ),

            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _titleCtrl,
              maxLength: 180,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Monthly check-in',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'Optional agenda or context',
                counterText: '',
              ),
            ),

            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Week from ${DateFormat('EEE, MMM d').format(_weekStart)}',
                    style: context.text.labelMedium,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _weekStart,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (picked == null) return;
                    setState(() => _weekStart = picked);
                    await _loadSlots();
                  },
                  child: const Text('Change'),
                ),
              ],
            ),
            if (_loadingSlots)
              const SkeletonBox(height: 60)
            else if (slotDays.isEmpty)
              Text('No open slots in this week.', style: context.text.bodySmall)
            else
              for (final day in slotDays) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    DateFormat('EEE, MMM d').format(DateTime.parse(day)),
                    style: context.text.labelSmall?.copyWith(color: tokens.muted),
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final slot in _slots[day] ?? const <String>[])
                      ChoiceChip(
                        label: Text(
                          DateFormat.jm().format(DateTime.parse(slot).toLocal()),
                        ),
                        selected: _selectedSlot == slot,
                        onSelected: (_) => setState(() => _selectedSlot = slot),
                      ),
                  ],
                ),
              ],

            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _pickExactTime,
              icon: const Icon(Icons.schedule, size: AppSize.iconRow),
              label: const Text('Or pick an exact date & time'),
            ),
            if (selectedTime != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Selected: ${DateFormat('EEE, MMM d · h:mm a').format(selectedTime)}',
                  style: context.text.bodySmall,
                ),
              ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _saving || _selectedClientIds.isEmpty || _selectedSlot.isEmpty
                  ? null
                  : _book,
              child: Text(_saving ? 'Scheduling…' : 'Schedule meeting'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Days off — the mobile form of the web's "Day off" dialog: recurring
/// weekdays on top, one-off dates underneath. Both are layered over the
/// weekly availability windows rather than replacing them, so toggling a day
/// back on brings its saved hours straight back.
class _DaysOffSheet extends ConsumerStatefulWidget {
  const _DaysOffSheet({required this.dateOffs, required this.weekdayOffs});

  final List<DateOffRecord> dateOffs;
  final List<WeekdayOffRecord> weekdayOffs;

  @override
  ConsumerState<_DaysOffSheet> createState() => _DaysOffSheetState();
}

class _DaysOffSheetState extends ConsumerState<_DaysOffSheet> {
  late List<DateOffRecord> _dateOffs;
  late List<WeekdayOffRecord> _weekdayOffs;
  int? _savingWeekday;
  bool _savingDate = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _dateOffs = [...widget.dateOffs];
    _weekdayOffs = [...widget.weekdayOffs];
  }

  Future<void> _toggleWeekday(int weekday) async {
    final existing = _weekdayOffs.where((off) => off.weekday == weekday).firstOrNull;
    setState(() {
      _savingWeekday = weekday;
      _error = '';
    });
    try {
      final api = ref.read(schedulingApiProvider);
      if (existing != null) {
        await api.deleteWeekdayOff(existing.id);
        if (!mounted) return;
        setState(() => _weekdayOffs =
            _weekdayOffs.where((off) => off.id != existing.id).toList());
      } else {
        final added = await api.addWeekdayOff(weekday);
        if (!mounted) return;
        setState(() => _weekdayOffs = [..._weekdayOffs, added]
          ..sort((a, b) => a.weekday.compareTo(b.weekday)));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error is ApiException
          ? error.message
          : 'Could not update that recurring day off.');
    } finally {
      if (mounted) setState(() => _savingWeekday = null);
    }
  }

  Future<void> _addDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // The backend rejects a backdated day off, so the picker starts at today.
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _savingDate = true;
      _error = '';
    });
    try {
      final added = await ref.read(schedulingApiProvider).addDateOff(
            _isoDay.format(picked),
          );
      if (!mounted) return;
      setState(() {
        _dateOffs = [..._dateOffs, added]..sort((a, b) => a.date.compareTo(b.date));
        _savingDate = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingDate = false;
        _error = error is ApiException
            ? error.message
            : 'Could not mark that date as a day off.';
      });
    }
  }

  Future<void> _removeDate(DateOffRecord dateOff) async {
    try {
      await ref.read(schedulingApiProvider).deleteDateOff(dateOff.id);
      if (!mounted) return;
      setState(() =>
          _dateOffs = _dateOffs.where((off) => off.id != dateOff.id).toList());
    } catch (error) {
      if (!mounted) return;
      setState(() => _error =
          error is ApiException ? error.message : 'Could not remove that day off.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        top: AppSpacing.md,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Days off', style: context.text.titleMedium),
            const SizedBox(height: AppSpacing.md),

            Text('Whole weekday, every week', style: context.text.titleSmall),
            Text(
              'Turn off an entire weekday for as long as you like. Your hours '
              'for that day stay saved underneath.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (var weekday = 0;
                    weekday < AvailabilityWindowRecord.weekdayLabels.length;
                    weekday++)
                  FilterChip(
                    label: Text(AvailabilityWindowRecord.weekdayLabels[weekday]),
                    selected: _weekdayOffs.any((off) => off.weekday == weekday),
                    onSelected: _savingWeekday == weekday
                        ? null
                        : (_) => _toggleWeekday(weekday),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: Text('Specific dates', style: context.text.titleSmall)),
                TextButton.icon(
                  onPressed: _savingDate ? null : _addDate,
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: Text(_savingDate ? 'Adding…' : 'Add date'),
                ),
              ],
            ),
            Text(
              'Block off individual dates — holidays, vacation, or a one-off day.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_dateOffs.isEmpty)
              const EmptyState(message: 'No specific days off scheduled.')
            else
              for (final dateOff in _dateOffs)
                RowItem(
                  title: DateFormat('EEE, MMM d, y')
                      .format(DateTime.parse(dateOff.date)),
                  trailing: IconButton(
                    onPressed: () => _removeDate(dateOff),
                    icon: const Icon(Icons.close),
                    iconSize: AppSize.iconRow,
                    color: context.colors.error,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove this day off',
                  ),
                ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error, style: TextStyle(color: context.colors.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
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

/// Book meeting + Set availability as one two-part control.
///
/// Both answer "when do I meet people?", and as a full-width primary button
/// beside a loose icon button they took a whole row while looking unrelated.
/// Booking stays visually primary — it is the frequent action; availability is
/// setup you revisit occasionally.
class _ScheduleActionGroup extends StatelessWidget {
  const _ScheduleActionGroup({
    required this.onBook,
    required this.onAvailability,
    required this.bookBusy,
  });

  final VoidCallback? onBook;
  final VoidCallback onAvailability;
  final bool bookBusy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: onBook,
              icon: const Icon(Icons.add, size: AppSize.iconRow),
              label: Text(bookBusy ? 'Loading…' : 'Book meeting'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSize.buttonHeightSm),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onAvailability,
            icon: const Icon(Icons.schedule_outlined, size: AppSize.iconRow),
            label: const Text('Availability'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
