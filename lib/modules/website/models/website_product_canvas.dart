import 'package:flutter/foundation.dart';

/// The parts of a product page drawn from the product page template, which
/// the operator selects on the canvas like a page block.
enum WebsiteProductPageSection { buy, sheet, related }

extension WebsiteProductPageSectionX on WebsiteProductPageSection {
  /// What the chip, the list and the inspector call it.
  String get label => switch (this) {
        WebsiteProductPageSection.buy => 'Foto y compra',
        WebsiteProductPageSection.sheet => 'Ficha técnica',
        WebsiteProductPageSection.related => 'Relacionados',
      };
}

/// One selectable section of the product page on the canvas. Its
/// [selectionId] is the reserved value carried by `selectedBlockId`, as the
/// header, the footer and the catalog sections carry theirs:
/// `product-page:<section>`. Every product page draws the same template, so
/// the section does not name a product.
@immutable
class WebsiteProductSectionTarget {
  const WebsiteProductSectionTarget(this.section);

  static const String _prefix = 'product-page:';

  final WebsiteProductPageSection section;

  String get selectionId => '$_prefix${section.name}';

  static WebsiteProductSectionTarget? parse(String? selectionId) {
    if (selectionId == null || !selectionId.startsWith(_prefix)) return null;
    final name = selectionId.substring(_prefix.length);
    for (final section in WebsiteProductPageSection.values) {
      if (section.name == name) return WebsiteProductSectionTarget(section);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is WebsiteProductSectionTarget && other.section == section;

  @override
  int get hashCode => section.hashCode;
}

/// What the product page on the canvas tells the inspector about itself:
/// the product it draws as an example, and what of the template it can show.
/// The product is the catalog's (edited in Inventario); the template is the
/// page's, for every product.
@immutable
class WebsiteProductCanvasContext {
  const WebsiteProductCanvasContext({
    required this.productName,
    required this.technical,
    required this.highlightCount,
    required this.relatedCount,
    required this.hasPromises,
    required this.service,
  });

  /// The product drawn, as its page names it.
  final String productName;

  /// It has technical data: the sheet is «Ficha técnica» and the help card
  /// asks about the customer's bicycle.
  final bool technical;

  /// Key data next to the price, and related products under the sheet.
  final int highlightCount;
  final int relatedCount;

  /// The site has pickup or delivery texts to show under the buy column.
  final bool hasPromises;

  final bool service;

  @override
  bool operator ==(Object other) =>
      other is WebsiteProductCanvasContext &&
      other.productName == productName &&
      other.technical == technical &&
      other.highlightCount == highlightCount &&
      other.relatedCount == relatedCount &&
      other.hasPromises == hasPromises &&
      other.service == service;

  @override
  int get hashCode => Object.hash(
        productName,
        technical,
        highlightCount,
        relatedCount,
        hasPromises,
        service,
      );
}
