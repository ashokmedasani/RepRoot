import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'trainer_format.dart';

/// Manage hub — quick actions + recent items + pending review.
/// Replica of mobile/src/app/pages/trainer/manage/trainer-manage.page.ts.
class TrainerManagePage extends ConsumerStatefulWidget {
  const TrainerManagePage({super.key});

  @override
  ConsumerState<TrainerManagePage> createState() => _TrainerManagePageState();
}

class _TrainerManagePageState extends ConsumerState<TrainerManagePage> {
  FormsGroupsOverview? _overview;
  List<TrackingTemplateRecord> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      () async {
        try {
          final overview = await ref.read(formsGroupsApiProvider).getOverview();
          if (mounted) setState(() => _overview = overview);
        } catch (_) {/* leave the hub usable if the overview fails */}
      }(),
      () async {
        try {
          final response = await ref.read(templatesApiProvider).getTemplates();
          if (mounted) setState(() => _templates = response.templates);
        } catch (_) {
          if (mounted) setState(() => _templates = []);
        }
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final leadForm = overview?.leadForm;
    final groups = overview?.groups ?? const <TrainerGroup>[];
    final pending = overview?.pendingForms ?? const <LeadSubmission>[];
    final tokens = context.tokens;

    final nothingYet =
        leadForm == null && _templates.isEmpty && groups.isEmpty && !_loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage')),
      body: PagePad(
        onRefresh: _load,
        children: [
          Text(
            'QUICK ACTIONS',
            style: context.text.labelSmall?.copyWith(
              color: tokens.muted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _QuickGrid(
            actions: [
              (Icons.description_outlined, 'Forms', Routes.trainerFormsGroups),
              (Icons.people_outline, 'Groups', '${Routes.trainerFormsGroups}?tab=groups'),
              (Icons.layers_outlined, 'Templates', Routes.trainerTemplates),
              (Icons.folder_open_outlined, 'References', Routes.trainerReferences),
              (Icons.calendar_today_outlined, 'Schedule', Routes.trainerSchedule),
              (Icons.add_circle_outline, 'New client', Routes.trainerClientCreate),
            ],
          ),

          const SectionHeader(title: 'Recent items'),
          if (_loading)
            for (var i = 0; i < 3; i++) const SkeletonBox(height: 66)
          else if (nothingYet)
            const EmptyState(
              message: 'Create your first form, group, or template to see it here.',
            )
          else ...[
            if (leadForm != null)
              RowItem(
                title: leadForm.title,
                subtitle: 'Main form · updated ${shortDate(leadForm.updatedAt)}',
                leading: Icon(
                  Icons.description_outlined,
                  color: tokens.success,
                  size: 22,
                ),
                trailing: const StatusPill(label: 'Form', tone: PillTone.info),
                onTap: () => context.go(Routes.trainerFormsGroups),
              ),
            for (final template in _templates.take(2))
              RowItem(
                title: template.name,
                subtitle: 'Template · updated ${shortDate(template.updatedAt)}',
                leading: Icon(
                  Icons.layers_outlined,
                  color: context.colors.primary,
                  size: 22,
                ),
                trailing: const StatusPill(label: 'Template', tone: PillTone.info),
                onTap: () => context.go(Routes.trainerTemplates),
              ),
            for (final group in groups.take(2))
              RowItem(
                title: group.name,
                subtitle: group.hasRegistrationForm
                    ? 'Group · registration link active'
                    : 'Group',
                leading: Icon(Icons.people_outline, color: tokens.accent, size: 22),
                trailing: const StatusPill(label: 'Group', tone: PillTone.info),
                onTap: () => context.go('${Routes.trainerGroups}/${group.id}'),
              ),
          ],

          if (pending.isNotEmpty) ...[
            SectionHeader(
              title: 'Waiting for review',
              actionLabel: 'Open',
              onAction: () =>
                  context.go('${Routes.trainerFormsGroups}?tab=requests'),
            ),
            for (final submission in pending.take(3))
              RowItem(
                title: submission.applicantName,
                subtitle: 'Submitted ${shortDate(submission.submittedAt)}',
                trailing: const StatusPill(label: 'Pending', tone: PillTone.warn),
                onTap: () =>
                    context.go('${Routes.trainerFormsGroups}?tab=requests'),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});

  final List<(IconData, String, String)> actions;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.05,
      children: [
        for (final (icon, label, route) in actions)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.sm),
            onTap: () => context.go(route),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 24, color: context.colors.primary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: context.text.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
