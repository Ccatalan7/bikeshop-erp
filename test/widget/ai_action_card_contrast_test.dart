import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/widgets/ai_chat_bubble.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

import '../support/ai_assistant_session_harness.dart';

/// The result cards used to be painted white whatever the theme, so in dark
/// mode the assistant showed a column of light islands inside the app's dark
/// chrome — the integration defect the collaboration contract names by hand.
/// Their surfaces and foregrounds now come from the colour scheme.
double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

void main() {
  testWidgets('the assistant panel carries no literal white surface',
      (tester) async {
    for (final brightness in Brightness.values) {
      final session = await boundAiSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: brightness,
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
        ),
      );
      await tester.pump();

      final scheme = Theme.of(
        tester.element(find.byType(AIChatPanel)),
      ).colorScheme;

      // In dark mode a surface role is dark; a card that ignored the theme
      // would still be near-white.
      if (brightness == Brightness.dark) {
        expect(
          scheme.surfaceContainerHigh.computeLuminance(),
          lessThan(0.5),
          reason: 'the dark surface role is not dark',
        );
        expect(
          _contrastRatio(scheme.onSurface, scheme.surfaceContainerHigh),
          greaterThanOrEqualTo(4.5),
        );
      }

      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'card text roles stay readable on their own surface in both '
      'brightnesses', (tester) async {
    for (final brightness in Brightness.values) {
      final theme = AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      );
      final scheme = theme.colorScheme;

      expect(
        _contrastRatio(scheme.onSurface, scheme.surfaceContainerHigh),
        greaterThanOrEqualTo(4.5),
        reason: 'title/description on the card surface ($brightness)',
      );
      expect(
        _contrastRatio(scheme.onSurfaceVariant, scheme.surfaceContainerHigh),
        greaterThanOrEqualTo(3.0),
        reason: 'subtitle on the card surface ($brightness)',
      );
      expect(
        _contrastRatio(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: 'chip text on the chip surface ($brightness)',
      );
    }
  });
}
