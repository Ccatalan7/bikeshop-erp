import '../../shared/models/product.dart';

const int _maxProductSlugLength = 80;

/// Builds the canonical public-store path for a product.
///
/// The readable slug may change with the product name, while the SKU remains
/// the stable lookup key. Products without a SKU retain their UUID route.
String publicProductPath(Product product) {
  return buildPublicProductPath(
    name: product.name,
    sku: product.sku,
    fallbackProductId: product.id,
  );
}

String buildPublicProductPath({
  required String name,
  required String sku,
  String? fallbackProductId,
}) {
  final normalizedSku = sku.trim();
  if (normalizedSku.isEmpty) {
    final fallback = fallbackProductId?.trim() ?? '';
    return fallback.isEmpty ? '/productos' : '/productos/$fallback';
  }

  final slug = productUrlSlug(name);
  final encodedSku = Uri.encodeComponent(normalizedSku);
  return '/productos/$slug/$encodedSku';
}

/// Adapts a canonical product route to the active storefront runtime.
///
/// Public links remain canonically rooted at `/productos`. The ERP mounts the
/// same storefront below `/tienda`, so Preview/Edit navigation needs the
/// mounted route while preserving the exact slug, SKU, query, and fragment.
String normalizePublicProductRouteForRuntime(
  String href, {
  required bool isErpMounted,
}) {
  return _normalizeCatalogRootForRuntime(
    href,
    isErpMounted: isErpMounted,
    roots: const ['productos'],
  );
}

/// Mounts canonical product and service catalog routes under `/tienda` when
/// the storefront is rendered inside the ERP.
String normalizePublicCatalogRouteForRuntime(
  String href, {
  required bool isErpMounted,
}) {
  return _normalizeCatalogRootForRuntime(
    href,
    isErpMounted: isErpMounted,
    roots: const ['productos', 'servicios'],
  );
}

String _normalizeCatalogRootForRuntime(
  String href, {
  required bool isErpMounted,
  required List<String> roots,
}) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.scheme.isNotEmpty) return href;

  var path = uri.path;
  final canonical = roots.any(
    (root) => path == '/$root' || path.startsWith('/$root/'),
  );
  final mounted = roots.any(
    (root) => path == '/tienda/$root' || path.startsWith('/tienda/$root/'),
  );
  if (isErpMounted) {
    if (canonical) {
      path = '/tienda$path';
    }
  } else if (mounted) {
    path = path.substring('/tienda'.length);
  }

  return uri.replace(path: path).toString();
}

String productUrlSlug(String value) {
  var slug = value.trim().toLowerCase();

  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };

  replacements.forEach((character, replacement) {
    slug = slug.replaceAll(character, replacement);
  });

  slug = slug
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  if (slug.length > _maxProductSlugLength) {
    slug = slug
        .substring(0, _maxProductSlugLength)
        .replaceFirst(RegExp(r'-+$'), '');
  }

  return slug.isEmpty ? 'producto' : slug;
}
