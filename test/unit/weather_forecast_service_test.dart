import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/weather_forecast_service.dart';

Map<String, dynamic> _answer({
  String expiresAt = '2026-11-12T23:49:40.000Z',
  double temperature = 19,
}) =>
    {
      'status': 'ok',
      'place': {
        'name': 'Viña del Mar',
        'latitude': -33.0252,
        'longitude': -71.5623,
      },
      'source': {
        'checked_at': '2026-11-12T23:19:40.000Z',
        'expires_at': expiresAt,
        'credits': [
          {'name': 'MET Norway', 'url': 'https://www.met.no/en'},
        ],
      },
      'observation': null,
      'steps': [
        {
          'time': '2026-11-12T23:00:00.000Z',
          'span_minutes': 60,
          'temperature': temperature,
        },
        {
          'time': '2026-11-13T00:00:00.000Z',
          'span_minutes': 0,
          'temperature': 17.4,
        },
      ],
    };

void main() {
  late DateTime now;
  late String? userId;
  late int reads;
  late FutureOr<Object?> Function() answer;

  WeatherForecastService service() => WeatherForecastService(
        fetcher: () async {
          reads++;
          return answer();
        },
        currentUserId: () => userId,
        clock: () => now,
      );

  setUp(() {
    now = DateTime.utc(2026, 11, 12, 23, 20);
    userId = 'employee-1';
    reads = 0;
    answer = _answer;
  });

  test('reads once and answers from hand until the server\'s expiry', () async {
    final weather = service();
    var notified = 0;
    weather.addListener(() => notified++);

    final first = weather.ensureFresh();
    expect(weather.loading, isTrue);
    await first;
    expect(weather.loading, isFalse);
    expect(reads, 1);
    expect(notified, 2);
    final snapshot = weather.snapshot!;
    expect(snapshot.forecast.place.name, 'Viña del Mar');
    expect(snapshot.confirmedAt, DateTime.utc(2026, 11, 12, 23, 19, 40));
    expect(snapshot.refreshAfter, DateTime.utc(2026, 11, 12, 23, 49, 40));

    now = DateTime.utc(2026, 11, 12, 23, 49);
    await weather.ensureFresh();
    expect(reads, 1);

    now = DateTime.utc(2026, 11, 12, 23, 50);
    answer = () => _answer(expiresAt: '2026-11-13T00:20:00.000Z');
    await weather.ensureFresh();
    expect(reads, 2);
    expect(weather.snapshot!.refreshAfter, DateTime.utc(2026, 11, 13, 0, 20));
  });

  test('callers that arrive together share one read', () async {
    final gate = Completer<Object?>();
    answer = () => gate.future;
    final weather = service();
    final all = [
      weather.ensureFresh(),
      weather.ensureFresh(),
      weather.ensureFresh(force: true),
    ];
    gate.complete(_answer());
    await Future.wait(all);
    expect(reads, 1);
    expect(weather.snapshot, isNotNull);
  });

  test('a failed read keeps the forecast in hand and rests five minutes',
      () async {
    final weather = service();
    await weather.ensureFresh();
    now = DateTime.utc(2026, 11, 12, 23, 55);
    answer = () => throw StateError('weather-forecast answered 502');
    await weather.ensureFresh();
    expect(reads, 2);
    expect(weather.failed, isTrue);
    expect(weather.snapshot, isNotNull);

    now = DateTime.utc(2026, 11, 12, 23, 59);
    await weather.ensureFresh();
    expect(reads, 2, reason: 'the server is left alone during the rest');

    // The person asking again does not wait.
    answer = _answer;
    await weather.ensureFresh(force: true);
    expect(reads, 3);
    expect(weather.failed, isFalse);

    answer = () => throw StateError('offline');
    now = DateTime.utc(2026, 11, 13, 0, 10);
    await weather.ensureFresh();
    now = DateTime.utc(2026, 11, 13, 0, 15, 1);
    answer = _answer;
    await weather.ensureFresh();
    expect(reads, 5);
    expect(weather.failed, isFalse);
  });

  test('a first read that fails says so and has nothing to show', () async {
    answer = () => throw StateError('offline');
    final weather = service();
    await weather.ensureFresh();
    expect(weather.failed, isTrue);
    expect(weather.snapshot, isNull);
    expect(weather.locationMissing, isFalse);
  });

  test('an answer that is not a forecast is a failure, not empty weather',
      () async {
    for (final broken in <Object?>[
      null,
      'text',
      {'status': 'unavailable'},
      {'status': 'ok', 'source': <String, dynamic>{}, 'steps': <Object>[]},
      {
        'status': 'ok',
        'place': {'latitude': -33.0, 'longitude': -71.5},
        'steps': [
          {'time': '2026-11-12T23:00:00Z', 'temperature': 19},
        ],
      },
    ]) {
      answer = () => broken;
      final weather = service();
      await weather.ensureFresh();
      expect(weather.failed, isTrue, reason: '$broken');
      expect(weather.snapshot, isNull);
    }
  });

  test('a shop without a place is told apart from a failure', () async {
    answer = () => {'status': 'location_missing'};
    final weather = service();
    await weather.ensureFresh();
    expect(weather.locationMissing, isTrue);
    expect(weather.failed, isFalse);
    expect(weather.snapshot, isNull);

    // Not asked again on every tick; an hour later it is.
    now = now.add(const Duration(minutes: 59));
    await weather.ensureFresh();
    expect(reads, 1);
    now = now.add(const Duration(minutes: 2));
    answer = _answer;
    await weather.ensureFresh();
    expect(reads, 2);
    expect(weather.locationMissing, isFalse);
    expect(weather.snapshot, isNotNull);
  });

  test('a server clock ahead of this one cannot turn every tick into a read',
      () async {
    answer = () => _answer(expiresAt: '2026-11-12T23:00:00.000Z');
    final weather = service();
    await weather.ensureFresh();
    expect(weather.snapshot!.refreshAfter, DateTime.utc(2026, 11, 12, 23, 21));
    now = DateTime.utc(2026, 11, 12, 23, 20, 30);
    await weather.ensureFresh();
    expect(reads, 1);
  });

  test('another account never sees the previous shop\'s weather', () async {
    final weather = service();
    await weather.ensureFresh();
    expect(weather.snapshot, isNotNull);

    userId = 'employee-of-another-shop';
    expect(weather.snapshot, isNull);
    expect(weather.failed, isFalse);
    answer = () => _answer(temperature: 8);
    await weather.ensureFresh();
    expect(reads, 2);
    expect(weather.snapshot!.forecast.steps.first.temperature, 8);

    userId = null;
    expect(weather.snapshot, isNull);
    await weather.ensureFresh(force: true);
    expect(reads, 2, reason: 'nobody signed in: nothing to ask');
  });

  test('a read that returns after the account changed is dropped', () async {
    final gate = Completer<Object?>();
    answer = () => gate.future;
    final weather = service();
    final pending = weather.ensureFresh();
    userId = 'employee-of-another-shop';
    answer = () => _answer(temperature: 8);
    await weather.ensureFresh();
    gate.complete(_answer(temperature: 30));
    await pending;
    expect(weather.snapshot!.forecast.steps.first.temperature, 8);
    expect(weather.loading, isFalse);
  });
}
