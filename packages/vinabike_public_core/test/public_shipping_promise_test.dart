import 'package:test/test.dart';
import 'package:vinabike_public_core/public_store/models/public_shipping_promise.dart';

/// The delivery promise is read from the zones, so the product page and the
/// checkout cannot drift apart again (2026-10-23: «1 a 3» on the product page
/// and «3 a 12» at the checkout, against zones of 1 to 10).
void main() {
  Map<String, Object?> tier(
    String zone,
    int order,
    num price,
    int min,
    int max,
  ) =>
      {
        'zone_name': zone,
        'zone_sort_order': order,
        'shipping_gross': price,
        'estimated_min_business_days': min,
        'estimated_max_business_days': max,
      };

  // The live zones of 2026-10-23, two bands each.
  final tiers = [
    tier('Zona austral', 6, 15990, 5, 10),
    tier('Región de Valparaíso', 1, 6490, 1, 3),
    tier('Región de Valparaíso', 1, 9490, 1, 3),
    tier('Santiago', 2, 7490, 2, 4),
    tier('Santiago', 2, 10490, 2, 4),
    tier('Norte', 5, 13990, 3, 7),
  ];

  test('the buy box says the own region and the rest of the country', () {
    final promise = PublicShippingPromise.fromTiers(tiers)!;
    expect(
      promise.buyBoxDetail,
      'Región de Valparaíso desde \$ 6.490, 1 a 3 días hábiles. '
      'Resto de Chile continental desde \$ 7.490, hasta 10 días.',
    );
  });

  test('the checkout window spans every zone', () {
    expect(
      PublicShippingPromise.fromTiers(tiers)!.checkoutWindow,
      'Chile continental, 1 a 10 días hábiles según tu región.',
    );
  });

  test('one zone is said alone', () {
    final promise = PublicShippingPromise.fromTiers([
      tier('Región de Valparaíso', 1, 6490, 2, 2),
    ])!;
    expect(promise.elsewhere, isNull);
    expect(
      promise.buyBoxDetail,
      'Región de Valparaíso desde \$ 6.490, 2 días hábiles.',
    );
  });

  group('a bicycle ships in its own box (20261121120000)', () {
    Map<String, Object?> bikeTier(String zone, int order, num price, num? bike) =>
        {
          ...tier(zone, order, price, 1, zone == 'Norte' ? 7 : 3),
          'bike_shipping_gross': bike,
          'bike_category_ids': ['bicis', 'bicis-ninos'],
        };

    test('its buy box says the price per zone', () {
      final promise = PublicShippingPromise.fromTiers([
        bikeTier('Región de Valparaíso', 1, 6490, 25990),
        bikeTier('Región de Valparaíso', 1, 12990, 25990),
        bikeTier('Santiago', 2, 7490, 30990),
        bikeTier('Norte', 5, 13990, 56990),
      ])!;
      expect(promise.shipsAsBike('bicis-ninos'), isTrue);
      expect(promise.shipsAsBike('cascos'), isFalse);
      expect(promise.shipsAsBike(null), isFalse);
      expect(
        promise.bikeBuyBoxDetail,
        'Despacho de la bicicleta a Región de Valparaíso \$ 25.990, '
        '1 a 3 días hábiles. Resto de Chile continental desde \$ 30.990, '
        'hasta 7 días.',
      );
      // The parcel promise does not change.
      expect(
        promise.buyBoxDetail,
        startsWith('Región de Valparaíso desde \$ 6.490'),
      );
    });

    test('without any zone that ships them, they are picked up', () {
      final promise = PublicShippingPromise.fromTiers([
        bikeTier('Región de Valparaíso', 1, 6490, null),
        bikeTier('Santiago', 2, 7490, null),
      ])!;
      expect(promise.bikeBuyBoxDetail, 'Las bicicletas se entregan en la tienda.');
    });

    test('a store without bicycle data ships none as a bicycle', () {
      expect(PublicShippingPromise.fromTiers(tiers)!.shipsAsBike('x'), isFalse);
    });
  });

  test('no rate or no window is no promise', () {
    expect(PublicShippingPromise.fromTiers(const []), isNull);
    expect(
      PublicShippingPromise.fromTiers([
        {'zone_name': 'Santiago', 'shipping_gross': 7490},
      ]),
      isNull,
    );
  });
}
