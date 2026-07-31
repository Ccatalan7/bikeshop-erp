import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/public_store/models/product_purchase_authority.dart';
import 'package:vinabike_erp/public_store/utils/category_trail.dart';

/// Behavioral coverage for the product page's stale-while-revalidate seams.
///
/// These drive the extracted decision logic through the real sequences the
/// page experiences — first frame from a warm catalog cache, the ~30 s
/// freshness pulse succeeding and failing, authority expiring, a category
/// being renamed or moved — rather than asserting on source strings.
void main() {
  group('purchase authority across refresh outcomes', () {
    final t0 = DateTime.utc(2026, 7, 28, 12, 0, 0);

    test('a refresh failure right after validation keeps the page selling', () {
      expect(
        purchaseAuthoritySurvivesRefreshFailure(
          lastValidatedAt: t0,
          now: t0.add(const Duration(seconds: 45)),
        ),
        isTrue,
      );
      // …and the row is honest about it: last-known-good, never a green check.
      expect(
        productAvailabilityRowState(validated: true, refreshFailed: true),
        ProductAvailabilityRowState.staleConfirmed,
      );
    });

    test('authority is bounded: past the window a failing page stops selling',
        () {
      expect(
        purchaseAuthoritySurvivesRefreshFailure(
          lastValidatedAt: t0,
          now: t0
              .add(productPurchaseAuthorityWindow)
              .add(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(
        productAvailabilityRowState(validated: false, refreshFailed: true),
        ProductAvailabilityRowState.unavailable,
      );
    });

    test('exactly at the window boundary authority still holds', () {
      expect(
        purchaseAuthoritySurvivesRefreshFailure(
          lastValidatedAt: t0,
          now: t0.add(productPurchaseAuthorityWindow),
        ),
        isTrue,
      );
    });

    test('no prior validation means a failure never grants authority', () {
      expect(
        purchaseAuthoritySurvivesRefreshFailure(lastValidatedAt: null, now: t0),
        isFalse,
      );
    });

    test('a clock that moved backwards is treated as no authority', () {
      expect(
        purchaseAuthoritySurvivesRefreshFailure(
          lastValidatedAt: t0.add(const Duration(minutes: 5)),
          now: t0,
        ),
        isFalse,
      );
    });

    test('a successful refresh always reads as confirmed, never stale', () {
      expect(
        productAvailabilityRowState(validated: true, refreshFailed: false),
        ProductAvailabilityRowState.confirmed,
      );
    });

    test('first arrival without data reads as refreshing', () {
      expect(
        productAvailabilityRowState(validated: false, refreshFailed: false),
        ProductAvailabilityRowState.refreshing,
      );
    });
  });

  group('related-product request ownership', () {
    test('a newer same-route request invalidates the older category response',
        () {
      expect(
        relatedProductsRequestStillOwnsPage(
          requestGeneration: 1,
          activeGeneration: 2,
          routeToken: 7,
          activeRouteToken: 7,
          requestedProductId: 'product-a',
          visibleProductId: 'product-a',
        ),
        isFalse,
      );
    });

    test('the latest response applies only to the still-visible product', () {
      expect(
        relatedProductsRequestStillOwnsPage(
          requestGeneration: 2,
          activeGeneration: 2,
          routeToken: 7,
          activeRouteToken: 7,
          requestedProductId: 'product-a',
          visibleProductId: 'product-a',
        ),
        isTrue,
      );
      expect(
        relatedProductsRequestStillOwnsPage(
          requestGeneration: 2,
          activeGeneration: 2,
          routeToken: 7,
          activeRouteToken: 8,
          requestedProductId: 'product-a',
          visibleProductId: 'product-b',
        ),
        isFalse,
      );
    });
  });

  group('first-frame breadcrumb trail from the warm catalog cache', () {
    Category category(
      String id,
      String name, {
      String? parentId,
      bool showOnWebsite = false,
    }) =>
        Category(
          id: id,
          tenantId: 'tenant',
          name: name,
          fullPath: name,
          parentId: parentId,
          level: 0,
          isActive: true,
          showOnWebsite: showOnWebsite,
        );

    final catalogCache = <Category>[
      category('root', 'Componentes'),
      category('mid', 'Transmisión', parentId: 'root'),
      category('leaf', 'Cadenas', parentId: 'mid'),
      category('other', 'Accesorios'),
    ];

    test('the complete trail derives synchronously — no short-crumb morph', () {
      final trail = categoryTrailFromCategories(catalogCache, 'leaf');
      expect(trail, isNotNull);
      expect(trail!.map((c) => c.name).toList(),
          ['Componentes', 'Transmisión', 'Cadenas']);
    });

    test('no cache means no answer, so the caller falls back to origin', () {
      expect(categoryTrailFromCategories(null, 'leaf'), isNull);
    });

    test('an uncategorized product has an empty trail, not a null one', () {
      expect(categoryTrailFromCategories(catalogCache, null), isEmpty);
      expect(categoryTrailFromCategories(catalogCache, '  '), isEmpty);
    });

    test('an unknown ancestor truncates the trail instead of failing', () {
      final orphaned = [category('leaf', 'Cadenas', parentId: 'gone')];
      final trail = categoryTrailFromCategories(orphaned, 'leaf');
      expect(trail!.map((c) => c.name).toList(), ['Cadenas']);
    });

    test('a parent cycle terminates', () {
      final cyclic = [
        category('a', 'A', parentId: 'b'),
        category('b', 'B', parentId: 'a'),
      ];
      final trail = categoryTrailFromCategories(cyclic, 'a');
      expect(trail!.length, 2);
    });

    test('the pulse does not churn state when nothing changed', () {
      final first = categoryTrailFromCategories(catalogCache, 'leaf')!;
      final second = categoryTrailFromCategories(catalogCache, 'leaf')!;
      expect(sameCategoryTrail(first, second), isTrue);
    });

    test('a renamed category is a real change and must apply', () {
      final before = categoryTrailFromCategories(catalogCache, 'leaf')!;
      final renamed = [
        for (final c in catalogCache)
          c.id == 'mid'
              ? Category(
                  id: c.id,
                  tenantId: c.tenantId,
                  name: 'Drivetrain',
                  fullPath: 'Drivetrain',
                  parentId: c.parentId,
                  level: c.level,
                  isActive: c.isActive,
                )
              : c,
      ];
      final after = categoryTrailFromCategories(renamed, 'leaf')!;
      expect(sameCategoryTrail(before, after), isFalse);
    });

    test('a re-parented category is a real change and must apply', () {
      final moved = [
        for (final c in catalogCache)
          c.id == 'leaf'
              ? Category(
                  id: c.id,
                  tenantId: c.tenantId,
                  name: c.name,
                  fullPath: c.fullPath,
                  parentId: 'other',
                  level: c.level,
                  isActive: c.isActive,
                )
              : c,
      ];
      final before = categoryTrailFromCategories(catalogCache, 'leaf')!;
      final after = categoryTrailFromCategories(moved, 'leaf')!;
      expect(after.map((c) => c.name).toList(), ['Accesorios', 'Cadenas']);
      expect(sameCategoryTrail(before, after), isFalse);
    });

    test('withdrawing a category is a real change and removes its link', () {
      final before = [
        category('leaf', 'Cadenas', showOnWebsite: true),
      ];
      final after = [
        category('leaf', 'Cadenas', showOnWebsite: false),
      ];

      expect(sameCategoryTrail(before, after), isFalse);
      expect(
        productBreadcrumbCategories(authoritativeTrail: after)
            .single
            .showOnWebsite,
        isFalse,
      );
    });

    test('the derived trail is immutable', () {
      final trail = categoryTrailFromCategories(catalogCache, 'leaf')!;
      expect(() => trail.add(catalogCache.first), throwsUnsupportedError);
    });

    test('an authoritative published trail preserves navigable owners', () {
      final trail = [
        category('root', 'Componentes'),
        category('leaf', 'Cadenas', showOnWebsite: true),
      ];

      final breadcrumb = productBreadcrumbCategories(
        authoritativeTrail: trail,
        fallbackCategoryId: 'denormalized-id',
        fallbackCategoryName: 'Texto antiguo',
      );

      expect(breadcrumb.map((value) => value.id), ['root', 'leaf']);
      expect(breadcrumb.last.showOnWebsite, isTrue);
    });

    test('a denormalized fallback is factual text, never a public link', () {
      final breadcrumb = productBreadcrumbCategories(
        authoritativeTrail: const [],
        fallbackCategoryId: 'hidden-category',
        fallbackCategoryName: 'Piñones',
      );

      expect(breadcrumb, hasLength(1));
      expect(breadcrumb.single.name, 'Piñones');
      expect(breadcrumb.single.showOnWebsite, isFalse);
    });

    test('an incomplete denormalized fallback is omitted', () {
      expect(
        productBreadcrumbCategories(
          authoritativeTrail: const [],
          fallbackCategoryId: '',
          fallbackCategoryName: 'Piñones',
        ),
        isEmpty,
      );
    });
  });
}
