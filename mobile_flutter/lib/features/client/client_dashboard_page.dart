import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/charts/graph_engine.dart';
import '../../shared/widgets/app_widgets.dart';
import '../professional/professional_format.dart';

/// Client dashboard — greeting, consistency KPIs, stat cards, and what's due.
/// Replica of mobile/src/app/pages/client/dashboard/client-dashboard.page.ts.
class ClientDashboardPage extends ConsumerStatefulWidget {
  const ClientDashboardPage({super.key});

  @override
  ConsumerState<ClientDashboardPage> createState() =>
      _ClientDashboardPageState();
}

class _ClientDashboardPageState extends ConsumerState<ClientDashboardPage> {
  ClientDashboardResponse? _data;
  ClientMeResponse? _me;
  List<TrackingTemplateRecord> _templates = [];
  List<TrackingEntryRecord> _entries = [];
  List<ChartSpec> _statCards = [];
  String _message = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String get _initials {
    final client = _me?.client;
    final first = client?.firstName ?? '';
    final last = client?.lastName ?? '';
    final letters =
        '${first.isNotEmpty ? first[0] : ''}${last.isNotEmpty ? last[0] : ''}'
            .toUpperCase();
    return letters.isEmpty ? 'C' : letters;
  }

  List<ClientReminder> get _upcoming => _data?.schedules ?? const [];

  /// Anything dated today or earlier that is not done.
  List<ClientReminder> get _dueToday {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return _upcoming
        .where((item) => item.date.compareTo(today) <= 0 && !item.isDone)
        .toList();
  }

  Future<void> _load() async {
    final api = ref.read(clientApiProvider);

    await Future.wait([
      () async {
        try {
          final me = await api.getMe();
          if (mounted) setState(() => _me = me);
        } catch (_) {
          if (mounted) setState(() => _me = null);
        }
      }(),
      () async {
        try {
          final data = await api.getDashboard();
          if (!mounted) return;
          setState(() {
            _data = data;
            _message = '';
          });
        } catch (_) {
          if (mounted) {
            setState(() =>
                _message = 'Could not load your dashboard. Pull to retry.');
          }
        }
      }(),
      () async {
        try {
          final templates = await api.getTemplates();
          if (mounted) setState(() => _templates = templates);
        } catch (_) {
          if (mounted) setState(() => _templates = []);
        }
      }(),
      () async {
        try {
          final entries = await api.getEntries();
          if (mounted) setState(() => _entries = entries);
        } catch (_) {
          if (mounted) setState(() => _entries = []);
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
    _buildStats();
  }

  /// KPI cards across every template that has entries, capped at 3.
  void _buildStats() {
    if (_templates.isEmpty || _entries.isEmpty) {
      setState(() => _statCards = []);
      return;
    }

    final cards = <ChartSpec>[];
    for (final template in _templates) {
      final templateEntries = _entries
          .where((entry) => entry.template == template.id)
          .map((e) => e.toEntryLike())
          .toList();
      if (templateEntries.isEmpty) continue;
      cards.addAll(buildOverviewCards(
        template.fields.map((f) => f.toFieldLike()).toList(),
        templateEntries,
      ));
    }
    setState(() => _statCards = cards.take(3).toList());
  }

  @override
  Widget build(BuildContext context) {
    final summary = _data?.summary;
    final tokens = context.tokens;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const PagePad(
          children: [SkeletonBox(height: 56), SkeletonBox(height: 150), SkeletonBox(height: 150)],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: PagePad(
        onRefresh: _load,
        children: [
          AppCard(
            color: tokens.primarySoft,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting, style: context.text.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        _me?.client.displayName.isNotEmpty ?? false
                            ? _me!.client.displayName
                            : 'Welcome',
                        style: context.text.displaySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_me?.client.professionalName.isNotEmpty ?? false)
                        Text(
                          'Coached by ${_me!.client.professionalName}',
                          style: context.text.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                AppAvatar(
                  initials: _initials,
                  imageUrl: Env.mediaUrl(_me?.client.photo ?? ''),
                  size: 46,
                ),
              ],
            ),
          ),

          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],

          if (_dueToday.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              color: context.colors.primary.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: context.colors.primary, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${_dueToday.length} ${_dueToday.length == 1 ? 'item is' : 'items are'} due today',
                      style: context.text.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SectionHeader(title: 'Your consistency', topSpace: AppSpacing.lg),
          KpiGrid(
            children: [
              KpiTile(
                label: 'Streak',
                icon: Icons.local_fire_department_outlined,
                iconColor: tokens.accent,
                value: '${summary?.currentStreak ?? 0}',
                caption: 'days in a row',
                valueColor: (summary?.currentStreak ?? 0) > 0 ? tokens.accent : null,
              ),
              KpiTile(
                label: 'Consistency',
                icon: Icons.percent_outlined,
                iconColor: context.colors.primary,
                value: '${summary?.consistencyPercent ?? 0}%',
                caption: 'last 30 days',
              ),
              KpiTile(
                label: 'Entries',
                icon: Icons.edit_note_outlined,
                iconColor: tokens.success,
                value: '${summary?.totalEntries ?? 0}',
                caption: '${summary?.entriesThisWeek ?? 0} this week',
              ),
              KpiTile(
                label: 'Active days',
                icon: Icons.calendar_today_outlined,
                iconColor: tokens.primaryStrong,
                value: '${summary?.activeDaysLast30 ?? 0}',
                caption: 'of last 30',
              ),
            ],
          ),

          if (_statCards.isNotEmpty) ...[
            SectionHeader(
              title: 'Your progress',
              actionLabel: 'See all',
              onAction: () => context.go(Routes.clientPrograms),
            ),
            for (final card in _statCards)
              ChartCard(spec: card, shareContext: 'My progress'),
          ],

          SectionHeader(
            title: 'Coming up',
            actionLabel: 'Programs',
            onAction: () => context.go(Routes.clientPrograms),
          ),
          if (_upcoming.isEmpty)
            const EmptyState(message: 'Nothing scheduled right now.')
          else
            for (final item in _upcoming.take(5))
              RowItem(
                title: item.title,
                subtitle: [
                  weekdayDate(item.date),
                  if (item.time.isNotEmpty) hhmm(item.time),
                ].join(' · '),
                trailing: item.isDone
                    ? const StatusPill(label: 'Done', tone: PillTone.good)
                    : (item.date.compareTo(_todayIso()) <= 0
                        ? const StatusPill(label: 'Due', tone: PillTone.warn)
                        : null),
              ),

          const SectionHeader(title: 'Your templates'),
          if (_templates.isEmpty)
            const EmptyState(message: 'Your professional has not assigned any yet.')
          else
            for (final template in _templates.take(4))
              RowItem(
                title: template.name,
                subtitle:
                    '${TemplateCadence.label(template.cadence)} · ${template.fields.length} fields',
                leading: Container(
                  width: 5,
                  height: 34,
                  decoration: BoxDecoration(
                    color: parseAccentColor(template.accent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onTap: () => context.go(Routes.clientPrograms),
              ),
        ],
      ),
    );
  }

  String _todayIso() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
