import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

tz.Location? _shopLocation;

/// A moment on the shop's clock (`America/Santiago`), whatever zone the device
/// is set to: a web order bought at 15:52 in Chile read 11:52 on a Mac set to
/// Pacific time, and a list built from the UTC value can show the next day
/// after 21:00 (2026-10-13).
DateTime shopTime(DateTime value) {
  final location = _shopLocation ??= () {
    tzdata.initializeTimeZones();
    return tz.getLocation('America/Santiago');
  }();
  return tz.TZDateTime.from(value.toUtc(), location);
}
