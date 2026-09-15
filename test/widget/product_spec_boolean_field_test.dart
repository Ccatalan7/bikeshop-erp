import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_boolean_field.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  testWidgets(
      'prerequisites disable a forbidden answer without inventing false',
      (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
          preset: AppearancePresets.pacific, brightness: Brightness.light),
      home: Scaffold(
          body: ProductSpecBooleanField(
        label: 'Reutilizable',
        value: null,
        allowedValues: const {false},
        onChanged: (value) => answer = value,
      )),
    ));
    expect(answer, isNull);
    await tester.tap(find.text('Sí'));
    await tester.pumpAndSettle();
    expect(answer, isNull);
    expect(find.textContaining('Los requisitos elegidos no admiten Sí.'),
        findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
  for (final width in [390.0, 768.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('unknown, false and true survive at $width / $brightness',
          (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        bool? observed;
        final answers = <bool?>[];
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.resolve(
              preset: AppearancePresets.pacific, brightness: brightness),
          home: Scaffold(
              body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => ProductSpecBooleanField(
                        label: 'Incluye conector',
                        value: observed,
                        onChanged: (answer) => setState(() {
                              observed = answer;
                              answers.add(answer);
                            }),
                        helperText: 'Según el contenido de esta presentación.'),
                  ))),
        ));
        expect(answers, isEmpty,
            reason: 'rendering an unanswered field does not invent false');
        await tester.tap(find.text('No'));
        await tester.pumpAndSettle();
        expect(observed, false);
        await tester.tap(find.text('Sí'));
        await tester.pumpAndSettle();
        expect(observed, true);
        await tester.tap(find.text('Sin dato'));
        await tester.pumpAndSettle();
        expect(observed, isNull);
        expect(answers, [false, true, null]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
