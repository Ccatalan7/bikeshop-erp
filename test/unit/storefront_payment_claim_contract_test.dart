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
      final source = readLibrarySource(
          'lib/public_store/widgets/public_store_layout.dart');
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
      final source = readLibrarySource(
          'lib/public_store/widgets/public_store_layout.dart');
      expect(source, isNot(contains('footer_payment_methods')));
      expect(source, isNot(contains('resolveConfirmedPaymentBadgeIds')));
    });

    test('the footer consumes the tenant-scoped capability with a lease', () {
      final source = readLibrarySource(
          'lib/public_store/widgets/public_store_layout.dart');
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
    // The bundled asset is ONE tenant's brand. It exists in the source on
    // purpose — Viñabike's own storefront renders it — so what has to be
    // proven is not its absence from a file but the rule that decides who may
    // use it. That rule has a single owner, and it is asked directly here;
    // what the header and the footer then paint is covered by the real widget
    // harness in test/widgets/public_store_header_responsive_test.dart.
    StorefrontLogoResolution resolutionFor({
      String configuredUrl = '',
      String? tenantLogoUrl,
      String? tenantId,
    }) {
      return StorefrontLogoResolution.resolve(
        configuredUrl: configuredUrl,
        tenantLogoUrl: tenantLogoUrl,
        tenantId: tenantId,
      );
    }

    test('the canonical tenant with no logo may use its own bundled asset', () {
      final resolution = resolutionFor(tenantId: VinabikeCanonicalTenant.id);

      expect(resolution.networkCandidates, isEmpty);
      expect(resolution.allowsBundledAsset, isTrue);
      expect(
        StorefrontLogoResolution.bundledAssetPath,
        'assets/images/vinabike_logo.png',
      );
    });

    test('a foreign tenant with no logo gets no asset to fall back on', () {
      final resolution = resolutionFor(tenantId: 'f0a1b2c3-tienda-ajena');

      expect(resolution.networkCandidates, isEmpty);
      expect(
        resolution.allowsBundledAsset,
        isFalse,
        reason: 'another store never inherits Viñabike branding',
      );
    });

    test('a foreign configured URL is attempted, and still unlocks nothing',
        () {
      final resolution = resolutionFor(
        configuredUrl: 'https://cdn.tienda-ajena.test/logo.png',
        tenantLogoUrl: 'https://cdn.tienda-ajena.test/logo.png',
        tenantId: 'f0a1b2c3-tienda-ajena',
      );

      expect(
        resolution.networkCandidates,
        <String>['https://cdn.tienda-ajena.test/logo.png'],
        reason: 'configured first, deduplicated against the hydrated tenant',
      );
      expect(
        resolution.allowsBundledAsset,
        isFalse,
        reason: 'a URL that fails to load falls through to the wordmark, '
            'never to a tenant asset that is not theirs',
      );
    });

    test('identity is the canonical id, and nothing else', () {
      expect(VinabikeCanonicalTenant.owns(VinabikeCanonicalTenant.id), isTrue);
      expect(
        VinabikeCanonicalTenant.owns(' ${VinabikeCanonicalTenant.id} '),
        isTrue,
        reason: 'the id is what it is after trimming',
      );
      expect(VinabikeCanonicalTenant.owns(null), isFalse);
      expect(VinabikeCanonicalTenant.owns(''), isFalse);
      expect(VinabikeCanonicalTenant.owns('f0a1b2c3-tienda-ajena'), isFalse);
      expect(
        resolutionFor(tenantId: null).allowsBundledAsset,
        isFalse,
        reason: 'an unknown tenant is a foreign tenant',
      );
    });
  });
}
