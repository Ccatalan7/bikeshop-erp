import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  group('SEO snapshot linked-brand parity', () {
    test('uses a valid linked brand when the denormalized brand is empty', () {
      final brandNames = snapshots.buildTenantSafeProductBrandNameMap(
        brandRows: const [
          {
            'id': 'brand-shimano',
            'name': 'Shimano',
            'tenant_id': 'tenant-vinabike',
            'is_active': true,
          },
        ],
        tenantId: 'tenant-vinabike',
        requestedBrandIds: const ['brand-shimano'],
      );

      final commerce = snapshots.projectSeoSnapshotCommerceProduct(
        {
          'id': 'product-1',
          'sku': 'M8100',
          'name': 'Cambio trasero XT',
          'description': 'Cambio de 12 velocidades.',
          'price': 129990,
          'price_currency': 'CLP',
          'track_stock': false,
          'image_url': 'https://cdn.example.test/m8100.webp',
          'brand_id': 'brand-shimano',
          'brand': '',
          'website_merchant_mpn': 'RD-M8100-SGS',
        },
        resolvedBrandNamesById: brandNames,
      );

      expect(commerce.brand, 'Shimano');
      expect(commerce.mpn, 'RD-M8100-SGS');
      expect(commerce.merchantEligible, isTrue);
    });

    test('accepts shared brands and rejects another tenant brand defensively',
        () {
      final names = snapshots.buildTenantSafeProductBrandNameMap(
        brandRows: const [
          {
            'id': 'shared-brand',
            'name': 'SRAM',
            'tenant_id': null,
            'is_active': true,
          },
          {
            'id': 'own-brand',
            'name': 'Viñabike',
            'tenant_id': 'tenant-vinabike',
            'is_active': true,
          },
          {
            'id': 'foreign-brand',
            'name': 'Marca ajena',
            'tenant_id': 'tenant-foreign',
            'is_active': true,
          },
          {
            'id': 'inactive-brand',
            'name': 'Marca inactiva',
            'tenant_id': 'tenant-vinabike',
            'is_active': false,
          },
          {
            'id': 'not-requested',
            'name': 'No solicitada',
            'tenant_id': null,
            'is_active': true,
          },
        ],
        tenantId: 'tenant-vinabike',
        requestedBrandIds: const [
          'shared-brand',
          'own-brand',
          'foreign-brand',
          'inactive-brand',
        ],
      );

      expect(names, {
        'shared-brand': 'SRAM',
        'own-brand': 'Viñabike',
      });
    });

    test('all snapshot projection sites use the linked-brand resolver', () {
      final source = File('scripts/generate_product_seo_snapshots.dart')
          .readAsStringSync();

      expect(source, contains('image_urls,brand_id,brand,category_id'));
      expect(source, contains('_fetchProductBrandRows('));
      expect(source, contains('buildTenantSafeProductBrandNameMap('));
      expect(source, contains("'is_active': 'eq.true'"));
      expect(
        RegExp(r'PublicCommerceProductProjection\.fromJson\(')
            .allMatches(source)
            .length,
        1,
      );
      expect(
        RegExp(r'projectSeoSnapshotCommerceProduct\(')
            .allMatches(source)
            .length,
        greaterThanOrEqualTo(5),
      );
    });
  });
}
