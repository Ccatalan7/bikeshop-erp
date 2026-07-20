import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String pageSource;
  late String canonicalServiceSource;
  late String legacyServiceSource;

  setUpAll(() {
    pageSource = File(
      'lib/modules/inventory/pages/product_import_page.dart',
    ).readAsStringSync();
    canonicalServiceSource = File(
      'lib/modules/inventory/services/product_import_service.dart',
    ).readAsStringSync();
    legacyServiceSource = File(
      'lib/shared/services/smart_import_service.dart',
    ).readAsStringSync();
  });

  test('routed product import exposes only the canonical traced action', () {
    expect(pageSource, contains('ProductImportService'));
    expect(pageSource, contains('_importService.importProducts('));
    expect(pageSource, isNot(contains('SmartImportService')));
    expect(pageSource, isNot(contains('_runSmartImport')));
    expect(pageSource, isNot(contains('Importar con Opciones')));
  });

  test('every imported target stock uses the audited database command', () {
    expect(canonicalServiceSource, contains("'apply_product_import_stock'"));
    expect(canonicalServiceSource, contains("..['inventory_qty'] = 0"));
    expect(canonicalServiceSource, contains("..['stock_quantity'] = 0"));
    expect(
      legacyServiceSource,
      contains("tableName.trim().toLowerCase() == 'products'"),
    );
    expect(
      legacyServiceSource,
      contains('La importación de productos usa exclusivamente'),
    );
  });
}
