import 'seo_helper_stub.dart' if (dart.library.html) 'seo_helper_web.dart';

/// Helper to update SEO Meta Tags and Title in the browser
class SeoHelper {
  /// Updates the browser title and meta (description, keywords, og:image)
  static void updateSeo({
    required String title,
    String? description,
    String? imageUrl,
    String? keywords,
    String? canonicalUrl,
    String? robots,
    String ogType = 'website',
  }) {
    updateSeoImpl(
      title: title,
      description: description,
      imageUrl: imageUrl,
      keywords: keywords,
      canonicalUrl: canonicalUrl,
      robots: robots,
      ogType: ogType,
    );
  }
}

class StorefrontSeoRouteProjection {
  const StorefrontSeoRouteProjection({
    required this.canonicalPath,
    required this.robots,
  });

  final String canonicalPath;
  final String robots;

  bool get isIndexable => robots == 'index,follow';
}

String normalizeStorefrontSeoPath(String rawPath) {
  var path = rawPath.trim();
  if (path.isEmpty) return '/';
  if (!path.startsWith('/')) path = '/$path';
  if (path == '/tienda') return '/';
  if (path.startsWith('/tienda/')) {
    path = path.substring('/tienda'.length);
  }
  if (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

bool isCatalogSeoManagedPath(String rawPath) {
  final path = normalizeStorefrontSeoPath(rawPath);
  return path == '/productos' ||
      path == '/servicios' ||
      path == '/productos/categoria' ||
      path.startsWith('/productos/categoria/') ||
      path == '/servicios/categoria' ||
      path.startsWith('/servicios/categoria/');
}

/// The catalog namespace comes from the route, never from a secondary filter.
///
/// In particular, `/productos/...?type=service` still belongs to the product
/// catalog for canonical and withdrawn-route purposes.
String storefrontCatalogRootPath(String rawPath) {
  final path = normalizeStorefrontSeoPath(rawPath);
  if (path == '/servicios' || path.startsWith('/servicios/')) {
    return '/servicios';
  }
  return '/productos';
}

/// Resolves a catalog selection without letting transient filter state change
/// the route namespace that owns the current page.
///
/// A root selection deliberately ignores [publishedCategoryPath]. This guards
/// withdrawn collection redirects from accidentally reusing the presentation
/// of a secondary `type=service` filter and crossing from `/productos` into
/// `/servicios`.
String storefrontCatalogSelectionPath({
  required String currentPath,
  required bool hasSelectedCategory,
  String? publishedCategoryPath,
}) {
  final candidate = publishedCategoryPath?.trim() ?? '';
  if (hasSelectedCategory && candidate.isNotEmpty) {
    return normalizeStorefrontSeoPath(candidate);
  }
  return storefrontCatalogRootPath(currentPath);
}

bool isProductDetailSeoManagedPath(String rawPath) {
  final path = normalizeStorefrontSeoPath(rawPath);
  return path.startsWith('/producto/') ||
      path.startsWith('/shop/') ||
      (path.startsWith('/productos/') &&
          !path.startsWith('/productos/categoria/'));
}

bool isStaticPolicySeoManagedPath(String rawPath) {
  final path = normalizeStorefrontSeoPath(rawPath);
  return const {
    '/nosotros',
    '/envios',
    '/devoluciones',
    '/terminos',
    '/privacidad',
  }.contains(path);
}

bool isDynamicWebsitePageSeoManagedPath(String rawPath) {
  final path = normalizeStorefrontSeoPath(rawPath);
  if (!path.startsWith('/pagina/')) return false;
  return path.substring('/pagina/'.length).trim().isNotEmpty;
}

/// System-owned indexation policy for public-store application routes.
///
/// Valuable combinations must become real editor-owned collections. Search,
/// sort, pagination and visitor facets remain transient application state and
/// canonicalize to the clean route without entering the index. An editor-owned
/// allow-indexing value is only an additional restriction: it cannot override
/// private mode, publication, content eligibility or transient-route policy.
StorefrontSeoRouteProjection projectStorefrontSeoRoute(
  Uri uri, {
  required bool isErpMounted,
  bool ownerAllowsIndexing = true,
  bool ownerIsPublished = true,
  bool hasEligibleContent = true,
  String? unavailableCanonicalPath,
}) {
  final currentPath = normalizeStorefrontSeoPath(uri.path);
  final fallbackCanonicalPath = unavailableCanonicalPath?.trim() ?? '';
  final canonicalPath = (!ownerIsPublished || !hasEligibleContent) &&
          fallbackCanonicalPath.isNotEmpty
      ? normalizeStorefrontSeoPath(fallbackCanonicalPath)
      : currentPath;

  const transientCatalogKeys = <String>{
    'q',
    'search',
    'type',
    'product_type',
    'tipo',
    'category',
    'category_id',
    'cat',
    'categoria',
    'category_scope',
    'brand',
    'brands',
    'brand_id',
    'brand_ids',
    'marca',
    'marcas',
    'min_price',
    'price_min',
    'precio_min',
    'max_price',
    'price_max',
    'precio_max',
    'stock',
    'availability',
    'disponibilidad',
    'only_in_stock',
    'sort',
    'sort_by',
    'orden',
    'page',
    'pagina',
    'page_size',
    'per_page',
    'limit',
  };
  final hasTransientCatalogState = uri.queryParameters.keys.any(
    transientCatalogKeys.contains,
  );
  final hasPrivateMode = uri.queryParameters['preview'] == 'true' ||
      uri.queryParameters['edit'] == 'true';
  final isTransactionalOrPrivate = currentPath == '/carrito' ||
      currentPath == '/checkout' ||
      currentPath == '/auth/callback' ||
      currentPath.startsWith('/cuenta') ||
      currentPath.startsWith('/pedido');
  final noIndex = isErpMounted ||
      hasPrivateMode ||
      hasTransientCatalogState ||
      isTransactionalOrPrivate ||
      !ownerAllowsIndexing ||
      !ownerIsPublished ||
      !hasEligibleContent;

  return StorefrontSeoRouteProjection(
    canonicalPath: canonicalPath,
    robots: noIndex ? 'noindex,follow' : 'index,follow',
  );
}
