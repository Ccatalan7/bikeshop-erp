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

Future<void> _pump(WidgetTester tester, double width) {
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
        body: SupplierConcentrationTable(
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
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('las columnas se ajustan al ancho que hay', () {
    testWidgets('ancho completo: las cinco columnas y la orden con rótulo',
        (tester) async {
      await _pump(tester, 1400);

      expect(find.text('ÚLTIMA COMPRA'), findsOneWidget);
      expect(find.text('CONFIRMADO'), findsOneWidget);
      // Con espacio, la orden se lee: el rótulo dice qué hace sin hover.
      expect(find.text('Confirmar hoy'), findsNWidgets(2));
      expect(find.text('Por qué'), findsNWidgets(2));
    });

    testWidgets('al estrecharse, la orden pasa a icono antes de perder un dato',
        (tester) async {
      await _pump(tester, 900);

      // Ningún dato se fue todavía: lo primero que cede es el rótulo, no la
      // columna, porque los números son lo que la tabla existe para comparar.
      expect(find.text('ÚLTIMA COMPRA'), findsOneWidget);
      expect(find.text('CONFIRMADO'), findsOneWidget);
      expect(find.text('Confirmar hoy'), findsNothing);

      // El tooltip nombra al proveedor: cuatro iconos iguales no identifican su
      // sujeto, ni para un lector de pantalla ni para esta prueba.
      expect(
        find.byTooltip('Confirmar hoy con TeknoBike'),
        findsOneWidget,
      );
      expect(find.byTooltip('Por qué Vittal quedó acá'), findsOneWidget);
    });

    testWidgets('más angosto: cae «Confirmado», que es lo menos comparable',
        (tester) async {
      await _pump(tester, 700);

      expect(find.text('ÚLTIMA COMPRA'), findsOneWidget);
      expect(find.text('CONFIRMADO'), findsNothing);
      expect(find.byTooltip('Confirmar hoy con TeknoBike'), findsOneWidget);
    });

    testWidgets('en compacto queda el ranking y la orden, nunca un desborde',
        (tester) async {
      await _pump(tester, 520);

      expect(find.text('PARTICIPACIÓN'), findsOneWidget);
      expect(find.text('COSTO UNITARIO'), findsOneWidget);
      expect(find.text('ÚLTIMA COMPRA'), findsNothing);
      expect(find.text('CONFIRMADO'), findsNothing);
      expect(find.byTooltip('Confirmar hoy con Vittal'), findsOneWidget);
    });

    testWidgets('el proveedor sin sitio conserva el hueco del icono',
        (tester) async {
      await _pump(tester, 1400);

      // Un solo enlace: el de TeknoBike. Si el hueco de Vittal se colapsara,
      // sus acciones correrían y la columna dejaría de alinear.
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      final teknoBike = tester.getTopLeft(find.text('Confirmar hoy').at(0));
      final vittal = tester.getTopLeft(find.text('Confirmar hoy').at(1));
      expect(teknoBike.dx, vittal.dx);
    });
  });
}
