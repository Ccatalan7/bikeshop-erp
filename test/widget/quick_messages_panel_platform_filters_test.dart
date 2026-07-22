import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/crm/models/crm_models.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_activity.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/widgets/quick_messages_panel.dart';

const _whatsAppFilterKey = ValueKey<String>('quick_messages_platform_whatsapp');
const _instagramFilterKey =
    ValueKey<String>('quick_messages_platform_instagram');
const _messengerFilterKey =
    ValueKey<String>('quick_messages_platform_messenger');
const _webFilterKey = ValueKey<String>('quick_messages_platform_web');

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
    'inline platform icons filter with search and remain overflow-free at 272px',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final conversations = [
        _conversation(
          id: 'whatsapp',
          channel: 'whatsapp',
          title: 'Alicia WhatsApp',
          message: 'Consulta por ruedas tubeless',
        ),
        _conversation(
          id: 'instagram',
          channel: 'instagram',
          title: 'Bruno Instagram',
          message: 'Consulta por ruedas de gravel',
        ),
        _conversation(
          id: 'messenger',
          channel: 'facebook_messenger',
          title: 'Carla Messenger',
          message: 'Consulta por un casco',
        ),
        _conversation(
          id: 'web',
          channel: 'website_portal',
          title: 'Diego Web',
          message: 'Consulta por ruedas de ruta',
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ChatProvider>(
              create: (_) => _TestChatProvider(conversations),
            ),
            ChangeNotifierProvider<CustomerService>(
              create: (_) => _EmptyCustomerService(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  // RightToolbar's 320 px minimum includes its 48 px icon rail.
                  width: 272,
                  height: 740,
                  child: QuickMessagesPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_whatsAppFilterKey), findsOneWidget);
      expect(find.byKey(_instagramFilterKey), findsOneWidget);
      expect(find.byKey(_messengerFilterKey), findsOneWidget);
      expect(find.byKey(_webFilterKey), findsOneWidget);
      expect(find.byTooltip('Filtrar por WhatsApp'), findsOneWidget);
      expect(find.byTooltip('Filtrar por Instagram'), findsOneWidget);
      expect(find.byTooltip('Filtrar por Messenger'), findsOneWidget);
      expect(find.byTooltip('Filtrar por Web'), findsOneWidget);
      expect(_findIcon(FontAwesomeIcons.whatsapp), findsOneWidget);
      expect(_findIcon(FontAwesomeIcons.instagram), findsOneWidget);
      expect(_findIcon(FontAwesomeIcons.facebookMessenger), findsOneWidget);
      _expectVisibleTitles(
        whatsapp: true,
        instagram: true,
        messenger: true,
        web: true,
      );
      _expectNoFlutterException(tester);

      await _tapFilter(tester, _whatsAppFilterKey);
      _expectVisibleTitles(whatsapp: true);

      // Pressing the selected platform again returns to the combined inbox.
      await _tapFilter(tester, _whatsAppFilterKey);
      _expectVisibleTitles(
        whatsapp: true,
        instagram: true,
        messenger: true,
        web: true,
      );

      await _tapFilter(tester, _instagramFilterKey);
      _expectVisibleTitles(instagram: true);
      await _tapFilter(tester, _messengerFilterKey);
      _expectVisibleTitles(messenger: true);
      await _tapFilter(tester, _webFilterKey);
      _expectVisibleTitles(web: true);

      // Search remains an AND constraint with the selected platform.
      await _tapFilter(tester, _webFilterKey); // Reset to Todos.
      await tester.enterText(find.byType(TextField), 'ruedas');
      await tester.pumpAndSettle();
      _expectVisibleTitles(
        whatsapp: true,
        instagram: true,
        web: true,
      );

      await _tapFilter(tester, _instagramFilterKey);
      _expectVisibleTitles(instagram: true);
      _expectNoFlutterException(tester);
    },
  );
}

Future<void> _tapFilter(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  _expectNoFlutterException(tester);
}

void _expectNoFlutterException(WidgetTester tester) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: exception is FlutterError
        ? exception.toStringDeep()
        : exception?.toString(),
  );
}

void _expectVisibleTitles({
  bool whatsapp = false,
  bool instagram = false,
  bool messenger = false,
  bool web = false,
}) {
  expect(
    find.text('Alicia WhatsApp'),
    whatsapp ? findsOneWidget : findsNothing,
  );
  expect(
    find.text('Bruno Instagram'),
    instagram ? findsOneWidget : findsNothing,
  );
  expect(
    find.text('Carla Messenger'),
    messenger ? findsOneWidget : findsNothing,
  );
  expect(find.text('Diego Web'), web ? findsOneWidget : findsNothing);
}

Finder _findIcon(IconData icon) {
  return find.byWidgetPredicate(
    (widget) =>
        (widget is Icon && widget.icon == icon) ||
        (widget is FaIcon && widget.icon == icon),
  );
}

Conversation _conversation({
  required String id,
  required String channel,
  required String title,
  required String message,
}) {
  return Conversation(
    id: id,
    type: 'support',
    channel: channel,
    status: 'active',
    creatorName: title,
    updatedAt: DateTime.utc(2026, 7, 21, 20),
    lastMessageAt: DateTime.utc(2026, 7, 21, 20),
    lastMessageContent: message,
    participantIds: const [],
  );
}

class _TestChatProvider extends ChatProvider {
  _TestChatProvider(this._testConversations);

  final List<Conversation> _testConversations;

  @override
  List<Conversation> get conversations => _testConversations;

  @override
  Future<void> refreshConversationContextHints() async {}
}

class _EmptyCustomerService extends CustomerService {
  _EmptyCustomerService() : super(DatabaseService(), TenantService());

  @override
  Future<List<Customer>> getCustomersForList(
      {bool forceRefresh = false}) async {
    return const [];
  }
}
