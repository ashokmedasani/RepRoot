import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/references_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/video/open_resource.dart';
import '../../shared/widgets/app_widgets.dart';

/// The references a professional attached to one program — reached from the
/// References tab rather than living inside the Program/Log entry flow.
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
        _message = 'Could not load references.';
        _loading = false;
      });
    }
  }

  Future<void> _open(TemplateReference reference) async {
    final raw = reference.link.isNotEmpty ? reference.link : reference.fileUrl;
    if (raw.isEmpty) return;
    await openResource(
      context,
      raw,
      title: reference.title,
      description: reference.description,
      failureMessage: 'Could not open this resource.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;

    final accent = template != null ? parseAccentColor(template.accent) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(template?.name ?? 'References'),
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
                else if (template.references.isEmpty)
                  EmptyState(
                    compact: false,
                    icon: Icons.folder_open_outlined,
                    message:
                        'Your professional has not shared any references for ${template.name} yet.',
                  )
                else
                  for (final reference in template.references)
                    RowItem(
                      title: reference.title,
                      subtitle: [
                        ReferenceType.label(reference.referenceType),
                        if (reference.categoryName.isNotEmpty)
                          reference.categoryName,
                        if (reference.subcategory.isNotEmpty)
                          reference.subcategory,
                      ].join(' · '),
                      leading: Icon(
                        switch (reference.referenceType) {
                          ReferenceType.videoLink => Icons.play_circle_outline,
                          ReferenceType.pdf => Icons.picture_as_pdf_outlined,
                          ReferenceType.image => Icons.image_outlined,
                          _ => Icons.notes_outlined,
                        },
                        size: 22,
                        color: accent ?? context.colors.primary,
                      ),
                      trailing: reference.link.isNotEmpty ||
                              reference.fileUrl.isNotEmpty
                          ? const Icon(Icons.open_in_new, size: AppSize.iconRow)
                          : null,
                      onTap: () => _open(reference),
                    ),
              ],
            ),
    );
  }
}
