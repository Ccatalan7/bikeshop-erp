import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_session_state.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/widgets/ai_chat_bubble.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

import '../support/ai_assistant_session_harness.dart';

void main() {
  Widget host(AIAssistantSessionService session) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 700,
          child: ChangeNotifierProvider<AIAssistantSessionService>.value(
            value: session,
            child: const AIChatPanel(jobs: [], embedded: true),
          ),
        ),
      ),
    );
  }

  testWidgets('opening the assistant runs no maintenance work', (tester) async {
    // The panel used to call InventoryService.backfillEmbeddings() from its
    // mount, against an RPC that does not exist in production, so every open
    // logged a failure loop nobody asked for. This host provides no
    // InventoryService at all: if the mount reached for one, provider would
    // throw and this test would fail. That is the whole point — the assertion
    // is that opening a panel touches no service.
    final session = await boundAiSession(
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(host(session));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(AIChatPanel), findsOneWidget);
  });

  testWidgets('a bound session shows its greeting and an open composer',
      (tester) async {
    final session = await boundAiSession(
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    addTearDown(session.dispose);

    await tester.pumpWidget(host(session));
    await tester.pump();

    expect(session.status, AIAssistantSessionStatus.ready);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('ai-assistant-message-input')),
    );
    expect(field.enabled, isTrue);
  });

  testWidgets('an unresolved session closes the composer and shows nothing',
      (tester) async {
    // Fail-closed is a visible state, not just an internal flag: no prior
    // transcript, no usable input, and a hint that says why.
    final session = AIAssistantSessionService();
    addTearDown(session.dispose);

    await tester.pumpWidget(host(session));
    await tester.pump();

    expect(session.canSend, isFalse);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('ai-assistant-message-input')),
    );
    expect(field.enabled, isFalse);

    final send = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('ai-assistant-send-message')),
    );
    expect(send.onPressed, isNull);

    final mic = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('ai-assistant-voice-input')),
    );
    expect(mic.onPressed, isNull);
  });
}
