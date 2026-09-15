import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/messaging/widgets/compact_chat_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/navigation_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/main_layout.dart';

final _conversation = Conversation(
  id: 'chat-visual',
  type: 'internal',
  channel: 'internal',
  title: 'Test',
  status: 'active',
  updatedAt: DateTime(2026, 9, 4),
  participantIds: const [],
  lastMessageContent: 'Archivo con una respuesta',
);

class _Chats extends ChatProvider {
  @override
  List<Conversation> get conversations => [_conversation];
  @override
  String getChatTitle(Conversation conversation) => conversation.title!;
  @override
  List<Message> messagesForConversation(String id) => [
        Message(
            id: 'original',
            conversationId: id,
            content: 'Test original',
            type: 'text',
            metadata: const {},
            createdAt: DateTime(2026, 9, 4, 18)),
        Message(
            id: 'file',
            conversationId: id,
            content: 'Archivo con una respuesta',
            type: 'file',
            isMe: true,
            createdAt: DateTime(2026, 9, 4, 18, 5),
            metadata: const {
              'filename': 'prueba-mensajeria.txt',
              'content_type': 'text/plain',
              'attachment_id': '11111111-1111-4111-8111-111111111111',
              'reply_to': {
                'conversation_id': 'chat-visual',
                'message_id': 'original',
                'content': 'Test original',
                'sender_name': 'Claudio',
                'type': 'text'
              },
            }),
      ];
  @override
  void updateConversationView(
      {required Object owner,
      required String conversationId,
      required bool visible}) {}
}

class _Customers extends CustomerService {
  _Customers() : super(DatabaseService(), TenantService());
  @override
  Future<List<Customer>> getCustomersForList(
          {bool forceRefresh = false}) async =>
      [];
}

class _Purchases extends PurchaseService {
  _Purchases() : super(DatabaseService(), TenantService());
  @override
  Future<List<Supplier>> getSuppliers(
          {bool forceRefresh = false, bool activeOnly = false}) async =>
      [];
  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList(
          {bool forceRefresh = false}) async =>
      [];
}

void main() => runMessagingCompactSurfaceTests();

/// The device suite runs this same real shell + inbox + chat composition.
void runMessagingCompactSurfaceTests({
  bool device = false,
  Future<void> Function(String, WidgetTester)? capture,
}) {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es_CL');
    await Supabase.initialize(
        url: 'http://127.0.0.1:54321', anonKey: 'test-key');
  });

  for (final module in [false, true]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'compact messaging ${module ? 'module' : 'toolbar'} ${brightness.name}: contrast, space, keyboard and return',
          (tester) async {
        if (!device) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        final navigation = NavigationService();
        final workspaces = WorkspaceManager(sessionIdentity: 'messaging-ui');
        final appearance = AppearanceService();
        final chat = _Chats();
        final toolbar = RightToolbarService();
        final workspace = workspaces.activeWorkspace!..isPinned = true;
        final theme = AppTheme.resolve(
            preset: AppearancePresets.vinabike, brightness: brightness);
        final router = GoRouter(routes: [
          GoRoute(
              path: '/',
              builder: (context, state) => MainLayout(
                  title: 'Dashboard',
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () => context.push('/chat/test'),
                          child: const Text('Entrar al chat'))))),
          GoRoute(
              path: '/chat/test',
              builder: (_, state) =>
                  CompactChatRoute(conversation: _conversation)),
        ]);
        await tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider<NavigationService>.value(value: navigation),
          ChangeNotifierProvider<WorkspaceManager>.value(value: workspaces),
          ChangeNotifierProvider<AppearanceService>.value(value: appearance),
          ChangeNotifierProvider<ChatProvider>.value(value: chat),
          ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
          ChangeNotifierProvider<CustomerService>(create: (_) => _Customers()),
          ChangeNotifierProvider<PurchaseService>(create: (_) => _Purchases()),
          Provider<Workspace>.value(value: workspace),
        ], child: MaterialApp.router(theme: theme, routerConfig: router)));
        await tester.pumpAndSettle();
        if (module) {
          await tester.tap(find.text('Entrar al chat'));
        } else {
          await tester
              .tap(find.byKey(const ValueKey('main-layout-mobile-messages')));
          await tester.pumpAndSettle();
          await tester.tap(
              find.byKey(const ValueKey('compact-messages-tab-customers')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Test').first);
        }
        await tester.pumpAndSettle();
        expect(find.byType(ChatWindow), findsOneWidget);
        final field = find.byKey(const ValueKey('chat-message-composer'));
        if (device) {
          tester.testTextInput.unregister();
          addTearDown(tester.testTextInput.register);
          tester.widget<TextField>(field).controller!.text =
              'Borrador conservado';
          await tester.tap(field);
          await tester.pump();
          await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
          for (var attempt = 0;
              attempt < 30 && tester.view.viewInsets.bottom == 0;
              attempt++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 200)));
            await tester.pump();
          }
          expect(tester.view.viewInsets.bottom, greaterThan(0),
              reason: 'Use the real Android IME, not TestTextInput.');
          debugPrint(
              'MESSAGING_IME_READY ${module ? 'module' : 'toolbar'}-${brightness.name} inset=${tester.view.viewInsets.bottom}');
          await tester
              .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
        } else {
          await tester.enterText(field, 'Borrador conservado');
        }
        await tester.pumpAndSettle();
        await capture?.call(
            '${module ? 'module' : 'toolbar'}-messaging-${brightness.name}-keyboard',
            tester);
        final composer =
            tester.getRect(find.byKey(const ValueKey('chat-message-composer')));
        expect(
            composer.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height /
                    tester.view.devicePixelRatio -
                tester.view.viewInsets.bottom / tester.view.devicePixelRatio));
        FocusManager.instance.primaryFocus?.unfocus();
        if (device)
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('chat-message-row-original'));
        final rect = tester.getRect(row);
        await tester.longPressAt(Offset(rect.right - 4, rect.center.dy));
        await tester.pumpAndSettle();
        final copy = find.byKey(const ValueKey('chat-selection-copy'));
        expect(copy, findsOneWidget);
        final icon = find.descendant(of: copy, matching: find.byType(Icon));
        final ink = IconTheme.of(tester.element(icon)).color!;
        final surface = theme.colorScheme.surface;
        final a = ink.computeLuminance(), b = surface.computeLuminance();
        final contrast = ((a > b ? a : b) + .05) / ((a > b ? b : a) + .05);
        expect(contrast, greaterThanOrEqualTo(3),
            reason:
                'Enabled selection icons must contrast with the application surface, not inherit app-bar ink.');
        expect(tester.getTopLeft(copy).dy, lessThan(kToolbarHeight * 2),
            reason:
                'Selection is the compact header, without sheet and chat headers stacked above it.');
        expect(tester.getSize(copy).shortestSide, greaterThanOrEqualTo(48));
        await capture?.call(
            '${module ? 'module' : 'toolbar'}-messaging-${brightness.name}-selection',
            tester);
        await tester.tap(find.byKey(const ValueKey('chat-selection-cancel')));
        await tester.pumpAndSettle();
        final options = find.byKey(const ValueKey('chat-options'));
        final optionsIcon =
            find.descendant(of: options, matching: find.byType(Icon));
        final optionsInk = IconTheme.of(tester.element(optionsIcon)).color!;
        final optionsLum = optionsInk.computeLuminance();
        final optionsContrast = ((optionsLum > b ? optionsLum : b) + .05) /
            ((optionsLum > b ? b : optionsLum) + .05);
        expect(optionsContrast, greaterThanOrEqualTo(3),
            reason: 'The menu glyph also rejects inherited AppBar IconTheme.');
        await tester.tap(options);
        await tester.pumpAndSettle();
        final info = find.text('Información del chat');
        expect(info, findsOneWidget);
        Navigator.of(tester.element(info)).pop();
        await tester.pumpAndSettle();
        await capture?.call(
            '${module ? 'module' : 'toolbar'}-messaging-${brightness.name}-conversation',
            tester);
        await tester.tap(find.byKey(ValueKey(
            module ? 'compact-chat-back' : 'quick-messages-back-to-inbox')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(module ? 'Entrar al chat' : 'Test').first);
        await tester.pumpAndSettle();
        expect(find.text('Borrador conservado'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        for (final notifier in <ChangeNotifier>[
          navigation,
          workspaces,
          appearance,
          chat,
          toolbar
        ]) {
          notifier.dispose();
        }
      });
    }
  }
}
