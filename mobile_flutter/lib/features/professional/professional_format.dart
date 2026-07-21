/// Date/number formatting shared across the trainer screens — the Flutter
/// equivalents of the Angular `date:` pipes used in the Ionic templates.
///
/// These parse date-only strings as local, deliberately: see FIX #2 in
/// graph_engine.dart for why the TS's `new Date(iso)` shifts a day west of UTC.
library;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `date: 'dd MMM'` -> "15 Jul"
String shortDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]}';
}

/// `date: 'EEE dd MMM'` -> "Wed 15 Jul"
String weekdayDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[date.weekday - 1]} ${date.day.toString().padLeft(2, '0')} '
      '${_months[date.month - 1]}';
}

/// `date: 'dd MMM yyyy'` -> "15 Jul 2026"
String longDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  return '${date.day.toString().padLeft(2, '0')} ${_months[date.month - 1]} ${date.year}';
}

/// "15 Jul, 14:30" — for timestamps.
String dateTimeLabel(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  final local = date.isUtc ? date.toLocal() : date;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${shortDate(iso)}, $hh:$mm';
}

/// Trims a backend "HH:mm:ss" to "HH:mm"; empty stays empty.
String hhmm(String time) =>
    time.length >= 5 ? time.substring(0, 5) : time;

/// "Any time" when a reminder has no clock time, matching the Ionic template.
String timeOrAnytime(String time) => time.isEmpty ? 'Any time' : hhmm(time);

/// Human byte size for storage/usage displays.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final rounded = value >= 10 || unit == 0
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$rounded ${units[unit]}';
}

/// Drops a trailing ".0" so 3.0 prints as "3" — JS number semantics.
String trimNumber(num value) {
  if (value is int) return value.toString();
  final d = value.toDouble();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return d.toString();
}

/// Sentence-cases a backend enum like 'daily' -> 'Daily'.
String titleCase(String value) =>
    value.isEmpty ? '' : value[0].toUpperCase() + value.substring(1);
