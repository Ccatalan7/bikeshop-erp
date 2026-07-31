import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  group('PublicCommerceProductProjection', () {
    test('raw deploy row and hydrated runtime Product resolve identically', () {
      final row = <String, dynamic>{
        'id': 'product-1',
        'name': 'Nombre catálogo',
        'website_name': 'Nombre web',
        'website_merchant_title': 'Nombre comercio',
        'sku': 'SKU-1',
        'description': 'Descripción catálogo',
        'website_description': 'Descripción web',
        'website_merchant_description': 'Descripción comercio',
        'price': 10000,
        'website_price': 12990,
        'price_currency': 'clp',
        'stock_quantity': 3,
        'inventory_qty': 9,
        'track_stock': true,
        'website_image_url': 'https://cdn.example.com/product-1.webp',
        'website_image_urls': [
          'https://cdn.example.com/product-1-detail.webp',
        ],
        'website_merchant_brand': '',
        'brand': 'Legacy brand',
        'website_merchant_gtin': '022255354042',
        'gtin': 'invalid',
        'barcode': '4715575883212',
        'website_merchant_mpn': 'SM-DBOIL-1L',
        'website_google_product_category': '499713',
        'category': 'components',
        'category_id': 'category-1',
        'category_name': 'Nombre denormalizado',
        'product_type': 'product',
        'created_at': '2026-07-22T00:00:00Z',
        'updated_at': '2026-07-22T00:00:00Z',
      };

      final deployProjection = PublicCommerceProductProjection.fromJson(
        row,
        resolvedBrand: 'Shimano',
        categoryPath: 'Componentes / Transmisión / Cadenas',
      );
      final runtimeProjection = PublicCommerceProductProjection.fromProduct(
        Product.fromJson(row),
        resolvedBrand: 'Shimano',
        categoryPath: 'Componentes / Transmisión / Cadenas',
      );
      final editorDraftProjection = PublicCommerceProductProjection.fromDraft(
        id: 'product-1',
        sku: 'SKU-1',
        catalogTitle: 'Nombre catálogo',
        websiteTitle: 'Nombre web',
        merchantTitle: 'Nombre comercio',
        catalogDescription: 'Descripción catálogo',
        websiteDescription: 'Descripción web',
        merchantDescription: 'Descripción comercio',
        price: 12990,
        currency: 'clp',
        brand: 'Shimano',
        categoryId: 'category-1',
        categoryPath: 'Componentes / Transmisión / Cadenas',
      );

      expect(runtimeProjection.toContractJson(),
          equals(deployProjection.toContractJson()));
      expect(editorDraftProjection.title, deployProjection.title);
      expect(editorDraftProjection.description, deployProjection.description);
      expect(editorDraftProjection.price, deployProjection.price);
      expect(editorDraftProjection.currency, deployProjection.currency);
      expect(editorDraftProjection.brand, deployProjection.brand);
      expect(editorDraftProjection.categoryPath, deployProjection.categoryPath);
      expect(
        deployProjection.toContractJson(),
        equals({
          'id': 'product-1',
          'sku': 'SKU-1',
          'title': 'Nombre comercio',
          'description': 'Descripción comercio',
          'price': 12990.0,
          'currency': 'CLP',
          'availability': 'in_stock',
          'image_urls': [
            'https://cdn.example.com/product-1.webp',
            'https://cdn.example.com/product-1-detail.webp',
          ],
          'brand': 'Shimano',
          'gtin': '4715575883212',
          'mpn': 'SM-DBOIL-1L',
          'category_id': 'category-1',
          'category_path': 'Componentes / Transmisión / Cadenas',
          'google_product_category': '499713',
          'merchant_eligible': true,
          'merchant_issues': <String>[],
        }),
      );
    });

    test('draft drops a denormalized category path without a category owner',
        () {
      final editorDraftProjection = PublicCommerceProductProjection.fromDraft(
        catalogTitle: 'Producto legacy',
        catalogDescription: 'Descripción factual.',
        price: 9990,
        categoryPath: 'Componentes / Transmisión / Piñones',
      );
      final deployProjection = PublicCommerceProductProjection.fromJson(
        {
          'name': 'Producto legacy',
          'description': 'Descripción factual.',
          'price': 9990,
          'category_name': 'Componentes / Transmisión / Piñones',
        },
        categoryPath: 'Componentes / Transmisión / Piñones',
      );

      expect(editorDraftProjection.categoryId, isEmpty);
      expect(editorDraftProjection.categoryPath, isEmpty);
      expect(editorDraftProjection.categoryPath, deployProjection.categoryPath);
    });

    test('optimized and original primary variants render as one gallery image',
        () {
      final row = <String, dynamic>{
        'id': 'product-images',
        'name': 'Volante',
        'sku': 'VOL-1',
        'description': 'Volante para bicicleta.',
        'price': 50000,
        'stock_quantity': 2,
        'track_stock': true,
        'website_image_url_optimized':
            'https://cdn.example.com/volante-main.webp',
        'website_image_url': 'https://cdn.example.com/volante-main.jpg',
        'website_image_urls': [
          'https://cdn.example.com/volante-main.jpg',
          'https://cdn.example.com/volante-detail.webp',
          'https://cdn.example.com/volante-detail.webp',
        ],
        'image_url_optimized': 'https://cdn.example.com/catalog-main.webp',
        'image_url': 'https://cdn.example.com/catalog-main.jpg',
        'brand': 'Shimano',
        'website_merchant_mpn': 'FC-TY501',
        'category': 'components',
        'product_type': 'product',
        'created_at': '2026-07-23T00:00:00Z',
        'updated_at': '2026-07-23T00:00:00Z',
      };

      final deployProjection = PublicCommerceProductProjection.fromJson(row);
      final runtimeProjection =
          PublicCommerceProductProjection.fromProduct(Product.fromJson(row));

      expect(
        deployProjection.imageUrls,
        [
          'https://cdn.example.com/volante-main.webp',
          'https://cdn.example.com/volante-detail.webp',
        ],
      );
      expect(runtimeProjection.imageUrls, deployProjection.imageUrls);
    });

    test('website primary keeps precedence over catalog optimized image', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-website-main',
          'name': 'Producto web',
          'description': 'Producto con imagen exclusiva para la web.',
          'price': 10000,
          'stock_quantity': 1,
          'track_stock': true,
          'website_image_url': 'https://cdn.example.com/website-main.jpg',
          'image_url_optimized': 'https://cdn.example.com/catalog-main.webp',
          'image_url': 'https://cdn.example.com/catalog-main.jpg',
          'brand': 'RBX',
          'website_merchant_mpn': 'WEB-MAIN-1',
        },
      );

      expect(
        projection.imageUrls,
        ['https://cdn.example.com/website-main.jpg'],
      );
    });

    test('catalog optimized and original URLs are one primary image', () {
      final row = <String, dynamic>{
        'id': 'product-catalog-main',
        'name': 'Producto catálogo',
        'sku': 'CATALOG-MAIN-1',
        'description': 'Producto con una imagen normal optimizada.',
        'price': 15000,
        'stock_quantity': 1,
        'track_stock': true,
        'image_url_optimized': 'https://cdn.example.com/catalog-main.webp',
        'image_url': 'https://cdn.example.com/catalog-main.jpg',
        'brand': 'RBX',
        'website_merchant_mpn': 'CATALOG-MAIN-1',
        'category': 'components',
        'product_type': 'product',
        'created_at': '2026-07-23T00:00:00Z',
        'updated_at': '2026-07-23T00:00:00Z',
      };

      final deployProjection = PublicCommerceProductProjection.fromJson(row);
      final runtimeProjection =
          PublicCommerceProductProjection.fromProduct(Product.fromJson(row));

      expect(
        deployProjection.imageUrls,
        ['https://cdn.example.com/catalog-main.webp'],
      );
      expect(runtimeProjection.imageUrls, deployProjection.imageUrls);
    });

    test('ineligible product reports facts and never guesses identifiers', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-2',
          'name': 'Producto sin datos',
          'sku': 'RETAILER-SKU',
          'description': '',
          'price': 0,
          'stock_quantity': 0,
          'track_stock': true,
          'brand': 'Genérico',
          'category_id': 'category-2',
          'category_name': 'No usar como ruta canónica',
          'product_type': 'product',
        },
      );

      expect(projection.merchantEligible, isFalse);
      expect(projection.mpn, isEmpty);
      expect(projection.gtin, isEmpty);
      expect(projection.categoryPath, isEmpty);
      expect(
        projection.merchantIssues.map((issue) => issue.code),
        equals([
          'missing_description',
          'invalid_price',
          'missing_image',
          'missing_brand',
          'missing_product_identifiers',
        ]),
      );
    });

    test('SEO fallback is factual and shared without changing eligibility', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-without-copy',
          'name': 'Biela izquierda aluminio 170 mm',
          'description': '',
          'price': 7990,
          'stock_quantity': 1,
          'track_stock': true,
          'image_url': 'https://cdn.example.com/biela.webp',
          'brand': 'Genérico',
          'category_id': 'category-volantes',
        },
        categoryPath: 'Componentes / Transmisión / Volantes',
      );

      expect(
        buildPublicProductSeoDescription(
          product: projection,
          storeName: 'Viñabike',
        ),
        'Conoce Biela izquierda aluminio 170 mm — Genérico · '
        'Componentes / Transmisión / Volantes. Revisa precio, stock y '
        'opciones de compra en Viñabike.',
      );
      expect(
        projection.merchantIssues,
        contains(PublicCommerceEligibilityIssue.missingDescription),
        reason: 'Generic SEO copy must not become canonical catalog content.',
      );
    });

    test('SEO fallback is deterministically capped at 320 characters', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-long-seo-fallback',
          'name': List.generate(
            45,
            (index) => 'componente-${index.toString().padLeft(2, '0')}',
          ).join(' '),
          'description': '',
          'price': 7990,
          'stock_quantity': 1,
          'track_stock': true,
          'brand': 'Marca técnica extendida',
          'category_id': 'category-long-path',
        },
        categoryPath:
            'Componentes / Transmisión / Volantes / Bielas / Repuestos',
      );

      final first = buildPublicProductSeoDescription(
        product: projection,
        storeName: 'Viñabike',
      );
      final second = buildPublicProductSeoDescription(
        product: projection,
        storeName: 'Viñabike',
      );

      expect(first, second);
      expect(first.length, lessThanOrEqualTo(320));
      expect(first, isNot(endsWith(' ')));
      expect(first, startsWith('Conoce componente-00 componente-01'));
      expect(RegExp(r'\s{2,}').hasMatch(first), isFalse);
    });

    test('out of stock is a valid Merchant availability', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-out-of-stock',
          'name': 'Cámara 26',
          'description': 'Cámara para bicicleta aro 26.',
          'price': 4990,
          'stock_quantity': 0,
          'track_stock': true,
          'image_url': 'https://cdn.example.com/camara.webp',
          'brand': 'RBX',
          'website_merchant_mpn': 'CAM-26-RBX',
        },
      );

      expect(projection.availability, PublicCommerceAvailability.outOfStock);
      expect(projection.merchantEligible, isTrue);
      expect(projection.merchantIssues, isEmpty);
    });

    test('brand alone does not replace GTIN or manufacturer MPN', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-brand-only',
          'name': 'Cámara 29',
          'description': 'Cámara para bicicleta aro 29.',
          'price': 5990,
          'stock_quantity': 1,
          'track_stock': true,
          'image_url': 'https://cdn.example.com/camara-29.webp',
          'brand': 'RBX',
        },
      );

      expect(projection.merchantEligible, isFalse);
      expect(
        projection.merchantIssues,
        [PublicCommerceEligibilityIssue.missingProductIdentifiers],
      );
    });

    test('invalid GTIN falls back only to another verified GTIN', () {
      final projection = PublicCommerceProductProjection.fromJson(
        {
          'id': 'product-3',
          'name': 'Cámara',
          'description': 'Cámara para bicicleta.',
          'price': 4990,
          'stock_quantity': 1,
          'track_stock': true,
          'image_url': 'https://cdn.example.com/camara.webp',
          'brand': 'RBX',
          'website_merchant_gtin': '022255354043',
          'gtin': 'no-es-gtin',
          'barcode': '4715575883212',
          'sku': 'CAMARA-RBX',
        },
      );

      expect(projection.gtin, '4715575883212');
      expect(projection.mpn, isEmpty);
      expect(projection.merchantEligible, isTrue);
    });
  });

  test('live storefront accepts only linked brands in the tenant scope', () {
    final resolved = canonicalPublicProductBrandNames(
      rows: const [
        {
          'id': 'own-brand',
          'name': 'Shimano',
          'tenant_id': 'tenant-vinabike',
          'is_active': true,
        },
        {
          'id': 'shared-brand',
          'name': 'SRAM',
          'tenant_id': null,
          'is_active': true,
        },
        {
          'id': 'foreign-brand',
          'name': 'Marca ajena',
          'tenant_id': 'tenant-other',
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
        'own-brand',
        'shared-brand',
        'foreign-brand',
        'inactive-brand',
      ],
    );

    expect(resolved, {
      'own-brand': 'Shimano',
      'shared-brand': 'SRAM',
    });
  });
}
