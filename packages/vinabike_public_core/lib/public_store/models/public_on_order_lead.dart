/// How long a product the store sells with a lead time takes to be ready:
/// the terms «Se vende a pedido» keeps on the ERP's product form
/// (`product_on_order_terms`), as `get_public_sold_out_offers_v1` hands them
/// to the site without naming the supplier, and how many one purchase may
/// take (20261120210000).
///
/// The store never says «a pedido» (owner, 2026-11-20: «No decir
/// directamente que es a pedido, eso ahuyenta mucho a los clientes… es
/// simplemente ponerlo bajo otros plazos de entrega»): sold out but sold
/// this way, the product is bought with the cart like any other and every
/// surface shows only its dispatch time, «Despacho en 3 a 5 días hábiles».
/// Google still reads a back order (`BackOrder`, Merchant `backorder`).
class PublicOnOrderLead {
  const PublicOnOrderLead({
    required this.leadDaysMin,
    required this.leadDaysMax,
    this.maxQuantity,
  });

  /// `{leadDaysMin, leadDaysMax, maxQuantity}`, or null when it is not a
  /// usable lead.
  static PublicOnOrderLead? fromJson(Object? json) {
    if (json is! Map) return null;
    final min = _days(json['leadDaysMin']);
    final max = _days(json['leadDaysMax']) ?? min;
    if (min == null || max == null || max < min) return null;
    final most = _days(json['maxQuantity']);
    return PublicOnOrderLead(
      leadDaysMin: min,
      leadDaysMax: max,
      maxQuantity: most == null || most < 1 ? null : most,
    );
  }

  /// The read's answer, `{<product id>: {leadDaysMin, leadDaysMax}}`, by id.
  static Map<String, PublicOnOrderLead> mapOf(Object? json) => {
    if (json is Map)
      for (final entry in json.entries) '${entry.key}': ?fromJson(entry.value),
  };

  final int leadDaysMin;
  final int leadDaysMax;

  /// The most one purchase may take this way, as the database's rule allows
  /// it now (the supplier's stock less a margin, capped by price); null when
  /// the read did not say, and then the cart does not sell it this way.
  final int? maxQuantity;

  /// Whether the cart may sell it this way at all.
  bool get buyable => (maxQuantity ?? 0) > 0;

  /// «3 a 5 días hábiles», «1 día hábil».
  String get window => leadDaysMin == leadDaysMax
      ? '$leadDaysMin ${leadDaysMin == 1 ? 'día hábil' : 'días hábiles'}'
      : '$leadDaysMin a $leadDaysMax días hábiles';

  /// Every surface's words for it: «Despacho en 3 a 5 días hábiles».
  String get dispatchLabel => 'Despacho en $window';

  /// What the reads merge into the row (`on_order`).
  Map<String, int> toJson() => {
    'leadDaysMin': leadDaysMin,
    'leadDaysMax': leadDaysMax,
    'maxQuantity': ?maxQuantity,
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
      other.leadDaysMax == leadDaysMax &&
      other.maxQuantity == maxQuantity;

  @override
  int get hashCode => Object.hash(leadDaysMin, leadDaysMax, maxQuantity);
}
