import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/chat_api.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/models/payment_models.dart';
import '../../core/api/payments_api.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

enum _DashboardTab { activity, payments, schedules }

/// Professional Dashboard — welcome header, overview KPIs, Client Tracking Center
/// charts, schedules, activity, templates.
/// Replica of mobile/src/app/pages/professional/dashboard/professional-dashboard.page.ts.
class ProfessionalDashboardPage extends ConsumerStatefulWidget {
  const ProfessionalDashboardPage({super.key});

  @override
  ConsumerState<ProfessionalDashboardPage> createState() =>
      _ProfessionalDashboardPageState();
}

class _ProfessionalDashboardPageState
    extends ConsumerState<ProfessionalDashboardPage> {
  FormsGroupsOverview? _overview;
  List<ClientReminder> _reminders = [];
  List<ClientProfileEditActivity> _profileEdits = [];
  ScheduleSummary? _summary;
  ProfessionalProfile? _profile;
  ProfessionalDataUsage? _usage;
  PaymentActionsResponse? _paymentActions;
  RevenueSummaryResponse? _revenue;
  ProfessionalUnreadSummary? _unread;
  ProfessionalOnboardingStatus? _onboarding;
  int _notificationUnread = 0;
  final Map<int, String> _clientNameById = {};

  /// Payment notification feed — polled separately from chat unread because
  /// the backend refreshes it far less often, matching the web's 10s vs 5s.
  List<PaymentNotificationItem> _paymentNotifications = [];
  int _paymentsUnreadCount = 0;

  _DashboardTab _tab = _DashboardTab.activity;
  bool _paymentsEnabled = false;
  bool _revenueUnlocked = false;
  String _revenuePeriod = '7';

  /// Set only while [_revenuePeriod] is 'custom'. The backend has accepted
  /// `period=custom&start=&end=` all along and the API client already had the
  /// parameters — mobile just never offered the control.
  DateTimeRange? _revenueCustomRange;
  bool _isReviewing = false;

  String _message = '';
  bool _loading = true;
  int _clientCount = 0;
  int _activeClientCount = 0;

  Timer? _unreadPoll;
  Timer? _paymentUnreadPoll;

  /// The greeting retires itself after [_welcomeDuration]; the user can also
  /// dismiss it early. Shown once per mount, which in practice means once per
  /// sign-in since the dashboard is the landing route.
  bool _showWelcome = true;
  Timer? _welcomeTimer;
  static const _welcomeDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    _unreadPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadUnread(),
    );
    _welcomeTimer = Timer(_welcomeDuration, () {
      if (mounted) setState(() => _showWelcome = false);
    });
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    _paymentUnreadPoll?.cancel();
    _welcomeTimer?.cancel();
    super.dispose();
  }

  /// Started only once payments are known to be enabled — polling an endpoint
  /// the account can't use would 403 on a loop.
  void _startPaymentNotificationPoll() {
    if (_paymentUnreadPoll != null) return;
    _loadPaymentNotifications();
    _paymentUnreadPoll = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadPaymentNotifications(),
    );
  }

  Future<void> _loadPaymentNotifications() async {
    try {
      final response = await ref
          .read(paymentsApiProvider)
          .getProfessionalPaymentNotifications();
      if (!mounted) return;
      setState(() {
        _paymentNotifications = response.items;
        _paymentsUnreadCount = response.unreadCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _paymentNotifications = [];
        _paymentsUnreadCount = 0;
      });
    }
  }

  Future<void> _markAllPaymentsRead() async {
    try {
      await ref
          .read(paymentsApiProvider)
          .markProfessionalPaymentNotificationsRead();
    } catch (error, stackTrace) {
      debugPrint(
        'Marking payment notifications read failed '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
    await _loadPaymentNotifications();
  }

  /// Opens the client/request a notification points at and clears just that
  /// request's unread flag — the same narrow mark-read the web does, so
  /// unrelated notifications stay unread.
  Future<void> _openPaymentNotification(PaymentNotificationItem item) async {
    final requestId = item.requestId;
    final clientId = item.clientId;

    unawaited(
      ref
          .read(paymentsApiProvider)
          .markProfessionalPaymentNotificationsRead(requestId: requestId)
          .then((_) => _loadPaymentNotifications())
          .catchError((_) => _loadPaymentNotifications()),
    );

    if (!mounted) return;
    if (clientId != null) {
      final name = _clientNameById[clientId] ?? '';
      context.go(
        '${Routes.professionalClients}/$clientId/payments'
        '${name.isEmpty ? '' : '?name=${Uri.encodeQueryComponent(name)}'}',
      );
    } else {
      // No parseable client in the action URL — fall back to the Payments tab
      // rather than navigating somewhere arbitrary.
      setState(() => _tab = _DashboardTab.payments);
    }
  }

  Future<void> _loadUnread() async {
    try {
      final summary = await ref
          .read(chatApiProvider)
          .getProfessionalUnreadCounts();
      if (mounted) setState(() => _unread = summary);
    } catch (error, stackTrace) {
      debugPrint(
        'Dashboard unread poll failed (${error.runtimeType})\n$stackTrace',
      );
    }
    // Refreshed on the same tick as chat unread. This page is kept alive by
    // the tab shell, so a one-off fetch in initState would leave the bell
    // frozen at its sign-in value for the whole session.
    try {
      final inbox = await ref
          .read(professionalAuthApiProvider)
          .getNotifications(limit: 1);
      if (mounted) setState(() => _notificationUnread = inbox.unreadCount);
    } catch (error, stackTrace) {
      debugPrint(
        'Dashboard notification poll failed '
        '(${error.runtimeType})\n$stackTrace',
      );
    }
  }

  int get _unreadTotal => _unread?.unreadCount ?? 0;

  int get _pendingRequestCount => _overview?.pendingForms.length ?? 0;

  int get _activityActionCount =>
      _unreadTotal + _pendingRequestCount + _profileEdits.length;

  int get _paymentsActionCount =>
      (_paymentActions?.reviewCount ?? 0) +
      (_paymentActions?.overdueCount ?? 0);

  int get _scheduleActionCount =>
      (_summary?.overdue ?? 0) + (_summary?.due24Hours ?? 0);

  /// Waiting chats, newest unread first — mirrors the web's messageRows.
  List<({int clientId, String name, int count})> get _messageRows {
    final unread = _unread;
    if (unread == null) return [];
    final rows = unread.byClient.entries
        .where((e) => e.value > 0)
        .map(
          (e) => (
            clientId: int.tryParse(e.key) ?? 0,
            name: _clientNameById[int.tryParse(e.key) ?? 0] ?? 'Client',
            count: e.value,
          ),
        )
        .toList();
    rows.sort((a, b) {
      final at = unread.lastUnreadFor(a.clientId)?.millisecondsSinceEpoch ?? 0;
      final bt = unread.lastUnreadFor(b.clientId)?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    return rows;
  }

  String get _professionalName {
    final profile = _profile;
    if (profile == null) return 'Professional';
    final name = profile.displayName;
    return name.isNotEmpty ? name : profile.username;
  }

  /// Each call is independent so one failing endpoint cannot blank the whole
  /// dashboard — same tolerance as the Ionic page, which subscribes separately.
  Future<void> _load() async {
    final professionalAuth = ref.read(professionalAuthApiProvider);
    final formsGroups = ref.read(formsGroupsApiProvider);

    await Future.wait([
      _guard(() async {
        final profile = await professionalAuth.getProfile();
        if (mounted) setState(() => _profile = profile);
      }),
      _guard(() async {
        final usage = await professionalAuth.getDataUsage();
        if (mounted) setState(() => _usage = usage);
      }),
      _guard(() async {
        final status = await professionalAuth.getOnboardingStatus();
        if (mounted) setState(() => _onboarding = status);
      }),
      _guard(() async {
        // Just the header badge count — the full inbox is its own page.
        final inbox = await professionalAuth.getNotifications(limit: 1);
        if (mounted) setState(() => _notificationUnread = inbox.unreadCount);
      }),
      _guard(() async {
        final settings = await ref
            .read(paymentsApiProvider)
            .getPaymentSettings();
        if (!mounted) return;
        setState(() {
          _paymentsEnabled = settings.settings.paymentTrackingEnabled;
          _revenueUnlocked = settings.settings.reportingCurrencyLocked;
        });
        if (_paymentsEnabled) {
          _guard(() async {
            final actions = await ref
                .read(paymentsApiProvider)
                .getPaymentActions();
            if (mounted) setState(() => _paymentActions = actions);
          });
          _startPaymentNotificationPoll();
          if (_revenueUnlocked) _loadRevenue();
        }
      }),
      _guard(
        () async {
          final overview = await formsGroups.getOverview();
          if (!mounted) return;
          setState(() {
            _overview = overview;
            _message = '';
            _countClients(overview);
          });
        },
        onError: () {
          if (mounted) {
            setState(
              () => _message = 'Could not load the dashboard. Pull to retry.',
            );
          }
        },
      ),
      _guard(
        () async {
          final upcoming = await formsGroups.getUpcomingReminders();
          if (!mounted) return;
          setState(() {
            _reminders = upcoming.reminders;
            _summary = upcoming.summary;
            _profileEdits = upcoming.profileEdits;
          });
        },
        onError: () {
          if (mounted) {
            setState(() {
              _reminders = [];
              _profileEdits = [];
            });
          }
        },
      ),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(
    Future<void> Function() run, {
    VoidCallback? onError,
  }) async {
    try {
      await run();
    } catch (_) {
      onError?.call();
    }
  }

  void _countClients(FormsGroupsOverview overview) {
    final converted = overview.approvedForms
        .where((item) => item.clientAccess != null)
        .toList();
    _clientCount = converted.length;
    _activeClientCount = converted.where((item) => item.isActive).length;
    // Map client id -> name so the Activity tab's message rows can be labelled,
    // same source the web dashboard uses.
    for (final submission in converted) {
      final access = submission.clientAccess;
      if (access != null) _clientNameById[access.id] = submission.applicantName;
    }
  }

  /// Short label for the range control — the current selection, not the word
  /// "Filter", so the section states its own scope without a second line of
  /// explanation.
  String get _revenueRangeLabel {
    final range = _revenueCustomRange;
    if (_revenuePeriod == 'custom' && range != null) {
      return '${shortDate(isoDate(range.start))} – ${shortDate(isoDate(range.end))}';
    }
    return switch (_revenuePeriod) {
      '30' => '30 Days',
      '90' => '90 Days',
      'lifetime' => 'All',
      _ => '7 Days',
    };
  }

  /// Five ranges in one menu rather than five chips on the page. Custom opens
  /// the platform date-range picker and calls the same `period=custom`
  /// endpoint the web uses.
  Future<void> _pickRevenueRange() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.card,
                0,
                AppSpacing.card,
                AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Revenue period', style: context.text.titleLarge),
              ),
            ),
            for (final option in const [
              ('7', '7 Days'),
              ('30', '30 Days'),
              ('90', '90 Days'),
              ('lifetime', 'All'),
              ('custom', 'Custom Date Range'),
            ])
              ListTile(
                dense: true,
                title: Text(option.$2),
                trailing: _revenuePeriod == option.$1
                    ? Icon(Icons.check, color: context.colors.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.$1),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: now,
        initialDateRange:
            _revenueCustomRange ??
            DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now,
            ),
      );
      // Cancelling the picker leaves the previous range alone rather than
      // dropping the section into an empty custom period.
      if (picked == null || !mounted) return;
      setState(() {
        _revenuePeriod = 'custom';
        _revenueCustomRange = picked;
      });
    } else {
      setState(() {
        _revenuePeriod = choice;
        _revenueCustomRange = null;
      });
    }
    await _loadRevenue();
  }

  Future<void> _loadRevenue() async {
    try {
      final range = _revenueCustomRange;
      final revenue = await ref
          .read(paymentsApiProvider)
          .getRevenueSummary(
            _revenuePeriod,
            customStart: range == null ? null : isoDate(range.start),
            customEnd: range == null ? null : isoDate(range.end),
          );
      if (mounted) setState(() => _revenue = revenue);
    } catch (_) {
      if (mounted) setState(() => _revenue = null);
    }
  }

  // ----- charts (one per tab, mirroring the web dashboard) -----

  ChartSpec? get _activityChart {
    final data = [
      DataPoint(label: 'Unread messages', value: _unreadTotal.toDouble()),
      DataPoint(
        label: 'Pending requests',
        value: _pendingRequestCount.toDouble(),
      ),
      DataPoint(
        label: 'Account requests',
        value: _profileEdits.length.toDouble(),
      ),
    ];
    if (!data.any((p) => p.value > 0)) return null;
    return ChartSpec(
      kind: ChartKind.bar,
      title: 'Activity breakdown',
      data: data,
      meta: ChartMeta(subtitle: '$_activityActionCount items waiting on you'),
    );
  }

  ChartSpec? get _paymentsChart {
    final review = (_paymentActions?.reviewCount ?? 0).toDouble();
    final overdue = (_paymentActions?.overdueCount ?? 0).toDouble();
    if (review == 0 && overdue == 0) return null;
    return ChartSpec(
      kind: ChartKind.bar,
      title: 'Payments needing action',
      data: [
        DataPoint(label: 'Awaiting review', value: review),
        DataPoint(label: 'Overdue', value: overdue),
      ],
      meta: ChartMeta(subtitle: '$_paymentsActionCount total'),
    );
  }

  ChartSpec? get _revenueChart {
    final points = _revenue?.series ?? [];
    if (points.isEmpty) return null;
    return ChartSpec(
      // Chart type follows the range, not the backend's hint: 7 points are
      // discrete days you compare against each other (bars), while 30 points
      // are a trend you read as a shape (line) — and 30 bars on a phone are
      // too thin to read individually anyway.
      kind: _revenuePeriod == '7' ? ChartKind.bar : ChartKind.line,
      title: 'Revenue (${_revenue?.reportingCurrency ?? ''})',
      data: [for (final p in points) DataPoint(label: p.label, value: p.total)],
      meta: const ChartMeta(subtitle: 'By date received'),
    );
  }

  Future<void> _reviewProfileEdit(
    ClientProfileEditActivity activity,
    String action,
  ) async {
    if (_isReviewing) return;
    setState(() => _isReviewing = true);
    try {
      await ref
          .read(formsGroupsApiProvider)
          .reviewChangeRequest(activity.client, activity.id, action);
      if (mounted) {
        setState(() {
          _profileEdits = _profileEdits
              .where((item) => item.id != activity.id)
              .toList();
        });
      }
      _toast(action == 'approve' ? 'Request approved.' : 'Request declined.');
    } catch (_) {
      _toast('Could not review the request.');
    }
    if (mounted) setState(() => _isReviewing = false);
  }

  Future<void> _completeReminder(ClientReminder reminder) async {
    try {
      await ref
          .read(formsGroupsApiProvider)
          .updateReminder(reminder.id, status: ReminderStatus.done);
      if (mounted) {
        setState(
          () => _reminders = _reminders
              .where((r) => r.id != reminder.id)
              .toList(),
        );
      }
      _toast('Schedule marked complete.');
    } catch (_) {
      _toast('Could not update the schedule.');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 1:1 port of professional-dashboard.component.ts's `scheduleChart` getter
  /// — same 4 bars, same title, same subtitle shape. The web has exactly one
  /// chart on this tab (no separate pending/completed pie); an earlier pass
  /// on mobile drifted from this (wrong 4th bar, plus an extra pie chart the
  /// web doesn't have) — fixed to match exactly.
  ChartSpec? get _scheduleChart {
    final summary = _summary;
    if (summary == null) return null;
    final data = [
      DataPoint(label: 'Overdue', value: summary.overdue.toDouble()),
      DataPoint(label: 'Due in 24 hrs', value: summary.due24Hours.toDouble()),
      DataPoint(label: 'Due in 7 days', value: summary.due7Days.toDouble()),
      DataPoint(
        label: 'Completed in last 7 days',
        value: summary.completedLast7Days.toDouble(),
      ),
    ];
    if (!data.any((point) => point.value > 0)) return null;
    return ChartSpec(
      kind: ChartKind.bar,
      title: 'Schedule status',
      data: data,
      meta: ChartMeta(
        subtitle:
            '${summary.totalPending} pending, ${summary.totalCompleted} completed overall',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: PagePad(
            children: [
              SkeletonBox(height: 56),
              SkeletonBox(height: 150),
              SkeletonBox(height: 150),
              SkeletonBox(height: 200),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // No AppBar — every tab shares one header shape now: eyebrow/title in
      // a row with that page's own actions (here, just the bell), then the
      // subtitle. A bare 52px toolbar with nothing but an icon in it was
      // dead space, and the old profile-photo action duplicated what More →
      // My Profile already does.
      body: SafeArea(
        child: PagePad(
          onRefresh: _load,
          children: [
            PageHeader(
              eyebrow: 'PROFESSIONAL DASHBOARD',
              title: 'Dashboard',
              info:
                  'Everything that needs your attention today, in one '
                  'place.\n\n'
                  'ACTIVITY\n'
                  'New sign-ups, client entries, and messages since you last '
                  'looked.\n\n'
                  'PAYMENTS\n'
                  'What you have been paid, what is overdue, and what is '
                  'waiting on your review.\n\n'
                  'SCHEDULES\n'
                  'Meetings and follow-ups coming up across all your clients.',
              trailing: NotificationBell(
                unread: _notificationUnread,
                onTap: () => context.push(Routes.professionalNotifications),
              ),
            ),
            // "Welcome back" is a greeting, not information — it earned a
            // permanent line on the page while saying nothing after the first
            // read. It now appears once per sign-in and retires itself.
            if (_showWelcome) ...[
              const SizedBox(height: AppSpacing.md),
              _WelcomeBanner(
                name: _professionalName,
                onDismiss: () => setState(() => _showWelcome = false),
              ),
            ],
            if (_message.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ErrorNote(message: _message, onRetry: _load),
            ],
            if (_onboarding != null && _onboarding!.hasPendingSetup) ...[
              const SizedBox(height: AppSpacing.md),
              _ActionRequiredBanner(status: _onboarding!),
            ],
            const SizedBox(height: AppSpacing.md),
            _PlanUsageCard(
              usage: _usage,
              clientCount: _clientCount,
              activeClientCount: _activeClientCount,
            ),
            const SizedBox(height: AppSpacing.md),
            _DashboardTabBar(
              tab: _tab,
              paymentsEnabled: _paymentsEnabled,
              activityCount: _activityActionCount,
              paymentsCount: _paymentsActionCount,
              scheduleCount: _scheduleActionCount,
              onSelect: (tab) => setState(() => _tab = tab),
            ),
            const SizedBox(height: AppSpacing.sm),
            ..._tabContent(summary),
          ],
        ),
      ),
    );
  }

  List<Widget> _tabContent(ScheduleSummary? summary) {
    return switch (_tab) {
      _DashboardTab.activity => _activityTab(),
      _DashboardTab.payments =>
        _paymentsEnabled
            ? _paymentsTab()
            : [
                const EmptyState(
                  compact: false,
                  icon: Icons.payments_outlined,
                  message:
                      'Payment tracking is off.\nEnable it from Manage → Payments.',
                ),
              ],
      _DashboardTab.schedules => _schedulesTab(summary),
    };
  }

  // ----- Activity tab -----

  List<Widget> _activityTab() {
    final messages = _messageRows;
    final requests = _overview?.pendingForms ?? const [];

    return [
      _CompactStatRow(
        stats: [
          _CompactStat(
            value: '$_unreadTotal',
            label: 'Unread\nMessages',
            icon: Icons.chat_bubble_outline,
            accent: MenuAccent.purple,
          ),
          _CompactStat(
            value: '${requests.length}',
            label: 'Pending\nRequests',
            icon: Icons.assignment_outlined,
            accent: MenuAccent.green,
            onTap: () =>
                context.go('${Routes.professionalFormsGroups}?tab=requests'),
          ),
          _CompactStat(
            value: '${_profileEdits.length}',
            label: 'Account\nRequests',
            icon: Icons.person_outline,
            accent: MenuAccent.blue,
          ),
          _CompactStat(
            value: '$_activityActionCount',
            label: 'Waiting\non You',
            icon: Icons.hourglass_top_outlined,
            accent: _activityActionCount > 0
                ? MenuAccent.orange
                : (fg: context.tokens.muted, bg: context.tokens.surfaceSoft),
          ),
        ],
      ),
      if (_activityChart != null) ...[
        const SizedBox(height: AppSpacing.md),
        ChartCard(spec: _activityChart!, shareContext: 'Activity'),
      ],

      const SectionHeader(title: 'Pending requests'),
      if (requests.isEmpty)
        const EmptyState(message: 'No new enquiries.')
      else
        for (final submission in requests.take(6))
          RowItem(
            title: submission.applicantName,
            subtitle: 'Submitted ${_shortDate(submission.submittedAt)}',
            leading: AppAvatar(
              initials: _initialsFor(submission.applicantName),
              size: 38,
            ),
            trailing: const StatusPill(label: 'Review', tone: PillTone.warn),
            onTap: () =>
                context.go('${Routes.professionalFormsGroups}?tab=requests'),
          ),

      const SectionHeader(title: 'Unread messages'),
      if (messages.isEmpty)
        const EmptyState(message: 'You are all caught up.')
      else
        for (final row in messages.take(8))
          RowItem(
            title: row.name,
            subtitle: '${row.count} unread message${row.count == 1 ? '' : 's'}',
            leading: AppAvatar(initials: _initialsFor(row.name), size: 38),
            trailing: StatusPill(label: '${row.count}', tone: PillTone.info),
            onTap: () =>
                context.go('${Routes.professionalClients}/${row.clientId}'),
          ),

      const SectionHeader(title: 'Account requests'),
      if (_profileEdits.isEmpty)
        const EmptyState(message: 'No client requests waiting.')
      else
        for (final activity in _profileEdits.take(6))
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
                          activity.clientName,
                          style: context.text.titleSmall,
                        ),
                      ),
                      StatusPill(
                        label: activity.isDeletion
                            ? 'Deletion'
                            : 'Profile edit',
                        tone: activity.isDeletion
                            ? PillTone.bad
                            : PillTone.info,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity.isDeletion
                        ? 'Requested account deletion'
                        : '${activity.proposedFieldCount} profile field(s) changed',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _isReviewing
                              ? null
                              : () => _reviewProfileEdit(activity, 'approve'),
                          child: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isReviewing
                              ? null
                              : () => _reviewProfileEdit(activity, 'reject'),
                          child: const Text('Decline'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    ];
  }

  // ----- Payments tab -----

  /// 1:1 port of the web dashboard's payments tab: the KPI row, chart, and
  /// needs-action list all live *inside* the same `revenueUnlocked` gate as
  /// revenue (see professional-dashboard.component.html's single
  /// `@if (revenueUnlocked) { ... }` wrapping everything but the setup
  /// card) — an earlier mobile pass showed the KPIs/chart/list unconditionally
  /// and only gated revenue, which let a professional with no reporting
  /// currency set see numbers the web would have hidden behind setup first.
  List<Widget> _paymentsTab() {
    if (!_revenueUnlocked) return [const _ReportingCurrencySetupCard()];

    final actions = _paymentActions?.items ?? const [];

    return [
      _CompactStatRow(
        stats: [
          _CompactStat(
            value: '${_paymentActions?.reviewCount ?? 0}',
            label: 'Awaiting\nReview',
            icon: Icons.rate_review_outlined,
            accent: MenuAccent.blue,
          ),
          _CompactStat(
            value: '${_paymentActions?.overdueCount ?? 0}',
            label: 'Overdue',
            icon: Icons.error_outline,
            accent: (_paymentActions?.overdueCount ?? 0) > 0
                ? (
                    fg: context.colors.error,
                    bg: context.colors.error.withValues(alpha: 0.12),
                  )
                : (fg: context.tokens.muted, bg: context.tokens.surfaceSoft),
          ),
        ],
      ),
      if (_paymentsChart != null) ...[
        const SizedBox(height: AppSpacing.md),
        ChartCard(spec: _paymentsChart!, shareContext: 'Payments'),
      ],

      // Payment notification feed — the web has had this on its dashboard all
      // along; mobile fetched the count and threw it away.
      if (_paymentNotifications.isNotEmpty) ...[
        SectionHeader(
          title: _paymentsUnreadCount > 0
              ? 'Payment updates ($_paymentsUnreadCount new)'
              : 'Payment updates',
          actionLabel: _paymentsUnreadCount > 0 ? 'Mark all read' : null,
          onAction: _paymentsUnreadCount > 0 ? _markAllPaymentsRead : null,
        ),
        for (final item in _paymentNotifications.take(5))
          RowItem(
            title: item.title,
            subtitle: item.body,
            leading: Icon(
              item.isRead
                  ? Icons.notifications_none
                  : Icons.notifications_active_outlined,
              size: AppSize.iconRow,
              color: item.isRead
                  ? context.tokens.muted
                  : context.colors.primary,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPaymentNotification(item),
          ),
      ],

      ...[
        // The range control lives in the heading's action slot: one compact
        // menu instead of a row of chips that wrapped to two lines and
        // competed with the heading for weight. The "Payments" shortcut that
        // used to sit here is reachable from Manage and from Settings ->
        // Payments already, and it was occupying the slot the filter needs.
        SectionHeader(
          title: 'Revenue Overview',
          actionLabel: _revenueRangeLabel,
          actionIcon: Icons.filter_list,
          onAction: _pickRevenueRange,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Two tiles, not two halves of one card. Sharing a card forced the
        // two amounts to compete for the same width, so a longer currency
        // figure (INR 1,20,000) pushed the other one off the screen edge.
        _CompactStatRow(
          stats: [
            _CompactStat(
              value: _revenue != null
                  ? '${_revenue!.reportingCurrency} ${_revenue!.totalRevenue}'
                  : '—',
              label: 'Total',
              icon: Icons.savings_outlined,
              accent: MenuAccent.green,
            ),
            _CompactStat(
              value: _revenue != null
                  ? '${_revenue!.reportingCurrency} ${_revenue!.thisMonthTotal}'
                  : '—',
              label: 'This month',
              icon: Icons.calendar_month_outlined,
              accent: MenuAccent.blue,
            ),
          ],
        ),
        if (_revenueChart != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ChartCard(spec: _revenueChart!, shareContext: 'Revenue'),
        ],
      ],

      const SectionHeader(title: 'Needs action'),
      if (actions.isEmpty)
        const EmptyState(message: 'No payments waiting on you.')
      else
        for (final item in actions.take(8))
          RowItem(
            title: item.clientName,
            subtitle: item.title,
            trailingValue: '${item.requestedCurrency} ${item.requestedAmount}',
            trailingCaption: PaymentRequestStatus.label(item.status),
            onTap: () => context.go(
              '${Routes.professionalClients}/${item.clientId}/payments'
              '?name=${Uri.encodeQueryComponent(item.clientName)}',
            ),
          ),
    ];
  }

  // ----- Schedules tab -----

  List<Widget> _schedulesTab(ScheduleSummary? summary) {
    final overdue = _reminders.where(_isOverdue).toList();
    final upcoming = _reminders.where((r) => !_isOverdue(r)).toList();

    return [
      _CompactStatRow(
        stats: [
          _CompactStat(
            value: '${summary?.overdue ?? 0}',
            label: 'Overdue',
            icon: Icons.warning_amber_outlined,
            accent: (summary?.overdue ?? 0) > 0
                ? (
                    fg: context.colors.error,
                    bg: context.colors.error.withValues(alpha: 0.12),
                  )
                : (fg: context.tokens.muted, bg: context.tokens.surfaceSoft),
          ),
          _CompactStat(
            value: '${summary?.due24Hours ?? 0}',
            label: 'Due\n24h',
            icon: Icons.timer_outlined,
            accent: MenuAccent.orange,
          ),
          _CompactStat(
            value: '${summary?.due7Days ?? 0}',
            label: 'Due\n7 days',
            icon: Icons.calendar_today_outlined,
            accent: MenuAccent.blue,
          ),
          _CompactStat(
            value: '${summary?.completedLast7Days ?? 0}',
            label: 'Done\n(7d)',
            icon: Icons.check_circle_outline,
            accent: MenuAccent.green,
          ),
        ],
      ),
      if (_scheduleChart != null) ...[
        const SizedBox(height: AppSpacing.md),
        ChartCard(spec: _scheduleChart!, shareContext: 'Schedules'),
      ],

      if (overdue.isNotEmpty) ...[
        SectionHeader(title: 'Overdue schedules (${overdue.length})'),
        for (final reminder in overdue) _scheduleRow(reminder, overdue: true),
      ],
      SectionHeader(
        title: 'Upcoming schedules (${upcoming.length})',
        actionLabel: 'View all',
        onAction: () => context.go(Routes.professionalSchedule),
      ),
      if (upcoming.isEmpty)
        const EmptyState(message: 'Nothing scheduled soon.')
      else
        for (final reminder in upcoming.take(10))
          _scheduleRow(reminder, overdue: false),
    ];
  }

  bool _isOverdue(ClientReminder reminder) {
    final target = DateTime.tryParse(
      '${reminder.date}T${reminder.time.isNotEmpty ? reminder.time : '23:59'}',
    );
    return target != null && target.isBefore(DateTime.now());
  }

  Widget _scheduleRow(ClientReminder reminder, {required bool overdue}) {
    return RowItem(
      title: reminder.title,
      subtitle: reminder.clientName,
      leading: IconButton(
        onPressed: () => _completeReminder(reminder),
        icon: const Icon(Icons.check_circle_outline),
        iconSize: 22,
        color: context.tokens.success,
        visualDensity: VisualDensity.compact,
        tooltip: 'Mark complete',
      ),
      trailingValue: _shortDate(reminder.date),
      trailingCaption: overdue
          ? 'Overdue'
          : reminder.time.isNotEmpty
          ? reminder.time.substring(0, 5)
          : 'Any time',
      onTap: () =>
          context.go('${Routes.professionalClients}/${reminder.client}'),
    );
  }

  String _initialsFor(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'C';
    final letters = parts.map((p) => p[0]).take(2).join().toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  /// "15 Jul" — the `date: 'dd MMM'` pipe in the Ionic template.
  String _shortDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
  }
}

/// Activity | Payments | Schedules switcher with per-tab action-count badges,
/// mirroring the web dashboard's tab strip.
class _DashboardTabBar extends StatelessWidget {
  const _DashboardTabBar({
    required this.tab,
    required this.paymentsEnabled,
    required this.activityCount,
    required this.paymentsCount,
    required this.scheduleCount,
    required this.onSelect,
  });

  final _DashboardTab tab;
  final bool paymentsEnabled;
  final int activityCount;
  final int paymentsCount;
  final int scheduleCount;
  final ValueChanged<_DashboardTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = <(_DashboardTab, String, int)>[
      (_DashboardTab.activity, 'Activity', activityCount),
      if (paymentsEnabled) (_DashboardTab.payments, 'Payments', paymentsCount),
      (_DashboardTab.schedules, 'Schedules', scheduleCount),
    ];

    // Same SegmentedButton the Clients, Schedule, and Forms & Groups pages
    // already use (with their default app-theme styling) — this used to be
    // a hand-rolled pill row with its own padding/border/radius, which read
    // as a visibly different control from every other tab strip in the app.
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<_DashboardTab>(
        segments: [
          for (final (value, label, count) in tabs)
            ButtonSegment(
              value: value,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label),
                  if (count > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      count > 99 ? '99+' : '$count',
                      style: context.text.labelSmall?.copyWith(
                        color: tab == value
                            ? context.colors.onPrimary
                            : context.colors.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        selected: {tab},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onSelect(selection.first),
      ),
    );
  }
}

/// "Action Required" workspace-setup checklist — real data from
/// GET /professional/dashboard/onboarding-status/. Hidden entirely once every
/// check passes, same as the web dashboard's `@if (missing_actions.length)`.
class _ActionRequiredBanner extends StatelessWidget {
  const _ActionRequiredBanner({required this.status});

  final ProfessionalOnboardingStatus status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? context.colors.onSurface : Colors.white;
    final mutedForeground = foreground.withValues(alpha: 0.78);
    final items = <(String, bool, VoidCallback, IconData)>[
      (
        'Lead Form',
        status.formCreated,
        () => context.go(Routes.professionalFormsGroups),
        Icons.description_outlined,
      ),
      (
        'Group',
        status.groupCreated,
        () => context.go(Routes.professionalFormsGroups),
        Icons.people_outline,
      ),
      (
        'Template',
        status.templateCreated,
        () => context.go(Routes.professionalFormsGroups),
        Icons.layers_outlined,
      ),
      (
        'Resources',
        status.resourceCreated,
        () => context.go(Routes.professionalResources),
        Icons.folder_open_outlined,
      ),
      (
        'Meeting Setup',
        status.meetingSetupComplete,
        () => context.go(Routes.professionalSchedule),
        Icons.event_available_outlined,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: BoxDecoration(
        color: isDark ? context.colors.surface : context.colors.primary,
        borderRadius: AppRadius.lgAll,
        border: isDark
            ? Border.all(color: context.colors.primary.withValues(alpha: 0.32))
            : null,
        boxShadow: isDark ? context.tokens.shadowSm : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: foreground, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Action Required',
                  style: context.text.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${status.completedCount} of ${ProfessionalOnboardingStatus.totalChecks} completed',
                style: context.text.labelSmall?.copyWith(
                  color: mutedForeground,
                ),
              ),
            ],
          ),
          if (status.message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              status.message,
              style: context.text.bodySmall?.copyWith(color: mutedForeground),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _ChecklistIcon(
                    label: item.$1,
                    done: item.$2,
                    onTap: item.$3,
                    icon: item.$4,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistIcon extends StatelessWidget {
  const _ChecklistIcon({
    required this.label,
    required this.done,
    required this.onTap,
    required this.icon,
  });

  final String label;
  final bool done;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? context.colors.onSurface : Colors.white;
    final circleColor = isDark
        ? (done ? context.tokens.primarySoft : context.tokens.surfaceSoft)
        : Colors.white.withValues(alpha: done ? 0.95 : 0.22);
    final iconColor = done
        ? context.colors.primary
        : (isDark ? context.tokens.warningStrong : const Color(0xFFFFDDAA));

    return InkWell(
      onTap: done ? null : onTap,
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Done keeps the flat white circle; not-done gets a warmer,
                // slightly more visible tint so it reads as "needs attention"
                // rather than the plain translucent-white it used to share
                // with every other unchecked state on this banner.
                color: circleColor,
                shape: BoxShape.circle,
                border: isDark
                    ? Border.all(color: context.tokens.border)
                    : null,
              ),
              child: Icon(
                done ? Icons.check : icon,
                // Warm amber/white mix — distinct from the done state's
                // brand-primary check, still readable on the blue banner.
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: labelColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plan name + resource-vs-limit counts + storage bar. All figures come from
/// GET /professional/data-usage/ (already loaded for other pages) — nothing
/// here is invented.
class _PlanUsageCard extends StatelessWidget {
  const _PlanUsageCard({
    required this.usage,
    required this.clientCount,
    required this.activeClientCount,
  });

  final ProfessionalDataUsage? usage;
  final int clientCount;
  final int activeClientCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final u = usage;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Plan and Usage', style: context.text.titleMedium),
              ),
              GestureDetector(
                onTap: () => context.go(Routes.professionalSettings),
                child: StatusPill(
                  label: u?.planName ?? '—',
                  tone: PillTone.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _UsageStat(
                  label: 'Clients',
                  value: '$clientCount',
                  caption: '$activeClientCount active',
                  level: _levelFor(u?.resourceUsage['clients']),
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: 'Groups',
                  value: '${u?.resourceUsage['groups']?.used ?? '—'}',
                  caption: u?.resourceUsage['groups']?.limit == null
                      ? 'Unlimited'
                      : 'of ${u?.resourceUsage['groups']?.limit}',
                  level: _levelFor(u?.resourceUsage['groups']),
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: 'Templates',
                  value: '${u?.resourceUsage['templates']?.used ?? '—'}',
                  caption: u?.resourceUsage['templates']?.limit == null
                      ? 'Unlimited'
                      : 'of ${u?.resourceUsage['templates']?.limit}',
                  level: _levelFor(u?.resourceUsage['templates']),
                ),
              ),
              Expanded(
                child: _UsageStat(
                  label: 'Resources',
                  value: '${u?.resourceUsage['resources']?.used ?? '—'}',
                  caption: u?.resourceUsage['resources']?.limit == null
                      ? 'Unlimited'
                      : 'of ${u?.resourceUsage['resources']?.limit}',
                  level: _levelFor(u?.resourceUsage['resources']),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Builder(
            builder: (context) {
              // Storage has its own warning/danger flags from the backend, so
              // it doesn't go through _levelFor — but it lands on the same
              // three colours, and green rather than brand-blue when healthy,
              // so a glance down the card reads consistently.
              final storageColor = (u?.isDanger ?? false)
                  ? context.colors.error
                  : (u?.isWarning ?? false)
                  ? tokens.accent
                  : tokens.success;
              final percent = (u?.usagePercent ?? 0).clamp(0, 100);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Storage used',
                        style: context.text.bodySmall?.copyWith(
                          color: tokens.muted,
                        ),
                      ),
                      Text(
                        '${percent.toStringAsFixed(0)}%',
                        style: context.text.labelMedium?.copyWith(
                          color: storageColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: AppRadius.pillAll,
                    child: LinearProgressIndicator(
                      value: (percent / 100).clamp(0, 1).toDouble(),
                      minHeight: 10,
                      backgroundColor: tokens.surfaceSoft,
                      color: storageColor,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Sized to its label, not the card. Full-width made a secondary
          // link the heaviest element in the Plan & Usage card, competing
          // with the figures above it.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              // Straight to Plan & Storage, which is the report this card
              // summarises. It used to land on the Settings index, leaving you
              // to find the right row yourself.
              onPressed: () =>
                  context.go(Routes.professionalSettingsPlanStorage),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, AppSize.buttonHeightSm),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.bar_chart_outlined, size: AppSize.iconRow),
              label: const Text('View all usage'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transient sign-in greeting. Auto-retires after five seconds, or on tap of
/// the close button — see [_ProfessionalDashboardPageState._showWelcome].
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({required this.name, required this.onDismiss});

  final String name;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      color: tokens.primarySoft,
      radius: AppRadius.tile,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.card,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(
            Icons.waving_hand_outlined,
            size: AppSize.iconRow,
            color: tokens.primaryStrong,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Welcome back, $name',
              style: context.text.bodyLarge?.copyWith(
                color: tokens.primaryStrong,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
            iconSize: AppSize.iconRow,
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            color: tokens.primaryStrong,
          ),
        ],
      ),
    );
  }
}

/// Dashboard KPIs, two across rather than four.
///
/// Four tiles on a ~390pt phone left each one about 85pt wide, which forced
/// the value down to title size and wrapped every label onto two lines — the
/// numbers, which are the entire point, ended up the smallest thing in the
/// card. Two across doubles the width, so the value can be display-sized and
/// labels fit on one line. Rows are laid out in pairs, and an odd final tile
/// simply takes the left half rather than stretching full width, which keeps
/// the grid reading as a grid.
class _CompactStatRow extends StatelessWidget {
  const _CompactStatRow({required this.stats});

  final List<_CompactStat> stats;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      final left = stats[i];
      final right = i + 1 < stats.length ? stats[i + 1] : null;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: right ?? const SizedBox.shrink()),
            ],
          ),
        ),
      );
      if (i + 2 < stats.length) {
        rows.add(const SizedBox(height: AppSpacing.sm));
      }
    }
    return Column(children: rows);
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.value,
    required this.label,
    this.icon,
    this.accent,
    this.onTap,
  }) : valueColor = null;

  final String value;
  final String label;

  /// When set (together with [accent]), a small tinted icon chip renders
  /// above the value — the same [MenuAccent] treatment as [ColorfulMenuCard].
  /// Both are optional so any call site that skips them still gets the
  /// original plain value/label rendering.
  final IconData? icon;
  final ({Color fg, Color bg})? accent;

  /// Explicit override for the value text color. When null, falls back to
  /// [accent]'s fg color if an accent was passed, else the theme default.
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final effectiveValueColor = valueColor ?? accent?.fg;

    // Keep every KPI on the same surface. Accent colors remain on the value
    // and icon so status is still scannable without mismatched card fills.
    final tint = tokens.surfaceSoft;

    // Labels arrive with hard newlines from the old four-across layout
    // ("Unread\nMessages"). At double the width they fit on one line, so the
    // breaks are stripped rather than every call site being rewritten.
    final flatLabel = label.replaceAll('\n', ' ');

    return AppCard(
      onTap: onTap,
      color: tint,
      radius: AppRadius.tile,
      padding: const EdgeInsets.all(AppSpacing.card),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: context.text.headlineSmall?.copyWith(
                    color: effectiveValueColor,
                    letterSpacing: -0.4,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  flatLabel.toUpperCase(),
                  style: context.text.labelSmall?.copyWith(
                    color: tokens.muted,
                    height: 1.25,
                    letterSpacing: 0.5,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (icon != null && accent != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(icon, size: AppSize.iconButton, color: accent!.fg),
          ],
        ],
      ),
    );
  }
}

/// Shown instead of the whole Payments tab until a reporting currency is set
/// — 1:1 copy (steps + button) of the web's `.payment-unlock-card`.
class _ReportingCurrencySetupCard extends StatelessWidget {
  const _ReportingCurrencySetupCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ONE-TIME SETUP',
            style: context.text.labelSmall?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your reporting currency',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, step) in const [
            'Open Settings → Payments.',
            'Select the currency you use for payment reports.',
            'Save it to unlock revenue totals and payment activity.',
          ].indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: context.text.bodySmall?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      step,
                      style: context.text.bodySmall?.copyWith(
                        color: tokens.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go(Routes.professionalSettings),
              child: const Text('Open Payment Settings'),
            ),
          ),
        ],
      ),
    );
  }
}

/// How close a plan resource is to its ceiling. Drives the colour of both the
/// figure and its caption so the state is readable without doing the division
/// in your head.
///
/// Unlimited resources are deliberately [_UsageLevel.ok] rather than a fourth
/// "neutral" state — there is no ceiling to approach, so healthy is the honest
/// reading, and adding a grey variant would just make the row noisier.
enum _UsageLevel { ok, warning, over }

_UsageLevel _levelFor(PlanResourceUsage? entry) {
  if (entry == null) return _UsageLevel.ok;
  final limit = entry.limit;
  if (limit == null || limit <= 0) return _UsageLevel.ok;
  final ratio = entry.used / limit;
  if (ratio >= 1) return _UsageLevel.over;
  if (ratio >= 0.8) return _UsageLevel.warning;
  return _UsageLevel.ok;
}

class _UsageStat extends StatelessWidget {
  const _UsageStat({
    required this.label,
    required this.value,
    required this.caption,
    this.level = _UsageLevel.ok,
  });

  final String label;
  final String value;
  final String caption;
  final _UsageLevel level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = switch (level) {
      _UsageLevel.ok => tokens.success,
      _UsageLevel.warning => tokens.accent,
      _UsageLevel.over => context.colors.error,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.text.labelSmall?.copyWith(color: tokens.muted),
        ),
        const SizedBox(height: 2),
        Text(value, style: context.text.titleLarge?.copyWith(color: color)),
        Text(
          caption,
          // The caption carries the limit ("of 25"), so it takes the state
          // colour too — at rest that's a calm green, and it turns red on the
          // one number that actually matters when a plan is exhausted.
          style: context.text.labelSmall?.copyWith(
            color: level == _UsageLevel.ok ? tokens.muted : color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
