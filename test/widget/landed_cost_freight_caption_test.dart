import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «incluye flete» bajo el costo aterrizado (frames 04/05, NOTES §85-87).
///
/// **Por qué importa y no es decorativo.** Sin esa línea el número se lee como
/// precio de lista: el operador le suma el flete de cabeza y descarta al
/// proveedor equivocado. Con ella sabe que el costo ya lo trae.
///
/// **Y por qué es condicional.** El módulo ya distingue «flete clasificado» de
/// «flete sin clasificar» en el desglose. Afirmar «incluye flete» cuando la
/// evidencia no alcanza sería la clase de frase que hace desconfiar de todas
/// las demás, así que se usa la misma señal.

PurchaseCandidate candidate({String? freightEvidence}) =>
    PurchaseCandidate.fromJson(<String, dynamic>{
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
      if (freightEvidence != null) 'freightEvidence': freightEvidence,
    });

Future<void> pumpCard(WidgetTester tester, PurchaseCandidate value) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: ProviderCandidateCard(
            candidate: value,
            selected: false,
            onSelect: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('con flete clasificado el costo lo dice', (tester) async {
    await pumpCard(tester, candidate(freightEvidence: 'complete'));

    expect(find.text('incluye flete'), findsOneWidget);
    expect(find.text('flete sin clasificar'), findsNothing);
  });

  testWidgets('sin evidencia de flete no se afirma que lo incluye',
      (tester) async {
    await pumpCard(tester, candidate(freightEvidence: 'partial'));

    expect(find.text('incluye flete'), findsNothing);
    expect(find.text('flete sin clasificar'), findsOneWidget);
  });

  testWidgets('sin el dato tampoco se afirma', (tester) async {
    await pumpCard(tester, candidate());

    expect(find.text('incluye flete'), findsNothing);
    expect(find.text('flete sin clasificar'), findsOneWidget);
  });
}
