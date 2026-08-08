import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_client.dart';
import '../../core/api/plan_lock_api.dart';
import '../../core/api/resources_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/video/open_resource.dart';
import '../../shared/widgets/app_widgets.dart';

enum CategoryEditorMode { create, edit, subcategory }

/// Resource library: categories -> subcategories -> resources, with editors
/// for both and file upload.
/// Replica of mobile/src/app/pages/professional/resources/professional-resources.page.ts.
class ProfessionalResourcesPage extends ConsumerStatefulWidget {
  const ProfessionalResourcesPage({super.key});

  @override
  ConsumerState<ProfessionalResourcesPage> createState() =>
      _ProfessionalResourcesPageState();
}

/// Copy for the Resource Library `i` popup. The page shows the library; the
/// rules about how it is structured and what locking means live in here.
const _libraryInfo =
    'Your Resource Library is what clients see attached to their templates — '
    'PDFs, links, videos, notes.\n\n'
    'HOW IT IS ORGANISED\n'
    'Categories are the top level, and each one holds resources. A resource '
    'can also be filed under a subcategory inside its category, so a large '
    'category stays browsable.\n\n'
    'ORDER\n'
    'Drag a category by the handle to reorder the library. That order is not '
    'only cosmetic: categories take your plan\'s slots from the top down, so '
    'whatever you drag to the bottom is what locks first if you go over.\n\n'
    'LOCKED CATEGORIES\n'
    'A locked category is past your plan\'s limit. Every resource inside it '
    'locks with it and is hidden from clients. Nothing is deleted — drag the '
    'category higher, free a slot, or upgrade, and it all comes back.';

const _lockedCategoriesInfo =
    'These categories are past your current plan\'s category limit.\n\n'
    'Every resource inside them is locked too, and hidden from your clients. '
    'Nothing has been deleted.\n\n'
    'To unlock one: drag it higher in Categories so it takes a slot ahead of '
    'another category, delete a category you no longer need, or upgrade your '
    'plan.';

class _ProfessionalResourcesPageState extends ConsumerState<ProfessionalResourcesPage> {
  final _query = TextEditingController();

  List<ResourceCategoryRecord> _categories = [];
  List<ProfessionalResourceRecord> _resources = [];
  PlanLockStatus _lockStatus = const PlanLockStatus();
  ResourceUsage _usage = const ResourceUsage(used: 0, limit: null);
  String _message = '';
  bool _loading = true;

  int _expandedCategoryId = 0;
  int _expandedResourceId = 0;

  // Resource editor
  bool _resourceFormOpen = false;
  int _editingResourceId = 0;
  bool _isSavingResource = false;
  int _draftCategory = 0;
  String _draftSubcategory = '';
  String _draftType = ResourceType.videoLink;
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

  List<ProfessionalResourceRecord> _resourcesForCategory(String name) =>
      _resources.where((r) => r.categoryName == name).toList();

  List<ProfessionalResourceRecord> _resourcesFor(String name, String subcategory) =>
      _resourcesForCategory(name).where((r) => r.subcategory == subcategory).toList();

  /// Includes the unnamed bucket when resources sit directly on the category.
  List<String> _subcategoriesOf(ResourceCategoryRecord category) {
    final values = [...category.subcategories];
    if (_resourcesFor(category.name, '').isNotEmpty) values.add('');
    return values;
  }

  List<String> _subcategoriesFor(int categoryId) =>
      _categories.where((c) => c.id == categoryId).firstOrNull?.subcategories ??
      const [];

  // ----- plan-limit lock ordering -----

  PlanLockSection get _categoryLock =>
      _lockStatus.section(PlanLockModelKey.categories);

  PlanLockSection get _resourceLock =>
      _lockStatus.section(PlanLockModelKey.resources);

  /// Until the lock-status call lands (or if it fails) there is no split to
  /// honour, so the library renders flat and drag is disabled.
  bool get _categoryLockLoaded =>
      _lockStatus.sections.containsKey(PlanLockModelKey.categories);

  bool get _resourceLockLoaded =>
      _lockStatus.sections.containsKey(PlanLockModelKey.resources);

  /// Order comes from the lock status' active_ids, never a separate local
  /// list, so a drag cannot drift out of sync with the stored order.
  List<ResourceCategoryRecord> get _activeCategories {
    if (!_categoryLockLoaded) return _categories;
    final byId = {for (final category in _categories) category.id: category};
    return [
      for (final id in _categoryLock.activeIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  List<ResourceCategoryRecord> get _lockedCategories {
    if (!_categoryLockLoaded) return const [];
    final lockedIds = _categoryLock.lockedIds.toSet();
    return _categories.where((category) => lockedIds.contains(category.id)).toList();
  }

  List<ProfessionalResourceRecord> _activeResourcesFor(
    String categoryName,
    String subcategory,
  ) {
    if (!_resourceLockLoaded) return _resourcesFor(categoryName, subcategory);
    final byId = {for (final resource in _resources) resource.id: resource};
    return [
      for (final id in _resourceLock.activeIds)
        if (byId[id] != null &&
            byId[id]!.categoryName == categoryName &&
            byId[id]!.subcategory == subcategory)
          byId[id]!,
    ];
  }

  List<ProfessionalResourceRecord> _lockedResourcesFor(
    String categoryName,
    String subcategory,
  ) {
    if (!_resourceLockLoaded) return const [];
    final lockedIds = _resourceLock.lockedIds.toSet();
    return _resourcesFor(categoryName, subcategory)
        .where((resource) => lockedIds.contains(resource.id))
        .toList();
  }

  /// Drag indices address the unfiltered list, so reordering is only offered
  /// when nothing is being searched.
  bool get _searching => _query.text.trim().isNotEmpty;

  /// Searches the category and everything inside it, so a hit on a resource
  /// keeps its parent visible.
  List<ResourceCategoryRecord> _matchingSearch(
    List<ResourceCategoryRecord> source,
  ) {
    final term = _query.text.trim().toLowerCase();
    if (term.isEmpty) return source;
    return source.where((category) {
      final haystack = [
        category.name,
        category.description,
        for (final resource in _resourcesForCategory(category.name)) ...[
          resource.title,
          resource.subcategory,
          resource.description,
          resource.tags.join(' '),
        ],
      ].join(' ').toLowerCase();
      return haystack.contains(term);
    }).toList();
  }

  List<ResourceCategoryRecord> get _visibleCategories =>
      _matchingSearch(_activeCategories);

  List<ResourceCategoryRecord> get _visibleLockedCategories =>
      _matchingSearch(_lockedCategories);

  bool _isCategoryOpen(int id) =>
      _expandedCategoryId == id || _query.text.trim().isNotEmpty;

  String get _categoryEditorTitle => switch (_categoryMode) {
        CategoryEditorMode.create => 'Create category',
        CategoryEditorMode.edit => 'Edit category',
        CategoryEditorMode.subcategory => 'Add subcategory',
      };

  Future<void> _load() async {
    final api = ref.read(resourcesApiProvider);
    try {
      final categories = await api.getCategories();
      if (mounted) setState(() => _categories = categories);
    } catch (_) {
      if (mounted) setState(() => _categories = []);
    }
    try {
      final list = await api.getResources();
      if (!mounted) return;
      setState(() {
        _resources = list.resources;
        _usage = list.usage;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load resources.';
        _loading = false;
      });
    }
    await _loadLockStatus();
  }

  Future<void> _loadLockStatus() async {
    try {
      final status = await ref.read(planLockApiProvider).getLockStatus();
      if (mounted) setState(() => _lockStatus = status);
    } catch (_) {/* the library just renders flat, without lock badges */}
  }

  /// Sends the permuted active order for one model and adopts the lock status
  /// the backend recomputes. Locked ids are never in the payload — the
  /// backend rejects any order that includes one.
  Future<void> _submitReorder(
    String modelKey,
    List<int> orderedIds,
    String failureMessage,
  ) async {
    final previous = _lockStatus;
    // Optimistic so the row stays where it was dropped during the round trip.
    setState(() {
      _lockStatus = _lockStatus.withSection(
        modelKey,
        _lockStatus.section(modelKey).copyWith(activeIds: orderedIds),
      );
    });

    try {
      final status =
          await ref.read(planLockApiProvider).reorder(modelKey, orderedIds);
      if (mounted) setState(() => _lockStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _lockStatus = previous);
      _toast(error is ApiException ? error.message : failureMessage);
    }
  }

  // onReorderItem already adjusts newIndex for the removed row.
  Future<void> _reorderCategories(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    final orderedIds = [..._categoryLock.activeIds];
    if (oldIndex < 0 || oldIndex >= orderedIds.length) return;
    orderedIds.insert(newIndex, orderedIds.removeAt(oldIndex));

    await _submitReorder(
      PlanLockModelKey.categories,
      orderedIds,
      'Could not reorder categories.',
    );
  }

  /// Resources are ranked professional-wide, but the library only shows one
  /// subcategory at a time. Dragging inside a subcategory reorders just that
  /// visible subset while preserving the exact slots those resources occupy
  /// in the full ranking, so priority against resources elsewhere is
  /// untouched. Mirrors dropResource() in the web references component.
  Future<void> _reorderResources(
    String categoryName,
    String subcategory,
    int oldIndex,
    int newIndex,
  ) async {
    // onReorderItem already adjusts newIndex for the removed row.
    if (oldIndex == newIndex) return;

    final scopedIds = _activeResourcesFor(categoryName, subcategory)
        .map((resource) => resource.id)
        .toList();
    if (oldIndex < 0 || oldIndex >= scopedIds.length) return;
    scopedIds.insert(newIndex, scopedIds.removeAt(oldIndex));

    final scopedIdSet = scopedIds.toSet();
    var cursor = 0;
    final mergedIds = [
      for (final id in _resourceLock.activeIds)
        if (scopedIdSet.contains(id)) scopedIds[cursor++] else id,
    ];

    await _submitReorder(
      PlanLockModelKey.resources,
      mergedIds,
      'Could not reorder resources.',
    );
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(milliseconds: 1800)),
    );
  }

  Future<void> _open(ProfessionalResourceRecord resource) async {
    final raw = resource.fileUrl.isNotEmpty ? resource.fileUrl : resource.link;
    if (raw.isEmpty) return;
    await openResource(
      context,
      raw,
      title: resource.title,
      description: resource.description,
      failureMessage: 'Could not open this resource.',
    );
  }

  // ----- category editor -----

  void _openCategoryEditor(CategoryEditorMode mode, [ResourceCategoryRecord? category]) {
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
    final api = ref.read(resourcesApiProvider);
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

  Future<void> _removeCategory(ResourceCategoryRecord category) async {
    // The backend refuses a non-empty category; say so up front.
    if (category.resourceCount > 0) {
      await _alert(
        'Cannot delete ${category.name}',
        'Move or delete the ${category.resourceCount} '
            '${category.resourceCount == 1 ? 'resource' : 'resources'} in this '
            'category first.',
      );
      return;
    }
    if (!await _confirm('Delete ${category.name}?', 'This category will be removed.')) {
      return;
    }
    try {
      await ref.read(resourcesApiProvider).deleteCategory(category.id);
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _removeSubcategory(
    ResourceCategoryRecord category,
    String subcategory,
  ) async {
    final inSub = _resourcesFor(category.name, subcategory).length;
    if (inSub > 0) {
      await _alert(
        'Cannot delete $subcategory',
        'Move or delete the $inSub ${inSub == 1 ? 'resource' : 'resources'} '
            'in this subcategory first.',
      );
      return;
    }
    if (!await _confirm('Delete $subcategory?', 'This subcategory will be removed.')) {
      return;
    }
    try {
      await ref.read(resourcesApiProvider).updateCategory(
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

  // ----- resource editor -----

  void _startCreateResource(ResourceCategoryRecord category, String subcategory) {
    if (_atLimit) {
      _toast('Resource limit reached on your plan.');
      return;
    }
    setState(() {
      _editingResourceId = 0;
      _draftCategory = category.id;
      _draftSubcategory = subcategory;
      _draftType = ResourceType.videoLink;
      _draftTitle.clear();
      _draftDescription.clear();
      _draftLink.clear();
      _draftTags.clear();
      _pickedFile = null;
      _resourceFormOpen = true;
    });
  }

  void _startEditResource(ProfessionalResourceRecord resource) {
    setState(() {
      _editingResourceId = resource.id;
      _draftCategory = resource.category;
      _draftSubcategory = resource.subcategory;
      _draftType = resource.resourceType;
      _draftTitle.text = resource.title;
      _draftDescription.text = resource.description;
      _draftLink.text = resource.link;
      _draftTags.text = resource.tags.join(', ');
      _pickedFile = null;
      _resourceFormOpen = true;
    });
  }

  Future<void> _pickFile() async {
    final isImage = _draftType == ResourceType.image;
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

  /// Same rules as validateResource() in the TS.
  String _validateResource() {
    if (_draftTitle.text.trim().isEmpty) return 'Add a title for the resource.';
    if (_draftCategory == 0) return 'Choose a category.';
    if (_draftType == ResourceType.videoLink && _draftLink.text.trim().isEmpty) {
      return 'Add a video URL.';
    }
    if (_draftType == ResourceType.pdf &&
        _draftLink.text.trim().isEmpty &&
        _pickedFile == null) {
      return 'Add a PDF URL or upload a PDF.';
    }
    if (_draftType == ResourceType.image &&
        _pickedFile == null &&
        _editingResourceId == 0) {
      return 'Upload an image.';
    }
    if (_draftType == ResourceType.textNote &&
        _draftDescription.text.trim().isEmpty) {
      return 'Add text for this resource.';
    }
    return '';
  }

  List<String> _parseTags(String raw) => raw
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();

  Future<void> _saveResource() async {
    final validation = _validateResource();
    if (validation.isNotEmpty) {
      setState(() => _message = validation);
      return;
    }

    final payload = ResourcePayload(
      category: _draftCategory,
      subcategory: _draftSubcategory,
      title: _draftTitle.text.trim(),
      resourceType: _draftType,
      description: _draftDescription.text.trim(),
      link: _draftLink.text.trim(),
      tags: _parseTags(_draftTags.text),
      filePath: _pickedFile?.path,
      fileName: _pickedFile?.name,
    );

    setState(() => _isSavingResource = true);
    final api = ref.read(resourcesApiProvider);
    try {
      final saved = _editingResourceId > 0
          ? await api.updateResource(_editingResourceId, payload)
          : await api.createResource(payload);
      if (!mounted) return;
      setState(() {
        _isSavingResource = false;
        _resourceFormOpen = false;
        _expandedResourceId = saved.id;
      });
      await _load();
      _toast('Resource saved.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSavingResource = false;
        _message = error.message;
      });
    }
  }

  Future<void> _duplicateResource(ProfessionalResourceRecord resource) async {
    if (_atLimit) {
      _toast('Resource limit reached on your plan.');
      return;
    }
    try {
      final copy = await ref.read(resourcesApiProvider).createResource(
            ResourcePayload(
              category: resource.category,
              subcategory: resource.subcategory,
              title: '${resource.title} Copy',
              resourceType: resource.resourceType,
              description: resource.description,
              // An uploaded file cannot be re-posted from here, so the copy
              // points at the original's URL — same as the TS.
              link: resource.link.isNotEmpty ? resource.link : resource.fileUrl,
              tags: resource.tags,
            ),
          );
      if (!mounted) return;
      setState(() => _expandedResourceId = copy.id);
      await _load();
      _toast('Resource duplicated.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _message = error.message);
    }
  }

  Future<void> _removeResource(ProfessionalResourceRecord resource) async {
    if (!await _confirm(
      'Delete "${resource.title}"?',
      'This removes the resource from the professional library.',
    )) {
      return;
    }
    try {
      await ref.read(resourcesApiProvider).deleteResource(resource.id);
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
        title: const Text('Resource Library'),
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
                hintText: 'Search resources…',
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
          if (_resourceFormOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _resourceEditor(),
          ],
          if (_categoryFormOpen) ...[
            const SizedBox(height: AppSpacing.md),
            _categoryEditor(),
          ],
          SectionHeader(
            title: 'Categories',
            infoBody: _libraryInfo,
            topSpace: AppSpacing.lg,
          ),

          if (_loading)
            for (var i = 0; i < 4; i++) const SkeletonBox(height: 64)
          else if (categories.isEmpty && _visibleLockedCategories.isEmpty)
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
          else ...[
            if (_canReorderCategories) ...[
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // Tiles expand on tap, so an explicit handle keeps a tap from
                // being read as the start of a drag.
                buildDefaultDragHandles: false,
                itemCount: categories.length,
                onReorderItem: _reorderCategories,
                itemBuilder: (context, index) => _categoryTile(
                  categories[index],
                  key: ValueKey(categories[index].id),
                  dragIndex: index,
                ),
              ),
            ] else
              for (final category in categories)
                _categoryTile(category, key: ValueKey(category.id)),

            if (_visibleLockedCategories.isNotEmpty) ...[
              SectionHeader(
                title: 'Locked categories',
                infoBody: _lockedCategoriesInfo,
              ),
              for (final category in _visibleLockedCategories)
                _categoryTile(
                  category,
                  key: ValueKey('locked-${category.id}'),
                  locked: true,
                ),
            ],
          ],
        ],
      ),
    );
  }

  bool get _canReorderCategories =>
      _categoryLockLoaded && !_searching && _activeCategories.length > 1;

  /// One category tile. [dragIndex] adds the reorder handle (active tiles
  /// inside the reorderable list only); [locked] renders the plan-lock
  /// variant, which cannot be edited until it unlocks.
  Widget _categoryTile(
    ResourceCategoryRecord category, {
    required Key key,
    int? dragIndex,
    bool locked = false,
  }) {
    final open = _isCategoryOpen(category.id);
    final tokens = context.tokens;

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() {
                _expandedCategoryId = _expandedCategoryId == category.id ? 0 : category.id;
                _expandedResourceId = 0;
              }),
              borderRadius: AppRadius.mdAll,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.card),
                child: Row(
                  children: [
                    if (dragIndex != null) ...[
                      ReorderableDragStartListener(
                        index: dragIndex,
                        child: Icon(
                          Icons.drag_indicator,
                          size: AppSize.iconRow,
                          color: tokens.muted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
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
                    StatusPill(
                      label: locked ? 'Locked' : '${category.resourceCount}',
                      tone: locked ? PillTone.warn : PillTone.neutral,
                    ),
                    IconButton(
                      onPressed: locked
                          ? null
                          : () => _openCategoryEditor(
                                CategoryEditorMode.edit,
                                category,
                              ),
                      icon: const Icon(Icons.edit_outlined),
                      iconSize: AppSize.iconRow,
                      visualDensity: VisualDensity.compact,
                      tooltip: locked
                          ? 'Locked categories can\'t be edited until they unlock'
                          : 'Edit category',
                    ),
                    IconButton(
                      onPressed: () => _removeCategory(category),
                      icon: Icon(
                        category.resourceCount > 0
                            ? Icons.lock_outline
                            : Icons.delete_outline,
                      ),
                      iconSize: AppSize.iconRow,
                      color: category.resourceCount > 0
                          ? tokens.muted
                          : context.colors.error,
                      visualDensity: VisualDensity.compact,
                      tooltip: category.resourceCount > 0
                          ? 'Has resources — empty it first'
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
                      _subcategoryBlock(
                        category,
                        subcategory,
                        categoryLocked: locked,
                      ),
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

  Widget _subcategoryBlock(
    ResourceCategoryRecord category,
    String subcategory, {
    bool categoryLocked = false,
  }) {
    // Everything inside a locked category is locked by cascade, so nothing
    // there is reorderable regardless of the resources lock section.
    final active = categoryLocked
        ? const <ProfessionalResourceRecord>[]
        : _activeResourcesFor(category.name, subcategory);
    final locked = categoryLocked
        ? _resourcesFor(category.name, subcategory)
        : _lockedResourcesFor(category.name, subcategory);
    final canReorder =
        !categoryLocked && _resourceLockLoaded && !_searching && active.length > 1;
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
                    : () => _startCreateResource(category, subcategory),
                icon: const Icon(Icons.add),
                iconSize: AppSize.iconRow,
                visualDensity: VisualDensity.compact,
                tooltip: 'Add resource',
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
          if (active.isEmpty && locked.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text('No resources here yet.', style: context.text.bodySmall),
            )
          else ...[
            if (canReorder)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                // Rows expand on tap, so an explicit handle keeps a tap from
                // being read as the start of a drag.
                buildDefaultDragHandles: false,
                itemCount: active.length,
                onReorderItem: (oldIndex, newIndex) => _reorderResources(
                  category.name,
                  subcategory,
                  oldIndex,
                  newIndex,
                ),
                itemBuilder: (context, index) => _resourceRow(
                  active[index],
                  key: ValueKey(active[index].id),
                  dragIndex: index,
                ),
              )
            else
              for (final resource in active)
                _resourceRow(resource, key: ValueKey(resource.id)),
            for (final resource in locked)
              _resourceRow(
                resource,
                key: ValueKey('locked-${resource.id}'),
                locked: true,
              ),
          ],
        ],
      ),
    );
  }

  /// One resource row. [dragIndex] adds the reorder handle (active rows inside
  /// the reorderable list only); [locked] rows are hidden from clients and
  /// cannot be edited, but can still be opened or deleted to free a slot.
  Widget _resourceRow(
    ProfessionalResourceRecord resource, {
    required Key key,
    int? dragIndex,
    bool locked = false,
  }) {
    final expanded = _expandedResourceId == resource.id;
    final tokens = context.tokens;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.smAll,
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
              () => _expandedResourceId = expanded ? 0 : resource.id,
            ),
            borderRadius: AppRadius.smAll,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              child: Row(
                children: [
                  if (dragIndex != null) ...[
                    ReorderableDragStartListener(
                      index: dragIndex,
                      child: Icon(
                        Icons.drag_indicator,
                        size: AppSize.iconRow,
                        color: tokens.muted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      resource.title.trim().isEmpty
                          ? 'R'
                          : resource.title.trim()[0].toUpperCase(),
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
                          resource.title,
                          style: context.text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ResourceType.label(resource.resourceType),
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (locked) ...[
                    const StatusPill(label: 'Locked', tone: PillTone.warn),
                    const SizedBox(width: AppSpacing.xs),
                  ],
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
                  if (locked)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'This resource is locked and hidden from clients. It '
                        'can still be deleted to free a slot, but not edited '
                        'until it unlocks.',
                        style: context.text.bodySmall?.copyWith(color: tokens.muted),
                      ),
                    ),
                  if (resource.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(resource.description, style: context.text.bodySmall),
                    ),
                  if (resource.tags.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final tag in resource.tags) StatusPill(label: tag),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      if (resource.fileUrl.isNotEmpty || resource.link.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _open(resource),
                          icon: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                          label: const Text('Open'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      TextButton.icon(
                        onPressed:
                            locked ? null : () => _startEditResource(resource),
                        icon: const Icon(Icons.edit_outlined, size: AppSize.iconRow),
                        label: const Text('Edit'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _atLimit || locked
                            ? null
                            : () => _duplicateResource(resource),
                        icon: const Icon(Icons.copy_outlined, size: AppSize.iconRow),
                        label: const Text('Duplicate'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _removeResource(resource),
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

  Widget _resourceEditor() {
    final needsFile = _draftType == ResourceType.image ||
        _draftType == ResourceType.pdf;
    final needsLink = _draftType == ResourceType.videoLink ||
        _draftType == ResourceType.pdf;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingResourceId > 0 ? 'Edit resource' : 'New resource',
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
            items: ResourceType.all
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(ResourceType.label(t)),
                    ))
                .toList(),
            onChanged: (value) => setState(() {
              _draftType = value ?? ResourceType.videoLink;
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
                labelText: _draftType == ResourceType.videoLink
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
                    _draftType == ResourceType.image ? 'Choose image' : 'Choose PDF',
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
            maxLines: _draftType == ResourceType.textNote ? 5 : 2,
            decoration: InputDecoration(
              labelText: _draftType == ResourceType.textNote ? 'Text' : 'Description',
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
                  onPressed: _isSavingResource ? null : _saveResource,
                  child: Text(_isSavingResource ? 'Saving…' : 'Save resource'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => setState(() => _resourceFormOpen = false),
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

  final ResourceUsage usage;

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
              'Limit reached — delete a resource or upgrade to add more.',
              style: context.text.bodySmall?.copyWith(color: context.colors.error),
            ),
          ],
        ],
      ),
    );
  }
}
