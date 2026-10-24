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
