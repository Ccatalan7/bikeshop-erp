/// How long a product the store sells on order takes to arrive: the terms
/// «Se vende a pedido» keeps on the ERP's product form
/// (`product_on_order_terms`), as `get_public_on_order_terms_v1` hands them to
/// the site without naming the supplier. Sold out, the page, its card and the
/// search say «A pedido» instead of «Agotado», and Google reads a back order.
class PublicOnOrderLead {
  const PublicOnOrderLead({
    required this.leadDaysMin,
    required this.leadDaysMax,
  });

  /// `{leadDaysMin, leadDaysMax}`, or null when it is not a usable lead.
  static PublicOnOrderLead? fromJson(Object? json) {
    if (json is! Map) return null;
    final min = _days(json['leadDaysMin']);
    final max = _days(json['leadDaysMax']) ?? min;
    if (min == null || max == null || max < min) return null;
    return PublicOnOrderLead(leadDaysMin: min, leadDaysMax: max);
  }

  /// The read's answer, `{<product id>: {leadDaysMin, leadDaysMax}}`, by id.
  static Map<String, PublicOnOrderLead> mapOf(Object? json) => {
    if (json is Map)
      for (final entry in json.entries) '${entry.key}': ?fromJson(entry.value),
  };

  final int leadDaysMin;
  final int leadDaysMax;

  /// «3 a 5 días hábiles», «1 día hábil».
  String get window => leadDaysMin == leadDaysMax
      ? '$leadDaysMin ${leadDaysMin == 1 ? 'día hábil' : 'días hábiles'}'
      : '$leadDaysMin a $leadDaysMax días hábiles';

  /// The page's stock line: «A pedido · llega en 3 a 5 días hábiles».
  String get stockLabel => 'A pedido · llega en $window';

  /// What the row carries once the reads merge it (`on_order`).
  Map<String, int> toJson() => {
    'leadDaysMin': leadDaysMin,
    'leadDaysMax': leadDaysMax,
  };

  static int? _days(Object? value) => switch (value) {
    final num days when days >= 0 && days == days.roundToDouble() =>
      days.toInt(),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PublicOnOrderLead &&
      other.leadDaysMin == leadDaysMin &&
      other.leadDaysMax == leadDaysMax;

  @override
  int get hashCode => Object.hash(leadDaysMin, leadDaysMax);
}
