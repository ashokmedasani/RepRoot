import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/templates_api.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/widgets/app_widgets.dart';

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
  List<TrackingTemplateRecord> _templates = [];
  ProfessionalProfile? _profile;
  ProfessionalDataUsage? _usage;

  String _message = '';
  bool _loading = true;
  int _clientCount = 0;
  int _activeClientCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
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

  double get _usagePercent {
    final percent = _usage?.usagePercent ?? 0;
    return (percent * 10).round() / 10;
  }

  /// Each call is independent so one failing endpoint cannot blank the whole
  /// dashboard — same tolerance as the Ionic page, which subscribes separately.
  Future<void> _load() async {
    final professionalAuth = ref.read(professionalAuthApiProvider);
    final formsGroups = ref.read(formsGroupsApiProvider);
    final templatesApi = ref.read(templatesApiProvider);

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
        final response = await templatesApi.getTemplates();
        if (mounted) setState(() => _templates = response.templates);
      }, onError: () {
        if (mounted) setState(() => _templates = []);
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
            actionLabel: 'This week',
            onAction: () => context.go(Routes.professionalSchedule),
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
                label: 'Schedules',
                icon: Icons.calendar_today_outlined,
                value: '${summary?.totalPending ?? 0}',
                caption: '${summary?.due24Hours ?? 0} due in 24h',
                onTap: () => context.go(Routes.professionalSchedule),
              ),
              KpiTile(
                label: 'Forms',
                icon: Icons.description_outlined,
                value: '${_overview?.pendingForms.length ?? 0}',
                caption: 'pending review',
                onTap: () => context.go(Routes.professionalFormsGroups),
              ),
              KpiTile(
                label: 'Storage',
                icon: Icons.storage_outlined,
                value: '$_usagePercent%',
                caption: 'of ${_usage?.planName.isNotEmpty ?? false ? _usage!.planName : 'your'} plan',
              ),
            ],
          ),

          const SectionHeader(title: 'Client Tracking Center'),
          KpiGrid(
            children: [
              KpiTile(
                label: 'Overdue',
                value: '${summary?.overdue ?? 0}',
                valueColor:
                    (summary?.overdue ?? 0) > 0 ? context.colors.error : null,
              ),
              KpiTile(
                label: 'Due 24 hours',
                value: '${summary?.due24Hours ?? 0}',
                valueColor: context.colors.primary,
              ),
              KpiTile(label: 'Due 7 days', value: '${summary?.due7Days ?? 0}'),
              KpiTile(
                label: 'Profile edits',
                value: '${summary?.pendingProfileEdits ?? 0}',
              ),
            ],
          ),

          if (_priorityChart != null) ...[
            const SizedBox(height: AppSpacing.md),
            ChartCard(spec: _priorityChart!, shareContext: 'Client Tracking Center'),
          ],
          if (_statusChart != null)
            ChartCard(spec: _statusChart!, shareContext: 'Client Tracking Center'),

          SectionHeader(
            title: 'Upcoming Schedule',
            actionLabel: 'View all',
            onAction: () => context.go(Routes.professionalSchedule),
          ),
          if (_reminders.isEmpty)
            const EmptyState(message: 'No pending schedules.')
          else
            for (final reminder in _reminders.take(5))
              RowItem(
                title: reminder.title,
                subtitle: reminder.clientName,
                trailingValue: _shortDate(reminder.date),
                trailingCaption: reminder.time.isNotEmpty
                    ? reminder.time.substring(0, 5)
                    : 'Any time',
                onTap: () => context.go(
                  '${Routes.professionalClients}/${reminder.client}',
                ),
              ),

          const SectionHeader(title: 'Recent Activity'),
          if (_profileEdits.isEmpty)
            const EmptyState(message: 'No client requests waiting.')
          else
            for (final activity in _profileEdits.take(5))
              RowItem(
                title: activity.clientName,
                subtitle: activity.isDeletion
                    ? 'Requested account deletion'
                    : '${activity.proposedFieldCount} profile field(s) changed',
                trailing: StatusPill(
                  label: 'Review',
                  tone: activity.isDeletion ? PillTone.bad : PillTone.info,
                ),
                onTap: () => context.go(
                  '${Routes.professionalClients}/${activity.client}',
                ),
              ),

          SectionHeader(
            title: 'Templates',
            actionLabel: 'Manage',
            onAction: () => context.go(Routes.professionalTemplates),
          ),
          if (_templates.isEmpty)
            const EmptyState(message: 'No templates yet.')
          else
            for (final template in _templates.take(4))
              RowItem(
                title: template.name,
                subtitle:
                    '${TemplateCadence.label(template.cadence)} · ${template.fields.length} fields',
                trailingValue: '${template.assignedCount}',
                trailingCaption: 'clients',
              ),

          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => context.go(Routes.professionalClients),
            child: const Text('Open Clients'),
          ),
        ],
      ),
    );
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
