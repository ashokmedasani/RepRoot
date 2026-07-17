import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/references_api.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import '../trainer/trainer_format.dart';

enum ProgramsTab { program, log, resources }

/// Client programs — pick a template, log an entry, see history and the
/// references the trainer attached.
/// Replica of mobile/src/app/pages/client/programs/client-programs.page.ts.
class ClientProgramsPage extends ConsumerStatefulWidget {
  const ClientProgramsPage({super.key});

  @override
  ConsumerState<ClientProgramsPage> createState() => _ClientProgramsPageState();
}

class _ClientProgramsPageState extends ConsumerState<ClientProgramsPage> {
  ProgramsTab _tab = ProgramsTab.program;
  List<TrackingTemplateRecord> _templates = [];
  List<TrackingEntryRecord> _entries = [];
  int? _selectedTemplateId;
  bool _loading = true;

  DateTime _entryDate = DateTime.now();
  TimeOfDay _entryTime = TimeOfDay.now();
  final Map<String, String> _answers = {};
  final _note = TextEditingController();
  bool _isSaving = false;
  String _message = '';
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  TrackingTemplateRecord? get _selectedTemplate {
    if (_templates.isEmpty) return null;
    return _templates.where((t) => t.id == _selectedTemplateId).firstOrNull ??
        _templates.first;
  }

  /// Newest first. Sorted explicitly rather than trusting the API's order —
  /// it returns newest-first, so a plain .reversed silently showed the oldest
  /// entries at the top.
  List<TrackingEntryRecord> get _entriesForSelected {
    final template = _selectedTemplate;
    if (template == null) return [];
    final list =
        _entries.where((entry) => entry.template == template.id).toList();
    list.sort((a, b) => '${b.entryDate} ${b.entryTime}'
        .compareTo('${a.entryDate} ${a.entryTime}'));
    return list;
  }

  /// The Ionic page's rough progress read: 10% per entry, capped at 100.
  int get _completionPercent =>
      (_entriesForSelected.length * 10).clamp(0, 100);

  /// Every reference across all templates, de-duplicated by id.
  List<TemplateReference> get _allReferences {
    final seen = <int>{};
    final references = <TemplateReference>[];
    for (final template in _templates) {
      for (final reference in template.references) {
        if (seen.add(reference.id)) references.add(reference);
      }
    }
    return references;
  }

  Future<void> _load() async {
    final api = ref.read(clientApiProvider);
    try {
      final templates = await api.getTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selectedTemplateId ??= templates.firstOrNull?.id;
        _message = '';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _messageIsError = true;
          _message = 'Could not load your programs. Pull to retry.';
        });
      }
    }
    await _loadEntries();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await ref.read(clientApiProvider).getEntries();
      if (mounted) setState(() => _entries = entries);
    } catch (_) {
      if (mounted) setState(() => _entries = []);
    }
  }

  void _resetDraft() {
    setState(() {
      _answers.clear();
      _note.clear();
      _entryDate = DateTime.now();
      _entryTime = TimeOfDay.now();
    });
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _isoTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _submitEntry() async {
    final template = _selectedTemplate;
    if (template == null || _isSaving) return;

    setState(() => _isSaving = true);
    // Blank answers are dropped rather than sent empty.
    final answers = <String, String>{
      for (final entry in _answers.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value,
    };

    try {
      await ref.read(clientApiProvider).submitEntry(
            templateId: template.id,
            entryDate: _isoDate(_entryDate),
            entryTime: _isoTime(_entryTime),
            answers: answers,
            note: _note.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _messageIsError = false;
        _message = 'Entry saved.';
        _tab = ProgramsTab.program;
      });
      _resetDraft();
      await _loadEntries();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _message = '');
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _messageIsError = true;
        _message = error.message;
      });
    }
  }

  Future<void> _open(TemplateReference reference) async {
    final raw = reference.link.isNotEmpty ? reference.link : reference.fileUrl;
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(Env.mediaUrl(raw));
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this resource.')),
        );
      }
    }
  }

  String _summary(TrackingEntryRecord entry) {
    final values = entry.answers.values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .take(3)
        .join(' · ');
    return values.isEmpty ? 'Submitted' : values;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Programs')),
        body: const PagePad(
          children: [SkeletonBox(height: 44), SkeletonBox(height: 180)],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Programs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              AppSpacing.sm,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: SegmentedButton<ProgramsTab>(
              segments: const [
                ButtonSegment(value: ProgramsTab.program, label: Text('Program')),
                ButtonSegment(value: ProgramsTab.log, label: Text('Log')),
                ButtonSegment(value: ProgramsTab.resources, label: Text('Resources')),
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
              ProgramsTab.program => _programTab(),
              ProgramsTab.log => _logTab(),
              ProgramsTab.resources => _resourcesTab(),
            },
          ),
        ],
      ),
    );
  }

  Widget _messageBanner() {
    if (_message.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        color: (_messageIsError ? context.colors.error : context.tokens.success)
            .withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(
              _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
              size: AppSize.iconRow,
              color: _messageIsError ? context.colors.error : context.tokens.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _message,
                style: context.text.bodySmall?.copyWith(
                  color: _messageIsError
                      ? context.colors.error
                      : context.tokens.success,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _templatePicker() {
    if (_templates.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final template in _templates)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(template.name),
                  selected: _selectedTemplate?.id == template.id,
                  onSelected: (_) =>
                      setState(() => _selectedTemplateId = template.id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _programTab() {
    final template = _selectedTemplate;

    return PagePad(
      onRefresh: _load,
      children: [
        _messageBanner(),
        _templatePicker(),
        if (template == null)
          const EmptyState(
            compact: false,
            icon: Icons.list_alt_outlined,
            message: 'Your trainer has not assigned any programs yet.',
          )
        else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.name, style: context.text.titleMedium),
                if (template.purpose.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(template.purpose, style: context.text.bodySmall),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    StatusPill(
                      label: TemplateCadence.label(template.cadence),
                      tone: PillTone.info,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${_entriesForSelected.length} entries logged',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _completionPercent / 100,
                    minHeight: 8,
                    backgroundColor: context.tokens.surfaceSoft,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => setState(() => _tab = ProgramsTab.log),
                  icon: const Icon(Icons.add, size: AppSize.iconRow),
                  label: const Text('Log an entry'),
                ),
              ],
            ),
          ),

          SectionHeader(title: 'History (${_entriesForSelected.length})'),
          if (_entriesForSelected.isEmpty)
            const EmptyState(message: 'No entries yet. Log your first one.')
          else
            for (final entry in _entriesForSelected.take(20))
              RowItem(
                title: shortDate(entry.entryDate),
                subtitle: _summary(entry),
                trailingCaption:
                    entry.entryTime.isNotEmpty ? hhmm(entry.entryTime) : null,
                trailingValue: entry.editedByTrainer ? 'Edited' : null,
              ),
        ],
      ],
    );
  }

  Widget _logTab() {
    final template = _selectedTemplate;

    if (template == null) {
      return const PagePad(
        children: [
          EmptyState(
            compact: false,
            icon: Icons.list_alt_outlined,
            message: 'Nothing to log yet.',
          ),
        ],
      );
    }

    return PagePad(
      children: [
        _messageBanner(),
        _templatePicker(),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Log ${template.name}', style: context.text.titleSmall),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
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
                      icon: const Icon(Icons.calendar_today_outlined,
                          size: AppSize.iconRow),
                      label: Text(shortDate(_isoDate(_entryDate))),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSize.buttonHeightSm),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _entryTime,
                        );
                        if (picked != null) setState(() => _entryTime = picked);
                      },
                      icon: const Icon(Icons.schedule, size: AppSize.iconRow),
                      label: Text(_isoTime(_entryTime)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSize.buttonHeightSm),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final field in template.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _answerField(field),
                ),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving ? null : _submitEntry,
                      child: Text(_isSaving ? 'Saving…' : 'Submit entry'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  TextButton(
                    onPressed: _isSaving ? null : _resetDraft,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resourcesTab() {
    final references = _allReferences;

    return PagePad(
      onRefresh: _load,
      children: [
        if (references.isEmpty)
          const EmptyState(
            compact: false,
            icon: Icons.folder_open_outlined,
            message: 'Your trainer has not shared any resources yet.',
          )
        else
          for (final reference in references)
            RowItem(
              title: reference.title,
              subtitle: [
                ReferenceType.label(reference.referenceType),
                if (reference.categoryName.isNotEmpty) reference.categoryName,
                if (reference.subcategory.isNotEmpty) reference.subcategory,
              ].join(' · '),
              leading: Icon(
                switch (reference.referenceType) {
                  ReferenceType.videoLink => Icons.play_circle_outline,
                  ReferenceType.pdf => Icons.picture_as_pdf_outlined,
                  ReferenceType.image => Icons.image_outlined,
                  _ => Icons.notes_outlined,
                },
                size: 22,
                color: context.colors.primary,
              ),
              trailing: reference.link.isNotEmpty || reference.fileUrl.isNotEmpty
                  ? const Icon(Icons.open_in_new, size: AppSize.iconRow)
                  : null,
              onTap: () => _open(reference),
            ),
      ],
    );
  }

  /// One input per field type — this is the client logging their own data.
  Widget _answerField(TemplateField field) {
    final key = field.answerKey;
    final value = _answers[key] ?? '';

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
              onSelectionChanged: (s) => setState(() => _answers[key] = s.first),
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
          onChanged: (v) => setState(() => _answers[key] = v ?? ''),
        );

      case TemplateFieldType.rating:
        final scale = ((field.scale == null || field.scale == 0) ? 5 : field.scale!)
            .clamp(2, 10);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: context.text.bodyMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (var i = 1; i <= scale; i++)
                  ChoiceChip(
                    label: Text('$i'),
                    selected: value == '$i',
                    onSelected: (_) => setState(() => _answers[key] = '$i'),
                  ),
              ],
            ),
          ],
        );

      case TemplateFieldType.number:
        return TextField(
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _answers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );

      case TemplateFieldType.longText:
        return TextField(
          maxLines: 3,
          onChanged: (v) => _answers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );

      default:
        return TextField(
          onChanged: (v) => _answers[key] = v,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
          ),
        );
    }
  }
}
