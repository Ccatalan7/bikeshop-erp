import 'website_page_models.dart';
import 'website_catalog_presentation.dart';
import 'website_catalog_query.dart';

/// Semantic type of a destination selected by a Website Builder link control.
enum WebsiteDestinationKind {
  none,
  system,
  page,
  category,
  product,
  anchor,
  external,
  custom,
}

/// Canonical parser shared by CTA controls, navigation, and destination audits.
///
/// Existing blocks continue to persist an href string for compatibility, but
/// the href is interpreted as a typed reference to the owning CMS/catalog
/// record whenever possible.
class WebsiteDestination {
  const WebsiteDestination({
    required this.kind,
    required this.href,
    this.reference,
  });

  final WebsiteDestinationKind kind;
  final String href;

  /// Page slug, category ID, product ID/token, anchor, or external URL.
  final String? reference;

  static const Map<String, String> systemRoutes = {
    '/': 'Inicio',
    '/productos': 'Catálogo',
    '/servicios': 'Servicios',
    '/contacto': 'Contacto',
    '/carrito': 'Carrito',
    '/checkout': 'Checkout',
    '/cuenta': 'Mi cuenta',
    '/cuenta/login': 'Login',
    '/cuenta/pedidos': 'Mis pedidos',
    '/nosotros': 'Sobre nosotros',
    '/terminos': 'Términos y condiciones',
    '/privacidad': 'Política de privacidad',
    '/devoluciones': 'Devoluciones',
    '/envios': 'Envíos',
  };

  static WebsiteDestination parse(
    String rawHref, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    final href = normalizeHref(
      rawHref,
      internalOrigins: internalOrigins,
    );
    if (href.isEmpty) {
      return const WebsiteDestination(
        kind: WebsiteDestinationKind.none,
        href: '',
      );
    }
    if (href.startsWith('http://') || href.startsWith('https://')) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.external,
        href: href,
        reference: href,
      );
    }
    if (href.startsWith('#')) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.anchor,
        href: href,
        reference: href.substring(1),
      );
    }

    final uri = Uri.tryParse(href);
    if (uri == null) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.custom,
        href: href,
        reference: href,
      );
    }

    final path = uri.path;
    final category = uri.queryParameters['category'];
    if ((path == '/productos' || path == '/servicios') &&
        category != null &&
        category.trim().isNotEmpty) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.category,
        href: href,
        reference: category.trim(),
      );
    }
    if (path.startsWith('/productos/categoria/') ||
        path.startsWith('/servicios/categoria/')) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.category,
        href: href,
        reference: pathSegments(path).lastOrNull,
      );
    }
    if (path.startsWith('/pagina/')) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.page,
        href: href,
        reference: pathSegments(path).lastOrNull,
      );
    }
    if (path.startsWith('/productos/')) {
      final segments = pathSegments(path);
      if (segments.length >= 2 && segments[1] != 'categoria') {
        return WebsiteDestination(
          kind: WebsiteDestinationKind.product,
          href: href,
          reference: segments.length == 2 ? segments[1] : segments.last,
        );
      }
    }
    if (systemRoutes.containsKey(path) && uri.queryParameters.isEmpty) {
      return WebsiteDestination(
        kind: WebsiteDestinationKind.system,
        href: href,
        reference: path,
      );
    }
    return WebsiteDestination(
      kind: WebsiteDestinationKind.custom,
      href: href,
      reference: href,
    );
  }

  /// Normalizes authored storefront destinations before they are classified.
  ///
  /// Absolute HTTP(S) URLs remain external by default. Callers that know the
  /// active storefront origins may supply them so an authored absolute link
  /// back to the same store is classified exactly like its relative form.
  static String normalizeHref(
    String rawHref, {
    Iterable<Uri> internalOrigins = const <Uri>[],
  }) {
    var value = rawHref.trim();
    if (value.isEmpty || value.startsWith('#')) {
      return value;
    }

    final absolute = Uri.tryParse(value);
    if (absolute != null &&
        (absolute.scheme == 'http' || absolute.scheme == 'https')) {
      final isInternal =
          internalOrigins.any((origin) => _sameHttpOrigin(absolute, origin));
      if (!isInternal) return value;

      final buffer = StringBuffer(
        absolute.path.isEmpty ? '/' : absolute.path,
      );
      if (absolute.hasQuery) buffer.write('?${absolute.query}');
      if (absolute.hasFragment) buffer.write('#${absolute.fragment}');
      value = buffer.toString();
    }

    if (!value.startsWith('/')) value = '/$value';

    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    var path = uri.path;
    if (path == '/tienda' || path == '/tienda/') {
      path = '/';
    } else if (path.startsWith('/tienda/')) {
      path = path.replaceFirst('/tienda', '');
    }
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final query = Map<String, String>.from(uri.queryParameters);
    for (final legacyKey in const ['categoria', 'category_id', 'cat']) {
      if (query.containsKey(legacyKey) && !query.containsKey('category')) {
        query['category'] = query[legacyKey]!;
      }
      query.remove(legacyKey);
    }
    query.removeWhere((_, value) => value.trim().isEmpty);
    return Uri(
      path: path.isEmpty ? '/' : path,
      queryParameters: query.isEmpty ? null : query,
      fragment: uri.hasFragment ? uri.fragment : null,
    ).toString();
  }

  /// Builds the tenant-owned HTTP origin set consumed by renderers, click
  /// guards, and destination audits.
  ///
  /// Callers remain responsible for supplying only origins that belong to the
  /// active tenant. Keeping parsing and de-duplication here prevents each
  /// consumer from interpreting configured domains differently.
  static List<Uri> resolveInternalOrigins({
    Iterable<String> configuredUrls = const <String>[],
    Iterable<String> ownedHosts = const <String>[],
    Uri? currentUri,
  }) {
    final origins = <Uri>[];
    final seen = <String>{};

    void add(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return;
      final uri = Uri.tryParse(
        value.contains('://') ? value : 'https://$value',
      );
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        return;
      }
      final hasCustomPort = uri.hasPort && uri.port != 80 && uri.port != 443;
      final key = '${uri.host.toLowerCase()}:'
          '${hasCustomPort ? uri.port : 'web'}';
      if (seen.add(key)) origins.add(uri);
    }

    for (final url in configuredUrls) {
      add(url);
    }
    for (final host in ownedHosts) {
      add(host);
    }
    if (currentUri != null) {
      add(currentUri.toString());
    }
    return List<Uri>.unmodifiable(origins);
  }

  static bool _sameHttpOrigin(Uri candidate, Uri origin) {
    final candidateScheme = candidate.scheme.toLowerCase();
    final originScheme = origin.scheme.toLowerCase();
    if ((candidateScheme != 'http' && candidateScheme != 'https') ||
        (originScheme != 'http' && originScheme != 'https')) {
      return false;
    }
    String normalizedHost(String host) {
      final value = host.toLowerCase();
      return value.startsWith('www.') ? value.substring(4) : value;
    }

    if (normalizedHost(candidate.host) != normalizedHost(origin.host)) {
      return false;
    }

    final candidateHasCustomPort =
        candidate.hasPort && candidate.port != 80 && candidate.port != 443;
    final originHasCustomPort =
        origin.hasPort && origin.port != 80 && origin.port != 443;
    if (candidateHasCustomPort || originHasCustomPort) {
      return candidate.port == origin.port;
    }

    // HTTP is an owned-but-insecure alias of the HTTPS storefront. Treating
    // it as internal lets the shared navigation layer upgrade/guard the
    // destination instead of launching an unchecked external collection.
    return true;
  }

  static String routeForPage({
    required String slug,
    required bool isHome,
  }) {
    if (isHome) return '/';
    final normalizedSlug = slug.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    if (normalizedSlug.isEmpty) return '/';
    const directSlugs = {
      'productos',
      'servicios',
      'contacto',
      'carrito',
      'checkout',
      'cuenta',
      'nosotros',
      'terminos',
      'privacidad',
      'devoluciones',
      'envios',
    };
    return directSlugs.contains(normalizedSlug)
        ? '/$normalizedSlug'
        : '/pagina/$normalizedSlug';
  }

  /// Builds the same catalog-filter href produced by the editor's destination
  /// control. Category and search are combined with AND semantics by the
  /// public catalog, so this can represent campaigns such as Tires + Maxxis.
  static String routeForCatalog({
    String? categoryId,
    String? categorySlug,
    String? searchQuery,
    String? productType,
    WebsiteCatalogQuery? catalogQuery,
  }) {
    final category = categoryId?.trim() ?? '';
    final slug = websiteCategorySlug(categorySlug ?? '');
    final legacyType = WebsiteCatalogProductTypeFilterX.tryParse(productType);
    if (catalogQuery == null &&
        productType != null &&
        productType.trim().isNotEmpty &&
        legacyType == null) {
      throw ArgumentError.value(
        productType,
        'productType',
        'Tipo de catálogo no compatible.',
      );
    }
    final effectiveQuery = catalogQuery ??
        WebsiteCatalogQuery(
          searchQuery: searchQuery ?? '',
          productType: legacyType,
        );
    final query = <String, String>{};
    if (category.isNotEmpty && slug.isEmpty) query['category'] = category;
    query.addAll(effectiveQuery.toQueryParameters());
    final services =
        effectiveQuery.productType == WebsiteCatalogProductTypeFilter.service;
    final root = services ? '/servicios' : '/productos';
    return Uri(
      path: slug.isEmpty ? root : '$root/categoria/$slug',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  static NavLinkType navigationTypeForHref(String href) {
    return switch (parse(href).kind) {
      WebsiteDestinationKind.external => NavLinkType.external,
      WebsiteDestinationKind.anchor => NavLinkType.anchor,
      WebsiteDestinationKind.category => NavLinkType.category,
      _ => NavLinkType.page,
    };
  }

  static List<String> pathSegments(String path) {
    return path.split('/').where((segment) => segment.isNotEmpty).toList();
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
