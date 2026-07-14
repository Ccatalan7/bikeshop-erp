import 'website_page_models.dart';

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

  static WebsiteDestination parse(String rawHref) {
    final href = normalizeHref(rawHref);
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

  static String normalizeHref(String rawHref) {
    var value = rawHref.trim();
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('#')) {
      return value;
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
    ).toString();
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
    String? searchQuery,
    String? productType,
  }) {
    final query = <String, String>{};
    final category = categoryId?.trim() ?? '';
    final search = searchQuery?.trim() ?? '';
    final type = productType?.trim() ?? '';
    if (category.isNotEmpty) query['category'] = category;
    if (search.isNotEmpty) query['q'] = search;
    if (type.isNotEmpty) query['type'] = type;
    return Uri(
      path: '/productos',
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
