/// Pure rules behind what the assistant says about an inventory search.
///
/// They live outside the service because each one encodes a statement the
/// operator acts on — how many products exist, how many can be sold today,
/// where a product is — and a statement about stock deserves a test that does
/// not need a database to run.
library;

/// Rows the operator can actually sell from.
///
/// Only rows proven active are retained. Every real row carries the
/// flag by this point — keyword rows read it from the catalog select, semantic
/// rows get it during rehydration — so a missing flag means the row could not
/// be verified at all, which is what a stale vector match looks like when its
/// product no longer exists. Keeping those was how the assistant reported 27
/// products for a search where the inventory screen showed 26.
List<Map<String, dynamic>> filterSellableCatalog(
  List<Map<String, dynamic>> rows,
) {
  return rows.where((row) => row['is_active'] == true).toList();
}

/// Counts rows with sellable stock over whatever set it is given.
///
/// Callers must pass the complete result set, not the truncated sample that
/// gets displayed — see [buildInventorySearchSentence].
int countRowsInStock(
  Iterable<Map<String, dynamic>> rows,
  double Function(Map<String, dynamic> row) stockOf,
) {
  return rows.where((row) => stockOf(row) > 0).length;
}

/// The sentence the operator reads after a search.
///
/// [inStockCount] must be counted over the same set [count] describes. The
/// defect this signature exists to prevent was a ratio built from two
/// different sets: the in-stock figure came from the 15 rows the payload
/// carried while the denominator was the full match count, so a search over 27
/// products announced "3 de 27 con stock" while the inventory screen beside it
/// showed 5 of 26. A null [inStockCount] means the ratio cannot be stated
/// honestly, and then it is not stated at all.
String buildInventorySearchSentence({
  required int count,
  required int? inStockCount,
  required List<String> sampleNames,
  required String? searchTerm,
}) {
  // Checked at runtime, not with an assert: asserts vanish in release, and a
  // release build is exactly where a wrong stock figure would reach the
  // counter and cost a sale. An impossible figure fails the turn instead of
  // being printed.
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'must not be negative');
  }
  if (inStockCount != null && (inStockCount < 0 || inStockCount > count)) {
    throw ArgumentError.value(
      inStockCount,
      'inStockCount',
      'must be counted over the same set as count ($count)',
    );
  }

  final trimmedTerm = searchTerm?.trim();
  final queryLabel = (trimmedTerm == null || trimmedTerm.isEmpty)
      ? 'tu búsqueda'
      : '"$trimmedTerm"';

  final stockSentence = inStockCount == null
      ? ''
      : inStockCount == 0
          ? 'Ahora mismo todos aparecen sin stock. '
          : inStockCount == count
              ? 'Todos aparecen con stock. '
              : '$inStockCount de $count aparecen con stock ahora. ';

  final names = sampleNames
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .take(2)
      .toList();

  final sampleSentence = names.isEmpty
      ? 'Te dejé algunas coincidencias abajo.'
      : names.length == 1
          ? 'La principal coincidencia es ${names.first}.'
          : 'Entre las primeras coincidencias están ${names.first} y '
              '${names[1]}.';

  return 'Encontré $count resultados para $queryLabel. '
      '$stockSentence$sampleSentence';
}

/// The location fragment of a product card, or nothing.
///
/// `warehouse_location` is unpopulated for the entire catalog today, and the
/// card used to print the literal `Ubicación Unknown` on every single result:
/// an English word stating a non-fact, on every card the assistant produced.
String? buildProductLocationFragment(Object? location) {
  final value = location?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return 'Ubicación $value';
}
