import '../../modules/inventory/models/category_models.dart';

/// Pure breadcrumb-trail derivation for the public product page.
///
/// Extracted from the page so first-frame completeness is testable as
/// behavior: given the category list a catalog visitor already has in memory,
/// the full trail must be derivable synchronously — the breadcrumb paints
/// complete on the first frame instead of morphing from a short crumb into
/// the real path when a network answer lands.
///
/// Returns `null` when [categories] is unavailable so the caller can fall
/// back to an origin fetch; returns an empty trail for a product without a
/// category. The walk is cycle-safe and stops at the first unknown ancestor.
List<Category>? categoryTrailFromCategories(
  List<Category>? categories,
  String? rawCategoryId,
) {
  if (categories == null) return null;
  final categoryId = rawCategoryId?.trim() ?? '';
  if (categoryId.isEmpty) return const [];

  final byId = {
    for (final category in categories)
      if (category.id?.trim().isNotEmpty == true) category.id!.trim(): category,
  };
  final reversedTrail = <Category>[];
  final visited = <String>{};
  var currentId = categoryId;
  while (currentId.isNotEmpty && visited.add(currentId)) {
    final category = byId[currentId];
    if (category == null) break;
    reversedTrail.add(category);
    currentId = category.parentId?.trim() ?? '';
  }
  return List.unmodifiable(reversedTrail.reversed);
}

/// Identity check so an unchanged trail never churns `setState` on the
/// freshness pulse.
bool sameCategoryTrail(List<Category> current, List<Category> next) {
  if (current.length != next.length) return false;
  for (var i = 0; i < current.length; i++) {
    if (current[i].id != next[i].id ||
        current[i].tenantId != next[i].tenantId ||
        current[i].name != next[i].name ||
        current[i].fullPath != next[i].fullPath ||
        current[i].parentId != next[i].parentId ||
        current[i].isActive != next[i].isActive ||
        current[i].showOnWebsite != next[i].showOnWebsite) {
      return false;
    }
  }
  return true;
}

/// Chooses the categories rendered in a product breadcrumb.
///
/// An origin/cache-derived trail carries the authoritative publication flags
/// and is therefore safe to navigate selectively. Product denormalization
/// (`category_id` + `category_name`) is only enough to preserve factual text;
/// it cannot prove that the category is currently a public destination.
/// Consequently the fallback is deliberately `showOnWebsite: false`.
List<Category> productBreadcrumbCategories({
  required List<Category> authoritativeTrail,
  String? fallbackCategoryId,
  String? fallbackCategoryName,
}) {
  if (authoritativeTrail.isNotEmpty) {
    return List<Category>.unmodifiable(authoritativeTrail);
  }
  final categoryId = fallbackCategoryId?.trim() ?? '';
  final categoryName = fallbackCategoryName?.trim() ?? '';
  if (categoryId.isEmpty || categoryName.isEmpty) return const <Category>[];
  return List<Category>.unmodifiable([
    Category(
      id: categoryId,
      tenantId: '',
      name: categoryName,
      fullPath: categoryName,
      showOnWebsite: false,
    ),
  ]);
}
