import '../../modules/website/models/website_catalog_presentation.dart';
import '../../modules/website/models/website_destination.dart';
import '../../modules/website/models/website_page_models.dart';

/// The catalog presentation a menu row shows in the wide menu — its section
/// photo, veils, overview width and text alignment from «Catálogo web» — or
/// `null` when the row does not link to a category with one. The category is
/// read from the link by id, else by slug.
///
/// One owner for the Flutter `MegaMenuButton` and the HTML store's wide menu,
/// so both show the same photo for the same row.
WebsiteCatalogPresentation? megaMenuPresentationOf(
  WebsiteNavigation item,
  WebsiteCatalogPresentationRegistry registry,
) {
  final destination = WebsiteDestination.parse(item.href ?? '');
  if (destination.kind != WebsiteDestinationKind.category) return null;
  final reference = destination.reference?.trim() ?? '';
  if (reference.isEmpty) return null;
  return registry.forCategory(reference) ??
      registry.resolveSlug(reference)?.presentation;
}
