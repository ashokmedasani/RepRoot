import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/models/template_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/api/templates_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Manage hub — banner + quick-create shortcuts + a Management list of every
/// real destination (Lead Forms/Groups/Templates/Resources/Add
/// Client), plus recent items and pending review below.
/// Replica of mobile/src/app/pages/professional/manage/professional-manage.page.ts,
/// restyled to match the colorful reference mockup. There is deliberately no
/// "Payments" entry here: the real website has no standalone professional-level
/// payments page (checked app.routes.ts — only `client/payments`, scoped to one
/// client, plus a payment-confirmation redirect). Payments stay reachable from
/// the Dashboard's Quick Actions and from each client's own profile.
class ProfessionalManagePage extends ConsumerStatefulWidget {
  const ProfessionalManagePage({super.key});

  @override
  ConsumerState<ProfessionalManagePage> createState() =>
      _ProfessionalManagePageState();
}

class _ProfessionalManagePageState
    extends ConsumerState<ProfessionalManagePage> {
  FormsGroupsOverview? _overview;
  List<TrackingTemplateRecord> _templates = [];
  ProfessionalDataUsage? _usage;
  int _notificationUnread = 0;
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
        } catch (error, stackTrace) {
          debugPrint(
            'Management overview load failed '
            '(${error.runtimeType})\n$stackTrace',
          );
        }
      }(),
      () async {
        try {
          final response = await ref.read(templatesApiProvider).getTemplates();
          if (mounted) setState(() => _templates = response.templates);
        } catch (_) {
          if (mounted) setState(() => _templates = []);
        }
      }(),
      () async {
        try {
          final usage = await ref
              .read(professionalAuthApiProvider)
              .getDataUsage();
          if (mounted) setState(() => _usage = usage);
        } catch (error, stackTrace) {
          debugPrint(
            'Management schedule counts load failed '
            '(${error.runtimeType})\n$stackTrace',
          );
        }
      }(),
      () async {
        try {
          // Just the header badge count — the full inbox is its own page,
          // same pattern as the Dashboard AppBar.
          final inbox = await ref
              .read(professionalAuthApiProvider)
              .getNotifications(limit: 1);
          if (mounted) setState(() => _notificationUnread = inbox.unreadCount);
        } catch (error, stackTrace) {
          debugPrint(
            'Could not load the notification badge (${error.runtimeType}).\n'
            '$stackTrace',
          );
        }
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    final leadForm = overview?.leadForm;
    final groups = overview?.groups ?? const <ProfessionalGroup>[];
    final pending = overview?.pendingForms ?? const <LeadSubmission>[];
    final usage = _usage;
    final tokens = context.tokens;

    final nothingYet =
        leadForm == null && _templates.isEmpty && groups.isEmpty && !_loading;

    return Scaffold(
      // No AppBar — same header shape as every other tab now: eyebrow/title
      // in a row with the page's own action (bell) at top-right, no separate
      // toolbar strip underneath.
      body: SafeArea(
        child: PagePad(
          onRefresh: _load,
          children: [
            // Same eyebrow/title/subtitle header pattern as every other tab —
            // mirrors the web shell's page header (there is no direct web
            // equivalent of this mobile-only hub page, so the copy is written
            // to describe what it really aggregates, not sourced from a
            // specific web string).
            PageHeader(
              eyebrow: 'PROFESSIONAL WORKSPACE',
              title: 'Manage',
              info:
                  'The setup side of your practice — everything you build '
                  'once and then use with clients.\n\n'
                  'Lead forms and groups bring people in. Templates decide '
                  'what clients log. Resources are what you share with them. '
                  'Payment settings configure how you get paid.\n\n'
                  'Day-to-day client work lives in Clients, not here.',
              trailing: NotificationBell(
                unread: _notificationUnread,
                onTap: () => context.push(Routes.professionalNotifications),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _ManagementList(
              rows: [
                _ManagementRow(
                  icon: Icons.description_outlined,
                  accent: MenuAccent.blue,
                  title: 'Lead Forms',
                  subtitle: 'Create and manage your lead forms',
                  count: (overview?.maxLeadForms ?? 0) > 0
                      ? '${overview?.leadForms.length ?? 0}/${overview?.maxLeadForms}'
                      : null,
                  onTap: () => context.go(Routes.professionalFormsGroups),
                ),
                _ManagementRow(
                  icon: Icons.people_outline,
                  accent: MenuAccent.green,
                  title: 'Groups',
                  subtitle: 'Manage client groups and requests',
                  count: usage?.resourceUsage['groups'] != null
                      ? '${usage!.resourceUsage['groups']!.used}'
                            '${usage.resourceUsage['groups']!.limit != null ? '/${usage.resourceUsage['groups']!.limit}' : ''}'
                      : null,
                  onTap: () => context.go(
                    '${Routes.professionalFormsGroups}?tab=groups',
                  ),
                ),
                _ManagementRow(
                  icon: Icons.layers_outlined,
                  accent: MenuAccent.orange,
                  title: 'Templates',
                  subtitle: 'Create and assign templates to clients',
                  count: usage?.resourceUsage['templates'] != null
                      ? '${usage!.resourceUsage['templates']!.used}'
                            '${usage.resourceUsage['templates']!.limit != null ? '/${usage.resourceUsage['templates']!.limit}' : ''}'
                      : null,
                  onTap: () => context.go(Routes.professionalTemplates),
                ),
                _ManagementRow(
                  icon: Icons.folder_open_outlined,
                  accent: MenuAccent.teal,
                  title: 'Resources',
                  subtitle: 'Categories, subcategories and resources',
                  count: usage?.resourceUsage['resources'] != null
                      ? '${usage!.resourceUsage['resources']!.used}'
                            '${usage.resourceUsage['resources']!.limit != null ? '/${usage.resourceUsage['resources']!.limit}' : ''}'
                      : null,
                  onTap: () => context.go(Routes.professionalResources),
                ),
                _ManagementRow(
                  icon: Icons.person_add_alt_outlined,
                  accent: MenuAccent.pink,
                  title: 'Add Client',
                  subtitle: 'Create a new client profile',
                  onTap: () => context.go(Routes.professionalClientCreate),
                ),
              ],
            ),

            const SectionHeader(title: 'Recent items'),
            if (_loading)
              for (var i = 0; i < 3; i++) const SkeletonBox(height: 66)
            else if (nothingYet)
              const EmptyState(
                message:
                    'Create your first form, group, or template to see it here.',
              )
            else ...[
              if (leadForm != null)
                RowItem(
                  title: leadForm.title,
                  subtitle:
                      'Main form · updated ${shortDate(leadForm.updatedAt)}',
                  leading: Icon(
                    Icons.description_outlined,
                    color: tokens.success,
                    size: 22,
                  ),
                  trailing: const StatusPill(
                    label: 'Form',
                    tone: PillTone.info,
                  ),
                  onTap: () => context.go(Routes.professionalFormsGroups),
                ),
              for (final template in _templates.take(2))
                RowItem(
                  title: template.name,
                  subtitle:
                      'Template · updated ${shortDate(template.updatedAt)}',
                  leading: Icon(
                    Icons.layers_outlined,
                    color: context.colors.primary,
                    size: 22,
                  ),
                  trailing: const StatusPill(
                    label: 'Template',
                    tone: PillTone.info,
                  ),
                  onTap: () => context.go(Routes.professionalTemplates),
                ),
              for (final group in groups.take(2))
                RowItem(
                  title: group.name,
                  subtitle: group.hasRegistrationForm
                      ? 'Group · registration link active'
                      : 'Group',
                  leading: Icon(
                    Icons.people_outline,
                    color: tokens.accent,
                    size: 22,
                  ),
                  trailing: const StatusPill(
                    label: 'Group',
                    tone: PillTone.info,
                  ),
                  onTap: () =>
                      context.go('${Routes.professionalGroups}/${group.id}'),
                ),
            ],

            if (pending.isNotEmpty) ...[
              SectionHeader(
                title: 'Waiting for review',
                actionLabel: 'Open',
                onAction: () => context.go(
                  '${Routes.professionalFormsGroups}?tab=requests',
                ),
              ),
              for (final submission in pending.take(3))
                RowItem(
                  title: submission.applicantName,
                  subtitle: 'Submitted ${shortDate(submission.submittedAt)}',
                  trailing: const StatusPill(
                    label: 'Pending',
                    tone: PillTone.warn,
                  ),
                  onTap: () => context.go(
                    '${Routes.professionalFormsGroups}?tab=requests',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row in the Management list — a colorful icon chip, title/subtitle,
/// and an optional real usage-count pill (only shown when the backend
/// actually returns a count for that resource) before the chevron.
class _ManagementRow {
  const _ManagementRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final ({Color fg, Color bg}) accent;
  final String title;
  final String subtitle;
  final String? count;
  final VoidCallback onTap;
}

class _ManagementList extends StatelessWidget {
  const _ManagementList({required this.rows});

  final List<_ManagementRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            InkWell(
              onTap: rows[i].onTap,
              borderRadius: i == 0
                  ? const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.md),
                    )
                  : i == rows.length - 1
                  ? const BorderRadius.vertical(
                      bottom: Radius.circular(AppRadius.md),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.card,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rows[i].accent.bg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        rows[i].icon,
                        size: AppSize.iconRow,
                        color: rows[i].accent.fg,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(rows[i].title, style: context.text.titleSmall),
                          Text(
                            rows[i].subtitle,
                            style: context.text.bodySmall?.copyWith(
                              color: tokens.muted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (rows[i].count != null) ...[
                      StatusPill(label: rows[i].count!, tone: PillTone.info),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Icon(
                      Icons.chevron_right,
                      size: AppSize.iconRow,
                      color: tokens.muted,
                    ),
                  ],
                ),
              ),
            ),
            if (i < rows.length - 1)
              Divider(height: 1, thickness: 1, color: tokens.border),
          ],
        ],
      ),
    );
  }
}
