import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Superficies publicadas en `handoff-t23` que no tenían cobertura.
///
/// Cada grupo cita el frame del que sale la composición y afirma la palabra o
/// la conducta, no un ancho: la fuente de las pruebas mide distinto que la real
/// y una aserción de píxeles miente.
Future<void> _pump(WidgetTester tester, Widget child, {double width = 900}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      // Los roles semánticos del módulo viven en el tema real: sin él las
      // superficies que leen `VinabikeThemeRoles` no llegan a construirse.
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: child),
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

  // Un tap que no alcanza a su objetivo es un fallo, no un aviso: si el centro
  // del finder no es hit-testable la prueba estaba pasando sin tocar nada.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  group('frame 09 · análisis parcial', () {
    testWidgets('dice el avance en palabras y ofrece continuar',
        (tester) async {
      var continued = 0;
      await _pump(
        tester,
        PartialAnalysisNotice(
          evaluated: 4,
          total: 6,
          pendingLabels: const ['Andes Industrial', 'Bicicletas del Sur'],
          onContinue: () => continued++,
        ),
      );

      expect(find.textContaining('Evaluamos 4 de 6 opciones'), findsOneWidget);
      expect(
        find.textContaining('Faltan Andes Industrial y Bicicletas del Sur'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('continue-partial-analysis')));
      expect(continued, 1);
    });

    testWidgets('las rondas y los KiB viven detrás del disclosure',
        (tester) async {
      await _pump(
        tester,
        PartialAnalysisNotice(
          evaluated: 4,
          total: 6,
          pendingLabels: const ['Andes Industrial'],
          onContinue: () {},
          technicalDetail: '2 rondas · 38 KiB de evidencia reutilizada',
        ),
      );

      // El mensaje principal no arrastra jerga interna.
      expect(find.textContaining('KiB'), findsNothing);
      await tester.tap(find.text('Detalle técnico'));
      await tester.pumpAndSettle();
      expect(find.textContaining('KiB'), findsOneWidget);
    });
  });

  group('frame 10 · ninguna opción visible', () {
    testWidgets('explica la causa y separa quitar filtros de incluir dudosas',
        (tester) async {
      var cleared = 0;
      var included = 0;
      await _pump(
        tester,
        NoMatchSurface(
          causeSentence:
              'Existen 6 opciones, pero los filtros activos las esconden todas.',
          onClearFilters: () => cleared++,
          onIncludeUnconfirmed: () => included++,
          perCandidateExplanations: const [
            'Ralco Explorer — gama económica desmarcada',
          ],
        ),
      );

      expect(
        find.text('Ninguna opción cumple todos los filtros'),
        findsOneWidget,
      );
      // Sin isla: la superficie ocupa el ancho de la región de resultados.
      expect(find.byType(Card), findsNothing);
      await tester.tap(find.byKey(const ValueKey('clear-provider-filters')));
      await tester.tap(
        find.byKey(const ValueKey('include-unconfirmed-compatibility')),
      );
      expect(cleared, 1);
      expect(included, 1);

      await tester.tap(find.text('Qué filtro oculta cada candidato'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('gama económica desmarcada'),
        findsOneWidget,
      );
    });
  });

  group('frames 07/18/21/24 · cabecera del plan', () {
    testWidgets('rotula el borrador y sus dos salidas', (tester) async {
      var back = 0;
      var local = 0;
      await _pump(
        tester,
        PlanDraftHeader(
          lineCount: 3,
          compact: false,
          onBackToCompare: () => back++,
          onRegisterLocalPurchase: () => local++,
        ),
      );

      expect(find.text('Plan borrador'), findsOneWidget);
      expect(find.text('3 líneas · nada comprado'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plan-back-to-compare')));
      await tester.tap(
        find.byKey(const ValueKey('plan-register-local-purchase')),
      );
      expect(back, 1);
      expect(local, 1);
    });

    testWidgets('no desborda en el ancho mínimo del panel', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 300,
          child: PlanDraftHeader(
            lineCount: 1,
            compact: true,
            onBackToCompare: () {},
            onRegisterLocalPurchase: () {},
          ),
        ),
        width: 390,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('1 línea · nada comprado'), findsOneWidget);
    });

    testWidgets('la evidencia del grupo es texto, no cápsula', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            PlanGroupEvidenceText(complete: true),
            PlanGroupEvidenceText(complete: false),
          ],
        ),
      );
      expect(find.text('evidencia completa'), findsOneWidget);
      expect(find.text('evidencia parcial'), findsOneWidget);
    });
  });

  group('frames 24/28 · stepper de cantidad', () {
    testWidgets('respeta mínimo y máximo y anuncia su valor', (tester) async {
      final values = <int>[];
      await _pump(
        tester,
        PurchaseQuantityStepper(
          value: 1,
          min: 1,
          max: 2,
          unitLabel: 'un',
          onChanged: values.add,
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('un'), findsOneWidget);
      // En el mínimo, restar está deshabilitado; sumar sí actúa.
      await tester.tap(find.byTooltip('Ya está en el mínimo'));
      expect(values, isEmpty);
      await tester.tap(find.byTooltip('Agregar una unidad'));
      expect(values, [2]);
    });
  });

  group('frame 20 · pestañas de la canasta', () {
    testWidgets('cambia de subestado sin perder el otro', (tester) async {
      var section = BasketSection.lines;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => BasketSectionTabs(
                active: section,
                onChanged: (value) => setState(() => section = value),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Líneas'), findsOneWidget);
      expect(find.text('Escenarios'), findsOneWidget);
      await tester.tap(find.text('Escenarios'));
      await tester.pump();
      expect(section, BasketSection.scenarios);
    });
  });

  group('frame 28 · líneas de la petición', () {
    testWidgets('una línea sin precisión muestra la causa y su salida',
        (tester) async {
      BasketRequestLine? resolved;
      await _pump(
        tester,
        BasketRequestLinesCard(
          compact: false,
          lines: const [
            BasketRequestLine(
              id: 'l1',
              name: 'Piñones (cassette 11v)',
              description: 'sin SKU exacto: familia y gama históricas',
              quantity: 4,
              unitLabel: 'un',
            ),
            BasketRequestLine(
              id: 'l2',
              name: 'Rayos',
              description: 'largo por confirmar según aro y maza',
              quantity: 144,
              unitLabel: 'un',
              precisionBlocker: 'el largo depende del aro y la maza',
            ),
          ],
          onChangeQuantity: (_, __) {},
          onRemoveLine: (_) {},
          onAddLine: () {},
          onResolvePrecision: (line) => resolved = line,
        ),
      );

      expect(find.text('Líneas de la petición'), findsOneWidget);
      expect(find.text('Agregar línea'), findsOneWidget);
      expect(
        find.text('Requiere precisión · el largo depende del aro y la maza'),
        findsOneWidget,
      );
      // La línea con SKU resuelto no arrastra la advertencia.
      expect(find.textContaining('Requiere precisión'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('basket-resolve-l2')));
      expect(resolved?.id, 'l2');
    });

    testWidgets('sin líneas lo dice en texto, sin isla', (tester) async {
      await _pump(
        tester,
        BasketRequestLinesCard(
          compact: true,
          lines: const [],
          onChangeQuantity: (_, __) {},
          onRemoveLine: (_) {},
          onAddLine: () {},
          onResolvePrecision: (_) {},
        ),
        width: 390,
      );
      expect(find.text('La canasta todavía no tiene líneas.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('frame 20/28 · la canasta conserva el otro subestado', () {
    testWidgets('cambiar de pestaña no descarta cantidades ni selección',
        (tester) async {
      var section = BasketSection.lines;
      var quantity = 4;
      String? selectedScenario;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  BasketSectionTabs(
                    active: section,
                    onChanged: (value) => setState(() => section = value),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: section == BasketSection.lines
                          ? BasketRequestLinesCard(
                              compact: false,
                              lines: [
                                BasketRequestLine(
                                  id: 'l1',
                                  name: 'Piñones',
                                  description: 'familia histórica',
                                  quantity: quantity,
                                  unitLabel: 'un',
                                ),
                              ],
                              onChangeQuantity: (_, value) =>
                                  setState(() => quantity = value),
                              onRemoveLine: (_) {},
                              onAddLine: () {},
                              onResolvePrecision: (_) {},
                            )
                          : TextButton(
                              key: const ValueKey('pick-scenario'),
                              onPressed: () =>
                                  setState(() => selectedScenario = 'best'),
                              child: const Text('Mejor equilibrio'),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Se sube la cantidad en Líneas…
      await tester.tap(find.byTooltip('Agregar una unidad'));
      await tester.pump();
      expect(quantity, 5);

      // …se elige escenario…
      await tester.tap(find.text('Escenarios'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pick-scenario')));
      await tester.pump();
      expect(selectedScenario, 'best');

      // …y al volver la cantidad sigue ahí, con el escenario intacto.
      await tester.tap(find.text('Líneas'));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(PurchaseQuantityStepper),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
      expect(selectedScenario, 'best');
      expect(tester.takeException(), isNull);
    });
  });

  group('frames 03/16/26 · controles de resultados', () {
    testWidgets(
      'en ancho el perfil es un dato del servidor y la vista un control',
      (tester) async {
        // **El perfil dejó de ser un menú.** La lectura externa lo toma de la
        // revisión que gobierna la necesidad, así que elegir otro acá no
        // cambiaba nada del backend: el resultado llegaba idéntico y el
        // control prometía algo que no podía cumplir.
        await _pump(
          tester,
          ProviderResultControls(
            compact: false,
            profileLabel: 'Prioridad · Equilibrado',
            viewValue: 'auto',
            viewOptions: const {'auto': 'Automática', 'compact': 'Esenciales'},
            onViewChanged: (_) {},
          ),
        );

        expect(find.text('Prioridad · Equilibrado'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('server-ranking-profile')),
          findsOneWidget,
        );
        expect(find.text('Vista'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('provider-profile-menu')),
          findsNothing,
        );
      },
    );

    testWidgets('en teléfono queda el dato y un solo control', (tester) async {
      await _pump(
        tester,
        ProviderResultControls(
          compact: true,
          profileLabel: 'Prioridad · Equilibrado',
          viewValue: 'auto',
          viewOptions: const {'auto': 'Automática'},
          onViewChanged: (_) {},
        ),
        width: 390,
      );

      expect(find.text('Prioridad · Equilibrado'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('provider-sort-and-filters')),
        findsOneWidget,
      );
    });
  });

  group('cumplimiento técnico · el veredicto sale de la ficha', () {
    SupplyExternalCandidate candidate(String matchState, String evidence) =>
        SupplyExternalCandidate.fromJson(<String, dynamic>{
          'candidateId': 'c-$matchState',
          'rank': 1,
          'baseRank': 1,
          'overallRank': 1,
          'rankingScore': 0.5,
          'baseRankingScore': 0.5,
          'group': matchState == 'unverified' ? 'unverified' : 'actionable',
          'matchState': matchState,
          'productId': 'p-1',
          'productName': 'Cadena',
          'supplierName': 'Andes',
          'supplierAvailability': 'unverified',
          'evidenceQuality': evidence,
          'purchaseCount': 3,
          'evidenceAgeDays': 10,
        });

    testWidgets('un match débil COINCIDE por nombre, no «cumple»',
        (tester) async {
      // «Cumple por nombre» sobreafirmaba: la ficha no lo dice, sólo el
      // nombre se parece.
      await _pump(
        tester,
        ComplianceLabel(
            compliance: complianceOf(candidate('weak', 'complete'))),
      );

      expect(find.text('Coincide por nombre'), findsOneWidget);
      expect(find.text('Cumple por nombre'), findsNothing);
      expect(find.text('Cumple'), findsNothing);
    });

    testWidgets('la factura completa no convierte un sin verificar en «Cumple»',
        (tester) async {
      await _pump(
        tester,
        ComplianceLabel(
          compliance: complianceOf(candidate('unverified', 'complete')),
        ),
      );

      expect(find.text('Sin verificar'), findsOneWidget);
      expect(find.text('Cumple'), findsNothing);
    });

    testWidgets('y una factura débil no rebaja lo que la ficha confirma',
        (tester) async {
      await _pump(
        tester,
        ComplianceLabel(compliance: complianceOf(candidate('strong', 'weak'))),
      );

      expect(find.text('Cumple'), findsOneWidget);
      expect(find.text('Evidencia débil'), findsNothing);
    });
  });
}
