import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_activity.dart';
import 'package:vinabike_erp/modules/messaging/widgets/conversation_tile.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/quick_supplier_messages_panel.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      ConversationActivity.activeOnlyPreferenceKey: true,
    });
    ConversationActivity.showOnlyActiveChats.value = true;
  });

  for (final width in [272.0, 420.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('first supplier frame is coherent at $width in $brightness',
          (tester) async {
        final fixture = _Fixture();
        await _mount(tester, fixture, width: width, brightness: brightness);

        // Chats and supplier identities are ready; purchases deliberately are
        // not. Inspect this frame before completing the second source.
        expect(find.byType(ConversationTile), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('resultados'), findsNothing);
        expect(find.text('Sin proveedores activos'), findsNothing);
        expect(fixture.purchases.calls, 1);

        fixture.purchases.pending.complete(fixture.invoices);
        await tester.pump();
        await tester.pump();
        final tiles = tester
            .widgetList<ConversationTile>(find.byType(ConversationTile))
            .toList();
        expect(tiles.length, 6);
        expect(tiles.first.secondaryContextLine, r'$6.414');
        expect(tiles.first.operationalStatusLabel, 'DOC-0 · Borrador');
        expect(tiles.map((tile) => tile.conversation.id),
            isNot(contains('conversation-6')));
        expect(tiles.map((tile) => tile.conversation.id),
            isNot(contains('conversation-7')));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failed first load stays explicit and retries in place',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture, width: 272);
    fixture.purchases.pending
        .completeError(Exception('connection interrupted'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ConversationTile), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No se pudieron cargar los chats de proveedores'),
        findsOneWidget);
    expect(find.text('Sin proveedores activos'), findsNothing);

    fixture.purchases.pending = Completer<List<PurchaseInvoice>>();
    await tester.tap(find.byTooltip('Reintentar'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    fixture.purchases.pending.complete(fixture.invoices);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConversationTile), findsNWidgets(6));
    expect(fixture.purchases.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh preserves the completed snapshot while purchases wait',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    fixture.purchases.pending.complete(fixture.invoices);
    await tester.pump();
    await tester.pump();
    fixture.purchases.pending = Completer<List<PurchaseInvoice>>();

    await tester.tap(find.byTooltip('Recargar'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConversationTile), findsNWidgets(6));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.label == '6 resultados'),
        findsOneWidget);
    fixture.purchases.pending.completeError(Exception('refresh failed'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ConversationTile), findsNWidgets(6));
    expect(find.text('Se conserva la última información cargada.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing during first load discards its late result',
      (tester) async {
    final fixture = _Fixture();
    await _mount(tester, fixture);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.purchases.pending.complete(fixture.invoices);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _mount(
  WidgetTester tester,
  _Fixture fixture, {
  double width = 420,
  Brightness brightness = Brightness.light,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final toolbar = RightToolbarService();
  addTearDown(toolbar.dispose);
  addTearDown(fixture.purchases.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ChatProvider>(
          create: (_) => _Chats(fixture.conversations)),
      ChangeNotifierProvider<PurchaseService>.value(value: fixture.purchases),
      ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
    ],
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 1050,
            child: QuickSupplierMessagesPanel(showTitle: width > 272),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

class _Fixture {
  late final suppliers = List.generate(
      8,
      (i) => Supplier(
            id: 'supplier-$i',
            tenantId: 'tenant-a',
            name: 'Supplier $i',
            phone: '+5691234500$i',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ));
  late final invoices = List.generate(
      8,
      (i) => PurchaseInvoice(
            id: 'invoice-$i',
            tenantId: 'tenant-a',
            invoiceNumber: 'DOC-$i',
            supplierId: suppliers[i].id,
            supplierName: suppliers[i].name,
            date: DateTime.utc(2026, 9, 1),
            total: 6414,
            status: i < 4
                ? PurchaseInvoiceStatus.draft
                : PurchaseInvoiceStatus.received,
          ));
  late final conversations = List.generate(
      8,
      (i) => Conversation(
            id: 'conversation-$i',
            type: 'support',
            channel: 'whatsapp',
            counterpartyType: 'supplier',
            status: 'active',
            contextType: 'supplier',
            contextId: suppliers[i].id,
            updatedAt: DateTime.utc(2026, 9, 1),
            participantIds: const [],
            lastMessageContent: i == 4 || i == 5 ? 'Mensaje recibido' : null,
            contextHint: ConversationContextHint(
              supplierId: suppliers[i].id,
              supplierName: suppliers[i].name,
              supplierPhone: suppliers[i].phone,
              purchaseInvoiceId: invoices[i].id,
              purchaseInvoiceNumber: invoices[i].invoiceNumber,
              purchaseInvoiceStatus: invoices[i].status.displayName,
            ),
          ));
  late final purchases = _Purchases(suppliers);
}

class _Chats extends ChatProvider {
  _Chats(this.rows);
  final List<Conversation> rows;
  @override
  List<Conversation> get conversations => rows;
  @override
  Future<void> refreshConversationContextHints() async {}
  @override
  Future<void> loadConversations(
      {String? type, bool refreshContextHints = true}) async {}
}

class _Purchases extends PurchaseService {
  _Purchases(this.rows) : super(DatabaseService(), TenantService());
  final List<Supplier> rows;
  var pending = Completer<List<PurchaseInvoice>>();
  int calls = 0;
  @override
  bool get hasSuppliersCache => true;
  @override
  List<Supplier> get cachedSuppliers => rows;
  @override
  bool get hasListInvoicesCache => false;
  @override
  Future<List<Supplier>> getSuppliers(
          {bool forceRefresh = false, bool activeOnly = false}) async =>
      rows;
  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList(
      {bool forceRefresh = false}) {
    calls++;
    return pending.future;
  }
}
