import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/modules/messaging/widgets/entity_chat_sidebar.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('collapsed deferred sidebar performs no inbox work until opened',
      (tester) async {
    final messaging = _RecordingMessagingService();
    await tester.pumpWidget(
      Provider<MessagingService>.value(
        value: messaging,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800,
              child: Align(
                alignment: Alignment.centerRight,
                child: EntityChatSidebar(
                  entityType: 'job',
                  entityId: 'job-1',
                  entityTitle: 'Trabajo #PG-00001',
                  deferLoadingUntilExpanded: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(messaging.contextReads, 0);
    expect(messaging.conversationReads, 0);
    expect(messaging.subscriptions, 0);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    expect(messaging.contextReads, 1);
    expect(messaging.conversationReads, 1);
    expect(messaging.subscriptions, 1);
    expect(find.text('No hay conversaciones'), findsOneWidget);
  });
}

class _RecordingMessagingService extends MessagingService {
  int contextReads = 0;
  int conversationReads = 0;
  int subscriptions = 0;

  @override
  Future<Set<String>> getConversationIdsForContext({
    required String contextType,
    required String contextId,
  }) async {
    contextReads++;
    return const <String>{};
  }

  @override
  Future<List<Conversation>> getConversations({
    String? type,
    bool includeContextHints = true,
  }) async {
    conversationReads++;
    return const <Conversation>[];
  }

  @override
  RealtimeChannel subscribeToConversationsUpdates(
    VoidCallback onUpdate, {
    ValueChanged<MessageReceiptRealtimeUpdate>? onMessageReceiptUpdate,
  }) {
    subscriptions++;
    return Supabase.instance.client.channel('deferred-sidebar-test');
  }
}
