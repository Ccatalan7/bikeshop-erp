import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';

void main() {
  test('la moneda estructurada sobrevive copyWith', () {
    final invoice = ParsedInvoice(
      invoiceNumber: 'AE010625',
      date: DateTime(2025, 6, 1),
      total: 47135,
      currencyCode: 'CLP',
      rawText: '{}',
    );

    expect(invoice.currencyCode, 'CLP');
    expect(invoice.copyWith(total: 47136).currencyCode, 'CLP');
  });

  test('la línea, variante y clave sobreviven el parser generado y copyWith',
      () {
    final invoice = InvoiceParserService().parseInvoiceFromText('''
FACTURA OCR ALIEXPRESS
ALIEXPRESS MARKETPLACE
IMPORTE
1
2
\$ 4159
\$ 8318
SUBTOTAL
Portabotella ZTTO aluminio (BLACK)
SKU: AE0275
LINE_TITLE: Portabotella ZTTO aluminio
VARIANT: BLACK
VARIANT_KEY: sku:12000039290217159
SOURCE_PURCHASE_QUANTITY: 2
SOURCE_PURCHASE_UNIT_PRICE: 3900.5
RAW_PACK_COUNT: 4
RAW_UNIT_TOKEN: pares
RAW_PACK_EVIDENCE_CONFLICT: true
SOURCE_ORDERS: 8202,8201,8202
PRODUCT_URL: https://www.aliexpress.com/item/1005006010538615.html
TOTAL
\$ 8318
''');

    expect(invoice.lineItems, hasLength(1));
    final item = invoice.lineItems.single;
    expect(item.description, 'Portabotella ZTTO aluminio (BLACK)');
    expect(item.lineTitle, 'Portabotella ZTTO aluminio');
    expect(item.variantLabel, 'BLACK');
    expect(item.variantKey, 'sku:12000039290217159');
    expect(item.sourcePurchaseQuantity, 2);
    expect(item.sourcePurchaseUnitPrice, 3900.5);
    expect(item.quantity, 2);
    expect(item.rawPackCount, 4);
    expect(item.rawUnitToken, 'pares');
    expect(item.rawPackEvidenceConflict, isTrue);
    expect(item.sourceOrderNumbers, ['8201', '8202']);
    expect(item.copyWith(total: 9000).lineTitle, item.lineTitle);
    expect(item.copyWith(total: 9000).variantLabel, item.variantLabel);
    expect(item.copyWith(total: 9000).variantKey, item.variantKey);
    expect(item.copyWith(total: 9000).sourcePurchaseQuantity, 2);
    expect(item.copyWith(total: 9000).sourcePurchaseUnitPrice, 3900.5);
    expect(item.copyWith(total: 9000).rawPackCount, 4);
    expect(item.copyWith(total: 9000).rawUnitToken, 'pares');
    expect(item.copyWith(total: 9000).rawPackEvidenceConflict, isTrue);
    expect(item.copyWith(total: 9000).sourceOrderNumbers, ['8201', '8202']);

    final roundTrip = ParsedLineItem.fromJson(item.toJson());
    expect(roundTrip.description, item.description);
    expect(roundTrip.sourcePurchaseQuantity, 2);
    expect(roundTrip.sourcePurchaseUnitPrice, 3900.5);
    expect(roundTrip.rawPackCount, 4);
    expect(roundTrip.rawUnitToken, 'pares');
    expect(roundTrip.rawPackEvidenceConflict, isTrue);
    expect(roundTrip.sourceOrderNumbers, ['8201', '8202']);
  });

  test('legacy pair metadata is retained only as unresolved raw evidence', () {
    final invoice = InvoiceParserService().parseInvoiceFromText('''
FACTURA OCR ALIEXPRESS
IMPORTE
1
2
\$ 5100
\$ 10200
SUBTOTAL
Pastillas ZTTO MS-01B
SKU: AE0292
SOURCE_PURCHASE_QUANTITY: 2
UNITS_PER_PURCHASE: 4
INVENTORY_UNIT: par
TOTAL
\$ 10200
''');

    expect(invoice.lineItems, hasLength(1));
    final item = invoice.lineItems.single;
    expect(item.sourcePurchaseQuantity, 2);
    expect(item.quantity, 2);
    expect(item.rawPackCount, 4);
    expect(item.rawUnitToken, 'par');
  });

  test('a missing middle amount row does not shift later product totals', () {
    final invoice = InvoiceParserService().parseInvoiceFromText('''
FACTURA OCR ALIEXPRESS
ALIEXPRESS MARKETPLACE
IMPORTE
1
1
\$ 100
\$ 100
3
3
\$ 300
\$ 900
SUBTOTAL
Producto uno
SKU: AE0001
Producto dos
SKU: AE0002
Producto tres
SKU: AE0003
TOTAL
\$ 1000
''');

    expect(invoice.lineItems, hasLength(3));
    expect(invoice.lineItems[0].total, 100);
    expect(invoice.lineItems[1].total, isNull);
    expect(invoice.lineItems[1].unitPrice, isNull);
    expect(invoice.lineItems[2].total, 900);
    expect(invoice.lineItems[2].unitPrice, 300);
  });

  test('los extractores conservan título y variante como campos separados', () {
    final content = File(
      'assets/browser/aliexpress_invoice_content.js',
    ).readAsStringSync();
    final renderer = File(
      'assets/browser/aliexpress_invoice.js',
    ).readAsStringSync();
    final ocr = File(
      'lib/shared/widgets/ocr_upload_widget.dart',
    ).readAsStringSync();

    expect(RegExp(r'\blineTitle\s*:').allMatches(content).length,
        greaterThanOrEqualTo(9));
    expect(content, contains('description: variant ?'));
    expect(content, contains('lineTitle: title'));
    expect(content, contains('variant: context.variant'));
    expect(content, contains('lineTitle: lineTitle || null'));

    expect(renderer, contains('item.lineTitle'));
    expect(renderer, contains('LINE_TITLE:'));
    expect(renderer, contains('VARIANT_KEY:'));
    expect(renderer, contains('SOURCE_ORDERS:'));
    expect(renderer, contains('SOURCE_PURCHASE_UNIT_PRICE:'));
    expect(renderer, contains(r'`${visibleBase} (${selectedVariant})`'));

    expect(ocr, contains("item['lineTitle']?.toString()"));
    expect(ocr, contains('lineTitle: lineTitle'));
    expect(ocr, contains('variantLabel: variantLabel'));
    expect(ocr, contains('variantKey: variantKey'));
    expect(ocr, contains('sourcePurchaseQuantity: sourcePurchaseQuantity'));
    expect(ocr, contains('sourcePurchaseUnitPrice: sourcePurchaseUnitPrice'));
    expect(ocr, contains('rawPackCount: rawPackCount'));
    expect(ocr, contains('rawUnitToken:'));
    expect(ocr, contains('rawPackEvidenceConflict: rawPackEvidenceConflict'));
    expect(ocr, contains('sourceOrderNumbers: sourceOrderNumbers'));
    expect(ocr, contains('final structured = originalItem.lineTitle?.trim()'));
  });
}
