/// Where a stored value of the technical sheet came from.
///
/// Of the 4,604 product facts on 2026-10-01 a person wrote one; the rest were
/// read from the product name, taken from the supplier's text, researched,
/// carried over from the previous sheet or deduced. The editor showed them
/// all alike, so «116 eslabones» read from a name looked as certain as a
/// checked datum (owner: «no se ve de dónde salió cada dato»). The server
/// sends `value_sources` in the same snapshot as `values` (20261002110000).
class ProductSpecValueOrigin {
  const ProductSpecValueOrigin({required this.source, this.readingCurrent});

  final String source;

  /// For a name reading: whether the name and the vocabulary it was judged
  /// with are still the current ones. Null for every other source.
  final bool? readingCurrent;

  /// The origins by field key; an older server sends none.
  static Map<String, ProductSpecValueOrigin> fromSnapshot(
      Map<String, dynamic> snapshot) {
    final raw = snapshot['value_sources'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value case {'source': final String source})
          entry.key as String: ProductSpecValueOrigin(
              source: source,
              readingCurrent: (entry.value as Map)['reading_current'] as bool?),
    };
  }

  /// The line under a value while the draft still holds what was stored:
  /// once the operator changes it, the stored origin no longer describes it.
  static String? noteFor(
          ProductSpecValueOrigin? origin, Object? draft, Object? stored) =>
      origin == null || draft == null || !_same(draft, stored)
          ? null
          : origin.note;

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          [for (var i = 0; i < a.length; i++) _same(a[i], b[i])]
              .every((x) => x);
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
    }
    return a == b;
  }

  /// The short line under the value, in the shop's words.
  String get note => switch (source) {
        'name_reading' => readingCurrent == false
            ? 'Leído del nombre del producto; ya no calza con el nombre actual'
            : 'Leído del nombre del producto',
        'supplier_text' => 'Del texto del proveedor',
        'research' => 'De la investigación del catálogo',
        'import' => 'De la ficha anterior',
        'inferred' => 'Deducido de otros datos',
        'catalog' => 'Del catálogo de referencias',
        'mechanic' => 'Escrito a mano',
        _ => 'Origen desconocido',
      };
}
