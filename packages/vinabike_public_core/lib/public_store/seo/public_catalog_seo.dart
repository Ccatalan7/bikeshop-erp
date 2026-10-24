/// Title and description of the catalog roots (`/productos`, `/servicios`)
/// and of a category page.
///
/// One owner for both renderers of those pages: the SEO generator wrote them
/// into the snapshots Google indexed until 2026-10-05, and the HTML storefront
/// serves the same words from then on, so moving the pages changes no title.
library;

import '../../modules/website/models/website_catalog_presentation.dart';
import '../../shared/utils/chilean_utils.dart';

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

/// Without the editor's words, `/productos` says what is sold, where, and
/// how it reaches the customer (both ways the checkout offers). Until
/// 2026-10-08: «Catálogo de productos publicados por Viñabike con precios
/// informados en CLP.».
String publicCatalogSeoDescription({
  required WebsiteCatalogPresentation presentation,
  required String storeName,
  String storeLocality = '',
}) {
  if (presentation.seoDescription.trim().isNotEmpty) {
    return presentation.seoDescription.trim();
  }
  final locality = cleanPublicSeoText(storeLocality);
  return cleanPublicSeoText(
    'Repuestos y accesorios para bicicleta en $storeName'
    '${locality.isEmpty ? '' : ', $locality'}, con precio y stock al día. '
    'Retiro en tienda sin costo o despacho a domicilio.',
  );
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

/// The catalog's own figures a category's Google texts may name with a
/// placeholder, so a price written there is never older than the page
/// (2026-10-23: the guides' «Desde $24.990» had to be checked by hand).
class PublicCatalogTextFacts {
  const PublicCatalogTextFacts({
    this.count,
    this.priceFrom,
    this.priceTo,
    this.brands = const [],
  });

  /// How many products the page lists.
  final int? count;

  /// The lowest and highest price among them.
  final double? priceFrom;
  final double? priceTo;

  /// Their brands, the one with most products first.
  final List<String> brands;
}

/// The placeholders, as the editor offers them.
const publicCatalogTextTokens = <String, String>{
  '{cantidad}': 'cuántos productos lista',
  '{desde}': 'el precio más bajo',
  '{hasta}': 'el precio más alto',
  '{marcas}': 'sus tres marcas con más productos',
};

final RegExp _catalogTextToken = RegExp(r'\{(cantidad|desde|hasta|marcas)\}');

/// Whether [text] names one of [publicCatalogTextTokens].
bool hasPublicCatalogTextTokens(String text) =>
    _catalogTextToken.hasMatch(text);

/// [text] with its placeholders replaced by [facts], or null when one of
/// them has no figure (the catalog's counts did not answer, or it has no
/// brand): then the page says its formula rather than a sentence with a
/// hole.
String? resolvePublicCatalogText(String text, PublicCatalogTextFacts facts) {
  String? valueOf(String token) => switch (token) {
    'cantidad' =>
      facts.count == null || facts.count! <= 0 ? null : '${facts.count}',
    'desde' =>
      facts.priceFrom == null || facts.priceFrom! <= 0
          ? null
          : ChileanUtils.formatCurrency(facts.priceFrom!),
    'hasta' =>
      facts.priceTo == null || facts.priceTo! <= 0
          ? null
          : ChileanUtils.formatCurrency(facts.priceTo!),
    'marcas' => facts.brands.isEmpty ? null : _humanList(facts.brands.take(3)),
    _ => null,
  };
  var missing = false;
  final resolved = text.replaceAllMapped(_catalogTextToken, (match) {
    final value = valueOf(match.group(1)!);
    if (value == null) missing = true;
    return value ?? '';
  });
  return missing ? null : cleanPublicSeoText(resolved);
}

/// The editor's [text] for Google with its placeholders filled, or an empty
/// string (the formula's turn) when it has none or one cannot be filled.
String publicCatalogEditorText(String text, PublicCatalogTextFacts facts) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';
  if (!hasPublicCatalogTextTokens(trimmed)) return trimmed;
  return resolvePublicCatalogText(trimmed, facts) ?? '';
}

/// «Kenda, Maxxis y Chaoyang».
String _humanList(Iterable<String> items) {
  final list = [
    for (final item in items)
      if (cleanPublicSeoText(item) case final clean when clean.isNotEmpty)
        clean,
  ];
  if (list.length <= 1) return list.join();
  return '${list.sublist(0, list.length - 1).join(', ')} y ${list.last}';
}

/// What a category's page for one of its measures or brands is called:
/// the editor's title, or the category and the filter («Cámaras aro 26»,
/// «Neumáticos Kenda»: a brand keeps its capital).
String publicCategoryLandingDisplayTitle({
  required WebsiteCatalogLanding landing,
  required String categoryTitle,
}) {
  if (landing.heroTitle.isNotEmpty) return landing.heroTitle;
  final label = landing.label;
  final shown = label.isEmpty || landing.brandIds.isNotEmpty
      ? label
      : '${label[0].toLowerCase()}${label.substring(1)}';
  return cleanPublicSeoText('$categoryTitle $shown');
}
