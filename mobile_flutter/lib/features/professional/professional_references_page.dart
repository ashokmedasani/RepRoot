import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/references_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/video/open_resource.dart';
import '../../shared/widgets/app_widgets.dart';

enum CategoryEditorMode { create, edit, subcategory }

/// Reference library: categories -> subcategories -> references, with editors
/// for both and file upload.
/// Replica of mobile/src/app/pages/professional/references/professional-references.page.ts.
class ProfessionalReferencesPage extends ConsumerStatefulWidget {
  const ProfessionalReferencesPage({super.key});

  @override
  ConsumerState<ProfessionalReferencesPage> createState() =>
      _ProfessionalReferencesPageState();
}

class _ProfessionalReferencesPageState extends ConsumerState<ProfessionalReferencesPage> {
  final _query = TextEditingController();

  List<ReferenceCategoryRecord> _categories = [];
  List<ProfessionalReferenceRecord> _references = [];
  ReferenceUsage _usage = const ReferenceUsage(used: 0, limit: null);
  String _message = '';
  bool _loading = true;

  int _expandedCategoryId = 0;
  int _expandedReferenceId = 0;

  // Reference editor
  bool _referenceFormOpen = false;
  int _editingReferenceId = 0;
  bool _isSavingReference = false;
  int _draftCategory = 0;
  String _draftSubcategory = '';
  String _draftType = ReferenceType.videoLink;
  final _draftTitle = TextEditingController();
  final _draftDescription = TextEditingController();
  final _draftLink = TextEditingController();
  final _draftTags = TextEditingController();
  PlatformFile? _pickedFile;

  // Category editor
  bool _categoryFormOpen = false;
  CategoryEditorMode _categoryMode = CategoryEditorMode.create;
  int _editingCategoryId = 0;
  bool _isSavingCategory = false;
  final _categoryName = TextEditingController();
  final _categoryDescription = TextEditingController();
  final _categorySubs = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _draftTitle.dispose();
    _draftDescription.dispose();
    _draftLink.dispose();
    _draftTags.dispose();
    _categoryName.dispose();
    _categoryDescription.dispose();
    _categorySubs.dispose();
    super.dispose();
  }

  bool get _atLimit => _usage.atLimit;

  List<ProfessionalReferenceRecord> _referencesForCategory(String name) =>
      _references.where((r) => r.categoryName == name).toList();

  List<ProfessionalReferenceRecord> _referencesFor(String name, String subcategory) =>
      _referencesForCategory(name).where((r) => r.subcategory == subcategory).toList();

  /// Includes the unnamed bucket when references sit directly on the category.
  List<String> _subcategoriesOf(ReferenceCategoryRecord category) {
    final values = [...category.subcategories];
    if (_referencesFor(category.name, '').isNotEmpty) values.add('');
    return values;
  }

  List<String> _subcategoriesFor(int categoryId) =>
      _categories.where((c) => c.id == categoryId).firstOrNull?.subcategories ??
      const [];

  /// Searches the category and everything inside it, so a hit on a reference
  /// keeps its parent visible.
  List<ReferenceCategoryRecord> get _visibleCategories {
    final term = _query.text.trim().toLowerCase();
    if (term.isEmpty) return _categories;
    return _categories.where((category) {
      final haystack = [
        category.name,
        category.description,
        for (final reference in _referencesForCategory(category.name)) ...[
          reference.title,
          reference.subcategory,
          reference.description,
          reference.tags.join(' '),
        ],
      ].join(' ').toLowerCase();
      return haystack.contains(term);
    }).toList();
  }

  bool _isCategoryOpen(int id) =>
      _expandedCategoryId == id || _query.text.trim().isNotEmpty;

  String get _categoryEditorTitle => switch (_categoryMode) {
        CategoryEditorMode.create => 'Create category',
        CategoryEditorMode.edit => 'Edit category',
        CategoryEditorMode.subcategory => 'Add subcategory',
      };

  Future<void> _load() async {
    final api = ref.read(referencesApiProvider);
    try {
      final categories = await api.getCategories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      if (mounted) setState(() => _categories = []);
    }
    try {
      final list = await api.getReferences();
      if (!mounted) return;
      setState(() {
        _references = list.references;
        _usage = list.usage;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load references.';
        _loading = false;
      });
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 1800)),
    );
  }

  Future<void> _open(ProfessionalReferenceRecord reference) async {
    final raw = reference.fileUrl.isNotEmpty ? reference.fileUrl : reference.link;
    if (raw.isEmpty) return;
    await openResource(
      context,
      raw,
      title: reference.title,
      description: reference.description,
      failureMessage: 'Could not open this reference.',
    );
  }

  // ----- category editor -----

  void _openCategoryEditor(CategoryEditorMode mode, [ReferenceCategoryRecord? category]) {
    setState(() {
      _categoryMode = mode;
      _editingCategoryId = category?.id ?? 0;
      _categoryName.text = category?.name ?? '';
      _categoryDescription.text = category?.description ?? '';
      _categorySubs.text = mode == CategoryEditorMode.edit
          ? (category?.subcategories ?? []).join('\n')
          : '';
      _categoryFormOpen = true;
    });
  }

  /// Split on newlines or commas, de-duplicated, capped at 5 — same rule as the TS.
  List<String> _parseSubcategories(String value) => value
      .split(RegExp(r'\r?\n|,'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .take(5)
      .toList();

  Future<void> _saveCategory() async {
    final current =
        _categories.where((c) => c.id == _editingCategoryId).firstOrNull;
    final entered = _parseSubcategories(_categorySubs.text);
    // "Add subcategory" merges into the existing list; "edit" replaces it.
    final subcategories = _categoryMode == CategoryEditorMode.subcategory && current != null
        ? {...current.subcategories, ...entered}.toList()
        : entered;

    setState(() => _isSavingCategory = true);
    final api = ref.read(referencesApiProvider);
    try {
      final saved = current != null
          ? await api.updateCategory(
              current.id,
              _categoryName.text.trim(),
              _categoryDescription.text.trim(),
              subcategories,
            )
          : await api.createCategory(
              _categoryName.text.trim(),
              _categoryDescription.text.trim(),
              const [],
            );
      if (!mounted) return;
      setState(() {
        _isSavingCategory = false;
        _categoryFormOpen = false;
        _expandedCategoryId = saved.id;
      });
      await _load();
      _toast('Category saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingCategory = false;
        _message = error.message;
      });
    }
  }

  Future<void> _removeCategory(ReferenceCategoryRecord category) async {
    // The backend refuses a non-empty category; say so up front.
    if (category.referenceCount > 0) {
      await _alert(
        'Cannot delete ${category.name}',
        'Move or delete the ${category.referenceCount} '
            '${category.referenceCount == 1 ? 'reference' : 'references'} in this '
            'category first.',
      );
      return;
    }
    if (!await _confirm('Delete ${category.name}?', 'This category will be removed.')) {
      return;
    }
    try {
      await ref.read(referencesApiProvider).deleteCategory(category.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _removeSubcategory(
    ReferenceCategoryRecord category,
    String subcategory,
  ) async {
    final inSub = _referencesFor(category.name, subcategory).length;
    if (inSub > 0) {
      await _alert(
        'Cannot delete $subcategory',
        'Move or delete the $inSub ${inSub == 1 ? 'reference' : 'references'} '
            'in this subcategory first.',
      );
      return;
    }
    if (!await _confirm('Delete $subcategory?', 'This subcategory will be removed.')) {
      return;
    }
    try {
      await ref.read(referencesApiProvider).updateCategory(
            category.id,
            category.name,
            category.description,
            category.subcategories.where((s) => s != subcategory).toList(),
          );
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  // ----- reference editor -----

  void _startCreateReference(ReferenceCategoryRecord category, String subcategory) {
    if (_atLimit) {
      _toast('Reference limit reached on your plan.');
      return;
    }
    setState(() {
      _editingReferenceId = 0;
      _draftCategory = category.id;
      _draftSubcategory = subcategory;
      _draftType = ReferenceType.videoLink;
      _draftTitle.clear();
      _draftDescription.clear();
      _draftLink.clear();
      _draftTags.clear();
      _pickedFile = null;
      _referenceFormOpen = true;
    });
  }

  void _startEditReference(ProfessionalReferenceRecord reference) {
    setState(() {
      _editingReferenceId = reference.id;
      _draftCategory = reference.category;
      _draftSubcategory = reference.subcategory;
      _draftType = reference.referenceType;
      _draftTitle.text = reference.title;
      _draftDescription.text = reference.description;
      _draftLink.text = reference.link;
      _draftTags.text = reference.tags.join(', ');
      _pickedFile = null;
      _referenceFormOpen = true;
    });
  }

  Future<void> _pickFile() async {
    final isImage = _draftType == ReferenceType.image;
    // file_picker 11 made pickFiles static; there is no .platform any more.
    final result = await FilePicker.pickFiles(
      type: isImage ? FileType.image : FileType.custom,
      allowedExtensions: isImage ? null : ['pdf'],
      withData: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  /// Same rules as validateReference() in the TS.
  String _validateReference() {
    if (_draftTitle.text.trim().isEmpty) return 'Add a title for the reference.';
    if (_draftCategory == 0) return 'Choose a category.';
    if (_draftType == ReferenceType.videoLink && _draftLink.text.trim().isEmpty) {
      return 'Add a video URL.';
    }
    if (_draftType == ReferenceType.pdf &&
        _draftLink.text.trim().isEmpty &&
        _pickedFile == null) {
      return 'Add a PDF URL or upload a PDF.';
    }
    if (_draftType == ReferenceType.image &&
        _pickedFile == null &&
        _editingReferenceId == 0) {
      return 'Upload an image.';
    }
    if (_draftType == ReferenceType.textNote &&
        _draftDescription.text.trim().isEmpty) {
      return 'Add text for this reference.';
    }
    return '';
  }

  List<String> _parseTags(String raw) => raw
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();

  Future<void> _saveReference() async {
    final validation = _validateReference();
    if (validation.isNotEmpty) {
      setState(() => _message = validation);
      return;
    }

    final payload = ReferencePayload(
      category: _draftCategory,
      subcategory: _draftSubcategory,
      title: _draftTitle.text.trim(),
      referenceType: _draftType,
      description: _draftDescription.text.trim(),
      link: _draftLink.text.trim(),
      tags: _parseTags(_draftTags.text),
      filePath: _pickedFile?.path,
      fileName: _pickedFile?.name,
    );

    setState(() => _isSavingReference = true);
    final api = ref.read(referencesApiProvider);
    try {
      final saved = _editingReferenceId > 0
          ? await api.updateReference(_editingReferenceId, payload)
          : await api.createReference(payload);
      if (!mounted) return;
      setState(() {
        _isSavingReference = false;
        _referenceFormOpen = false;
        _expandedReferenceId = saved.id;
      });
      await _load();
      _toast('Reference saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingReference = false;
        _message = error.message;
      });
    }
  }

  Future<void> _duplicateReference(ProfessionalReferenceRecord reference) async {
    if (_atLimit) {
      _toast('Reference limit reached on your plan.');
      return;
    }
    try {
      final copy = await ref.read(referencesApiProvider).createReference(
            ReferencePayload(
              category: reference.category,
              subcategory: reference.subcategory,
              title: '${reference.title} Copy',
              referenceType: reference.referenceType,
              description: reference.description,
              // An uploaded file cannot be re-posted from here, so the copy
              // points at the original's URL — same as the TS.
              link: reference.link.isNotEmpty ? reference.link : reference.fileUrl,
              tags: reference.tags,
            ),
          );
      if (!mounted) return;
      setState(() => _expandedReferenceId = copy.id);
      await _load();
      _toast('Reference duplicated.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _removeReference(ProfessionalReferenceRecord reference) async {
    if (!await _confirm(
      'Delete "${reference.title}"?',
      'This removes the reference from the professional library.',
    )) {
      return;
    }
    try {
      await ref.read(referencesApiProvider).deleteReference(reference.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _alert(String title, String body) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => context.pop(), child: const Text('Close')),
          ],
        ),
      );

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: const Text('Cancel')),
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
    return result == true;
  }

  // ----- build -----

  @override
  Widget build(BuildContext context) {
    final categories = _visibleCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('References'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalManage)),
        actions: [
          IconButton(
            onPressed: () => _openCategoryEditor(CategoryEditorMode.create),
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New category',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              0,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search references…',
                prefixIcon: const Icon(Icons.search, size: AppSize.iconRow),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: AppSize.iconRow),
                        onPressed: () => setState(() => _query.clear()),
                      ),
              ),
            ),
          ),
        ),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          _UsageBar(usage: _usage),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],
          if (_referenceFormOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _referenceEditor(),
          ],
          if (_categoryFormOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _categoryEditor(),
          ],
          const SizedBox(height: AppSpacing.md),

          if (_loading)
            for (var i = 0; i < 4; i++) const SkeletonBox(height: 64)
          else if (categories.isEmpty)
            EmptyState(
              compact: false,
              icon: Icons.folder_open_outlined,
              message: _categories.isEmpty
                  ? 'No categories yet.\nCreate one to start your library.'
                  : 'Nothing matches your search.',
              actionLabel: _categories.isEmpty ? 'Create category' : null,
              onAction: _categories.isEmpty
                  ? () => _openCategoryEditor(CategoryEditorMode.create)
                  : null,
            )
          else
            for (final category in categories) _categoryTile(category),
        ],
      ),
    );
  }

  Widget _categoryTile(ReferenceCategoryRecord category) {
    final open = _isCategoryOpen(category.id);
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() {
                _expandedCategoryId = _expandedCategoryId == category.id ? 0 : category.id;
                _expandedReferenceId = 0;
              }),
              borderRadius: AppRadius.mdAll,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: AppSize.iconRow,
                      color: tokens.muted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category.name, style: context.text.titleSmall),
                          if (category.description.isNotEmpty)
                            Text(
                              category.description,
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    StatusPill(label: '${category.referenceCount}'),
                    IconButton(
                      onPressed: () =>
                          _openCategoryEditor(CategoryEditorMode.edit, category),
                      icon: const Icon(Icons.edit_outlined),
                      iconSize: AppSize.iconRow,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Edit category',
                    ),
                    IconButton(
                      onPressed: () => _removeCategory(category),
                      icon: Icon(
                        category.referenceCount > 0
                            ? Icons.lock_outline
                            : Icons.delete_outline,
                      ),
                      iconSize: AppSize.iconRow,
                      color: category.referenceCount > 0
                          ? tokens.muted
                          : context.colors.error,
                      visualDensity: VisualDensity.compact,
                      tooltip: category.referenceCount > 0
                          ? 'Has references — empty it first'
                          : 'Delete category',
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              Divider(height: 1, color: tokens.border),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final subcategory in _subcategoriesOf(category))
                      _subcategoryBlock(category, subcategory),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _openCategoryEditor(
                            CategoryEditorMode.subcategory,
                            category,
                          ),
                          icon: const Icon(Icons.add, size: AppSize.iconRow),
                          label: const Text('Subcategory'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, AppSize.buttonHeightSm),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subcategoryBlock(ReferenceCategoryRecord category, String subcategory) {
    final items = _referencesFor(category.name, subcategory);
    final tokens = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subcategory.isEmpty ? 'Uncategorised' : subcategory,
                  style: context.text.labelMedium?.copyWith(
                    color: tokens.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _atLimit
                    ? null
                    : () => _startCreateReference(category, subcategory),
                icon: const Icon(Icons.add),
                iconSize: AppSize.iconRow,
                visualDensity: VisualDensity.compact,
                tooltip: 'Add reference',
              ),
              if (subcategory.isNotEmpty)
                IconButton(
                  onPressed: () => _removeSubcategory(category, subcategory),
                  icon: const Icon(Icons.delete_outline),
                  iconSize: AppSize.iconRow,
                  color: context.colors.error,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete subcategory',
                ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text('No references here yet.', style: context.text.bodySmall),
            )
          else
            for (final reference in items) _referenceRow(reference),
        ],
      ),
    );
  }

  Widget _referenceRow(ProfessionalReferenceRecord reference) {
    final expanded = _expandedReferenceId == reference.id;
    final tokens = context.tokens;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.smAll,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
              () => _expandedReferenceId = expanded ? 0 : reference.id,
            ),
            borderRadius: AppRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      reference.title.trim().isEmpty
                          ? 'R'
                          : reference.title.trim()[0].toUpperCase(),
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reference.title,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ReferenceType.label(reference.referenceType),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: AppSize.iconRow,
                    color: tokens.muted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (reference.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(reference.description, style: context.text.bodySmall),
                    ),
                  if (reference.tags.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final tag in reference.tags) StatusPill(label: tag),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      if (reference.fileUrl.isNotEmpty || reference.link.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _open(reference),
                          icon: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                          label: const Text('Open'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () => _startEditReference(reference),
                        icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            _atLimit ? null : () => _duplicateReference(reference),
                        icon: const Icon(Icons.copy_outlined, size: AppSize.iconRow),
                        label: const Text('Duplicate'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _removeReference(reference),
                        icon: const Icon(Icons.delete_outline, size: AppSize.iconRow),
                        label: const Text('Delete'),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.error,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryEditor() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_categoryEditorTitle, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          if (_categoryMode != CategoryEditorMode.subcategory) ...[
            TextField(
              controller: _categoryName,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _categoryDescription,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_categoryMode != CategoryEditorMode.create)
            TextField(
              controller: _categorySubs,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Subcategories',
                helperText: 'One per line or comma separated · max 5',
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSavingCategory || _categoryName.text.trim().isEmpty
                      ? null
                      : _saveCategory,
                  child: Text(_isSavingCategory ? 'Saving…' : 'Save'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _categoryFormOpen = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _referenceEditor() {
    final needsFile = _draftType == ReferenceType.image ||
        _draftType == ReferenceType.pdf;
    final needsLink = _draftType == ReferenceType.videoLink ||
        _draftType == ReferenceType.pdf;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingReferenceId > 0 ? 'Edit reference' : 'New reference',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _draftTitle,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<int>(
            initialValue: _draftCategory > 0 ? _draftCategory : null,
            decoration: const InputDecoration(labelText: 'Category'),
            items: _categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                .toList(),
            onChanged: (value) => setState(() {
              _draftCategory = value ?? 0;
              // Reset the subcategory to the new category's first, as in the TS.
              _draftSubcategory = _subcategoriesFor(_draftCategory).firstOrNull ?? '';
            }),
          ),
          if (_subcategoriesFor(_draftCategory).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _subcategoriesFor(_draftCategory).contains(_draftSubcategory)
                  ? _draftSubcategory
                  : null,
              decoration: const InputDecoration(labelText: 'Subcategory'),
              items: _subcategoriesFor(_draftCategory)
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (value) => setState(() => _draftSubcategory = value ?? ''),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _draftType,
            decoration: const InputDecoration(labelText: 'Type'),
            items: ReferenceType.all
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(ReferenceType.label(t)),
                    ))
                .toList(),
            onChanged: (value) => setState(() {
              _draftType = value ?? ReferenceType.videoLink;
              _pickedFile = null;
            }),
          ),
          if (needsLink) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _draftLink,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _draftType == ReferenceType.videoLink
                    ? 'Video URL'
                    : 'PDF URL (or upload below)',
              ),
            ),
          ],
          if (needsFile) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file, size: AppSize.iconRow),
                  label: Text(
                    _draftType == ReferenceType.image ? 'Choose image' : 'Choose PDF',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, AppSize.buttonHeightSm),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _pickedFile?.name ?? 'No file chosen',
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _draftDescription,
            maxLines: _draftType == ReferenceType.textNote ? 5 : 2,
            decoration: InputDecoration(
              labelText: _draftType == ReferenceType.textNote ? 'Text' : 'Description',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _draftTags,
            decoration: const InputDecoration(
              labelText: 'Tags',
              helperText: 'Comma separated',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSavingReference ? null : _saveReference,
                  child: Text(_isSavingReference ? 'Saving…' : 'Save reference'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _referenceFormOpen = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});

  final ReferenceUsage usage;

  @override
  Widget build(BuildContext context) {
    final limit = usage.limit;
    final ratio = limit == null || limit == 0
        ? 0.0
        : (usage.used / limit).clamp(0.0, 1.0);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Library usage', style: context.text.titleSmall),
              ),
              Text(
                limit == null ? '${usage.used}' : '${usage.used} / $limit',
                style: context.text.titleSmall?.copyWith(
                  color: usage.atLimit ? context.colors.error : null,
                ),
              ),
            ],
          ),
          if (limit != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 8,
                backgroundColor: context.tokens.surfaceSoft,
                valueColor: AlwaysStoppedAnimation(
                  usage.atLimit ? context.colors.error : context.colors.primary,
                ),
              ),
            ),
          ],
          if (usage.atLimit) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Limit reached — delete a reference or upgrade to add more.',
              style: context.text.bodySmall?.copyWith(color: context.colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
