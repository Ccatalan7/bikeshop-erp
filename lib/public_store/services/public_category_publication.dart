import '../../modules/website/models/website_catalog_presentation.dart';
import '../../modules/website/models/website_destination.dart';
import '../../modules/website/models/website_page_models.dart';

/// Minimal projection of a product category needed to reason about
/// publication.
///
/// Deliberately not the full `Category` model: this stays a pure rule,
/// unit-testable without Supabase, Flutter or the inventory service.
class PublicCategoryDescriptor {
  const PublicCategoryDescriptor({
    required this.id,
    required this.name,
    required this.fullPath,
    required this.showOnWebsite,
  });

  final String id;
  final String name;
  final String fullPath;

  /// The `product_categories.show_on_website` flag — the single owner of
  /// whether a category is a public destination.
  final bool showOnWebsite;
}

/// Publication truth plus menu-consistency diagnostics.
///
/// Ownership is deliberately asymmetric and this class must never blur it:
///
///  * `product_categories.show_on_website` **owns** whether a category is a
///    public destination. [publishedIds] is derived from that flag alone.
///  * `website_navigation` owns placement — where a published category
///    appears in the menus, in what order, under which parent. It is not a
///    second publisher, and nothing here may widen publication because a menu
///    row exists.
///
/// A menu row pointing at an unpublished or nonexistent category is a
/// *misconfiguration to surface*, not an instruction to follow: it is
/// reported through [menuOnlyCategoryIds] / [unresolvedNavigationTokens].
/// Public renderers must also consume [PublicCategoryNavigationProjection] so
/// the stale row never becomes a customer-facing destination while the data is
/// being corrected in its canonical owner.
class PublicCategoryPublication {
  const PublicCategoryPublication({
    required this.publishedIds,
    required this.menuOnlyCategoryIds,
    required this.unresolvedNavigationTokens,
    required Map<String, PublicCategoryDescriptor> categoriesById,
    required Map<String, Set<String>> categoryIdsBySlug,
    required WebsiteCatalogPresentationRegistry presentationRegistry,
  })  : _categoriesById = categoriesById,
        _categoryIdsBySlug = categoryIdsBySlug,
        _presentationRegistry = presentationRegistry;

  const PublicCategoryPublication._empty()
      : publishedIds = const <String>{},
        menuOnlyCategoryIds = const <String>{},
        unresolvedNavigationTokens = const <String>{},
        _categoriesById = const <String, PublicCategoryDescriptor>{},
        _categoryIdsBySlug = const <String, Set<String>>{},
        _presentationRegistry = const WebsiteCatalogPresentationRegistry({});

  factory PublicCategoryPublication.empty() =>
      const PublicCategoryPublication._empty();

  final Map<String, PublicCategoryDescriptor> _categoriesById;
  final Map<String, Set<String>> _categoryIdsBySlug;
  final WebsiteCatalogPresentationRegistry _presentationRegistry;

  /// Categories that are public destinations: exactly the flagged set.
  final Set<String> publishedIds;

  /// Menu destinations that resolve to a real category the owner has NOT
  /// published. These are retained as editor diagnostics, but a public
  /// navigation projection must not expose them as destinations.
  final Set<String> menuOnlyCategoryIds;

  /// Menu destinations that name no unambiguous category at all.
  final Set<String> unresolvedNavigationTokens;

  bool isPublished(String? categoryId) =>
      categoryId != null && publishedIds.contains(categoryId);

  /// Resolves a category value against every active category, independently
  /// from publication.
  ///
  /// This is the read-side counterpart of [allowsCategoryValue]. It lets a
  /// route distinguish a known withdrawn collection from an unknown or
  /// ambiguous URL without ever turning that category back into a public
  /// destination.
  String? resolveCategoryValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final token = _categoryTokenFromRaw(normalized);
    if (token == null || token.isEmpty) return null;
    return _resolveToken(
      token,
      byId: _categoriesById,
      bySlug: _categoryIdsBySlug,
      presentationRegistry: _presentationRegistry,
    );
  }

  bool isKnownUnpublishedCategoryValue(String value) {
    final categoryId = resolveCategoryValue(value);
    return categoryId != null && !isPublished(categoryId);
  }

  /// Resolves every category destination shape historically stored by the
  /// Website Builder. Ambiguity and missing records fail closed.
  String? resolveNavigationCategoryId(
    WebsiteNavigation navigation, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final token = navigation.linkType == NavLinkType.category
        ? _categoryToken(
            navigation,
            internalOrigins: internalOrigins,
          )
        : _catalogCategoryTokenFromNavigation(
            navigation,
            internalOrigins: internalOrigins,
          );
    if (token == null || token.isEmpty) return null;
    return _resolveToken(
      token,
      byId: _categoriesById,
      bySlug: _categoryIdsBySlug,
      presentationRegistry: _presentationRegistry,
    );
  }

  bool isCategoryDestination(
    WebsiteNavigation navigation, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) =>
      navigation.linkType == NavLinkType.category ||
      _catalogCategoryTokenFromNavigation(
            navigation,
            internalOrigins: internalOrigins,
          ) !=
          null;

  /// Whether this authored item may act as a public destination.
  ///
  /// Non-category destinations preserve their existing behavior. Category
  /// destinations are allowed only when they resolve unambiguously to the
  /// flag-owned publication set.
  bool allowsNavigationDestination(
    WebsiteNavigation navigation, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    if (!isCategoryDestination(
      navigation,
      internalOrigins: internalOrigins,
    )) {
      return navigation.href?.trim().isNotEmpty == true;
    }
    return isPublished(
      resolveNavigationCategoryId(
        navigation,
        internalOrigins: internalOrigins,
      ),
    );
  }

  /// Applies the same category-publication boundary to an arbitrary href.
  ///
  /// Useful for defensive checks outside menu widgets (for example a CTA or
  /// a legacy internal link). Non-category hrefs remain eligible.
  bool allowsHref(
    String href, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final normalized = WebsiteDestination.normalizeHref(
      href,
      internalOrigins: internalOrigins,
    );
    if (normalized.isEmpty) return false;
    final token = _catalogCategoryTokenFromHref(
      normalized,
      internalOrigins: internalOrigins,
    );
    if (token == null) return true;
    return _allowsCategoryToken(token);
  }

  /// Applies publication to a value authored inside a category-specific
  /// surface, where a bare UUID/name is known to represent a category rather
  /// than an arbitrary page or product.
  ///
  /// This is intentionally stricter than [allowsHref]: a generic catalog URL
  /// has no category token and therefore cannot masquerade as a category card.
  bool allowsCategoryValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return false;
    final token = _categoryTokenFromRaw(normalized);
    if (token == null || token.isEmpty) return false;
    return _allowsCategoryToken(token);
  }

  bool _allowsCategoryToken(String token) {
    final resolved = _resolveToken(
      token,
      byId: _categoriesById,
      bySlug: _categoryIdsBySlug,
      presentationRegistry: _presentationRegistry,
    );
    return isPublished(resolved);
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static final RegExp _categoryPath =
      RegExp(r'^/(?:tienda/)?(?:productos|servicios)/categoria/([^/?#]+)');

  static PublicCategoryPublication resolve({
    required Iterable<PublicCategoryDescriptor> categories,
    required Iterable<WebsiteNavigation> navigation,
    WebsiteCatalogPresentationRegistry presentationRegistry =
        const WebsiteCatalogPresentationRegistry({}),
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final byId = <String, PublicCategoryDescriptor>{};
    final bySlug = <String, Set<String>>{};

    for (final category in categories) {
      if (category.id.isEmpty) continue;
      byId[category.id] = category;
      for (final slug in <String>{
        websiteCategorySlug(category.name),
        websiteCategorySlug(category.fullPath),
      }) {
        if (slug.isEmpty) continue;
        bySlug.putIfAbsent(slug, () => <String>{}).add(category.id);
      }
    }

    // Publication is the flag, full stop.
    final published = <String>{
      for (final category in byId.values)
        if (category.showOnWebsite) category.id,
    };

    // Everything below is diagnosis of the menus against that truth.
    final menuOnly = <String>{};
    final unresolved = <String>{};
    for (final item in _flattenNavigation(navigation)) {
      if (!item.isVisible) continue;
      if (item.linkType != NavLinkType.category) continue;

      final token = _categoryToken(
        item,
        internalOrigins: internalOrigins,
      );
      if (token == null || token.isEmpty) continue;

      final resolved = _resolveToken(
        token,
        byId: byId,
        bySlug: bySlug,
        presentationRegistry: presentationRegistry,
      );
      if (resolved == null) {
        unresolved.add(token);
      } else if (!published.contains(resolved)) {
        menuOnly.add(resolved);
      }
    }

    return PublicCategoryPublication(
      publishedIds: Set<String>.unmodifiable(published),
      menuOnlyCategoryIds: Set<String>.unmodifiable(menuOnly),
      unresolvedNavigationTokens: Set<String>.unmodifiable(unresolved),
      categoriesById: Map<String, PublicCategoryDescriptor>.unmodifiable(byId),
      categoryIdsBySlug: Map<String, Set<String>>.unmodifiable({
        for (final entry in bySlug.entries)
          entry.key: Set<String>.unmodifiable(entry.value),
      }),
      presentationRegistry: presentationRegistry,
    );
  }

  static Iterable<WebsiteNavigation> _flattenNavigation(
    Iterable<WebsiteNavigation> roots,
  ) sync* {
    for (final item in roots) {
      yield item;
      yield* _flattenNavigation(item.children);
    }
  }

  /// Extracts the category identifier a menu destination points at.
  ///
  /// `link_value` is not one shape. Older rows store a bare category id or the
  /// legacy `'/productos?category=<id>'`; newer editor saves store the clean
  /// `'/productos/categoria/<slug>'`. All three must resolve for the
  /// diagnostics to be trustworthy.
  static String? _categoryToken(
    WebsiteNavigation item, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final raw = item.linkValue?.trim();
    if (raw == null || raw.isEmpty) return null;
    final catalogToken = _catalogCategoryTokenFromHref(
      raw,
      internalOrigins: internalOrigins,
    );
    if (catalogToken != null) return catalogToken;
    return _categoryTokenFromRaw(raw);
  }

  static String? _categoryTokenFromRaw(String raw) {
    if (raw.isEmpty) return null;
    if (!raw.startsWith('/')) return raw;

    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final pathMatch = _categoryPath.firstMatch(uri.path);
    if (pathMatch != null) {
      return Uri.decodeComponent(pathMatch.group(1)!);
    }

    final qp = uri.queryParameters;
    final fromQuery =
        (qp['category'] ?? qp['category_id'] ?? qp['cat'] ?? '').trim();
    return fromQuery.isEmpty ? null : fromQuery;
  }

  /// Detects only catalog-category URL shapes. Unlike [_categoryTokenFromRaw],
  /// this never interprets an arbitrary bare page/custom value as a category.
  static String? _catalogCategoryTokenFromHref(
    String raw, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final normalized = WebsiteDestination.normalizeHref(
      raw,
      internalOrigins: internalOrigins,
    );
    if (!normalized.startsWith('/')) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return null;

    final pathMatch = _categoryPath.firstMatch(uri.path);
    if (pathMatch != null) {
      return Uri.decodeComponent(pathMatch.group(1)!);
    }
    if (uri.path != '/productos' &&
        uri.path != '/servicios' &&
        uri.path != '/tienda/productos' &&
        uri.path != '/tienda/servicios') {
      return null;
    }
    final qp = uri.queryParameters;
    final token =
        (qp['category'] ?? qp['category_id'] ?? qp['cat'] ?? '').trim();
    return token.isEmpty ? null : token;
  }

  static String? _catalogCategoryTokenFromNavigation(
    WebsiteNavigation navigation, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final authored = navigation.linkValue?.trim() ?? '';
    final authoredToken = _catalogCategoryTokenFromHref(
      authored,
      internalOrigins: internalOrigins,
    );
    if (authoredToken != null) return authoredToken;
    return _catalogCategoryTokenFromHref(
      navigation.href ?? '',
      internalOrigins: internalOrigins,
    );
  }

  /// Ambiguity fails closed: a duplicated leaf slug must never resolve to an
  /// unrelated branch that happens to share a name.
  static String? _resolveToken(
    String token, {
    required Map<String, PublicCategoryDescriptor> byId,
    required Map<String, Set<String>> bySlug,
    required WebsiteCatalogPresentationRegistry presentationRegistry,
  }) {
    if (_uuid.hasMatch(token)) {
      return byId.containsKey(token) ? token : null;
    }
    final registryClaims = presentationRegistry.categorySlugClaimCount(token);
    if (registryClaims > 0) {
      final categoryId =
          presentationRegistry.resolveSlug(token)?.presentation.categoryId;
      return categoryId != null && byId.containsKey(categoryId)
          ? categoryId
          : null;
    }
    final matches = bySlug[websiteCategorySlug(token)];
    if (matches == null || matches.length != 1) return null;
    return matches.single;
  }
}

enum PublicNavigationAudience {
  desktop,
  mobile,
}

/// Shared public projection for every surface backed by
/// `website_navigation`.
///
/// The projection may narrow publication but can never widen it:
///
/// * a published category remains a navigable destination;
/// * the first two authored menu levels may remain as non-navigable layout
///   containers when they organize published descendants;
/// * below that menu shell, an unpublished category is never rendered: its
///   published descendants are promoted to the nearest surviving container;
/// * an unpublished/unresolved leaf disappears;
/// * non-category navigation keeps its authored behavior.
///
/// An empty publication is intentionally fail-closed for category
/// destinations. The storefront bootstrap loads the retained category
/// snapshot before revealing navigation, so visitors do not see stale links
/// while the first classification is in flight.
class PublicCategoryNavigationProjection {
  const PublicCategoryNavigationProjection(
    this.publication, {
    this.internalOrigins = const <Uri>[],
  });

  final PublicCategoryPublication publication;
  final Iterable<Uri> internalOrigins;

  bool canNavigate(WebsiteNavigation navigation) =>
      publication.allowsNavigationDestination(
        navigation,
        internalOrigins: internalOrigins,
      );

  List<WebsiteNavigation> forDesktop(
    Iterable<WebsiteNavigation> navigation,
  ) =>
      _project(
        navigation,
        audience: PublicNavigationAudience.desktop,
      );

  List<WebsiteNavigation> forMobile(
    Iterable<WebsiteNavigation> navigation,
  ) =>
      _project(
        navigation,
        audience: PublicNavigationAudience.mobile,
      );

  List<WebsiteNavigation> _project(
    Iterable<WebsiteNavigation> navigation, {
    required PublicNavigationAudience audience,
  }) {
    return List<WebsiteNavigation>.unmodifiable(
      _projectLevel(
        navigation,
        audience: audience,
        depth: 0,
      ),
    );
  }

  List<WebsiteNavigation> _projectLevel(
    Iterable<WebsiteNavigation> navigation, {
    required PublicNavigationAudience audience,
    required int depth,
  }) {
    final result = <WebsiteNavigation>[];
    for (final item in navigation) {
      final visibleForAudience = item.isVisible &&
          switch (audience) {
            PublicNavigationAudience.desktop => item.showOnDesktop,
            PublicNavigationAudience.mobile => item.showOnMobile,
          };
      if (!visibleForAudience) continue;

      final projectedChildren = _projectLevel(
        item.children,
        audience: audience,
        depth: depth + 1,
      );

      if (publication.isCategoryDestination(
            item,
            internalOrigins: internalOrigins,
          ) &&
          !canNavigate(item)) {
        if (projectedChildren.isEmpty) continue;

        // Depths 0 and 1 are the authored header/rail shell of the mega menu.
        // They may organize public leaves, but their stale category payload is
        // stripped. Deeper rows are customer-facing category cards/items:
        // never expose an unpublished label such as "Piñones"; promote its
        // public children (for example "Cassette") in its place.
        if (depth <= 1) {
          result.add(
            _asStructuralGroup(
              item,
              children: projectedChildren,
            ),
          );
        } else {
          result.addAll(projectedChildren);
        }
        continue;
      }

      result.add(
        item.copyWith(
          children: List<WebsiteNavigation>.unmodifiable(projectedChildren),
        ),
      );
    }

    return result;
  }

  /// Removes the route payload from a category retained only as a grouping.
  ///
  /// The predicate remains the primary semantic guard, but making the
  /// projected value itself non-navigable prevents a renderer, focus action or
  /// future consumer from accidentally following the authored stale href.
  WebsiteNavigation _asStructuralGroup(
    WebsiteNavigation source, {
    required List<WebsiteNavigation> children,
  }) {
    return WebsiteNavigation(
      id: source.id,
      tenantId: source.tenantId,
      menuLocation: source.menuLocation,
      label: source.label,
      icon: source.icon,
      linkType: NavLinkType.action,
      linkValue: null,
      openInNewTab: false,
      parentId: source.parentId,
      orderIndex: source.orderIndex,
      isVisible: source.isVisible,
      showOnDesktop: source.showOnDesktop,
      showOnMobile: source.showOnMobile,
      cssClass: source.cssClass,
      highlight: source.highlight,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      children: List<WebsiteNavigation>.unmodifiable(children),
      linkedPage: null,
    );
  }
}
