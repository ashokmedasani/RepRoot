import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/resources_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/video/open_resource.dart';
import '../../shared/widgets/app_widgets.dart';

/// The resources a professional attached to one program — reached from the
/// Resources tab rather than living inside the Program/Log entry flow.
class ClientTemplateResourcesPage extends ConsumerStatefulWidget {
  const ClientTemplateResourcesPage({super.key, required this.templateId});

  final int templateId;

  @override
  ConsumerState<ClientTemplateResourcesPage> createState() =>
      _ClientTemplateResourcesPageState();
}

class _ClientTemplateResourcesPageState
    extends ConsumerState<ClientTemplateResourcesPage> {
  TrackingTemplateRecord? _template;
  bool _loading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final templates = await ref.read(clientApiProvider).getTemplates();
      if (!mounted) return;
      setState(() {
        _template =
            templates.where((t) => t.id == widget.templateId).firstOrNull;
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
  }

  Future<void> _open(TemplateResource resource) async {
    final raw = resource.link.isNotEmpty ? resource.link : resource.fileUrl;
    if (raw.isEmpty) return;
    await openResource(
      context,
      raw,
      title: resource.title,
      description: resource.description,
      failureMessage: 'Could not open this resource.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;

    final accent =
        template != null ? TemplateAccent.of(context, template.accent) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(template?.name ?? 'Resources'),
        leading: BackButton(onPressed: () => context.go(Routes.clientPrograms)),
      ),
      body: _loading
          ? const PagePad(
              children: [SkeletonBox(height: 60), SkeletonBox(height: 60)],
            )
          : PagePad(
              onRefresh: _load,
              children: [
                if (_message.isNotEmpty)
                  ErrorNote(message: _message, onRetry: _load),
                if (template == null)
                  const EmptyState(
                    compact: false,
                    icon: Icons.folder_open_outlined,
                    message: 'This program could not be found.',
                  )
                else if (template.resources.isEmpty)
                  EmptyState(
                    compact: false,
                    icon: Icons.folder_open_outlined,
                    message:
                        'Your professional has not shared any resources for ${template.name} yet.',
                  )
                else
                  for (final resource in template.resources)
                    RowItem(
                      title: resource.title,
                      subtitle: [
                        ResourceType.label(resource.resourceType),
                        if (resource.categoryName.isNotEmpty)
                          resource.categoryName,
                        if (resource.subcategory.isNotEmpty)
                          resource.subcategory,
                      ].join(' · '),
                      leading: Icon(
                        switch (resource.resourceType) {
                          ResourceType.videoLink => Icons.play_circle_outline,
                          ResourceType.pdf => Icons.picture_as_pdf_outlined,
                          ResourceType.image => Icons.image_outlined,
                          _ => Icons.notes_outlined,
                        },
                        size: 22,
                        color: accent ?? context.colors.primary,
                      ),
                      trailing: resource.link.isNotEmpty ||
                              resource.fileUrl.isNotEmpty
                          ? const Icon(Icons.open_in_new, size: AppSize.iconRow)
                          : null,
                      onTap: () => _open(resource),
                    ),
              ],
            ),
    );
  }
}
