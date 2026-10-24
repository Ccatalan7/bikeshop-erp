/// The related products of a product page, ranked by the filterable spec
/// values each one shares with the product (`get_public_related_fit_v1`):
/// the ones that share more first, then the catalog's order; when some
/// share a value, the ones that share none are left out (no 20-inch tyre
/// under a 700 x 23C road tyre). The HTML product page applies the same rule
/// in `get_public_product_page_v2` (20261024010000).
List<T> rankRelatedByFit<T>(
  List<T> candidates, {
  required String Function(T candidate) idOf,
  required Map<String, int> sharedById,
}) {
  final scored = [
    for (var i = 0; i < candidates.length; i++)
      (
        candidate: candidates[i],
        order: i,
        shared: sharedById[idOf(candidates[i])] ?? 0,
      ),
  ];
  final best = scored.fold<int>(
    0,
    (top, row) => row.shared > top ? row.shared : top,
  );
  final kept = scored.where((row) => best == 0 || row.shared > 0).toList()
    ..sort((a, b) {
      final byFit = b.shared.compareTo(a.shared);
      return byFit != 0 ? byFit : a.order.compareTo(b.order);
    });
  return [for (final row in kept) row.candidate];
}
