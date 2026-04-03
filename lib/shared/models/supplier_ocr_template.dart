enum SupplierOcrDiscountParser {
  none,
  anchoredTrailingNumeric,
}

class SupplierOcrTemplate {
  final bool enabled;
  final SupplierOcrDiscountParser discountParser;

  const SupplierOcrTemplate({
    this.enabled = false,
    this.discountParser = SupplierOcrDiscountParser.none,
  });

  bool get usesRawRowDiscountFallback =>
      enabled &&
      discountParser == SupplierOcrDiscountParser.anchoredTrailingNumeric;

  factory SupplierOcrTemplate.fromJson(dynamic json) {
    if (json is! Map) {
      return const SupplierOcrTemplate();
    }

    final map = Map<String, dynamic>.from(json);
    final parserName = map['discount_parser']?.toString();

    return SupplierOcrTemplate(
      enabled: map['enabled'] as bool? ?? false,
      discountParser: SupplierOcrDiscountParser.values.firstWhere(
        (value) => value.name == parserName,
        orElse: () => SupplierOcrDiscountParser.none,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'discount_parser': discountParser.name,
    };
  }

  SupplierOcrTemplate copyWith({
    bool? enabled,
    SupplierOcrDiscountParser? discountParser,
  }) {
    return SupplierOcrTemplate(
      enabled: enabled ?? this.enabled,
      discountParser: discountParser ?? this.discountParser,
    );
  }
}
