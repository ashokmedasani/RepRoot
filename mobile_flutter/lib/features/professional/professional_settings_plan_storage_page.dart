import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/models/professional_models.dart';
import '../../core/api/professional_auth_api.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_widgets.dart';
import 'professional_format.dart';

/// Plan & Storage ("Data Usage" on the Settings menu) — usage stats, progress
/// bar, lock/grace-period messaging, storage breakdown rows, and the one
/// entry point into the Recycle Bin (moved off the Settings landing page —
/// see professional_settings_page.dart).
/// Split out of the former single-scroll professional_settings_page.dart.
class ProfessionalSettingsPlanStoragePage extends ConsumerStatefulWidget {
  const ProfessionalSettingsPlanStoragePage({super.key});

  @override
  ConsumerState<ProfessionalSettingsPlanStoragePage> createState() =>
      _ProfessionalSettingsPlanStoragePageState();
}

class _ProfessionalSettingsPlanStoragePageState
    extends ConsumerState<ProfessionalSettingsPlanStoragePage> {
  ProfessionalDataUsage? _usage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(professionalAuthApiProvider);
    try {
      final usage = await api.getDataUsage();
      if (mounted) setState(() => _usage = usage);
    } catch (_) {}
  }

  double get _usagePercent => ((_usage?.usagePercent ?? 0) * 10).round() / 10;

  /// Storage breakdown as real columns rather than one joined string.
  ///
  /// These used to be rendered as "Chat · 1,204 records · 12 MB · 8%" on a
  /// single line, so nothing lined up between rows and the numbers were
  /// impossible to compare down the column — which is the entire point of a
  /// breakdown. Now it's a table: section, records, size, share.
  ///
  /// The size column only exists on Pro/Premium: data_usage._sanitize_sections
  /// omits `total_bytes` on Free, so rendering "0 B" there would state a
  /// falsehood rather than an absence.
  List<_StorageRow> get _storageRows {
    final usage = _usage;
    if (usage == null) return const [];
    return [
      for (final entry in usage.sections.entries)
        _StorageRow(
          label: ProfessionalUsageSection.labelFor(entry.key),
          records: entry.value.recordCount,
          size: usage.hasSectionBytes
              ? (entry.value.totalBytes == null
                  ? '—'
                  : formatBytes(entry.value.totalBytes!))
              : null,
          percent: (entry.value.percentOfQuota * 10).round() / 10,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Usage'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: PagePad(
        onRefresh: _load,
        children: [
          const SettingsHeroCard(
            icon: Icons.storage_outlined,
            title: 'Data Usage',
            subtitle: 'View storage and data usage details.',
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            title: 'Plan & Storage',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _KvList(
                  rows: [
                    ('Plan', _usage?.planName.isNotEmpty ?? false ? _usage!.planName : '—'),
                    ('Storage used', '$_usagePercent%'),
                    if ((_usage?.usageLabel ?? '').isNotEmpty)
                      ('Capacity', titleCase(_usage!.usageLabel)),
                    (
                      'Records',
                      '${_usage?.recordCount ?? 0}'
                          '${_usage != null && _usage!.totalBytes > 0 ? ' · ${formatBytes(_usage!.totalBytes)}' : ''}'
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_usagePercent / 100).clamp(0, 1),
                    minHeight: 10,
                    backgroundColor: tokens.surfaceSoft,
                    color: _usage?.isDanger ?? false
                        ? context.colors.error
                        : _usage?.isWarning ?? false
                            ? tokens.accent
                            : context.colors.primary,
                  ),
                ),
                if (_usage?.isLocked ?? false) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _usage!.lockReason.isNotEmpty
                        ? _usage!.lockReason
                        : 'Uploads are paused — you are over your storage quota.',
                    style: context.text.bodySmall?.copyWith(color: context.colors.error),
                  ),
                ] else if (_usage?.gracePeriodEndsAt != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Grace period ends ${shortDate(_usage!.gracePeriodEndsAt!)}.',
                    style: context.text.bodySmall?.copyWith(color: tokens.accent),
                  ),
                ],
                if (_storageRows.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _usage!.hasSectionBytes
                        ? 'WHAT IS USING YOUR STORAGE'
                        : 'STORAGE BREAKDOWN',
                    style: context.text.labelSmall?.copyWith(
                      color: tokens.muted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StorageTable(rows: _storageRows),
                  if (_usage!.hasSectionBytes)
                    Text(
                      'Sizes are included with your ${_usage!.planName} plan.',
                      style: context.text.bodySmall?.copyWith(color: tokens.muted),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          ColorfulMenuCard(
            items: [
              ColorfulMenuItem(
                icon: Icons.delete_outline,
                accent: MenuAccent.orange,
                label: 'Recycle Bin',
                subtitle: 'Restore or permanently delete recently-deleted items',
                onTap: () => context.push(Routes.professionalSettingsRecycleBin),
              ),
            ],
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

/// Label/value rows — the .kv-list rule.
class _KvList extends StatelessWidget {
  const _KvList({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(label, style: context.text.bodySmall),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    value.trim().isEmpty ? '—' : value,
                    style: context.text.titleSmall,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}


/// One row of the storage breakdown.
class _StorageRow {
  const _StorageRow({
    required this.label,
    required this.records,
    required this.size,
    required this.percent,
  });

  final String label;
  final int records;

  /// Null on plans where the backend withholds byte totals.
  final String? size;
  final double percent;
}

/// Fixed-width columns so figures line up vertically and can be compared at a
/// glance. Flex weights rather than a DataTable: this has to survive a 360pt
/// screen without horizontal scrolling.
class _StorageTable extends StatelessWidget {
  const _StorageTable({required this.rows});

  final List<_StorageRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final showSize = rows.any((r) => r.size != null);

    Widget cell(String text, {required int flex, TextAlign align = TextAlign.right, TextStyle? style}) =>
        Expanded(
          flex: flex,
          child: Text(
            text,
            textAlign: align,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );

    final headerStyle = context.text.labelSmall?.copyWith(
      color: tokens.muted,
      letterSpacing: 0.4,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            children: [
              cell('SECTION', flex: 5, align: TextAlign.left, style: headerStyle),
              cell('RECORDS', flex: 3, style: headerStyle),
              if (showSize) cell('SIZE', flex: 3, style: headerStyle),
              cell('SHARE', flex: 2, style: headerStyle),
            ],
          ),
        ),
        Divider(color: tokens.border, height: 1),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                cell(row.label,
                    flex: 5,
                    align: TextAlign.left,
                    style: context.text.bodyMedium),
                cell('${row.records}', flex: 3, style: context.text.bodyMedium),
                if (showSize)
                  cell(row.size ?? '—', flex: 3, style: context.text.bodyMedium),
                cell('${trimNumber(row.percent)}%',
                    flex: 2,
                    style: context.text.bodyMedium?.copyWith(
                      color: tokens.muted,
                    )),
              ],
            ),
          ),
      ],
    );
  }
}
