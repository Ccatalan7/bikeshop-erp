import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/messaging/widgets/message_delivery_indicator.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/compact_messages_host.dart';

/// 2026-10-08: en el teléfono una notificación o «Compartir» abrían el chat en
/// una capa, y la bandeja del botón de mensajes —un diálogo aparte— quedaba
/// encima: había que apretar atrás para ver el mensaje. Ahora hay una sola
/// pantalla de mensajes y todo pedido llega a ella.
Conversation _supplierChat() => Conversation(
      id: 'conv-supplier',
      type: 'support',
      channel: 'whatsapp',
      counterpartyType: 'supplier',
      title: 'TeknoBike',
      status: 'active',
      updatedAt: DateTime(2026, 10, 8, 10, 28),
      participantIds: const [],
    );

class _Chats extends ChatProvider {
  _Chats({List<Conversation>? initial, this.listLater}) : _list = [...?initial];

  final List<Conversation> _list;

  /// A thread the inbox only learns about when asked to list it.
  final Conversation? listLater;
  final Completer<void> listed = Completer<void>();

  @override
  List<Conversation> get conversations => List.unmodifiable(_list);

  @override
  String getChatTitle(Conversation conversation) => conversation.title ?? '';

  @override
  List<Message> messagesForConversation(String id) => [
        Message(
          id: 'inbound-1',
          conversationId: id,
          content: 'confírmame si es eso entonces',
          type: 'text',
          metadata: const {'message_direction': 'inbound'},
          createdAt: DateTime(2026, 10, 8, 10, 28),
        ),
        Message(
          id: 'teammate-1',
          conversationId: id,
          senderId: 'staff-diego',
          content: 'Te confirmo en un rato',
          type: 'text',
          metadata: const {
            'message_direction': 'outbound',
            'external_provider': 'whatsapp',
            'external_status': 'delivered',
          },
          createdAt: DateTime(2026, 10, 8, 10, 29),
        ),
        Message(
          id: 'mine-1',
          conversationId: id,
          senderId: 'staff-claudio',
          content: 'quedo atento al monto',
          type: 'text',
          isMe: true,
          metadata: const {
            'message_direction': 'outbound',
            'external_provider': 'whatsapp',
            'external_status': 'queued',
          },
          createdAt: DateTime(2026, 10, 8, 10, 30),
        ),
      ];

  @override
  Future<bool> ensureConversationListed(String conversationId) async {
    final later = listLater;
    if (later != null && later.id == conversationId) {
      await listed.future;
      _list.add(later);
      notifyListeners();
      return true;
    }
    return _list.any((c) => c.id == conversationId);
  }

  @override
  bool isTenantStaffUser(String userId) => userId.startsWith('staff-');

  // Sin servidor: abrir o soltar un hilo no se suscribe a nada.
  @override
  void setActiveConversation(String conversationId) {}

  @override
  void clearActiveConversation({
    String? conversationId,
    bool notify = true,
  }) {}

  @override
  void updateConversationView({
    required Object owner,
    required String conversationId,
    required bool visible,
  }) {}
}

class _Customers extends CustomerService {
  _Customers() : super(DatabaseService(), TenantService());
  @override
  Future<List<Customer>> getCustomersForList({
    bool forceRefresh = false,
  }) async =>
      [];
}

class _Purchases extends PurchaseService {
  _Purchases() : super(DatabaseService(), TenantService());
  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async =>
      [];
  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList({
    bool forceRefresh = false,
  }) async =>
      [];
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es_CL');
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'k');
  });

  setUp(CompactMessagesHost.resetForTest);

  Future<RightToolbarService> pumpPhone(
    WidgetTester tester,
    _Chats chats,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final toolbar = RightToolbarService();
    final workspaces = WorkspaceManager(sessionIdentity: 'compact-host');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationService>.value(
            value: NavigationService(),
          ),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(
            value: AppearanceService(),
          ),
          ChangeNotifierProvider<ChatProvider>.value(value: chats),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
          ChangeNotifierProvider<CustomerService>(create: (_) => _Customers()),
          ChangeNotifierProvider<PurchaseService>(create: (_) => _Purchases()),
          Provider<Workspace>.value(value: workspaces.activeWorkspace!),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.light,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => CompactMessagesHost.open(
                  context,
                  tool: ToolbarTool.messages,
                ),
                child: const Text('Mensajes'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return toolbar;
  }

  BuildContext homeContext(WidgetTester tester) =>
      tester.element(find.text('Mensajes', skipOffstage: false).first);

  testWidgets(
      'con la bandeja de Clientes abierta, la notificación de un proveedor '
      'abre su chat encima', (tester) async {
    final chats = _Chats(initial: [_supplierChat()]);
    final toolbar = await pumpPhone(tester, chats);

    await tester.tap(find.text('Mensajes'));
    await tester.pumpAndSettle();
    expect(find.byType(CompactMessagesSurface), findsOneWidget);
    expect(find.byType(ChatWindow), findsNothing);

    toolbar.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-supplier',
    );
    CompactMessagesHost.ensureOpen(homeContext(tester));
    await tester.pumpAndSettle();

    expect(find.byType(CompactMessagesSurface), findsOneWidget,
        reason: 'una sola pantalla de mensajes, nunca dos apiladas');
    expect(find.byType(ChatWindow), findsOneWidget,
        reason: 'el chat pedido es lo que se ve, no la bandeja');
    expect(find.byKey(const ValueKey('compact-messages-tab-customers')),
        findsNothing,
        reason: 'con chat abierto la cabecera de pestañas cede su alto');
    expect(tester.takeException(), isNull);
  });

  testWidgets('un hilo que la bandeja aún no trae se espera, no se suelta',
      (tester) async {
    final chats = _Chats(listLater: _supplierChat());
    final toolbar = await pumpPhone(tester, chats);

    toolbar.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-supplier',
    );
    CompactMessagesHost.ensureOpen(homeContext(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Abriendo el chat…'), findsOneWidget);
    expect(find.byType(ChatWindow), findsNothing);

    chats.listed.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ChatWindow), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'atrás desde el chat vuelve a la bandeja; desde la bandeja, cierra',
      (tester) async {
    final chats = _Chats(initial: [_supplierChat()]);
    final toolbar = await pumpPhone(tester, chats);

    toolbar.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-supplier',
    );
    CompactMessagesHost.ensureOpen(homeContext(tester));
    await tester.pumpAndSettle();
    expect(find.byType(ChatWindow), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatWindow), findsNothing);
    expect(find.byType(CompactMessagesSurface), findsOneWidget,
        reason: 'como WhatsApp: del chat a la lista');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CompactMessagesSurface), findsNothing);
    expect(toolbar.activeTool, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'lo que escribe un compañero va a la derecha, firmado y con checks',
      (tester) async {
    final chats = _Chats(initial: [_supplierChat()]);
    final toolbar = await pumpPhone(tester, chats);

    toolbar.openConversation(
      tool: ToolbarTool.supplierMessages,
      conversationId: 'conv-supplier',
    );
    CompactMessagesHost.ensureOpen(homeContext(tester));
    await tester.pumpAndSettle();

    final author =
        find.byKey(const ValueKey('chat-business-author-teammate-1'));
    expect(author, findsOneWidget,
        reason: 'el compañero firma como Viñabike con su nombre');
    expect(tester.widget<Text>(author).data, startsWith('Viñabike'));

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final teammate = find.byKey(const ValueKey('chat-message-row-teammate-1'));
    final teammateText = find.descendant(
      of: teammate,
      matching: find.text('Te confirmo en un rato'),
    );
    expect(tester.getRect(teammateText).right, greaterThan(width * 0.6),
        reason: 'del lado de Viñabike, no del contacto');
    expect(
      find.descendant(
        of: teammate,
        matching: find.byType(MessageDeliveryIndicator),
      ),
      findsOneWidget,
      reason: 'sus checks reales también se ven',
    );

    final inbound = find.descendant(
      of: find.byKey(const ValueKey('chat-message-row-inbound-1')),
      matching: find.text('confírmame si es eso entonces'),
    );
    expect(tester.getRect(inbound).left, lessThan(width * 0.4));
    expect(tester.takeException(), isNull);
  });
}
