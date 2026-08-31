import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// Independent coverage of the actual parent surface, not only its leaf widget.
Future<void> _mount(
  WidgetTester tester,
  double width,
  Brightness brightness,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1400);
  addTearDown(tester.view.reset);
  final snapshot = SupplierNeedPortalSearchSnapshot(
    query: 'puños',
    status: SupplierNeedPortalSearchStatus.completed,
    checkedAt: DateTime.now(),
    searchRevisionNo: 1,
    currentRevisionNo: 1,
    matches: const <SupplierNeedPortalMatch>[
      SupplierNeedPortalMatch(
        candidate: SupplierPortalCatalogCandidate(
          code: 'independent-grips',
          name: 'PUÑOS SIN TAPONES CON ESPUMA AMORTIGUADORA',
          brand: 'Marca de prueba',
          priceNet: 3500,
        ),
        state: SupplierNeedMatchState.possible,
        provenFields: <String>['product_family'],
        missingFields: <String>[kRequestedPropertyField],
        conflictingFields: <String>[],
        requirementFindings: <SupplyRequirementFinding>[
          SupplyRequirementFinding(
            label: 'gel',
            affirmed: true,
            status: SupplyRequirementStatus.inferred,
            quote: 'ESPUMA AMORTIGUADORA',
          ),
          SupplyRequirementFinding(
            label: 'sin tapones',
            affirmed: false,
            status: SupplyRequirementStatus.proven,
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: brightness,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SupplierConcentrationTable(
          report: SupplierConcentrationReport.fromJson(<String, dynamic>{
            'hasMore': false,
            'items': <Map<String, dynamic>>[
              <String, dynamic>{
                'entityId': 'supplier-test',
                'supplierName': 'Proveedor de prueba',
                'spendSharePercent': 100,
                'purchaseLines': 2,
                'purchaseInvoices': 1,
                'distinctProducts': 1,
                'evidencePurchaseLines': 2,
                'evidenceSuppliers': 1,
              },
            ],
          }),
          confirmedLabelFor: (_) => snapshot.rowLabel,
          confirmedAgeFor: (_) => snapshot.ageLabel,
          confirmedDetailFor: (_) => snapshot.detailLabel,
          portalSearchFor: (_) => snapshot,
          expandedPortalSupplierId: 'supplier-test',
          onTogglePortalResults: (_) {},
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
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  for (final width in <double>[1455, 834, 390]) {
    for (final brightness in Brightness.values) {
      testWidgets('supplier findings are visible at $width / $brightness',
          (tester) async {
        await _mount(tester, width, brightness);
        expect(find.textContaining('PUÑOS SIN TAPONES'), findsOneWidget);
        expect(find.text('gel: leído por IA, sin confirmar'), findsOneWidget,
            reason:
                'the real wide and narrow parent must both mount the findings');
        expect(find.text('sin tapones: lo dice el proveedor'), findsOneWidget,
            reason: 'a literal negative quote must not become sin sin tapones');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
