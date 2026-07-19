import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/product_tax_treatment.dart';

void main() {
  group('product tax treatment', () {
    test('hydrates both historical affected representations', () {
      expect(
        productTaxTreatmentFromStoredRate(0.19),
        ProductTaxTreatment.taxable19,
      );
      expect(
        productTaxTreatmentFromStoredRate(19),
        ProductTaxTreatment.taxable19,
      );
      expect(
        productTaxTreatmentFromStoredRate('19'),
        ProductTaxTreatment.taxable19,
      );
      expect(normalizeProductTaxRate(19), 0.19);
    });

    test('preserves explicit exempt classification', () {
      expect(
        productTaxTreatmentFromStoredRate(0),
        ProductTaxTreatment.exempt,
      );
      expect(normalizeProductTaxRate(0), 0.0);
    });

    test('never invents a classification', () {
      expect(productTaxTreatmentFromStoredRate(null), isNull);
      expect(productTaxTreatmentFromStoredRate(0.2), isNull);
      expect(productTaxTreatmentFromStoredRate(19.5), isNull);
      expect(productTaxTreatmentFromStoredRate(''), isNull);
      expect(hasSupportedProductTaxRate(null), isFalse);
    });
  });
}
