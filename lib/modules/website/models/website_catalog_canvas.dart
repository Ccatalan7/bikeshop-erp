import 'package:flutter/foundation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';

/// The parts of a catalog page drawn from its presentation, which the
/// operator selects on the canvas like a page block. [page] is the page
/// itself: its layout and how Google shows it.
enum WebsiteCatalogSection { page, hero, plans, list, closing }

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
      other.offersPriceList == offersPriceList;

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
      );
}
