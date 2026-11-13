import 'dart:math' as math;

/// Where the sun is for a place, from NOAA's solar position equations.
///
/// The weather forecast says what the sky does; whether an hour is day or
/// night at the shop is astronomy, the same every year, so it is computed here
/// instead of asked from a service. Checked against MET Norway's Sunrise API
/// for Viña del Mar, Oslo and Punta Arenas: within two minutes
/// (`test/unit/solar_times_test.dart`).
class SolarTimes {
  const SolarTimes._();

  /// The sun's centre is this far below the horizon at sunrise and sunset:
  /// its radius plus the bending of light by the air.
  static const double _horizonDegrees = -0.833;

  /// Sunrise and sunset, in UTC, of the day whose solar noon is nearest to
  /// [around]. Both are null where the sun does not cross the horizon that
  /// day (polar day or night).
  static ({DateTime? sunrise, DateTime? sunset}) of({
    required DateTime around,
    required double latitude,
    required double longitude,
  }) {
    final instant = around.toUtc();
    // Local mean noon of the place nearest to the instant asked.
    final dayStart = DateTime.utc(instant.year, instant.month, instant.day);
    final meanNoonMinutes = 720 - 4 * longitude;
    var noon = dayStart.add(_minutes(meanNoonMinutes));
    if (noon.difference(instant).inHours > 12) {
      noon = noon.subtract(const Duration(days: 1));
    } else if (instant.difference(noon).inHours > 12) {
      noon = noon.add(const Duration(days: 1));
    }

    final sun = _sunAt(noon);
    final solarNoon = noon.subtract(_minutes(sun.equationOfTimeMinutes));
    final latitudeRadians = _radians(latitude);
    final cosHourAngle = (math.sin(_radians(_horizonDegrees)) -
            math.sin(latitudeRadians) * math.sin(sun.declination)) /
        (math.cos(latitudeRadians) * math.cos(sun.declination));
    if (cosHourAngle < -1 || cosHourAngle > 1) {
      return (sunrise: null, sunset: null);
    }
    final halfDay = _minutes(4 * _degrees(math.acos(cosHourAngle)));
    return (
      sunrise: solarNoon.subtract(halfDay),
      sunset: solarNoon.add(halfDay),
    );
  }

  /// Whether the sun is up at [instant] in that place.
  static bool isDaylight({
    required DateTime instant,
    required double latitude,
    required double longitude,
  }) {
    final utc = instant.toUtc();
    final sun = _sunAt(utc);
    final minutesOfDay =
        utc.hour * 60 + utc.minute + utc.second / 60 + utc.millisecond / 60000;
    final trueSolarMinutes =
        (minutesOfDay + sun.equationOfTimeMinutes + 4 * longitude) % 1440;
    final hourAngle = _radians(trueSolarMinutes / 4 - 180);
    final latitudeRadians = _radians(latitude);
    final sinElevation = math.sin(latitudeRadians) * math.sin(sun.declination) +
        math.cos(latitudeRadians) *
            math.cos(sun.declination) *
            math.cos(hourAngle);
    return sinElevation > math.sin(_radians(_horizonDegrees));
  }

  static ({double declination, double equationOfTimeMinutes}) _sunAt(
    DateTime utc,
  ) {
    final julianDay = utc.millisecondsSinceEpoch / 86400000 + 2440587.5;
    final t = (julianDay - 2451545.0) / 36525;
    final meanLongitude =
        _radians((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360);
    final meanAnomaly = _radians(357.52911 + t * (35999.05029 - 0.0001537 * t));
    final eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    final centre =
        math.sin(meanAnomaly) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
            math.sin(2 * meanAnomaly) * (0.019993 - 0.000101 * t) +
            math.sin(3 * meanAnomaly) * 0.000289;
    final omega = _radians(125.04 - 1934.136 * t);
    final apparentLongitude = meanLongitude +
        _radians(centre) -
        _radians(0.00569 + 0.00478 * math.sin(omega));
    final meanObliquity = 23 +
        (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
    final obliquity = _radians(meanObliquity + 0.00256 * math.cos(omega));
    final declination =
        math.asin(math.sin(obliquity) * math.sin(apparentLongitude));
    final y = math.pow(math.tan(obliquity / 2), 2).toDouble();
    final equationOfTime = 4 *
        _degrees(
          y * math.sin(2 * meanLongitude) -
              2 * eccentricity * math.sin(meanAnomaly) +
              4 *
                  eccentricity *
                  y *
                  math.sin(meanAnomaly) *
                  math.cos(2 * meanLongitude) -
              0.5 * y * y * math.sin(4 * meanLongitude) -
              1.25 * eccentricity * eccentricity * math.sin(2 * meanAnomaly),
        );
    return (declination: declination, equationOfTimeMinutes: equationOfTime);
  }

  static Duration _minutes(double minutes) => Duration(
      microseconds: (minutes * Duration.microsecondsPerMinute).round());

  static double _radians(double degrees) => degrees * math.pi / 180;

  static double _degrees(double radians) => radians * 180 / math.pi;
}
