import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/online_order_official_document.dart';
import 'package:vinabike_erp/modules/website/models/order_communication.dart';
import 'package:vinabike_erp/modules/website/services/order_evidence_service.dart';
import 'package:vinabike_erp/modules/website/widgets/order_evidence_section.dart';

void main() {
  testWidgets(
    'shows divided read-only communication and fiscal evidence with safe actions',
    (tester) async {
      final voucher = OnlineOrderOfficialDocument.fromJson({
        'id': 'document-1',
        'order_id': 'order-1',
        'document_kind': 'payment_voucher',
        'provider': 'mercadopago',
        'provider_document_id': 'voucher-42',
        'payment_operation_id': 'mp-payment-42',
        'fiscal_validity': 'voucher_valid_as_boleta',
        'document_type': null,
        'folio': null,
        'amount': 12990,
        'currency': 'CLP',
        'issued_at': '2026-07-18T18:00:00.000Z',
        'artifact_url': 'https://documents.example.test/voucher.pdf',
        'artifact_sha256': List.filled(64, 'a').join(),
        'status': 'approved',
        'recorded_at': '2026-07-18T18:00:02.000Z',
      });
      final communication = OrderCommunication.fromJson({
        'id': 'message-1',
        'order_id': 'order-1',
        'message_kind': 'payment_voucher_available',
        'recipient_email': 'customer@example.test',
        'subject': 'Tu comprobante oficial',
        'delivery_mode': 'send',
        'state': 'delivered',
        'attempt_count': 1,
        'created_at': '2026-07-18T18:01:00.000Z',
        'delivered_at': '2026-07-18T18:01:05.000Z',
      });
      final service = _FakeOrderEvidenceReader(
        OnlineOrderEvidence(
          communications: [communication],
          officialDocuments: [voucher],
        ),
      );
      OnlineOrderOfficialDocument? openedDocument;
      Uri? openedUri;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 720,
                child: OrderEvidenceSection(
                  orderId: 'order-1',
                  salesInvoiceId: 'invoice-1',
                  service: service,
                  onOpenOfficialDocument: (document, uri) {
                    openedDocument = document;
                    openedUri = uri;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DOCUMENTOS'), findsOneWidget);
      expect(
        find.text('Voucher Mercado Pago válido como boleta'),
        findsOneWidget,
      );
      expect(find.text('Venta ERP vinculada'), findsOneWidget);
      expect(find.text('Respaldo interno · no tributario'), findsOneWidget);
      expect(find.text('COMUNICACIONES AL CLIENTE'), findsOneWidget);
      expect(
        find.text('Voucher válido como boleta disponible'),
        findsOneWidget,
      );
      expect(find.text('Entregado'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(Divider), findsWidgets);

      await tester.tap(find.text('Abrir documento'));
      expect(openedDocument, same(voucher));
      expect(openedUri, voucher.verifiedArtifactUri);
    },
  );

  testWidgets('does not expose an open action for unsafe document evidence',
      (tester) async {
    final unsafeDocument = OnlineOrderOfficialDocument.fromJson({
      'id': 'document-2',
      'order_id': 'order-1',
      'document_kind': 'payment_voucher',
      'provider': 'mercadopago',
      'provider_document_id': 'voucher-43',
      'payment_operation_id': 'mp-payment-43',
      'fiscal_validity': 'voucher_valid_as_boleta',
      'document_type': null,
      'folio': null,
      'amount': 12990,
      'currency': 'CLP',
      'issued_at': '2026-07-18T18:00:00.000Z',
      'artifact_url': 'http://documents.example.test/voucher.pdf',
      'artifact_sha256': List.filled(64, 'a').join(),
      'status': 'approved',
      'recorded_at': '2026-07-18T18:00:02.000Z',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: OrderEvidenceSection(
                orderId: 'order-1',
                salesInvoiceId: null,
                service: _FakeOrderEvidenceReader(
                  OnlineOrderEvidence(
                    communications: const [],
                    officialDocuments: [unsafeDocument],
                  ),
                ),
                onOpenOfficialDocument: (_, __) => fail('Unsafe URL opened'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enlace no verificable'), findsOneWidget);
    expect(find.text('Abrir documento'), findsNothing);
  });

  // 2026-10-13: after «Registrar despacho» the open order still listed two
  // emails; the «va en camino» one appeared only after reopening it.
  testWidgets('a step taken with the order open reloads what was sent',
      (tester) async {
    final service = _FakeOrderEvidenceReader(
      const OnlineOrderEvidence(communications: [], officialDocuments: []),
    );
    Widget section(int version) => MaterialApp(
          home: Scaffold(
            body: OrderEvidenceSection(
              orderId: 'order-1',
              orderVersion: version,
              salesInvoiceId: null,
              service: service,
              onOpenOfficialDocument: (_, __) {},
            ),
          ),
        );

    await tester.pumpWidget(section(4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(section(4));
    await tester.pumpAndSettle();
    expect(service.loads, 1);

    await tester.pumpWidget(section(5));
    await tester.pumpAndSettle();
    expect(service.loads, 2);
  });
}

class _FakeOrderEvidenceReader implements OrderEvidenceReader {
  _FakeOrderEvidenceReader(this.evidence);

  final OnlineOrderEvidence evidence;
  int loads = 0;

  @override
  Future<OnlineOrderEvidence> loadForOrder(String orderId) async {
    loads++;
    return evidence;
  }
}
