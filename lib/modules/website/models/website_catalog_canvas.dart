import 'package:flutter/foundation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';

/// The parts of a catalog page drawn from its presentation, which the
/// operator selects on the canvas like a page block. [page] is the page
/// itself: its layout and how Google shows it.
/// A category page's [guide] (its text and questions under the products)
/// and its [landings] (its pages for a measure or a brand) since 2026-10-23.
enum WebsiteCatalogSection { page, hero, plans, list, closing, guide, landings }

/// One selectable section of one catalog page.
///
/// Its [selectionId] is the reserved value carried by `selectedBlockId`, as
/// the header and the footer carry theirs: `catalog:<owner>:<section>`, where
/// the owner is the presentation's (`@catalog/services` or a category id).
@immutable
class WebsiteCatalogSectionTarget {
  const WebsiteCatalogSectionTarget(this.ownerId, this.section);

  static const String _prefix = 'catalog:';

  final String ownerId;
  final WebsiteCatalogSection section;

  String get selectionId => '$_prefix$ownerId:${section.name}';

  /// What the chip and the inspector call it.
  String labelFor({String noun = 'servicios'}) => switch (section) {
        WebsiteCatalogSection.page => 'Página',
        WebsiteCatalogSection.hero => 'Portada',
        WebsiteCatalogSection.plans => 'Planes',
        WebsiteCatalogSection.list => 'Todos los $noun',
        WebsiteCatalogSection.closing => 'Cierre',
        WebsiteCatalogSection.guide => 'Guía y preguntas',
        WebsiteCatalogSection.landings => 'Páginas por medida o marca',
      };

  static WebsiteCatalogSectionTarget? parse(String? selectionId) {
    if (selectionId == null || !selectionId.startsWith(_prefix)) return null;
    final rest = selectionId.substring(_prefix.length);
    final split = rest.lastIndexOf(':');
    if (split <= 0) return null;
    final ownerId = rest.substring(0, split);
    final name = rest.substring(split + 1);
    for (final section in WebsiteCatalogSection.values) {
      if (section.name == name) {
        return WebsiteCatalogSectionTarget(ownerId, section);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogSectionTarget &&
      other.ownerId == ownerId &&
      other.section == section;

  @override
  int get hashCode => Object.hash(ownerId, section);
}

/// A category the plans can come from, with how many published items it has.
@immutable
class WebsiteCatalogCanvasCategory {
  const WebsiteCatalogCanvasCategory({
    required this.id,
    required this.name,
    required this.itemCount,
  });

  final String id;
  final String name;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogCanvasCategory &&
      other.id == id &&
      other.name == name &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(id, name, itemCount);
}

/// One value a category's page can be made for: a technical value of its
/// list («Aro 26», 7 products) or one of its brands.
@immutable
class WebsiteCatalogCanvasFilterValue {
  const WebsiteCatalogCanvasFilterValue({
    required this.value,
    required this.label,
    required this.itemCount,
  });

  final String value;
  final String label;
  final int itemCount;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogCanvasFilterValue &&
      other.value == value &&
      other.label == label &&
      other.itemCount == itemCount;

  @override
  int get hashCode => Object.hash(value, label, itemCount);
}

/// A filter of the category's list, with its values: a spec key
/// (`bead_seat_diameter_mm`, «Aro») or, with [brand], the brands.
@immutable
class WebsiteCatalogCanvasFilter {
  const WebsiteCatalogCanvasFilter({
    required this.key,
    required this.label,
    required this.values,
    this.brand = false,
  });

  final String key;
  final String label;
  final List<WebsiteCatalogCanvasFilterValue> values;
  final bool brand;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogCanvasFilter &&
      other.key == key &&
      other.label == label &&
      other.brand == brand &&
      listEquals(other.values, values);

  @override
  int get hashCode => Object.hash(key, label, brand, Object.hashAll(values));
}

/// What the catalog page on the canvas tells the inspector about itself: the
/// presentation as saved (a draft equal to it is no draft), and the catalog
/// data its sections read, which is edited in Inventario and not here.
@immutable
class WebsiteCatalogCanvasContext {
  const WebsiteCatalogCanvasContext({
    required this.saved,
    required this.rootLabel,
    required this.noun,
    required this.itemCount,
    required this.groupCount,
    required this.planCount,
    required this.categories,
    this.ratingSummary,
    this.collection = false,
    this.offersPriceList = false,
    this.template,
    this.categoryPageCount = 0,
    this.filters = const [],
    this.priceFrom,
    this.priceTo,
    this.brandNames = const [],
  });

  final WebsiteCatalogPresentation saved;

  /// «Servicios»: what the page is called in the page picker.
  final String rootLabel;

  /// «servicios».
  final String noun;

  /// Published items listed, in groups, and the plan cards.
  final int itemCount;
  final int groupCount;
  final int planCount;

  /// The categories with published items, in the page's order.
  final List<WebsiteCatalogCanvasCategory> categories;

  /// «4,4 de 5 · 36 reseñas», or null when the store has no rating.
  final String? ratingSummary;

  /// A category's page: its own portada over the product grid. Its texts,
  /// photo and look are this presentation's; its name, description and
  /// products are the category's, edited in Inventario.
  final bool collection;

  /// The page can be laid out as a price list (`/servicios`); every other
  /// catalog page is a grid.
  final bool offersPriceList;

  /// On a category's page, the category template as saved: the look its
  /// portada and grid draw unless the category has its own.
  final WebsiteCatalogPresentation? template;

  /// How many category pages the site publishes (all of them follow the
  /// template unless they have their own look).
  final int categoryPageCount;

  /// On a category's page, the filters of its list a page for a measure or
  /// a brand can be made for, with their values and counts.
  final List<WebsiteCatalogCanvasFilter> filters;

  /// The lowest and highest price of what the page lists, and its brands
  /// (most products first): what `{desde}`, `{hasta}` and `{marcas}` say.
  final double? priceFrom;
  final double? priceTo;
  final List<String> brandNames;

  String get ownerId => saved.ownerId;

  @override
  bool operator ==(Object other) =>
      other is WebsiteCatalogCanvasContext &&
      other.saved.hasSamePersistedValue(saved) &&
      other.rootLabel == rootLabel &&
      other.noun == noun &&
      other.itemCount == itemCount &&
      other.groupCount == groupCount &&
      other.planCount == planCount &&
      listEquals(other.categories, categories) &&
      other.ratingSummary == ratingSummary &&
      other.collection == collection &&
      other.offersPriceList == offersPriceList &&
      (other.template == null) == (template == null) &&
      (template == null || other.template!.hasSamePersistedValue(template!)) &&
      other.categoryPageCount == categoryPageCount &&
      listEquals(other.filters, filters) &&
      other.priceFrom == priceFrom &&
      other.priceTo == priceTo &&
      listEquals(other.brandNames, brandNames);

  @override
  int get hashCode => Object.hash(
        saved.ownerId,
        rootLabel,
        itemCount,
        groupCount,
        planCount,
        Object.hashAll(categories),
        ratingSummary,
        collection,
        offersPriceList,
        categoryPageCount,
        Object.hashAll(filters),
        priceFrom,
        priceTo,
      );
}
