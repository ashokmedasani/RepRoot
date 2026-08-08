import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/resources_api.dart';
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
/// The four internal sections of an assigned template. Previously all of
/// this was one scroll — range picker, overview cards, charts, entry list,
/// then progress records — which meant reading a client's latest entry
/// required scrolling past every chart on the page.
enum _TemplateTab { overview, resources, progress, entries }

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
  _TemplateTab _tab = _TemplateTab.overview;
  String _message = '';
  bool _loading = true;

  bool _showEntryForm = false;
  bool _isSavingEntry = false;

  /// Non-null while the entry form is correcting an existing entry rather than
  /// logging a new one; drives PUT-vs-POST in [_saveEntry].
  int? _editingEntryId;
  DateTime _entryDate = DateTime.now();
  final Map<String, String> _entryAnswers = {};
  final _entryNote = TextEditingController();

  /// Progress Records — professional-written notes, client-wide (not scoped
  /// to this one template), same as the website's per-template Progress tab.
  List<ProgressEntry> _progress = [];
  bool _isProgressFormOpen = false;
  bool _isSavingProgress = false;
  int? _editingProgressId;
  DateTime _progressDate = DateTime.now();
  final _progressTitle = TextEditingController();
  final _progressStatus = TextEditingController();
  final _progressNotes = TextEditingController();
  final _progressNextStep = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entryNote.dispose();
    _progressTitle.dispose();
    _progressStatus.dispose();
    _progressNotes.dispose();
    _progressNextStep.dispose();
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
      () async {
        try {
          final progress = await formsGroups.getClientProgress(widget.clientId);
          if (mounted) setState(() => _progress = progress);
        } catch (_) {
          if (mounted) setState(() => _progress = []);
        }
      }(),
    ]);

    if (!mounted) return;
    setState(() => _loading = false);
    _rebuild();
  }


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

    final editingId = _editingEntryId;
    try {
      final api = ref.read(templatesApiProvider);
      if (editingId != null) {
        final saved = await api.updateEntry(
          editingId,
          answers: answers,
          note: _entryNote.text.trim(),
          entryDate: isoDate(_entryDate),
        );
        if (!mounted) return;
        setState(() {
          _entries = [
            for (final entry in _entries) entry.id == editingId ? saved : entry,
          ];
          _resetEntryForm();
        });
      } else {
        final saved = await api.createClientEntry(
          widget.clientId,
          templateId: template.id,
          entryDate: isoDate(_entryDate),
          answers: answers,
          note: _entryNote.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _entries = [..._entries, saved];
          _resetEntryForm();
        });
      }
      _rebuild();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSavingEntry = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Clears the entry form back to "new entry" state. Call inside a setState.
  void _resetEntryForm() {
    _entryAnswers.clear();
    _entryNote.clear();
    _entryDate = DateTime.now();
    _editingEntryId = null;
    _showEntryForm = false;
    _isSavingEntry = false;
  }

  /// Picks which of the professional's resources this client can see for this
  /// assignment — the mobile equivalent of the web's share dialog.
  ///
  /// The library is fetched on open rather than with the page: most visits
  /// never touch it, and it is the one call here that scales with the whole
  /// resource library rather than with this client.
  Future<void> _editSharedReferences() async {
    final assignment = _assignment;
    if (assignment == null) return;

    List<ProfessionalResourceRecord> library;
    try {
      library = (await ref.read(resourcesApiProvider).getResources()).resources;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load your resource library.')),
      );
      return;
    }
    if (!mounted) return;

    if (library.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add resources to your library first, then share them here.'),
        ),
      );
      return;
    }

    final selected = assignment.resources.map((r) => r.id).toSet();
    final saved = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.screen,
                  AppSpacing.screen,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shared resources', style: context.text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'The client sees these alongside this template.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final resource in library)
                      CheckboxListTile(
                        dense: true,
                        value: selected.contains(resource.id),
                        onChanged: (checked) => setSheetState(() {
                          if (checked ?? false) {
                            selected.add(resource.id);
                          } else {
                            selected.remove(resource.id);
                          }
                        }),
                        title: Text(resource.title),
                        subtitle: Text(
                          resource.categoryName.isNotEmpty
                              ? resource.categoryName
                              : resource.resourceType,
                          style: context.text.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.screen),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => sheetContext.pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => sheetContext.pop(selected),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == null || !mounted) return;
    try {
      final updated = await ref
          .read(templatesApiProvider)
          .updateAssignmentReferences(
            widget.clientId,
            assignment.id,
            saved.toList(),
          );
      if (!mounted) return;
      setState(() => _assignment = updated);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Loads an existing entry back into the form for correction — the mobile
  /// equivalent of the web's `startEntryEdit`. Without this a mistyped entry
  /// could only be fixed from a desktop browser.
  void _startEntryEdit(TrackingEntryRecord entry) {
    setState(() {
      _editingEntryId = entry.id;
      _entryAnswers
        ..clear()
        ..addAll(entry.answers);
      _entryNote.text = entry.note;
      _entryDate = DateTime.tryParse(entry.entryDate) ?? DateTime.now();
      _showEntryForm = true;
    });
  }

  // ----- Progress Records -----

  void _openProgressForm() {
    setState(() {
      _editingProgressId = null;
      _progressTitle.clear();
      _progressStatus.clear();
      _progressNotes.clear();
      _progressNextStep.clear();
      _progressDate = DateTime.now();
      _isProgressFormOpen = true;
    });
  }

  void _editProgress(ProgressEntry entry) {
    setState(() {
      _editingProgressId = entry.id;
      _progressTitle.text = entry.title;
      _progressStatus.text = entry.status;
      _progressNotes.text = entry.notes;
      _progressNextStep.text = entry.nextStep;
      _progressDate = DateTime.tryParse(entry.date) ?? DateTime.now();
      _isProgressFormOpen = true;
    });
  }

  void _cancelProgress() {
    setState(() {
      _isProgressFormOpen = false;
      _editingProgressId = null;
    });
  }

  Future<void> _saveProgress() async {
    if (_progressTitle.text.trim().isEmpty || _isSavingProgress) return;
    setState(() => _isSavingProgress = true);
    final formsGroups = ref.read(formsGroupsApiProvider);
    final editingId = _editingProgressId;
    try {
      if (editingId != null) {
        await formsGroups.updateProgress(
          editingId,
          title: _progressTitle.text.trim(),
          date: isoDate(_progressDate),
          notes: _progressNotes.text.trim(),
          status: _progressStatus.text.trim(),
          nextStep: _progressNextStep.text.trim(),
        );
      } else {
        await formsGroups.createProgress(
          widget.clientId,
          title: _progressTitle.text.trim(),
          date: isoDate(_progressDate),
          notes: _progressNotes.text.trim(),
          status: _progressStatus.text.trim(),
          nextStep: _progressNextStep.text.trim(),
        );
      }
      if (!mounted) return;
      final progress = await formsGroups.getClientProgress(widget.clientId);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _isSavingProgress = false;
        _isProgressFormOpen = false;
        _editingProgressId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingProgress = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          error is ApiException ? error.message : 'Progress record could not be saved.',
        ),
      ));
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
            // Also switches to Entries — the form renders there, so toggling
            // it from another tab used to do nothing visible.
            // Closing drops any in-progress edit, so reopening starts a new
            // entry rather than silently resuming the old one.
            onPressed: () => setState(() {
              if (_showEntryForm) {
                _resetEntryForm();
              } else {
                _showEntryForm = true;
                _tab = _TemplateTab.entries;
              }
            }),
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screen,
                    AppSpacing.sm,
                    AppSpacing.screen,
                    AppSpacing.sm,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<_TemplateTab>(
                      segments: const [
                        ButtonSegment(
                          value: _TemplateTab.overview,
                          label: Text('Overview', maxLines: 1),
                        ),
                        ButtonSegment(
                          value: _TemplateTab.resources,
                          label: Text('Resources', maxLines: 1),
                        ),
                        ButtonSegment(
                          value: _TemplateTab.progress,
                          label: Text('Progress', maxLines: 1),
                        ),
                        ButtonSegment(
                          value: _TemplateTab.entries,
                          label: Text('Entries', maxLines: 1),
                        ),
                      ],
                      selected: {_tab},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _tab = s.first),
                    ),
                  ),
                ),
                Expanded(
                  child: switch (_tab) {
                    _TemplateTab.overview => _overviewTab(template),
                    _TemplateTab.resources => _resourcesTab(),
                    _TemplateTab.progress => _progressTab(),
                    _TemplateTab.entries => _entriesTab(template),
                  },
                ),
              ],
            ),
    );
  }

  /// Overview — the summary line, the range picker that scopes it, the KPI
  /// cards, and the charts. Everything here answers "how is this going?".
  Widget _overviewTab(TrackingTemplateRecord? template) {
    return PagePad(
      onRefresh: _load,
      children: [
        if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

        if (_clientName.isNotEmpty || template != null)
          AppCard(
            color: context.tokens.surfaceSoft,
            child: Row(
              children: [
                Icon(Icons.insights_outlined,
                    size: AppSize.iconButton, color: context.colors.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _clientName.isEmpty ? 'This client' : _clientName,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (template != null)
                            TemplateCadence.label(template.cadence),
                          '${_templateEntries().length} entries',
                        ].join(' · '),
                        style: context.text.bodySmall
                            ?.copyWith(color: context.tokens.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // The range scopes the cards and charts below it, so it sits with
        // them rather than as a section of its own.
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
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
          ),
        ),

        if (_overviewCards.isNotEmpty) ...[
          const SectionHeader(title: 'Summary'),
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
      ],
    );
  }

  /// Resources — what this client can open alongside this template.
  Widget _resourcesTab() {
    final resources = _assignment?.resources ?? const <TemplateResource>[];

    return PagePad(
      onRefresh: _load,
      children: [
        SectionHeader(
          title: 'Shared with this client',
          topSpace: 0,
          actionLabel: 'Manage',
          onAction: _editSharedReferences,
        ),
        Text(
          'References the client can open from this template — guides, '
          'videos, documents.',
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (resources.isEmpty)
          EmptyState(
            compact: false,
            icon: Icons.folder_open_outlined,
            message: 'Nothing shared yet.',
            actionLabel: 'Share resources',
            onAction: _editSharedReferences,
          )
        else
          for (final resource in resources)
            RowItem(
              title: resource.title,
              subtitle: [
                if (resource.categoryName.isNotEmpty) resource.categoryName,
                if (resource.subcategory.isNotEmpty) resource.subcategory,
              ].join(' · '),
              leading: Icon(
                Icons.description_outlined,
                size: AppSize.iconButton,
                color: context.colors.primary,
              ),
            ),
      ],
    );
  }

  /// Progress — what the professional wrote after reviewing or meeting.
  /// Distinct from Entries, which is what the client submitted.
  Widget _progressTab() {
    return PagePad(
      onRefresh: _load,
      children: [
        SectionHeader(
          title: 'Progress Records',
          topSpace: 0,
          actionLabel: _isProgressFormOpen ? null : '+ Add Record',
          onAction: _isProgressFormOpen ? null : _openProgressForm,
        ),
        Text(
          'Your own notes after reviewing or meeting with '
          '${_clientName.isEmpty ? 'this client' : _clientName}.',
          style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_isProgressFormOpen) ...[
          _progressForm(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_progress.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.timeline_outlined,
            message:
                'No progress records yet.\nAdd one after your next client review.',
          )
        else
          for (final entry in _progress) _progressCard(entry),
      ],
    );
  }

  Widget _progressCard(ProgressEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(entry.title, style: context.text.titleSmall),
                ),
                if (entry.status.isNotEmpty) ...[
                  StatusPill(label: entry.status),
                  const SizedBox(width: AppSpacing.xs),
                ],
                TextButton(
                  onPressed: () => _editProgress(entry),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Edit'),
                ),
              ],
            ),
            Text(
              shortDate(entry.date),
              style: context.text.labelSmall
                  ?.copyWith(color: context.tokens.muted),
            ),
            if (entry.notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(entry.notes, style: context.text.bodySmall),
            ],
            if (entry.nextStep.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Next: ${entry.nextStep}',
                style: context.text.bodySmall
                    ?.copyWith(color: context.tokens.muted),
              ),
            ],
            if (entry.createdBy.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'By ${entry.createdBy}',
                style: context.text.labelSmall
                    ?.copyWith(color: context.tokens.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Entries — what the client submitted, plus the form for logging or
  /// correcting one on their behalf.
  Widget _entriesTab(TrackingTemplateRecord? template) {
    return PagePad(
      onRefresh: _load,
      children: [
        if (_showEntryForm && template != null) ...[
          _entryForm(template),
          const SizedBox(height: AppSpacing.md),
        ],
        SectionHeader(
          title: 'Entry history (${_visibleEntries.length})',
          topSpace: 0,
          actionLabel: _showEntryForm ? null : 'Log entry',
          onAction: _showEntryForm
              ? null
              : () => setState(() => _showEntryForm = true),
        ),
        if (_visibleEntries.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.fact_check_outlined,
            message: 'No entries logged yet.',
          )
        else
          for (final entry in _visibleEntries)
            RowItem(
              title: shortDate(entry.entryDate),
              subtitle: _entrySummary(entry),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.editedByProfessional)
                    const StatusPill(label: 'Edited', tone: PillTone.info),
                  IconButton(
                    onPressed: () => _startEntryEdit(entry),
                    icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
                    tooltip: 'Edit entry',
                  ),
                ],
              ),
              onTap: () => _startEntryEdit(entry),
            ),
      ],
    );
  }

  Widget _progressForm() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingProgressId != null ? 'Update record' : 'New progress record',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _progressTitle,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Weekly Review',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _progressDate,
                firstDate: now.subtract(const Duration(days: 365 * 3)),
                lastDate: now,
              );
              if (picked != null) setState(() => _progressDate = picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: AppSize.iconRow),
            label: Text(shortDate(isoDate(_progressDate))),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _progressStatus,
            decoration: const InputDecoration(
              labelText: 'Status (optional)',
              hintText: 'On track / Needs focus',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _progressNotes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Progress notes'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _progressNextStep,
            decoration: const InputDecoration(labelText: 'Next step (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSavingProgress ? null : _cancelProgress,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: _isSavingProgress ? null : _saveProgress,
                  child: Text(
                    _isSavingProgress
                        ? 'Saving…'
                        : (_editingProgressId != null ? 'Update record' : 'Save record'),
                  ),
                ),
              ),
            ],
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
          Text(
            _editingEntryId != null ? 'Edit entry' : 'Log an entry',
            style: context.text.titleSmall,
          ),
          if (_editingEntryId != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The client sees this entry as edited by you.',
              style: context.text.bodySmall?.copyWith(color: context.tokens.muted),
            ),
          ],
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
            label: Text(shortDate(isoDate(_entryDate))),
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
          Row(
            children: [
              if (_editingEntryId != null) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSavingEntry
                        ? null
                        : () => setState(_resetEntryForm),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _isSavingEntry ? null : _saveEntry,
                  child: Text(
                    _isSavingEntry
                        ? 'Saving…'
                        : (_editingEntryId != null ? 'Update entry' : 'Save entry'),
                  ),
                ),
              ),
            ],
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
