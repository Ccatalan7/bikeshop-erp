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
///
/// Without one, the title says what people search for and where:
/// «Neumáticos para bicicleta | Viñabike Viña del Mar». Until 2026-10-08 it
/// was «Neumáticos | Viñabike», which matches neither the bicycle nor the
/// city a local search names.
String publicCategorySeoTitle({
  required String seoTitle,
  required String displayTitle,
  required String storeName,
  String storeLocality = '',
  bool services = false,
}) {
  if (seoTitle.trim().isNotEmpty) return seoTitle.trim();
  final subject = publicCategorySearchSubject(displayTitle, services: services);
  final store = cleanPublicSeoText(
    '$storeName ${cleanPublicSeoText(storeLocality)}',
  );
  return store.isEmpty ? subject : '$subject | $store';
}

/// «Neumáticos para bicicleta», or «Mantenciones de bicicleta» for a group
/// of workshop [services]: the category's name with what it is for, unless
/// the name already says it («Bicicletas urbanas»).
String publicCategorySearchSubject(
  String displayTitle, {
  bool services = false,
}) {
  final title = cleanPublicSeoText(displayTitle);
  if (title.isEmpty) return title;
  if (RegExp(r'bici', caseSensitive: false).hasMatch(title)) return title;
  return services ? '$title de bicicleta' : '$title para bicicleta';
}

/// [seoDescription] is the editor's SEO description for the category, if any.
String publicCategorySeoDescription({
  required String seoDescription,
  required String intro,
  required int productCount,
  required String displayTitle,
  required String storeName,
  String storeLocality = '',
  bool services = false,
}) {
  if (seoDescription.trim().isNotEmpty) return seoDescription.trim();
  if (intro.isNotEmpty) return intro;

  // A factual fallback projected from canonical owners. It deliberately does
  // not infer technical attributes or buying claims from product titles.
  final store = cleanPublicSeoText(storeName);
  final locality = cleanPublicSeoText(storeLocality);
  final subject = publicCategorySearchSubject(displayTitle, services: services);
  final one = productCount == 1;
  final items = services
      ? '${one ? 'servicio' : 'servicios'} con precio publicado'
      : '${one ? 'producto' : 'productos'} con precio y stock al día';
  return cleanPublicSeoText(
    '$subject${store.isEmpty ? '' : ' en $store'}'
    '${locality.isEmpty ? '' : ', $locality'}: $productCount $items.',
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
