import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/models/catalog_filter_rail_policy.dart';
import 'package:vinabike_public_core/public_store/models/public_catalog_facets.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/seo/public_catalog_seo.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/public_store/utils/public_spec_display.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_public_core/shared/models/public_product_visibility_policy.dart';

import 'public_reads.dart';
import 'site_layout.dart';
import 'storefront_shell.dart';

typedef CatalogProduct = ({
  PublicCommerceProductProjection commerce,
  String path,
});

typedef CatalogLink = ({String id, String label, String path, int count});

/// `/productos`, a category page, or a search: the listing, its filters and
/// how the page presents itself, from the public reads and the shared core.
class CatalogPageModel {
  CatalogPageModel._({
    required this.page,
    required this.uri,
    required this.query,
    required this.categoryId,
    required this.presentation,
    required this.displayTitle,
    required this.intro,
    required this.heroImage,
    required this.products,
    required this.total,
    required this.facets,
    required this.directCounts,
    required this.queryError,
  });

  factory CatalogPageModel.build({
    required PageContext page,
    required Uri uri,
    required WebsiteCatalogQuery query,
    required String? categoryId,
    required CatalogReads reads,
    String? queryError,
  }) {
    final shell = page.shell;
    final presentation = categoryId == null
        ? shell.presentations.forCatalogRoot(WebsiteCatalogRoot.products) ??
              WebsiteCatalogPresentation.catalogRoot(WebsiteCatalogRoot.products)
        : shell.presentationFor(categoryId);
    final category = categoryId == null ? null : shell.categories[categoryId];
    final displayTitle = categoryId == null
        ? (presentation.heroTitle.trim().isNotEmpty
              ? presentation.heroTitle.trim()
              : 'Productos')
        : publicCategoryDisplayTitle(
            presentation,
            (category?['name'] ?? '').toString(),
          );
    final facets = PublicCatalogFacetSnapshot.fromRows(
      reads.facets,
      optionDisplayByKey: publicSpecOptionDisplayFromRows(reads.optionLabels),
    );
    final rows = rowsOf(reads.products);
    // Each card's brand by the store's rule (`_attachCanonicalBrandNames`).
    final brandNames = canonicalPublicProductBrandNames(
      rows: rowsOf(reads.brandRows),
      tenantId: page.tenantId,
      requestedBrandIds: [
        for (final row in rows)
          if ((row['brand_id'] ?? '').toString().isNotEmpty)
            row['brand_id'].toString(),
      ],
    );
    return CatalogPageModel._(
      page: page,
      uri: uri,
      query: query,
      categoryId: categoryId,
      presentation: presentation,
      displayTitle: displayTitle,
      intro: publicCategoryIntro(
        presentation,
        (category?['description'] ?? '').toString(),
      ),
      heroImage: [
        presentation.heroImageUrl,
        (category?['image_url'] ?? '').toString(),
      ].map((url) => url.trim()).firstWhere(
            (url) => url.startsWith('https://'),
            orElse: () => '',
          ),
      products: [
        for (final row in rows)
          (
            commerce: PublicCommerceProductProjection.fromJson(
              row,
              resolvedBrand: brandNames[(row['brand_id'] ?? '').toString()],
            ),
            path: publicProductPath(Product.fromJson(row)),
          ),
      ],
      total: rows.isEmpty ? 0 : (rows.first['total_count'] as num?)?.toInt() ?? rows.length,
      facets: facets,
      directCounts: facets.directCategoryCounts,
      queryError: queryError,
    );
  }

  final PageContext page;
  final Uri uri;
  final WebsiteCatalogQuery query;

  /// `null` on `/productos`.
  final String? categoryId;
  final WebsiteCatalogPresentation presentation;
  final String displayTitle;
  final String intro;
  final String heroImage;
  final List<CatalogProduct> products;
  final int total;
  final PublicCatalogFacetSnapshot facets;

  /// Products per category, without descendants, under the visitor's other
  /// filters: the facet read's `category` rows, which the Flutter catalog
  /// prefers over `get_public_product_category_counts`.
  final Map<String, int> directCounts;

  /// Why the URL's filters were not applied, as the Flutter catalog says it.
  final String? queryError;

  StorefrontShell get shell => page.shell;

  int get pageCount => total == 0 ? 1 : (total / query.pageSize).ceil();

  /// The page shown: the listing read answers a page past the end with the
  /// last one, and the Flutter catalog clamps the same way.
  int get currentPage => query.page.clamp(1, pageCount);

  /// `/productos` or the category's public path.
  String get basePath => categoryId == null ? '/productos' : shell.categoryPath(categoryId!);

  /// Products in a category and everything under it.
  int countOf(String id) =>
      shell.subtreeOf(id).fold(0, (sum, child) => sum + (directCounts[child] ?? 0));

  /// «Todas»: the facet read's summary, every product the other filters
  /// leave, with or without a category.
  int get allCount =>
      facets.filteredTotalCount ??
      directCounts.values.fold(0, (sum, n) => sum + n);

  /// Published categories whose parent is not published, with products: the
  /// roots of the Flutter catalog's category list.
  List<String> get rootCategories => [
    for (final id in shell.categories.keys)
      if (shell.isPublishedCategory(id) &&
          !shell.isPublishedCategory(shell.parentOf(id) ?? '') &&
          countOf(id) > 0)
        id,
  ]..sort(shell.compareCategories);

  /// Published children with products, in order.
  List<String> visibleChildren(String id) => [
    for (final child in shell.childrenOfCategory(id))
      if (shell.isPublishedCategory(child) && countOf(child) > 0) child,
  ];

  /// The selected category and its ancestors: the branches the list opens.
  Set<String> get openBranch {
    final open = <String>{};
    var current = categoryId;
    while (current != null && open.add(current)) {
      current = shell.parentOf(current);
    }
    return open;
  }

  /// «Subcategorías» or «Más en `padre`», as the Flutter catalog decides it.
  CatalogCollectionFacetDecision<String>? get navigator {
    final id = categoryId;
    if (id == null) return null;
    final parent = shell.parentOf(id);
    return decideCatalogCollectionFacet<String>(
      selectedId: id,
      children: visibleChildren(id),
      parentName: parent == null || !shell.isPublishedCategory(parent)
          ? null
          : shell.categoryName(parent),
      siblings: parent == null ? const [] : visibleChildren(parent),
    );
  }

  CatalogLink linkTo(String id) => (
    id: id,
    label: shell.categoryName(id),
    path: shell.categoryPath(id),
    count: countOf(id),
  );

  /// Each published category from the top to the current one.
  List<CatalogLink> get trail {
    final trail = <CatalogLink>[];
    var current = categoryId;
    final seen = <String>{};
    while (current != null && seen.add(current)) {
      if (shell.isPublishedCategory(current)) trail.insert(0, linkTo(current));
      current = shell.parentOf(current);
    }
    return trail;
  }

  /// The hero's links to the category's published children with products.
  List<CatalogLink> get subcategories => presentation.showSubcategories && categoryId != null
      ? [for (final child in visibleChildren(categoryId!)) linkTo(child)]
      : const [];

  /// The technical filters offered here, as the Flutter catalog picks them.
  List<PublicCatalogSpecFacet> get specFacets =>
      offeredPublicSpecFacets(facets.specFacets, selected: {
        for (final entry in query.specFilters.entries)
          entry.key: entry.value.toSet(),
      });

  String specValueLabel(PublicCatalogSpecFacet facet, String value) =>
      publicSpecValueLabel(
        specKey: facet.key,
        value: value,
        dataType: facet.dataType,
        unit: facet.unit,
        optionDisplay: facet.optionDisplay,
      );

  /// The availability filter is shown only where it can change something:
  /// not when the site already lists only products in stock.
  bool get availabilityFacetVisible => decideCatalogAvailabilityFacet(
    stockPolicy: PublicCatalogStockPolicyLabel.fromStorageValue(
      shell.settings[PublicProductVisibilityPolicy.stockPolicyKey],
    ),
    isEditMode: false,
    facetDataAvailable: facets.isAvailable,
  ).visible;

  /// The same URL with other filters, back on page 1.
  String hrefWith(WebsiteCatalogQuery next) {
    final parameters = next.toQueryParameters();
    return parameters.isEmpty
        ? basePath
        : Uri(path: basePath, queryParameters: parameters).toString();
  }

  String pageHref(int number) => hrefWith(_copy(page: number));

  WebsiteCatalogQuery _copy({int? page}) => WebsiteCatalogQuery(
    searchQuery: query.searchQuery,
    productType: query.productType,
    categoryScope: query.categoryScope,
    brandIds: query.brandIds,
    specFilters: query.specFilters,
    minPrice: query.minPrice,
    maxPrice: query.maxPrice,
    stock: query.stock,
    sort: query.sort,
    page: page ?? query.page,
    pageSize: query.pageSize,
  );

  PageMeta get meta {
    final storeName = shell.storeName;
    final published = categoryId == null || shell.isPublishedCategory(categoryId!);
    final route = projectStorefrontSeoRoute(
      uri.replace(path: basePath),
      isErpMounted: false,
      ownerAllowsIndexing: presentation.allowIndexing,
      ownerIsPublished: published,
      hasEligibleContent: total > 0,
      unavailableCanonicalPath: '/productos',
    );
    final storeUrl = page.storeUrl;
    final canonicalUrl = '$storeUrl${route.canonicalPath}';
    final title = categoryId == null
        ? publicCatalogSeoTitle(
            presentation: presentation,
            storeName: storeName,
            storeLocality: shell.setting(
              'seo_address_city',
              shell.setting('seo_address_locality'),
            ),
          )
        : publicCategorySeoTitle(
            seoTitle: presentation.seoTitle,
            displayTitle: displayTitle,
            storeName: storeName,
          );
    final description = categoryId == null
        ? publicCatalogSeoDescription(
            presentation: presentation,
            storeName: storeName,
          )
        : publicCategorySeoDescription(
            seoDescription: presentation.seoDescription,
            intro: intro,
            productCount: total,
            displayTitle: displayTitle,
            storeName: storeName,
          );
    final image = presentation.socialImageUrl.trim().isNotEmpty
        ? presentation.socialImageUrl.trim()
        : heroImage;
    final listed = products.take(categoryId == null ? 24 : 10).toList();
    return PageMeta(
      title: currentPage > 1 ? '$title · página $currentPage' : title,
      description: description,
      canonicalUrl: canonicalUrl,
      indexable: route.isIndexable,
      imageUrl: image,
      // The largest paint: a category's hero photo, otherwise the first card.
      preloadImage: categoryId != null && heroImage.isNotEmpty
          ? (src: heroImage, srcset: null, sizes: null)
          : products.isEmpty || products.first.commerce.imageUrls.isEmpty
          ? null
          : (src: products.first.commerce.imageUrls.first, srcset: null, sizes: null),
      structuredData: [
        {
          '@context': 'https://schema.org',
          '@graph': [
            {
              '@type': 'CollectionPage',
              'name': categoryId == null
                  ? 'Productos para bicicletas en $storeName'
                  : displayTitle,
              'url': canonicalUrl,
              'description': description,
              if (categoryId != null && image.isNotEmpty) 'image': image,
            },
            {
              '@type': 'BreadcrumbList',
              'itemListElement': [
                for (final (i, crumb) in [
                  ('Inicio', storeUrl),
                  ('Productos', '$storeUrl/productos'),
                  if (categoryId != null) (displayTitle, canonicalUrl),
                ].indexed)
                  {
                    '@type': 'ListItem',
                    'position': i + 1,
                    'name': crumb.$1,
                    'item': crumb.$2,
                  },
              ],
            },
            {
              '@type': 'ItemList',
              'name': categoryId == null
                  ? 'Catálogo de $storeName'
                  : '$displayTitle en $storeName',
              'numberOfItems': total,
              'itemListElement': [
                for (final (i, product) in listed.indexed)
                  {
                    '@type': 'ListItem',
                    'position': i + 1,
                    'url': '$storeUrl${product.path}',
                    'name': cleanPublicSeoText(product.commerce.title),
                  },
              ],
            },
          ],
        },
      ],
    );
  }
}

/// The listing a catalog URL asks for: its categories (the category and all
/// below it, unless the URL asks for that category alone), the visitor's
/// filters, order and page.
CatalogRequest catalogRequestFor({
  required StorefrontShell? shell,
  required String? categoryId,
  required WebsiteCatalogQuery query,
}) => CatalogRequest(
  categoryIds: categoryId == null
      ? null
      : query.categoryScope == WebsiteCatalogCategoryScope.direct
      ? [categoryId]
      : shell!.subtreeOf(categoryId),
  searchQuery: query.searchQuery,
  brandIds: query.brandIds,
  specFilters: publicSpecFiltersForRpc(query.specFilters),
  minPrice: query.minPrice,
  maxPrice: query.maxPrice,
  onlyInStock: query.stock == WebsiteCatalogStockFilter.available,
  sortBy: query.sort.storageValue,
  limit: query.pageSize,
  offset: (query.page - 1) * query.pageSize,
);
