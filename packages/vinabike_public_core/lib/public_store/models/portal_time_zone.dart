// The customer portal's dates in the store's time zone, for a process that
// does not run in it (the HTML store runs in UTC on Cloud Run).
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'customer_portal_presentation.dart';

/// Makes [portalLocalTime] read an instant in [location] (the store's, by
/// default). A value without a zone (`2026-09-24`, a date column) is already
/// the store's wall time and stays as it is, as in the customer's browser.
void usePortalTimeZone([String location = 'America/Santiago']) {
  tzdata.initializeTimeZones();
  final zone = tz.getLocation(location);
  portalLocalTime = (date) {
    if (!date.isUtc) return date;
    final local = tz.TZDateTime.from(date, zone);
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
    );
  };
}
