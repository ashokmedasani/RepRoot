import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/plan_lock_api.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Tracking template library: create/edit with a field builder, adopt
/// standards, delete.
/// Replica of mobile/src/app/pages/professional/templates/professional-templates.page.ts.
class ProfessionalTemplatesPage extends ConsumerStatefulWidget {
  const ProfessionalTemplatesPage({super.key});

  @override
  ConsumerState<ProfessionalTemplatesPage> createState() =>
      _ProfessionalTemplatesPageState();
}

/// Mutable field row for the builder — TemplateField is immutable.
class _DraftField {
  _DraftField({
    this.label = '',
    this.fieldType = TemplateFieldType.number,
    this.placeholder = '',
    List<String>? options,
    this.scale,
  }) : options = options ?? [];

  String label;
  String fieldType;
  String placeholder;
  List<String> options;
  int? scale;

  TemplateField toField() => TemplateField(
        label: label.trim(),
        fieldType: fieldType,
        placeholder: placeholder,
        options: fieldType == TemplateFieldType.dropdown ? options : const [],
        scale: fieldType == TemplateFieldType.rating ? (scale ?? 5) : null,
      );

  static _DraftField from(TemplateField field) => _DraftField(
        label: field.label,
        fieldType: field.fieldType,
        placeholder: field.placeholder,
        options: [...field.options],
        scale: field.scale,
      );
}

/// Copy for the Tracking Library `i` popup. Kept out of the page body so the
/// list itself stays a list — these rules matter once, when you first wonder
/// why a template locked, not on every visit.
const _libraryInfo =
    'Your Tracking Library holds the templates you assign to clients — a '
    'weight log, a daily check-in, whatever you track.\n\n'
    'ORDER\n'
    'Drag a template by the handle on the left to reorder the library. The '
    'order is yours to set and it decides what happens if you go over your '
    'plan: templates fill your plan\'s slots from the top down, so anything '
    'you drag to the bottom is what locks first.\n\n'
    'LOCKED TEMPLATES\n'
    'A locked template is past your plan\'s limit. Nothing is deleted — it '
    'cannot be edited or assigned until it unlocks. Drag it higher, or '
    'upgrade, and it comes back intact.\n\n'
    'DELETING\n'
    'A template assigned to even one client cannot be deleted, so nobody '
    'loses a tracker they are still logging against. Unassign it from every '
    'client first and the delete becomes available. Past entries are kept '
    'either way.';

const _lockedInfo =
    'These templates are past your current plan\'s template limit.\n\n'
    'Nothing was deleted. They cannot be edited or assigned to anyone while '
    'they are locked.\n\n'
    'To unlock one: drag it higher in the Tracking Library so it takes a '
    'slot ahead of another template, delete a template you no longer need, '
    'or upgrade your plan for more slots.';

class _ProfessionalTemplatesPageState extends ConsumerState<ProfessionalTemplatesPage> {
  List<TrackingTemplateRecord> _templates = [];
  List<StandardTemplateRecord> _standards = [];
  PlanLockStatus _lockStatus = const PlanLockStatus();
  int _maxTemplates = 0;
  String _message = '';
  bool _loading = true;

  int _editingId = 0;

  final _name = TextEditingController();
  final _purpose = TextEditingController();
  String _cadence = TemplateCadence.daily;
  String _accent = TemplateAccent.blue;
  List<_DraftField> _fields = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _purpose.dispose();
    super.dispose();
  }

  int get _assignedTotal =>
      _templates.fold(0, (sum, item) => sum + item.assignedCount);

  List<StandardTemplateRecord> get _unAdoptedStandards =>
      _standards.where((standard) => !standard.adopted).toList();

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _fields.any((field) => field.label.trim().isNotEmpty);

  PlanLockSection get _lock => _lockStatus.section(PlanLockModelKey.templates);

  /// Until the lock-status call lands (or if it fails) there is no split to
  /// honour, so the library renders flat and drag is disabled rather than
  /// showing an empty list.
  bool get _lockStatusLoaded =>
      _lockStatus.sections.containsKey(PlanLockModelKey.templates);

  /// Display order is always derived from the lock status' active_ids, never
  /// from a separately tracked local list, so a drag cannot drift out of sync
  /// with the order the backend believes it stored.
  List<TrackingTemplateRecord> get _activeTemplates {
    if (!_lockStatusLoaded) return _templates;
    final byId = {for (final template in _templates) template.id: template};
    return [
      for (final id in _lock.activeIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  List<TrackingTemplateRecord> get _lockedTemplates {
    if (!_lockStatusLoaded) return const [];
    final lockedIds = _lock.lockedIds.toSet();
    return _templates.where((template) => lockedIds.contains(template.id)).toList();
  }

  bool get _canReorder => _lockStatusLoaded && _activeTemplates.length > 1;

  Future<void> _load() async {
    try {
      final response = await ref.read(templatesApiProvider).getTemplates();
      if (!mounted) return;
      setState(() {
        _templates = response.templates;
        _maxTemplates = response.maxTemplates;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load templates.';
        _loading = false;
      });
    }
    try {
      final standards = await ref.read(templatesApiProvider).getStandardTemplates();
      if (mounted) setState(() => _standards = standards);
    } catch (_) {
      if (mounted) setState(() => _standards = []);
    }
    await _loadLockStatus();
  }

  Future<void> _loadLockStatus() async {
    try {
      final status = await ref.read(planLockApiProvider).getLockStatus();
      if (mounted) setState(() => _lockStatus = status);
    } catch (_) {/* the library just renders flat, without lock badges */}
  }

  /// Sets the professional's own priority order among their ACTIVE templates.
  /// Locked templates are never part of the payload — the backend rejects any
  /// order that includes one (plan_lock_status.reorder_active_items).
  // onReorderItem already adjusts newIndex for the removed row — no manual
  // `newIndex -= 1` correction here, unlike the deprecated onReorder.
  Future<void> _reorderTemplates(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final previous = _lockStatus;
    final orderedIds = [..._lock.activeIds];
    if (oldIndex < 0 || oldIndex >= orderedIds.length) return;
    orderedIds.insert(newIndex, orderedIds.removeAt(oldIndex));

    // Optimistic: the row stays where it was dropped instead of snapping back
    // until the round trip finishes.
    setState(() {
      _lockStatus = _lockStatus.withSection(
        PlanLockModelKey.templates,
        _lock.copyWith(activeIds: orderedIds),
      );
    });

    try {
      final status = await ref
          .read(planLockApiProvider)
          .reorder(PlanLockModelKey.templates, orderedIds);
      if (mounted) setState(() => _lockStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _lockStatus = previous);
      _toast(error is ApiException ? error.message : 'Could not reorder templates.');
    }
  }

  /// True when the plan's template slots are all taken. The backend refuses
  /// the create with "Maximum of N templates reached." either way; this stops
  /// the professional filling in a whole form before finding that out.
  bool get _atTemplateLimit =>
      _maxTemplates > 0 && _templates.length >= _maxTemplates;

  Future<void> _startCreate() async {
    if (_atTemplateLimit) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('You have reached your template limit'),
          content: Text(
            'Your plan allows $_maxTemplates '
            '${_maxTemplates == 1 ? 'template' : 'templates'}, and all of '
            '${_maxTemplates == 1 ? 'it is' : 'them are'} in use.\n\n'
            'Delete a template you no longer need, or upgrade your plan, to '
            'create another one.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _editingId = 0;
      _name.clear();
      _purpose.clear();
      _cadence = TemplateCadence.daily;
      _accent = TemplateAccent.blue;
      _fields = [_DraftField()];
    });
    await _openEditor();
  }

  Future<void> _startEdit(TrackingTemplateRecord template) async {
    setState(() {
      _editingId = template.id;
      _name.text = template.name;
      _purpose.text = template.purpose;
      _cadence = template.cadence.isEmpty ? TemplateCadence.daily : template.cadence;
      _accent = TemplateAccent.normalize(template.accent);
      _fields = template.fields.map(_DraftField.from).toList();
    });
    await _openEditor();
  }

  /// Creating and editing happen on their own full-screen page, then drop you
  /// back on the list. The editor used to expand inline above the library,
  /// which pushed the list you were working from off-screen and left Save
  /// stranded below however many fields you had added.
  Future<void> _openEditor() async {
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (dialogContext) => Dialog.fullscreen(
        child: StatefulBuilder(
          builder: (dialogContext, setLocal) {
            Future<void> save() async {
              setLocal(() => saving = true);
              final ok = await _save();
              if (!dialogContext.mounted) return;
              if (ok) {
                Navigator.of(dialogContext).pop();
              } else {
                setLocal(() => saving = false);
              }
            }

            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel',
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                ),
                title: Text(_editingId > 0 ? 'Edit template' : 'New template'),
                actions: [
                  TextButton(
                    onPressed: (_canSave && !saving) ? save : null,
                    child: Text(saving ? 'Saving…' : 'Save'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              body: SafeArea(
                child: _Editor(
                  name: _name,
                  purpose: _purpose,
                  cadence: _cadence,
                  accent: _accent,
                  fields: _fields,
                  onCadence: (value) => setLocal(() => _cadence = value),
                  onAccent: (value) => setLocal(() => _accent = value),
                  onChanged: () => setLocal(() {}),
                  onAddField: () => setLocal(() => _fields.add(_DraftField())),
                  onRemoveField: (index) =>
                      setLocal(() => _fields.removeAt(index)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _save() async {
    final payload = TemplatePayload(
      name: _name.text.trim(),
      purpose: _purpose.text.trim(),
      cadence: _cadence,
      accent: _accent,
      customFields: _fields
          .where((field) => field.label.trim().isNotEmpty)
          .map((field) => field.toField())
          .toList(),
    );

    final api = ref.read(templatesApiProvider);
    try {
      if (_editingId > 0) {
        await api.updateTemplate(_editingId, payload);
      } else {
        await api.createTemplate(payload);
      }
      if (!mounted) return false;
      await _load();
      if (mounted) _toast('Template saved.');
      return true;
    } on ApiException catch (error) {
      if (!mounted) return false;
      setState(() => _message = error.message);
      // The plan-limit refusal arrives here too, if the count changed on
      // another device between opening the editor and saving.
      _toast(error.message);
      return false;
    }
  }

  Future<void> _adopt(StandardTemplateRecord standard) async {
    try {
      await ref.read(templatesApiProvider).adoptStandardTemplate(standard.key);
      await _load();
      if (mounted) _toast('${standard.name} added.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _remove(TrackingTemplateRecord template) async {
    // A template still assigned to clients cannot be deleted: the professional must
    // unassign it from each client first. This protects clients from silently
    // losing a tracker they are actively logging against.
    if (template.assignedCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${template.name} is in use'),
          content: Text(
            'This template is assigned to ${template.assignedCount} '
            '${template.assignedCount == 1 ? 'client' : 'clients'}.\n\n'
            'Remove it from every client first, then you can delete it.',
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                context.pop();
                context.go(Routes.professionalClients);
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, AppSize.buttonHeightSm),
              ),
              child: const Text('Open Clients'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${template.name}?'),
        content: const Text(
          'This template is not assigned to anyone. Past entries stay saved.',
        ),
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
      await ref.read(templatesApiProvider).deleteTemplate(template.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 1800)),
    );
  }

  /// One library row. [dragIndex] adds the reorder handle (active rows inside
  /// the reorderable list only); [locked] renders the plan-lock variant, which
  /// cannot be edited but can still be deleted to free a slot.
  Widget _templateRow(
    TrackingTemplateRecord template, {
    required Key key,
    int? dragIndex,
    bool locked = false,
  }) {
    return RowItem(
      key: key,
      title: template.name,
      subtitle:
          '${TemplateCadence.label(template.cadence)} · ${template.fields.length} fields · ${template.assignedCount} assigned',
      // The accent is the card's own left edge, as on the web
      // (`border-left: 4px solid`), rather than a floating swatch sitting in
      // the content — a separate bar read as one more item in the row.
      accentColor: TemplateAccent.of(context, template.accent),
      leading: dragIndex == null
          ? null
          : ReorderableDragStartListener(
              index: dragIndex,
              child: Icon(
                Icons.drag_indicator,
                size: AppSize.iconRow,
                color: context.tokens.muted,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked)
            const StatusPill(label: 'Locked', tone: PillTone.warn)
          else
            IconButton(
              onPressed: () => _startEdit(template),
              icon: const Icon(Icons.edit_outlined),
              iconSize: AppSize.iconRow,
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: () => _remove(template),
            icon: Icon(
              template.assignedCount > 0
                  ? Icons.lock_outline
                  : Icons.delete_outline,
            ),
            iconSize: AppSize.iconRow,
            // Locked reads as unavailable, not as a destructive action.
            color: template.assignedCount > 0
                ? context.tokens.muted
                : context.colors.error,
            tooltip: template.assignedCount > 0
                ? 'Assigned to ${template.assignedCount} — unassign first'
                : 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalManage)),
        actions: [
          IconButton(
            onPressed: _startCreate,
            icon: const Icon(Icons.add),
            tooltip: 'New template',
          ),
        ],
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          KpiGrid(
            children: [
              KpiTile(
                label: 'Templates used',
                value: '${_templates.length} / ${_maxTemplates > 0 ? _maxTemplates : '—'}',
              ),
              KpiTile(label: 'Assigned clients', value: '$_assignedTotal'),
            ],
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],

          SectionHeader(
            title: 'Tracking Library',
            infoBody: _libraryInfo,
          ),
          if (_loading)
            for (var i = 0; i < 3; i++) const SkeletonBox(height: 66)
          else if (_templates.isEmpty)
            const EmptyState(
              message: 'No templates yet. Create one or adopt a standard below.',
            )
          else ...[
            if (_canReorder) ...[
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // The rows already carry two icon buttons; an explicit handle
                // keeps a tap on those from being read as the start of a drag.
                buildDefaultDragHandles: false,
                itemCount: _activeTemplates.length,
                onReorderItem: _reorderTemplates,
                itemBuilder: (context, index) {
                  final template = _activeTemplates[index];
                  return _templateRow(
                    template,
                    key: ValueKey(template.id),
                    dragIndex: index,
                  );
                },
              ),
            ] else
              for (final template in _activeTemplates)
                _templateRow(template, key: ValueKey(template.id)),

            if (_lockedTemplates.isNotEmpty) ...[
              SectionHeader(
                title: 'Locked by your plan',
                infoBody: _lockedInfo,
              ),
              for (final template in _lockedTemplates)
                _templateRow(
                  template,
                  key: ValueKey('locked-${template.id}'),
                  locked: true,
                ),
            ],
          ],

          if (_unAdoptedStandards.isNotEmpty) ...[
            const SectionHeader(title: 'Standard templates'),
            for (final standard in _unAdoptedStandards)
              RowItem(
                title: standard.name,
                subtitle:
                    '${TemplateCadence.label(standard.cadence)} · ${standard.fields.length} fields',
                trailing: OutlinedButton(
                  onPressed: () => _adopt(standard),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(72, AppSize.buttonHeightSm),
                  ),
                  child: const Text('Adopt'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Body of the full-screen template editor. Save and Cancel live in the host
/// page's app bar, not here, so they stay reachable however long the field
/// list gets.
class _Editor extends StatelessWidget {
  const _Editor({
    required this.name,
    required this.purpose,
    required this.cadence,
    required this.accent,
    required this.fields,
    required this.onCadence,
    required this.onAccent,
    required this.onChanged,
    required this.onAddField,
    required this.onRemoveField,
  });

  final TextEditingController name;
  final TextEditingController purpose;
  final String cadence;
  final String accent;
  final List<_DraftField> fields;
  final ValueChanged<String> onCadence;
  final ValueChanged<String> onAccent;
  final VoidCallback onChanged;
  final VoidCallback onAddField;
  final ValueChanged<int> onRemoveField;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    // The editor sits on the page wash, and the inputs are borderless tinted
    // by theme — on their own they dissolved into that background. Grouping
    // the template's own settings onto one white card gives the form an
    // edge to sit on, and separates "what this template is" from the list of
    // fields below it.
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        AppSpacing.md,
        AppSpacing.screen,
        AppSpacing.xxl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          TextField(
            controller: name,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Daily Nutrition Log',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: purpose,
            decoration: const InputDecoration(
              labelText: 'Purpose',
              hintText: 'What does this track?',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: cadence,
            decoration: const InputDecoration(labelText: 'Cadence'),
            items: TemplateCadence.all
                .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(TemplateCadence.label(c)),
                    ))
                .toList(),
            onChanged: (value) => onCadence(value ?? TemplateCadence.daily),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'ACCENT COLOR',
            style: context.text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Exactly the four accents the web can render. The old picker
          // offered eight arbitrary swatches and saved them as hex, so half
          // of them had no meaning on the website at all.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final name in TemplateAccent.all)
                InkWell(
                  onTap: () => onAccent(name),
                  borderRadius: AppRadius.pillAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: name == accent
                          ? TemplateAccent.of(context, name)
                              .withValues(alpha: 0.12)
                          : tokens.surfaceSoft,
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(
                        color: name == accent
                            ? TemplateAccent.of(context, name)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: TemplateAccent.of(context, name),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          TemplateAccent.label(name),
                          style: context.text.labelMedium?.copyWith(
                            fontWeight:
                                name == accent ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

            ],
          ),
        ),
          SectionHeader(
            title: 'Fields',
            topSpace: AppSpacing.xl,
            infoBody: 'Each field is one question the client answers every '
                'time they log against this template.\n\n'
                'The answer type decides the input they get — a number pad, '
                'a dropdown, a rating scale — so pick the one that makes '
                'logging quickest for them.\n\n'
                'Changing a field does not alter entries already submitted; '
                'past entries keep the answers they were saved with.',
          ),
          for (var i = 0; i < fields.length; i++)
            _FieldEditor(
              index: i,
              field: fields[i],
              onChanged: onChanged,
              onRemove: fields.length > 1 ? () => onRemoveField(i) : null,
            ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onAddField,
            icon: const Icon(Icons.add, size: AppSize.iconRow),
            label: const Text('Add field'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeight),
            ),
          ),
      ],
    );
  }
}

/// One field, in its own bordered card with a numbered header.
///
/// Previously every field was a flat tinted block whose label, type, options
/// and Remove ran together with the next field's — on a form with five
/// fields there was no visible boundary telling you which controls belonged
/// to which. The header row now names the field and owns the delete action,
/// and the type-specific settings sit in a separated group below.
class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.index,
    required this.field,
    required this.onChanged,
    this.onRemove,
  });

  final int index;
  final _DraftField field;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasSettings = field.fieldType == TemplateFieldType.dropdown ||
        field.fieldType == TemplateFieldType.rating;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.tileAll,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: which field this is, and the only way to delete it.
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.surfaceSoft,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.tile),
                topRight: Radius.circular(AppRadius.tile),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    field.label.trim().isEmpty
                        ? 'Field ${index + 1}'
                        : field.label.trim(),
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                    iconSize: AppSize.iconRow,
                    color: context.colors.error,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove field',
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: field.label,
                  onChanged: (value) {
                    field.label = value;
                    onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Field name',
                    hintText: 'e.g. Weight (kg)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: field.fieldType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Answer type'),
                  items: TemplateFieldType.all
                      .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(TemplateFieldType.label(t)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    field.fieldType = value ?? TemplateFieldType.number;
                    onChanged();
                  },
                ),
                if (hasSettings) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'SETTINGS',
                    style: context.text.labelSmall?.copyWith(
                      color: tokens.muted,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (field.fieldType == TemplateFieldType.dropdown)
                    TextFormField(
                      initialValue: field.options.join(', '),
                      onChanged: (value) {
                        field.options = value
                            .split(',')
                            .map((option) => option.trim())
                            .where((option) => option.isNotEmpty)
                            .toList();
                      },
                      decoration: const InputDecoration(
                        labelText: 'Options',
                        helperText: 'Comma separated',
                      ),
                    ),
                  if (field.fieldType == TemplateFieldType.rating)
                    TextFormField(
                      initialValue: '${field.scale ?? 5}',
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        // The engine clamps 2..10 anyway; keep the input
                        // honest here too.
                        field.scale = int.tryParse(value)?.clamp(2, 10);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Scale',
                        helperText: '2 to 10',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
