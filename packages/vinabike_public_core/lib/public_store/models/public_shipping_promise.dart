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
    this.bikeHere,
    this.bikeElsewhere,
    this.bikeCategoryIds = const <String>{},
  });

  /// The first zone by the store's order (its own region).
  final PublicShippingZoneOffer nearest;

  /// The cheapest of the other zones, null when there is only one.
  final PublicShippingZoneOffer? elsewhere;

  /// The window over every zone.
  final int minDays;
  final int maxDays;

  /// What one bicycle costs to the first zone, null when that zone takes no
  /// bicycles (20261121120000: a bicycle ships in its own box, priced per
  /// unit by zone).
  final double? bikeHere;

  /// The cheapest bicycle price of the other zones, null when none ships
  /// them.
  final double? bikeElsewhere;

  /// The categories that ship as a bicycle, their children included.
  final Set<String> bikeCategoryIds;

  /// Whether a product of [categoryId] ships as a bicycle.
  bool shipsAsBike(String? categoryId) =>
      categoryId != null && bikeCategoryIds.contains(categoryId);

  /// Null when no row carries a rate and a window.
  static PublicShippingPromise? fromTiers(Iterable<Object?> rows) {
    final zones = <String, ({int order, PublicShippingZoneOffer offer})>{};
    final bikes = <String, double>{};
    final bikeCategories = <String>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final ids = raw['bike_category_ids'];
      if (ids is Iterable) {
        bikeCategories.addAll(
          ids.whereType<Object>().map((id) => id.toString()),
        );
      }
      final price = _number(raw['shipping_gross']);
      final minDays = _number(raw['estimated_min_business_days'])?.toInt();
      final maxDays = _number(raw['estimated_max_business_days'])?.toInt();
      if (price == null || minDays == null || maxDays == null) continue;
      final name = (raw['zone_name'] ?? '').toString().trim();
      final order = _number(raw['zone_sort_order'])?.toInt() ?? 0;
      final key = name.isEmpty ? '#$order' : name;
      final bike = _number(raw['bike_shipping_gross']);
      if (bike != null) bikes[key] = bike;
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
    final ordered = zones.entries.toList()
      ..sort((a, b) => a.value.order.compareTo(b.value.order));
    final nearest = ordered.first.value.offer;
    PublicShippingZoneOffer? elsewhere;
    double? bikeElsewhere;
    for (final zone in ordered.skip(1)) {
      if (elsewhere == null || zone.value.offer.price < elsewhere.price) {
        elsewhere = zone.value.offer;
      }
      final bike = bikes[zone.key];
      if (bike != null && (bikeElsewhere == null || bike < bikeElsewhere)) {
        bikeElsewhere = bike;
      }
    }
    return PublicShippingPromise(
      nearest: nearest,
      elsewhere: elsewhere,
      minDays: ordered.map((z) => z.value.offer.minDays).reduce(_min),
      maxDays: ordered.map((z) => z.value.offer.maxDays).reduce(_max),
      bikeHere: bikes[ordered.first.key],
      bikeElsewhere: bikeElsewhere,
      bikeCategoryIds: bikeCategories,
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

  /// The buy box of a bicycle: «Despacho de la bicicleta a Región de
  /// Valparaíso $ 25.990, 1 a 3 días hábiles. Resto de Chile continental
  /// desde $ 30.990, hasta 10 días.» Without any zone that ships bicycles,
  /// it says they are picked up in store.
  String get bikeBuyBoxDetail {
    final here = bikeHere;
    final rest = bikeElsewhere;
    if (here == null && rest == null) {
      return 'Las bicicletas se entregan en la tienda.';
    }
    if (here == null) {
      return 'Despacho de la bicicleta desde '
          '${ChileanUtils.formatCurrency(rest!)} según tu región, '
          'hasta $maxDays días.';
    }
    final to = nearest.name.isEmpty ? '' : ' a ${nearest.name}';
    final first =
        'Despacho de la bicicleta$to ${ChileanUtils.formatCurrency(here)}, '
        '${_window(nearest.minDays, nearest.maxDays)}.';
    if (rest == null) return first;
    return '$first Resto de Chile continental desde '
        '${ChileanUtils.formatCurrency(rest)}, hasta $maxDays días.';
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
