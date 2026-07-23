import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/charts/analytics_types.dart';
import '../../shared/charts/chart_card.dart';
import '../../shared/charts/graph_engine.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Template analytics for one client: KPI cards, the charts the graph engine
/// decides, an entry logger, and the recent entry list.
/// Replica of mobile/src/app/pages/professional/client-template/client-template.page.ts.
class ProfessionalClientTemplatePage extends ConsumerStatefulWidget {
  const ProfessionalClientTemplatePage({
    super.key,
    required this.clientId,
    required this.assignmentId,
  });

  final int clientId;
  final int assignmentId;

  @override
  ConsumerState<ProfessionalClientTemplatePage> createState() =>
      _ProfessionalClientTemplatePageState();
}

class _ProfessionalClientTemplatePageState
    extends ConsumerState<ProfessionalClientTemplatePage> {
  String _clientName = '';
  TemplateAssignmentRecord? _assignment;
  TrackingTemplateRecord? _template;
  List<TrackingEntryRecord> _entries = [];
  List<ChartSpec> _charts = [];
  List<ChartSpec> _overviewCards = [];
  int _range = DateRange.month;
  String _message = '';
  bool _loading = true;

  bool _showEntryForm = false;
  bool _isSavingEntry = false;
  DateTime _entryDate = DateTime.now();
  final Map<String, String> _entryAnswers = {};
  final _entryNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entryNote.dispose();
    super.dispose();
  }

  String get _shareContext =>
      '${_clientName.isEmpty ? 'Client' : _clientName} · ${_template?.name ?? ''}'
          .trim();

  /// Entries for this assignment's template only — getClientEntries returns
  /// every template's entries for the client.
  List<TrackingEntryRecord> _templateEntries() {
    final templateId = _assignment?.templateId ?? _template?.id;
    if (templateId == null) return _entries;
    return _entries.where((entry) => entry.template == templateId).toList();
  }

  /// Newest first, capped at 25, as in the TS.
  List<TrackingEntryRecord> get _visibleEntries {
    final ordered = _templateEntries().toList()
      ..sort((a, b) {
        final left = '${a.entryDate} ${a.entryTime.isEmpty ? '00:00' : a.entryTime}';
        final right = '${b.entryDate} ${b.entryTime.isEmpty ? '00:00' : b.entryTime}';
        return right.compareTo(left);
      });
    return ordered.take(25).toList();
  }

  void _rebuild() {
    final template = _template;
    if (template == null) {
      setState(() {
        _charts = [];
        _overviewCards = [];
      });
      return;
    }
    final fields = template.fields.map((f) => f.toFieldLike()).toList();
    final entries = _templateEntries().map((e) => e.toEntryLike()).toList();
    setState(() {
      _charts = buildFieldCharts(fields, entries, _range);
      _overviewCards = buildOverviewCards(fields, entries).take(4).toList();
    });
  }

  Future<void> _load() async {
    final formsGroups = ref.read(formsGroupsApiProvider);
    final templatesApi = ref.read(templatesApiProvider);

    await Future.wait([
      () async {
        try {
          final detail = await formsGroups.getClientProfile(widget.clientId);
          if (mounted) setState(() => _clientName = detail.client.displayName);
        } catch (_) {/* the header just falls back to 'Client' */}
      }(),
      () async {
        try {
          final assignments = await templatesApi.getAssignments(widget.clientId);
          final assignment = assignments
              .where((item) => item.id == widget.assignmentId)
              .firstOrNull;
          if (!mounted) return;
          if (assignment == null) {
            setState(() => _message = 'Assignment not found.');
            return;
          }
          setState(() => _assignment = assignment);
          final template = await templatesApi.getTemplate(assignment.templateId);
          if (mounted) setState(() => _template = template);
        } catch (_) {
          if (mounted) setState(() => _message = 'Could not load the template.');
        }
      }(),
      () async {
        try {
          final entries = await templatesApi.getClientEntries(widget.clientId);
          if (mounted) setState(() => _entries = entries);
        } catch (_) {
          if (mounted) setState(() => _entries = []);
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
    _rebuild();
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _saveEntry() async {
    final template = _template;
    if (template == null) return;

    setState(() => _isSavingEntry = true);
    // Blank answers are dropped rather than sent empty — the engine skips them
    // anyway, and an empty string is not an answer.
    final answers = <String, String>{
      for (final entry in _entryAnswers.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };

    try {
      final saved = await ref.read(templatesApiProvider).createClientEntry(
            widget.clientId,
            templateId: template.id,
            entryDate: _isoDate(_entryDate),
            answers: answers,
            note: _entryNote.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, saved];
        _entryAnswers.clear();
        _entryNote.clear();
        _showEntryForm = false;
        _isSavingEntry = false;
      });
      _rebuild();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSavingEntry = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _unassign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unassign template?'),
        content: const Text(
          'The client will no longer see this template. Past entries stay saved.',
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => context.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
            child: const Text('Unassign'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(templatesApiProvider)
          .unassignTemplate(widget.clientId, widget.assignmentId);
      if (mounted) context.go('${Routes.professionalClients}/${widget.clientId}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not unassign.')));
      }
    }
  }

  String _entrySummary(TrackingEntryRecord entry) {
    final parts = entry.answers.entries
        .take(3)
        .map((e) => '${e.key.replaceAll('_', ' ')}: ${e.value}')
        .join(' · ');
    if (parts.isNotEmpty) return parts;
    return entry.note.isNotEmpty ? entry.note : '—';
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;

    return Scaffold(
      appBar: AppBar(
        title: Text(template?.name ?? 'Template'),
        leading: BackButton(
          onPressed: () => context.go('${Routes.professionalClients}/${widget.clientId}'),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showEntryForm = !_showEntryForm),
            icon: Icon(_showEntryForm ? Icons.close : Icons.add),
            tooltip: _showEntryForm ? 'Close' : 'Log entry',
          ),
          IconButton(
            onPressed: _unassign,
            icon: const Icon(Icons.link_off),
            tooltip: 'Unassign',
          ),
        ],
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 60), SkeletonBox(height: 200)],
            )
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty)
                  ErrorNote(message: _message, onRetry: _load),

                if (_clientName.isNotEmpty || template != null)
                  Text(
                    [
                      if (_clientName.isNotEmpty) _clientName,
                      if (template != null) TemplateCadence.label(template.cadence),
                      '${_templateEntries().length} entries',
                    ].join(' · '),
                    style: context.text.bodySmall,
                  ),

                if (_showEntryForm && template != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _entryForm(template),
                ],

                const SectionHeader(title: 'Range'),
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

                if (_overviewCards.isNotEmpty) ...[
                  const SectionHeader(title: 'Overview'),
                  for (final card in _overviewCards)
                    ChartCard(spec: card, shareContext: _shareContext),
                ],

                const SectionHeader(title: 'Charts'),
                if (_charts.isEmpty)
                  const EmptyState(
                    compact: false,
                    icon: Icons.insights_outlined,
                    message: 'No chartable data in this range yet.',
                  )
                else
                  for (final chart in _charts)
                    ChartCard(spec: chart, shareContext: _shareContext),

                SectionHeader(title: 'Recent entries (${_visibleEntries.length})'),
                if (_visibleEntries.isEmpty)
                  const EmptyState(message: 'No entries logged yet.')
                else
                  for (final entry in _visibleEntries)
                    RowItem(
                      title: shortDate(entry.entryDate),
                      subtitle: _entrySummary(entry),
                      trailing: entry.editedByProfessional
                          ? const StatusPill(label: 'Edited', tone: PillTone.info)
                          : null,
                    ),
              ],
            ),
    );
  }

  Widget _entryForm(TrackingTemplateRecord template) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Log an entry', style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _entryDate,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now,
              );
              if (picked != null) setState(() => _entryDate = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: AppSize.iconRow),
            label: Text(shortDate(_isoDate(_entryDate))),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final field in template.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _answerField(field),
            ),
          TextField(
            controller: _entryNote,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _isSavingEntry ? null : _saveEntry,
            child: Text(_isSavingEntry ? 'Saving…' : 'Save entry'),
          ),
        ],
      ),
    );
  }

  /// One input per field type — the professional logs on the client's behalf.
  Widget _answerField(TemplateField field) {
    final key = field.answerKey;
    final value = _entryAnswers[key] ?? '';

    switch (field.fieldType) {
      case TemplateFieldType.yesNo:
        return Row(
          children: [
            Expanded(child: Text(field.label, style: context.text.bodyMedium)),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'yes', label: Text('Yes')),
                ButtonSegment(value: 'no', label: Text('No')),
              ],
              selected: {value.isEmpty ? 'no' : value},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  setState(() => _entryAnswers[key] = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: context.text.labelSmall,
              ),
            ),
          ],
        );

      case TemplateFieldType.dropdown:
        return DropdownButtonFormField<String>(
          initialValue: field.options.contains(value) ? value : null,
          decoration: InputDecoration(labelText: field.label),
          items: field.options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setState(() => _entryAnswers[key] = v ?? ''),
        );

      case TemplateFieldType.rating:
        final scale = (field.scale == null || field.scale == 0) ? 5 : field.scale!;
        final clamped = scale.clamp(2, 10);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: context.text.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (var i = 1; i <= clamped; i++)
                  ChoiceChip(
                    label: Text('$i'),
                    selected: value == '$i',
                    onSelected: (_) => setState(() => _entryAnswers[key] = '$i'),
                  ),
              ],
            ),
          ],
        );

      case TemplateFieldType.number:
        return TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _entryAnswers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );

      case TemplateFieldType.longText:
        return TextField(
          maxLines: 3,
          onChanged: (v) => _entryAnswers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );

      default:
        return TextField(
          onChanged: (v) => _entryAnswers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );
    }
  }
}
