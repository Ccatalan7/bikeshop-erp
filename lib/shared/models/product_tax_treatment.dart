enum ProductTaxTreatment {
  taxable19,
  exempt,
}

extension ProductTaxTreatmentPresentation on ProductTaxTreatment {
  String get label => switch (this) {
        ProductTaxTreatment.taxable19 => 'Afecto a IVA · 19%',
        ProductTaxTreatment.exempt => 'Exento · 0%',
      };

  String get description => switch (this) {
        ProductTaxTreatment.taxable19 =>
          'La venta aplica la tasa general de IVA del 19%.',
        ProductTaxTreatment.exempt =>
          'La venta se registra sin IVA por su condición exenta.',
      };

  double get normalizedRate => switch (this) {
        ProductTaxTreatment.taxable19 => 0.19,
        ProductTaxTreatment.exempt => 0.0,
      };
}

/// Resolves the two supported catalog classifications without inventing a
/// default. Historical rows may contain the affected rate as either 0.19 or
/// 19; both normalize to 0.19 when the product is saved again.
ProductTaxTreatment? productTaxTreatmentFromStoredRate(Object? rawRate) {
  final value = switch (rawRate) {
    num number => number.toDouble(),
    String text => double.tryParse(text.trim().replaceAll(',', '.')),
    _ => null,
  };
  if (value == null || !value.isFinite) return null;

  const tolerance = 0.000001;
  if (value.abs() <= tolerance) return ProductTaxTreatment.exempt;
  if ((value - 0.19).abs() <= tolerance || (value - 19).abs() <= tolerance) {
    return ProductTaxTreatment.taxable19;
  }
  return null;
}

double? normalizeProductTaxRate(Object? rawRate) =>
    productTaxTreatmentFromStoredRate(rawRate)?.normalizedRate;

bool hasSupportedProductTaxRate(Object? rawRate) =>
    productTaxTreatmentFromStoredRate(rawRate) != null;
