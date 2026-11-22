import 'website_page_models.dart';

/// A brand as a menu shows it (2026-11-21): its name and its logo, read with
/// the menu. The store's server gets them from `get_public_storefront_shell_v1`
/// (`brands`), the editor from the same columns of `product_brands`; the
/// logo is the one «Inventario › Marcas» keeps.
class WebsiteMenuBrand {
  const WebsiteMenuBrand({
    required this.id,
    required this.name,
    this.logoUrl = '',
  });

  /// `{id, name, logo_url}`, or null without an id.
  static WebsiteMenuBrand? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] ?? '').toString().trim().toLowerCase();
    if (id.isEmpty) return null;
    return WebsiteMenuBrand(
      id: id,
      name: (json['name'] ?? '').toString().trim(),
      logoUrl: (json['logo_url'] ?? '').toString().trim(),
    );
  }

  /// The read's rows by brand id.
  static Map<String, WebsiteMenuBrand> mapOf(Object? rows) {
    final brands = <String, WebsiteMenuBrand>{};
    if (rows is List) {
      for (final row in rows) {
        final brand = fromJson(row);
        if (brand != null) brands[brand.id] = brand;
      }
    }
    return brands;
  }

  final String id;
  final String name;

  /// Empty when the brand has no logo: the menu writes its name instead.
  final String logoUrl;
}

/// The brand an item leads to, when it is a brand item with a brand's id.
String? websiteMenuBrandId(WebsiteNavigation item) {
  if (item.linkType != NavLinkType.brand) return null;
  final id = item.linkValue?.trim().toLowerCase() ?? '';
  return _brandId.hasMatch(id) ? id : null;
}

final _brandId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// What a brand without a logo shows in its place: the first letter of its
/// first two words («Radical Mountain» → «RM», «Shimano» → «S»).
String websiteMenuBrandInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = [
    for (final word in words.take(2)) word.substring(0, 1).toUpperCase(),
  ];
  return letters.isEmpty ? '?' : letters.join();
}

/// A menu whose items are all brands: the wide panel and the phone's level
/// show their logos in a grid instead of a list of names (2026-11-21, the
/// owner: «un buen mega menú de marcas… elegante, que sea bien útil»).
bool websiteMenuShowsBrands(Iterable<WebsiteNavigation> items) =>
    items.isNotEmpty &&
    items.every((item) => item.linkType == NavLinkType.brand);
