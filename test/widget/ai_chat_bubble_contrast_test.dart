import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/dev/agent_input.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/widgets/ai_chat_bubble.dart';

import '../support/ai_assistant_session_harness.dart';

/// The panel no longer owns its transcript or its engine; the session service
/// does. Mounting it therefore needs one session bound through the real
/// `synchronize`. Only this harness changed — both assertions below are
/// unchanged.
Widget _withSession(AIAssistantSessionService session, Widget child) {
  return ChangeNotifierProvider<AIAssistantSessionService>.value(
    value: session,
    child: child,
  );
}

void main() {
  testWidgets('assistant bubble uses a readable theme pair in light and dark', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final session = await boundAiSession();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: brightness,
            useMaterial3: true,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 700,
              child: _withSession(
                session,
                const AIChatPanel(
                  jobs: [],
                  embedded: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      const bubbleKey = ValueKey('ai-chat-assistant-bubble-0');
      final bubbleFinder = find.byKey(bubbleKey);
      expect(bubbleFinder, findsOneWidget);

      final bubble = tester.widget<Container>(bubbleFinder);
      final decoration = bubble.decoration! as BoxDecoration;
      final scheme = Theme.of(tester.element(bubbleFinder)).colorScheme;
      expect(decoration.color, scheme.surfaceContainerHighest);
      expect(
        _contrastRatio(scheme.onSurface, decoration.color!),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('composer accepts agent text in its real controller',
      (tester) async {
    const prompt = 'Dame un resumen de los trabajos activos.';
    final session = await boundAiSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 700,
            child: _withSession(
              session,
              const AIChatPanel(
                jobs: [],
                embedded: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final result = await enterTextAgentInputTargetForTesting(const {
      'key': 'ai-assistant-message-input',
      'text': prompt,
    });
    await tester.pump();

    expect(result['ok'], isTrue);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('ai-assistant-message-input')),
    );
    expect(field.controller!.text, prompt);
    expect(field.textInputAction, TextInputAction.send);
    expect(find.byTooltip('Enviar mensaje'), findsOneWidget);
  });
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
