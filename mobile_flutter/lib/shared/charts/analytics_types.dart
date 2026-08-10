/// Shared analytics contracts — 1:1 port of
/// mobile/src/app/shared/analytics/analytics.types.ts.
///
/// The graph engine turns template fields + entries into ChartSpec objects, and
/// ChartCard draws whichever chart the spec asks for. Keep this the single
/// source of truth for chart data shapes.
library;

enum ChartKind { line, bar, hbar, pie, ring, summary }

class DataPoint {
  const DataPoint({
    required this.label,
    required this.value,
    this.tooltip = '',
  });

  final String label;
  final double value;
  final String tooltip;

  @override
  bool operator ==(Object other) =>
      other is DataPoint &&
      other.label == label &&
      other.value == value &&
      other.tooltip == tooltip;

  @override
  int get hashCode => Object.hash(label, value, tooltip);

  @override
  String toString() => 'DataPoint($label, $value)';
}

class ChartMeta {
  const ChartMeta({
    this.average,
    this.total,
    this.percent,
    this.value,
    this.valueText = '',
    this.unit = '',
    this.delta,
    this.deltaText = '',
    this.subtitle = '',
  });

  final double? average;
  final double? total;
  final double? percent;
  final double? value;
  final String valueText;
  final String unit;
  final double? delta;
  final String deltaText;
  final String subtitle;
}

class ChartSpec {
  const ChartSpec({
    required this.kind,
    required this.title,
    this.unit = '',
    this.data = const [],
    this.meta,
  });

  final ChartKind kind;
  final String title;
  final String unit;
  final List<DataPoint> data;
  final ChartMeta? meta;
}

/// Minimal field shape the engine understands (matches TemplateField).
class FieldLike {
  const FieldLike({
    this.key = '',
    required this.label,
    required this.fieldType,
    this.options = const [],
    this.scale,
  });

  final String key;
  final String label;

  /// 'number' | 'rating' | 'yes_no' | 'dropdown' | 'short_text' | 'long_text'
  final String fieldType;
  final List<String> options;
  final int? scale;
}

/// Minimal entry shape the engine understands (matches TrackingEntryRecord).
class EntryLike {
  const EntryLike({
    required this.entryDate,
    this.entryTime = '',
    this.answers = const {},
    this.createdAt = '',
  });

  /// ISO date, e.g. 2026-07-15
  final String entryDate;

  /// HH:mm[:ss]
  final String entryTime;
  final Map<String, String> answers;
  final String createdAt;
}

/// Days window; 0 means "all data". The TS union type `7 | 30 | 90 | 0` has no
/// Dart equivalent, so these are the intended values.
class DateRange {
  const DateRange._();

  static const int week = 7;
  static const int month = 30;
  static const int quarter = 90;
  static const int all = 0;
}
