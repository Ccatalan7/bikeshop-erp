/// Title and description of the catalog roots (`/productos`, `/servicios`)
/// and of a category page.
///
/// One owner for both renderers of those pages: the SEO generator wrote them
/// into the snapshots Google indexed until 2026-10-05, and the HTML storefront
/// serves the same words from then on, so moving the pages changes no title.
library;

import '../../modules/website/models/website_catalog_presentation.dart';

/// HTML stripped and whitespace collapsed, as meta text needs it.
String cleanPublicSeoText(String text) => text
    .replaceAll(RegExp(r'<[^>]+>'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The name a category page shows: the editor's hero title, or the
/// category's own name.
String publicCategoryDisplayTitle(
  WebsiteCatalogPresentation presentation,
  String categoryName,
) {
  final hero = presentation.heroTitle.trim();
  return hero.isNotEmpty ? hero : cleanPublicSeoText(categoryName);
}

/// The text a category page introduces itself with: the editor's hero
/// description, or the category's own description.
String publicCategoryIntro(
  WebsiteCatalogPresentation presentation,
  String categoryDescription,
) {
  final hero = presentation.heroDescription.trim();
  return hero.isNotEmpty ? hero : cleanPublicSeoText(categoryDescription);
}

/// [seoTitle] is the editor's SEO title for the category, if any.
String publicCategorySeoTitle({
  required String seoTitle,
  required String displayTitle,
  required String storeName,
}) {
  if (seoTitle.trim().isNotEmpty) return seoTitle.trim();
  final cleanStoreName = cleanPublicSeoText(storeName);
  return cleanStoreName.isEmpty
      ? displayTitle
      : '$displayTitle | $cleanStoreName';
}

/// [seoDescription] is the editor's SEO description for the category, if any.
String publicCategorySeoDescription({
  required String seoDescription,
  required String intro,
  required int productCount,
  required String displayTitle,
  required String storeName,
}) {
  if (seoDescription.trim().isNotEmpty) return seoDescription.trim();
  if (intro.isNotEmpty) return intro;

  // A factual fallback projected from canonical owners. It deliberately does
  // not infer technical attributes or buying claims from product titles.
  return cleanPublicSeoText(
    '$productCount productos publicados en '
    '$displayTitle${storeName.trim().isEmpty ? '' : ' de $storeName'}.',
  );
}

String publicCatalogSeoTitle({
  required WebsiteCatalogPresentation presentation,
  required String storeName,
  required String storeLocality,
}) {
  if (presentation.seoTitle.trim().isNotEmpty) {
    return presentation.seoTitle.trim();
  }
  return 'Productos para bicicletas | $storeName'
      '${storeLocality.isEmpty ? '' : ' $storeLocality'}';
}

String publicCatalogSeoDescription({
  required WebsiteCatalogPresentation presentation,
  required String storeName,
}) {
  if (presentation.seoDescription.trim().isNotEmpty) {
    return presentation.seoDescription.trim();
  }
  return 'Catálogo de productos publicados por $storeName con precios '
      'informados en CLP.';
}

/// `/servicios`: the workshop's services and their prices.
String publicServicesCatalogSeoTitle({
  required WebsiteCatalogPresentation presentation,
  required String storeName,
  required String storeLocality,
}) {
  if (presentation.seoTitle.trim().isNotEmpty) {
    return presentation.seoTitle.trim();
  }
  final locality = cleanPublicSeoText(storeLocality);
  return 'Servicios y precios del taller de bicicletas | $storeName'
      '${locality.isEmpty ? '' : ' $locality'}';
}

String publicServicesCatalogSeoDescription({
  required WebsiteCatalogPresentation presentation,
  required String storeName,
  required String storeLocality,
}) {
  if (presentation.seoDescription.trim().isNotEmpty) {
    return presentation.seoDescription.trim();
  }
  final locality = cleanPublicSeoText(storeLocality);
  return 'Mantenciones, ajustes y reparaciones de bicicletas en el taller de '
      '$storeName${locality.isEmpty ? '' : ' en $locality'}, '
      'con precios en CLP.';
}
