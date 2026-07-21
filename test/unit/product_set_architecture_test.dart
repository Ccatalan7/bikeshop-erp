import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product form saves sets only through the aggregate command', () {
    final form = File(
      'lib/modules/inventory/pages/product_form_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/inventory/services/inventory_service.dart',
    ).readAsStringSync();

    expect(form, contains('saveProductSetAggregate('));
    expect(form, contains("parentPayload['expected_updated_at']"));
    expect(form, isNot(contains('_createSetComponentProducts')));
    expect(service, contains("'save_product_set_aggregate'"));
    expect(service, contains("'get_product_set_composition'"));
  });

  test('sales and inventory surfaces consume canonical set projections', () {
    final sales = File(
      'lib/modules/sales/services/sales_service.dart',
    ).readAsStringSync();
    final fullInvoice = File(
      'lib/modules/sales/pages/invoice_form_page.dart',
    ).readAsStringSync();
    final embeddedInvoice = File(
      'lib/modules/sales/widgets/sales_invoice_editor.dart',
    ).readAsStringSync();
    final productPicker = File(
      'lib/shared/widgets/product_autocomplete_field.dart',
    ).readAsStringSync();
    final bulkDialog = File(
      'lib/modules/inventory/widgets/bulk_product_edit_dialog.dart',
    ).readAsStringSync();
    final inventory = File(
      'lib/modules/inventory/pages/product_list_page.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(sales, contains("'preview_product_stock_impact'"));
    expect(fullInvoice, isNot(contains('_showSetComponentSaleBlocked')));
    expect(embeddedInvoice, isNot(contains('_showSetComponentSaleBlocked')));
    expect(productPicker, contains("'Pieza de juego'"));
    expect(bulkDialog, isNot(contains("key: 'is_set'")));
    expect(bulkDialog, isNot(contains("key: 'set_type'")));
    expect(inventory, contains('summarizePhysicalInventory('));
    expect(inventory, contains('_effectiveInventoryQty(product)'));
    expect(registry, contains('## Product Set And Component Surfaces'));
  });

  test('secondary stock surfaces never trust a set header quantity', () {
    final posService =
        File('lib/modules/pos/services/pos_service.dart').readAsStringSync();
    final purchaseList = File(
      'lib/modules/purchases/services/smart_purchase_list_service.dart',
    ).readAsStringSync();
    final importer = File(
      'lib/modules/inventory/services/product_import_service.dart',
    ).readAsStringSync();
    final publicInventory = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();
    final ai = File(
      'lib/modules/ai_assistant/services/ai_service.dart',
    ).readAsStringSync();

    expect(posService, contains('availableStockQuantity'));
    expect(purchaseList, contains('_normalizeItems'));
    expect(purchaseList, contains('product.isSetComponent'));
    expect(purchaseList, contains('product.availableStockQuantity'));
    expect(importer, contains('_rejectStockImportForSetHeader'));
    expect(importer, contains('no se puede importar en la cabecera'));
    expect(publicInventory, contains('_attachSetIdentity'));
    expect(ai, contains('available_stock_quantity'));
  });
}
