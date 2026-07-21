import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Tracking template library: create/edit with a field builder, adopt
/// standards, delete.
/// Replica of mobile/src/app/pages/trainer/templates/trainer-templates.page.ts.
class TrainerTemplatesPage extends ConsumerStatefulWidget {
  const TrainerTemplatesPage({super.key});

  @override
  ConsumerState<TrainerTemplatesPage> createState() =>
      _TrainerTemplatesPageState();
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

class _TrainerTemplatesPageState extends ConsumerState<TrainerTemplatesPage> {
  List<TrackingTemplateRecord> _templates = [];
  List<StandardTemplateRecord> _standards = [];
  int _maxTemplates = 0;
  String _message = '';
  bool _loading = true;

  bool _editorOpen = false;
  int _editingId = 0;
  bool _isSaving = false;

  final _name = TextEditingController();
  final _purpose = TextEditingController();
  String _cadence = TemplateCadence.daily;
  Color _accent = const Color(0xFF0B7DE3);
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
      !_isSaving &&
      _name.text.trim().isNotEmpty &&
      _fields.any((field) => field.label.trim().isNotEmpty);

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
  }

  void _startCreate() {
    setState(() {
      _editingId = 0;
      _name.clear();
      _purpose.clear();
      _cadence = TemplateCadence.daily;
      _accent = const Color(0xFF0B7DE3);
      _fields = [_DraftField()];
      _editorOpen = true;
    });
  }

  void _startEdit(TrackingTemplateRecord template) {
    setState(() {
      _editingId = template.id;
      _name.text = template.name;
      _purpose.text = template.purpose;
      _cadence = template.cadence.isEmpty ? TemplateCadence.daily : template.cadence;
      _accent = _parseAccent(template.accent);
      _fields = template.fields.map(_DraftField.from).toList();
      _editorOpen = true;
    });
  }

  /// Backend stores accents as "#rrggbb"; fall back to brand blue.
  Color _parseAccent(String hex) {
    final cleaned = hex.replaceAll('#', '').trim();
    if (cleaned.length != 6) return const Color(0xFF0B7DE3);
    final value = int.tryParse(cleaned, radix: 16);
    return value == null ? const Color(0xFF0B7DE3) : Color(0xFF000000 | value);
  }

  String _accentHex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final payload = TemplatePayload(
      name: _name.text.trim(),
      purpose: _purpose.text.trim(),
      cadence: _cadence,
      accent: _accentHex(_accent),
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
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _editorOpen = false;
      });
      await _load();
      if (mounted) _toast('Template saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _message = error.message;
      });
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
    // A template still assigned to clients cannot be deleted: the trainer must
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
                context.go(Routes.trainerClients);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        leading: BackButton(onPressed: () => context.go(Routes.trainerManage)),
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

          if (_editorOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _Editor(
              editing: _editingId > 0,
              name: _name,
              purpose: _purpose,
              cadence: _cadence,
              accent: _accent,
              fields: _fields,
              isSaving: _isSaving,
              canSave: _canSave,
              onCadence: (value) => setState(() => _cadence = value),
              onAccent: (value) => setState(() => _accent = value),
              onChanged: () => setState(() {}),
              onAddField: () => setState(() => _fields.add(_DraftField())),
              onRemoveField: (index) => setState(() => _fields.removeAt(index)),
              onSave: _save,
              onCancel: () => setState(() => _editorOpen = false),
            ),
          ],

          const SectionHeader(title: 'Tracking Library'),
          if (_loading)
            for (var i = 0; i < 3; i++) const SkeletonBox(height: 66)
          else if (_templates.isEmpty)
            const EmptyState(
              message: 'No templates yet. Create one or adopt a standard below.',
            )
          else
            for (final template in _templates)
              RowItem(
                title: template.name,
                subtitle:
                    '${TemplateCadence.label(template.cadence)} · ${template.fields.length} fields · ${template.assignedCount} assigned',
                leading: Container(
                  width: 5,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _parseAccent(template.accent),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              ),

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

class _Editor extends StatelessWidget {
  const _Editor({
    required this.editing,
    required this.name,
    required this.purpose,
    required this.cadence,
    required this.accent,
    required this.fields,
    required this.isSaving,
    required this.canSave,
    required this.onCadence,
    required this.onAccent,
    required this.onChanged,
    required this.onAddField,
    required this.onRemoveField,
    required this.onSave,
    required this.onCancel,
  });

  final bool editing;
  final TextEditingController name;
  final TextEditingController purpose;
  final String cadence;
  final Color accent;
  final List<_DraftField> fields;
  final bool isSaving;
  final bool canSave;
  final ValueChanged<String> onCadence;
  final ValueChanged<Color> onAccent;
  final VoidCallback onChanged;
  final VoidCallback onAddField;
  final ValueChanged<int> onRemoveField;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  /// A native colour picker is a heavy dependency for one field; the Ionic page
  /// used <input type="color">. A swatch row covers the real use (a visual tag)
  /// with far less weight.
  static const _swatches = [
    Color(0xFF0B7DE3), Color(0xFF2563EB), Color(0xFF0F9F9D), Color(0xFF159567),
    Color(0xFFD97706), Color(0xFFD92D20), Color(0xFF7C3AED), Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editing ? 'Edit template' : 'New template',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.md),
          Text(
            'ACCENT COLOR',
            style: context.text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final swatch in _swatches)
                InkWell(
                  onTap: () => onAccent(swatch),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: swatch.toARGB32() == accent.toARGB32()
                            ? context.colors.onSurface
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),
          Text(
            'FIELDS',
            style: context.text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (var i = 0; i < fields.length; i++)
            _FieldEditor(
              field: fields[i],
              onChanged: onChanged,
              onRemove: fields.length > 1 ? () => onRemoveField(i) : null,
            ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onAddField,
            icon: const Icon(Icons.add),
            label: const Text('Add field'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonHeightSm),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: canSave ? onSave : null,
                  child: Text(isSaving ? 'Saving…' : 'Save template'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldEditor extends StatelessWidget {
  const _FieldEditor({
    required this.field,
    required this.onChanged,
    this.onRemove,
  });

  final _DraftField field;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border, style: BorderStyle.solid),
        borderRadius: AppRadius.smAll,
        color: tokens.surfaceSoft,
      ),
      child: Column(
        children: [
          TextFormField(
            initialValue: field.label,
            onChanged: (value) {
              field.label = value;
              onChanged();
            },
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Weight (kg)',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: field.fieldType,
            decoration: const InputDecoration(labelText: 'Type'),
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
          if (field.fieldType == TemplateFieldType.dropdown) ...[
            const SizedBox(height: AppSpacing.sm),
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
          ],
          if (field.fieldType == TemplateFieldType.rating) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: '${field.scale ?? 5}',
              keyboardType: TextInputType.number,
              onChanged: (value) {
                // The engine clamps 2..10 anyway; keep the input honest here too.
                field.scale = int.tryParse(value)?.clamp(2, 10);
              },
              decoration: const InputDecoration(
                labelText: 'Scale',
                helperText: '2 to 10',
              ),
            ),
          ],
          if (onRemove != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: AppSize.iconRow),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
