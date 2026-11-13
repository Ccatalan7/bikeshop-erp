import 'dart:math' as math;

import '../utils/shop_time.dart';
import '../utils/solar_times.dart';

/// How much of the sky the clouds take.
enum WeatherSky { clear, fair, partlyCloudy, cloudy, fog }

enum WeatherPrecipitation { none, rain, sleet, snow }

enum WeatherIntensity { light, moderate, heavy }

/// What a symbol says about the sky, taken apart so the words and the drawing
/// come from the same reading.
///
/// The server names the sky with MET Norway's symbols, which are built by
/// composition (`lightrainshowers_day`, `heavysnowandthunder`). They are read
/// by their parts instead of from a table that would miss the next one.
/// Whether it is day or night is not taken from the symbol: the app knows
/// where the sun is ([SolarTimes]).
class WeatherCondition {
  const WeatherCondition({
    required this.code,
    required this.sky,
    this.precipitation = WeatherPrecipitation.none,
    this.intensity = WeatherIntensity.moderate,
    this.showers = false,
    this.thunder = false,
  });

  factory WeatherCondition.fromSymbolCode(String raw) {
    final code = raw.trim().toLowerCase();
    final separator = code.indexOf('_');
    final base = separator < 0 ? code : code.substring(0, separator);
    final precipitation = base.contains('sleet')
        ? WeatherPrecipitation.sleet
        : base.contains('snow')
            ? WeatherPrecipitation.snow
            : base.contains('rain')
                ? WeatherPrecipitation.rain
                : WeatherPrecipitation.none;
    final showers = base.contains('showers');
    final WeatherSky sky;
    if (precipitation != WeatherPrecipitation.none) {
      sky = showers ? WeatherSky.partlyCloudy : WeatherSky.cloudy;
    } else if (base.startsWith('clearsky')) {
      sky = WeatherSky.clear;
    } else if (base.startsWith('fair')) {
      sky = WeatherSky.fair;
    } else if (base.startsWith('partlycloudy')) {
      sky = WeatherSky.partlyCloudy;
    } else if (base.startsWith('fog')) {
      sky = WeatherSky.fog;
    } else {
      sky = WeatherSky.cloudy;
    }
    return WeatherCondition(
      code: code,
      sky: sky,
      precipitation: precipitation,
      intensity: base.startsWith('light')
          ? WeatherIntensity.light
          : base.startsWith('heavy')
              ? WeatherIntensity.heavy
              : WeatherIntensity.moderate,
      showers: showers,
      thunder: base.contains('thunder'),
    );
  }

  static WeatherCondition? tryParse(Object? raw) {
    final code = raw?.toString().trim() ?? '';
    return code.isEmpty ? null : WeatherCondition.fromSymbolCode(code);
  }

  final String code;
  final WeatherSky sky;
  final WeatherPrecipitation precipitation;
  final WeatherIntensity intensity;
  final bool showers;
  final bool thunder;

  bool get isWet => precipitation != WeatherPrecipitation.none;

  /// The sky in the words a Chilean forecast uses.
  String get label {
    final String words;
    switch (precipitation) {
      case WeatherPrecipitation.none:
        words = switch (sky) {
          WeatherSky.clear => 'Despejado',
          WeatherSky.fair => 'Escasa nubosidad',
          WeatherSky.partlyCloudy => 'Nubosidad parcial',
          WeatherSky.cloudy => 'Nublado',
          WeatherSky.fog => 'Neblina',
        };
      case WeatherPrecipitation.rain:
        words = showers
            ? _graded('Chubascos débiles', 'Chubascos', 'Chubascos intensos')
            : _graded('Lluvia débil', 'Lluvia', 'Lluvia intensa');
      case WeatherPrecipitation.sleet:
        words = showers
            ? 'Chubascos de aguanieve'
            : _graded('Aguanieve débil', 'Aguanieve', 'Aguanieve intensa');
      case WeatherPrecipitation.snow:
        words = showers
            ? 'Chubascos de nieve'
            : _graded('Nieve débil', 'Nieve', 'Nieve intensa');
    }
    return thunder ? '$words con tormenta' : words;
  }

  String _graded(String light, String moderate, String heavy) {
    return switch (intensity) {
      WeatherIntensity.light => light,
      WeatherIntensity.moderate => moderate,
      WeatherIntensity.heavy => heavy,
    };
  }
}

class WeatherPlace {
  const WeatherPlace({
    required this.latitude,
    required this.longitude,
    this.name,
  });

  final double latitude;
  final double longitude;

  /// The city of the shop, when its listing names one.
  final String? name;
}

/// Who the readings come from, to be named next to them.
class WeatherCredit {
  const WeatherCredit({required this.name, this.url});

  final String name;
  final String? url;
}

/// What the nearest aerodrome measured in its last report.
class WeatherObservation {
  const WeatherObservation({
    required this.time,
    required this.station,
    required this.distanceKm,
    required this.temperature,
    this.apparentTemperature,
    this.windSpeed,
    this.windFromDirection,
    this.windGust,
    this.humidity,
    this.condition,
  });

  /// UTC.
  final DateTime time;

  /// ICAO code of the aerodrome.
  final String station;
  final double distanceKm;
  final double temperature;
  final double? apparentTemperature;

  /// Metres per second.
  final double? windSpeed;
  final double? windFromDirection;
  final double? windGust;
  final double? humidity;
  final WeatherCondition? condition;
}

/// One step of the series: the state at [time] and what happens over [span],
/// until the next step.
class WeatherStep {
  const WeatherStep({
    required this.time,
    required this.span,
    required this.temperature,
    this.apparentTemperature,
    this.windSpeed,
    this.windFromDirection,
    this.humidity,
    this.uvIndex,
    this.condition,
    this.precipitation = 0,
    this.spanMinTemperature,
    this.spanMaxTemperature,
    this.halfDayCondition,
  });

  /// UTC.
  final DateTime time;
  final Duration span;

  /// °C.
  final double temperature;
  final double? apparentTemperature;

  /// Metres per second, mean at ten metres. Null when the server does not
  /// stand behind the forecast's wind for this place.
  final double? windSpeed;

  /// Degrees the wind comes from.
  final double? windFromDirection;

  /// Per cent.
  final double? humidity;

  /// Under a clear sky.
  final double? uvIndex;

  /// The sky over [span].
  final WeatherCondition? condition;

  /// Millimetres over [span].
  final double precipitation;
  final double? spanMinTemperature;
  final double? spanMaxTemperature;

  /// The sky over the twelve hours from [time].
  final WeatherCondition? halfDayCondition;

  DateTime get end => time.add(span);
}

/// The weather at one instant: measured, or read between two steps of the
/// forecast.
class WeatherMoment {
  const WeatherMoment({
    required this.time,
    required this.temperature,
    required this.daylight,
    this.apparentTemperature,
    this.windSpeed,
    this.windFromDirection,
    this.windGust,
    this.humidity,
    this.uvIndex,
    this.condition,
    this.measurement,
  });

  final DateTime time;
  final double temperature;
  final double? apparentTemperature;
  final double? windSpeed;
  final double? windFromDirection;
  final double? windGust;
  final double? humidity;
  final double? uvIndex;
  final WeatherCondition? condition;
  final bool daylight;

  /// The report these values were measured in; null when they are forecast.
  final WeatherObservation? measurement;

  double? get windKilometresPerHour =>
      windSpeed == null ? null : windSpeed! * 3.6;
}

/// One hour of the next day.
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperature,
    required this.precipitation,
    required this.daylight,
    this.apparentTemperature,
    this.windSpeed,
    this.windFromDirection,
    this.condition,
  });

  /// UTC, on the hour.
  final DateTime time;
  final double temperature;
  final double? apparentTemperature;

  /// Millimetres in the hour that starts at [time].
  final double precipitation;
  final double? windSpeed;
  final double? windFromDirection;
  final WeatherCondition? condition;

  /// Whether the sun is up through most of the hour.
  final bool daylight;

  double? get windKilometresPerHour =>
      windSpeed == null ? null : windSpeed! * 3.6;
}

/// One day on the shop's calendar.
class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.minTemperature,
    required this.maxTemperature,
    required this.precipitation,
    this.maxWindSpeed,
    this.condition,
  });

  /// Midnight of the shop's day, as a plain calendar date.
  final DateTime date;
  final double minTemperature;
  final double maxTemperature;

  /// Millimetres over the day.
  final double precipitation;
  final double? maxWindSpeed;

  /// The sky of its daytime.
  final WeatherCondition? condition;
}

/// The weather of the shop's place, as the `weather-forecast` function
/// answers it: a forecast series and, when an aerodrome nearby reported
/// lately, what it measured.
class WeatherForecast {
  WeatherForecast({
    required this.place,
    required List<WeatherStep> steps,
    this.modelUpdatedAt,
    this.observation,
    List<WeatherCredit> credits = const [],
  })  : steps = List.unmodifiable(steps),
        credits = List.unmodifiable(credits);

  /// A measurement says what «now» is for about two hours: the aerodromes
  /// report every hour, and the app keeps an answer for half an hour more.
  static const Duration observationHolds = Duration(minutes: 130);

  /// Reads the function's document. Null when it holds no usable series.
  static WeatherForecast? tryParse(Object? document) {
    if (document is! Map) return null;
    final place = document['place'];
    final series = document['steps'];
    if (place is! Map || series is! List) return null;
    final latitude = _number(place['latitude']);
    final longitude = _number(place['longitude']);
    if (latitude == null || longitude == null) return null;

    final steps = <WeatherStep>[];
    for (final entry in series) {
      if (entry is! Map) continue;
      final time = DateTime.tryParse(entry['time']?.toString() ?? '');
      final temperature = _number(entry['temperature']);
      if (time == null || temperature == null) continue;
      steps.add(
        WeatherStep(
          time: time.toUtc(),
          span: Duration(
            minutes: math.max(0, _number(entry['span_minutes'])?.round() ?? 0),
          ),
          temperature: temperature,
          apparentTemperature: _number(entry['apparent_temperature']),
          windSpeed: _number(entry['wind_speed']),
          windFromDirection: _number(entry['wind_from_direction']),
          humidity: _number(entry['humidity']),
          uvIndex: _number(entry['uv_index']),
          condition: WeatherCondition.tryParse(entry['symbol']),
          precipitation: math.max(0, _number(entry['precipitation']) ?? 0),
          spanMinTemperature: _number(entry['span_min_temperature']),
          spanMaxTemperature: _number(entry['span_max_temperature']),
          halfDayCondition: WeatherCondition.tryParse(entry['half_day_symbol']),
        ),
      );
    }
    if (steps.isEmpty) return null;
    steps.sort((a, b) => a.time.compareTo(b.time));

    final source = document['source'];
    final credits = <WeatherCredit>[];
    if (source is Map && source['credits'] is List) {
      for (final credit in source['credits'] as List) {
        if (credit is! Map) continue;
        final name = credit['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final url = credit['url']?.toString().trim() ?? '';
        credits.add(WeatherCredit(name: name, url: url.isEmpty ? null : url));
      }
    }
    final name = place['name']?.toString().trim() ?? '';
    return WeatherForecast(
      place: WeatherPlace(
        latitude: latitude,
        longitude: longitude,
        name: name.isEmpty ? null : name,
      ),
      steps: steps,
      modelUpdatedAt: source is Map
          ? DateTime.tryParse(source['model_updated_at']?.toString() ?? '')
              ?.toUtc()
          : null,
      observation: _observation(document['observation']),
      credits: credits,
    );
  }

  static WeatherObservation? _observation(Object? raw) {
    if (raw is! Map) return null;
    final time = DateTime.tryParse(raw['time']?.toString() ?? '');
    final temperature = _number(raw['temperature']);
    if (time == null || temperature == null) return null;
    return WeatherObservation(
      time: time.toUtc(),
      station: raw['station']?.toString().trim() ?? '',
      distanceKm: _number(raw['distance_km']) ?? 0,
      temperature: temperature,
      apparentTemperature: _number(raw['apparent_temperature']),
      windSpeed: _number(raw['wind_speed']),
      windFromDirection: _number(raw['wind_from_direction']),
      windGust: _number(raw['wind_gust']),
      humidity: _number(raw['humidity']),
      condition: WeatherCondition.tryParse(raw['symbol']),
    );
  }

  final WeatherPlace place;

  /// When the forecast's model last ran for this place.
  final DateTime? modelUpdatedAt;
  final List<WeatherStep> steps;

  /// The last measurement near the place, if any reached the server.
  final WeatherObservation? observation;
  final List<WeatherCredit> credits;

  /// The series ends here; nothing is known after it.
  DateTime get horizon => steps.last.time;

  /// The weather right now: what was just measured while that report is
  /// recent, the forecast otherwise. Null when neither reaches [now].
  WeatherMoment? nowAt(DateTime now) {
    final utc = now.toUtc();
    final forecast = momentAt(utc);
    final measured = observation;
    if (measured == null ||
        utc.difference(measured.time) > observationHolds ||
        measured.time.difference(utc) > const Duration(minutes: 10)) {
      return forecast;
    }
    return WeatherMoment(
      time: measured.time,
      temperature: measured.temperature,
      apparentTemperature: measured.apparentTemperature,
      windSpeed: measured.windSpeed,
      windFromDirection: measured.windFromDirection,
      windGust: measured.windGust,
      humidity: measured.humidity,
      // An instrument does not report the sun's strength; the forecast does.
      uvIndex: forecast?.uvIndex,
      condition: measured.condition ?? forecast?.condition,
      daylight: _daylight(utc),
      measurement: measured,
    );
  }

  /// The forecast at [instant], read between the two steps around it. Null
  /// when the series does not reach that far.
  WeatherMoment? momentAt(DateTime instant) {
    var utc = instant.toUtc();
    // A clock a few minutes behind the first step still gets that step.
    if (utc.isBefore(steps.first.time) &&
        steps.first.time.difference(utc) <= const Duration(hours: 1)) {
      utc = steps.first.time;
    }
    final index = _stepIndexAt(utc);
    if (index == null) return null;
    final step = steps[index];
    final next = index + 1 < steps.length ? steps[index + 1] : null;
    final share = next == null || step.span == Duration.zero
        ? 0.0
        : utc.difference(step.time).inMicroseconds / step.span.inMicroseconds;
    final nearest = share >= 0.5 && next != null ? next : step;
    return WeatherMoment(
      time: utc,
      temperature: _between(step.temperature, next?.temperature, share)!,
      apparentTemperature: _between(
        step.apparentTemperature,
        next?.apparentTemperature,
        share,
      ),
      windSpeed: _between(step.windSpeed, next?.windSpeed, share),
      windFromDirection: nearest.windFromDirection,
      humidity: _between(step.humidity, next?.humidity, share),
      uvIndex: _between(step.uvIndex, next?.uvIndex, share),
      condition: step.condition ?? next?.condition,
      daylight: _daylight(utc),
    );
  }

  /// The [count] hours that start with the hour [from] falls in, plus the one
  /// that closes them, so a curve can reach the end of its last hour.
  List<WeatherHour> hoursFrom(DateTime from, {int count = 24}) {
    final utc = from.toUtc();
    var start = DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
    if (start.isBefore(steps.first.time) &&
        steps.first.time.difference(start) <= const Duration(hours: 1)) {
      start = steps.first.time;
    }
    final hours = <WeatherHour>[];
    for (var offset = 0; offset <= count; offset++) {
      final time = start.add(Duration(hours: offset));
      final moment = momentAt(time);
      if (moment == null) break;
      hours.add(
        WeatherHour(
          time: time,
          temperature: moment.temperature,
          apparentTemperature: moment.apparentTemperature,
          precipitation: _precipitationBetween(
            time,
            time.add(const Duration(hours: 1)),
          ),
          windSpeed: moment.windSpeed,
          windFromDirection: moment.windFromDirection,
          condition: moment.condition,
          daylight: _daylight(time.add(const Duration(minutes: 30))),
        ),
      );
    }
    return hours;
  }

  /// The shop's days after the one [now] falls in, while the series covers
  /// at least three quarters of each.
  List<WeatherDay> daysAfter(DateTime now, {int count = 8}) {
    final today = shopTime(now);
    final days = <WeatherDay>[];
    for (var offset = 1; days.length < count && offset <= count + 2; offset++) {
      final date = DateTime(today.year, today.month, today.day + offset);
      final after = DateTime(date.year, date.month, date.day + 1);
      final start = shopClockToUtc(date.year, date.month, date.day);
      final end = shopClockToUtc(after.year, after.month, after.day);
      if (start.isAfter(horizon)) break;
      final covered =
          (horizon.isBefore(end) ? horizon : end).difference(start).inMinutes;
      if (covered < end.difference(start).inMinutes * 3 ~/ 4) break;

      double? minimum;
      double? maximum;
      double? wind;
      void take(double? value) {
        if (value == null) return;
        minimum = minimum == null ? value : math.min(minimum!, value);
        maximum = maximum == null ? value : math.max(maximum!, value);
      }

      for (final step in steps) {
        if (step.time.isBefore(start) || !step.time.isBefore(end)) continue;
        take(step.temperature);
        // A six-hour step also knows the extremes between its two ends.
        if (step.span > const Duration(hours: 1)) {
          take(step.spanMinTemperature);
          take(step.spanMaxTemperature);
        }
        final speed = step.windSpeed;
        if (speed != null) wind = wind == null ? speed : math.max(wind, speed);
      }
      if (minimum == null || maximum == null) break;
      days.add(
        WeatherDay(
          date: date,
          minTemperature: minimum!,
          maxTemperature: maximum!,
          precipitation: _precipitationBetween(start, end),
          maxWindSpeed: wind,
          condition: _daytimeCondition(date),
        ),
      );
    }
    return days;
  }

  /// Sunrise and sunset of the shop's day [now] falls in, in UTC.
  ({DateTime? sunrise, DateTime? sunset}) sunOn(DateTime now) {
    final today = shopTime(now);
    return SolarTimes.of(
      around: shopClockToUtc(today.year, today.month, today.day, 12),
      latitude: place.latitude,
      longitude: place.longitude,
    );
  }

  int? _stepIndexAt(DateTime utc) {
    if (utc.isBefore(steps.first.time) || utc.isAfter(horizon)) return null;
    var low = 0;
    var high = steps.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (steps[middle].time.isAfter(utc)) {
        high = middle - 1;
      } else {
        low = middle;
      }
    }
    return low;
  }

  /// Millimetres between two instants: each step gives the share of its span
  /// that falls inside them.
  double _precipitationBetween(DateTime start, DateTime end) {
    var total = 0.0;
    for (final step in steps) {
      if (step.span == Duration.zero || step.precipitation <= 0) continue;
      if (!step.end.isAfter(start)) continue;
      if (!step.time.isBefore(end)) break;
      final from = step.time.isAfter(start) ? step.time : start;
      final to = step.end.isBefore(end) ? step.end : end;
      total += step.precipitation *
          to.difference(from).inMicroseconds /
          step.span.inMicroseconds;
    }
    return total;
  }

  /// The sky of the day's working hours: the half-day summary that starts
  /// nearest to nine in the morning at the shop.
  WeatherCondition? _daytimeCondition(DateTime date) {
    final morning = shopClockToUtc(date.year, date.month, date.day, 9);
    WeatherStep? best;
    for (final step in steps) {
      if (step.halfDayCondition == null) continue;
      final distance = step.time.difference(morning).abs();
      if (distance > const Duration(hours: 3)) continue;
      if (best == null || distance < best.time.difference(morning).abs()) {
        best = step;
      }
    }
    if (best != null) return best.halfDayCondition;
    final noon = shopClockToUtc(date.year, date.month, date.day, 12);
    final index = _stepIndexAt(noon);
    return index == null ? null : steps[index].condition;
  }

  bool _daylight(DateTime utc) => SolarTimes.isDaylight(
        instant: utc,
        latitude: place.latitude,
        longitude: place.longitude,
      );

  static double? _between(double? from, double? to, double share) {
    if (from == null) return to;
    if (to == null) return from;
    return from + (to - from) * share;
  }

  static double? _number(Object? value) {
    if (value is num) {
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }
    return null;
  }
}
