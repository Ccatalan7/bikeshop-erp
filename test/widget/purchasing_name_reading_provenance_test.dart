import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';

/// La procedencia tiene que llegar hasta la palabra que ve el operador.
///
/// Desde que una lectura del nombre cuenta como prueba, una fila puede estar
/// completa **sin que exista ninguna ficha**. «Cumple los criterios según la
/// ficha» sería falso justo en el caso nuevo, y una frase falsa en la fila que
/// el operador va a elegir es peor que no decir nada.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('la frase dice de dónde salió la evidencia, no «la ficha» siempre', () {
    expect(
      supplyEvidenceProvenanceLabel(const <Map<String, dynamic>>[
        <String, dynamic>{'field': 'a', 'source': 'product_spec'},
        <String, dynamic>{'field': 'b', 'source': 'product_spec'},
      ]),
      'según la ficha',
    );
    expect(
      supplyEvidenceProvenanceLabel(const <Map<String, dynamic>>[
        <String, dynamic>{'field': 'a', 'source': 'name_reading'},
      ]),
      'según el nombre del producto, comprobado',
      reason: 'no es la ficha del taller: es el nombre, leído y comprobado',
    );
    expect(
      supplyEvidenceProvenanceLabel(const <Map<String, dynamic>>[
        <String, dynamic>{'field': 'a', 'source': 'identity_fallback'},
      ]),
      'según la identidad del producto',
    );
    expect(
      supplyEvidenceProvenanceLabel(const <Map<String, dynamic>>[
        <String, dynamic>{'field': 'a', 'source': 'name_reading'},
        <String, dynamic>{'field': 'b', 'source': 'identity_fallback'},
      ]),
      'según la evidencia comprobada',
      reason: 'mezclada, la frase no puede atribuirla a una sola fuente',
    );
    expect(
      supplyEvidenceProvenanceLabel(const <Map<String, dynamic>>[
        <String, dynamic>{'field': 'a', 'source': 'unresolved'},
      ]),
      isNull,
      reason: 'sin nada probado no hay procedencia que nombrar',
    );
  });

  const option = SupplyStockOption(
    productId: '11111111-1111-4111-8111-111111111111',
    name: 'Cambio Shimano 9V. RD-M370-L SGS Altus Negro',
    sku: 'RD-M370',
    availableToPromise: 3,
    coverage: 'full',
    matchState: 'strong',
    evidenceComplete: true,
    blocksExternal: true,
    matchDetail: <Map<String, dynamic>>[
      <String, dynamic>{
        'field': 'drivetrain_primary_ecosystem',
        'source': 'name_reading',
      },
      <String, dynamic>{
        'field': 'derailleur_cage_length',
        'source': 'name_reading',
      },
    ],
  );

  const resolution = SupplyStockResolution(
    needId: '22222222-2222-4222-8222-222222222222',
    needVersion: 1,
    revisionNo: 1,
    quantity: 1,
    unit: 'unidad',
    lane: 'family',
    status: 'ok',
    coverage: 'full',
    blocksExternal: true,
    items: <SupplyStockOption>[option],
    counts: SupplyStockCounts(
      full: 1,
      partial: 0,
      none: 0,
      eligible: 1,
      reviewed: 1,
      unverified: 0,
    ),
  );

  // El teléfono usa otra tarjeta, y ahí la procedencia se perdía: la misma
  // mentira con menos ancho.
  for (final ancho in <double>[1455, 834, 390]) {
    testWidgets(
      'una fila comprobada por el nombre no dice «según la ficha» a $ancho',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(ancho, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: FamilyStockOptions(
              resolution: resolution,
              onChooseProduct: (_) {},
              onCompareProviders: () {},
              busy: false,
              compact: ancho < 900,
            ),
          ),
        ));
        await tester.pumpAndSettle();

        final textos = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.data ?? '')
            .join(' | ');
        expect(textos, contains('cumple los criterios'));
        expect(textos, contains('según el nombre del producto, comprobado'));
        expect(textos, isNot(contains('cumple los criterios según la ficha')),
            reason: 'este producto no tiene ficha: su evidencia es su nombre');
      },
    );
  }

  // La tarjeta compacta no puede decir dos veces el mismo veredicto: la nota
  // que reemplaza al botón y la línea de evidencia decían lo mismo, una encima
  // de la otra.
  testWidgets('la tarjeta de teléfono dice el veredicto una sola vez',
      (tester) async {
    const sinVerificar = SupplyStockOption(
      productId: '33333333-3333-4333-8333-333333333333',
      name: 'PATIN (PAR) RUTA ALONGHA PRIMO',
      sku: '19267',
      availableToPromise: 8,
      coverage: 'full',
      matchState: 'unverified',
      evidenceComplete: false,
      blocksExternal: false,
      matchDetail: <Map<String, dynamic>>[
        <String, dynamic>{'field': 'compound_type', 'source': 'unresolved'},
      ],
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 928);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: FamilyStockOptions(
          resolution: const SupplyStockResolution(
            needId: '44444444-4444-4444-8444-444444444444',
            needVersion: 1,
            revisionNo: 1,
            quantity: 6,
            unit: 'juego',
            lane: 'family',
            status: 'ok',
            coverage: 'full',
            blocksExternal: false,
            items: <SupplyStockOption>[sinVerificar],
            counts: SupplyStockCounts(
              full: 1,
              partial: 0,
              none: 0,
              eligible: 0,
              reviewed: 1,
              unverified: 1,
            ),
          ),
          onChooseProduct: (_) {},
          onCompareProviders: () {},
          busy: false,
          compact: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final veredictos = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        // Sólo los veredictos de fila: el subtítulo del bloque cuenta el
        // universo revisado y es otra frase con otro dueño.
        .where((texto) =>
            texto == 'no se pudo verificar contra los criterios' ||
            texto == 'sin verificar contra los criterios')
        .toList();
    expect(veredictos, hasLength(1),
        reason: 'una vez, donde estaría el botón: $veredictos');
    // Y la evidencia útil sigue estando.
    final todo = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join(' | ');
    expect(todo, contains('cubre la necesidad completa'));
  });
}
