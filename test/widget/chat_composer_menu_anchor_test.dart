import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/messaging/widgets/chat_window.dart';

/// The composer menu hangs from the «+» button.
///
/// It used to be placed by subtracting a hardcoded `estimatedHeight` from the
/// button's top, so any panel shorter than that estimate floated the leftover
/// distance away from what the operator had just pressed.
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

  testWidgets(
    'the composer menu opens against the + button, not against the window edge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ChatProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  // A second pane on the left: the overlay spans the whole
                  // window, so a mis-anchored panel drifts over this one.
                  const Expanded(child: ColoredBox(color: Colors.black12)),
                  Expanded(
                    child: ChatWindow(
                      conversation: Conversation(
                        id: 'conv-1',
                        type: 'support',
                        channel: 'website_portal',
                        counterpartyType: 'customer',
                        title: 'Cliente',
                        updatedAt: DateTime.now(),
                        participantIds: const [],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await settle(tester);

      final button = tester.getRect(find.byTooltip('Agregar al mensaje'));
      await tester.tap(find.byTooltip('Agregar al mensaje'));
      await settle(tester);

      final panel = tester.getRect(
        find
            .ancestor(
              of: find.text('Agregar al mensaje'),
              matching: find.byType(Material),
            )
            .first,
      );

      // Its bottom edge sits just above the button, whatever the panel's real
      // height turns out to be.
      expect(panel.bottom, lessThanOrEqualTo(button.top));
      expect(button.top - panel.bottom, lessThan(24));

      // And it stays on the button's side of the window.
      // Within the button's own padding, not 600 px away at the window edge.
      expect(panel.left, closeTo(button.left, 8));
      expect(tester.takeException(), isNull);
    },
  );
}
