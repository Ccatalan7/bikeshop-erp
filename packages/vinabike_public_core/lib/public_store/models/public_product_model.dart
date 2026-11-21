/// A model: products that are sizes or colors of the same thing, sold as one
/// page with a selector (20261120230000). The owner, seeing the four sizes of
/// a knee pad listed as four products: «¿no deberíamos generar variantes en
/// una sola publicación?».
///
/// Each variant stays its own product (stock, SKU, price, lead time, page).
/// The model says what changes between them (its axes, «Color» and «Talla»,
/// with their values in order) and each variant which one it is (its
/// options). The ERP keeps it (`product_model_save_v1`); the store reads it
/// with `p_group_models`.
library;

/// One axis of a model and its values, in the order they show.
class PublicModelAxis {
  const PublicModelAxis({required this.name, required this.values});

  final String name;
  final List<String> values;

  static List<PublicModelAxis> listOf(Object? json) => [
    if (json is List)
      for (final axis in json)
        if (axis is Map && _text(axis['name']) != null)
          PublicModelAxis(
            name: _text(axis['name'])!,
            values: [
              if (axis['values'] is List)
                for (final value in axis['values'] as List) ?_text(value),
            ],
          ),
  ];
}

/// How many values of an axis a model shows: «3» tallas.
typedef PublicModelAxisCount = ({String name, int count});

/// A listing card's model: one card for the model, «2 colores · 3 tallas»,
/// «Desde $X» when the prices differ. Read from the row's `model_id`,
/// `model_name` and `model_summary` (`get_public_products_faceted_v2` with
/// `p_group_models`, or a related product of the page).
class PublicProductModelSummary {
  const PublicProductModelSummary({
    required this.id,
    required this.name,
    required this.variants,
    required this.axes,
    this.priceMin,
    this.priceMax,
  });

  /// Null when the row is not a grouped model (or shows a single variant).
  static PublicProductModelSummary? fromRow(Map<Object?, Object?> row) {
    final id = _text(row['model_id']);
    final summary = row['model_summary'];
    if (id == null || summary is! Map) return null;
    final variants = _int(summary['variants']) ?? 0;
    if (variants < 2) return null;
    return PublicProductModelSummary(
      id: id,
      name: _text(row['model_name']) ?? '',
      variants: variants,
      axes: [
        if (summary['axes'] is List)
          for (final axis in summary['axes'] as List)
            if (axis is Map && _text(axis['name']) != null)
              (name: _text(axis['name'])!, count: _int(axis['count']) ?? 0),
      ],
      priceMin: _double(summary['priceMin']),
      priceMax: _double(summary['priceMax']),
    );
  }

  final String id;
  final String name;
  final int variants;
  final List<PublicModelAxisCount> axes;
  final double? priceMin;
  final double? priceMax;

  /// «2 colores · 3 tallas»; empty when no axis varies.
  String get label => productModelAxesLabel(axes);

  /// Whether the variants cost different amounts: the card says «Desde».
  bool get pricesVary =>
      priceMin != null && priceMax != null && priceMax! > priceMin!;
}

/// The page's model: its axes and its variants, each one shaped like a store
/// product row (the read of `get_public_products` without its cost, with the
/// web fields) plus its `options`, so the store judges stock, lead time and
/// price for each one with the same rule as for the page itself.
class PublicProductModel {
  const PublicProductModel({
    required this.id,
    required this.name,
    required this.axes,
    required this.variants,
  });

  /// Null unless the read carries a model with two variants or more.
  static PublicProductModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    if (id == null) return null;
    final axes = PublicModelAxis.listOf(json['axes']);
    final variants = <Map<String, dynamic>>[
      if (json['variants'] is List)
        for (final row in json['variants'] as List)
          if (row is Map && _text(row['id']) != null)
            Map<String, dynamic>.from(row),
    ];
    if (axes.isEmpty || variants.length < 2) return null;
    return PublicProductModel(
      id: id,
      name: _text(json['name']) ?? '',
      axes: axes,
      variants: variants,
    );
  }

  final String id;
  final String name;
  final List<PublicModelAxis> axes;
  final List<Map<String, dynamic>> variants;

  /// A variant's options, `{"Color": "Negra", "Talla": "XXL"}`.
  static Map<String, String> optionsOf(Map<Object?, Object?> variant) => {
    if (variant['options'] is Map)
      for (final entry in (variant['options'] as Map).entries)
        if (_text(entry.value) != null) '${entry.key}': _text(entry.value)!,
  };

  /// The variant with this id, or null.
  Map<String, dynamic>? variantById(String id) {
    for (final variant in variants) {
      if (variant['id']?.toString() == id) return variant;
    }
    return null;
  }

  /// The variant a visitor lands on choosing [value] of [axis] while looking
  /// at [current]: the one that keeps most of the current choices («Negra»
  /// from «Blanco/Negro S/M» goes to «Negra S/M» if it exists), and among
  /// those, one that can be bought ([available]) before one that cannot.
  /// Null when no variant has that value.
  Map<String, dynamic>? variantFor(
    Map<String, String> current,
    String axis,
    String value, {
    bool Function(Map<String, dynamic> variant)? available,
  }) {
    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final variant in variants) {
      final options = optionsOf(variant);
      if (options[axis] != value) continue;
      var score = 0;
      for (final other in axes) {
        if (other.name == axis) continue;
        if (options[other.name] != null &&
            options[other.name] == current[other.name]) {
          score += 10;
        }
      }
      if (available?.call(variant) ?? false) score += 1;
      if (score > bestScore) {
        best = variant;
        bestScore = score;
      }
    }
    return best;
  }

  /// The variant that is exactly [current] with [axis] set to [value], or
  /// null when that combination does not exist: a size that does not come
  /// in the current color is shown crossed out, not as a link to another
  /// color.
  Map<String, dynamic>? exactVariant(
    Map<String, String> current,
    String axis,
    String value,
  ) {
    final wanted = {...current, axis: value};
    for (final variant in variants) {
      final options = optionsOf(variant);
      var same = true;
      for (final other in axes) {
        if (options[other.name] != wanted[other.name]) {
          same = false;
          break;
        }
      }
      if (same) return variant;
    }
    return null;
  }

  /// The axes whose values the visitor chooses: those that vary.
  List<PublicModelAxis> get choosableAxes => [
    for (final axis in axes)
      if (variants.map((v) => optionsOf(v)[axis.name]).toSet().length > 1) axis,
  ];
}

/// The word for [count] values of an axis: «colores», «talla», «medidas».
String productModelAxisWord(String axis, int count) {
  final word = axis.trim().toLowerCase();
  if (count == 1) return word;
  return switch (word) {
    'color' => 'colores',
    'talla' => 'tallas',
    'medida' => 'medidas',
    'largo' => 'largos',
    'diámetro' => 'diámetros',
    'tamaño' => 'tamaños',
    _ when word.isEmpty => word,
    _ when RegExp(r'[aeiouáéíóú]$').hasMatch(word) => '${word}s',
    _ when word.endsWith('z') => '${word.substring(0, word.length - 1)}ces',
    _ => '${word}es',
  };
}

/// «2 colores · 3 tallas»: each axis that varies, in the model's order.
String productModelAxesLabel(Iterable<PublicModelAxisCount> axes) => [
  for (final axis in axes)
    if (axis.count > 1)
      '${axis.count} ${productModelAxisWord(axis.name, axis.count)}',
].join(' · ');

String? _text(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('${value ?? ''}');

double? _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
