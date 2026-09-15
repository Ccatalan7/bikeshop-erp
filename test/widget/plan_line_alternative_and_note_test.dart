import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Alternativa y nota», el desplegable de la línea del plan.
///
/// **El hueco.** `handoff-t23/spec.json`, `frames[plan].with_lines`:
/// `line_disclosure: "Alternativa y nota (sustituir candidato, nota libre)"`.
/// El desplegable existía pero se llamaba «Evidencia de la línea» y sólo
/// **mostraba** evidencia: no dejaba decir por qué se eligió ese candidato ni
/// cambiarlo sin ir a buscarlo a mano. La razón de una compra es justo lo que
/// se pierde entre el borrador y el documento si no queda escrita.
///
/// La evidencia se conserva —sostiene la decisión— y encima aparecen las dos
/// acciones que el contrato nombra.

PurchasePlanLine line({String? note}) => PurchasePlanLine(
      id: 'line-1',
      sourceNeedId: 'need-1',
      candidateId: 'cand-1',
      productId: 'prod-1',
      productName: 'Cámara Maxxis 29',
      supplierName: 'TeknoBike',
      quantity: 4,
      unit: 'unit',
      currency: 'CLP',
      supplierAvailability: 'unverified',
      landedUnitCostNet: 3181.45,
      note: note,
    );

Future<void> pumpRow(
  WidgetTester tester, {
  PurchasePlanLine? value,
  void Function(String? note)? onSaveNote,
  VoidCallback? onSubstitute,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          child: SingleChildScrollView(
            child: PurchasePlanLineRow(
              line: value ?? line(),
              busy: false,
              updating: false,
              removing: false,
              onEditQuantity: () {},
              onStepQuantity: (_) {},
              onRemove: () {},
              onSaveNote: onSaveNote,
              onSubstitute: onSubstitute,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> openDisclosure(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('plan-line-evidence-line-1')));
  await tester.pump();
}

void main() {
  testWidgets('el desplegable se nombra por lo que hace', (tester) async {
    await pumpRow(tester, onSaveNote: (_) {}, onSubstitute: () {});

    expect(find.text('Alternativa y nota'), findsOneWidget);
    expect(find.text('Evidencia de la línea'), findsNothing);
  });

  testWidgets('sin las acciones conserva el nombre y el contenido viejos',
      (tester) async {
    await pumpRow(tester);

    expect(find.text('Evidencia de la línea'), findsOneWidget);
    await openDisclosure(tester);
    // La evidencia no se fue: sigue sosteniendo la decisión.
    expect(find.text('Disponibilidad declarada'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('plan-line-note-field-line-1')),
      findsNothing,
    );
  });

  testWidgets('la nota guardada llega al campo', (tester) async {
    await pumpRow(
      tester,
      value: line(note: 'Se eligió por plazo, no por precio.'),
      onSaveNote: (_) {},
      onSubstitute: () {},
    );
    await openDisclosure(tester);

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('plan-line-note-field-line-1')),
    );
    expect(field.controller?.text, 'Se eligió por plazo, no por precio.');
  });

  testWidgets('escribir y guardar entrega el texto tal cual', (tester) async {
    final saved = <String?>[];
    await pumpRow(tester, onSaveNote: saved.add, onSubstitute: () {});
    await openDisclosure(tester);

    await tester.enterText(
      find.byKey(const ValueKey('plan-line-note-field-line-1')),
      'Llega en tres días',
    );
    await tester.tap(find.byKey(const ValueKey('plan-line-note-save-line-1')));
    await tester.pump();

    expect(saved, ['Llega en tres días']);
  });

  testWidgets('vaciar el campo es una orden de borrar, no un no-op',
      (tester) async {
    final saved = <String?>[];
    await pumpRow(
      tester,
      value: line(note: 'Una nota vieja'),
      onSaveNote: saved.add,
      onSubstitute: () {},
    );
    await openDisclosure(tester);

    await tester.enterText(
      find.byKey(const ValueKey('plan-line-note-field-line-1')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('plan-line-note-save-line-1')));
    await tester.pump();

    // Se manda vacío: normalizar «en blanco» es del comando, no del widget.
    expect(saved, ['']);
  });

  testWidgets('sustituir candidato es una acción, no una lectura',
      (tester) async {
    var substituted = 0;
    await pumpRow(
      tester,
      onSaveNote: (_) {},
      onSubstitute: () => substituted++,
    );
    await openDisclosure(tester);

    await tester.tap(find.byKey(const ValueKey('plan-line-substitute-line-1')));
    await tester.pump();
    expect(substituted, 1);
  });
}
