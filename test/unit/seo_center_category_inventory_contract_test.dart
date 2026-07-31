import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';
import 'package:vinabike_erp/modules/website/services/website_seo_center_service.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_category_publication.dart';

/// Two contracts that must hold together, and only together.
///
/// 1. **Internal inventory is complete.** The SEO center lists every active
///    category, published or not, so "why is this category not on the site?"
///    has an answer with a reason and an action. A category missing from the
///    center is indistinguishable from a category that does not exist.
///
/// 2. **Public projection stays narrow.** Being inventoried grants nothing.
///    `product_categories.show_on_website` remains the single publisher, so an
///    unpublished category never reaches the mega-menu, public navigation, the
///    sitemap or an indexable snapshot.
///
/// Asserting only the first would let a diagnostic surface widen publication.
/// Asserting only the second would let the center keep hiding the problem.
void main() {
  Category category(String id, {required bool published, String? parentId}) {
    return Category(
      id: id,
      tenantId: 'tenant',
      name: id,
      fullPath: parentId == null ? id : '$parentId / $id',
      parentId: parentId,
      showOnWebsite: published,
    );
  }

  const settings = {
    'store_name': 'Tienda',
    'store_url': 'https://example.cl',
    'seo_meta_title': 'Tienda',
    'seo_meta_description': 'Descripción base.',
    'seo_og_image': 'https://example.cl/logo.png',
  };

  Future<WebsiteSeoCenterProjection> project(
    List<Category> categories,
  ) async {
    final service = WebsiteSeoCenterService(
      clock: () => DateTime.utc(2026, 7, 28, 23),
      siteStatusLoader: () async => const {'error': 'Unknown action'},
    );
    return service.load(
      service.buildOwnersFromLoadedServices(
        settings: settings,
        pages: const <WebsitePage>[],
        categories: categories,
        products: const [],
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      ),
    );
  }

  group('contract 1: the center inventories every active category', () {
    test('lists published and unpublished rows alike', () async {
      final result = await project([
        category('publicada-a', published: true),
        category('publicada-b', published: true),
        category('interna-a', published: false),
        category('interna-b', published: false),
        category('interna-c', published: false),
      ]);

      expect(result.collections, hasLength(5));
      expect(result.categoryOwnerTotal, 5);
      expect(result.publishedCategoryOwnerCount, 2);
      expect(result.unpublishedCategoryOwnerCount, 3);
    });

    test('isPublished mirrors showOnWebsite exactly', () async {
      final service = WebsiteSeoCenterService(
        siteStatusLoader: () async => const {},
      );
      final owners = service.buildOwnersFromLoadedServices(
        settings: settings,
        pages: const <WebsitePage>[],
        categories: [
          category('si', published: true),
          category('no', published: false),
        ],
        products: const [],
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      );

      for (final owner in owners.collections) {
        expect(
          owner.isPublished,
          owner.id == 'si',
          reason: '${owner.id} must mirror show_on_website',
        );
      }
    });

    test('an unpublished row states the reason as its blocking issue',
        () async {
      final result = await project([
        category('interna', published: false),
      ]);

      final row = result.collections.single;
      expect(
        row.appEligibility.blockingIssues,
        contains(WebsiteSeoAppEligibilityIssue.ownerNotPublished),
      );
      expect(row.appEligibility.isEligible, isFalse);
      // The row still carries the route it would occupy, so the operator can
      // see what publishing would produce.
      expect(row.canonicalPath, startsWith('/productos/categoria/'));
    });

    test('an unpublished category is never counted as published', () async {
      final result = await project([
        category('interna', published: false),
      ]);

      expect(result.publishedCategoryOwnerCount, 0);
      expect(result.publishedCollections, isEmpty);
      expect(result.unpublishedCollections.map((c) => c.id), ['interna']);
      expect(result.collectionsSummary.appEligible, 0);
    });

    test('a hidden descendant of a published parent stays unpublished',
        () async {
      // Hidden descendants still contribute products to a published ancestor,
      // but that must never publish the descendant itself.
      final result = await project([
        category('padre', published: true),
        category('hijo-oculto', published: false, parentId: 'padre'),
      ]);

      expect(result.publishedCollections.map((c) => c.id), ['padre']);
      expect(result.unpublishedCollections.map((c) => c.id), ['hijo-oculto']);
    });
  });

  group('contract 2: an unpublished category reaches no public surface', () {
    PublicCategoryDescriptor descriptor(String id, {required bool published}) {
      return PublicCategoryDescriptor(
        id: id,
        name: id,
        fullPath: id,
        showOnWebsite: published,
      );
    }

    test('publishedIds is the flag alone', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          descriptor('publicada', published: true),
          descriptor('interna', published: false),
        ],
        navigation: const [],
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      );

      expect(publication.publishedIds, {'publicada'});
      expect(publication.isPublished('interna'), isFalse);
      expect(publication.isPublished('publicada'), isTrue);
    });

    test('a menu row cannot publish a category', () {
      // The mega-menu and public navigation consume this projection, so a
      // stale menu row pointing at an unpublished category is a diagnostic,
      // never a destination.
      final publication = PublicCategoryPublication.resolve(
        categories: [descriptor('interna', published: false)],
        navigation: [_categoryNav('Interna', 'interna')],
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      );

      expect(publication.publishedIds, isEmpty);
      expect(publication.menuOnlyCategoryIds, contains('interna'));

      final projection = PublicCategoryNavigationProjection(publication);
      expect(
        projection.forDesktop([_categoryNav('Interna', 'interna')]),
        isEmpty,
      );
      expect(
        projection.forMobile([_categoryNav('Interna', 'interna')]),
        isEmpty,
      );
      expect(
          projection.canNavigate(_categoryNav('Interna', 'interna')), isFalse);
    });

    test('the mega-menu host really consumes that projection', () {
      // Without this, the projection assertions above could stay green while
      // the header rendered raw navigation rows and published a category by
      // showing it.
      final layout = _readSource(
        'lib/public_store/widgets/public_store_layout.dart',
      );
      expect(layout, contains('PublicCategoryNavigationProjection('));
      expect(layout, contains('categoryNavigationProjection.forDesktop('));
      expect(layout, contains('categoryNavigationProjection.forMobile('));
    });

    test('the snapshot and sitemap generator gates on the same flag', () {
      // The generator is outside this partition; this asserts the gate that
      // keeps an unpublished category out of the crawlable artifacts.
      final generator = _readSource(
        'scripts/generate_product_seo_snapshots.dart',
      );
      expect(
          generator, contains("if (row['show_on_website'] != true) continue"));
      expect(
        generator,
        contains('only\n/// `show_on_website` categories may produce '
            'collection pages'),
      );
    });
  });

  test('the center never widens publication for a public consumer', () async {
    // The bridge assertion: the same unpublished id is present in the internal
    // inventory and absent from the public publication set.
    final center = await project([
      category('publicada', published: true),
      category('interna', published: false),
    ]);
    final publication = PublicCategoryPublication.resolve(
      categories: const [
        PublicCategoryDescriptor(
          id: 'publicada',
          name: 'publicada',
          fullPath: 'publicada',
          showOnWebsite: true,
        ),
        PublicCategoryDescriptor(
          id: 'interna',
          name: 'interna',
          fullPath: 'interna',
          showOnWebsite: false,
        ),
      ],
      navigation: const [],
      presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
    );

    final inventoried = center.collections.map((c) => c.id).toSet();
    expect(inventoried, {'publicada', 'interna'});
    expect(publication.publishedIds, {'publicada'});
    expect(
      inventoried.difference(publication.publishedIds),
      {'interna'},
      reason: 'inventoried but not published is exactly the intended gap',
    );
  });
}

WebsiteNavigation _categoryNav(String label, String linkValue) {
  final now = DateTime.utc(2026, 1, 1);
  return WebsiteNavigation(
    id: 'nav-$linkValue',
    tenantId: 'tenant',
    label: label,
    linkType: NavLinkType.category,
    linkValue: linkValue,
    isVisible: true,
    showOnDesktop: true,
    showOnMobile: true,
    children: const [],
    createdAt: now,
    updatedAt: now,
  );
}

String _readSource(String path) => File(path).readAsStringSync();
