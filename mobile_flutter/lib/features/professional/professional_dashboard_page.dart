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
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/widgets/app_widgets.dart';

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

class _ProfessionalDashboardPageState extends ConsumerState<ProfessionalDashboardPage> {
  FormsGroupsOverview? _overview;
  List<ClientReminder> _reminders = [];
  List<ClientProfileEditActivity> _profileEdits = [];
  ScheduleSummary? _summary;
  ProfessionalProfile? _profile;
  ProfessionalDataUsage? _usage;
  PaymentActionsResponse? _paymentActions;
  RevenueSummaryResponse? _revenue;
  ProfessionalUnreadSummary? _unread;
  final Map<int, String> _clientNameById = {};

  _DashboardTab _tab = _DashboardTab.activity;
  bool _paymentsEnabled = false;
  bool _revenueUnlocked = false;
  String _revenuePeriod = '7';
  bool _isReviewing = false;

  String _message = '';
  bool _loading = true;
  int _clientCount = 0;
  int _activeClientCount = 0;

  Timer? _unreadPoll;

  @override
  void initState() {
    super.initState();
    _load();
    _loadUnread();
    _unreadPoll = Timer.periodic(const Duration(seconds: 5), (_) => _loadUnread());
  }

  @override
  void dispose() {
    _unreadPoll?.cancel();
    super.dispose();
  }

  Future<void> _loadUnread() async {
    try {
      final summary = await ref.read(chatApiProvider).getProfessionalUnreadCounts();
      if (mounted) setState(() => _unread = summary);
    } catch (_) {/* a failed poll must not disturb the dashboard */}
  }

  int get _unreadTotal => _unread?.unreadCount ?? 0;

  int get _pendingRequestCount => _overview?.pendingForms.length ?? 0;

  int get _activityActionCount =>
      _unreadTotal + _pendingRequestCount + _profileEdits.length;

  int get _paymentsActionCount =>
      (_paymentActions?.reviewCount ?? 0) + (_paymentActions?.overdueCount ?? 0);

  int get _scheduleActionCount =>
      (_summary?.overdue ?? 0) + (_summary?.due24Hours ?? 0);

  /// Waiting chats, newest unread first — mirrors the web's messageRows.
  List<({int clientId, String name, int count})> get _messageRows {
    final unread = _unread;
    if (unread == null) return [];
    final rows = unread.byClient.entries
        .where((e) => e.value > 0)
        .map((e) => (
              clientId: int.tryParse(e.key) ?? 0,
              name: _clientNameById[int.tryParse(e.key) ?? 0] ?? 'Client',
              count: e.value,
            ))
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

  String get _initials {
    final letters = _professionalName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    if (letters.isEmpty) return 'T';
    return letters.length > 2 ? letters.substring(0, 2) : letters;
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
        final settings = await ref.read(paymentsApiProvider).getPaymentSettings();
        if (!mounted) return;
        setState(() {
          _paymentsEnabled = settings.settings.paymentTrackingEnabled;
          _revenueUnlocked = settings.settings.reportingCurrencyLocked;
        });
        if (_paymentsEnabled) {
          _guard(() async {
            final actions = await ref.read(paymentsApiProvider).getPaymentActions();
            if (mounted) setState(() => _paymentActions = actions);
          });
          if (_revenueUnlocked) _loadRevenue();
        }
      }),
      _guard(() async {
        final overview = await formsGroups.getOverview();
        if (!mounted) return;
        setState(() {
          _overview = overview;
          _message = '';
          _countClients(overview);
        });
      }, onError: () {
        if (mounted) {
          setState(() => _message = 'Could not load the dashboard. Pull to retry.');
        }
      }),
      _guard(() async {
        final upcoming = await formsGroups.getUpcomingReminders();
        if (!mounted) return;
        setState(() {
          _reminders = upcoming.reminders;
          _summary = upcoming.summary;
          _profileEdits = upcoming.profileEdits;
        });
      }, onError: () {
        if (mounted) {
          setState(() {
            _reminders = [];
            _profileEdits = [];
          });
        }
      }),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(Future<void> Function() run, {VoidCallback? onError}) async {
    try {
      await run();
    } catch (_) {
      onError?.call();
    }
  }

  void _countClients(FormsGroupsOverview overview) {
    final converted =
        overview.approvedForms.where((item) => item.clientAccess != null).toList();
    _clientCount = converted.length;
    _activeClientCount = converted.where((item) => item.isActive).length;
    // Map client id -> name so the Activity tab's message rows can be labelled,
    // same source the web dashboard uses.
    for (final submission in converted) {
      final access = submission.clientAccess;
      if (access != null) _clientNameById[access.id] = submission.applicantName;
    }
  }

  Future<void> _loadRevenue() async {
    try {
      final revenue =
          await ref.read(paymentsApiProvider).getRevenueSummary(_revenuePeriod);
      if (mounted) setState(() => _revenue = revenue);
    } catch (_) {
      if (mounted) setState(() => _revenue = null);
    }
  }

  // ----- charts (one per tab, mirroring the web dashboard) -----

  ChartSpec? get _activityChart {
    final data = [
      DataPoint(label: 'Unread messages', value: _unreadTotal.toDouble()),
      DataPoint(label: 'Pending requests', value: _pendingRequestCount.toDouble()),
      DataPoint(label: 'Account requests', value: _profileEdits.length.toDouble()),
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
      kind: _revenue?.chartKind == 'line' ? ChartKind.line : ChartKind.bar,
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
          _profileEdits =
              _profileEdits.where((item) => item.id != activity.id).toList();
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
        setState(() =>
            _reminders = _reminders.where((r) => r.id != reminder.id).toList());
      }
      _toast('Schedule marked complete.');
    } catch (_) {
      _toast('Could not update the schedule.');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Built from the schedule summary, not the graph engine — these are
  /// dashboard-specific specs, matching buildCharts() in the Ionic page.
  ChartSpec? get _priorityChart {
    final summary = _summary;
    if (summary == null) return null;
    final data = [
      DataPoint(label: 'Overdue', value: summary.overdue.toDouble()),
      DataPoint(label: 'Next 24h', value: summary.due24Hours.toDouble()),
      DataPoint(label: 'Next 7 days', value: summary.due7Days.toDouble()),
      DataPoint(label: 'Profile edits', value: summary.pendingProfileEdits.toDouble()),
    ];
    if (!data.any((point) => point.value > 0)) return null;
    return ChartSpec(
      kind: ChartKind.bar,
      title: 'Attention by priority',
      data: data,
      meta: const ChartMeta(subtitle: 'Open items needing action'),
    );
  }

  ChartSpec? get _statusChart {
    final summary = _summary;
    if (summary == null) return null;
    final data = [
      DataPoint(label: 'Pending', value: summary.totalPending.toDouble()),
      DataPoint(label: 'Completed', value: summary.totalCompleted.toDouble()),
    ];
    if (!data.any((point) => point.value > 0)) return null;
    return ChartSpec(
      kind: ChartKind.pie,
      title: 'Schedule status',
      data: data,
      meta: const ChartMeta(subtitle: 'Pending vs completed schedules'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const PagePad(
          children: [
            SkeletonBox(height: 56),
            SkeletonBox(height: 150),
            SkeletonBox(height: 150),
            SkeletonBox(height: 200),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: PagePad(
        onRefresh: _load,
        children: [
          _Hero(name: _professionalName, initials: _initials, profile: _profile),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],
          SectionHeader(
            title: 'Overview',
            actionLabel: 'Clients',
            onAction: () => context.go(Routes.professionalClients),
            topSpace: AppSpacing.lg,
          ),
          KpiGrid(
            children: [
              KpiTile(
                label: 'Clients',
                icon: Icons.people_outline,
                value: '$_clientCount',
                caption: '$_activeClientCount active',
                onTap: () => context.go(Routes.professionalClients),
              ),
              KpiTile(
                label: 'Forms',
                icon: Icons.description_outlined,
                value: '$_pendingRequestCount',
                caption: 'pending review',
                onTap: () => context.go(Routes.professionalFormsGroups),
              ),
              KpiTile(
                label: 'Groups',
                icon: Icons.groups_outlined,
                value: _usage?.resourceUsage['groups']?.label ?? '—',
                caption: 'plan usage',
                onTap: () => context.go(Routes.professionalFormsGroups),
              ),
              KpiTile(
                label: 'References',
                icon: Icons.book_outlined,
                value: _usage?.resourceUsage['references']?.label ?? '—',
                caption: 'plan usage',
                onTap: () => context.go(Routes.professionalReferences),
              ),
              KpiTile(
                label: 'Lead Forms',
                icon: Icons.list_alt_outlined,
                value: _usage?.resourceUsage['lead_forms']?.label ?? '—',
                caption: 'plan usage',
                onTap: () => context.go(Routes.professionalFormsGroups),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),
          _DashboardTabBar(
            tab: _tab,
            paymentsEnabled: _paymentsEnabled,
            activityCount: _activityActionCount,
            paymentsCount: _paymentsActionCount,
            scheduleCount: _scheduleActionCount,
            onSelect: (tab) => setState(() => _tab = tab),
          ),
          const SizedBox(height: AppSpacing.md),
          ..._tabContent(summary),
        ],
      ),
    );
  }

  List<Widget> _tabContent(ScheduleSummary? summary) {
    return switch (_tab) {
      _DashboardTab.activity => _activityTab(),
      _DashboardTab.payments => _paymentsEnabled
          ? _paymentsTab()
          : [
              const EmptyState(
                compact: false,
                icon: Icons.payments_outlined,
                message: 'Payment tracking is off.\nEnable it from Manage → Payments.',
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
      KpiGrid(
        children: [
          KpiTile(
            label: 'Unread',
            icon: Icons.mark_chat_unread_outlined,
            value: '$_unreadTotal',
            caption: 'messages',
          ),
          KpiTile(
            label: 'Requests',
            icon: Icons.description_outlined,
            value: '${requests.length}',
            caption: 'pending',
            onTap: () => context.go('${Routes.professionalFormsGroups}?tab=requests'),
          ),
          KpiTile(
            label: 'Account',
            icon: Icons.manage_accounts_outlined,
            value: '${_profileEdits.length}',
            caption: 'requests',
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
            leading: AppAvatar(initials: _initialsFor(submission.applicantName), size: 38),
            trailing: const StatusPill(label: 'Review', tone: PillTone.warn),
            onTap: () => context.go('${Routes.professionalFormsGroups}?tab=requests'),
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
            onTap: () => context.go('${Routes.professionalClients}/${row.clientId}'),
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
                        child: Text(activity.clientName, style: context.text.titleSmall),
                      ),
                      StatusPill(
                        label: activity.isDeletion ? 'Deletion' : 'Profile edit',
                        tone: activity.isDeletion ? PillTone.bad : PillTone.info,
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

  List<Widget> _paymentsTab() {
    final actions = _paymentActions?.items ?? const [];

    return [
      KpiGrid(
        children: [
          KpiTile(
            label: 'Awaiting review',
            icon: Icons.rate_review_outlined,
            value: '${_paymentActions?.reviewCount ?? 0}',
            valueColor: context.colors.primary,
          ),
          KpiTile(
            label: 'Overdue',
            icon: Icons.schedule_outlined,
            value: '${_paymentActions?.overdueCount ?? 0}',
            valueColor:
                (_paymentActions?.overdueCount ?? 0) > 0 ? context.colors.error : null,
          ),
        ],
      ),
      if (_paymentsChart != null) ...[
        const SizedBox(height: AppSpacing.md),
        ChartCard(spec: _paymentsChart!, shareContext: 'Payments'),
      ],

      if (_revenueUnlocked) ...[
        SectionHeader(
          title: 'Revenue',
          actionLabel: 'Payments',
          onAction: () => context.go(Routes.professionalPayments),
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final period in const [
              ('7', '7d'),
              ('30', '30d'),
              ('90', '90d'),
              ('lifetime', 'All'),
            ])
              ChoiceChip(
                label: Text(period.$2),
                selected: _revenuePeriod == period.$1,
                onSelected: (_) {
                  setState(() => _revenuePeriod = period.$1);
                  _loadRevenue();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total',
                        style: context.text.bodySmall?.copyWith(color: context.tokens.muted)),
                    Text(
                      _revenue != null
                          ? '${_revenue!.reportingCurrency} ${_revenue!.totalRevenue}'
                          : '—',
                      style: context.text.titleLarge,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('This month',
                      style: context.text.bodySmall?.copyWith(color: context.tokens.muted)),
                  Text(
                    _revenue != null
                        ? '${_revenue!.reportingCurrency} ${_revenue!.thisMonthTotal}'
                        : '—',
                    style: context.text.titleMedium,
                  ),
                ],
              ),
            ],
          ),
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
      KpiGrid(
        children: [
          KpiTile(
            label: 'Overdue',
            value: '${summary?.overdue ?? 0}',
            valueColor: (summary?.overdue ?? 0) > 0 ? context.colors.error : null,
          ),
          KpiTile(
            label: 'Due 24h',
            value: '${summary?.due24Hours ?? 0}',
            valueColor: context.colors.primary,
          ),
          KpiTile(label: 'Due 7 days', value: '${summary?.due7Days ?? 0}'),
          KpiTile(
            label: 'Done (7d)',
            value: '${summary?.completedLast7Days ?? 0}',
            valueColor: context.tokens.success,
          ),
        ],
      ),
      if (_priorityChart != null) ...[
        const SizedBox(height: AppSpacing.md),
        ChartCard(spec: _priorityChart!, shareContext: 'Schedules'),
      ],
      if (_statusChart != null) ChartCard(spec: _statusChart!, shareContext: 'Schedules'),

      if (overdue.isNotEmpty) ...[
        SectionHeader(title: 'Overdue schedules (${overdue.length})'),
        for (final reminder in overdue)
          _scheduleRow(reminder, overdue: true),
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
      onTap: () => context.go('${Routes.professionalClients}/${reminder.client}'),
    );
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    final letters =
        parts.map((p) => p[0]).take(2).join().toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  /// "15 Jul" — the `date: 'dd MMM'` pipe in the Ionic template.
  String _shortDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    final tokens = context.tokens;

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: index == tabs.length - 1 ? 0 : AppSpacing.sm,
                ),
                child: InkWell(
                  onTap: () => onSelect(tabs[index].$1),
                  borderRadius: AppRadius.mdAll,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tab == tabs[index].$1
                          ? context.colors.primary
                          : context.colors.surface,
                      border: Border.all(
                        color: tab == tabs[index].$1
                            ? context.colors.primary
                            : tokens.border,
                      ),
                      borderRadius: AppRadius.mdAll,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            tabs[index].$2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.labelMedium?.copyWith(
                              color: tab == tabs[index].$1
                                  ? context.colors.onPrimary
                                  : tokens.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (tabs[index].$3 > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            tabs[index].$3 > 99 ? '99+' : '${tabs[index].$3}',
                            style: context.text.labelSmall?.copyWith(
                              color: tab == tabs[index].$1
                                  ? context.colors.onPrimary
                                  : context.colors.error,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name, required this.initials, this.profile});

  final String name;
  final String initials;
  final ProfessionalProfile? profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome back,', style: context.text.bodySmall),
              const SizedBox(height: 2),
              Text(
                '$name 👋',
                style: context.text.displaySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        AppAvatar(
          initials: initials.isEmpty ? 'T' : initials,
          imageUrl: Env.mediaUrl(profile?.profilePhotoUrl ?? ''),
          size: 46,
        ),
      ],
    );
  }
}
