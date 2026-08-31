import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Un número sin referente no informa, y «10» era exactamente eso.**
///
/// La fila del proveedor decía «10 opciones» sobre la primera página de una
/// consulta angosta. Estas pruebas fijan lo contrario: se ofrece lo que el
/// operador puede elegir, se dice cuántos productos se revisaron para llegar
/// ahí, y se distingue haber recorrido el catálogo completo de no haberlo
/// recorrido. Se afirman las palabras, nunca anchos: la fuente de las pruebas
/// mide distinto que la real.

SupplierConcentration _supplier() => SupplierConcentration(
      supplierId: 's1',
      supplierName: 'RBX',
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
      brands: 'Kenda',
      gamaMix: null,
      supplierWebsite: 'https://portal.rburgos.cl',
      supplierCity: 'Santiago',
      salesRepName: null,
      salesRepPhone: null,
      salesRepEmail: null,
      hasPortalAccount: true,
    );

SupplierNeedPortalMatch _match(
  String code,
  String name,
  SupplierNeedMatchState state,
) =>
    SupplierNeedPortalMatch(
      candidate: SupplierPortalCatalogCandidate(
        code: code,
        name: name,
        priceNet: 2240,
      ),
      state: state,
      provenFields: const <String>['product_family'],
      missingFields: const <String>[],
      conflictingFields: state == SupplierNeedMatchState.conflict
          ? const <String>['product_family']
          : const <String>[],
    );

/// Diez cámaras 700 que sí sirven, más nueve filas revisadas y descartadas:
/// siete de otra medida y los dos neumáticos que el proveedor archivó dentro
/// de `CAMARAS RUTA`.
SupplierNeedPortalSearchSnapshot _snapshot({required bool complete}) =>
    SupplierNeedPortalSearchSnapshot(
      query: 'camara',
      status: SupplierNeedPortalSearchStatus.completed,
      checkedAt: DateTime.now(),
      matches: <SupplierNeedPortalMatch>[
        for (var index = 0; index < 10; index++)
          _match(
            '1000${index + 1}',
            'CAMARA 700X28/38C V/AUTO ${index + 1}',
            SupplierNeedMatchState.exact,
          ),
        for (var index = 0; index < 7; index++)
          _match(
            '2000${index + 1}',
            'CAMARA 26X1.75 V/AMERICANA ${index + 1}',
            SupplierNeedMatchState.conflict,
          ),
        _match(
            '12010', 'NEUMATICO 700X23C K191', SupplierNeedMatchState.conflict),
        _match(
            '17570', 'NEUMATICO RUTA 700X25C', SupplierNeedMatchState.conflict),
      ],
      coverage: SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: complete,
        limit: complete
            ? SupplierNeedCoverageLimit.enumerated
            : SupplierNeedCoverageLimit.maxPages,
        nodeLabels: const <String>['CAMARAS RUTA'],
        nodeIds: const <String>['171'],
        nodesAvailable: 1,
        nodesPlanned: 1,
        nodesCompleted: 1,
        pagesFetched: 3,
        rowsObserved: 19,
        rowsUnique: 19,
        rowsPersisted: 19,
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  SupplierNeedPortalSearchSnapshot snapshot, {
  double width = 1280,
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  String? expanded;
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
              exactProducts: const <SupplyStockOption>[],
              plannedProductIds: const <String>{},
              onAddExactProduct: (_) {},
              onCheckExactProduct: (_) {},
              onOpenExactSupplier: (_) {},
              report: SupplierConcentrationReport(
                items: <SupplierConcentration>[_supplier()],
                hasMore: false,
              ),
              confirmedLabelFor: (_) => snapshot.rowLabel,
              confirmedAgeFor: (_) => snapshot.ageLabel,
              confirmedDetailFor: (_) => snapshot.detailLabel,
              portalSearchFor: (_) => snapshot,
              expandedPortalSupplierId: expanded,
              onTogglePortalResults: (supplier) => setState(() {
                expanded = expanded == supplier.supplierId
                    ? null
                    : supplier.supplierId;
              }),
              canSearchNeedFor: (_) => true,
              needsLoginFor: (_) => false,
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

void main() {
  testWidgets('se ofrecen las opciones, no todo lo que el portal mostró',
      (tester) async {
    await _pump(tester, _snapshot(complete: true));

    // 19 revisadas, 10 elegibles: contar las contradichas como opciones sería
    // ofrecer dos neumáticos como cámaras.
    expect(find.text('Ver 10 opciones'), findsOneWidget);
    expect(find.text('Ver 19 opciones'), findsNothing);
  });

  testWidgets('el panel dice cuántas se revisaron y que se recorrió todo',
      (tester) async {
    await _pump(tester, _snapshot(complete: true));
    await tester.tap(find.text('Ver 10 opciones').first);
    await tester.pump();

    final summary = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (text) => (text.data ?? '').contains('opciones exactas'),
        );
    expect(summary.data, contains('10 opciones exactas'));
    expect(summary.data, contains('19 productos revisados'));
    expect(summary.data, contains('9 de 19 contradicen la ficha'));
    expect(summary.data, isNot(contains('sin evaluar')));
    expect(summary.data, contains('Cobertura completa'));
    expect(summary.data, contains('CAMARAS RUTA'));
  });

  testWidgets('una revisión parcial se rotula parcial, no completa',
      (tester) async {
    await _pump(tester, _snapshot(complete: false));
    await tester.tap(find.text('Ver 10 opciones').first);
    await tester.pump();

    final summary = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (text) => (text.data ?? '').contains('opciones exactas'),
        );
    expect(summary.data, contains('Revisión parcial'));
    expect(summary.data, isNot(contains('Cobertura completa')));
  });

  testWidgets('lo confirmado y lo que falta verificar se muestran aparte',
      (tester) async {
    // La corrida real del 2026-08-29: 17 filas que declaran la ficha y una
    // que no. «18 opciones relevantes» escondía justo la que había que mirar.
    final mixed = SupplierNeedPortalSearchSnapshot(
      query: 'camara',
      status: SupplierNeedPortalSearchStatus.completed,
      checkedAt: DateTime.now(),
      matches: <SupplierNeedPortalMatch>[
        for (var index = 0; index < 17; index++)
          _match('30$index', 'CAMARA 700 X 28/38C V/FRANCESA $index',
              SupplierNeedMatchState.exact),
        _match('18180', 'CAMARA SCOOTER 8-1/2 X 2 50/76-6.1 VALVULA SCHRADE',
            SupplierNeedMatchState.possible),
      ],
      coverage: const SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: true,
        limit: SupplierNeedCoverageLimit.enumerated,
        nodeLabels: <String>['CAMARAS RUTA'],
        nodesAvailable: 1,
        nodesPlanned: 1,
        nodesCompleted: 1,
        pagesFetched: 2,
        rowsObserved: 18,
        rowsUnique: 18,
        rowsPersisted: 18,
      ),
    );

    await _pump(tester, mixed);
    await tester.tap(find.text('Ver 18 opciones').first);
    await tester.pump();

    final summary = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (text) => (text.data ?? '').contains('exactas'),
        );
    expect(summary.data, contains('17 exactas'));
    expect(summary.data, contains('1 por revisar'));
    expect(summary.data, isNot(contains('18 opciones')));
  });

  testWidgets('con truncamiento el panel separa omitidos de contradichos',
      (tester) async {
    // 200 enumeradas, 120 guardadas por el tope, 100 relevantes: los 80
    // omitidos no se juzgaron nunca y no pueden contarse como contradicciones.
    final truncated = SupplierNeedPortalSearchSnapshot(
      query: 'camara',
      status: SupplierNeedPortalSearchStatus.completed,
      checkedAt: DateTime.now(),
      matches: <SupplierNeedPortalMatch>[
        for (var index = 0; index < 100; index++)
          _match('7$index', 'CAMARA 700X28/38C $index',
              SupplierNeedMatchState.exact),
        for (var index = 0; index < 20; index++)
          _match('9$index', 'NEUMATICO 700X23C $index',
              SupplierNeedMatchState.conflict),
      ],
      coverage: const SupplierNeedPortalCoverage(
        method: SupplierNeedCoverageMethod.taxonomy,
        isComplete: false,
        limit: SupplierNeedCoverageLimit.storageCap,
        nodeLabels: <String>['CAMARAS RUTA'],
        nodesAvailable: 1,
        nodesPlanned: 1,
        nodesCompleted: 1,
        pagesFetched: 23,
        rowsObserved: 210,
        rowsUnique: 200,
        rowsPersisted: 120,
      ),
    );

    await _pump(tester, truncated);
    await tester.tap(find.text('Ver 100 opciones').first);
    await tester.pump();

    final summary = tester.widgetList<Text>(find.byType(Text)).firstWhere(
          (text) => (text.data ?? '').contains('opciones exactas'),
        );
    expect(summary.data, contains('100 opciones exactas'));
    expect(summary.data, contains('20 de 120 contradicen la ficha'));
    expect(summary.data, contains('80 quedaron sin evaluar'));
    expect(summary.data, contains('Revisión parcial'));
    expect(summary.data, isNot(contains('Cobertura completa')));
  });

  testWidgets('las filas contradichas no se dibujan como opciones',
      (tester) async {
    await _pump(tester, _snapshot(complete: true));
    await tester.tap(find.text('Ver 10 opciones').first);
    await tester.pump();

    expect(find.textContaining('NEUMATICO'), findsNothing);
    expect(find.textContaining('CAMARA 26X1.75'), findsNothing);
    expect(find.textContaining('CAMARA 700X28/38C'), findsWidgets);
  });
}
