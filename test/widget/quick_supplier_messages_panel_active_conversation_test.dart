import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_activity.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
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

  testWidgets(
    'an open supplier chat stays in Activos after its purchase was received',
    (tester) async {
      final conversation = Conversation(
        id: 'derman-conversation',
        type: 'support',
        channel: 'whatsapp',
        counterpartyType: 'supplier',
        status: 'active',
        contextType: 'supplier',
        contextId: 'supplier-derman',
        updatedAt: DateTime.utc(2026, 9, 4, 19, 23),
        lastMessageAt: DateTime.utc(2026, 9, 4, 19, 23),
        lastMessageContent: 'Foto',
        lastMessageType: 'image',
        lastMessageDirection: 'inbound',
        unreadCount: 1,
        participantIds: const [],
        contextHint: const ConversationContextHint(
          supplierId: 'supplier-derman',
          supplierName: 'Derman',
          supplierPhone: '+56 9 2749 7948',
          contactPersonName: 'Derman',
          purchaseInvoiceId: 'purchase-10068',
          purchaseInvoiceNumber: '10068',
          purchaseInvoiceStatus: 'received',
        ),
      );
      final toolbarService = RightToolbarService();
      final purchaseService = _DermanPurchaseService();
      addTearDown(toolbarService.dispose);
      addTearDown(purchaseService.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ChatProvider>(
              create: (_) => _ConversationChatProvider(conversation),
            ),
            ChangeNotifierProvider<PurchaseService>.value(
              value: purchaseService,
            ),
            ChangeNotifierProvider<RightToolbarService>.value(
              value: toolbarService,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                height: 720,
                child: QuickSupplierMessagesPanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Derman · Derman'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'a received purchase alone does not revive an empty supplier binding',
    () {
      final oldConversation = Conversation(
        id: 'old-conversation',
        type: 'support',
        channel: 'whatsapp',
        counterpartyType: 'supplier',
        status: 'active',
        updatedAt: DateTime.utc(2026, 6, 1),
        lastMessageAt: DateTime.utc(2026, 6, 1),
        participantIds: const [],
      );

      expect(
        ConversationActivity.hasActiveSupplierWork(
          conversation: oldConversation,
          purchaseInvoiceStatuses: const ['received'],
        ),
        isFalse,
      );
    },
  );
}

class _ConversationChatProvider extends ChatProvider {
  _ConversationChatProvider(this.conversation);

  final Conversation conversation;

  @override
  List<Conversation> get conversations => [conversation];

  @override
  Future<void> refreshConversationContextHints() async {}
}

class _DermanPurchaseService extends PurchaseService {
  _DermanPurchaseService() : super(DatabaseService(), TenantService());

  late final Supplier supplier = Supplier(
    id: 'supplier-derman',
    tenantId: 'tenant-a',
    name: 'Derman',
    phone: '+56 9 2749 7948',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );

  late final PurchaseInvoice receivedInvoice = PurchaseInvoice(
    id: 'purchase-10068',
    tenantId: 'tenant-a',
    invoiceNumber: '10068',
    supplierId: supplier.id,
    supplierName: supplier.name,
    date: DateTime.utc(2026, 9, 4),
    status: PurchaseInvoiceStatus.received,
    total: 65188,
  );

  @override
  ErpAuthorityScopeKey? get supplierAuthorityScope =>
      const ErpAuthorityScopeKey(
        userId: 'user-a',
        tenantId: 'tenant-a',
      );

  @override
  bool get hasSuppliersCache => true;

  @override
  List<Supplier> get cachedSuppliers => [supplier];

  @override
  bool get hasListInvoicesCache => true;

  @override
  List<PurchaseInvoice> get cachedListInvoices => [receivedInvoice];

  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async =>
      [supplier];

  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList({
    bool forceRefresh = false,
  }) async =>
      [receivedInvoice];
}
