import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../widgets/app_widgets.dart';
import 'analytics_types.dart';
import 'branded_share.dart';

/// Renders a ChartSpec from the graph engine.
/// Flutter equivalent of mobile/src/app/shared/chart-card.component.ts.
///
/// The engine decides the chart kind; this only draws it. fl_chart is not
/// pixel-identical to Chart.js — per the migration plan the target is data
/// correctness and equivalent readability, not identical rendering.
class ChartCard extends StatefulWidget {
  const ChartCard({super.key, required this.spec, this.shareContext = ''});

  final ChartSpec spec;

  /// Extra context printed on the branded share image, e.g. client or template
  /// name. Falls back to the card's own subtitle when empty.
  final String shareContext;

  @override
  State<ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<ChartCard> {
  /// Wraps only the chart body, so the export gets the graph without the
  /// card's title row — the branded header reprints the title itself.
  final _chartKey = GlobalKey();
  bool _sharing = false;

  String get _subtitle {
    final meta = widget.spec.meta;
    return [
      if (meta?.subtitle.isNotEmpty ?? false) meta!.subtitle,
      // A summary card already prints the unit next to its value, and the unit
      // is usually in the title too ("Body weight (lb)") — three times is noise.
      if (widget.spec.unit.isNotEmpty && widget.spec.kind != ChartKind.summary)
        widget.spec.unit,
      if (meta?.average != null) 'avg ${_trim(meta!.average!)}',
    ].join(' · ');
  }

  Future<void> _share() async {
    // toImage on a boundary that is mid-paint throws; a second tap while the
    // sheet is opening is the easy way to hit that.
    if (_sharing) return;
    setState(() => _sharing = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final shared = await BrandedShare.shareChart(
        boundaryKey: _chartKey,
        title: widget.spec.title,
        subtitle: widget.shareContext.isNotEmpty
            ? widget.shareContext
            : _subtitle,
        brightness: Theme.of(context).brightness,
      );
      if (!shared) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Chart is not ready to share yet.')),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not share this chart.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              spec: widget.spec,
              subtitle: _subtitle,
              // Nothing to export from a single number — matches the Ionic
              // card, which also hides Share on summary specs.
              onShare: widget.spec.kind == ChartKind.summary ? null : _share,
              sharing: _sharing,
            ),
            const SizedBox(height: AppSpacing.md),
            RepaintBoundary(
              key: _chartKey,
              child: _ChartBody(spec: widget.spec),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.spec,
    required this.subtitle,
    required this.sharing,
    this.onShare,
  });

  final ChartSpec spec;
  final String subtitle;
  final bool sharing;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spec.title, style: context.text.titleSmall, maxLines: 2),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(subtitle, style: context.text.bodySmall),
              ],
            ],
          ),
        ),
        if (onShare != null)
          IconButton(
            onPressed: sharing ? null : onShare,
            icon: sharing
                ? SizedBox.square(
                    dimension: AppSize.iconRow,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.tokens.muted,
                      ),
                    ),
                  )
                : const Icon(Icons.ios_share),
            iconSize: AppSize.iconRow,
            tooltip: 'Share chart',
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _ChartBody extends StatelessWidget {
  const _ChartBody({required this.spec});

  final ChartSpec spec;

  static const double _height = 180;

  @override
  Widget build(BuildContext context) {
    if (spec.kind == ChartKind.summary) return _Summary(spec: spec);
    if (spec.kind == ChartKind.ring) return _Ring(spec: spec);

    if (spec.data.isEmpty) {
      return const EmptyState(message: 'No data for this range yet.');
    }

    return SizedBox(
      height: _height,
      child: switch (spec.kind) {
        ChartKind.line => _LineChart(spec: spec),
        ChartKind.bar => _BarChart(spec: spec),
        ChartKind.hbar => _HBarChart(spec: spec),
        ChartKind.pie => _PieChart(spec: spec),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// Palette for multi-series charts (pie slices, hbar rows).
List<Color> _palette(BuildContext context) {
  final colors = context.colors;
  final tokens = context.tokens;
  return [
    colors.primary,
    tokens.accent,
    tokens.success,
    tokens.primaryStrong,
    colors.error,
    tokens.muted,
  ];
}

String _trim(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toStringAsFixed(1);
}

/// fl_chart labels the axis max *and* every interval tick, so the max label
/// collides with the tick just below it (31.9 drawn over 30). Drop the max
/// label; the top gridline reads fine without it.
Widget Function(double, TitleMeta) _leftTitle(
  BuildContext context,
  AppTokens tokens,
) {
  return (value, meta) {
    if (value == meta.max) return const SizedBox.shrink();
    return Text(
      _trim(value),
      style: context.text.labelSmall?.copyWith(color: tokens.muted),
    );
  };
}

class _Summary extends StatelessWidget {
  const _Summary({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final meta = spec.meta;
    final value = meta?.valueText.isNotEmpty ?? false
        ? meta!.valueText
        : _trim(meta?.value ?? 0);
    final delta = meta?.delta;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(value, style: context.text.displaySmall),
        if (meta?.unit.isNotEmpty ?? false) ...[
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(meta!.unit, style: context.text.bodySmall),
          ),
        ],
        const Spacer(),
        if (delta != null && (meta?.deltaText.isNotEmpty ?? false))
          StatusPill(
            label: meta!.deltaText,
            tone: delta > 0
                ? PillTone.good
                : delta < 0
                ? PillTone.bad
                : PillTone.neutral,
          ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final percent = (spec.meta?.percent ?? 0).clamp(0, 100).toDouble();
    final colors = context.colors;

    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: 140,
            child: PieChart(
              PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 0,
                centerSpaceRadius: 44,
                sections: [
                  PieChartSectionData(
                    value: percent,
                    color: colors.primary,
                    radius: 14,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: 100 - percent,
                    color: context.tokens.surfaceSoft,
                    radius: 14,
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${_trim(percent)}%', style: context.text.displaySmall),
              Text('completed', style: context.text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tokens = context.tokens;
    final points = spec.data;
    final bounds = _paddedBounds(points);
    final interval = _labelInterval(points.length);
    final last = points.length - 1;

    return LineChart(
      LineChartData(
        minY: bounds.min,
        maxY: bounds.max,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: _leftTitle(context, tokens),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: interval,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                // Same trap as the left axis: fl_chart labels the axis max on
                // top of the interval sequence. The last point sits hard on the
                // plot's right edge, so its label is both half outside the card
                // (it exported as "7/") and printed over the interval tick a
                // day or two behind it. Drop it — the tick before it reads fine
                // and a tap still gives the exact date.
                if (index == last) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    points[index].label,
                    style: context.text.labelSmall?.copyWith(
                      color: tokens.muted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              final point = points[spot.x.toInt()];
              return LineTooltipItem(
                '${_trim(point.value)}${spec.unit.isNotEmpty ? ' ${spec.unit}' : ''}\n${point.tooltip.isNotEmpty ? point.tooltip : point.label}',
                context.text.labelSmall!.copyWith(color: colors.surface),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            color: colors.primary,
            barWidth: 2.5,
            dotData: FlDotData(show: points.length <= 20),
            belowBarData: BarAreaData(
              show: true,
              color: colors.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps the x-axis readable on a phone by thinning labels on long series.
  double _labelInterval(int count) =>
      count <= 8 ? 1 : (count / 6).ceilToDouble();

  /// fl_chart fits the y-axis exactly to the data, which puts the highest point
  /// on the top edge — and since the line is curved, the spline overshoots that
  /// point and gets clipped, so every peak rendered with a flat top. Chart.js
  /// rounds its scale outward to nice bounds, which is why the Ionic chart never
  /// showed this; padding the range gives the same breathing room.
  ({double min, double max}) _paddedBounds(List<DataPoint> points) {
    var low = points.first.value;
    var high = points.first.value;
    for (final point in points) {
      if (point.value < low) low = point.value;
      if (point.value > high) high = point.value;
    }

    final span = high - low;
    // A flat series has no span to scale the padding from — fall back to the
    // value itself so the line sits mid-plot instead of on a zero-height axis.
    final pad = span > 0
        ? span * 0.12
        : high.abs() > 0
        ? high.abs() * 0.1
        : 1.0;

    return (
      // Counts and durations are never negative; don't invent an axis that says
      // they could be.
      min: low >= 0 && low - pad < 0 ? 0 : low - pad,
      max: high + pad,
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tokens = context.tokens;
    final points = spec.data;

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: _leftTitle(context, tokens),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // Category labels can be words ("Profile edits"), not just dates,
              // so they need room for two lines and a hard width cap —
              // unconstrained they run into the neighbouring label.
              reservedSize: 38,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: SizedBox(
                    width: 62,
                    child: Text(
                      points[index].label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelSmall?.copyWith(
                        color: tokens.muted,
                        fontSize: 9.5,
                        height: 1.15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) {
              final point = points[group.x];
              return BarTooltipItem(
                '${_trim(point.value)}${spec.unit.isNotEmpty ? ' ${spec.unit}' : ''}\n${point.tooltip.isNotEmpty ? point.tooltip : point.label}',
                context.text.labelSmall!.copyWith(color: colors.surface),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].value,
                  color: colors.primary,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Horizontal bars — used for rating distributions and response breakdowns,
/// where labels are text and need room to read.
class _HBarChart extends StatelessWidget {
  const _HBarChart({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final points = spec.data;
    final palette = _palette(context);
    final max = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < points.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(
                      points[i].label,
                      style: context.text.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        // Guard against a divide-by-zero when every bar is 0.
                        value: max <= 0 ? 0 : points[i].value / max,
                        minHeight: 12,
                        backgroundColor: context.tokens.surfaceSoft,
                        valueColor: AlwaysStoppedAnimation(
                          palette[i % palette.length],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 28,
                    child: Text(
                      _trim(points[i].value),
                      style: context.text.labelSmall,
                      textAlign: TextAlign.right,
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

class _PieChart extends StatelessWidget {
  const _PieChart({required this.spec});

  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final points = spec.data;
    final palette = _palette(context);
    final total = points.fold<double>(0, (sum, p) => sum + p.value);

    return Row(
      children: [
        SizedBox(
          width: 150,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                for (var i = 0; i < points.length; i++)
                  PieChartSectionData(
                    value: points[i].value,
                    color: palette[i % palette.length],
                    radius: 44,
                    title: total <= 0
                        ? ''
                        : '${(points[i].value / total * 100).round()}%',
                    titleStyle: context.text.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < points.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs + 2),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: palette[i % palette.length],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            points[i].label,
                            style: context.text.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _trim(points[i].value),
                          style: context.text.labelSmall?.copyWith(
                            color: context.tokens.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
