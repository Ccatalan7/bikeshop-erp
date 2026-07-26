import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

String _section(
  String source, {
  required String from,
  required String to,
}) {
  final start = source.indexOf(from);
  final end = source.indexOf(to, start + from.length);
  expect(start, greaterThanOrEqualTo(0), reason: 'No se encontró: $from');
  expect(end, greaterThan(start), reason: 'No se encontró después: $to');
  return source.substring(start, end);
}

void main() {
  test(
    'formal receipt detail keeps thumbnails, a flat summary table and '
    'collapsed trace evidence',
    () {
      final source = _read(
        'lib/modules/purchases/widgets/purchase_receipt_detail_view.dart',
      );
      final lineTable = _section(
        source,
        from: 'class _ReceiptLineTable',
        to: 'class _ReceiptResolutionSection',
      );
      final trace = _section(
        source,
        from: 'class _TraceEvidence',
        to: 'class _TraceRow',
      );

      expect(source, contains('class PurchaseReceiptDetailView'));
      expect(lineTable, contains('_ProductThumbnail('));
      expect(lineTable, contains('CachedNetworkImage('));
      expect(lineTable, contains('widget.productImageUrls[line.productId]'));

      for (final header in const [
        "'PRODUCTO'",
        "'PEDIDO'",
        "'RECIBIDO'",
        "'DIFERENCIA'",
        "'MOTIVO / EVIDENCIA'",
      ]) {
        expect(lineTable, contains(header));
      }
      expect(lineTable, isNot(contains('DataTable(')));
      expect(lineTable, isNot(contains('Card(')));
      expect(lineTable, isNot(contains("_TableHeader('DAÑADO'")));
      expect(lineTable, isNot(contains("_TableHeader('RECHAZADO'")));
      expect(lineTable, isNot(contains("_TableHeader('FALTANTE'")));
      expect(lineTable, isNot(contains("_TableHeader('SALDO'")));
      expect(lineTable, contains('Saldo pendiente:'));

      expect(trace, contains('ExpansionTile('));
      expect(
        trace,
        contains("ValueKey('purchase-receipt-trace-disclosure')"),
      );
      expect(trace, contains('initiallyExpanded: false'));
    },
  );

  test('receipt detail page loads and passes product image URLs', () {
    final source = _read(
      'lib/modules/purchases/pages/purchase_receipt_detail_page.dart',
    );

    expect(source, contains('Future<Map<String, String>> _loadProductImages('));
    expect(
      source,
      contains('_receivingService.getProductImageUrls(productIds)'),
    );
    expect(
      source,
      contains('final productImagesFuture = _loadProductImages('),
    );
    expect(source, contains('_productImageUrls = productImageUrls'));
    expect(source, contains('productImageUrls: _productImageUrls'));
  });

  test(
    'resolution picker preserves every outcome and explicit cancellation',
    () {
      final source = _read(
        'lib/modules/purchases/pages/purchase_receipt_detail_page.dart',
      );
      final resolutionFlow = _section(
        source,
        from: 'Future<void> _resolveCase(',
        to: 'Future<PurchaseReceiptResolutionOutcome?> '
            '_selectResolutionOutcome(',
      );
      final picker = _section(
        source,
        from: 'class _ResolutionOutcomePicker',
        to: 'class _ResolutionOutcomeOption',
      );

      expect(resolutionFlow, contains('_selectResolutionOutcome('));
      expect(resolutionFlow, contains('_openCreditNoteResolution('));
      expect(resolutionFlow, contains('_showingLaterDelivery = true'));
      expect(resolutionFlow, contains('_recordDocumentedLoss('));

      for (final outcome in const [
        'PurchaseReceiptResolutionOutcome.creditNote',
        'PurchaseReceiptResolutionOutcome.laterDelivery',
        'PurchaseReceiptResolutionOutcome.documentedLoss',
      ]) {
        expect(picker, contains('onSelected($outcome)'));
      }
      expect(picker, contains('onPressed: onCancel'));
      expect(picker, contains("child: const Text('Cancelar')"));
    },
  );

  test('resolution cases are ordered chronologically before tie-breakers', () {
    final source = _read(
      'lib/modules/purchases/services/purchase_receipt_resolution_service.dart',
    );
    final query = _section(
      source,
      from: "final rawCases = await _client",
      to: 'if (rawCases.isEmpty)',
    );

    final view = query.indexOf('purchase_receipt_resolution_case_view');
    final createdAt = query.indexOf(".order('created_at')");
    final sourceLine = query.indexOf(".order('source_line_index')");
    final kind = query.indexOf(".order('discrepancy_kind')");

    expect(view, greaterThanOrEqualTo(0));
    expect(createdAt, greaterThan(view));
    expect(sourceLine, greaterThan(createdAt));
    expect(kind, greaterThan(sourceLine));
  });
}
