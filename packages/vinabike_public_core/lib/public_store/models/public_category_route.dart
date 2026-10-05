/// Which published category a catalog route value names
/// (`/productos/categoria/<valor>`, `?category=<valor>`).
///
/// Moved out of the Flutter catalog page (2026-10-05) so the Flutter store and
/// the HTML storefront open the same category for the same URL. The HTML one
/// used the menu resolver instead, which looks at every category: «Cambios»
/// and «Frenos» exist twice (one published, one not) and their pages answered
/// 404 there while Flutter opened them.
library;

import '../../modules/website/models/website_catalog_presentation.dart';

typedef PublicCategoryRouteCandidate = ({
  String id,
  String name,
  String fullPath,
  bool isPublished,
});

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Lowercase, Spanish accents folded, punctuation as single spaces.
String normalizePublicCatalogText(String input) {
  final s = input
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// A published category's id, or null.
///
/// - A UUID names that category, only when it is published.
/// - A slug or alias saved in «Catálogo web» belongs to its category: when
///   that category is not published, or the slug is claimed twice, nothing
///   opens (it never falls through to a similarly named category).
/// - Otherwise the value is matched against the name and full path of the
///   published categories; exactly one match opens, duplicates fail closed.
String? resolvePublishedCategoryRouteValue(
  String raw, {
  required WebsiteCatalogPresentationRegistry presentations,
  required Iterable<PublicCategoryRouteCandidate> categories,
}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final published = {
    for (final category in categories)
      if (category.isPublished) category.id: category,
  };

  if (_uuid.hasMatch(trimmed)) {
    return published.containsKey(trimmed) ? trimmed : null;
  }

  if (presentations.categorySlugClaimCount(trimmed) > 0) {
    final presentation = presentations.forSlug(trimmed);
    return presentation != null &&
            published.containsKey(presentation.categoryId)
        ? presentation.categoryId
        : null;
  }

  final wanted = normalizePublicCatalogText(trimmed);
  if (wanted.isEmpty) return null;
  final slug = websiteCategorySlug(trimmed);
  final matches = <String>{
    for (final category in published.values)
      if (normalizePublicCatalogText(category.name) == wanted ||
          normalizePublicCatalogText(category.fullPath) == wanted ||
          websiteCategorySlug(category.name) == slug ||
          websiteCategorySlug(category.fullPath) == slug)
        category.id,
  };
  return matches.length == 1 ? matches.single : null;
}
