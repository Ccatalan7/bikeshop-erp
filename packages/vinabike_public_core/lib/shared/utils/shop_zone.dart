import 'package:timezone/timezone.dart' as tz;

import 'shop_zone_data.dart';

/// The shop's zone: every business hour the ERP and the store show is read on
/// it.
const kShopTimeZone = 'America/Santiago';

tz.Location? _shopLocation;

/// The shop's zone as a location, for code that builds `tz.TZDateTime`s.
///
/// One owner, here so the storefront and the ERP share it. Before 2026-10-14
/// each caller loaded the whole world's zone table (`timezone/data/latest.dart`,
/// ~0.8 MB of JavaScript) to read this one zone, and the storefront's bundles
/// outgrew their budget. It is built from the shop's zone alone and never
/// touches the package's global database, so code that needs another zone can
/// still load the full table.
tz.Location shopLocation() => _shopLocation ??=
    tz.Location(kShopTimeZone, shopZoneTransitionAt, shopZoneTransitionZone, [
      for (final (offset, isDst, abbreviation) in shopZonePeriods)
        tz.TimeZone(offset, isDst: isDst, abbreviation: abbreviation),
    ]);
