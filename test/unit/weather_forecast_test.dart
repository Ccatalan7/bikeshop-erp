import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/weather_forecast.dart';
import 'package:vinabike_erp/shared/models/weather_outlook.dart';

/// The fixture is what the `weather-forecast` function answered for Viña del
/// Mar on 2026-11-12 at 23:20 UTC (20:20 at the shop): MET Norway's series,
/// tied to the 19° the aerodrome of Concón had just measured.
final _now = DateTime.utc(2026, 11, 12, 23, 20);

Map<String, dynamic> _document() => jsonDecode(
      File('test/fixtures/weather/shop_weather_vina_del_mar_20261112.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

/// An hourly series from [start], one step per temperature.
Map<String, dynamic> _hourly(
  DateTime start,
  List<double> temperatures, {
  Map<int, double> rain = const {},
  Map<int, double> wind = const {},
  Map<String, dynamic>? observation,
}) {
  return {
    'status': 'ok',
    'place': {
      'name': 'Viña del Mar',
      'latitude': -33.0252,
      'longitude': -71.5623
    },
    'source': {'credits': <Object>[]},
    'observation': observation,
    'steps': [
      for (var index = 0; index < temperatures.length; index++)
        {
          'time': start.add(Duration(hours: index)).toIso8601String(),
          'span_minutes': index + 1 < temperatures.length ? 60 : 0,
          'temperature': temperatures[index],
          'wind_speed': wind[index],
          'wind_from_direction': wind.containsKey(index) ? 225 : null,
          'symbol': rain.containsKey(index) ? 'rain' : 'fair_day',
          'precipitation': rain[index] ?? 0,
        },
    ],
  };
}

void main() {
  group('the function\'s document', () {
    test('is read whole: place, series, measurement and credits', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      expect(forecast.place.name, 'Viña del Mar');
      expect(forecast.place.latitude, -33.0252);
      expect(forecast.steps, hasLength(89));
      expect(forecast.steps.first.time, DateTime.utc(2026, 11, 12, 22));
      expect(forecast.horizon, DateTime.utc(2026, 11, 22));
      expect(forecast.modelUpdatedAt, DateTime.utc(2026, 11, 12, 19, 19, 40));
      expect(forecast.credits.map((credit) => credit.name), [
        'MET Norway',
        'NOAA Aviation Weather Center',
      ]);
      // Hourly for two and a half days, six-hourly after.
      expect(forecast.steps[0].span, const Duration(hours: 1));
      expect(forecast.steps[62].time, DateTime.utc(2026, 11, 15, 12));
      expect(forecast.steps[62].span, const Duration(hours: 6));
      expect(forecast.steps.last.span, Duration.zero);

      final measured = forecast.observation!;
      expect(measured.station, 'SCVM');
      expect(measured.time, DateTime.utc(2026, 11, 12, 23));
      expect(measured.temperature, 19);
      expect(measured.windSpeed, 3.1);
      expect(measured.windFromDirection, 330);
      expect(measured.distanceKm, 11.7);
      expect(measured.condition!.label, 'Despejado');
    });

    test('what is not a forecast is not read as one', () {
      for (final document in <Object?>[
        null,
        'text',
        <String, dynamic>{},
        {'place': <String, dynamic>{}, 'steps': <Object>[]},
        {
          'place': {'latitude': -33.0, 'longitude': -71.5},
          'steps': <Object>[],
        },
        {
          'place': {'latitude': -33.0, 'longitude': -71.5},
          'steps': [
            {'time': 'never', 'temperature': 20},
            {'time': '2026-11-12T22:00:00Z'},
            'noise',
          ],
        },
        {
          'place': {'latitude': 'south', 'longitude': -71.5},
          'steps': [
            {'time': '2026-11-12T22:00:00Z', 'temperature': 20},
          ],
        },
      ]) {
        expect(WeatherForecast.tryParse(document), isNull);
      }
    });
  });

  group('now', () {
    test('is what the aerodrome just measured, while that is recent', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      final now = forecast.nowAt(_now)!;
      expect(now.measurement!.station, 'SCVM');
      expect(now.temperature, 19);
      expect(now.apparentTemperature, 19);
      expect(now.windKilometresPerHour, closeTo(11.2, 0.05));
      expect(weatherCompass(now.windFromDirection!), 'NO');
      expect(now.humidity, 73);
      expect(now.condition!.label, 'Despejado');
      // An instrument does not report the sun's strength; the forecast does.
      expect(now.uvIndex, isNotNull);
      // 20:20 at the shop, three minutes before sunset.
      expect(now.daylight, isTrue);
    });

    test('goes back to the forecast when the report grows old', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      final later = forecast.nowAt(DateTime.utc(2026, 11, 13, 1, 30))!;
      expect(later.measurement, isNull);
      // Between the 01:00 and 02:00 UTC steps of the tied series.
      expect(later.temperature, closeTo(17.6, 0.15));
      expect(later.daylight, isFalse);
      // The server stood behind no wind for this place that evening.
      expect(later.windSpeed, isNull);
    });

    test('a report from the future or no report leaves the forecast', () {
      final document = _document();
      (document['observation'] as Map)['time'] = '2026-11-13T00:30:00.000Z';
      expect(
          WeatherForecast.tryParse(document)!.nowAt(_now)!.measurement, isNull);
      document['observation'] = null;
      final alone = WeatherForecast.tryParse(document)!;
      expect(alone.observation, isNull);
      expect(alone.nowAt(_now)!.temperature, closeTo(18.5, 0.1));
    });

    test('past the end of the series there is nothing to say', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      expect(forecast.nowAt(DateTime.utc(2026, 11, 22, 0, 1)), isNull);
      expect(forecast.momentAt(DateTime.utc(2026, 11, 12, 20)), isNull);
      // A clock a few minutes behind the first step still gets that step.
      expect(
        forecast.momentAt(DateTime.utc(2026, 11, 12, 21, 30))!.temperature,
        forecast.steps.first.temperature,
      );
    });
  });

  group('the next hours', () {
    test('start with the hour in course and close the last one', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      final hours = forecast.hoursFrom(_now);
      expect(hours, hasLength(25));
      expect(hours.first.time, DateTime.utc(2026, 11, 12, 23));
      expect(hours.last.time, DateTime.utc(2026, 11, 13, 23));
      // The curve starts at what was measured.
      expect(hours.first.temperature, 19);
      // 20:00–21:00 at the shop: the sun sets at 20:23.
      expect(hours.first.daylight, isFalse);
      // 11:00–12:00 the next morning.
      expect(hours[15].daylight, isTrue);
      expect(hours.every((hour) => hour.precipitation == 0), isTrue);
    });

    test('rain in a six-hour step is shared among its hours', () {
      final forecast = WeatherForecast.tryParse({
        'place': {'latitude': -33.0252, 'longitude': -71.5623},
        'steps': [
          {
            'time': '2026-11-15T12:00:00Z',
            'span_minutes': 360,
            'temperature': 14,
            'precipitation': 6,
            'symbol': 'rain',
          },
          {
            'time': '2026-11-15T18:00:00Z',
            'span_minutes': 0,
            'temperature': 20
          },
        ],
      })!;
      final hours = forecast.hoursFrom(DateTime.utc(2026, 11, 15, 12, 10));
      expect(hours, hasLength(7));
      expect(hours.take(6).map((hour) => hour.precipitation),
          everyElement(closeTo(1, 0.0001)));
      expect(hours.last.precipitation, 0);
      expect(hours[3].temperature, closeTo(17, 0.0001));
      expect(hours[3].condition!.label, 'Lluvia');
    });
  });

  group('the next days', () {
    test('are the shop\'s days, each with its extremes and its rain', () {
      final forecast = WeatherForecast.tryParse(_document())!;
      final days = forecast.daysAfter(_now);
      expect(days.map((day) => day.date.day), [13, 14, 15, 16, 17, 18, 19, 20]);
      expect(days.first.date, DateTime(2026, 11, 13));

      // Sunday the 15th: drizzle from 00:00 to 07:00, then six-hour steps,
      // and half of the one that straddles midnight.
      final sunday = days[2];
      expect(sunday.precipitation, closeTo(1.85, 0.01));
      expect(sunday.condition, isNotNull);
      for (final day in days) {
        expect(day.minTemperature, lessThanOrEqualTo(day.maxTemperature));
        expect(day.maxTemperature, inInclusiveRange(15, 30));
      }
    });

    test('a day the series barely reaches is not offered', () {
      final forecast = WeatherForecast.tryParse(
        _hourly(DateTime.utc(2026, 11, 12, 22), List.filled(30, 18)),
      )!;
      // Ends at 03:00 UTC of the 14th: all of the 13th, nothing of the 14th.
      expect(
        forecast.daysAfter(_now).map((day) => day.date.day),
        [13],
      );
    });

    test('sunrise and sunset are those of the shop\'s day', () {
      final sun = WeatherForecast.tryParse(_document())!.sunOn(_now);
      expect(
        sun.sunrise!
            .difference(DateTime.utc(2026, 11, 12, 9, 38))
            .inMinutes
            .abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        sun.sunset!
            .difference(DateTime.utc(2026, 11, 12, 23, 23))
            .inMinutes
            .abs(),
        lessThanOrEqualTo(2),
      );
    });
  });

  group('the sky in words', () {
    test('every symbol reads by its parts', () {
      const labels = {
        'clearsky_day': 'Despejado',
        'clearsky_night': 'Despejado',
        'clearsky': 'Despejado',
        'fair_day': 'Escasa nubosidad',
        'partlycloudy_night': 'Nubosidad parcial',
        'cloudy': 'Nublado',
        'fog': 'Neblina',
        'lightrain': 'Lluvia débil',
        'rain': 'Lluvia',
        'heavyrain': 'Lluvia intensa',
        'lightrainshowers_day': 'Chubascos débiles',
        'rainshowers_night': 'Chubascos',
        'heavyrainshowers_day': 'Chubascos intensos',
        'rainandthunder': 'Lluvia con tormenta',
        'heavyrainshowersandthunder_day': 'Chubascos intensos con tormenta',
        'lightsleet': 'Aguanieve débil',
        'sleetshowers_day': 'Chubascos de aguanieve',
        'lightssleetshowersandthunder_day':
            'Chubascos de aguanieve con tormenta',
        'snow': 'Nieve',
        'heavysnow': 'Nieve intensa',
        'lightsnowshowers_night': 'Chubascos de nieve',
        'something_new': 'Nublado',
      };
      labels.forEach((code, label) {
        expect(WeatherCondition.fromSymbolCode(code).label, label,
            reason: code);
      });
      final showers = WeatherCondition.fromSymbolCode('lightrainshowers_day');
      expect(showers.sky, WeatherSky.partlyCloudy);
      expect(showers.isWet, isTrue);
      expect(showers.intensity, WeatherIntensity.light);
      expect(WeatherCondition.fromSymbolCode('rain').sky, WeatherSky.cloudy);
      expect(WeatherCondition.tryParse(null), isNull);
      expect(WeatherCondition.tryParse('  '), isNull);
    });
  });

  group('the outlook', () {
    WeatherOutlook outlook(Map<String, dynamic> document, DateTime now) =>
        WeatherOutlook.of(WeatherForecast.tryParse(document)!, now);

    test('the real evening: drizzle on Sunday, nothing else to say', () {
      final result = outlook(_document(), _now);
      expect(result.kind, WeatherOutlookKind.rainLater);
      expect(result.headline,
          'Lluvia desde el domingo a las 2:00 (cerca de 1 mm)');
      expect(result.note, isNull);
    });

    // 12:00 at the shop on a Thursday.
    final noon = DateTime.utc(2026, 11, 12, 15);
    final mild = List<double>.filled(60, 18);

    test('rain later today names its hour and its amount', () {
      final result = outlook(
        _hourly(noon, mild, rain: {3: 2, 4: 3, 5: 1}),
        noon.add(const Duration(minutes: 20)),
      );
      expect(result.kind, WeatherOutlookKind.rainSoon);
      expect(result.headline, 'Lluvia desde las 15:00 (unos 6 mm)');
    });

    test('rain tomorrow says tomorrow, and one o\'clock is singular', () {
      final result = outlook(
        _hourly(noon, mild, rain: {13: 1.5, 14: 2}),
        noon,
      );
      expect(result.headline, 'Lluvia desde mañana a la 1:00 (unos 4 mm)');
      expect(result.kind, WeatherOutlookKind.rainSoon);
    });

    test('a short weak shower is a maybe', () {
      final result = outlook(_hourly(noon, mild, rain: {5: 0.3, 6: 0.2}), noon);
      expect(result.headline, 'Puede lloviznar a las 17:00');
    });

    test('rain under way says until when, bridging a dry hour', () {
      final result = outlook(
        _hourly(noon, mild, rain: {0: 1, 1: 2, 3: 1}),
        noon.add(const Duration(minutes: 5)),
      );
      expect(result.kind, WeatherOutlookKind.raining);
      expect(result.headline, 'Lluvia hasta las 16:00 (unos 4 mm)');
    });

    test('rain with no end in sight says so', () {
      final result = outlook(
        _hourly(noon, mild,
            rain: {for (var hour = 0; hour < 60; hour++) hour: 1}),
        noon,
      );
      expect(result.headline,
          'Lluvia sin pausa en los próximos días (unos 59 mm)');
    });

    test('the model\'s drizzle noise is not rain', () {
      final result = outlook(
        _hourly(noon, mild, rain: {2: 0.1, 3: 0.1, 9: 0.1}),
        noon,
      );
      expect(result.kind, WeatherOutlookKind.dry);
    });

    test('dry days name the day the rain comes', () {
      final document = _hourly(noon, mild);
      (document['steps'] as List).last['span_minutes'] = 60;
      // After the hourly series: six-hour steps to Wednesday, rain on
      // Tuesday the 17th.
      final start = noon.add(const Duration(hours: 60));
      for (var block = 0; block < 16; block++) {
        final time = start.add(Duration(hours: block * 6));
        (document['steps'] as List).add({
          'time': time.toIso8601String(),
          'span_minutes': block < 15 ? 360 : 0,
          'temperature': 17,
          'precipitation': time.day == 17 && time.hour >= 12 ? 4 : 0,
        });
      }
      final result = outlook(document, noon);
      expect(result.kind, WeatherOutlookKind.dry);
      expect(result.headline, 'Sin lluvia hasta el martes');
    });

    test('nothing wet in the whole series', () {
      final result = outlook(_hourly(noon, List.filled(100, 18)), noon);
      expect(result.headline, 'Sin lluvia en los próximos 3 días');
      expect(result.note, isNull);
    });

    test('the note names strong wind, heat or cold, in that order', () {
      final windy = outlook(
        _hourly(noon, mild,
            wind: {for (var h = 0; h < 60; h++) h: h == 4 ? 11 : 5}),
        noon,
      );
      expect(windy.note, 'Viento fuerte a las 16:00: 40 km/h del suroeste');

      final windyNow = outlook(
        _hourly(noon, mild,
            wind: {for (var h = 0; h < 60; h++) h: h == 0 ? 12 : 5}),
        noon,
      );
      expect(windyNow.note, 'Viento fuerte ahora: 43 km/h del suroeste');

      final hot = outlook(
        _hourly(noon, [for (var h = 0; h < 60; h++) h == 3 ? 31.4 : 22]),
        noon,
      );
      expect(hot.note, 'Calor a las 15:00: 31°');

      final cold = outlook(
        _hourly(noon, [for (var h = 0; h < 60; h++) h == 18 ? 1.6 : 9]),
        noon,
      );
      expect(cold.note, 'Frío mañana a las 6:00: 2°');
    });
  });

  group('words for numbers', () {
    test('compass, degrees, millimetres, clock and UV', () {
      expect(
        [0, 22, 23, 90, 135, 202, 225, 270, 315, 338, 359.9].map(
          (degrees) => weatherCompass(degrees.toDouble()),
        ),
        ['N', 'N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO', 'N', 'N'],
      );
      expect(weatherCompassWords(330), 'noroeste');
      expect(weatherDegrees(18.5), '19°');
      expect(weatherDegrees(-0.4), '0°');
      expect(weatherDegrees(-3.6), '-4°');
      expect(weatherMillimetres(0.4), 'menos de 1 mm');
      expect(weatherMillimetres(6.5), '7 mm');
      // 23:20 UTC is 20:20 in Viña del Mar, whatever the device's zone.
      expect(weatherShopClock(_now), '20:20');
      expect(weatherShopClock(DateTime.utc(2026, 11, 12, 12, 5)), '9:05');
      expect(
        <double>[0.4, 2.4, 3, 5.4, 6, 7.4, 8, 10.4, 11].map(weatherUvBand),
        [
          'bajo',
          'bajo',
          'moderado',
          'moderado',
          'alto',
          'alto',
          'muy alto',
          'muy alto',
          'extremo',
        ],
      );
      expect(weatherWeekdayShort(DateTime(2026, 11, 13)), 'vie');
      expect(weatherWeekday(DateTime(2026, 11, 15)), 'domingo');
    });
  });
}
