part of '../public_store_layout.dart';

/// Runtime routing mode for the public store shell.
///
/// The same store UI is embedded in two different apps:
/// - Standalone public store (`main_store.dart`)
/// - ERP/admin app preview/editor (`main.dart`)
///
/// Route normalization must behave differently between those modes,
/// especially on native platforms where we cannot infer it from the host.
class PublicStoreRuntimeConfig {
  static bool isErpMounted = false;

  /// The single truth for which route space this runtime owns.
  ///
  /// Both entrypoints already declare it: the dedicated store bundle sets
  /// `isErpMounted = false` in `PublicStoreRouter.createRouter`, and the ERP
  /// bundle sets `isErpMounted = !forcePublicStoreHost` in
  /// `AppRouter.createRouter`. Nothing else may re-derive it — a host
  /// allowlist previously duplicated this decision and silently excluded every
  /// custom domain, so a tenant on its own domain received `/tienda/...`
  /// hrefs on a clean storefront.
  static bool get isStandaloneStoreRuntime => !isErpMounted;
}

/// Projects an in-app route into the href space this runtime actually owns.
///
/// Pure by construction: it reads no host, no `Uri.base` and no platform flag,
/// so a custom domain, a preview channel and a local build all behave the same
/// as long as their entrypoint declared `isErpMounted` correctly.
@visibleForTesting
String publicStoreHref(
  String legacyRoute, {
  required bool isErpMounted,
}) {
  final uri = Uri.tryParse(legacyRoute);
  if (uri == null) return legacyRoute;

  var path = uri.path;

  // Normalize relative paths like 'productos' to '/productos'.
  // This avoids odd browser URL behavior on web and keeps routing consistent.
  if (uri.scheme.isEmpty && path.isNotEmpty && !path.startsWith('/')) {
    path = '/$path';
  }

  if (!isErpMounted) {
    // Standalone storefront: clean routes only.
    if (path == '/tienda' || path == '/tienda/') {
      path = '/';
    } else if (path.startsWith('/tienda/')) {
      path = path.substring('/tienda'.length);
      if (path.isEmpty) path = '/';
    }
    return uri.replace(path: path).toString();
  }

  // ERP-mounted: keep policy pages as clean URLs (they are part of the shell).
  const policyPaths = {
    '/nosotros',
    '/terminos',
    '/privacidad',
    '/devoluciones',
    '/envios',
  };
  if (policyPaths.contains(path)) {
    return uri.toString();
  }

  // Preserve explicit legacy routes.
  if (path == '/tienda' || path.startsWith('/tienda/')) {
    return uri.toString();
  }

  // Product links use one clean canonical shape. Mount that same route under
  // `/tienda` inside the ERP so Preview/Edit never hands a canonical product
  // card to an unregistered clean-route branch.
  final normalizedProductHref = normalizePublicCatalogRouteForRuntime(
    uri.replace(path: path).toString(),
    isErpMounted: true,
  );
  if (normalizedProductHref != uri.replace(path: path).toString()) {
    return normalizedProductHref;
  }

  // Never navigate to ERP root.
  if (path.isEmpty || path == '/') {
    return uri.replace(path: '/tienda').toString();
  }

  // Map common clean store routes into the ERP-mounted `/tienda/*` space.
  if (path == '/carrito') path = '/tienda/carrito';
  if (path == '/checkout') path = '/tienda/checkout';
  if (path == '/contacto') path = '/tienda/contacto';

  // Detail and scoped sections.
  if (path.startsWith('/producto/')) path = '/tienda$path';
  if (path.startsWith('/pedido/')) path = '/tienda$path';
  if (path == '/cuenta' || path.startsWith('/cuenta/')) path = '/tienda$path';
  if (path.startsWith('/pagina/')) path = '/tienda$path';

  return uri.replace(path: path).toString();
}

String resolvePublicStoreSystemSeoTitle({
  required String path,
  required String storeName,
}) {
  final normalizedPath = normalizeStorefrontSeoPath(path);
  final normalizedStoreName = storeName.trim();
  if (normalizedPath == '/') return normalizedStoreName;

  final systemLabel = WebsiteDestination.systemRoutes[normalizedPath];
  if (systemLabel == null) return normalizedStoreName;
  if (normalizedStoreName.isEmpty) return systemLabel;
  return '$systemLabel | $normalizedStoreName';
}

/// Projects SEO from the routed page identity, not from a stale ancestor
/// [GoRouterState] that can remain visible while an imperative route is
/// stacked (for example, cart -> deferred checkout).
Uri resolvePublicStoreSeoUri({
  required Uri routerUri,
  String? routePath,
}) {
  final explicitPath = routePath?.trim() ?? '';
  if (explicitPath.isEmpty || explicitPath == routerUri.path) {
    return routerUri;
  }
  return routerUri.replace(path: explicitPath);
}
