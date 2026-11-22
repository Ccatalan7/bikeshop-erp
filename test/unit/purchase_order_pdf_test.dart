// The order a supplier gets (20261122030000): one drawing in the shared core
// (`buildPurchaseOrderPdf`), used by the purchasing assistant when the
// operator sends it and by the HTML store when the open order leaves by
// itself in the morning, read with the dispatch's one-time code. These are
// the words it states.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/public_store/documents/purchase_order_pdf.dart';

Map<String, Object?> _projection({List<Map<String, Object?>>? lines}) => {
      'order_number': 'PED-202611-48213',
      'issued_at': '2026-11-23T12:30:00+00:00',
      'buyer': {'name': 'Viñabike', 'city': 'Viña del Mar'},
      'supplier': {
        'name': 'MKR Imports',
        'legal_name': 'MKR Importaciones Limitada',
        'rut': '76.000.000-0',
        'contact': 'Álvaro Curín · +56 9 0000 0000',
        'payment_terms': 'net30',
      },
      'lines': lines ??
          [
            {
              'product_id': 'p1',
              'name': 'Neumático Maxxis Ardent 29 x 2.40',
              'brand': 'Maxxis',
              'sku': 'TB00011100',
              'quantity': 2,
              'unit_cost': 21008.4,
            },
            {
              'product_id': 'p2',
              'name': 'Cámara 29 x 2.0/2.5 Presta',
              'sku': null,
              'quantity': 1,
              'unit_cost': 3990,
            },
          ],
      'note': 'Para los pedidos WEB-26-00031 y WEB-26-00034.',
      'storefront': {
        'schemaVersion': 1,
        'displayName': 'Viñabike',
        'legalName': 'NEWEN SpA',
      },
    };

void main() {
  test('the morning order reads with its folio, its supplier and its lines',
      () {
    final order = PurchaseOrderDocument.fromProjection(_projection())!;
    expect(order.isDraft, isFalse);
    expect(order.orderNumber, 'PED-202611-48213');
    expect(order.fileName, 'pedido_PED-202611-48213.pdf');
    // 12:30 UTC on 23 November is 09:30 in Chile: the shop's date.
    expect(order.issuedOn, '23/11/2026');
    expect(order.buyerName, 'Viñabike');
    expect(order.buyerCity, 'Viña del Mar');
    expect(order.supplierName, 'MKR Imports');
    expect(order.supplierLegalName, 'MKR Importaciones Limitada');
    expect(order.supplierContact, 'Álvaro Curín · +56 9 0000 0000');
    expect([
      for (final line in order.lines) line.reference
    ], [
      'Maxxis · SKU TB00011100',
      null,
    ]);
    expect([for (final line in order.lines) line.quantity], ['2', '1']);
    expect(order.unitCount, '3');
    expect(order.note, 'Para los pedidos WEB-26-00031 y WEB-26-00034.');
    // The same totals the assistant shows: net of the lines, 19 % on top.
    expect(order.netTotal, r'$ 46.007');
    expect(order.ivaAmount, r'$ 8.741');
    expect(order.total, r'$ 54.748');
  });

  test('payment terms read as words, not as the sheet code', () {
    final order = PurchaseOrderDocument.fromProjection(_projection())!;
    expect(order.paymentTerms, '30 días');
    expect(PurchaseOrderDocument.paymentTermsLabel('prepaid'), 'Prepago');
    expect(PurchaseOrderDocument.paymentTermsLabel('immediate'), 'Contado');
    expect(
      PurchaseOrderDocument.paymentTermsLabel('Transferencia al despacho'),
      'Transferencia al despacho',
    );
    expect(PurchaseOrderDocument.paymentTermsLabel('  '), isNull);
  });

  test('a supplier whose legal name is its name does not repeat it', () {
    final projection = _projection();
    (projection['supplier'] as Map<String, Object?>)['legal_name'] =
        'mkr imports';
    final order = PurchaseOrderDocument.fromProjection(projection)!;
    expect(order.supplierLegalName, isNull);
  });

  test('an order without lines or folio is not drawn', () {
    expect(
        PurchaseOrderDocument.fromProjection(_projection(lines: [])), isNull);
    final noFolio = _projection()..remove('order_number');
    expect(PurchaseOrderDocument.fromProjection(noFolio), isNull);
    expect(PurchaseOrderDocument.fromProjection('nada'), isNull);
  });

  test('a draft composed in the assistant says it has no number', () {
    final draft = PurchaseOrderDocument.compose(
      orderNumber: null,
      issuedOn: DateTime(2026, 11, 22, 10),
      buyerName: 'Viñabike',
      supplierName: 'RBX',
      lines: const [
        PurchaseOrderDocumentSource(
          productId: 'a',
          name: 'Cámara 26',
          reference: null,
          quantity: 1.5,
          unitCostNet: 1000,
          costIsFromCatalog: true,
        ),
      ],
    );
    expect(draft.isDraft, isTrue);
    expect(draft.orderNumber, 'Sin número');
    expect(draft.fileName, 'pedido_borrador.pdf');
    expect(draft.lines.single.quantity, '1.5');
    expect(draft.unverifiedCostLines, 1);
  });

  test('the store draws it as a PDF with the store fonts and logo', () async {
    final regular = File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync();
    final bold = File('assets/fonts/Barlow-Bold.ttf').readAsBytesSync();
    final logo = File('assets/images/vinabike_logo.webp').readAsBytesSync();
    for (final logoBytes in [logo, null]) {
      final bytes = await buildPurchaseOrderPdf(
        PurchaseOrderDocument.fromProjection(_projection())!,
        regularFont: ByteData.sublistView(regular),
        boldFont: ByteData.sublistView(bold),
        logo: logoBytes,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    }
  });
}
