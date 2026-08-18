import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_plan_close.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El cierre del plan es lo que faltaba para que el recorrido termine en algo.
/// Estas pruebas fijan las tres reglas del contrato de datos que lo gobiernan:
/// monedas separadas, margen sin base cuando no hay precio vigente, y que
/// preparar no compre nada.
PurchasePlanLine _line({
  required String currency,
  required double quantity,
  double? cost,
  double? margin,
  String needId = 'need-1',
}) {
  return PurchasePlanLine.fromJson({
    'id': 'line-$currency-$quantity-$needId',
    'source_need_id': needId,
    'candidate_id': 'candidate-1',
    'product_id': 'product-1',
    'product_name': 'Neumático',
    'supplier_name': 'NMKR',
    'quantity': quantity,
    'unit': 'unidad',
    'currency_code': currency,
    'landed_unit_cost_net': cost,
    'projected_gross_margin_ratio': margin,
    'supplier_availability': 'unverified',
  });
}

Future<void> _pump(WidgetTester tester, List<PurchasePlanLine> lines,
    {int missing = 0}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PurchasePlanClose(
            lines: lines,
            supplierCount: 2,
            missingCount: missing,
          ),
        ),
      ),
    ),
  );
}

void main() {
  // La escala del asistente resuelve sus familias con `google_fonts`. En las
  // pruebas se prohíbe la descarga en tiempo de ejecución: sin esto el
  // resultado dependería de la red y del caché de la máquina, que es
  // exactamente lo contrario de una regresión.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('CLP y USD viajan separados y el segundo se rotula no sumado',
      (tester) async {
    await _pump(tester, [
      _line(currency: 'CLP', quantity: 2, cost: 10000, margin: 0.4),
      _line(currency: 'USD', quantity: 1, cost: 50, margin: 0.3),
    ]);

    expect(find.text('SUBTOTAL CLP'), findsOneWidget);
    expect(find.text('SUBTOTAL USD'), findsOneWidget);
    // El peso se escribe como en el resto del ERP —con signo y separador de
    // miles—, y la moneda extranjera con su código y dos decimales. Antes esto
    // decía `CLP 20000`: la cifra más importante del plan era la única del
    // módulo sin separador de miles.
    expect(find.text('\$20.000'), findsOneWidget);
    expect(find.text('USD 50.00'), findsOneWidget);
    expect(find.text('no se suma'), findsOneWidget);
  });

  testWidgets('sin precio de venta vigente el margen es «sin base», no cero',
      (tester) async {
    await _pump(tester, [
      _line(currency: 'CLP', quantity: 1, cost: 5000),
    ]);

    expect(find.text('sin base'), findsOneWidget);
    expect(find.text('0.0 %'), findsNothing);
  });

  testWidgets('el margen se pondera por valor y dice sobre cuántas líneas',
      (tester) async {
    await _pump(tester, [
      _line(currency: 'CLP', quantity: 1, cost: 1000, margin: 0.5),
      _line(currency: 'CLP', quantity: 1, cost: 1000, needId: 'need-2'),
    ]);

    expect(find.text('50.0 %'), findsOneWidget);
    expect(find.text('sobre 1 de 2 líneas'), findsOneWidget);
  });

  testWidgets('preparar confirma inline y no compra nada', (tester) async {
    await _pump(
      tester,
      [_line(currency: 'CLP', quantity: 3, cost: 1000, margin: 0.2)],
      missing: 2,
    );

    await tester.tap(find.byKey(const ValueKey('plan-prepare-documents')));
    await tester.pumpAndSettle();

    // Paso inline, nunca un diálogo con velo.
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('plan-close-confirm')), findsOneWidget);
    expect(find.text('PROVEEDORES'), findsOneWidget);
    expect(find.text('LÍNEAS'), findsOneWidget);
    expect(find.text('QUEDA FUERA'), findsOneWidget);
    expect(find.text('2'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('plan-close-confirm-action')));
    await tester.pumpAndSettle();

    expect(find.text('Listo · no se creó ninguna compra'), findsOneWidget);
  });

  testWidgets('sin líneas no se puede preparar', (tester) async {
    await _pump(tester, const []);

    // El toque no abre el paso de confirmación: la acción está apagada.
    await tester.tap(
      find.byKey(const ValueKey('plan-prepare-documents')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('plan-close-confirm')), findsNothing);
  });
}
