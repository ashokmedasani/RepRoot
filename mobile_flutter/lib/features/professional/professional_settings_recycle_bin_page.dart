import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models/account_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// Recycle Bin — restore or permanently delete recently-deleted items.
/// Split out of the former single-scroll professional_settings_page.dart.
/// Unlike the old "Recycle bin" card (only rendered when non-empty), this
/// page is always reachable from the Settings menu and shows an [EmptyState]
/// when there is nothing in the bin.
class ProfessionalSettingsRecycleBinPage extends ConsumerStatefulWidget {
  const ProfessionalSettingsRecycleBinPage({super.key});

  @override
  ConsumerState<ProfessionalSettingsRecycleBinPage> createState() =>
      _ProfessionalSettingsRecycleBinPageState();
}

class _ProfessionalSettingsRecycleBinPageState
    extends ConsumerState<ProfessionalSettingsRecycleBinPage> {
  List<RecycleBinItem> _recycleBin = [];
  bool _loaded = false;
  String _loadError = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    if (mounted) {
      setState(() {
        _loaded = false;
        _loadError = '';
      });
    }
    try {
      final bin = await api.getRecycleBin();
      if (mounted) setState(() => _recycleBin = bin);
    } catch (error, stackTrace) {
      debugPrint(
        'Could not load the recycle bin (${error.runtimeType}).\n$stackTrace',
      );
      if (mounted) {
        setState(() => _loadError = 'The recycle bin could not be loaded.');
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _restoreBinItem(RecycleBinItem item) async {
    try {
      await ref
          .read(professionalAuthApiProvider)
          .restoreRecycleBinItem(item.id);
      if (mounted) {
        setState(
          () =>
              _recycleBin = _recycleBin.where((i) => i.id != item.id).toList(),
        );
      }
      _toast('Restored.');
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not restore.');
    }
  }

  Future<void> _deleteBinItem(RecycleBinItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${item.title}" forever?'),
        content: const Text('This cannot be undone.'),
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
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(professionalAuthApiProvider)
          .deleteRecycleBinItemPermanently(item.id);
      if (mounted) {
        setState(
          () =>
              _recycleBin = _recycleBin.where((i) => i.id != item.id).toList(),
        );
      }
    } catch (error) {
      _toast(error is ApiException ? error.message : 'Could not delete.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          const SettingsHeroCard(
            icon: Icons.delete_outline,
            title: 'Recycle Bin',
            subtitle: 'Restore or permanently delete recently-deleted items.',
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Recycle bin',
            child: _loadError.isNotEmpty
                ? ErrorNote(message: _loadError, onRetry: _load)
                : !_loaded
                ? const SizedBox.shrink()
                : _recycleBin.isEmpty
                ? const EmptyState(
                    message: 'Nothing in the recycle bin.',
                    icon: Icons.delete_outline,
                  )
                : Column(
                    children: [
                      for (final item in _recycleBin)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: MenuAccent.orange.bg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                  color: MenuAccent.orange.fg,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.title.isNotEmpty
                                          ? item.title
                                          : item.categoryLabel,
                                      style: context.text.bodyMedium,
                                    ),
                                    Text(
                                      '${item.categoryLabel} · ${item.daysRemaining}d left',
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () => _restoreBinItem(item),
                                child: const Text('Restore'),
                              ),
                              IconButton(
                                onPressed: () => _deleteBinItem(item),
                                icon: const Icon(Icons.delete_forever_outlined),
                                iconSize: AppSize.iconRow,
                                color: context.colors.error,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Titled surface — the .card rule.
class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
