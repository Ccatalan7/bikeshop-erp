import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/models/catalog_filter_rail_policy.dart';
import 'package:vinabike_public_core/public_store/models/public_catalog_facets.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';
import 'package:vinabike_public_core/public_store/models/public_product_brand_names.dart';
import 'package:vinabike_public_core/public_store/seo/public_catalog_seo.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/public_store/utils/public_spec_display.dart';
import 'package:vinabike_public_core/shared/models/product.dart';
import 'package:vinabike_public_core/shared/models/public_product_visibility_policy.dart';

import 'product_card.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'storefront_shell.dart';

typedef CatalogProduct = ({
  PublicCommerceProductProjection commerce,
  String path,
  PublicImageThumbnail? thumbnail,
});

typedef CatalogLink = ({String id, String label, String path, int count});

/// The parts of a catalog page the editor selects as it selects a block
/// (`WebsiteCatalogSection` in the ERP), named `catalog:<owner>:<section>`.
/// A category's page for a measure or a brand is edited in its category's
/// `landings`.
enum WebsiteCatalogDraftSection { hero, plans, list, closing, guide, landings }

/// A category's page for one of its measures or brands, as a link beside
/// the others.
typedef CatalogLandingLink = ({String label, String path, bool current});

/// `/productos`, `/servicios`, a category page, or a search: the listing,
/// its filters and how the page presents itself, from the public reads and
/// the shared core.
class CatalogPageModel {
  CatalogPageModel._({
    required this.services,
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
    required this.selectedBrandNames,
    required this.directCounts,
    required this.queryError,
    required this.priceList,
    required this.landing,
    required this.categoryPresentation,
    required this.categoryTitle,
  });

  factory CatalogPageModel.build({
    required PageContext page,
    required Uri uri,
    required WebsiteCatalogQuery query,
    required String? categoryId,
    required CatalogReads reads,
    String? queryError,
    bool services = false,
    WebsiteCatalogLanding? landing,
  }) {
    final shell = page.shell;
    final root = services
        ? WebsiteCatalogRoot.services
        : WebsiteCatalogRoot.products;
    final presentation = categoryId == null
        ? shell.presentations.forCatalogRoot(root) ??
              WebsiteCatalogPresentation.catalogRoot(root)
        // A category without a look of its own draws the template's.
        : shell.presentations.drawnCategory(shell.presentationFor(categoryId));
    final category = categoryId == null ? null : shell.categories[categoryId];
    final categoryTitle = categoryId == null
        ? ''
        : publicCategoryDisplayTitle(
            presentation,
            (category?['name'] ?? '').toString(),
          );
    final displayTitle = landing != null
        ? publicCategoryLandingDisplayTitle(
            landing: landing,
            categoryTitle: categoryTitle,
          )
        : categoryId == null
        ? (presentation.heroTitle.trim().isNotEmpty
              ? presentation.heroTitle.trim()
              : services
              ? 'Servicios'
              : 'Productos')
        : categoryTitle;
    final facetRows = reads.facets;
    final facets = facetRows == null
        ? const PublicCatalogFacetSnapshot.unavailable()
        : PublicCatalogFacetSnapshot.fromRows(
            facetRows,
            optionDisplayByKey: publicSpecOptionDisplayFromRows(
              reads.optionLabels,
            ),
          );
    final rows = rowsOf(reads.products);
    final thumbnails = PublicImageThumbnail.byUrl(reads.thumbnails);
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
    // The URL's brands by name, for the ones the facet read no longer lists.
    final selectedBrandNames = canonicalPublicProductBrandNames(
      rows: rowsOf(reads.brandRows),
      tenantId: page.tenantId,
      requestedBrandIds: query.brandIds,
    );
    // A root laid out as a price list: every row, grouped by its own
    // category in the catalog's order, the plan category apart.
    final priceList = categoryId == null && presentation.isPriceList
        ? CatalogPriceList.build(
            items: [
              for (final row in rows)
                if (PublicCommerceProductProjection.fromJson(row)
                    case final commerce)
                  CatalogPriceItem(
                    id: commerce.id,
                    name: commerce.title,
                    price: commerce.price,
                    priceMode: (row['website_price_mode'] ?? 'exact')
                        .toString(),
                    categoryId: (row['category_id'] ?? '').toString(),
                    description: CatalogPriceItem.descriptionOf(
                      websiteDescription: row['website_description']
                          ?.toString(),
                      description: row['description']?.toString(),
                    ),
                  ),
            ],
            compareCategories: shell.compareCategories,
            categoryLabel: shell.categoryName,
            plansCategoryId: presentation.plansCategoryId,
          )
        : null;
    return CatalogPageModel._(
      priceList: priceList,
      services: services,
      page: page,
      uri: uri,
      query: query,
      categoryId: categoryId,
      presentation: presentation,
      displayTitle: displayTitle,
      categoryTitle: categoryTitle,
      landing: landing,
      categoryPresentation: categoryId == null
          ? presentation
          : shell.presentationFor(categoryId),
      // A measure's page says only what its editor wrote: the category's
      // text would be the same paragraph on every one of them.
      intro: landing != null
          ? landing.heroDescription
          : publicCategoryIntro(
              presentation,
              (category?['description'] ?? '').toString(),
            ),
      heroImage:
          [presentation.heroImageUrl, (category?['image_url'] ?? '').toString()]
              .map((url) => url.trim())
              .firstWhere(
                (url) => url.startsWith('https://'),
                orElse: () => '',
              ),
      products: [
        for (final row in rows)
          if (PublicCommerceProductProjection.fromJson(
                row,
                resolvedBrand: brandNames[(row['brand_id'] ?? '').toString()],
              )
              case final commerce)
            (
              commerce: commerce,
              path: publicProductPath(Product.fromJson(row)),
              thumbnail: commerce.imageUrls.isEmpty
                  ? null
                  : thumbnails[commerce.imageUrls.first],
            ),
      ],
      total: rows.isEmpty
          ? 0
          : (rows.first['total_count'] as num?)?.toInt() ?? rows.length,
      facets: facets,
      selectedBrandNames: selectedBrandNames,
      directCounts: facets.directCategoryCounts,
      queryError: queryError,
    );
  }

  /// `/servicios` and its categories: the workshop's services.
  final bool services;
  final PageContext page;
  final Uri uri;
  final WebsiteCatalogQuery query;

  /// `null` on `/productos` and `/servicios`.
  final String? categoryId;

  /// The presentation this page's sections edit, as the editor's canvas
  /// names it: the root's (`@catalog/products`, `@catalog/services`) or the
  /// category's.
  String get presentationOwnerId =>
      categoryId ??
      (services ? WebsiteCatalogRoot.services : WebsiteCatalogRoot.products)
          .presentationId;

  /// In the editor's draft, [section] of this page picked by a click, named
  /// as the canvas names it.
  ///
  /// On a category's page for a measure or a brand, its portada and its
  /// guide are that page's, edited among the category's pages.
  Map<String, String> pickSection(WebsiteCatalogDraftSection section) {
    final shown =
        landing != null &&
            (section == WebsiteCatalogDraftSection.hero ||
                section == WebsiteCatalogDraftSection.guide)
        ? WebsiteCatalogDraftSection.landings
        : section;
    return page.pick(
      'catalog:$presentationOwnerId:${shown.name}',
      switch (shown) {
        WebsiteCatalogDraftSection.hero => 'Portada',
        WebsiteCatalogDraftSection.plans => 'Planes',
        WebsiteCatalogDraftSection.list =>
          services ? 'Todos los servicios' : 'Todos los productos',
        WebsiteCatalogDraftSection.closing => 'Cierre',
        WebsiteCatalogDraftSection.guide => 'Guía y preguntas',
        WebsiteCatalogDraftSection.landings => 'Páginas por medida o marca',
      },
    );
  }

  final WebsiteCatalogPresentation presentation;
  final String displayTitle;
  final String intro;
  final String heroImage;
  final List<CatalogProduct> products;
  final int total;
  final PublicCatalogFacetSnapshot facets;

  /// The names of the URL's brands, by id.
  final Map<String, String> selectedBrandNames;

  /// Products per category, without descendants, under the visitor's other
  /// filters: the facet read's `category` rows, which the Flutter catalog
  /// prefers over `get_public_product_category_counts`.
  final Map<String, int> directCounts;

  /// Why the URL's filters were not applied, as the Flutter catalog says it.
  final String? queryError;

  /// The root's price list ([WebsiteCatalogLayout.priceList]), or `null`
  /// for the grid.
  final CatalogPriceList? priceList;

  /// The category's page for a measure or a brand this is, or `null`.
  final WebsiteCatalogLanding? landing;

  /// The category's presentation as saved (its address and its pages), not
  /// the look it draws.
  final WebsiteCatalogPresentation categoryPresentation;

  /// The category's own title, also on its pages for a measure or a brand.
  final String categoryTitle;

  /// What the page says under its products: the page's own guide.
  WebsiteCatalogGuide get guide =>
      landing?.guide ??
      (categoryId == null ? WebsiteCatalogGuide.empty : presentation.guide);

  /// The figures a Google text names with `{cantidad}`, `{desde}`,
  /// `{hasta}` or `{marcas}`, from the listing and its counts.
  PublicCatalogTextFacts get textFacts {
    final brands = [...facets.brands]
      ..sort((a, b) => b.itemCount.compareTo(a.itemCount));
    return PublicCatalogTextFacts(
      count: total,
      priceFrom: facets.isAvailable ? facets.minPrice : null,
      priceTo: facets.isAvailable ? facets.maxPrice : null,
      brands: [for (final brand in brands) brand.label],
    );
  }

  /// The category's pages for a measure or a brand, as links: on the
  /// category, those with products (all of them when the counts did not
  /// answer); on one of them, all of its siblings, the current one marked.
  List<CatalogLandingLink> get landingLinks {
    final id = categoryId;
    if (id == null || services) return const [];
    return [
      for (final candidate in categoryPresentation.landings)
        if (landing != null || _landingHasProducts(candidate))
          (
            label: candidate.label,
            path: publicCategoryLandingPath(
              presentation: categoryPresentation,
              landing: candidate,
            ),
            current: candidate.slug == landing?.slug,
          ),
    ];
  }

  /// What the links to the category's pages are about: «aro» when they all
  /// narrow the same technical filter, «marca» when they are all brands.
  String get landingLinksLabel {
    final landings = categoryPresentation.landings;
    if (landings.isEmpty) return '';
    final own = categoryPresentation.landingsLabel;
    if (own.isNotEmpty) return own;
    if (landings.every((each) => each.brandIds.isNotEmpty)) return 'Por marca';
    final keys = {for (final each in landings) ...each.specFilters.keys};
    if (keys.length == 1 && landings.every((each) => each.brandIds.isEmpty)) {
      for (final facet in facets.specFacets) {
        if (facet.key == keys.single && facet.label.trim().isNotEmpty) {
          return 'Por ${facet.label.trim().toLowerCase()}';
        }
      }
    }
    return 'Más buscado';
  }

  bool _landingHasProducts(WebsiteCatalogLanding candidate) {
    if (!countsKnown) return true;
    for (final entry in candidate.specFilters.entries) {
      final facet = facets.specFacets
          .where((each) => each.key == entry.key)
          .firstOrNull;
      if (facet == null) return false;
      final count = facet.values
          .where((value) => entry.value.contains(value.value))
          .fold(0, (sum, value) => sum + value.itemCount);
      if (count == 0) return false;
    }
    if (candidate.brandIds.isNotEmpty &&
        !facets.brands.any(
          (brand) =>
              candidate.brandIds.contains(brand.id) && brand.itemCount > 0,
        )) {
      return false;
    }
    return true;
  }

  /// Each listed item's public page.
  late final Map<String, String> pathById = {
    for (final product in products) product.commerce.id: product.path,
  };

  StorefrontShell get shell => page.shell;

  int get pageCount => total == 0 ? 1 : (total / query.pageSize).ceil();

  /// The page shown: the listing read answers a page past the end with the
  /// last one, and the Flutter catalog clamps the same way.
  int get currentPage => query.page.clamp(1, pageCount);

  /// `/productos` or `/servicios`.
  String get rootPath => services ? '/servicios' : '/productos';

  /// «Productos» or «Servicios»: the catalog's name.
  String get rootLabel => services ? 'Servicios' : 'Productos';

  /// What it lists, in plural («productos», «servicios»).
  String get noun => services ? 'servicios' : 'productos';

  /// One of what it lists («servicio», «producto»).
  String get singularNoun => services ? 'servicio' : 'producto';

  /// The root, the category's or its page's public path.
  String get basePath => categoryId == null
      ? rootPath
      : landing != null
      ? publicCategoryLandingPath(
          presentation: categoryPresentation,
          landing: landing!,
        )
      : shell.categoryPath(categoryId!, services: services);

  /// The category's own path, also from one of its pages.
  String get categoryBasePath => categoryId == null
      ? rootPath
      : shell.categoryPath(categoryId!, services: services);

  /// Whether the facet read answered: without it the page knows no counts,
  /// lists every published category and shows no number beside them.
  bool get countsKnown => facets.isAvailable;

  bool _listed(String id) =>
      shell.isPublishedCategory(id) && (!countsKnown || countOf(id) > 0);

  /// Products in a category and everything under it.
  int countOf(String id) => shell
      .subtreeOf(id)
      .fold(0, (sum, child) => sum + (directCounts[child] ?? 0));

  /// «Todas»: the facet read's summary, every product the other filters
  /// leave, with or without a category.
  int get allCount =>
      facets.filteredTotalCount ??
      directCounts.values.fold(0, (sum, n) => sum + n);

  /// Published categories whose parent is not published, with products: the
  /// roots of the Flutter catalog's category list.
  List<String> get rootCategories => [
    for (final id in shell.categories.keys)
      if (_listed(id) && !shell.isPublishedCategory(shell.parentOf(id) ?? ''))
        id,
  ]..sort(shell.compareCategories);

  /// Published children with products, in order.
  List<String> visibleChildren(String id) => [
    for (final child in shell.childrenOfCategory(id))
      if (_listed(child)) child,
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
    path: shell.categoryPath(id, services: services),
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
  List<CatalogLink> get subcategories =>
      presentation.showSubcategories && categoryId != null && landing == null
      ? [for (final child in visibleChildren(categoryId!)) linkTo(child)]
      : const [];

  /// The technical filters offered here, as the Flutter catalog picks them,
  /// each with the URL's values the read no longer lists added at 0, for
  /// the same reason as [brandOptions].
  ///
  /// A page for a measure or a brand does not offer what it already fixes:
  /// the other values are its siblings' pages, linked above the list.
  late final List<PublicCatalogSpecFacet> specFacets = [
    for (final facet in offeredPublicSpecFacets(
      facets.specFacets,
      selected: {
        for (final entry in query.specFilters.entries)
          entry.key: entry.value.toSet(),
      },
    ))
      if (!(landing?.specFilters.containsKey(facet.key) ?? false))
        _withSelected(facet),
  ];

  PublicCatalogSpecFacet _withSelected(PublicCatalogSpecFacet facet) {
    final listed = {for (final value in facet.values) value.value};
    final missing = [
      for (final value in query.specFilters[facet.key] ?? const <String>[])
        if (listed.add(value))
          PublicCatalogSpecFacetValue(value: value, itemCount: 0),
    ];
    if (missing.isEmpty) return facet;
    return PublicCatalogSpecFacet(
      key: facet.key,
      label: facet.label,
      dataType: facet.dataType,
      unit: facet.unit,
      values: [...facet.values, ...missing],
      productCount: facet.productCount,
      scopeCount: facet.scopeCount,
      optionDisplay: facet.optionDisplay,
    );
  }

  /// The brand filter's rows: the facet read's, and each brand of the URL
  /// it no longer lists because the other filters leave that brand no
  /// product. Those stay, checked and with 0, so the visitor sees why the
  /// list is empty and can take them off, as on any serious store; one
  /// whose name is unknown rides along unseen ([CatalogPageView]).
  List<PublicCatalogBrandFacet> get brandOptions {
    if (!countsKnown) return const [];
    if (landing?.brandIds.isNotEmpty ?? false) return const [];
    final listed = {for (final brand in facets.brands) brand.id};
    return [
      ...facets.brands,
      for (final id in query.brandIds)
        if (!listed.contains(id))
          if (selectedBrandNames[id] case final name?)
            PublicCatalogBrandFacet(id: id, label: name, itemCount: 0),
    ];
  }

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

  /// The same results in another order, from page 1 (the phone's «Ordenar
  /// por» sheet).
  String sortHref(WebsiteCatalogSort sort) =>
      hrefWith(_copy(page: 1, sort: sort));

  /// The same results without the price range («Quitar rango de precio»).
  String get priceClearedHref => hrefWith(_copy(page: 1, clearPrice: true));

  /// Whether a brand, a technical value, a price or availability narrows
  /// the results (the search does not count: it is what was asked).
  bool get hasFilters =>
      query.brandIds.isNotEmpty ||
      query.specFilters.isNotEmpty ||
      query.minPrice != null ||
      query.maxPrice != null ||
      query.stock != null;

  /// The same search in the same place without any filter: the way out of
  /// an empty result, whatever filter emptied it, drawn or not.
  String get filtersClearedHref => hrefWith(_copy(page: 1, clearFilters: true));

  WebsiteCatalogQuery _copy({
    int? page,
    WebsiteCatalogSort? sort,
    bool clearPrice = false,
    bool clearFilters = false,
  }) => WebsiteCatalogQuery(
    searchQuery: query.searchQuery,
    productType: query.productType,
    categoryScope: query.categoryScope,
    brandIds: clearFilters ? const [] : query.brandIds,
    specFilters: clearFilters ? const {} : query.specFilters,
    minPrice: clearPrice || clearFilters ? null : query.minPrice,
    maxPrice: clearPrice || clearFilters ? null : query.maxPrice,
    stock: clearFilters ? null : query.stock,
    sort: sort ?? query.sort,
    page: page ?? query.page,
    pageSize: query.pageSize,
  );

  PageMeta get meta {
    final storeName = shell.storeName;
    final published =
        categoryId == null || shell.isPublishedCategory(categoryId!);
    // Page 2 on is its own canonical page, at the page actually shown (a
    // page past the end shows the last); a price list is one page.
    final listedPage = storefrontCatalogListedPage(uri);
    final parameters = listedPage == null
        ? uri.queryParameters
        : {if (priceList == null && currentPage > 1) 'page': '$currentPage'};
    final route = projectStorefrontSeoRoute(
      Uri(
        path: basePath,
        queryParameters: parameters.isEmpty ? null : parameters,
      ),
      isErpMounted: false,
      ownerAllowsIndexing:
          presentation.allowIndexing && (landing?.allowIndexing ?? true),
      ownerIsPublished: published,
      // A measure's page with one or two products is too thin to rank: it
      // points to its category, as a filtered list does.
      hasEligibleContent: landing != null
          ? total >= websiteCatalogLandingMinimumItems
          : total > 0,
      unavailableCanonicalPath: landing != null ? categoryBasePath : rootPath,
    );
    final storeUrl = page.storeUrl;
    final canonicalUrl = '$storeUrl${route.canonicalPath}';
    final locality = shell.setting(
      'seo_address_city',
      shell.setting('seo_address_locality'),
    );
    final facts = textFacts;
    final title = categoryId == null
        ? (services
              ? publicServicesCatalogSeoTitle(
                  presentation: presentation,
                  storeName: storeName,
                  storeLocality: locality,
                )
              : publicCatalogSeoTitle(
                  presentation: presentation,
                  storeName: storeName,
                  storeLocality: locality,
                ))
        : publicCategorySeoTitle(
            seoTitle: publicCatalogEditorText(
              landing?.seoTitle ?? presentation.seoTitle,
              facts,
            ),
            displayTitle: displayTitle,
            storeName: storeName,
            storeLocality: locality,
            services: services,
          );
    final description = categoryId == null
        ? (services
              ? publicServicesCatalogSeoDescription(
                  presentation: presentation,
                  storeName: storeName,
                  storeLocality: locality,
                )
              : publicCatalogSeoDescription(
                  presentation: presentation,
                  storeName: storeName,
                  storeLocality: locality,
                ))
        : publicCategorySeoDescription(
            seoDescription: publicCatalogEditorText(
              landing?.seoDescription ?? presentation.seoDescription,
              facts,
            ),
            intro: intro,
            productCount: total,
            displayTitle: displayTitle,
            storeName: storeName,
            storeLocality: locality,
            services: services,
          );
    // The editor's social image, else the hero's; a category without either
    // shows its first photographed product, so a shared link and Google's
    // result carry a picture of what is sold there (2026-10-08).
    final image = [
      presentation.socialImageUrl.trim(),
      heroImage,
      if (categoryId != null)
        for (final product in products) ...product.commerce.imageUrls.take(1),
    ].firstWhere((url) => url.isNotEmpty, orElse: () => '');
    // A price list is one page with every service: Google gets them all.
    final listed = priceList != null
        ? products
        : products.take(categoryId == null ? 24 : 10).toList();
    return PageMeta(
      title: currentPage > 1 && priceList == null
          ? '$title · página $currentPage'
          : title,
      description: description,
      canonicalUrl: canonicalUrl,
      indexable: route.isIndexable,
      imageUrl: image,
      // The largest paint: a category's hero photo, otherwise the first card,
      // with the same candidates the card offers so it is fetched once.
      // A price list draws no card photo: only its hero's, if it has one.
      preloadImage:
          (categoryId != null || priceList != null) && heroImage.isNotEmpty
          ? (src: heroImage, srcset: null, sizes: null)
          : priceList != null ||
                products.isEmpty ||
                products.first.commerce.imageUrls.isEmpty
          ? null
          : switch (products.first.thumbnail) {
              final copies? when copies.variants.isNotEmpty => (
                src: copies.smallestUrl,
                srcset: copies.srcset,
                sizes: cardImageSizes(presentation.gridDensity),
              ),
              _ => (
                src: products.first.commerce.imageUrls.first,
                srcset: null,
                sizes: null,
              ),
            },
      structuredData: [
        {
          '@context': 'https://schema.org',
          '@graph': [
            {
              '@type': 'CollectionPage',
              'name': categoryId == null
                  ? services
                        ? 'Servicios del taller de $storeName'
                        : 'Productos para bicicletas en $storeName'
                  : displayTitle,
              'url': canonicalUrl,
              'description': description,
              if (categoryId != null && image.isNotEmpty) 'image': image,
            },
            {
              '@type': 'BreadcrumbList',
              'itemListElement': [
                // The trail the page shows, «Componentes › Ruedas ›
                // Neumáticos»: until 2026-10-08 Google got only the last
                // step and could not show the branch under the result.
                for (final (i, crumb) in [
                  ('Inicio', storeUrl),
                  (rootLabel, '$storeUrl$rootPath'),
                  if (categoryId != null) ...[
                    for (final link in trail)
                      if (link.id != categoryId || landing != null)
                        (
                          link.id == categoryId ? categoryTitle : link.label,
                          '$storeUrl${link.path}',
                        ),
                    (displayTitle, '$storeUrl$basePath'),
                  ],
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
                  ? services
                        ? 'Servicios de $storeName'
                        : 'Catálogo de $storeName'
                  : '$displayTitle en $storeName',
              'numberOfItems': total,
              'itemListElement': [
                for (final (i, product) in listed.indexed)
                  if (services)
                    // A service with its price, as the services page Google
                    // indexed from the snapshot listed them.
                    {
                      '@type': 'ListItem',
                      'position': i + 1,
                      'item': {
                        '@type': 'Service',
                        'name': cleanPublicSeoText(product.commerce.title),
                        'url': '$storeUrl${product.path}',
                        if (product.commerce.price > 0)
                          'offers': {
                            '@type': 'Offer',
                            'price': product.commerce.price.toStringAsFixed(0),
                            'priceCurrency': 'CLP',
                          },
                      },
                    }
                  else
                    {
                      '@type': 'ListItem',
                      'position': i + 1,
                      'url': '$storeUrl${product.path}',
                      'name': cleanPublicSeoText(product.commerce.title),
                    },
              ],
            },
            // The guide's questions, as the page shows them. Google keeps
            // its own question results for health and government sites;
            // Bing and the assistants read them.
            if (guide.shownQuestions.isNotEmpty && route.isIndexable)
              {
                '@type': 'FAQPage',
                'mainEntity': [
                  for (final question in guide.shownQuestions)
                    {
                      '@type': 'Question',
                      'name': cleanPublicSeoText(question.question),
                      'acceptedAnswer': {
                        '@type': 'Answer',
                        'text': cleanPublicSeoText(question.answer),
                      },
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
///
/// A category's page for a measure or a brand ([landing]) lists the
/// category's products with its filters, under whatever the visitor adds;
/// what it fixes, the visitor cannot widen.
CatalogRequest catalogRequestFor({
  required StorefrontShell? shell,
  required String? categoryId,
  required WebsiteCatalogQuery query,
  bool services = false,
  WebsiteCatalogLanding? landing,
}) => CatalogRequest(
  services: services,
  categoryIds: categoryId == null
      ? null
      : query.categoryScope == WebsiteCatalogCategoryScope.direct
      ? [categoryId]
      : shell!.subtreeOf(categoryId),
  searchQuery: query.searchQuery,
  brandIds: landing != null && landing.brandIds.isNotEmpty
      ? landing.brandIds
      : query.brandIds,
  specFilters: publicSpecFiltersForRpc({
    ...query.specFilters,
    ...?landing?.specFilters,
  }),
  minPrice: query.minPrice,
  maxPrice: query.maxPrice,
  onlyInStock: query.stock == WebsiteCatalogStockFilter.available,
  sortBy: query.sort.storageValue,
  limit: query.pageSize,
  offset: (query.page - 1) * query.pageSize,
);
