import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/api/client_api.dart';
import '../../core/api/models/client_models.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';

/// The trainer as the client sees them.
///
/// Every section here is optional by design: the backend only sends what the
/// trainer set visible on their profile, so an absent section means "private",
/// not "missing".
/// Replica of mobile/src/app/pages/client/trainer/client-trainer.page.ts.
class ClientTrainerPage extends ConsumerStatefulWidget {
  const ClientTrainerPage({super.key});

  @override
  ConsumerState<ClientTrainerPage> createState() => _ClientTrainerPageState();
}

class _ClientTrainerPageState extends ConsumerState<ClientTrainerPage> {
  ClientTrainerProfile? _trainer;
  List<AdditionalInfoItem> _sharedInfo = [];
  bool _loading = true;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await ref.read(clientApiProvider).getMe();
      if (!mounted) return;
      setState(() {
        _trainer = me.trainerProfile;
        _sharedInfo = me.sharedAdditionalInfo;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load your trainer.';
        _loading = false;
      });
    }
  }

  Future<void> _open(String raw) async {
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(Env.mediaUrl(raw));
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    }
  }

  String get _initials {
    final parts = (_trainer?.trainerName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    if (parts.isEmpty) return 'T';
    return parts.length > 2 ? parts.substring(0, 2) : parts;
  }

  @override
  Widget build(BuildContext context) {
    final trainer = _trainer;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your trainer')),
        body: const PagePad(children: [SkeletonBox(height: 110), SkeletonBox(height: 160)]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your trainer'),
        leading: BackButton(onPressed: () => context.go(Routes.clientMore)),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          if (_message.isNotEmpty) ErrorNote(message: _message, onRetry: _load),

          if (trainer == null)
            const EmptyState(
              compact: false,
              icon: Icons.person_outline,
              message: 'Your trainer has not shared their profile yet.',
            )
          else ...[
            AppCard(
              child: Row(
                children: [
                  AppAvatar(
                    initials: _initials,
                    imageUrl: Env.mediaUrl(trainer.profilePhotoUrl),
                    size: 60,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(trainer.trainerName, style: context.text.titleMedium),
                        if (trainer.professionalHeadline.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            trainer.professionalHeadline,
                            style: context.text.bodySmall,
                          ),
                        ],
                        if (trainer.location.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Icon(Icons.place_outlined,
                                  size: 14, color: context.tokens.muted),
                              const SizedBox(width: 2),
                              Text(trainer.location, style: context.text.bodySmall),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (trainer.aboutMe.isNotEmpty) ...[
              const SectionHeader(title: 'About'),
              AppCard(child: Text(trainer.aboutMe, style: context.text.bodyMedium)),
            ],

            if (trainer.professionalSummary != null) ...[
              const SectionHeader(title: 'Professional details'),
              AppCard(
                child: Column(
                  children: [
                    _kv('Type', trainer.professionalSummary!.trainerType),
                    _kv(
                      'Experience',
                      trainer.professionalSummary!.yearsExperience != null
                          ? '${trainer.professionalSummary!.yearsExperience} years'
                          : '',
                    ),
                    _kv('Specializations',
                        trainer.professionalSummary!.specializations),
                    _kv('Languages', trainer.professionalSummary!.languagesKnown),
                  ],
                ),
              ),
            ],

            if (trainer.trainingStyle.isNotEmpty) ...[
              const SectionHeader(title: 'Training style'),
              AppCard(
                child: Text(trainer.trainingStyle, style: context.text.bodyMedium),
              ),
            ],

            if (trainer.certification != null) ...[
              const SectionHeader(title: 'Certification'),
              AppCard(
                child: Column(
                  children: [
                    _kv('Name', trainer.certification!.name),
                    _kv('Issued by', trainer.certification!.issuedBy),
                    _kv('Year', trainer.certification!.year?.toString() ?? ''),
                    if (trainer.certification!.fileUrl.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _open(trainer.certification!.fileUrl),
                          icon: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                          label: const Text('View certificate'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (trainer.images.isNotEmpty) ...[
              const SectionHeader(title: 'Gallery'),
              SizedBox(
                height: 132,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final image in trainer.images)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: GestureDetector(
                          onTap: () => _open(image.url),
                          child: ClipRRect(
                            borderRadius: AppRadius.mdAll,
                            child: Image.network(
                              Env.mediaUrl(image.url),
                              width: 132,
                              height: 132,
                              fit: BoxFit.cover,
                              // A broken image must not blank the gallery.
                              errorBuilder: (_, _, _) => Container(
                                width: 132,
                                height: 132,
                                color: context.tokens.surfaceSoft,
                                child: Icon(Icons.broken_image_outlined,
                                    color: context.tokens.muted),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (trainer.links.isNotEmpty) ...[
              const SectionHeader(title: 'Links'),
              for (final link in trainer.links)
                RowItem(
                  title: link.title.isEmpty ? link.url : link.title,
                  subtitle: link.title.isEmpty ? null : link.url,
                  leading: Icon(Icons.link, size: 20, color: context.colors.primary),
                  trailing: const Icon(Icons.open_in_new, size: AppSize.iconRow),
                  onTap: () => _open(link.url),
                ),
            ],
          ],

          if (_sharedInfo.isNotEmpty) ...[
            const SectionHeader(title: 'Shared with you'),
            for (final item in _sharedInfo)
              RowItem(
                title: item.title,
                subtitle: item.text.isNotEmpty ? item.text : item.link,
                leading: Icon(
                  switch (item.type) {
                    AdditionalInfoType.link => Icons.link,
                    AdditionalInfoType.reference => Icons.folder_open_outlined,
                    _ => Icons.notes_outlined,
                  },
                  size: 20,
                  color: context.tokens.accent,
                ),
                onTap: item.link.isNotEmpty ? () => _open(item.link) : null,
              ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: context.text.bodySmall)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: context.text.titleSmall,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
