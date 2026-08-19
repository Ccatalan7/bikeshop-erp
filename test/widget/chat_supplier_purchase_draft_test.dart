import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/services/inventory_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

/// The supplier chat offers the same purchase document the operator would have
/// sent from «Documentos de compra», and offers only the drafts: anything the
/// supplier already received is not a candidate for sending again.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  // The chat keeps a live indicator running, so the tree never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpChat(
    WidgetTester tester, {
    required Conversation conversation,
    required PurchaseService purchaseService,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider()),
          ChangeNotifierProvider<PurchaseService>.value(value: purchaseService),
          ChangeNotifierProvider(create: (_) => AppearanceService()),
          ChangeNotifierProvider(create: (_) => InventoryService()),
        ],
        child: MaterialApp(
          home: Scaffold(body: ChatWindow(conversation: conversation)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'supplier chat offers only the draft purchase documents of that supplier',
    (tester) async {
      final purchaseService = _SupplierDraftsPurchaseService([
        _invoice(id: 'inv-draft', number: '141500'),
        _invoice(
          id: 'inv-sent',
          number: '141498',
          status: PurchaseInvoiceStatus.sent,
        ),
      ]);

      await pumpChat(
        tester,
        conversation: _supplierConversation(),
        purchaseService: purchaseService,
      );

      await tester.tap(find.byTooltip('Agregar al mensaje'));
      await settle(tester);

      expect(find.text('Documento de compra'), findsOneWidget);

      await tester.tap(find.text('Documento de compra'));
      await settle(tester);

      expect(purchaseService.requestedSupplierIds, ['sup-1']);
      expect(find.text('N° 141500'), findsOneWidget);
      expect(find.text('N° 141498'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'choosing a draft leaves the document in the composer, not on the wire',
    (tester) async {
      await pumpChat(
        tester,
        conversation: _supplierConversation(),
        purchaseService: _SupplierDraftsPurchaseService([
          _invoice(id: 'inv-draft', number: '141500'),
        ]),
      );

      await tester.tap(find.byTooltip('Agregar al mensaje'));
      await settle(tester);
      await tester.tap(find.text('Documento de compra'));
      await settle(tester);
      await tester.tap(find.text('N° 141500'));
      await settle(tester);

      // It is queued, with the prefilled note, and nothing has been sent.
      expect(find.text('Adjunto listo'), findsOneWidget);
      expect(find.text('documento_compra_141500.pdf'), findsOneWidget);
      expect(
        find.text('Te enviamos el documento de compra N° 141500.'),
        findsOneWidget,
      );
      // And the tile is the way into the preview.
      expect(find.byTooltip('Ver o editar el documento'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'supplier chat without drafts says so instead of offering an empty list',
    (tester) async {
      await pumpChat(
        tester,
        conversation: _supplierConversation(),
        purchaseService: _SupplierDraftsPurchaseService([
          _invoice(
            id: 'inv-paid',
            number: '141400',
            status: PurchaseInvoiceStatus.paid,
          ),
        ]),
      );

      await tester.tap(find.byTooltip('Agregar al mensaje'));
      await settle(tester);
      await tester.tap(find.text('Documento de compra'));
      await settle(tester);

      expect(
        find.text('Este proveedor no tiene documentos de compra en borrador.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'customer chat keeps the purchase document out of the composer',
    (tester) async {
      await pumpChat(
        tester,
        conversation: Conversation(
          id: 'conv-2',
          type: 'support',
          channel: 'website_portal',
          counterpartyType: 'customer',
          title: 'Cliente',
          updatedAt: DateTime.now(),
          participantIds: const [],
        ),
        purchaseService: _SupplierDraftsPurchaseService([
          _invoice(id: 'inv-draft', number: '141500'),
        ]),
      );

      await tester.tap(find.byTooltip('Agregar al mensaje'));
      await settle(tester);

      expect(find.text('Foto o archivo'), findsOneWidget);
      expect(find.text('Documento de compra'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Conversation _supplierConversation() => Conversation(
      id: 'conv-1',
      type: 'support',
      channel: 'website_portal',
      counterpartyType: 'supplier',
      title: 'TeknoBike',
      updatedAt: DateTime.now(),
      participantIds: const [],
      contextHint: const ConversationContextHint(
        supplierId: 'sup-1',
        supplierName: 'TeknoBike',
      ),
    );

PurchaseInvoice _invoice({
  required String id,
  required String number,
  PurchaseInvoiceStatus status = PurchaseInvoiceStatus.draft,
}) =>
    PurchaseInvoice(
      id: id,
      tenantId: 'tenant-1',
      invoiceNumber: number,
      supplierId: 'sup-1',
      supplierName: 'TeknoBike',
      date: DateTime(2026, 8, 18),
      status: status,
      total: 64210,
    );

class _SupplierDraftsPurchaseService extends PurchaseService {
  _SupplierDraftsPurchaseService(this._invoices)
      : super(DatabaseService(), TenantService());

  final List<PurchaseInvoice> _invoices;
  final List<String> requestedSupplierIds = [];

  @override
  Future<List<PurchaseInvoice>> getInvoicesBySupplier(String supplierId) async {
    requestedSupplierIds.add(supplierId);
    return _invoices
        .where((invoice) => invoice.supplierId == supplierId)
        .toList();
  }
}
