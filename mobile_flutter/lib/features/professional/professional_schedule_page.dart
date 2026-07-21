import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/forms_groups_api.dart';
import '../../core/api/models/forms_groups_models.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Full schedule overview: every pending reminder, soonest first.
/// Replica of mobile/src/app/pages/professional/schedule/professional-schedule.page.ts.
class ProfessionalSchedulePage extends ConsumerStatefulWidget {
  const ProfessionalSchedulePage({super.key});

  @override
  ConsumerState<ProfessionalSchedulePage> createState() => _ProfessionalSchedulePageState();
}

class _ProfessionalSchedulePageState extends ConsumerState<ProfessionalSchedulePage> {
  List<ClientReminder> _reminders = [];
  ScheduleSummary? _summary;
  String _message = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final upcoming = await ref.read(formsGroupsApiProvider).getUpcomingReminders();
      if (!mounted) return;
      setState(() {
        _reminders = upcoming.reminders;
        _summary = upcoming.summary;
        _message = '';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Could not load schedules.';
        _loading = false;
      });
    }
  }

  Future<void> _complete(ClientReminder reminder) async {
    try {
      await ref
          .read(formsGroupsApiProvider)
          .updateReminder(reminder.id, status: ReminderStatus.done);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${reminder.title} marked done.')),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not update the schedule.');
    }
  }

  Future<void> _remove(ClientReminder reminder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete schedule?'),
        content: Text('"${reminder.title}" for ${reminder.clientName} will be removed.'),
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
      await ref.read(formsGroupsApiProvider).deleteReminder(reminder.id);
      if (!mounted) return;
      // Drop locally rather than refetching, matching the Ionic page.
      setState(() => _reminders =
          _reminders.where((item) => item.id != reminder.id).toList());
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not delete the schedule.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        leading: BackButton(onPressed: () => context.go(Routes.professionalManage)),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          KpiGrid(
            children: [
              KpiTile(label: 'Pending', value: '${summary?.totalPending ?? 0}'),
              KpiTile(
                label: 'Due 24 hours',
                value: '${summary?.due24Hours ?? 0}',
                valueColor: context.colors.primary,
              ),
              KpiTile(label: 'Due 7 days', value: '${summary?.due7Days ?? 0}'),
              KpiTile(
                label: 'Completed (7d)',
                value: '${summary?.completedLast7Days ?? 0}',
                valueColor: tokens.success,
              ),
            ],
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorNote(message: _message, onRetry: _load),
          ],

          const SectionHeader(title: 'Upcoming'),
          if (_loading)
            for (var i = 0; i < 4; i++) const SkeletonBox(height: 70)
          else if (_reminders.isEmpty)
            const EmptyState(
              compact: false,
              icon: Icons.event_available_outlined,
              message: "Nothing scheduled.\nAdd follow-ups from a client's page.",
            )
          else
            for (final reminder in _reminders)
              _ReminderRow(
                reminder: reminder,
                onComplete: () => _complete(reminder),
                onDelete: () => _remove(reminder),
                onOpenClient: () =>
                    context.go('${Routes.professionalClients}/${reminder.client}'),
              ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.onComplete,
    required this.onDelete,
    required this.onOpenClient,
  });

  final ClientReminder reminder;
  final VoidCallback onComplete;
  final VoidCallback onDelete;
  final VoidCallback onOpenClient;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final when = [
      weekdayDate(reminder.date),
      if (reminder.time.isNotEmpty) hhmm(reminder.time),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.card,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reminder.title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: onOpenClient,
                          child: Text(
                            reminder.clientName,
                            style: context.text.bodySmall?.copyWith(
                              color: context.colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Text(' · $when', style: context.text.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onComplete,
              icon: const Icon(Icons.check),
              iconSize: AppSize.iconRow,
              color: tokens.success,
              tooltip: 'Mark done',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              iconSize: AppSize.iconRow,
              color: context.colors.error,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
