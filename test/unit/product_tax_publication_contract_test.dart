import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  // Since 20261030190000 a product saved without tax carries 19 %: «sin
  // clasificar» waited for a person and hid 87 products from the web.
  test('a new product starts as IVA 19 % and publication still fails closed',
      () {
    final source = File(
      'lib/modules/inventory/pages/product_form_page.dart',
    ).readAsStringSync();
    final treatment = File(
      'lib/shared/models/product_tax_treatment.dart',
    ).readAsStringSync();
    final reader =
        File('lib/shared/widgets/ocr_upload_widget.dart').readAsStringSync();
    final bulkCreate = File(
      'lib/modules/inventory/widgets/bulk_product_create_dialog.dart',
    ).readAsStringSync();
    final baseDefault = File(
      'supabase/migrations/20261030190000_products_default_tax_rate.sql',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'ProductTaxTreatment? _selectedTaxTreatment = ProductTaxTreatment.taxable19;',
      ),
    );
    for (final creator in [reader, bulkCreate]) {
      expect(
        creator,
        contains('taxRate: ProductTaxTreatment.taxable19.normalizedRate'),
      );
    }
    expect(baseDefault, contains('new.tax_rate := 19;'));
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
      contains('Un producto que se guarda sin elegir queda con IVA 19%.'),
    );
    expect(
      source,
      contains('Google Merchant requiere clasificar IVA 19% o Exento.'),
    );
  });

  test('every Dart publication entry point rejects missing tax classification',
      () {
    final catalog = File(
      'lib/modules/website/catalog/catalog_web_models.dart',
    ).readAsStringSync();
    final rule = File(
      'supabase/migrations/20261010010000_catalog_single_sale_rule.sql',
    ).readAsStringSync();
    final websiteService =
        readLibrarySource('lib/modules/website/services/website_service.dart');
    final bulkService = File(
      'lib/modules/inventory/services/bulk_product_edit_service.dart',
    ).readAsStringSync();
    final importer = File(
      'lib/modules/inventory/services/product_import_service.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    // Since 2026-10-10 the store rule itself refuses an unclassified
    // product, and the catalog shows that reason instead of guessing it.
    expect(rule, contains("then 'missing_tax'"));
    expect(catalog, contains('bool get hasTaxClassification'));
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
