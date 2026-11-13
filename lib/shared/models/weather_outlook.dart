import 'weather_forecast.dart';

/// What the forecast means for the day at the shop, in one line: when it
/// rains, and whatever else is out of the ordinary.
///
/// The numbers are in the chart; this is the sentence someone would say after
/// reading it. It only states what the series holds: MET gives millimetres,
/// not a chance of rain, so it never invents one.
class WeatherOutlook {
  const WeatherOutlook({
    required this.kind,
    required this.headline,
    this.note,
  });

  /// An hour counts as rain from here; below it is the model's drizzle noise.
  static const double rainPerHour = 0.2;

  /// A day counts as rainy from here.
  static const double rainPerDay = 1.0;

  /// Mean wind, in metres per second, that a cyclist calls strong (36 km/h).
  static const double strongWind = 10;

  static const double hotTemperature = 30;
  static const double coldTemperature = 3;

  factory WeatherOutlook.of(WeatherForecast forecast, DateTime now) {
    final zone = forecast.place.zone;
    // The series is hourly for about two and a half days. The last point only
    // closes the hour before it: nothing says what falls after it.
    final reach = forecast.hoursFrom(now, count: 60);
    final hours = reach.isEmpty ? reach : reach.sublist(0, reach.length - 1);
    bool wet(int index) =>
        index < hours.length && hours[index].precipitation >= rainPerHour;
    // Rain ends where two dry hours follow each other; a dry hour at the very
    // end of what is known is not an end yet.
    int endOfRain(int from) {
      for (var index = from; index + 1 < hours.length; index++) {
        if (!wet(index) && !wet(index + 1)) return index;
      }
      return hours.length;
    }

    double total(int from, int to) {
      var sum = 0.0;
      for (var index = from; index < to && index < hours.length; index++) {
        sum += hours[index].precipitation;
      }
      return sum;
    }

    final note = _note(forecast, now);

    if (hours.isNotEmpty && wet(0)) {
      final end = endOfRain(1);
      final amount = _about(total(0, end));
      return WeatherOutlook(
        kind: WeatherOutlookKind.raining,
        headline: end >= hours.length
            ? 'Lluvia sin pausa en los próximos días ($amount)'
            : 'Lluvia hasta ${_when(hours[end].time, now, zone, bare: true)} '
                '($amount)',
        note: note,
      );
    }

    for (var start = 1; start < hours.length; start++) {
      if (!wet(start)) continue;
      final end = endOfRain(start + 1);
      final amount = total(start, end);
      final soon = start <= 24;
      final brief = amount < rainPerDay && end - start <= 3;
      return WeatherOutlook(
        kind: soon ? WeatherOutlookKind.rainSoon : WeatherOutlookKind.rainLater,
        headline: brief
            ? 'Puede lloviznar ${_when(hours[start].time, now, zone)}'
            : 'Lluvia desde ${_when(hours[start].time, now, zone, bare: true)} '
                '(${_about(amount)})',
        note: note,
      );
    }

    final lastHour = hours.isEmpty ? now.toUtc() : hours.last.time;
    final days = forecast.daysAfter(now);
    for (final day in days) {
      if (day.precipitation < rainPerDay) continue;
      final dayEnd = forecast.place.zone
          .utcOf(day.date.year, day.date.month, day.date.day)
          .add(const Duration(hours: 24));
      // The hours above already said this day is dry.
      if (!dayEnd.isAfter(lastHour)) continue;
      return WeatherOutlook(
        kind: WeatherOutlookKind.dry,
        headline: 'Sin lluvia hasta el ${weatherWeekday(day.date)}',
        note: note,
      );
    }
    return WeatherOutlook(
      kind: WeatherOutlookKind.dry,
      headline: days.length < 2
          ? 'Sin lluvia a la vista'
          : 'Sin lluvia en los próximos ${days.length} días',
      note: note,
    );
  }

  final WeatherOutlookKind kind;

  /// About rain.
  final String headline;

  /// Strong wind, heat or cold in the next day, when there is any.
  final String? note;

  static String? _note(WeatherForecast forecast, DateTime now) {
    final zone = forecast.place.zone;
    final day = forecast.hoursFrom(now, count: 24);
    if (day.isEmpty) return null;
    // The server sends no wind when it does not stand behind the forecast's.
    WeatherHour? windiest;
    var hottest = day.first;
    var coldest = day.first;
    for (final hour in day) {
      final speed = hour.windSpeed;
      if (speed != null && speed > (windiest?.windSpeed ?? 0)) windiest = hour;
      if (hour.temperature > hottest.temperature) hottest = hour;
      if (hour.temperature < coldest.temperature) coldest = hour;
    }
    String at(WeatherHour hour) =>
        identical(hour, day.first) ? 'ahora' : _when(hour.time, now, zone);
    if (windiest != null && windiest.windSpeed! >= strongWind) {
      final from = windiest.windFromDirection;
      return 'Viento fuerte ${at(windiest)}: '
          '${windiest.windKilometresPerHour!.round()} km/h'
          '${from == null ? '' : ' del ${weatherCompassWords(from)}'}';
    }
    if (hottest.temperature >= hotTemperature) {
      return 'Calor ${at(hottest)}: ${weatherDegrees(hottest.temperature)}';
    }
    if (coldest.temperature <= coldTemperature) {
      return 'Frío ${at(coldest)}: ${weatherDegrees(coldest.temperature)}';
    }
    return null;
  }

  /// «a las 15:00», «mañana a las 9:00», «el sábado a las 9:00». With [bare],
  /// today's hour comes without its «a», for «desde las 15:00» and «hasta la
  /// 1:00».
  static String _when(
    DateTime instant,
    DateTime now,
    WeatherZone zone, {
    bool bare = false,
  }) {
    final today = zone.local(now);
    final then = zone.local(instant);
    final clock = '${then.hour == 1 ? 'la' : 'las'} ${_clockOf(then)}';
    // Calendar days apart; in hours so a clock change cannot shift it.
    final hoursApart = DateTime(then.year, then.month, then.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inHours;
    if (hoursApart < 12) return bare ? clock : 'a $clock';
    if (hoursApart < 36) return 'mañana a $clock';
    return 'el ${weatherWeekday(then)} a $clock';
  }

  /// A forecast amount is an estimate, and the sentence says so.
  static String _about(double millimetres) {
    if (millimetres < 1) return weatherMillimetres(millimetres);
    // «unos 1 mm» does not agree in number.
    final approximately = millimetres.round() == 1 ? 'cerca de' : 'unos';
    return '$approximately ${weatherMillimetres(millimetres)}';
  }
}

enum WeatherOutlookKind { raining, rainSoon, rainLater, dry }

const _weekdays = <String>[
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

const _weekdaysShort = <String>[
  'lun',
  'mar',
  'mié',
  'jue',
  'vie',
  'sáb',
  'dom'
];

const _compass = <String>['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];

const _compassWords = <String>[
  'norte',
  'noreste',
  'este',
  'sureste',
  'sur',
  'suroeste',
  'oeste',
  'noroeste',
];

int _compassIndex(double degrees) => (((degrees % 360) + 22.5) ~/ 45) % 8;

/// Where the wind comes from, in the eight points a person says.
String weatherCompass(double degrees) => _compass[_compassIndex(degrees)];

String weatherCompassWords(double degrees) =>
    _compassWords[_compassIndex(degrees)];

String weatherWeekday(DateTime date) => _weekdays[date.weekday - 1];

String weatherWeekdayShort(DateTime date) => _weekdaysShort[date.weekday - 1];

/// A whole degree; a value that rounds to zero never reads «-0°».
String weatherDegrees(double celsius) {
  final rounded = celsius.round();
  return '${rounded == 0 ? 0 : rounded}°';
}

/// «menos de 1 mm» below one, whole millimetres above.
String weatherMillimetres(double millimetres) {
  if (millimetres < 1) return 'menos de 1 mm';
  return '${millimetres.round()} mm';
}

/// The hour on the shop's clock, as «9:00» or «15:00».
String weatherShopClock(
  DateTime instant, [
  WeatherZone zone = const WeatherZone.shop(),
]) =>
    _clockOf(zone.local(instant));

/// «9:00» from a moment already on the place's clock.
String _clockOf(DateTime local) =>
    '${local.hour}:${local.minute.toString().padLeft(2, '0')}';

/// The World Health Organization's bands for the UV index.
String weatherUvBand(double index) {
  final value = index.round();
  if (value >= 11) return 'extremo';
  if (value >= 8) return 'muy alto';
  if (value >= 6) return 'alto';
  if (value >= 3) return 'moderado';
  return 'bajo';
}
