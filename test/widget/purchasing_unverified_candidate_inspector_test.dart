import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Un candidato del grupo sin verificar se mira, no se compromete.**
///
/// El servidor los devuelve en su propio grupo, pero el inspector no lo sabía y
/// les ofrecía `Agregar al plan` y `Elegir producto` igual que a los
/// comprobados. Abrirlo es legítimo —para eso está—; declararlo la respuesta del
/// taller con un botón, no.
PurchaseCandidate _candidate() => PurchaseCandidate.fromJson(
      <String, dynamic>{
        'candidateId': 'cand-1',
        'rank': 1,
        'productId': 'prod-1',
        'productName': 'PASTILLA AVID METALICA',
        'supplierId': 'sup-1',
        'supplierName': 'RBX',
        'unitCostNet': 5000,
        'currency': 'CLP',
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool comprobado,
  bool identidadConfirmada = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1455, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: CandidateInspectorPanel(
        candidate: _candidate(),
        quantity: 6,
        unitLabel: 'juego',
        onClose: () {},
        onOpenSupplier: () {},
        adding: false,
        alreadyInPlan: false,
        // Es lo que hace el workspace: sin comprobar, no hay atajo.
        onAddToPlan: comprobado ? () {} : null,
        onChooseProduct: comprobado && !identidadConfirmada ? () {} : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('sin comprobar: ni elegir producto ni agregar al plan',
      (tester) async {
    await _pump(tester, comprobado: false);
    expect(find.byKey(const ValueKey('add-candidate-to-plan')), findsNothing);
    expect(find.byKey(const ValueKey('choose-family-product')), findsNothing);
  });

  testWidgets('pero sigue visible y dice por qué', (tester) async {
    await _pump(tester, comprobado: false);
    expect(find.text('PASTILLA AVID METALICA'), findsOneWidget,
        reason: 'mirarlo es legítimo: para eso está el inspector');
    expect(find.byKey(const ValueKey('candidate-unverified-note')),
        findsOneWidget);
    expect(find.text('Sin verificar contra los criterios'), findsOneWidget,
        reason: 'un botón ausente sin explicación se lee como un defecto');
    expect(find.byKey(const ValueKey('open-supplier-from-inspector')),
        findsOneWidget,
        reason: 'y abrir el proveedor para mirarlo sigue disponible');
  });

  testWidgets('comprobado conserva su acción', (tester) async {
    await _pump(tester, comprobado: true);
    expect(find.byKey(const ValueKey('add-candidate-to-plan')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('candidate-unverified-note')), findsNothing);
  });

  testWidgets('comprobado en el carril familia ofrece elegir producto',
      (tester) async {
    await _pump(tester, comprobado: true, identidadConfirmada: false);
    expect(find.byKey(const ValueKey('choose-family-product')), findsOneWidget);
  });
}
