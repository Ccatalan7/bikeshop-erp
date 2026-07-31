import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../public_store/services/public_inventory_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/models/public_product_visibility_policy.dart';
import '../../inventory/models/category_models.dart';
import '../models/website_catalog_presentation.dart';
import '../models/website_page_models.dart';
import '../models/website_seo_center_models.dart';
import 'website_service.dart';

typedef WebsiteSeoSiteStatusLoader = Future<Object?> Function();
typedef WebsiteSeoClock = DateTime Function();

/// Read-only aggregation boundary for the future SEO control center.
///
/// The service deliberately keeps three independent planes:
///
/// * current app eligibility, derived from canonical editable owners;
/// * evidence from the last deployed build;
/// * dated evidence reported by Google.
///
/// A positive result in one plane is never promoted to either of the others.
class WebsiteSeoCenterService {
  WebsiteSeoCenterService({
    WebsiteSeoSiteStatusLoader? siteStatusLoader,
    WebsiteSeoClock? clock,
  })  : _siteStatusLoader = siteStatusLoader ?? _invokeSiteStatus,
        _clock = clock ?? DateTime.now;

  final WebsiteSeoSiteStatusLoader _siteStatusLoader;
  final WebsiteSeoClock _clock;

  /// Projects already-loaded canonical owners and obtains optional deploy /
  /// Search Console evidence through the `site_status` Edge action.
  Future<WebsiteSeoCenterProjection> load(
    WebsiteSeoCenterOwners owners,
  ) async {
    final status = await _loadSiteStatus();
    return _project(owners, status);
  }

  /// Canonical loading helper for UI consumers.
  ///
  /// Callers supply the existing provider-owned services and never issue their
  /// own Supabase queries. The helper uses their normal tenant-scoped loaders,
  /// then builds the exact same typed projection as [load].
  Future<WebsiteSeoCenterProjection> loadFromServices({
    required String tenantId,
    required WebsiteService websiteService,
    required PublicInventoryService publicInventoryService,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw ArgumentError.value(
        tenantId,
        'tenantId',
        'Debe existir una tienda activa.',
      );
    }

    final siteStatusFuture = _loadSiteStatus();
    late Map<String, String> settings;
    late List<Category> categories;
    late List<Product> products;

    await Future.wait<void>([
      () async {
        settings = await websiteService.loadSettingsForTenant(
          normalizedTenantId,
          rethrowErrors: true,
        );
      }(),
      websiteService.loadPagesForTenant(
        normalizedTenantId,
        rethrowErrors: true,
      ),
      () async {
        categories = await publicInventoryService.getCategoriesForTenant(
          tenantId: normalizedTenantId,
          forceRefresh: true,
        );
      }(),
      () async {
        products = await _loadAllInternalProducts(
          tenantId: normalizedTenantId,
          publicInventoryService: publicInventoryService,
        );
      }(),
    ]);
    final visibilityPolicy =
        PublicProductVisibilityPolicy.fromSettings(settings);
    final eligibleProducts = await _loadAllPublicProducts(
      tenantId: normalizedTenantId,
      publicInventoryService: publicInventoryService,
      policy: visibilityPolicy,
    );
    final eligibleProductIds = <String>{
      for (final product in eligibleProducts) product.id.trim(),
    };

    final owners = buildOwnersFromLoadedServices(
      settings: settings,
      pages: websiteService.pages,
      categories: categories,
      products: products,
      eligibleProductIds: eligibleProductIds,
      presentationRegistry: websiteService.catalogPresentationRegistry,
    );
    return _project(owners, await siteStatusFuture);
  }

  /// Pure owner construction seam used by tests and future cached UI refreshes.
  ///
  /// [categories] is the full active taxonomy, but only the canonical
  /// `showOnWebsite` set becomes a collection owner. Navigation rows are not
  /// accepted here and therefore cannot silently widen publication.
  WebsiteSeoCenterOwners buildOwnersFromLoadedServices({
    required Map<String, String> settings,
    required Iterable<WebsitePage> pages,
    required Iterable<Category> categories,
    required Iterable<Product> products,
    Set<String>? eligibleProductIds,
    required WebsiteCatalogPresentationRegistry presentationRegistry,
  }) {
    final site = WebsiteSeoSiteOwner(
      storeName: _firstSetting(settings, const ['store_name', 'business_name']),
      origin: _firstSetting(
        settings,
        const ['store_url', 'seo_canonical_url'],
      ),
      title: _firstSetting(
        settings,
        const ['seo_meta_title', 'meta_title'],
      ),
      description: _firstSetting(
        settings,
        const [
          'seo_meta_description',
          'meta_description',
          'store_description',
        ],
      ),
      imageUrl: _firstSetting(
        settings,
        const ['seo_og_image', 'logo_url'],
      ),
      keywords: _firstSetting(
        settings,
        const ['seo_meta_keywords', 'meta_keywords'],
      ),
      locality: _firstSetting(
        settings,
        const ['seo_address_city', 'seo_address_locality'],
      ),
    );

    final categoryList = categories.toList(growable: false);
    final categoryById = <String, Category>{
      for (final category in categoryList)
        if (category.id?.trim().isNotEmpty == true)
          category.id!.trim(): category,
    };
    final productList = products.toList(growable: false);
    final eligibleCategoryIds = _eligibleProductCategoryIds(
      products: productList,
      categories: categoryList,
      eligibleProductIds: eligibleProductIds,
    );
    final titleTemplate = _firstSetting(
      settings,
      const ['seo_product_title_template'],
      fallback: '{product_name} | {store_name}',
    );
    final descriptionTemplate = _firstSetting(
      settings,
      const ['seo_product_description_template'],
      fallback: '{product_description}',
    );

    final pageOwners = pages
        .map(
          (page) => WebsiteSeoPageOwner.fromPage(
            page: page,
            site: site,
          ),
        )
        .toList(growable: false);

    final productOwners = productList
        .map(
          (product) => WebsiteSeoProductOwner.fromProduct(
            product: product,
            site: site,
            titleTemplate: titleTemplate,
            descriptionTemplate: descriptionTemplate,
            categoryPath: categoryById[product.categoryId]?.fullPath,
            isPubliclyEligible: eligibleProductIds?.contains(product.id),
          ),
        )
        .toList(growable: false);

    // Every active category is inventoried, published or not.
    //
    // Skipping the unpublished ones made the center unable to answer the
    // question it exists for — "why is this category not on the site?" — and
    // silently equated "not published" with "does not exist". Publication
    // remains owned exclusively by `product_categories.show_on_website`:
    // appearing in this inventory grants a category nothing, and an
    // unpublished row carries `isPublished: false`, so the shared owner
    // projection marks it `ownerNotPublished` and every public consumer keeps
    // excluding it.
    final collectionOwners = <WebsiteSeoCollectionOwner>[];
    for (final category in categoryList) {
      final id = category.id?.trim() ?? '';
      if (id.isEmpty) continue;
      final presentation = presentationRegistry.forCategory(id) ??
          WebsiteCatalogPresentation.fallback(
            categoryId: id,
            categoryName: category.name,
          );
      collectionOwners.add(
        WebsiteSeoCollectionOwner.fromPresentation(
          id: id,
          label: category.name,
          // The route the category would occupy. It is prospective for an
          // unpublished row, never a claim that the URL is live: the row's
          // own blocking reason says it is not published.
          canonicalPath: '/productos/categoria/${presentation.slug}',
          isPublished: category.showOnWebsite,
          hasEligibleContent: eligibleCategoryIds.contains(id),
          presentation: presentation,
          site: site,
          canonicalDescription: category.description ?? '',
          canonicalImageUrl: category.imageUrl ?? '',
        ),
      );
    }

    return WebsiteSeoCenterOwners(
      site: site,
      pages: pageOwners,
      products: productOwners,
      collections: collectionOwners,
      categoryOwnerTotal: categoryList.length,
    );
  }

  Future<List<Product>> _loadAllPublicProducts({
    required String tenantId,
    required PublicInventoryService publicInventoryService,
    required PublicProductVisibilityPolicy policy,
  }) async {
    const pageSize = 500;
    final products = <Product>[];
    var offset = 0;
    while (true) {
      final page = await publicInventoryService.getProductPageForTenant(
        tenantId: tenantId,
        policy: policy,
        onlyInStock:
            policy.stockPolicy == PublicCatalogStockPolicy.availableOnly,
        sortBy: 'name',
        limit: pageSize,
        offset: offset,
      );
      products.addAll(page.products);
      offset += page.products.length;
      if (page.products.isEmpty || offset >= page.totalCount) break;
    }
    return List.unmodifiable(products);
  }

  Future<List<Product>> _loadAllInternalProducts({
    required String tenantId,
    required PublicInventoryService publicInventoryService,
  }) async {
    // Supabase projects commonly cap one response at 1,000 rows. The SEO
    // center intentionally diagnoses every internal product, including rows
    // outside the public set, so an unbounded-looking SDK call is not enough.
    const pageSize = 500;
    final products = <Product>[];
    var offset = 0;
    while (true) {
      final page = await publicInventoryService.getProductsForTenant(
        tenantId: tenantId,
        onlyInStock: false,
        includeUnpublished: true,
        rethrowErrors: true,
        limit: pageSize,
        offset: offset,
      );
      products.addAll(page);
      offset += page.length;
      if (page.length < pageSize) break;
    }
    return List.unmodifiable(products);
  }

  WebsiteSeoCenterProjection _project(
    WebsiteSeoCenterOwners owners,
    WebsiteSeoSiteStatus status,
  ) {
    final siteBuild = WebsiteSeoBuildEvidence.fromSiteStatus(status);
    final siteGoogle = WebsiteSeoGoogleEvidence.fromSiteStatus(status);
    return WebsiteSeoCenterProjection(
      generatedAt: _clock().toUtc(),
      siteStatus: status,
      site: owners.site.project(
        build: siteBuild,
        google: siteGoogle,
      ),
      pages: owners.pages.map((owner) => owner.project()),
      products: owners.products.map((owner) => owner.project()),
      collections: owners.collections.map((owner) => owner.project()),
      categoryOwnerTotal: owners.categoryOwnerTotal,
    );
  }

  Future<WebsiteSeoSiteStatus> _loadSiteStatus() async {
    final observedAt = _clock().toUtc();
    try {
      final payload = await _siteStatusLoader();
      return WebsiteSeoSiteStatus.fromPayload(
        payload,
        fallbackObservedAt: observedAt,
      );
    } catch (_) {
      return WebsiteSeoSiteStatus.unavailable(
        observedAt: observedAt,
        // Transport/backend details belong in operational logs, never in the
        // operator UI or its accessibility tree.
        error: 'No se pudo consultar la evidencia técnica del sitio.',
      );
    }
  }

  static Future<Object?> _invokeSiteStatus() async {
    final response = await Supabase.instance.client.functions.invoke(
      'google-product-diagnostics',
      body: const {'action': 'site_status'},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(
        message?.trim().isNotEmpty == true
            ? message!
            : 'La acción site_status no está disponible.',
      );
    }
    return response.data;
  }
}

String _firstSetting(
  Map<String, String> settings,
  Iterable<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = settings[key]?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

Set<String> _eligibleProductCategoryIds({
  required Iterable<Product> products,
  required Iterable<Category> categories,
  Set<String>? eligibleProductIds,
}) {
  final childrenByParentId = <String, Set<String>>{};
  for (final category in categories) {
    final id = category.id?.trim() ?? '';
    final parentId = category.parentId?.trim() ?? '';
    if (id.isEmpty || parentId.isEmpty) continue;
    childrenByParentId.putIfAbsent(parentId, () => <String>{}).add(id);
  }

  final directlyEligible = <String>{
    for (final product in products)
      if ((eligibleProductIds == null
              ? product.isActive == true &&
                  product.isPublished == true &&
                  product.lifecycleStatus.toString().trim().toLowerCase() ==
                      'active'
              : eligibleProductIds.contains(product.id)) &&
          product.categoryId?.toString().trim().isNotEmpty == true)
        product.categoryId.toString().trim(),
  };
  if (directlyEligible.isEmpty) return const <String>{};

  final result = <String>{...directlyEligible};
  final allCategoryIds = <String>{
    for (final category in categories)
      if (category.id?.trim().isNotEmpty == true) category.id!.trim(),
  };
  for (final categoryId in allCategoryIds) {
    final pending = <String>[categoryId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final candidate = pending.removeLast();
      if (!visited.add(candidate)) continue;
      if (directlyEligible.contains(candidate)) {
        result.add(categoryId);
        break;
      }
      pending.addAll(childrenByParentId[candidate] ?? const <String>{});
    }
  }
  return Set.unmodifiable(result);
}
