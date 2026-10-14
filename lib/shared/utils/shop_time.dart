import 'package:timezone/timezone.dart' as tz;
import 'package:vinabike_public_core/shared/utils/shop_zone.dart';

export 'package:vinabike_public_core/shared/utils/shop_zone.dart'
    show kShopTimeZone, shopLocation;

/// A moment on the shop's clock (`America/Santiago`), whatever zone the device
/// is set to: a web order bought at 15:52 in Chile read 11:52 on a Mac set to
/// Pacific time, and a list built from the UTC value can show the next day
/// after 21:00 (2026-10-13).
DateTime shopTime(DateTime value) {
  return tz.TZDateTime.from(value.toUtc(), _location());
}

/// The instant of a wall-clock time read on the shop's clock, such as the
/// admission time printed on a carrier's receipt («13/10/2026 17:43» in
/// Viña del Mar is 20:43 UTC in October).
DateTime shopClockToUtc(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) {
  return tz.TZDateTime(_location(), year, month, day, hour, minute).toUtc();
}

tz.Location _location() => shopLocation();
