import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import '../support/library_source.dart';

/// The footer may only claim payment methods the server confirmed.
///
/// The previous implementation asserted MercadoPago, Visa, Mastercard and
/// Redcompra for every store unconditionally; the round before that replaced
/// it with an orphan `footer_payment_methods` setting nothing could write.
/// Both are gone: the tenant-scoped `PublicCheckoutCapabilities` contract is
/// now the single source, and card networks are not representable at all.
void main() {
  PublicCheckoutCapabilities capabilities({
    required bool mercadopago,
    required bool transfer,
  }) {
    return PublicCheckoutCapabilities.fromRpc({
      'schemaVersion': 1,
      'methods': [
        {
          'code': 'mercadopago',
          'available': mercadopago,
          'reasonCode': mercadopago ? 'available' : 'configuration_incomplete',
        },
        {
          'code': 'transfer',
          'available': transfer,
          'reasonCode': transfer ? 'available' : 'configuration_incomplete',
        },
      ],
    });
  }

  group('claims follow the server capability', () {
    test('only available methods are claimed', () {
      expect(
        resolvePublicPaymentClaims(
          capabilities(mercadopago: true, transfer: false),
        ),
        [PublicCheckoutPaymentCode.mercadopago],
      );
      expect(
        resolvePublicPaymentClaims(
          capabilities(mercadopago: false, transfer: true),
        ),
        [PublicCheckoutPaymentCode.transfer],
      );
      expect(
        resolvePublicPaymentClaims(
          capabilities(mercadopago: true, transfer: true),
        ),
        [
          PublicCheckoutPaymentCode.mercadopago,
          PublicCheckoutPaymentCode.transfer,
        ],
      );
    });

    test('a store with nothing available claims nothing', () {
      expect(
        resolvePublicPaymentClaims(
          capabilities(mercadopago: false, transfer: false),
        ),
        isEmpty,
      );
    });

    test('unknown — loading or failed — claims nothing', () {
      expect(resolvePublicPaymentClaims(null), isEmpty);
    });
  });

  group('card networks can never be claimed', () {
    test('the claim catalogue holds no card network', () {
      expect(
        kPublicStorePaymentClaims.keys.toSet(),
        PublicCheckoutPaymentCode.values.toSet(),
      );
      for (final entry in kPublicStorePaymentClaims.entries) {
        for (final network in const ['Visa', 'Mastercard', 'Redcompra']) {
          expect(entry.value.label, isNot(contains(network)));
        }
      }
    });

    test('transfer is stated generically, with no third-party mark', () {
      final transfer =
          kPublicStorePaymentClaims[PublicCheckoutPaymentCode.transfer]!;
      expect(transfer.imageUrl, isNull);
      expect(transfer.label, 'Transferencia bancaria');
    });

    test('the renderer no longer references card-network assets', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
      for (final asset in const [
        'payment-icons/visa.svg',
        'payment-icons/mastercard.svg',
        'payment-icons/redcompra.png',
      ]) {
        expect(source, isNot(contains(asset)));
      }
    });
  });

  group('the orphan setting is gone', () {
    test('footer_payment_methods is no longer read anywhere', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
      expect(source, isNot(contains('footer_payment_methods')));
      expect(source, isNot(contains('resolveConfirmedPaymentBadgeIds')));
    });

    test('the footer consumes the tenant-scoped capability with a lease', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
      expect(source, contains('_paymentCapabilitiesGeneration'));
      expect(source, contains('_paymentCapabilitiesTenantId'));
      // A late response for another tenant must be discarded on both axes.
      expect(
        source,
        contains('generation != _paymentCapabilitiesGeneration'),
      );
      expect(source, contains('PublicCheckoutCapabilityService().load'));
    });
  });

  group('no tenant identity is fabricated', () {
    test('the bundled logo asset is never a fallback', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
      expect(source, isNot(contains('vinabike_logo')));
    });

    test('the wordmark degrades to a neutral label', () {
      final source = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
      expect(source, isNot(contains("'MI TIENDA'")));
      expect(source, contains("storeName.isNotEmpty ? storeName : 'Tienda'"));
    });
  });
}
