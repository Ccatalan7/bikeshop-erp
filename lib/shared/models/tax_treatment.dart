/// Tax treatment enum for flexible IVA handling
/// Matches check constraint in database: ('no_tax', 'tax_included')
enum TaxTreatment {
  /// No tax - Full amount is revenue/cost (receipts, international purchases)
  noTax('no_tax'),

  /// Tax included - Amount includes 19% IVA (divide by 1.19 for net)
  taxIncluded('tax_included');

  final String value;
  const TaxTreatment(this.value);

  /// Parse from database string value
  static TaxTreatment fromString(String? value) {
    switch (value) {
      case 'tax_included':
        return TaxTreatment.taxIncluded;
      case 'no_tax':
      default:
        return TaxTreatment.noTax;
    }
  }

  /// Convert to database string value
  String toValue() => value;
}
