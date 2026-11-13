import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/solar_times.dart';

/// Reference times from MET Norway's Sunrise API 3.0, read on 2026-11-12.
void main() {
  Matcher within(DateTime expected, [int minutes = 2]) => predicate<DateTime?>(
        (actual) =>
            actual != null &&
            actual.difference(expected).abs() <= Duration(minutes: minutes),
        'within $minutes min of $expected',
      );

  group('sunrise and sunset', () {
    test('Viña del Mar through the year', () {
      final spring = SolarTimes.of(
        around: DateTime.utc(2026, 11, 12, 15),
        latitude: -33.0252,
        longitude: -71.5623,
      );
      expect(spring.sunrise, within(DateTime.utc(2026, 11, 12, 9, 38)));
      expect(spring.sunset, within(DateTime.utc(2026, 11, 12, 23, 23)));

      final winter = SolarTimes.of(
        around: DateTime.utc(2026, 6, 21, 16),
        latitude: -33.0252,
        longitude: -71.5623,
      );
      expect(winter.sunrise, within(DateTime.utc(2026, 6, 21, 11, 49)));
      expect(winter.sunset, within(DateTime.utc(2026, 6, 21, 21, 47)));

      final summer = SolarTimes.of(
        around: DateTime.utc(2026, 12, 21, 16),
        latitude: -33.0252,
        longitude: -71.5623,
      );
      expect(summer.sunrise, within(DateTime.utc(2026, 12, 21, 9, 34)));
      expect(summer.sunset, within(DateTime.utc(2026, 12, 21, 23, 54)));
    });

    test('any hour of the shop\'s day gives that day\'s sun', () {
      // 22:00 on the 12th in Viña del Mar is already the 13th in UTC.
      final evening = SolarTimes.of(
        around: DateTime.utc(2026, 11, 13, 1),
        latitude: -33.0252,
        longitude: -71.5623,
      );
      expect(evening.sunrise, within(DateTime.utc(2026, 11, 12, 9, 38)));
      expect(evening.sunset, within(DateTime.utc(2026, 11, 12, 23, 23)));
    });

    test('other latitudes and a sunset past midnight UTC', () {
      final oslo = SolarTimes.of(
        around: DateTime.utc(2026, 11, 12, 11),
        latitude: 59.9139,
        longitude: 10.7522,
      );
      expect(oslo.sunrise, within(DateTime.utc(2026, 11, 12, 7, 6)));
      expect(oslo.sunset, within(DateTime.utc(2026, 11, 12, 14, 54)));

      final puntaArenas = SolarTimes.of(
        around: DateTime.utc(2026, 12, 21, 16),
        latitude: -53.1638,
        longitude: -70.9171,
      );
      expect(puntaArenas.sunrise, within(DateTime.utc(2026, 12, 21, 8, 12), 3));
      expect(puntaArenas.sunset, within(DateTime.utc(2026, 12, 22, 1, 10), 3));
    });

    test('where the sun does not cross the horizon there is neither', () {
      for (final around in [
        DateTime.utc(2026, 12, 21, 11),
        DateTime.utc(2026, 6, 21, 11),
      ]) {
        final tromso = SolarTimes.of(
          around: around,
          latitude: 69.6492,
          longitude: 18.9553,
        );
        expect(tromso.sunrise, isNull);
        expect(tromso.sunset, isNull);
      }
    });
  });

  group('daylight', () {
    bool daylight(DateTime instant) => SolarTimes.isDaylight(
          instant: instant,
          latitude: -33.0252,
          longitude: -71.5623,
        );

    test('follows the sun across sunrise and sunset', () {
      expect(daylight(DateTime.utc(2026, 11, 12, 16, 30)), isTrue);
      expect(daylight(DateTime.utc(2026, 11, 12, 3)), isFalse);
      expect(daylight(DateTime.utc(2026, 11, 12, 9, 30)), isFalse);
      expect(daylight(DateTime.utc(2026, 11, 12, 9, 46)), isTrue);
      expect(daylight(DateTime.utc(2026, 11, 12, 23, 15)), isTrue);
      expect(daylight(DateTime.utc(2026, 11, 12, 23, 31)), isFalse);
    });

    test('polar day and polar night', () {
      expect(
        SolarTimes.isDaylight(
          instant: DateTime.utc(2026, 6, 21, 23),
          latitude: 69.6492,
          longitude: 18.9553,
        ),
        isTrue,
      );
      expect(
        SolarTimes.isDaylight(
          instant: DateTime.utc(2026, 12, 21, 11),
          latitude: 69.6492,
          longitude: 18.9553,
        ),
        isFalse,
      );
    });
  });
}
