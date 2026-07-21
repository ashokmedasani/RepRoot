import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/client_api.dart';
import '../../core/api/models/template_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/charts/graph_engine.dart';
import '../../shared/widgets/app_widgets.dart';
import '../professional/professional_format.dart';

enum ProgressTab { overview, charts, history }

/// One template's charts and numeric stats.
class TemplateChartGroup {
  const TemplateChartGroup({
    required this.template,
    required this.charts,
    required this.stats,
  });

  final TrackingTemplateRecord template;
  final List<ChartSpec> charts;
  final List<NumericFieldStat> stats;
}

/// Full progress detail — quick stats, the charts the engine decides per
/// template, and entry history. Embedded as the Progress segment of the
/// Programs tab (no Scaffold/AppBar of its own — it isn't routed to directly).
/// Replica of mobile/src/app/pages/client/progress/client-progress.page.ts.
class ClientProgressSection extends ConsumerStatefulWidget {
  const ClientProgressSection({super.key});

  @override
  ConsumerState<ClientProgressSection> createState() =>
      _ClientProgressSectionState();
}

class _ClientProgressSectionState extends ConsumerState<ClientProgressSection> {
  ProgressTab _tab = ProgressTab.overview;
  int _range = DateRange.month;
  List<TrackingTemplateRecord> _templates = [];
  List<TrackingEntryRecord> _entries = [];
  List<TemplateChartGroup> _chartGroups = [];
  List<NumericFieldStat> _quickStats = [];
  int _historyTemplateId = 0;
  String _message = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Newest first, capped at 40, optionally filtered to one template.
  List<TrackingEntryRecord> get _historyEntries {
    final filtered = _historyTemplateId > 0
        ? _entries.where((e) => e.template == _historyTemplateId).toList()
        : [..._entries];
    filtered.sort((a, b) =>
        '${b.entryDate} ${b.entryTime}'.compareTo('${a.entryDate} ${a.entryTime}'));
    return filtered.take(40).toList();
  }

  Future<void> _load() async {
    final api = ref.read(clientApiProvider);
    try {
      final templates = await api.getTemplates();
      if (mounted) setState(() => _templates = templates);
    } catch (_) {
      if (mounted) setState(() => _templates = []);
    }
    try {
      final entries = await api.getEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _message = '';
      });
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not load your progress.');
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _rebuild();
  }

  void _rebuild() {
    final groups = <TemplateChartGroup>[];
    final stats = <NumericFieldStat>[];

    for (final template in _templates) {
      final templateEntries = _entries
          .where((entry) => entry.template == template.id)
          .map((e) => e.toEntryLike())
          .toList();
      if (templateEntries.isEmpty) continue;

      final fields = template.fields.map((f) => f.toFieldLike()).toList();
      final charts = buildFieldCharts(fields, templateEntries, _range);
      final templateStats = numericFieldStats(fields, templateEntries)
          .where((stat) => stat.hasData)
          .toList();
      stats.addAll(templateStats);

      if (charts.isNotEmpty) {
        groups.add(TemplateChartGroup(
          template: template,
          charts: charts,
          stats: templateStats,
        ));
      }
    }

    setState(() {
      _chartGroups = groups;
      _quickStats = stats;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PagePad(
        children: [SkeletonBox(height: 44), SkeletonBox(height: 180)],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screen,
            AppSpacing.sm,
            AppSpacing.screen,
            AppSpacing.sm,
          ),
          child: SegmentedButton<ProgressTab>(
            segments: const [
              ButtonSegment(value: ProgressTab.overview, label: Text('Overview')),
              ButtonSegment(value: ProgressTab.charts, label: Text('Charts')),
              ButtonSegment(value: ProgressTab.history, label: Text('History')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
            style: SegmentedButton.styleFrom(
              textStyle: context.text.labelMedium,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            ProgressTab.overview => _overviewTab(),
            ProgressTab.charts => _chartsTab(),
            ProgressTab.history => _historyTab(),
          },
        ),
      ],
    );
  }

  Widget _overviewTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),
        if (_quickStats.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.insights_outlined,
            message: 'Log some entries and your numbers will show up here.',
          )
        else
          for (final stat in _quickStats)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stat.label, style: context.text.titleSmall),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        _statCell('Latest', stat.latest, stat.unit),
                        _statCell('Average', stat.average, stat.unit),
                        _statCell('Min', stat.min, stat.unit),
                        _statCell('Max', stat.max, stat.unit),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text('${stat.count} entries', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _statCell(String label, double value, String unit) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.text.labelSmall?.copyWith(color: context.tokens.muted),
          ),
          const SizedBox(height: 2),
          Text(
            '${trimNumber(value)}${unit.isNotEmpty ? ' $unit' : ''}',
            style: context.text.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _chartsTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: DateRange.week, label: Text('7d')),
            ButtonSegment(value: DateRange.month, label: Text('30d')),
            ButtonSegment(value: DateRange.quarter, label: Text('90d')),
            ButtonSegment(value: DateRange.all, label: Text('All')),
          ],
          selected: {_range},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            setState(() => _range = s.first);
            _rebuild();
          },
          style: SegmentedButton.styleFrom(
            textStyle: context.text.labelMedium,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_chartGroups.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.show_chart,
            message: 'No chartable data in this range yet.',
          )
        else
          for (final group in _chartGroups) ...[
            SectionHeader(title: group.template.name, topSpace: AppSpacing.md),
            for (final chart in group.charts)
              ChartCard(spec: chart, shareContext: 'My ${group.template.name}'),
          ],
      ],
    );
  }

  Widget _historyTab() {
    final entries = _historyEntries;

    return PagePad(
      onRefresh: _load,
      children: [
        if (_templates.length > 1) ...[
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _historyTemplateId == 0,
                    onSelected: (_) => setState(() => _historyTemplateId = 0),
                  ),
                ),
                for (final template in _templates)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(template.name),
                      selected: _historyTemplateId == template.id,
                      onSelected: (_) =>
                          setState(() => _historyTemplateId = template.id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (entries.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.history,
            message: 'No entries logged yet.',
          )
        else
          for (final entry in entries)
            RowItem(
              title: entry.templateName.isEmpty
                  ? shortDate(entry.entryDate)
                  : entry.templateName,
              subtitle: [
                shortDate(entry.entryDate),
                if (entry.entryTime.isNotEmpty) hhmm(entry.entryTime),
                if (entry.note.isNotEmpty) entry.note,
              ].join(' · '),
              trailing: entry.editedByProfessional
                  ? const StatusPill(label: 'Edited', tone: PillTone.info)
                  : null,
            ),
      ],
    );
  }
}
