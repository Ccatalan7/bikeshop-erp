import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El `»` de la cabecera del inspector (frames 04/05 y 17).
///
/// **El hueco.** El contrato pide **dos** controles en esa cabecera —«botón `»`
/// (colapsar) + `×` (cerrar)», NOTES §100— y sólo estaba el segundo. Sin `»`,
/// la única forma de devolverle ancho a la lista era cerrar el detalle y perder
/// el candidato abierto: eso es exactamente lo que colapsar evita.
///
/// **Por qué condicional.** Sólo el split pane de escritorio tiene ancho que
/// ceder. En la hoja de teléfono un `»` no tendría a quién dárselo, y un
/// control que no hace nada es peor que no tenerlo.

PurchaseCandidate candidate() => PurchaseCandidate.fromJson(<String, dynamic>{
      'candidateId': 'cand-1',
      'productId': 'prod-1',
      'productName': 'Cámara Maxxis 29',
      'supplierName': 'TeknoBike',
      'currency': 'CLP',
      'latestLandedUnitCostNet': 3181.45,
      'projectedGrossMarginRatio': 0.495,
      'evidenceQuality': 'complete',
      'evidenceAgeDays': 79,
      'purchaseCount': 3,
      'supplierAvailability': 'unverified',
    });

Future<void> pumpPanel(
  WidgetTester tester, {
  VoidCallback? onToggleCollapsed,
  bool collapsed = false,
  ValueChanged<int>? onQuantityChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: CandidateInspectorPanel(
            candidate: candidate(),
            quantity: 4,
            unitLabel: 'unidades',
            onClose: () {},
            onAddToPlan: () {},
            onOpenSupplier: null,
            adding: false,
            alreadyInPlan: false,
            onToggleCollapsed: onToggleCollapsed,
            collapsed: collapsed,
            onQuantityChanged: onQuantityChanged,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  /// `frames[single-inspector].blocks.pie` del spec: «cantidad **con stepper**
  /// + total + Abrir proveedor + Agregar al plan». El pie mostraba el total de
  /// una cantidad que sólo se podía cambiar **después**, en la línea del plan:
  /// para llevar tres de algo había que agregar la cantidad de la necesidad y
  /// corregirla en el paso siguiente.
  testWidgets('el pie deja elegir la cantidad antes de agregar',
      (tester) async {
    final chosen = <int>[];
    await pumpPanel(tester, onQuantityChanged: chosen.add);

    final plus = find.byKey(const ValueKey('inspector-quantity-increase'));
    expect(plus, findsOneWidget);
    await tester.tap(plus);
    await tester.pump();
    expect(chosen, [5], reason: 'parte de las 4 de la necesidad y sube a 5');
  });

  testWidgets('sin control de cantidad el pie queda como estaba',
      (tester) async {
    await pumpPanel(tester);

    expect(
      find.byKey(const ValueKey('inspector-quantity-increase')),
      findsNothing,
    );
  });

  testWidgets('en el split pane la cabecera lleva los dos controles',
      (tester) async {
    var toggled = 0;
    await pumpPanel(tester, onToggleCollapsed: () => toggled++);

    final collapse = find.byKey(const ValueKey('collapse-candidate-inspector'));
    expect(collapse, findsOneWidget);
    expect(
      find.byKey(const ValueKey('close-candidate-inspector')),
      findsOneWidget,
      reason: 'colapsar no reemplaza a cerrar: son dos cosas distintas',
    );

    await tester.tap(collapse);
    await tester.pump();
    expect(toggled, 1);
  });

  testWidgets('el rótulo dice hacia dónde va, no dónde está', (tester) async {
    await pumpPanel(tester, onToggleCollapsed: () {}, collapsed: true);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('collapse-candidate-inspector')),
    );
    expect(button.tooltip, 'Ampliar detalle');
  });

  testWidgets('sin ancho que ceder no se ofrece el control', (tester) async {
    // La hoja de teléfono: el panel llega sin `onToggleCollapsed`.
    await pumpPanel(tester);

    expect(
      find.byKey(const ValueKey('collapse-candidate-inspector')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('close-candidate-inspector')),
      findsOneWidget,
      reason: 'la salida sigue estando en toda talla',
    );
  });
}
