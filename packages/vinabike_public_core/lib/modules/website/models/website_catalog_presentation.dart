import 'dart:convert';

/// Canonical storage key for catalog and category collection presentation.
///
/// The complete registry lives in `website_settings`, so it participates in
/// the existing website backup/restore and public-read contracts without
/// creating a second category owner. The legacy key name is intentionally
/// retained so existing category presentation records keep round-tripping.
const websiteCatalogPresentationsSettingKey =
    'catalog_category_presentations_v1';

/// Stable presentation owners for the two canonical catalog roots.
///
/// Category presentations continue to use their real category UUID. These
/// reserved IDs let `/productos` and `/servicios` participate in the same
/// visible/editable registry without pretending that either route is a product
/// category or creating duplicate CMS pages.
const websiteProductsCatalogPresentationId = '@catalog/products';
const websiteServicesCatalogPresentationId = '@catalog/services';

enum WebsiteCatalogRoot { products, services }

extension WebsiteCatalogRootX on WebsiteCatalogRoot {
  String get presentationId => switch (this) {
        WebsiteCatalogRoot.products => websiteProductsCatalogPresentationId,
        WebsiteCatalogRoot.services => websiteServicesCatalogPresentationId,
      };

  String get routeSegment => switch (this) {
        WebsiteCatalogRoot.products => 'productos',
        WebsiteCatalogRoot.services => 'servicios',
      };

  String get label => switch (this) {
        WebsiteCatalogRoot.products => 'Todos los productos',
        WebsiteCatalogRoot.services => 'Todos los servicios',
      };

  static WebsiteCatalogRoot? fromPresentationId(String raw) {
    return WebsiteCatalogRoot.values
        .where((root) => root.presentationId == raw)
        .firstOrNull;
  }
}

enum WebsiteCatalogHeroSize { compact, standard, immersive }

extension WebsiteCatalogHeroSizeX on WebsiteCatalogHeroSize {
  String get storageValue => name;

  String get label => switch (this) {
        WebsiteCatalogHeroSize.compact => 'Compacto',
        WebsiteCatalogHeroSize.standard => 'Estándar',
        WebsiteCatalogHeroSize.immersive => 'Inmersivo',
      };

  double get desktopHeight => switch (this) {
        WebsiteCatalogHeroSize.compact => 250,
        WebsiteCatalogHeroSize.standard => 360,
        WebsiteCatalogHeroSize.immersive => 500,
      };

  static WebsiteCatalogHeroSize fromStorage(Object? raw) =>
      WebsiteCatalogHeroSize.values.firstWhere(
        (value) => value.storageValue == raw?.toString(),
        orElse: () => WebsiteCatalogHeroSize.standard,
      );
}

enum WebsiteCatalogHeroAlignment { left, center }

extension WebsiteCatalogHeroAlignmentX on WebsiteCatalogHeroAlignment {
  String get storageValue => name;

  String get label => switch (this) {
        WebsiteCatalogHeroAlignment.left => 'Izquierda',
        WebsiteCatalogHeroAlignment.center => 'Centro',
      };

  static WebsiteCatalogHeroAlignment fromStorage(Object? raw) =>
      WebsiteCatalogHeroAlignment.values.firstWhere(
        (value) => value.storageValue == raw?.toString(),
        orElse: () => WebsiteCatalogHeroAlignment.left,
      );
}

enum WebsiteMegaMenuContentAlignment { top, center, bottom }

extension WebsiteMegaMenuContentAlignmentX on WebsiteMegaMenuContentAlignment {
  String get storageValue => name;

  String get label => switch (this) {
        WebsiteMegaMenuContentAlignment.top => 'Arriba',
        WebsiteMegaMenuContentAlignment.center => 'Centro',
        WebsiteMegaMenuContentAlignment.bottom => 'Abajo',
      };

  static WebsiteMegaMenuContentAlignment fromStorage(Object? raw) =>
      WebsiteMegaMenuContentAlignment.values.firstWhere(
        (value) => value.storageValue == raw?.toString(),
        orElse: () => WebsiteMegaMenuContentAlignment.bottom,
      );
}

enum WebsiteCatalogGridDensity { editorial, balanced, compact }

extension WebsiteCatalogGridDensityX on WebsiteCatalogGridDensity {
  String get storageValue => name;

  String get label => switch (this) {
        WebsiteCatalogGridDensity.editorial => 'Editorial',
        WebsiteCatalogGridDensity.balanced => 'Equilibrada',
        WebsiteCatalogGridDensity.compact => 'Compacta',
      };

  String get description => switch (this) {
        WebsiteCatalogGridDensity.editorial =>
          'Imágenes grandes y hasta 4 columnas.',
        WebsiteCatalogGridDensity.balanced =>
          'Buen equilibrio entre imagen y cantidad.',
        WebsiteCatalogGridDensity.compact => 'Más productos visibles por fila.',
      };

  static WebsiteCatalogGridDensity fromStorage(Object? raw) =>
      WebsiteCatalogGridDensity.values.firstWhere(
        (value) => value.storageValue == raw?.toString(),
        orElse: () => WebsiteCatalogGridDensity.balanced,
      );
}

/// Facets currently backed by the public catalog query contract.
///
/// Do not add a facet here until the public inventory query can apply it to
/// the complete server-paged result set. This prevents a control from
/// filtering only the products already loaded on screen.
enum WebsiteCatalogFacet { categories, availability, brand, price }

extension WebsiteCatalogFacetX on WebsiteCatalogFacet {
  String get storageValue => name;

  String get label => switch (this) {
        WebsiteCatalogFacet.categories => 'Categorías',
        WebsiteCatalogFacet.availability => 'Disponibilidad',
        WebsiteCatalogFacet.brand => 'Marca',
        WebsiteCatalogFacet.price => 'Precio',
      };

  static WebsiteCatalogFacet? tryFromStorage(Object? raw) {
    final value = raw?.toString();
    for (final facet in WebsiteCatalogFacet.values) {
      if (facet.storageValue == value) return facet;
    }
    return null;
  }
}

/// Presentation owned by one canonical catalog root or real product category.
///
/// Root owners expose grid/facet and SEO presentation. For category owners,
/// blank text and media values intentionally inherit the corresponding
/// category fields. The category remains the taxonomy/content owner; this
/// object only owns how that content is presented as a public collection.
class WebsiteCatalogPresentation {
  WebsiteCatalogPresentation({
    required this.categoryId,
    required String slug,
    List<String> slugAliases = const [],
    this.heroSize = WebsiteCatalogHeroSize.standard,
    this.heroAlignment = WebsiteCatalogHeroAlignment.left,
    this.gridDensity = WebsiteCatalogGridDensity.balanced,
    this.heroImageUrl = '',
    this.heroEyebrow = '',
    this.heroTitle = '',
    this.heroDescription = '',
    this.megaMenuImageUrl = '',
    this.seoTitle = '',
    this.seoDescription = '',
    this.socialImageUrl = '',
    this.allowIndexing = true,
    this.heroOverlay = 0.42,
    double megaMenuOverlay = 0.58,
    double megaMenuCardOverlay = 0,
    double megaMenuOverviewWidth = defaultMegaMenuOverviewWidth,
    this.megaMenuContentAlignment = WebsiteMegaMenuContentAlignment.bottom,
    this.showBreadcrumbs = true,
    this.showSubcategories = true,
    List<WebsiteCatalogFacet> facets = defaultFacets,
  })  : megaMenuOverlay = megaMenuOverlay.clamp(0.0, 0.85),
        megaMenuCardOverlay = megaMenuCardOverlay.clamp(0.0, 0.65),
        megaMenuOverviewWidth = megaMenuOverviewWidth
            .clamp(minMegaMenuOverviewWidth, maxMegaMenuOverviewWidth)
            .toDouble(),
        slug = websiteCategorySlug(slug),
        slugAliases = List<String>.unmodifiable(
          _normalizeCategorySlugAliases(
            slugAliases,
            currentSlug: websiteCategorySlug(slug),
          ),
        ),
        facets = List<WebsiteCatalogFacet>.unmodifiable(
          _dedupeFacets(facets),
        );

  static const List<WebsiteCatalogFacet> defaultFacets = [
    WebsiteCatalogFacet.categories,
    WebsiteCatalogFacet.availability,
  ];
  static const double minMegaMenuOverviewWidth = 300;
  static const double maxMegaMenuOverviewWidth = 440;
  static const double defaultMegaMenuOverviewWidth = 440;

  final String categoryId;
  final String slug;
  final List<String> slugAliases;
  final WebsiteCatalogHeroSize heroSize;
  final WebsiteCatalogHeroAlignment heroAlignment;
  final WebsiteCatalogGridDensity gridDensity;
  final String heroImageUrl;
  final String heroEyebrow;
  final String heroTitle;
  final String heroDescription;
  final String megaMenuImageUrl;
  final String seoTitle;
  final String seoDescription;
  final String socialImageUrl;
  final bool allowIndexing;
  final double heroOverlay;
  final double megaMenuOverlay;
  final double megaMenuCardOverlay;
  final double megaMenuOverviewWidth;
  final WebsiteMegaMenuContentAlignment megaMenuContentAlignment;
  final bool showBreadcrumbs;
  final bool showSubcategories;
  final List<WebsiteCatalogFacet> facets;

  /// Canonical registry identity. For legacy category records this is the real
  /// category UUID; root records use one of the reserved catalog owner IDs.
  String get ownerId => categoryId;

  WebsiteCatalogRoot? get catalogRoot =>
      WebsiteCatalogRootX.fromPresentationId(ownerId);

  bool get isCatalogRoot => catalogRoot != null;

  bool get isCategoryPresentation => !isCatalogRoot;

  factory WebsiteCatalogPresentation.catalogRoot(
    WebsiteCatalogRoot root,
  ) {
    return WebsiteCatalogPresentation(
      categoryId: root.presentationId,
      slug: root.routeSegment,
      showBreadcrumbs: false,
      showSubcategories: false,
    );
  }

  factory WebsiteCatalogPresentation.fallback({
    required String categoryId,
    required String categoryName,
  }) {
    return WebsiteCatalogPresentation(
      categoryId: categoryId,
      slug: websiteCategorySlug(categoryName),
    );
  }

  factory WebsiteCatalogPresentation.fromJson(Map<String, dynamic> json) {
    final hasFacets = json.containsKey('facets');
    final rawFacets = json['facets'];
    final facets = rawFacets is List
        ? _dedupeFacets(
            rawFacets
                .map(WebsiteCatalogFacetX.tryFromStorage)
                .whereType<WebsiteCatalogFacet>(),
          )
        : const <WebsiteCatalogFacet>[];
    final overlay = (json['hero_overlay'] as num?)?.toDouble() ?? 0.42;
    return WebsiteCatalogPresentation(
      categoryId: json['category_id']?.toString() ?? '',
      slug: websiteCategorySlug(json['slug']?.toString() ?? ''),
      slugAliases: (json['slug_aliases'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>[],
      heroSize: WebsiteCatalogHeroSizeX.fromStorage(json['hero_size']),
      heroAlignment:
          WebsiteCatalogHeroAlignmentX.fromStorage(json['hero_alignment']),
      gridDensity: WebsiteCatalogGridDensityX.fromStorage(json['grid_density']),
      heroImageUrl: json['hero_image_url']?.toString().trim() ?? '',
      heroEyebrow: json['hero_eyebrow']?.toString().trim() ?? '',
      heroTitle: json['hero_title']?.toString().trim() ?? '',
      heroDescription: json['hero_description']?.toString().trim() ?? '',
      megaMenuImageUrl: json['mega_menu_image_url']?.toString().trim() ?? '',
      seoTitle: json['seo_title']?.toString().trim() ?? '',
      seoDescription: json['seo_description']?.toString().trim() ?? '',
      socialImageUrl: json['social_image_url']?.toString().trim() ?? '',
      allowIndexing: json['allow_indexing'] != false,
      heroOverlay: overlay.clamp(0.0, 0.78),
      megaMenuOverlay: (json['mega_menu_overlay'] as num?)?.toDouble() ?? 0.58,
      megaMenuCardOverlay:
          (json['mega_menu_card_overlay'] as num?)?.toDouble() ?? 0,
      megaMenuOverviewWidth:
          (json['mega_menu_overview_width'] as num?)?.toDouble() ??
              defaultMegaMenuOverviewWidth,
      megaMenuContentAlignment: WebsiteMegaMenuContentAlignmentX.fromStorage(
        json['mega_menu_content_alignment'],
      ),
      showBreadcrumbs: json['show_breadcrumbs'] != false,
      showSubcategories: json['show_subcategories'] != false,
      // Missing means “inherit the polished defaults”. An explicit empty list
      // means that the administrator deliberately hid every optional facet.
      facets: hasFacets ? facets : defaultFacets,
    ).normalizedForOwner();
  }

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'slug': slug,
        'slug_aliases': slugAliases,
        'hero_size': heroSize.storageValue,
        'hero_alignment': heroAlignment.storageValue,
        'grid_density': gridDensity.storageValue,
        'hero_image_url': heroImageUrl,
        'hero_eyebrow': heroEyebrow,
        'hero_title': heroTitle,
        'hero_description': heroDescription,
        'mega_menu_image_url': megaMenuImageUrl,
        'seo_title': seoTitle,
        'seo_description': seoDescription,
        'social_image_url': socialImageUrl,
        'allow_indexing': allowIndexing,
        'hero_overlay': heroOverlay,
        'mega_menu_overlay': megaMenuOverlay,
        'mega_menu_card_overlay': megaMenuCardOverlay,
        'mega_menu_overview_width': megaMenuOverviewWidth,
        'mega_menu_content_alignment': megaMenuContentAlignment.storageValue,
        'show_breadcrumbs': showBreadcrumbs,
        'show_subcategories': showSubcategories,
        'facets': facets.map((facet) => facet.storageValue).toList(),
      };

  WebsiteCatalogPresentation copyWith({
    String? slug,
    List<String>? slugAliases,
    WebsiteCatalogHeroSize? heroSize,
    WebsiteCatalogHeroAlignment? heroAlignment,
    WebsiteCatalogGridDensity? gridDensity,
    String? heroImageUrl,
    String? heroEyebrow,
    String? heroTitle,
    String? heroDescription,
    String? megaMenuImageUrl,
    String? seoTitle,
    String? seoDescription,
    String? socialImageUrl,
    bool? allowIndexing,
    double? heroOverlay,
    double? megaMenuOverlay,
    double? megaMenuCardOverlay,
    double? megaMenuOverviewWidth,
    WebsiteMegaMenuContentAlignment? megaMenuContentAlignment,
    bool? showBreadcrumbs,
    bool? showSubcategories,
    List<WebsiteCatalogFacet>? facets,
  }) {
    return WebsiteCatalogPresentation(
      categoryId: categoryId,
      slug: slug ?? this.slug,
      slugAliases: slugAliases ?? this.slugAliases,
      heroSize: heroSize ?? this.heroSize,
      heroAlignment: heroAlignment ?? this.heroAlignment,
      gridDensity: gridDensity ?? this.gridDensity,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      heroEyebrow: heroEyebrow ?? this.heroEyebrow,
      heroTitle: heroTitle ?? this.heroTitle,
      heroDescription: heroDescription ?? this.heroDescription,
      megaMenuImageUrl: megaMenuImageUrl ?? this.megaMenuImageUrl,
      seoTitle: seoTitle ?? this.seoTitle,
      seoDescription: seoDescription ?? this.seoDescription,
      socialImageUrl: socialImageUrl ?? this.socialImageUrl,
      allowIndexing: allowIndexing ?? this.allowIndexing,
      heroOverlay: heroOverlay ?? this.heroOverlay,
      megaMenuOverlay: megaMenuOverlay ?? this.megaMenuOverlay,
      megaMenuCardOverlay: megaMenuCardOverlay ?? this.megaMenuCardOverlay,
      megaMenuOverviewWidth:
          megaMenuOverviewWidth ?? this.megaMenuOverviewWidth,
      megaMenuContentAlignment:
          megaMenuContentAlignment ?? this.megaMenuContentAlignment,
      showBreadcrumbs: showBreadcrumbs ?? this.showBreadcrumbs,
      showSubcategories: showSubcategories ?? this.showSubcategories,
      facets: facets ?? this.facets,
    );
  }

  /// Stable deep comparison used by editor draft/save/discard semantics.
  ///
  /// `toJson` has a deterministic key order and the facet order is meaningful,
  /// so the encoded values form an exact persistence-boundary comparison.
  bool hasSamePersistedValue(WebsiteCatalogPresentation other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  /// Removes values that the selected owner cannot expose or consume.
  ///
  /// Catalog roots currently own grid density, ordered facets and explicit SEO
  /// values. This prevents imports/automation from creating hidden root hero
  /// values that no administrator could inspect in the workspace.
  WebsiteCatalogPresentation normalizedForOwner() {
    final root = catalogRoot;
    if (root == null) return this;
    return WebsiteCatalogPresentation.catalogRoot(root).copyWith(
      gridDensity: gridDensity,
      facets: facets,
      seoTitle: seoTitle,
      seoDescription: seoDescription,
      socialImageUrl: socialImageUrl,
      allowIndexing: allowIndexing,
    );
  }
}

List<WebsiteCatalogFacet> _dedupeFacets(
  Iterable<WebsiteCatalogFacet> facets,
) {
  final seen = <WebsiteCatalogFacet>{};
  return facets.where(seen.add).toList(growable: false);
}

class WebsiteCatalogPresentationRegistry {
  const WebsiteCatalogPresentationRegistry(this.byCategoryId);

  /// Legacy-compatible backing name retained for existing category consumers.
  ///
  /// New code should use [byOwnerId], because the two canonical catalog roots
  /// now live beside category UUID owners in this same registry.
  final Map<String, WebsiteCatalogPresentation> byCategoryId;

  Map<String, WebsiteCatalogPresentation> get byOwnerId => byCategoryId;

  WebsiteCatalogPresentation? forCategory(String? categoryId) {
    if (categoryId == null) return null;
    final presentation = byCategoryId[categoryId];
    return presentation?.isCategoryPresentation == true ? presentation : null;
  }

  WebsiteCatalogPresentation? forCatalogRoot(WebsiteCatalogRoot root) {
    return byCategoryId[root.presentationId];
  }

  WebsiteCatalogPresentation? forSlug(String rawSlug) {
    return resolveSlug(rawSlug)?.presentation;
  }

  int categorySlugClaimCount(String rawSlug) {
    final slug = websiteCategorySlug(rawSlug);
    if (slug.isEmpty) return 0;
    return byCategoryId.values.where((presentation) {
      return presentation.isCategoryPresentation &&
          (presentation.slug == slug ||
              presentation.slugAliases.contains(slug));
    }).length;
  }

  /// Resolves a current category slug or one of its durable aliases.
  ///
  /// Imported/legacy settings can predate collision validation. If more than
  /// one category claims the same current slug or alias, resolution fails
  /// closed instead of selecting whichever map entry happened to be first.
  WebsiteCatalogSlugResolution? resolveSlug(String rawSlug) {
    final slug = websiteCategorySlug(rawSlug);
    if (slug.isEmpty) return null;
    final matches = <WebsiteCatalogPresentation>[];
    for (final presentation in byCategoryId.values) {
      if (!presentation.isCategoryPresentation) continue;
      if (presentation.slug == slug ||
          presentation.slugAliases.contains(slug)) {
        matches.add(presentation);
      }
    }
    if (matches.length != 1) return null;
    final presentation = matches.single;
    return WebsiteCatalogSlugResolution(
      presentation: presentation,
      requestedSlug: slug,
      matchedAlias: presentation.slug != slug,
    );
  }

  int get categoryPresentationCount => byCategoryId.values
      .where((presentation) => presentation.isCategoryPresentation)
      .length;

  factory WebsiteCatalogPresentationRegistry.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const WebsiteCatalogPresentationRegistry({});
    }
    try {
      final decoded = jsonDecode(raw);
      final items = decoded is Map<String, dynamic> ? decoded['items'] : null;
      if (items is! List) {
        return const WebsiteCatalogPresentationRegistry({});
      }
      final byCategoryId = <String, WebsiteCatalogPresentation>{};
      for (final item in items.whereType<Map>()) {
        final presentation = WebsiteCatalogPresentation.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (presentation.ownerId.isNotEmpty && presentation.slug.isNotEmpty) {
          byCategoryId[presentation.ownerId] = presentation;
        }
      }
      return WebsiteCatalogPresentationRegistry(byCategoryId);
    } catch (_) {
      return const WebsiteCatalogPresentationRegistry({});
    }
  }

  String encode() {
    final items = byCategoryId.values.toList(growable: false)
      ..sort((a, b) => a.ownerId.compareTo(b.ownerId));
    return jsonEncode({
      'version': 1,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    });
  }

  WebsiteCatalogPresentationRegistry put(
    WebsiteCatalogPresentation presentation,
  ) {
    final normalized = presentation.normalizedForOwner();
    return WebsiteCatalogPresentationRegistry({
      ...byCategoryId,
      normalized.ownerId: normalized,
    });
  }

  /// Prepares the value that [WebsiteService] persists.
  ///
  /// A category slug change automatically turns the previously saved slug
  /// into a durable alias. Both current slugs and aliases share one namespace;
  /// collisions are rejected before the registry is encoded.
  WebsiteCatalogPresentation prepareForSave(
    WebsiteCatalogPresentation presentation,
  ) {
    final normalized = presentation.normalizedForOwner();
    if (!normalized.isCategoryPresentation) return normalized;

    final existing = forCategory(normalized.ownerId);
    final previousSlugIsUnambiguous =
        existing != null && categorySlugClaimCount(existing.slug) == 1;
    final next = previousSlugIsUnambiguous && existing.slug != normalized.slug
        ? normalized.copyWith(
            slugAliases: [existing.slug, ...normalized.slugAliases],
          )
        : normalized;
    final nextClaims = <String>{next.slug, ...next.slugAliases};

    for (final other in byCategoryId.values) {
      if (!other.isCategoryPresentation || other.ownerId == next.ownerId) {
        continue;
      }
      final otherClaims = <String>{other.slug, ...other.slugAliases};
      final collisions = nextClaims.intersection(otherClaims);
      if (collisions.isNotEmpty) {
        throw WebsiteCatalogSlugCollisionException(
          slug: collisions.first,
          existingOwnerId: other.ownerId,
        );
      }
    }
    return next;
  }

  WebsiteCatalogPresentationRegistry remove(String categoryId) {
    final next = Map<String, WebsiteCatalogPresentation>.from(byCategoryId)
      ..remove(categoryId);
    return WebsiteCatalogPresentationRegistry(next);
  }
}

class WebsiteCatalogSlugCollisionException implements Exception {
  const WebsiteCatalogSlugCollisionException({
    required this.slug,
    required this.existingOwnerId,
  });

  final String slug;
  final String existingOwnerId;

  @override
  String toString() =>
      'La ruta “$slug” ya pertenece a otra categoría o a uno de sus alias.';
}

class WebsiteCatalogSlugResolution {
  const WebsiteCatalogSlugResolution({
    required this.presentation,
    required this.requestedSlug,
    required this.matchedAlias,
  });

  final WebsiteCatalogPresentation presentation;
  final String requestedSlug;
  final bool matchedAlias;
}

List<String> _normalizeCategorySlugAliases(
  Iterable<String> aliases, {
  required String currentSlug,
}) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final rawAlias in aliases) {
    final alias = websiteCategorySlug(rawAlias);
    if (alias.isEmpty || alias == currentSlug || !seen.add(alias)) continue;
    normalized.add(alias);
  }
  return normalized;
}

String websiteCategorySlug(String raw) {
  var value = raw.trim().toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  for (final entry in replacements.entries) {
    value = value.replaceAll(entry.key, entry.value);
  }
  value = value
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return value;
}

String publicCategoryPath({
  required WebsiteCatalogPresentation presentation,
  bool services = false,
}) {
  final catalogRoot = presentation.catalogRoot;
  if (catalogRoot != null) {
    return '/${catalogRoot.routeSegment}';
  }
  final root = services ? 'servicios' : 'productos';
  return '/$root/categoria/${presentation.slug}';
}

class WebsiteCatalogGridMetrics {
  const WebsiteCatalogGridMetrics({
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
  });

  final int crossAxisCount;
  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
}

/// Shared responsive grid projection for public, Edit and Preview consumers.
///
/// Keep this function presentation-only: product eligibility and paging remain
/// owned by the public catalog query.
WebsiteCatalogGridMetrics websiteCatalogGridMetrics({
  required double width,
  required WebsiteCatalogGridDensity density,
}) {
  if (width < 400) {
    return const WebsiteCatalogGridMetrics(
      crossAxisCount: 2,
      childAspectRatio: 0.58,
      crossAxisSpacing: 16,
      mainAxisSpacing: 22,
    );
  }
  if (width < 600) {
    return const WebsiteCatalogGridMetrics(
      crossAxisCount: 2,
      childAspectRatio: 0.63,
      crossAxisSpacing: 18,
      mainAxisSpacing: 24,
    );
  }
  if (width < 980) {
    return const WebsiteCatalogGridMetrics(
      crossAxisCount: 3,
      childAspectRatio: 0.69,
      crossAxisSpacing: 22,
      mainAxisSpacing: 30,
    );
  }
  if (width < 1320) {
    return WebsiteCatalogGridMetrics(
      crossAxisCount: density == WebsiteCatalogGridDensity.editorial ? 3 : 4,
      childAspectRatio:
          density == WebsiteCatalogGridDensity.editorial ? 0.76 : 0.72,
      crossAxisSpacing: 28,
      mainAxisSpacing: 36,
    );
  }
  return WebsiteCatalogGridMetrics(
    crossAxisCount: density == WebsiteCatalogGridDensity.compact ? 5 : 4,
    childAspectRatio:
        density == WebsiteCatalogGridDensity.editorial ? 0.82 : 0.75,
    crossAxisSpacing: density == WebsiteCatalogGridDensity.compact ? 26 : 34,
    mainAxisSpacing: 40,
  );
}
