class PublicShippingQuote {
  const PublicShippingQuote({
    required this.deliveryType,
    required this.itemGross,
    required this.shippingGross,
    required this.shippingNet,
    required this.shippingTax,
    required this.taxRate,
    required this.estimatedMinBusinessDays,
    required this.estimatedMaxBusinessDays,
    this.tierId,
  });

  final String deliveryType;
  final int itemGross;
  final int shippingGross;
  final int shippingNet;
  final int shippingTax;
  final int taxRate;
  final int estimatedMinBusinessDays;
  final int estimatedMaxBusinessDays;
  final String? tierId;

  int get orderGross => itemGross + shippingGross;
  bool get isPickup => deliveryType == 'pickup';

  factory PublicShippingQuote.fromRpc(Object? value) {
    if (value is! Map) {
      throw const FormatException('La cotización de despacho no es válida.');
    }
    final map = Map<String, dynamic>.from(value);

    int wholeClp(String key) {
      final raw = map[key];
      final amount = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (amount == null || !amount.isFinite || amount < 0) {
        throw FormatException('La cotización no contiene $key.');
      }
      final rounded = amount.round();
      if ((amount - rounded).abs() > 0.000001) {
        throw FormatException('$key debe estar expresado en pesos completos.');
      }
      return rounded;
    }

    int wholeNumber(String key) {
      final raw = map[key];
      final amount = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (amount == null || !amount.isFinite || amount < 0) {
        throw FormatException('La cotización no contiene $key.');
      }
      final rounded = amount.round();
      if ((amount - rounded).abs() > 0.000001) {
        throw FormatException('$key debe ser un número entero.');
      }
      return rounded;
    }

    final deliveryType = (map['delivery_type'] ?? '').toString();
    if (deliveryType != 'shipping' && deliveryType != 'pickup') {
      throw const FormatException('El tipo de entrega cotizado no es válido.');
    }

    final quote = PublicShippingQuote(
      deliveryType: deliveryType,
      itemGross: wholeClp('item_gross'),
      shippingGross: wholeClp('shipping_gross'),
      shippingNet: wholeClp('shipping_net'),
      shippingTax: wholeClp('shipping_tax'),
      taxRate: wholeNumber('tax_rate'),
      estimatedMinBusinessDays: wholeNumber('estimated_min_business_days'),
      estimatedMaxBusinessDays: wholeNumber('estimated_max_business_days'),
      tierId: map['tier_id']?.toString(),
    );

    if (quote.shippingGross != quote.shippingNet + quote.shippingTax) {
      throw const FormatException('La cotización de despacho no cuadra.');
    }
    if (quote.isPickup && quote.shippingGross != 0) {
      throw const FormatException('El retiro no puede incluir despacho.');
    }
    if (quote.estimatedMaxBusinessDays < quote.estimatedMinBusinessDays) {
      throw const FormatException('El plazo de despacho no es válido.');
    }
    return quote;
  }
}
