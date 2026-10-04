import 'dart:convert';

/// Days in the order the store lists them, as Google Business names them.
const List<String> publicBusinessDays = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

/// One opening span of one day, with times as `HH:MM`.
class PublicBusinessHoursPeriod {
  const PublicBusinessHoursPeriod({
    required this.day,
    required this.opens,
    required this.closes,
  });

  /// One of [publicBusinessDays].
  final String day;
  final String opens;
  final String closes;
}

/// The opening hours saved in `business_hours_json` (the ERP's «Horario del
/// local») or `google_business_regular_hours`, in either shape they arrive:
/// Google Places (`open: {day: 1, time: "1030"}`, Sunday = 0) or Google
/// Business (`openDay: "MONDAY", openTime: {hours, minutes}`).
///
/// Dart puro: lo leen la página de contacto y el generador de snapshots, que
/// declara el mismo horario en los datos estructurados del negocio. Nothing
/// readable returns an empty list; a day without a period is closed.
List<PublicBusinessHoursPeriod> parsePublicBusinessHours(String rawJson) {
  if (rawJson.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) return const [];
    final data = decoded['opening_hours'] is Map
        ? decoded['opening_hours'] as Map
        : decoded;
    final periods = data['periods'];
    if (periods is! List) return const [];

    final result = <PublicBusinessHoursPeriod>[];
    for (final rawPeriod in periods) {
      if (rawPeriod is! Map) continue;
      String? day;
      String? opens;
      String? closes;
      if (rawPeriod.containsKey('openDay') ||
          rawPeriod.containsKey('openTime')) {
        day = rawPeriod['openDay']?.toString().toUpperCase();
        opens = _businessTime(rawPeriod['openTime']);
        closes = _businessTime(rawPeriod['closeTime']);
      } else {
        final open = rawPeriod['open'];
        final close = rawPeriod['close'];
        day = open is Map ? _placesDay(open['day']) : null;
        opens = open is Map ? _placesTime(open['time']) : null;
        closes = close is Map ? _placesTime(close['time']) : null;
      }
      if (day == null ||
          !publicBusinessDays.contains(day) ||
          !_isTimeOfDay(opens) ||
          !_isTimeOfDay(closes)) {
        continue;
      }
      result.add(
        PublicBusinessHoursPeriod(day: day, opens: opens!, closes: closes!),
      );
    }
    return List.unmodifiable(result);
  } on Object {
    // A malformed value (a string where Google sends a number) leaves the
    // hours unknown, as `/contacto` always did; it never breaks the page or
    // the store build.
    return const [];
  }
}

/// 00:00 to 23:59, or 24:00 for a span that closes at midnight (Google
/// Business allows both ends of `00:00–24:00`).
bool _isTimeOfDay(String? time) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time ?? '');
  if (match == null) return false;
  final hours = int.parse(match.group(1)!);
  final minutes = int.parse(match.group(2)!);
  return (hours < 24 && minutes < 60) || (hours == 24 && minutes == 0);
}

String? _placesDay(Object? rawDay) {
  final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
  return switch (day) {
    0 => 'SUNDAY',
    1 => 'MONDAY',
    2 => 'TUESDAY',
    3 => 'WEDNESDAY',
    4 => 'THURSDAY',
    5 => 'FRIDAY',
    6 => 'SATURDAY',
    _ => null,
  };
}

/// Google Business sends a `TimeOfDay` that omits a zero field (`{hours:
/// 10}` is 10:00, `{}` is midnight); anything else that is not a whole hour
/// and minute of the day is not a time.
String? _businessTime(Object? rawTime) {
  if (rawTime is String) return _placesTime(rawTime);
  if (rawTime is! Map) return null;
  final hours = rawTime['hours'] ?? 0;
  final minutes = rawTime['minutes'] ?? 0;
  if (hours is! int || minutes is! int || hours < 0 || minutes < 0) {
    return null;
  }
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

String? _placesTime(Object? rawTime) {
  final digits = rawTime?.toString().trim();
  if (digits == null || digits.isEmpty) return null;
  if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(digits)) {
    return digits.padLeft(5, '0');
  }
  if (!RegExp(r'^\d{3,4}$').hasMatch(digits)) return null;
  final padded = digits.padLeft(4, '0');
  return '${padded.substring(0, 2)}:${padded.substring(2, 4)}';
}
