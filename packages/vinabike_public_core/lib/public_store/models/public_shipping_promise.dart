import '../../shared/utils/chilean_utils.dart';

/// One delivery zone as the buyer reads it: its name, the cheapest rate of
/// its bands and its delivery window.
class PublicShippingZoneOffer {
  const PublicShippingZoneOffer({
    required this.name,
    required this.price,
    required this.minDays,
    required this.maxDays,
  });

  final String name;
  final double price;
  final int minDays;
  final int maxDays;
}

/// What the store promises about home delivery, read from its zones
/// (`get_public_online_shipping_tiers`), so the product page and the
/// checkout say the same thing in both stores.
///
/// 2026-10-23: the product page said the nearest zone's «1 a 3 días» as if
/// it were the whole country, and the checkout a hand-written «3 a 12»,
/// against zones that go from 1 to 10.
class PublicShippingPromise {
  const PublicShippingPromise({
    required this.nearest,
    required this.elsewhere,
    required this.minDays,
    required this.maxDays,
  });

  /// The first zone by the store's order (its own region).
  final PublicShippingZoneOffer nearest;

  /// The cheapest of the other zones, null when there is only one.
  final PublicShippingZoneOffer? elsewhere;

  /// The window over every zone.
  final int minDays;
  final int maxDays;

  /// Null when no row carries a rate and a window.
  static PublicShippingPromise? fromTiers(Iterable<Object?> rows) {
    final zones = <String, ({int order, PublicShippingZoneOffer offer})>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final price = _number(raw['shipping_gross']);
      final minDays = _number(raw['estimated_min_business_days'])?.toInt();
      final maxDays = _number(raw['estimated_max_business_days'])?.toInt();
      if (price == null || minDays == null || maxDays == null) continue;
      final name = (raw['zone_name'] ?? '').toString().trim();
      final order = _number(raw['zone_sort_order'])?.toInt() ?? 0;
      final key = name.isEmpty ? '#$order' : name;
      final known = zones[key];
      zones[key] = (
        order: order,
        offer: PublicShippingZoneOffer(
          name: name,
          price: known == null || price < known.offer.price
              ? price
              : known.offer.price,
          minDays: known == null || minDays < known.offer.minDays
              ? minDays
              : known.offer.minDays,
          maxDays: known == null || maxDays > known.offer.maxDays
              ? maxDays
              : known.offer.maxDays,
        ),
      );
    }
    if (zones.isEmpty) return null;
    final ordered = zones.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final nearest = ordered.first.offer;
    PublicShippingZoneOffer? elsewhere;
    for (final zone in ordered.skip(1)) {
      if (elsewhere == null || zone.offer.price < elsewhere.price) {
        elsewhere = zone.offer;
      }
    }
    return PublicShippingPromise(
      nearest: nearest,
      elsewhere: elsewhere,
      minDays: ordered.map((z) => z.offer.minDays).reduce(_min),
      maxDays: ordered.map((z) => z.offer.maxDays).reduce(_max),
    );
  }

  /// The buy box: «Región de Valparaíso desde $ 6.490, 1 a 3 días hábiles.
  /// Resto de Chile continental desde $ 7.490, hasta 10 días.»
  String get buyBoxDetail {
    final here = nearest.name.isEmpty ? 'Desde' : '${nearest.name} desde';
    final first =
        '$here ${ChileanUtils.formatCurrency(nearest.price)}, '
        '${_window(nearest.minDays, nearest.maxDays)}.';
    final rest = elsewhere;
    if (rest == null) return first;
    return '$first Resto de Chile continental desde '
        '${ChileanUtils.formatCurrency(rest.price)}, hasta $maxDays días.';
  }

  /// The checkout's delivery option: «Chile continental, 1 a 10 días
  /// hábiles según tu región.»
  String get checkoutWindow =>
      'Chile continental, ${_window(minDays, maxDays)} según tu región.';

  static String _window(int min, int max) => min == max
      ? '$min ${min == 1 ? 'día hábil' : 'días hábiles'}'
      : '$min a $max días hábiles';

  static int _min(int a, int b) => a < b ? a : b;
  static int _max(int a, int b) => a > b ? a : b;

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
