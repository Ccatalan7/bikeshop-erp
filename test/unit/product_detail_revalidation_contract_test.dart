import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the stale-while-revalidate contract on the public product page.
///
/// The storefront freshness monitor invalidates inventory roughly every 30
/// seconds. The page used to treat each pulse as a fresh arrival: validation
/// was torn down, so the buy button disabled, the availability row flipped to
/// "Actualizando precio y disponibilidad…", the breadcrumb collapsed to its
/// short form, and the SEO title flapped to "Producto no disponible" — every
/// half minute, on a page whose data almost never changed. A validated product
/// must stay interactive while the fresh row loads in the background.
void main() {
  final source = File(
    'lib/public_store/pages/product_detail_page.dart',
  ).readAsStringSync();

  group('product detail revalidation', () {
    test('an inventory pulse never tears down a validated page', () {
      final handler = source
          .split('void _handlePublicInventoryInvalidated()')[1]
          .split('\n  }')[0];
      expect(handler, isNot(contains('_isProductValidated = false')));
      expect(handler, contains('unawaited(_loadProduct())'));
    });

    test('the breadcrumb trail survives a same-product reload', () {
      expect(
        source,
        contains('if (previousProduct?.id != _product?.id ||'),
      );
      // The unconditional clear this replaced.
      expect(
        source.split('previousProduct?.categoryId != _product?.categoryId')[1],
        contains('_categoryTrail = const [];'),
      );
    });

    test('the trail paints complete from cache on the first pass', () {
      // Seeded synchronously before the first build (catalog -> detail), and
      // again in the trail loader with a stale-aware snapshot: retained data
      // paints, and a stale snapshot still continues the origin revalidation.
      final seed = source
          .split('void _seedProductFromSessionSnapshot(')[1]
          .split('\n  }')[0];
      expect(seed, contains('categoryTrailFromCategories('));
      expect(source, contains('cachedCategoriesForTenant(tenantId: tenantId)'));
      expect(source, contains('if (snapshot!.isFresh) return;'));
      // Unchanged trails must not churn setState on every pulse.
      expect(source, contains('sameCategoryTrail('));
      // The pure walk lives in the shared util the behavior tests drive.
      expect(
        File('lib/public_store/utils/category_trail.dart').readAsStringSync(),
        contains('List<Category>? categoryTrailFromCategories('),
      );
    });

    test('purchase authority is bounded, refresh status is separate state', () {
      // A failed refresh keeps last-known-good authority only inside the
      // window, and the row renders from the two facts, never one boolean.
      expect(source, contains('purchaseAuthoritySurvivesRefreshFailure('));
      expect(source, contains('_lastValidatedAt = DateTime.now();'));
      expect(
        source,
        contains(
          '_isProductValidated ? snapshot.originValidatedAt : null',
        ),
      );
      expect(source, contains('productAvailabilityRowState('));
      expect(source, contains("'Mostrando la última información confirmada.'"));
    });

    test('confirmed metadata stays in place during a background refresh', () {
      expect(
        source,
        contains(
          'if (!hadRecentValidation) {\n'
          '      removeStructuredDataScript(_structuredDataScriptId);\n'
          '    }',
        ),
      );
      // First arrivals still install the restrictive state before origin
      // confirmation; only the already-validated refresh is exempt.
      expect(source, contains('_updatePendingSeo(token);'));
      expect(
        source,
        contains("titlePrefix: 'Producto no disponible'"),
      );
      expect(source, contains('void _updateSeo(int token)'));
      expect(
        source,
        contains(
          'token != _loadToken ||\n'
          '          !_isProductValidated ||\n'
          '          _product?.id != productId ||\n'
          '          _validatedTenantId != tenantId',
        ),
      );
    });

    test('expired purchase authority also removes sellable metadata', () {
      expect(
        source,
        contains(
          'if (!retainsAuthority) {\n'
          '          removeStructuredDataScript(_structuredDataScriptId);\n'
          '          _updateUnavailableSeo(token, force: true);',
        ),
      );
      expect(
        source,
        contains('if (product == null || !_isProductValidated) {'),
      );
    });

    test('purchase authority never crosses a tenant change', () {
      expect(
        source,
        contains('context.watch<PublicStoreTenantProvider>()'),
      );
      expect(source, contains('final tenantRouteChanged ='));
      expect(
        source,
        contains(
          'resolvedTenantId == _validatedTenantId &&\n'
          '            purchaseAuthoritySurvivesRefreshFailure(',
        ),
      );
      expect(
        source,
        contains(
          '_isProductValidated = false;\n'
          '          _productValidationFailed = true;\n'
          '          _lastValidatedAt = null;\n'
          '          _validatedTenantId = null;',
        ),
      );
    });

    test('route-local interaction state never crosses product or tenant', () {
      final reset =
          source.split('void _resetRouteLocalUiState()')[1].split('\n  }')[0];
      for (final field in <String>[
        '_justAddedResetTimer?.cancel()',
        '_justAddedToCart = false',
        '_hideProductFeedbackBanner(animated: false)',
        '_selectedDetailsTab = 0',
        '_quantity = 1',
        '_selectedImageIndex = 0',
        '_trackedProductIdForRoute = null',
      ]) {
        expect(reset, contains(field));
      }
      expect(
        source
            .split('if (widget.productId != oldWidget.productId) {')[1]
            .split('removeStructuredDataScript')[0],
        contains('_resetRouteLocalUiState()'),
      );
      expect(
        source.split('if (tenantRouteChanged) {')[1].split('_loadToken++')[0],
        contains('_resetRouteLocalUiState()'),
      );
      expect(source, contains('images[selectedImageIndex]'));
    });

    test('transport failure is retryable and distinct from confirmed absence',
        () {
      final catchWithoutProduct = source
          .split(
            'if (mounted && token == _loadToken && _product == null) {',
          )[1]
          .split('} else if')[0];
      expect(catchWithoutProduct, contains('_productValidationFailed = true'));
      expect(source, contains("'No se pudo cargar el producto'"));
      expect(source, contains("ValueKey('product-detail-retry')"));
      expect(source, contains("'Producto no encontrado'"));

      final aliasLookup = source
          .split('Future<String?> _resolveProductAlias(')[1]
          .split('void _scheduleCanonicalProductUrlReplacement')[0];
      expect(aliasLookup, contains('rethrow;'));
      expect(aliasLookup, isNot(contains('return null;\n    } catch')));
    });

    test('only the newest related-products request may update the page', () {
      expect(source, contains('int _relatedRequestGeneration = 0;'));
      expect(source, contains('relatedProductsRequestStillOwnsPage('));
      expect(source, contains('requestGeneration: requestGeneration'));
    });
  });
}
