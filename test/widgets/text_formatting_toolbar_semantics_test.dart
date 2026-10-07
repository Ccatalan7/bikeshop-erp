import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/text_formatting_toolbar.dart';

/// The «Formato» controls name themselves: a screen reader hears each style
/// as a button and whether it is on, and the size and color with their
/// values. Until
/// 2026-10-07 they were icons with only a tooltip.
void main() {
  testWidgets('each formatting control is a named button', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextFormattingToolbar(
            currentFormatting: const TextFormatting(
              isBold: true,
              textColor: Color(0xFF1E88E5),
            ),
            onFormattingChanged: (_) {},
            transactionIdentity: Object(),
            preset: TextToolbarPreset.basic,
            showAdvancedOptions: false,
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Negrita')),
      matchesSemantics(
        label: 'Negrita',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Cursiva')),
      matchesSemantics(
        label: 'Cursiva',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(find.bySemanticsLabel('Subrayado'), findsOneWidget);
    expect(find.bySemanticsLabel('Alineación'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Tamaño de texto')).value,
      '16',
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Color de texto')).value,
      '#1E88E5',
    );
    semantics.dispose();
  });
}
