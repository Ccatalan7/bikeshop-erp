import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **La tabla se mide contra el ancho que hay, no contra una constante.**
///
/// La primera versión reservaba 172 px fijos para las acciones rotuladas:
/// «Confirmado» y «Confirmar hoy» se pisaban y la fila se salía del panel. El
/// dueño lo vio en la app antes que cualquier prueba.
///
/// Se afirma **qué se suelta y en qué orden**, nunca un ancho: la fuente de las
/// pruebas mide distinto que la real, así que un número de píxeles mentiría.
/// El desborde no se afirma — el framework lo convierte en excepción y la
/// prueba muere sola.
SupplierConcentration _supplier({
  required String id,
  required String name,
  String? website,
}) {
  return SupplierConcentration(
    supplierId: id,
    supplierName: name,
    spendSharePercent: 42,
    purchaseLines: 4,
    purchaseInvoices: 3,
    distinctProducts: 2,
    evidencePurchaseLines: 9,
    evidenceSuppliers: 4,
    scopeRelaxed: false,
    droppedWords: null,
    droppedFilters: null,
    averageLandedUnitCostNet: 2895,
    // Relativa a la corrida: una fecha absoluta en una fixture se pudre sola
    // cuando pasa el calendario.
    lastPurchaseAt: DateTime.now().subtract(const Duration(days: 92)),
    daysSinceLastPurchase: 92,
    brands: 'Maxxis',
    gamaMix: null,
    supplierWebsite: website,
    supplierCity: 'Santiago',
    salesRepName: null,
    salesRepPhone: null,
    salesRepEmail: null,
    hasPortalAccount: website != null,
  );
}

Future<void> _pump(
  WidgetTester tester,
  double width, {
  bool includeExact = false,
  String? loginSupplierId,
  SupplierNeedPortalSearchSnapshot? portalSnapshot,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  String? expandedPortalSupplierId;
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => SupplierConcentrationTable(
              exactProducts: includeExact
                  ? <SupplyStockOption>[
                      SupplyStockOption.fromJson(<String, dynamic>{
                        'productId': 'p-exact',
                        'name': 'Cámara aro 29 Presta 60 mm',
                        'sku': '160-4',
                        'atp': 0,
                        'coverage': 'none',
                        'matchState': 'strong',
                        'blocksExternal': false,
                        'evidenceState': 'catalog_assignment',
                        'supplierId': 's-derman',
                        'supplierName': 'Derman',
                        'purchaseCount': 0,
                        'availabilityFresh': false,
                        'catalogCostNet': 3396,
                        'catalogCostCurrency': 'CLP',
                        'supplierCode': '160-4',
                        'automaticAvailabilityEnabled': false,
                      }),
                    ]
                  : const <SupplyStockOption>[],
              plannedProductIds: const <String>{},
              onAddExactProduct: (_) {},
              onCheckExactProduct: (_) {},
              onOpenExactSupplier: (_) {},
              report: SupplierConcentrationReport(
                items: [
                  _supplier(
                    id: 's1',
                    name: 'TeknoBike',
                    website: 'https://teknobike.cl',
                  ),
                  // Sin sitio: es la fila que antes corría sus acciones y rompía
                  // la alineación de la columna.
                  _supplier(id: 's2', name: 'Vittal'),
                ],
                hasMore: false,
              ),
              confirmedLabelFor: (id) =>
                  id == 's1' ? portalSnapshot?.rowLabel ?? '12 de 12' : null,
              confirmedAgeFor: (id) => id == 's1'
                  ? portalSnapshot?.ageLabel ?? 'hace 2 horas'
                  : null,
              confirmedDetailFor: (id) => id == 's1'
                  ? portalSnapshot?.detailLabel ??
                      '12 de 12 disponibles hace 2 horas'
                  : null,
              portalSearchFor: (id) => id == 's1' ? portalSnapshot : null,
              expandedPortalSupplierId: expandedPortalSupplierId,
              onTogglePortalResults: (supplier) => setState(() {
                expandedPortalSupplierId =
                    expandedPortalSupplierId == supplier.supplierId
                        ? null
                        : supplier.supplierId;
              }),
              canSearchNeedFor: (_) => true,
              needsLoginFor: (id) => id == loginSupplierId,
              checkProgress: null,
              busySupplierId: null,
              expandedSupplierId: null,
              onConfirm: (_) {},
              onExplain: (_) {},
              onOpenPortal: (_) {},
              onOpenSupplier: (_) {},
              basis: PurchaseCostBasis.sinFlete,
              onBasisChanged: (_) {},
              evidencePanelBuilder: (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
}

SupplierNeedPortalSearchSnapshot _tenPortalMatches() {
  return SupplierNeedPortalSearchSnapshot(
    query: 'camara 700',
    status: SupplierNeedPortalSearchStatus.completed,
    checkedAt: DateTime.now(),
    // Una lectura sólo se muestra vigente si responde la revisión actual;
    // sin estas dos la fila se rotula «Ficha anterior», que es el contrato
    // nuevo funcionando y no un defecto de la tabla.
    searchRevisionNo: 1,
    currentRevisionNo: 1,
    matches: List<SupplierNeedPortalMatch>.generate(
      10,
      (index) => SupplierNeedPortalMatch(
        candidate: SupplierPortalCatalogCandidate(
          code: 'RBX-${index + 1}',
          name: index == 0
              ? 'CÁMARA 700 X 18/25C V/AUTO 60MM'
              : index == 9
                  ? 'CÁMARA 700 X 35/43C V/FRANCESA 48MM'
                  : 'CÁMARA 700 OPCIÓN ${index + 1}',
          brand: 'Chaoyang',
          priceNet: 2130 + index.toDouble(),
        ),
        state: SupplierNeedMatchState.exact,
        provenFields: const <String>['wheel_size'],
        missingFields: const <String>[],
        conflictingFields: const <String>[],
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('las columnas se ajustan al ancho que hay', () {
    testWidgets('ancho completo: las cinco columnas y la orden con rótulo',
        (tester) async {
      await _pump(tester, 1400);

      expect(find.text('EVIDENCIA'), findsOneWidget);
      expect(find.text('RESULTADO PORTAL'), findsOneWidget);
      // Con espacio, la orden se lee: el rótulo dice qué hace sin hover.
      expect(find.text('Buscar necesidad'), findsNWidgets(2));
      expect(find.text('Por qué'), findsNWidgets(2));
    });

    testWidgets('una sesión vencida ofrece recuperarla antes del login visible',
        (tester) async {
      await _pump(tester, 1400, loginSupplierId: 's1');

      expect(find.text('Recuperar sesión'), findsOneWidget);
      expect(find.text('Buscar necesidad'), findsOneWidget);
    });

    testWidgets('al estrecharse, la orden pasa a icono antes de perder un dato',
        (tester) async {
      await _pump(tester, 900);

      // Ningún dato se fue todavía: lo primero que cede es el rótulo, no la
      // columna, porque los números son lo que la tabla existe para comparar.
      expect(find.text('EVIDENCIA'), findsOneWidget);
      expect(find.text('RESULTADO PORTAL'), findsNothing);
      expect(find.text('Buscar necesidad'), findsNothing);

      // El tooltip nombra al proveedor: cuatro iconos iguales no identifican su
      // sujeto, ni para un lector de pantalla ni para esta prueba.
      expect(
        find.byTooltip('Buscar esta necesidad en TeknoBike'),
        findsOneWidget,
      );
      expect(find.byTooltip('Por qué Vittal quedó acá'), findsOneWidget);
    });

    testWidgets('más angosto: cae el resultado, que es lo menos comparable',
        (tester) async {
      await _pump(tester, 700);

      expect(find.text('EVIDENCIA'), findsNothing);
      expect(find.text('RESULTADO PORTAL'), findsNothing);
      expect(
          find.byTooltip('Buscar esta necesidad en TeknoBike'), findsOneWidget);
    });

    testWidgets('en compacto queda el ranking y la orden, nunca un desborde',
        (tester) async {
      await _pump(tester, 520);

      expect(find.text('CALCE'), findsNothing);
      expect(find.text('COSTO UNITARIO'), findsNothing);
      expect(find.text('PARECIDO · NO PRUEBA EL CALCE EXACTO'), findsNothing);
      expect(find.text('COMPRADO ANTES · MISMO ALCANCE'), findsOneWidget);
      expect(find.text('Buscar necesidad'), findsNWidgets(2));
    });

    testWidgets('en compacto el exacto sigue primero y explica su procedencia',
        (tester) async {
      await _pump(tester, 390, includeExact: true);

      expect(
        find.text('EXACTO · CUMPLE LA FICHA TÉCNICA PEDIDA'),
        findsOneWidget,
      );
      expect(find.text('Derman'), findsOneWidget);
      expect(find.textContaining(r'$3.396'), findsOneWidget);
      expect(find.text('Llevar al plan'), findsOneWidget);
      expect(
        find.byTooltip(
          'Derman todavía no tiene consulta automática para este producto',
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Derman')).dy,
        lessThan(tester.getTopLeft(find.text('TeknoBike')).dy),
      );
    });

    testWidgets('el proveedor sin sitio conserva el hueco del icono',
        (tester) async {
      await _pump(tester, 1400);

      // Un solo enlace: el de TeknoBike. Si el hueco de Vittal se colapsara,
      // sus acciones correrían y la columna dejaría de alinear.
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final teknoBike = tester.getTopLeft(find.text('Buscar necesidad').at(0));
      final vittal = tester.getTopLeft(find.text('Buscar necesidad').at(1));
      expect(teknoBike.dx, vittal.dx);
    });

    testWidgets('los resultados del portal se despliegan dentro del proveedor',
        (tester) async {
      await _pump(tester, 1400, portalSnapshot: _tenPortalMatches());

      expect(find.text('10 exactos'), findsOneWidget);
      expect(find.text('Ver 10 opciones'), findsOneWidget);
      expect(find.text('CÁMARA 700 X 18/25C V/AUTO 60MM'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('portal-results-toggle-s1')));
      await tester.pumpAndSettle();

      expect(find.text('Resultados en TeknoBike'), findsOneWidget);
      expect(find.text('CÁMARA 700 X 18/25C V/AUTO 60MM'), findsOneWidget);
      expect(find.text('CÁMARA 700 X 35/43C V/FRANCESA 48MM'), findsOneWidget);
      expect(find.text('Ocultar opciones'), findsOneWidget);
      expect(
          find.textContaining('El portal no publica unidades'), findsOneWidget);
    });

    testWidgets('en compacto las opciones conservan lectura vertical',
        (tester) async {
      await _pump(tester, 390, portalSnapshot: _tenPortalMatches());

      await tester.tap(find.byKey(const ValueKey('portal-results-toggle-s1')));
      await tester.pumpAndSettle();

      expect(find.text('Resultados en TeknoBike'), findsOneWidget);
      expect(find.text('RBX-1 · Chaoyang'), findsOneWidget);
      expect(find.textContaining(r'$2.130'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en tablet el acceso sobrevive aunque la columna se repliegue',
        (tester) async {
      await _pump(tester, 900, portalSnapshot: _tenPortalMatches());

      expect(find.text('RESULTADO PORTAL'), findsNothing);
      expect(find.text('Ver 10 opciones'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('portal-results-toggle-s1')));
      await tester.pumpAndSettle();

      expect(find.text('Resultados en TeknoBike'), findsOneWidget);
      expect(find.text('CÁMARA 700 X 35/43C V/FRANCESA 48MM'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
