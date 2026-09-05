import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/ocr_product_review_workspace.dart';
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
        ],
        callbacks: OcrProductReviewCallbacks(onOpenCandidates: requests.add));
    await tester.tap(find.byKey(const Key('ocr-review-alternatives-l1')));
    await tester.tap(find.byKey(const Key('ocr-review-inventory-l1')));
    expect(requests, ['l1', 'l1']);
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
    expect(find.text('Aplicar regla guardada'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('ocr-purchase-quantity-l1')), '3');
    expect(fields, ['quantity']);
    expect(confirmed, 0);
    await tester.tap(find.byKey(const Key('ocr-review-confirm-amounts-l1')));
    expect(confirmed, 1);
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
    expect(find.text('Seleccionar producto'), findsOneWidget);
    expect(find.text('Marcar como nuevo'), findsOneWidget);
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
  OcrPurchaseReviewStep step = OcrPurchaseReviewStep.identify,
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
          step: step,
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
  List<ProductDuplicateCandidate> candidates = const [],
  List<Category>? categories,
  Category? category,
  String? categoryValidationMessage,
  String? brandWarning,
  bool isReservingSku = false,
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
}) {
  return OcrProductReviewLine(
    id: id,
    identityDecision: identity,
    inventoryProduct: _candidates(1).first.product,
    inventoryOrigin: 'Primera coincidencia',
    hasRememberedSuggestion: remembered,
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
