import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  test('product form keeps unclassified drafts but fails closed on publication',
      () {
    final source = File(
      'lib/modules/inventory/pages/product_form_page.dart',
    ).readAsStringSync();
    final treatment = File(
      'lib/shared/models/product_tax_treatment.dart',
    ).readAsStringSync();

    expect(source, contains('ProductTaxTreatment? _selectedTaxTreatment;'));
    expect(source, contains('bool _isPublished = false;'));
    expect(
      source,
      contains(
        'if (!_hasTaxClassification && (_isPublished || _isGoogleMerchant))',
      ),
    );
    expect(source, contains('_selectedTaxTreatment?.normalizedRate'));
    expect(source, contains('taxRate: normalizedTaxRate'));
    expect(treatment, contains('Afecto a IVA · 19%'));
    expect(treatment, contains('Exento · 0%'));
    expect(
      source,
      contains('Un borrador despublicado puede quedar sin clasificar.'),
    );
    expect(
      source,
      contains('Google Merchant requiere clasificar IVA 19% o Exento.'),
    );
  });

  test('every Dart publication entry point rejects missing tax classification',
      () {
    final catalog = File(
      'lib/modules/website/pages/product_website_visibility_page.dart',
    ).readAsStringSync();
    final websiteService = readLibrarySource('lib/modules/website/services/website_service.dart');
    final bulkService = File(
      'lib/modules/inventory/services/bulk_product_edit_service.dart',
    ).readAsStringSync();
    final importer = File(
      'lib/modules/inventory/services/product_import_service.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(catalog, contains('price,tax_rate,inventory_qty'));
    expect(catalog, contains('product.hasTaxClassification'));
    expect(
      websiteService,
      contains('_assertTaxClassificationForWebPublication'),
    );
    expect(
        bulkService, contains('hasSupportedProductTaxRate(product.taxRate)'));
    expect(importer, contains("'is_published': false"));
    expect(importer, contains('parsedPublished && taxRate == null'));
    expect(registry, contains('Product tax classification for publication'));
  });
}
