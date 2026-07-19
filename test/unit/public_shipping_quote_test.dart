import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/public_shipping_quote.dart';

void main() {
  group('PublicShippingQuote', () {
    test('parses a gross CLP shipping quote and reconciles its total', () {
      final quote = PublicShippingQuote.fromRpc({
        'delivery_type': 'shipping',
        'item_gross': 29999,
        'shipping_gross': 6990,
        'shipping_net': 5874,
        'shipping_tax': 1116,
        'tax_rate': 19,
        'estimated_min_business_days': 3,
        'estimated_max_business_days': 12,
        'tier_id': 'tier-1',
      });

      expect(quote.orderGross, 36989);
      expect(quote.shippingNet + quote.shippingTax, quote.shippingGross);
      expect(quote.isPickup, isFalse);
    });

    test('accepts a zero-cost pickup quote', () {
      final quote = PublicShippingQuote.fromRpc({
        'delivery_type': 'pickup',
        'item_gross': 150000,
        'shipping_gross': 0,
        'shipping_net': 0,
        'shipping_tax': 0,
        'tax_rate': 0,
        'estimated_min_business_days': 0,
        'estimated_max_business_days': 0,
      });

      expect(quote.orderGross, 150000);
      expect(quote.isPickup, isTrue);
    });

    test('rejects a quote whose gross shipping amount does not reconcile', () {
      expect(
        () => PublicShippingQuote.fromRpc({
          'delivery_type': 'shipping',
          'item_gross': 30000,
          'shipping_gross': 8990,
          'shipping_net': 7555,
          'shipping_tax': 1400,
          'tax_rate': 19,
          'estimated_min_business_days': 3,
          'estimated_max_business_days': 12,
        }),
        throwsFormatException,
      );
    });

    test('rejects fractional CLP values', () {
      expect(
        () => PublicShippingQuote.fromRpc({
          'delivery_type': 'shipping',
          'item_gross': 29999.5,
          'shipping_gross': 6990,
          'shipping_net': 5874,
          'shipping_tax': 1116,
          'tax_rate': 19,
          'estimated_min_business_days': 3,
          'estimated_max_business_days': 12,
        }),
        throwsFormatException,
      );
    });

    test('rejects fractional delivery metadata instead of truncating it', () {
      expect(
        () => PublicShippingQuote.fromRpc({
          'delivery_type': 'shipping',
          'item_gross': 30000,
          'shipping_gross': 8990,
          'shipping_net': 7555,
          'shipping_tax': 1435,
          'tax_rate': 19,
          'estimated_min_business_days': 3.5,
          'estimated_max_business_days': 12,
        }),
        throwsFormatException,
      );
    });
  });
}
