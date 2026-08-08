/// Date/number formatting shared across the professional screens — the Flutter
/// equivalents of the Angular `date:` pipes used in the Ionic templates.
///
/// These parse date-only strings as local, deliberately: see FIX #2 in
/// graph_engine.dart for why the TS's `new Date(iso)` shifts a day west of UTC.
library;

import 'package:flutter/material.dart' show TimeOfDay;

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A [DateTime]'s **local** calendar day as `YYYY-MM-DD`.
///
/// Deliberately built from `.year`/`.month`/`.day` rather than
/// `toIso8601String()`, for the same reason the web's `toISOString()` was
/// wrong: any UTC round-trip lands on the neighbouring day for part of every
/// day outside UTC. Entry dates, reminder dates and payment dates are all
/// local calendar days, so they must be formatted locally to compare
/// correctly against what the backend stores.
///
/// This lived as six identical private copies across the feature pages; it is
/// centralised here so a future edit can't fix one and miss the rest.
String isoDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Today's local calendar day as `YYYY-MM-DD`.
String todayIso() => isoDate(DateTime.now());

/// A [TimeOfDay] as the backend's `HH:mm`.
String isoTime(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

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
