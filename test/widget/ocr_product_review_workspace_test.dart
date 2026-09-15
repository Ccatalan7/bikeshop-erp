import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_product_review_workspace.dart';
import 'package:vinabike_erp/shared/widgets/ocr_review_evidence.dart';
import 'package:vinabike_erp/shared/widgets/vb_button.dart';
import 'package:vinabike_erp/shared/widgets/vb_skeleton.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';
import 'package:vinabike_erp/shared/services/ocr_purchase_review_flow.dart';

void main() {
  testWidgets(
      'identity shows the OCR source and the real first inventory record',
      (tester) async {
    final line = _line(id: 'l1', status: OcrProductReviewStatus.ready);
    Product? opened;
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        callbacks: OcrProductReviewCallbacks(
            onOpenInventoryProduct: (product) => opened = product));
    expect(find.text('ARTÍCULO LEÍDO POR OCR'), findsOneWidget);
    expect(find.text('COINCIDENCIA EN INVENTARIO'), findsOneWidget);
    expect(find.text(line.originalTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-inventory-record-l1-p0')),
        findsOneWidget);
    expect(find.text(line.inventoryProduct!.name), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ocr-inventory-open-l1-p0')));
    expect(opened?.id, 'p0');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selecting identity does not apply a remembered decomposition',
      (tester) async {
    Product? selected;
    var applied = 0;
    var created = 0;
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [
          _line(
              id: 'l1', status: OcrProductReviewStatus.ready, remembered: true),
        ],
        callbacks: OcrProductReviewCallbacks(
            onLinkCandidate: (_, product) => selected = product,
            onConfirmRememberedResolution: (_) => applied++,
            onConfirmNewProduct: (_) => created++));
    expect(find.text('Aplicar regla guardada'), findsNothing);
    expect(find.text('Regla por revisar'), findsNothing);
    expect(find.text('Por decidir'), findsNothing);
    await tester.tap(find.byKey(const Key('ocr-review-select-l1')));
    expect(selected?.id, 'p0');
    expect(applied, 0);
    expect(created, 0);
  });

  testWidgets('new identity marks the row without opening fields or creating',
      (tester) async {
    var marked = 0;
    var created = 0;
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [
          _line(id: 'l1', status: OcrProductReviewStatus.ready),
        ],
        callbacks: OcrProductReviewCallbacks(
            onPrepareNewProduct: (_) => marked++,
            onConfirmNewProduct: (_) => created++));
    await tester.tap(find.byKey(const Key('ocr-review-new-l1')));
    expect(marked, 1);
    expect(created, 0);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
      'alternatives and inventory search keep the current source identity',
      (tester) async {
    final requests = <String>[];
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [
          _line(
              id: 'l1',
              status: OcrProductReviewStatus.ready,
              viableCandidateCount: 2,
              candidates: _candidates(2)),
          _line(
              id: 'l2',
              status: OcrProductReviewStatus.abstained,
              hasInventoryProduct: false),
        ],
        callbacks: OcrProductReviewCallbacks(onOpenCandidates: requests.add));
    // One door into the picker per row: «Comparar (N)» when there is
    // something to compare, «Buscar en inventario» when there is not.
    expect(find.text('Comparar (2)'), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-inventory-l1')), findsNothing);
    expect(find.text('Sin coincidencia recomendada'), findsOneWidget);
    expect(find.text('Nada parecido en el inventario'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-review-alternatives-l1')));
    await tester.tap(find.byKey(const Key('ocr-review-inventory-l2')));
    expect(requests, ['l1', 'l2']);
  });

  testWidgets('a row the matcher has not compared yet says so and waits',
      (tester) async {
    await _pump(tester, size: const Size(1440, 900), lines: [
      _line(
          id: 'l1',
          status: OcrProductReviewStatus.needsSearch,
          hasInventoryProduct: false),
    ]);
    expect(find.byKey(const Key('ocr-review-pending-l1')), findsOneWidget);
    expect(find.text('Pendiente de comparar'), findsOneWidget);
    expect(find.text('Sin coincidencias sugeridas'), findsNothing);
    expect(find.byKey(const Key('ocr-review-select-l1')), findsNothing);
    expect(find.byKey(const Key('ocr-review-new-l1')), findsNothing);
    expect(find.byKey(const Key('ocr-review-alternatives-l1')), findsNothing);
    expect(find.text('Esperando la comparación'), findsOneWidget);
  });

  testWidgets('a queued row draws its silhouette and never reads «pendiente»',
      (tester) async {
    await _pump(tester, size: const Size(1440, 900), lines: [
      _line(
          id: 'l1',
          status: OcrProductReviewStatus.searching,
          queued: true,
          hasInventoryProduct: false),
      _line(
          id: 'l2',
          status: OcrProductReviewStatus.searching,
          hasInventoryProduct: false),
    ]);
    // Queued: the X-01 silhouette, an inert decision that says so, and none
    // of the words that would suggest nothing is running.
    expect(find.byKey(const Key('ocr-review-queued-l1')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('ocr-review-queued-l1')),
            matching: find.byType(VbSkeleton)),
        findsNWidgets(3));
    expect(find.byType(VbSkeletonGroup), findsOneWidget);
    expect(find.text('En cola'), findsOneWidget);
    expect(find.text('Pendiente de comparar'), findsNothing);
    expect(find.textContaining('aún no corre'), findsNothing);
    expect(find.byKey(const Key('ocr-review-select-l1')), findsNothing);
    expect(find.byKey(const Key('ocr-review-new-l1')), findsNothing);
    // Taken by a worker: the spinner, not the silhouette.
    expect(find.text('Comparando con el inventario…'), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-queued-l2')), findsNothing);
    expect(find.text('Comparando…'), findsOneWidget);
  });

  testWidgets('a settled table runs no skeleton clock', (tester) async {
    await _pump(tester, size: const Size(1440, 900), lines: [
      _line(id: 'l1', status: OcrProductReviewStatus.ready),
    ]);
    expect(find.byType(VbSkeletonGroup), findsNothing);
    expect(find.byType(VbSkeleton), findsNothing);
  });

  testWidgets('the header publishes the running pass and hides the retry',
      (tester) async {
    var retries = 0;
    await _pump(tester,
        size: const Size(1440, 900),
        callbacks: OcrProductReviewCallbacks(onSearchPending: () => retries++),
        activity: const OcrProductReviewActivity(
            label: 'Comparando con el inventario', completed: 2, total: 5),
        lines: [
          _line(
              id: 'l1',
              status: OcrProductReviewStatus.searching,
              queued: true,
              hasInventoryProduct: false),
        ]);
    expect(
        find.byKey(const Key('ocr-review-activity-spinner')), findsOneWidget);
    expect(find.text('Comparando con el inventario · 2 de 5'), findsOneWidget);
    expect(find.textContaining('identificados'), findsNothing);
    expect(find.text('Reintentar pendientes'), findsNothing);
    expect(retries, 0);
  });

  testWidgets('without a running pass the header counts and offers the retry',
      (tester) async {
    await _pump(tester,
        size: const Size(1440, 900),
        callbacks: OcrProductReviewCallbacks(onSearchPending: () {}),
        lines: [
          _line(
              id: 'l1',
              status: OcrProductReviewStatus.needsSearch,
              hasInventoryProduct: false),
        ]);
    expect(find.byKey(const Key('ocr-review-activity-spinner')), findsNothing);
    expect(find.text('0 de 1 identificados'), findsOneWidget);
    expect(find.text('Reintentar pendientes'), findsOneWidget);
  });

  testWidgets('evidence is on the row and «Podría ser» compares first',
      (tester) async {
    final requests = <String>[];
    Product? selected;
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [
          _line(
              id: 'strong',
              status: OcrProductReviewStatus.ready,
              viableCandidateCount: 1,
              bestEvidence: const OcrCandidateEvidence(
                  'Muy parecido', VbStatusTone.info)),
          _line(
              id: 'weak',
              status: OcrProductReviewStatus.ready,
              viableCandidateCount: 3,
              bestEvidence: const OcrCandidateEvidence(
                  'Podría ser', VbStatusTone.neutral, needsComparison: true),
              categoryObjection:
                  'Está en otra categoría: Accesorios (seleccionada: Asientos).'),
        ],
        callbacks: OcrProductReviewCallbacks(
            onOpenCandidates: requests.add,
            onLinkCandidate: (_, product) => selected = product));
    expect(find.byKey(const Key('ocr-review-evidence-strong')), findsOneWidget);
    expect(find.text('Muy parecido'), findsOneWidget);
    expect(find.text('Mejor coincidencia'), findsNWidgets(2));
    expect(find.text('Primera coincidencia'), findsNothing);
    final strongSelect = tester
        .widget<VbButton>(find.byKey(const Key('ocr-review-select-strong')));
    expect(strongSelect.onPressed, isNotNull);
    expect(strongSelect.variant, VbButtonVariant.primary);
    expect(find.text('Seleccionar'), findsOneWidget);
    // Weak evidence: the primary button opens the comparison; selecting is
    // secondary and says it is a choice against the evidence.
    expect(find.byKey(const Key('ocr-review-compare-weak')), findsOneWidget);
    expect(find.text('Seleccionar igual'), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-note-weak')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-review-compare-weak')));
    expect(requests, ['weak']);
    await tester.tap(find.byKey(const Key('ocr-review-select-weak')));
    expect(selected?.id, 'p0');
  });

  testWidgets(
      'a pack reading keeps the product on the row and can be re-compared',
      (tester) async {
    final retried = <String>[];
    Product? selected;
    final pack = _candidates(1).first.product;
    final line = OcrProductReviewLine(
      id: 'l1',
      sku: 'AE0320',
      originalTitle: 'Sillín de bicicleta hueco MTB',
      controllers: OcrProductDraftControllers(
        sku: TextEditingController(text: 'AE0320'),
        name: TextEditingController(text: 'Sillín'),
        cost: TextEditingController(text: '8645'),
        price: TextEditingController(text: '17000'),
      ),
      status: OcrProductReviewStatus.abstained,
      sourceQuantity: 2,
      viableCandidateCount: 17,
      candidates: _candidates(2),
      aiCompositeProposal: '2 × AE0320 · Sillín Prostático Riderace',
      aiCompositeProduct: pack,
      aiCompositeUnits: 2,
    );
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        callbacks: OcrProductReviewCallbacks(
            onRetryLine: retried.add,
            onLinkCandidate: (_, product) => selected = product));
    // The product the AI named stays a record, not a sentence.
    expect(find.byKey(const Key('ocr-review-pack-l1')), findsOneWidget);
    expect(find.text(pack.name), findsOneWidget);
    expect(find.text('Leído como pack'), findsOneWidget);
    expect(find.textContaining('Coincide como pack:'), findsNothing);
    expect(find.text('Definir contenido'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-review-select-l1')));
    expect(selected?.id, pack.id);
    // Any compared row can be compared again with the current code.
    expect(find.text('Volver a comparar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-review-retry-l1')));
    expect(retried, ['l1']);
  });

  testWidgets('two lines proposing the same product warn each other',
      (tester) async {
    await _pump(tester, size: const Size(1440, 900), lines: [
      _line(
          id: 'a',
          status: OcrProductReviewStatus.ready,
          sharedWithLineTitle: 'Luz trasera USB roja'),
    ]);
    expect(find.byKey(const Key('ocr-review-shared-a')), findsOneWidget);
    expect(
        find.textContaining('ya propone este producto: “Luz trasera USB roja”'),
        findsOneWidget);
  });

  testWidgets('amounts are prefilled and confirmed separately after identity',
      (tester) async {
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.existing,
        remembered: true);
    var confirmed = 0;
    final fields = <String>[];
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        step: OcrPurchaseReviewStep.amounts,
        callbacks: OcrProductReviewCallbacks(
            onConfirmAmounts: (_) => confirmed++,
            onAmountsChanged: (_, field) => fields.add(field)));
    expect(line.purchaseQuantityController!.text, '5');
    expect(line.purchaseTotalController!.text, '40242');
    // Step 2 is one table: header, a row per line, no per-row confirm button.
    for (final header in [
      'PRODUCTO',
      'COMPRADO',
      'COSTO/COMPRA',
      'TOTAL LÍNEA',
      'UNID./COMPRA',
      'INGRESO A INVENTARIO',
      'REGLA',
      'ESTADO',
    ]) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    expect(find.text('Confirmar línea'), findsNothing);
    expect(
        find.byKey(const Key('ocr-review-confirm-amounts-l1')), findsNothing);
    expect(find.byKey(const Key('ocr-review-apply-rule-l1')), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-reject-rule-l1')), findsOneWidget);
    expect(find.text('Regla por decidir'), findsOneWidget);
    expect(find.text('5 unidades'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('ocr-purchase-quantity-l1')), '3');
    expect(fields, ['quantity']);
    expect(confirmed, 0);
  });

  testWidgets('the amounts table shows an applied rule as component rows',
      (tester) async {
    const parts = [
      OcrReviewComponent(
          productId: 'front',
          name: 'Maneta BUCKLOS delantera',
          sku: 'AE0300',
          unitsPerPurchase: 1,
          totalQuantity: 3,
          role: 'front',
          costRatio: 0.5),
      OcrReviewComponent(
          productId: 'rear',
          name: 'Maneta BUCKLOS trasera',
          sku: 'AE0301',
          unitsPerPurchase: 1,
          totalQuantity: 3,
          role: 'rear',
          costRatio: 0.5),
    ];
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.existing,
        appliedComposition: true,
        resolutionComponents: parts,
        ruleAttribution: 'confirmada por ti el 12/08/2026');
    line.purchaseQuantityController!.text = '3';
    line.purchaseTotalController!.text = '30000';
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        step: OcrPurchaseReviewStep.amounts);
    expect(find.text('Regla aplicada'), findsOneWidget);
    expect(find.text('confirmada por ti el 12/08/2026'), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-component-l1-0')), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-component-l1-1')), findsOneWidget);
    expect(find.text('AE0300 · delantero'), findsOneWidget);
    expect(find.text('3 × AE0300 + 3 × AE0301'), findsOneWidget);
    expect(find.text('\$15.000'), findsNWidgets(2));
    expect(find.byKey(const Key('ocr-purchase-units-l1')), findsNothing);
    expect(find.text('Modificar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the amounts table becomes cards under 900 px, also in dark',
      (tester) async {
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.existing,
        errorMessage:
            'La compra sigue; no se guardó la regla para la próxima vez.');
    await _pump(tester,
        size: const Size(430, 900),
        dark: true,
        lines: [line],
        step: OcrPurchaseReviewStep.amounts);
    expect(find.text('PRODUCTO'), findsNothing);
    expect(find.text('Comprado'), findsOneWidget);
    expect(find.text('Unid./compra'), findsOneWidget);
    expect(find.byKey(const Key('ocr-purchase-quantity-l1')), findsOneWidget);
    expect(find.text('Ingreso a inventario: 5 unidades'), findsOneWidget);
    expect(find.text('Con error'), findsOneWidget);
    expect(find.text('Descomponer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a remembered rule shows its author and can be changed',
      (tester) async {
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.existing,
        remembered: true,
        ruleAttribution:
            'confirmada por ti el 12/08/2026 · compra del 12/08/2026');
    var applied = 0;
    var rejected = 0;
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        step: OcrPurchaseReviewStep.amounts,
        callbacks: OcrProductReviewCallbacks(
            onConfirmRememberedResolution: (_) => applied++,
            onRejectRememberedResolution: (_) => rejected++));
    expect(find.text('confirmada por ti el 12/08/2026 · compra del 12/08/2026'),
        findsOneWidget);
    expect(find.text('Regla anterior'), findsOneWidget);
    expect(find.text('Aplicar'), findsOneWidget);
    expect(find.text('Cambiar'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ocr-review-reject-rule-l1')));
    expect(rejected, 1);
    expect(applied, 0);
  });

  testWidgets('a changed rule says the confirmed choice will be saved',
      (tester) async {
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.existing,
        ruleRejected: true);
    await _pump(tester,
        size: const Size(1440, 900),
        lines: [line],
        step: OcrPurchaseReviewStep.amounts);
    expect(
        find.byKey(const Key('ocr-review-rule-rejected-l1')), findsOneWidget);
    expect(find.text('Se guardará tu elección'), findsOneWidget);
    expect(find.byKey(const Key('ocr-review-apply-rule-l1')), findsNothing);
  });

  testWidgets(
      'the bulk-creation step contains only new rows with fields in columns',
      (tester) async {
    await _pump(tester,
        size: const Size(1440, 900),
        step: OcrPurchaseReviewStep.newProducts,
        lines: [
          _line(
              id: 'existing',
              status: OcrProductReviewStatus.linked,
              identity: OcrProductIdentityDecision.existing),
          _line(
              id: 'new',
              status: OcrProductReviewStatus.ready,
              identity: OcrProductIdentityDecision.newProduct)
        ]);
    expect(
        find.byKey(const Key('ocr-review-create-row-existing')), findsNothing);
    final name = find.byKey(const Key('ocr-review-name-new'));
    final cost = find.byKey(const Key('ocr-review-cost-new'));
    final price = find.byKey(const Key('ocr-review-price-new'));
    expect(name, findsOneWidget);
    expect(cost, findsOneWidget);
    expect(tester.getTopLeft(name).dx, lessThan(tester.getTopLeft(cost).dx));
    expect(tester.getTopLeft(cost).dx, lessThan(tester.getTopLeft(price).dx));
    expect(find.text('Configurar descomposición'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple new products expose their fields without row expansion',
      (tester) async {
    await _pump(tester,
        size: const Size(1440, 900),
        step: OcrPurchaseReviewStep.newProducts,
        lines: [
          for (final id in ['one', 'two'])
            _line(
                id: id,
                status: OcrProductReviewStatus.ready,
                identity: OcrProductIdentityDecision.newProduct),
        ]);
    expect(find.byType(ExpansionTile), findsNothing);
    for (final id in ['one', 'two']) {
      expect(
          find.byKey(Key('ocr-review-name-$id')).hitTestable(), findsOneWidget);
      expect(
          find.byKey(Key('ocr-review-cost-$id')).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final width in [390.0, 834.0, 900.0, 1311.0, 1312.0, 1440.0]) {
      testWidgets(
          'new-product grid retains fields and single errors at $width dark=$dark',
          (tester) async {
        final line = _line(
            id: 'l1',
            status: OcrProductReviewStatus.ready,
            identity: OcrProductIdentityDecision.newProduct,
            categoryValidationMessage: 'Selecciona una categoría',
            errorMessage: 'Selecciona una categoría');
        await _pump(tester,
            size: Size(width, 1000),
            dark: dark,
            step: OcrPurchaseReviewStep.newProducts,
            lines: [line]);
        expect(find.text('Selecciona una categoría'), findsOneWidget);
        expect(find.text('Unid./compra'), findsNothing);
        expect(find.text('Unidades por compra'), findsNothing);
        expect(find.byKey(const Key('ocr-review-new-units-l1')), findsNothing);
        expect(
            find.byKey(const Key('ocr-review-stock-receipt-l1')), findsNothing);
        expect(line.newProductUnitsController!.text, '1');
        expect(line.newProductInventoryQuantity, 5);
        expect(find.byType(ExpansionTile), findsNothing);
        final name = find.byKey(const Key('ocr-review-name-l1'));
        final editable =
            find.descendant(of: name, matching: find.byType(EditableText));
        final border = InputDecorator.containerOf(tester.element(editable))!;
        final touch = width - 32 < 900;
        expect(border.size.height, closeTo(touch ? 48 : 34, .1));
        if (width >= 1312) {
          final inputs = ['name', 'sku', 'cost', 'price'];
          for (final kind in inputs) {
            final field = find.byKey(Key('ocr-review-$kind-l1'));
            expect(tester.getTopLeft(field).dy,
                closeTo(tester.getTopLeft(name).dy, .1));
          }
          // The frame wraps the batch rather than outlining a screen of empty space.
          expect(
              tester
                  .getSize(find.byKey(const Key('ocr-new-products-table')))
                  .height,
              lessThan(180));
          expect(find.text('Categoría'), findsOneWidget);
          expect(find.text('Marca'), findsOneWidget);
        }
        final cost = find.byKey(const Key('ocr-review-cost-l1'));
        await tester.ensureVisible(cost);
        await tester.enterText(cost, '1234,5');
        await tester.pump();
        expect(line.controllers.cost.text, '1234,5');
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final isSold in [false, true]) {
    testWidgets('step 3 workshop supply checkbox maps draft isSold=$isSold',
        (tester) async {
      var sold = <bool>[];
      var copied = <String>[];
      final line = OcrProductReviewLine(
        id: 'l1',
        isSold: isSold,
        identityDecision: OcrProductIdentityDecision.newProduct,
        isSelected: true,
        sku: 'AE0140',
        originalTitle: 'Luz trasera USB roja',
        controllers: OcrProductDraftControllers(
          sku: TextEditingController(text: 'AE0140'),
          name: TextEditingController(text: 'Luz trasera USB'),
          cost: TextEditingController(text: '3000'),
          price: TextEditingController(text: '6000'),
        ),
        status: OcrProductReviewStatus.ready,
        newProductUnitsController: TextEditingController(text: '1'),
        newProductInventoryQuantity: 2,
        sourceQuantity: 2,
        categories: _categories,
        brands: _brands,
        category: _categories.first,
        brand: _brands.first,
        siblingLineId: 'l2',
        siblingSuggestion:
            'La línea “Luz trasera USB negra” comparte esta publicación.',
      );
      await _pump(tester,
          size: const Size(1440, 900),
          step: OcrPurchaseReviewStep.newProducts,
          lines: [line],
          callbacks: OcrProductReviewCallbacks(
              onSoldChanged: (_, value) => sold.add(value),
              onCopySibling: (_, sibling) => copied.add(sibling),
              onReplaceImage: (_) {}));
      expect(find.byKey(const Key('ocr-review-consumable-l1')), findsOneWidget);
      expect(find.text('Insumo de taller'), findsOneWidget);
      expect(
          tester
              .widget<Checkbox>(
                  find.byKey(const Key('ocr-review-consumable-l1')))
              .value,
          !isSold);
      await tester.tap(find.byKey(const Key('ocr-review-consumable-l1')));
      expect(sold, [!isSold]);
      await tester.tap(find.byKey(const Key('ocr-review-copy-sibling-l1')));
      expect(copied, ['l2']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1440.0, 390.0]) {
    testWidgets('product images accept platform drops and click at $width',
        (tester) async {
      final drops = <String>[];
      final clicks = <String>[];
      await _pump(tester,
          size: Size(width, 1000),
          step: OcrPurchaseReviewStep.newProducts,
          lines: [
            for (final id in ['one', 'two'])
              _line(
                  id: id,
                  status: OcrProductReviewStatus.ready,
                  identity: OcrProductIdentityDecision.newProduct),
          ],
          callbacks: OcrProductReviewCallbacks(
              onDropImage: (id, files) => drops.add('$id:${files.single.name}'),
              onReplaceImage: clicks.add));
      final image = find.byKey(const Key('ocr-review-image-one'));
      final position = tester.getCenter(image);
      const codec = StandardMethodCodec();
      Future<void> send(String method, Object args) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            codec.encodeMethodCall(MethodCall(method, args)),
            (_) {});
        await tester.pump();
      }

      await send('entered', [position.dx, position.dy]);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsOneWidget);
      await send('performOperation', ['/tmp/product-test.png']);
      expect(drops, ['one:product-test.png']);
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);
      await tester.tap(image);
      await tester.pumpAndSettle();
      for (final target
          in tester.widgetList<DropTarget>(find.byType(DropTarget))) {
        expect(target.enable, isFalse);
      }
      await tester.tap(find.text('Reemplazar imagen'));
      await tester.pumpAndSettle();
      expect(clicks, ['one']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a locally staged image can be removed before upload',
      (tester) async {
    final removed = <String>[];
    await _pump(tester,
        size: const Size(1440, 900),
        step: OcrPurchaseReviewStep.newProducts,
        lines: [
          _line(
              id: 'l1',
              status: OcrProductReviewStatus.ready,
              identity: OcrProductIdentityDecision.newProduct,
              imageBytes: base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=='))
        ],
        callbacks: OcrProductReviewCallbacks(onRemoveImage: removed.add));
    await tester.tap(find.byKey(const Key('ocr-review-image-l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quitar imagen'));
    await tester.pumpAndSettle();
    expect(removed, ['l1']);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('hover reveals a direct image remove action dark=$dark',
        (tester) async {
      final removed = <String>[];
      await _pump(tester,
          size: const Size(1440, 900),
          dark: dark,
          step: OcrPurchaseReviewStep.newProducts,
          lines: [
            _line(
                id: 'l1',
                status: OcrProductReviewStatus.ready,
                identity: OcrProductIdentityDecision.newProduct,
                imageBytes: base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=='))
          ],
          callbacks: OcrProductReviewCallbacks(onRemoveImage: removed.add));
      final clear = find.byKey(const Key('ocr-review-clear-image-l1'));
      expect(clear, findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
          tester.getCenter(find.byKey(const Key('ocr-review-image-l1'))));
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      final imageRect =
          tester.getRect(find.byKey(const Key('ocr-review-image-l1')));
      final clearRect = tester.getRect(clear);
      expect(clearRect.width * clearRect.height,
          lessThan(imageRect.width * imageRect.height / 4));
      expect(clearRect.topRight, imageRect.topRight);
      // The rest of the thumbnail keeps its own action, not a hidden delete
      // target larger than the visible cross.
      await tester.tapAt(imageRect.bottomLeft + const Offset(4, -4));
      await tester.pumpAndSettle();
      expect(removed, isEmpty);
      expect(
          find.byKey(const Key('ocr-review-remove-image-l1')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(clear, findsNothing);
      await mouse.moveTo(
          tester.getCenter(find.byKey(const Key('ocr-review-image-l1'))));
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(removed, ['l1']);
      expect(find.byType(PopupMenuItem), findsNothing);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  for (final locked in ['readOnly', 'loading']) {
    testWidgets('image drop is disabled while $locked', (tester) async {
      await _pump(tester,
          size: const Size(1440, 900),
          step: OcrPurchaseReviewStep.newProducts,
          readOnly: locked == 'readOnly',
          lines: [
            _line(
                id: 'l1',
                status: OcrProductReviewStatus.ready,
                isUploadingImage: locked == 'loading',
                identity: OcrProductIdentityDecision.newProduct)
          ],
          callbacks: OcrProductReviewCallbacks(onDropImage: (_, __) {}));
      expect(find.byType(DropTarget), findsNothing);
    });
  }

  testWidgets('new-product edits survive compact recomposition',
      (tester) async {
    final line = _line(
        id: 'l1',
        status: OcrProductReviewStatus.ready,
        identity: OcrProductIdentityDecision.newProduct);
    await _pump(tester,
        size: const Size(1440, 900),
        step: OcrPurchaseReviewStep.newProducts,
        lines: [line]);
    await tester.enterText(
        find.byKey(const Key('ocr-review-name-l1')), 'Tee corregida');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(line.controllers.name.text, 'Tee corregida');
    expect(find.byKey(const Key('ocr-review-name-l1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'category selection preserves full branch identity and keyboard access',
      (tester) async {
    Category? chosen;
    await _pump(tester,
        size: const Size(1440, 900),
        step: OcrPurchaseReviewStep.newProducts,
        lines: [
          _line(
              id: 'l1',
              status: OcrProductReviewStatus.ready,
              identity: OcrProductIdentityDecision.newProduct,
              categories: _ambiguousCategories)
        ],
        callbacks: OcrProductReviewCallbacks(
            onCategoryChanged: (_, value) => chosen = value));
    await tester.tap(find.byKey(const Key('ocr-review-category-l1')));
    await tester.pumpAndSettle();
    expect(find.text('Accesorios / Adaptadores'), findsOneWidget);
    expect(find.text('Componentes / Frenos / Adaptadores'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Rotores');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(chosen?.name, 'Rotores');
  });

  testWidgets(
      'compact dark identity keeps professional decisions and record access',
      (tester) async {
    await _pump(tester,
        size: const Size(390, 844),
        dark: true,
        lines: [_line(id: 'l1', status: OcrProductReviewStatus.ready)]);
    expect(find.text('Seleccionar'), findsOneWidget);
    expect(find.text('Marcar como nuevo'), findsOneWidget);
    expect(find.text('Seleccionar producto'), findsNothing);
    expect(find.text('Es este'), findsNothing);
    expect(find.text('Preparar nuevo'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

// ── helpers ───────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required List<OcrProductReviewLine> lines,
  OcrProductReviewCallbacks callbacks = const OcrProductReviewCallbacks(),
  bool dark = false,
  bool readOnly = false,
  OcrPurchaseReviewStep step = OcrPurchaseReviewStep.identify,
  OcrProductReviewActivity? activity,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Scaffold(
        body: OcrProductReviewWorkspace(
          lines: lines,
          readOnly: readOnly,
          step: step,
          activity: activity,
          callbacks: callbacks,
          primaryLabel: 'Crear productos',
          pricingPolicyLabel: 'Precio sugerido = costo × 2',
        ),
      ),
    ),
  );
  // `pumpAndSettle` never returns here on purpose: a line that is still
  // searching shows a real indeterminate spinner. Settle a couple of frames
  // instead of waiting for an animation that is not supposed to end.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

final _categories = <Category>[
  _category('Tee', 'Componentes / Dirección / Tee'),
  _category('Rotores', 'Componentes / Frenos / Rotores'),
  _category('Maza', 'Componentes / Ruedas / Mazas / Maza'),
];

final _ambiguousCategories = <Category>[
  ..._categories,
  _category('Adaptadores', 'Accesorios / Adaptadores'),
  _category('Adaptadores', 'Componentes / Frenos / Adaptadores'),
];

Category _category(String name, String fullPath) => Category(
      id: fullPath,
      tenantId: 'tenant-test',
      name: name,
      fullPath: fullPath,
    );

final _brands = <ProductBrand>[
  ProductBrand(id: 'b1', tenantId: 'tenant-test', name: 'Wake'),
  ProductBrand(id: 'b2', tenantId: 'tenant-test', name: 'Shimano'),
];

OcrProductReviewLine _line({
  required String id,
  required OcrProductReviewStatus status,
  OcrProductIdentityDecision identity = OcrProductIdentityDecision.undecided,
  bool remembered = false,
  bool isUploadingImage = false,
  Uint8List? imageBytes,
  List<ProductDuplicateCandidate> candidates = const [],
  List<Category>? categories,
  Category? category,
  String? categoryValidationMessage,
  String? brandWarning,
  bool isReservingSku = false,
  bool queued = false,
  bool skuIsReadOnly = false,
  String? skuErrorMessage,
  int viableCandidateCount = 0,
  int discardedCandidateCount = 0,
  int categoryConflictCount = 0,
  String? aiCompositeProposal,
  bool canConfirmCompositeProposal = false,
  OcrProductResolvedMode resolvedMode = OcrProductResolvedMode.catalogLink,
  String? resolvedOutcomeSummary,
  bool canChangeResolvedDecision = true,
  bool ruleRejected = false,
  String? ruleAttribution,
  bool hasInventoryProduct = true,
  OcrCandidateEvidence? bestEvidence,
  String? sharedWithLineTitle,
  String? categoryObjection,
  bool appliedComposition = false,
  List<OcrReviewComponent> resolutionComponents = const [],
  String? errorMessage,
}) {
  return OcrProductReviewLine(
    id: id,
    isUploadingImage: isUploadingImage,
    imageBytes: imageBytes,
    identityDecision: identity,
    inventoryProduct: hasInventoryProduct ? _candidates(1).first.product : null,
    inventoryOrigin: 'Mejor coincidencia',
    bestEvidence: bestEvidence,
    sharedWithLineTitle: sharedWithLineTitle,
    categoryObjection: categoryObjection,
    appliedComposition: appliedComposition,
    resolutionComponents: resolutionComponents,
    errorMessage: errorMessage,
    hasRememberedSuggestion: remembered,
    ruleRejected: ruleRejected,
    ruleAttribution: ruleAttribution,
    purchaseQuantityController: TextEditingController(text: '5'),
    purchaseUnitCostController: TextEditingController(text: '8048.4'),
    purchaseTotalController: TextEditingController(text: '40242'),
    purchaseUnitsController: TextEditingController(text: '1'),
    newProductUnitsController: TextEditingController(text: '1'),
    newProductInventoryQuantity: 5,
    purchaseAmountsValid: true,
    sku: 'AE0${id.hashCode.abs() % 900 + 100}',
    originalTitle: 'WAKE-vástago ligero de aluminio 31,8mm',
    supplierCode: '1005007336672891',
    sourceQuantity: 1,
    controllers: OcrProductDraftControllers(
      sku: TextEditingController(text: 'AE0137'),
      name: TextEditingController(text: 'Tee WAKE 31.8mm'),
      cost: TextEditingController(text: '7172'),
      price: TextEditingController(text: '14300'),
    ),
    status: status,
    candidates: candidates.isEmpty && status == OcrProductReviewStatus.ready
        ? _candidates(1)
        : candidates,
    viableCandidateCount: viableCandidateCount,
    discardedCandidateCount: discardedCandidateCount,
    categoryConflictCount: categoryConflictCount,
    aiCompositeProposal: aiCompositeProposal,
    canConfirmCompositeProposal: canConfirmCompositeProposal,
    categories: categories ?? _categories,
    brands: _brands,
    category: categoryValidationMessage != null
        ? category
        : (category ?? (categories ?? _categories).first),
    brand: _brands.first,
    categoryValidationMessage: categoryValidationMessage,
    brandWarning: brandWarning,
    isReservingSku: isReservingSku,
    queued: queued,
    skuIsReadOnly: skuIsReadOnly,
    skuErrorMessage: skuErrorMessage,
    resolvedProductName: 'Tee Aluminio Wake MTB 31.8MM Rojo',
    resolvedProductSku: 'AE0137',
    resolvedMode: resolvedMode,
    resolvedOutcomeSummary: resolvedOutcomeSummary,
    canChangeResolvedDecision: canChangeResolvedDecision,
  );
}

List<ProductDuplicateCandidate> _candidates(int count) {
  return <ProductDuplicateCandidate>[
    for (var index = 0; index < count; index++)
      ProductDuplicateCandidate(
        product: Product(
          id: 'p$index',
          tenantId: 'tenant-test',
          sku: 'AE000${index + 1}',
          name: 'Tee Aluminio Wake MTB 31.8MM ${index == 0 ? 'Rojo' : 'Negro'}',
          brand: 'Wake',
          categoryName: 'Tee',
          price: 14300,
          cost: 7172,
        ),
        matchTier: index == 0
            ? ProductDuplicateMatchTier.strong
            : ProductDuplicateMatchTier.possible,
        confidence: 0.9 - index * 0.1,
        reasons: const ['Es tee', 'Diámetro de abrazadera 31.8mm'],
        objections: index == 0 ? const [] : const ['Otro color: negro'],
        gates: const [],
        variantMismatch: index != 0,
        hasProductImage: false,
      ),
  ];
}
