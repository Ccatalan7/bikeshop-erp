import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Lo que la fila del plan **dice** sobre su evidencia.
///
/// `handoff-t23`, `07 · Plan con líneas`, pide la meta
/// «evidencia 18 días · completa». La fila decía sólo «evidencia completa»: la
/// antigüedad, que es el dato que decide si el costo aterrizado todavía sirve,
/// no llegaba a la pantalla aunque el servidor ya la escribe.
///
/// Estas pruebas afirman el texto renderizado, no la constante: si alguien
/// vuelve a dejar la edad fuera del rótulo, o la escribe cuando no la tiene,
/// se ponen rojas.

PurchasePlanLine line({int? evidenceAgeDays, double? landedUnitCostNet}) {
  return PurchasePlanLine(
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
    landedUnitCostNet: landedUnitCostNet,
    evidenceAgeDays: evidenceAgeDays,
  );
}

Future<void> pumpRow(WidgetTester tester, PurchasePlanLine value) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 900,
          child: PurchasePlanLineRow(
            line: value,
            busy: false,
            updating: false,
            removing: false,
            onEditQuantity: () {},
            onStepQuantity: (_) {},
            onRemove: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('la fila antepone los días a «completa»', (tester) async {
    await pumpRow(
      tester,
      line(evidenceAgeDays: 79, landedUnitCostNet: 3181.45),
    );

    expect(find.text('evidencia 79 días · completa'), findsOneWidget);
    // El rótulo viejo ya no puede quedar suelto en la fila.
    expect(find.text('evidencia completa'), findsNothing);
  });

  testWidgets('sin edad conocida no se inventa un número', (tester) async {
    await pumpRow(tester, line(landedUnitCostNet: 3181.45));

    expect(find.text('evidencia completa'), findsOneWidget);
    expect(find.textContaining('días'), findsNothing);
  });

  testWidgets('sin costo aterrizado manda el hueco, no la edad', (tester) async {
    // Una línea sin costo aterrizado no tiene evidencia comparable: decirlo
    // vale más que decir cuántos días tiene un número que no existe.
    await pumpRow(tester, line(evidenceAgeDays: 79));

    expect(
      find.text('evidencia incompleta · sin costo aterrizado'),
      findsOneWidget,
    );
    expect(find.textContaining('79'), findsNothing);
  });
}
