import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_center_models.dart';
import 'package:vinabike_erp/modules/website/services/website_seo_center_service.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  group('WebsiteSeoCenterService', () {
    test('keeps app, deployed build and Google as independent planes',
        () async {
      var calls = 0;
      final observedAt = DateTime.utc(2026, 7, 28, 20);
      final service = WebsiteSeoCenterService(
        clock: () => observedAt,
        siteStatusLoader: () async {
          calls += 1;
          return _completeSiteStatusPayload(observedAt);
        },
      );
      final site = _siteOwner();
      final page = WebsiteSeoPageOwner.fromPage(
        page: _page(
          id: 'page-products',
          title: 'Productos',
          slug: 'productos',
          isPublished: true,
        ),
        site: site,
      );

      final result = await service.load(
        WebsiteSeoCenterOwners(site: site, pages: [page]),
      );

      expect(calls, 1);
      expect(result.site.appEligibility.isEligible, isTrue);
      expect(
        result.site.buildEvidence.state,
        WebsiteSeoBuildInclusionState.included,
      );
      // A submitted/downloaded sitemap is dated Google evidence, not proof
      // that either the site or one route is indexed.
      expect(
        result.site.googleEvidence.state,
        WebsiteSeoGoogleIndexState.unknown,
      );
      expect(result.site.googleEvidence.sitemapSubmitted, isTrue);
      expect(
        result.pages.single.buildEvidence.state,
        WebsiteSeoBuildInclusionState.unknown,
      );
      expect(
        result.pages.single.googleEvidence.state,
        WebsiteSeoGoogleIndexState.unknown,
      );
      expect(result.pagesSummary.appEligible, 1);
      expect(result.pagesSummary.buildUnknown, 1);
      expect(result.pagesSummary.googleUnknown, 1);
    });

    test('tolerates an absent site_status action without losing app truth',
        () async {
      final now = DateTime.utc(2026, 7, 28, 21);
      final service = WebsiteSeoCenterService(
        clock: () => now,
        siteStatusLoader: () async {
          throw StateError('Unknown action: site_status');
        },
      );

      final result = await service.load(
        WebsiteSeoCenterOwners(site: _siteOwner()),
      );

      expect(result.siteStatus.available, isFalse);
      expect(
        result.siteStatus.error,
        'No se pudo consultar la evidencia técnica del sitio.',
      );
      expect(result.siteStatus.error, isNot(contains('Unknown action')));
      expect(result.site.appEligibility.isEligible, isTrue);
      expect(
        result.site.buildEvidence.state,
        WebsiteSeoBuildInclusionState.unknown,
      );
      expect(
        result.site.googleEvidence.state,
        WebsiteSeoGoogleIndexState.unavailable,
      );
    });

    test('does not promote dirty builds, root robots blocks or Google errors',
        () async {
      final observedAt = DateTime.utc(2026, 7, 28, 21, 30);
      final payload = _completeSiteStatusPayload(observedAt);
      final artifacts = payload['artifacts']! as Map<String, dynamic>;
      final release = artifacts['release']! as Map<String, dynamic>;
      final robots = artifacts['robots']! as Map<String, dynamic>;
      final searchConsole = payload['searchConsole']! as Map<String, dynamic>;
      release['dirty'] = true;
      robots['rootDisallowDirectivePresent'] = true;
      searchConsole['ok'] = false;
      searchConsole['error'] = 'Search Console respondió 403.';

      final result = await WebsiteSeoCenterService(
        clock: () => observedAt,
        siteStatusLoader: () async => payload,
      ).load(WebsiteSeoCenterOwners(site: _siteOwner()));

      expect(
        result.site.buildEvidence.state,
        WebsiteSeoBuildInclusionState.unknown,
      );
      expect(
        result.site.googleEvidence.state,
        WebsiteSeoGoogleIndexState.unavailable,
      );
      expect(result.site.googleEvidence.error, contains('403'));
    });

    test('reports effective owner values and inheritance without flattening',
        () {
      final site = _siteOwner();
      final pageOwner = WebsiteSeoPageOwner.fromPage(
        page: _page(
          id: 'page-contact',
          title: 'Contacto',
          slug: 'contacto',
          isPublished: true,
          metaTitle: 'Contacto y taller en Viña del Mar',
        ),
        site: site,
      );
      final collectionOwner = WebsiteSeoCollectionOwner.fromPresentation(
        id: 'category-cadenas',
        label: 'Cadenas',
        canonicalPath: '/productos/categoria/cadenas',
        isPublished: true,
        hasEligibleContent: true,
        presentation: WebsiteCatalogPresentation(
          categoryId: 'category-cadenas',
          slug: 'cadenas',
          heroTitle: 'Cadenas para bicicleta',
        ),
        site: site,
      );
      final productOwner = WebsiteSeoProductOwner.fromProduct(
        product: _product(
          id: 'product-chain',
          name: 'Cadena KMC Z8.3',
          sku: 'KMC-Z83',
          categoryId: 'category-cadenas',
          websiteSeoTitle: 'Cadena KMC Z8.3 para bicicleta',
        ),
        site: site,
        titleTemplate: '{product_name} | {store_name}',
        descriptionTemplate: '{product_description}',
        categoryPath: 'Transmisión / Cadenas',
      );

      expect(
        pageOwner.metadata.title.source,
        WebsiteSeoValueSource.explicit,
      );
      expect(
        pageOwner.metadata.description.source,
        WebsiteSeoValueSource.inherited,
      );
      expect(
        pageOwner.metadata.description.ownerKind,
        WebsiteSeoEntityKind.site,
      );
      expect(
        collectionOwner.metadata.title.source,
        WebsiteSeoValueSource.ownerFallback,
      );
      expect(
        collectionOwner.metadata.imageUrl.source,
        WebsiteSeoValueSource.inherited,
      );
      expect(
        productOwner.metadata.title.source,
        WebsiteSeoValueSource.explicit,
      );
      expect(
        productOwner.canonicalPath,
        '/productos/cadena-kmc-z8-3/KMC-Z83',
      );
    });

    test('preserves exactly five published categories as neutral collections',
        () async {
      final service = WebsiteSeoCenterService(
        clock: () => DateTime.utc(2026, 7, 28, 22),
        siteStatusLoader: () async => const {'error': 'Unknown action'},
      );
      final categories = <Category>[
        for (var index = 1; index <= 5; index += 1)
          Category(
            id: 'category-$index',
            tenantId: 'tenant',
            name: 'Categoría $index',
            fullPath: 'Componentes / Categoría $index',
            showOnWebsite: true,
          ),
        Category(
          id: 'category-hidden',
          tenantId: 'tenant',
          name: 'No publicada',
          fullPath: 'Componentes / No publicada',
          showOnWebsite: false,
        ),
      ];
      final owners = service.buildOwnersFromLoadedServices(
        settings: const {
          'store_name': 'Viñabike',
          'store_url': 'https://vinabike.cl',
          'seo_meta_title': 'Viñabike',
          'seo_meta_description': 'Tienda y taller de bicicletas.',
          'seo_og_image': 'https://vinabike.cl/logo.png',
        },
        pages: const [],
        categories: categories,
        products: [
          _product(
            id: 'product-1',
            name: 'Cadena publicada',
            sku: 'CHAIN-1',
            categoryId: 'category-1',
          ),
        ],
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      );

      // Every active category is inventoried, but publication is untouched:
      // exactly the five flagged rows remain published.
      expect(owners.collections, hasLength(6));
      expect(
        owners.collections.map((owner) => owner.id),
        contains('category-hidden'),
      );
      expect(
        owners.collections.where((owner) => owner.isPublished).map((o) => o.id),
        {'category-1', 'category-2', 'category-3', 'category-4', 'category-5'},
      );
      expect(
        owners.collections
            .firstWhere((owner) => owner.id == 'category-hidden')
            .isPublished,
        isFalse,
      );

      final result = await service.load(owners);

      expect(result.collections, hasLength(6));
      expect(result.categoryOwnerTotal, 6);
      expect(result.publishedCategoryOwnerCount, 5);
      expect(result.unpublishedCategoryOwnerCount, 1);
      expect(result.collectionsSummary.total, 6);
      expect(result.collectionsSummary.buildUnknown, 6);
      expect(result.collectionsSummary.googleUnknown, 6);
      // Empty, disabled or unpublished collections remain visible as
      // diagnostics; they are never dropped or relabeled as deployed/indexed.
      expect(result.collectionsSummary.appEligible, 1);
      expect(result.collectionsSummary.appIneligible, 5);

      // The unpublished row carries the reason, and only that reason —
      // appearing in the inventory grants it nothing.
      final hidden = result.collections.firstWhere(
        (collection) => collection.id == 'category-hidden',
      );
      expect(
        hidden.appEligibility.blockingIssues,
        contains(WebsiteSeoAppEligibilityIssue.ownerNotPublished),
      );
      expect(
          result.unpublishedCollections.map((c) => c.id), ['category-hidden']);
      expect(
        result.publishedCollections.map((c) => c.id),
        isNot(contains('category-hidden')),
      );
    });

    test('uses the canonical public-product set for exact eligibility', () {
      final service = WebsiteSeoCenterService(
        siteStatusLoader: () async => const {},
      );
      final owners = service.buildOwnersFromLoadedServices(
        settings: const {
          'store_name': 'Viñabike',
          'store_url': 'https://vinabike.cl',
          'seo_meta_title': 'Viñabike',
          'seo_meta_description': 'Tienda y taller de bicicletas.',
        },
        pages: const [],
        categories: [
          Category(
            id: 'category-public',
            tenantId: 'tenant',
            name: 'Publicada',
            fullPath: 'Componentes / Publicada',
            showOnWebsite: true,
          ),
          Category(
            id: 'category-empty',
            tenantId: 'tenant',
            name: 'Sin productos públicos',
            fullPath: 'Componentes / Sin productos públicos',
            showOnWebsite: true,
          ),
        ],
        products: [
          _product(
            id: 'product-public',
            name: 'Producto público',
            sku: 'PUBLIC-1',
            categoryId: 'category-public',
          ),
          // This row still looks active in the internal inventory projection.
          // It must remain in the diagnostic list but cannot be promoted to
          // public eligibility unless the canonical public RPC returned it.
          _product(
            id: 'product-internal-only',
            name: 'Producto interno',
            sku: 'INTERNAL-1',
            categoryId: 'category-empty',
          ),
        ],
        eligibleProductIds: const {'product-public'},
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
      );

      expect(owners.products, hasLength(2));
      expect(
        owners.products
            .singleWhere((owner) => owner.id == 'product-public')
            .project()
            .appEligibility
            .isEligible,
        isTrue,
      );
      expect(
        owners.products
            .singleWhere((owner) => owner.id == 'product-internal-only')
            .project()
            .appEligibility
            .isEligible,
        isFalse,
      );
      final internalOnlyIssues = owners.products
          .singleWhere((owner) => owner.id == 'product-internal-only')
          .project()
          .appEligibility
          .blockingIssues;
      expect(
        internalOnlyIssues,
        contains(WebsiteSeoAppEligibilityIssue.publicPolicyExcluded),
      );
      expect(
        internalOnlyIssues,
        isNot(contains(WebsiteSeoAppEligibilityIssue.ownerNotPublished)),
      );
      expect(
        owners.collections
            .singleWhere((owner) => owner.id == 'category-public')
            .project()
            .appEligibility
            .isEligible,
        isTrue,
      );
      expect(
        owners.collections
            .singleWhere((owner) => owner.id == 'category-empty')
            .project()
            .appEligibility
            .isEligible,
        isFalse,
      );
    });

    test('labels search-term enriched product copy as generated', () {
      final owner = WebsiteSeoProductOwner.fromProduct(
        product: _product(
          id: 'product-search-copy',
          name: 'Cadena KMC Z8.3',
          sku: 'KMC-Z83',
          categoryId: 'category-cadenas',
          websiteSearchTerms: const ['cadena bicicleta Viña del Mar'],
        ),
        site: WebsiteSeoSiteOwner(
          storeName: 'Viñabike',
          origin: 'https://vinabike.cl',
          title: 'Viñabike',
          description: 'Tienda y taller de bicicletas.',
          imageUrl: 'https://vinabike.cl/logo.png',
          keywords: 'bicicletas',
          locality: 'Viña del Mar',
        ),
        titleTemplate: '{product_name} | {store_name}',
        descriptionTemplate: '{product_description}',
        categoryPath: 'Transmisión / Cadenas',
      );

      expect(owner.metadata.title.source, WebsiteSeoValueSource.ownerFallback);
      expect(
        owner.metadata.description.source,
        WebsiteSeoValueSource.ownerFallback,
      );
      expect(owner.metadata.title.value, contains('Cadena bicicleta'));
      expect(
        owner.metadata.description.value,
        contains('cadena bicicleta Viña del Mar'),
      );
      expect(
        owner.metadata.keywords.value,
        'cadena bicicleta Viña del Mar',
      );
    });

    test('requires an HTTPS canonical origin for site eligibility', () {
      final site = WebsiteSeoSiteOwner(
        storeName: 'Viñabike',
        origin: 'http://vinabike.cl',
        title: 'Viñabike',
        description: 'Tienda y taller de bicicletas.',
        imageUrl: 'https://vinabike.cl/logo.png',
      ).project();

      expect(site.canonicalPath, isEmpty);
      expect(site.appEligibility.isEligible, isFalse);
      expect(
        site.appEligibility.blockingIssues,
        contains(WebsiteSeoAppEligibilityIssue.missingCanonicalPath),
      );
    });
  });
}

WebsiteSeoSiteOwner _siteOwner() {
  return WebsiteSeoSiteOwner(
    storeName: 'Viñabike',
    origin: 'https://vinabike.cl',
    title: 'Viñabike | Tienda y taller',
    description: 'Tienda y taller de bicicletas en Viña del Mar.',
    imageUrl: 'https://vinabike.cl/logo.png',
    keywords: 'bicicletas, taller',
  );
}

WebsitePage _page({
  required String id,
  required String title,
  required String slug,
  required bool isPublished,
  String? metaTitle,
}) {
  final timestamp = DateTime.utc(2026, 7, 28);
  return WebsitePage(
    id: id,
    tenantId: 'tenant',
    slug: slug,
    title: title,
    metaTitle: metaTitle,
    isPublished: isPublished,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Product _product({
  required String id,
  required String name,
  required String sku,
  required String categoryId,
  String? websiteSeoTitle,
  List<String> websiteSearchTerms = const [],
}) {
  return Product.fromJson({
    'id': id,
    'name': name,
    'sku': sku,
    'price': 15990,
    'cost': 8000,
    'inventory_qty': 2,
    'stock_quantity': 2,
    'description': 'Repuesto para bicicleta con información real del catálogo.',
    'image_url': 'https://vinabike.cl/$id.png',
    'category': 'other',
    'category_id': categoryId,
    'category_name': 'Categoría',
    'brand': 'KMC',
    'gtin': '1234567890128',
    'website_seo_title': websiteSeoTitle,
    'website_search_terms': websiteSearchTerms,
    'is_active': true,
    'is_published': true,
    'show_on_website': true,
    'lifecycle_status': 'active',
    'created_at': '2026-07-28T00:00:00Z',
    'updated_at': '2026-07-28T00:00:00Z',
  });
}

Map<String, dynamic> _completeSiteStatusPayload(DateTime observedAt) {
  Map<String, dynamic> http(String url) => {
        'url': url,
        'observedAt': observedAt.toIso8601String(),
        'reachable': true,
        'httpOk': true,
        'status': 200,
        'durationMs': 25,
        'contentType': 'application/json',
        'etag': '"etag"',
        'lastModified': 'Tue, 28 Jul 2026 20:00:00 GMT',
        'timedOut': false,
        'error': null,
      };

  return {
    'ok': true,
    'observedAt': observedAt.toIso8601String(),
    'origin': 'https://vinabike.cl',
    'siteUrl': 'sc-domain:vinabike.cl',
    'artifacts': {
      'origin': 'https://vinabike.cl',
      'release': {
        ...http('https://vinabike.cl/release.json'),
        'documentValid': true,
        'parseError': null,
        'commit': 'abc123',
        'run': 'run-42',
        'builtAt': '2026-07-28T19:55:00Z',
        'target': 'store',
        'source': 'github-actions',
        'dirty': false,
      },
      'sitemap': {
        ...http('https://vinabike.cl/sitemap.xml'),
        'documentValid': true,
        'hasUrlset': true,
        'urlEntryCount': 558,
        'locationCount': 558,
        'locationsMatchEntries': true,
        'invalidLocationCount': 0,
        'foreignOriginCount': 0,
        'canonicalOriginConsistent': true,
      },
      'robots': {
        ...http('https://vinabike.cl/robots.txt'),
        'documentValid': true,
        'hasWildcardUserAgent': true,
        'expectedSitemapDeclared': true,
        'sitemapUrls': ['https://vinabike.cl/sitemap.xml'],
        'userAgentCount': 1,
        'disallowDirectiveCount': 0,
        'rootDisallowDirectivePresent': false,
      },
      'summary': {
        'allReachable': true,
        'allHttpOk': true,
        'allDocumentsValid': true,
      },
    },
    'searchConsole': {
      'configured': true,
      'ok': true,
      'submitted': true,
      'sitemapUrl': 'https://vinabike.cl/sitemap.xml',
      'lastSubmitted': '2026-07-27T20:00:00Z',
      'lastDownloaded': '2026-07-28T18:00:00Z',
      'isPending': false,
      'warnings': 0,
      'errors': 0,
    },
    'indexingDisclaimer': 'La evidencia no garantiza rastreo ni indexación.',
  };
}
