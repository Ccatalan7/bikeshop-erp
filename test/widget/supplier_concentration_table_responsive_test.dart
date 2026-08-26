import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
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
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SupplierConcentrationTable(
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
            confirmedLabelFor: (id) => id == 's1' ? '12 de 12' : null,
            confirmedAgeFor: (id) => id == 's1' ? 'hace 2 horas' : null,
            confirmedDetailFor: (id) =>
                id == 's1' ? '12 de 12 disponibles hace 2 horas' : null,
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
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('las columnas se ajustan al ancho que hay', () {
    testWidgets('ancho completo: las cinco columnas y la orden con rótulo',
        (tester) async {
      await _pump(tester, 1400);

      expect(find.text('EVIDENCIA'), findsOneWidget);
      expect(find.text('DISPONIBLE HOY'), findsOneWidget);
      // Con espacio, la orden se lee: el rótulo dice qué hace sin hover.
      expect(find.text('Consultar portal'), findsNWidgets(2));
      expect(find.text('Por qué'), findsNWidgets(2));
    });

    testWidgets('al estrecharse, la orden pasa a icono antes de perder un dato',
        (tester) async {
      await _pump(tester, 900);

      // Ningún dato se fue todavía: lo primero que cede es el rótulo, no la
      // columna, porque los números son lo que la tabla existe para comparar.
      expect(find.text('EVIDENCIA'), findsOneWidget);
      expect(find.text('DISPONIBLE HOY'), findsNothing);
      expect(find.text('Consultar portal'), findsNothing);

      // El tooltip nombra al proveedor: cuatro iconos iguales no identifican su
      // sujeto, ni para un lector de pantalla ni para esta prueba.
      expect(
        find.byTooltip('Consultar el portal de TeknoBike'),
        findsOneWidget,
      );
      expect(find.byTooltip('Por qué Vittal quedó acá'), findsOneWidget);
    });

    testWidgets('más angosto: cae «Confirmado», que es lo menos comparable',
        (tester) async {
      await _pump(tester, 700);

      expect(find.text('EVIDENCIA'), findsNothing);
      expect(find.text('DISPONIBLE HOY'), findsNothing);
      expect(
          find.byTooltip('Consultar el portal de TeknoBike'), findsOneWidget);
    });

    testWidgets('en compacto queda el ranking y la orden, nunca un desborde',
        (tester) async {
      await _pump(tester, 520);

      expect(find.text('CALCE'), findsNothing);
      expect(find.text('COSTO UNITARIO'), findsNothing);
      expect(find.text('PARECIDO · NO PRUEBA EL CALCE EXACTO'), findsNothing);
      expect(find.text('COMPRADO ANTES · MISMO ALCANCE'), findsOneWidget);
      expect(find.text('Consultar portal'), findsNWidgets(2));
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
      final teknoBike = tester.getTopLeft(find.text('Consultar portal').at(0));
      final vittal = tester.getTopLeft(find.text('Consultar portal').at(1));
      expect(teknoBike.dx, vittal.dx);
    });
  });
}
