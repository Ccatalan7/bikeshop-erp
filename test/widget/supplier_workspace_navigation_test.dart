import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Cada fila de proveedor es una puerta.**
///
/// El chevron dice que lleva a alguna parte, pero el blanco es la fila entera:
/// un icono de 18 px obliga a apuntar, y lo que el operador quiere tocar es el
/// proveedor. Se afirma la conducta y el rótulo hablado, nunca una coordenada.
SupplierConcentration _supplier(String id, String name) {
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
    lastPurchaseAt: DateTime.now().subtract(const Duration(days: 92)),
    daysSinceLastPurchase: 92,
    brands: 'Maxxis',
    gamaMix: null,
    supplierWebsite: null,
    supplierCity: 'Santiago',
    salesRepName: null,
    salesRepPhone: null,
    salesRepEmail: null,
    hasPortalAccount: false,
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);

  testWidgets('tocar la fila abre la ficha de ESE proveedor', (tester) async {
    final abiertos = <String>[];
    final explicados = <String>[];
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.dark,
        ),
        home: Scaffold(
          body: SupplierConcentrationTable(
            report: SupplierConcentrationReport(
              items: [_supplier('s1', 'TeknoBike'), _supplier('s2', 'Vittal')],
              hasMore: false,
            ),
            confirmedLabelFor: (_) => null,
            confirmedAgeFor: (_) => null,
            confirmedDetailFor: (_) => null,
            checkProgress: null,
            busySupplierId: null,
            expandedSupplierId: null,
            onConfirm: (_) {},
            onExplain: (supplier) => explicados.add(supplier.supplierId),
            onOpenPortal: (_) {},
            onOpenSupplier: (supplier) => abiertos.add(supplier.supplierId),
            basis: PurchaseCostBasis.sinFlete,
            onBasisChanged: (_) {},
            evidencePanelBuilder: (_) => const SizedBox.shrink(),
          ),
        ),
      ),
    );

    // El chevron anuncia que hay a dónde ir. Sin él la fila se ve inerte.
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Abrir la ficha de Vittal'));
    await tester.pump();
    expect(abiertos, ['s2']);

    // Y las órdenes de la fila siguen siendo suyas: tocar «Por qué» no puede
    // abrir la ficha por debajo.
    await tester.tap(find.text('Por qué').first);
    await tester.pump();
    expect(explicados, ['s1']);
    expect(abiertos, ['s2'], reason: 'la orden no debe disparar la fila');
  });
}
