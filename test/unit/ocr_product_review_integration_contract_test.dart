import 'dart:io';

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart'
    as inventory_models;
import 'package:vinabike_erp/modules/purchases/pages/purchase_invoice_form_page.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';
import 'package:vinabike_erp/shared/widgets/ocr_upload_widget.dart';

void main() {
  final source = File(
    'lib/shared/widgets/ocr_upload_widget.dart',
  ).readAsStringSync();
  final workspace = File(
    'lib/shared/widgets/ocr_product_review_workspace.dart',
  ).readAsStringSync();
  final purchaseForm = File(
    'lib/modules/purchases/pages/purchase_invoice_form_page.dart',
  ).readAsStringSync();
  final router = File(
    'lib/shared/routes/app_router.dart',
  ).readAsStringSync();
  final matcher = File(
    'lib/modules/inventory/services/product_duplicate_matcher_service.dart',
  ).readAsStringSync();
  final picker = File(
    'lib/shared/widgets/ocr_candidate_picker.dart',
  ).readAsStringSync();

  test('purchase exit guards are scoped and release after critical work',
      () async {
    final firstScope = Object();
    final secondScope = Object();
    final firstOwner = Object();
    final secondOwner = Object();
    var firstCreationInFlight = true;

    addTearDown(() {
      PurchaseInvoiceExitGuard.unregister(firstScope, firstOwner);
      PurchaseInvoiceExitGuard.unregister(secondScope, secondOwner);
    });

    PurchaseInvoiceExitGuard.register(
      firstScope,
      firstOwner,
      () async => !firstCreationInFlight,
    );
    PurchaseInvoiceExitGuard.register(
      secondScope,
      secondOwner,
      () async => true,
    );

    expect(await PurchaseInvoiceExitGuard.canExit(firstScope), isFalse);
    expect(await PurchaseInvoiceExitGuard.canExit(secondScope), isTrue);
    expect(await PurchaseInvoiceExitGuard.canExit(Object()), isTrue);

    firstCreationInFlight = false;
    expect(await PurchaseInvoiceExitGuard.canExit(firstScope), isTrue);

    PurchaseInvoiceExitGuard.unregister(firstScope, Object());
    firstCreationInFlight = true;
    expect(await PurchaseInvoiceExitGuard.canExit(firstScope), isFalse);

    PurchaseInvoiceExitGuard.unregister(firstScope, firstOwner);
    PurchaseInvoiceExitGuard.unregister(secondScope, secondOwner);
    expect(await PurchaseInvoiceExitGuard.canExit(firstScope), isTrue);
    expect(await PurchaseInvoiceExitGuard.canExit(secondScope), isTrue);
  });

  test('purchase exit guard uses value-equal composite keys and fails closed',
      () async {
    final routerScope = Object();
    final registeredScope = (
      routerScope,
      const ValueKey<String>('purchase-page'),
    );
    final lookupScope = (
      routerScope,
      const ValueKey<String>('purchase-page'),
    );
    final compositeOwner = Object();
    final throwingScope = Object();
    final throwingOwner = Object();
    addTearDown(() {
      PurchaseInvoiceExitGuard.unregister(lookupScope, compositeOwner);
      PurchaseInvoiceExitGuard.unregister(throwingScope, throwingOwner);
    });

    PurchaseInvoiceExitGuard.register(
      registeredScope,
      compositeOwner,
      () async => false,
    );
    expect(identical(registeredScope, lookupScope), isFalse);
    expect(await PurchaseInvoiceExitGuard.canExit(lookupScope), isFalse);

    PurchaseInvoiceExitGuard.register(
      throwingScope,
      throwingOwner,
      () async => throw StateError('guard failed'),
    );
    expect(await PurchaseInvoiceExitGuard.canExit(throwingScope), isFalse);
  });

  test('OCR product creation uses the adaptive review workspace', () {
    expect(source, contains('OcrProductReviewWorkspace('));
    expect(source, isNot(contains('ProductDuplicateReviewDialog(')));
    expect(source, isNot(contains('_minTableInnerWidth')));
    expect(source, contains('persistComputedImageFingerprints: false'));
  });

  test(
      'preview has one desktop DataRow per invoice product and compact fallback',
      () {
    final previewTable = _section(
      source,
      'Widget desktopProductTable(List<DataRow> rows)',
      'DataRow previewDataRow(ParsedLineItem item, int index)',
    );
    final previewRow = _section(
      source,
      'DataRow previewDataRow(ParsedLineItem item, int index)',
      'final primaryLabel =',
    );

    expect(source, contains('final tableLayout = width >= 900;'));
    expect(
      previewTable,
      contains("key: const Key('ocr-preview-products-table')"),
    );
    expect(
      previewTable,
      contains("key: Key('ocr-preview-table-header')"),
    );
    expect(previewTable, contains('DataTable('));
    _expectInOrder(previewTable, const [
      "'#'",
      "'Producto leído'",
      "'Código proveedor'",
      "'Cant.'",
      "'Costo unit. factura'",
      "'Dscto.'",
      "'Total línea'",
      "'Producto ERP'",
      "'Estado'",
    ]);

    expect(
      previewRow,
      contains("key: ValueKey<String>('ocr-preview-row-\$index')"),
    );
    for (final cell in [
      'product',
      'code',
      'quantity',
      'unit-price',
      'discount',
      'total',
      'erp-product',
      'status',
    ]) {
      expect(
        previewRow,
        contains("key: Key('ocr-preview-cell-$cell-\$index')"),
        reason: '$cell must remain a stable column cell in every preview row',
      );
    }
    expect(
      source,
      contains(
        'else if (tableLayout)\n'
        '                    desktopProductTable([',
      ),
    );
    expect(
      source,
      contains('previewDataRow(data.lineItems[index], index)'),
    );
    expect(
      source,
      contains(
        'else\n'
        '                    for (var index = 0;',
      ),
    );
    expect(source, contains('productRow(data.lineItems[index], index)'));
  });

  test('preview projects a composite as real inventory lines once', () {
    const frontId = '20000000-0000-4000-8000-000000000001';
    const rearId = '20000000-0000-4000-8000-000000000002';
    final evidence = SupplierOptionEvidence(
      variantKey: 'sku:immutable-bucklos-set',
      packCount: 2,
      rawUnitToken: 'pcs',
    );
    final resolution = SupplierVariantResolution.fromLookupJson(
      <String, dynamic>{
        'status': 'resolved',
        'authoritative': true,
        'id': '10000000-0000-4000-8000-000000000001',
        'tenant_id': '10000000-0000-4000-8000-000000000002',
        'supplier_id': '10000000-0000-4000-8000-000000000003',
        'listing_id': '1005005789807730',
        'variant_key': evidence.variantKey.value,
        'revision_number': 1,
        'state': 'active',
        'resolution_kind': 'composite',
        'option_evidence_hash': evidence.sha256Hex,
        'option_pack_count': 2,
        'option_unit_class': 'piece',
        'pack_evidence_conflict': false,
        'edge_set_hash':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'operation_id': '10000000-0000-4000-8000-000000000004',
        'request_fingerprint':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'decision_source': 'operator_confirmed',
        'decision_evidence_hash':
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        'decision_evidence': <String, dynamic>{
          'confirmation_surface': 'purchase_invoice_ocr',
        },
        'edges': <Map<String, dynamic>>[
          <String, dynamic>{
            'edge_id': '30000000-0000-4000-8000-000000000001',
            'edge_ordinal': 1,
            'product_id': frontId,
            'catalog_units_per_purchase': 1,
            'allocation_ratio': 0.5,
            'component_role': 'front',
          },
          <String, dynamic>{
            'edge_id': '30000000-0000-4000-8000-000000000002',
            'edge_ordinal': 2,
            'product_id': rearId,
            'catalog_units_per_purchase': 1,
            'allocation_ratio': 0.5,
            'component_role': 'rear',
          },
        ],
      },
    );
    final item = ParsedLineItem(
      description: 'BUCKLOS Front-Rear Calipers',
      sourcePurchaseQuantity: 3,
      quantity: 3,
      total: 35737,
      supplierResolution: resolution,
    );
    inventory_models.Product product(
      String id,
      String sku,
      String name,
    ) =>
        inventory_models.Product(
          id: id,
          tenantId: '10000000-0000-4000-8000-000000000002',
          sku: sku,
          name: name,
          price: 0,
          cost: 0,
        );

    final components = buildOcrPreviewResolutionComponents(
      item: item,
      productsById: <String, inventory_models.Product>{
        frontId: product(frontId, 'AE0145', 'Caliper delantero BUCKLOS'),
        rearId: product(rearId, 'AE0144', 'Caliper trasero BUCKLOS'),
      },
    );

    expect(resolution.isResolved, isTrue);
    expect(components, hasLength(2));
    expect(
      components.map((component) => component.displayLabel),
      <String>[
        '3 × AE0145 · delantero · Caliper delantero BUCKLOS',
        '3 × AE0144 · trasero · Caliper trasero BUCKLOS',
      ],
    );
    expect(
      buildOcrPreviewResolutionComponents(
        item: item,
        productsById: const <String, inventory_models.Product>{},
      ),
      isEmpty,
      reason: 'the preview must never display only part of a source graph',
    );
  });

  test('preview has one neutral handoff into product review', () {
    expect(source, contains("'Factura leída'"));
    expect(source, isNot(contains('Factura Procesada')));
    expect(source, isNot(contains('Productos Nuevos')));
    expect(source, isNot(contains("'Resolver 1 producto'")));
    expect(
      source,
      isNot(contains("'Resolver \$unresolvedProductCount productos'")),
    );

    expect(
      RegExp("key: const Key\\('ocr-preview-review-products'\\)")
          .allMatches(source),
      hasLength(1),
    );
    expect(
      source,
      contains(
        "'Revisar \$unresolved producto\${unresolved == 1 ? '' : 's'}'",
      ),
    );
  });

  test('AliExpress verification never treats supplier SKU as catalog SKU', () {
    final verifyOne = _section(
      source,
      'Future<ParsedLineItem> _verifySingleProduct',
      'ParsedLineItem _clearProductResolution',
    );
    final nameLookup = verifyOne.substring(
      verifyOne.indexOf('// PRIORITY 3: Fall back to searching by name'),
    );
    expect(verifyOne, contains('bool allowCatalogCodeLookup = true'));
    expect(
      verifyOne,
      matches(RegExp(r'if \(allowCatalogCodeLookup &&.*?getProductBySku',
          dotAll: true)),
    );
    expect(nameLookup, contains('if (allowNameFallback &&'));

    final batchVerification = _section(
      source,
      'Future<ParsedInvoice> _verifyProductsInDatabase',
      'String _formatError',
    );
    expect(
      batchVerification,
      contains('final isAliExpress = _looksLikeAliExpressInvoice(invoice);'),
    );
    expect(
      batchVerification,
      contains('allowNameFallback: allowNameFallback'),
    );
    expect(
      batchVerification,
      contains('allowCatalogCodeLookup: !isAliExpress'),
    );

    final manualLink = _section(
      source,
      'Future<bool> _useExistingProductForEntry',
      'void _changeProductDecision',
    );
    expect(manualLink, isNot(contains('_rememberAliExpressResolution(')));
    expect(
      manualLink,
      contains('SupplierOptionEvidence.requiresExplicitCompositionFor('),
    );
  });

  test('canonical semantics sees both cleaned and supplier source titles', () {
    final semantics = _section(
      source,
      'void _applyCanonicalProductSemantics',
      'Future<void> _checkSimilarProductsForNewEntries',
    );
    expect(
      semantics,
      contains('entry.originalItem.description.trim()'),
    );
    expect(
      semantics,
      contains('entry.originalNoisyTitle!.trim()'),
    );
    expect(semantics, contains("rawTitle: semanticTitles.join(' | ')"));
    expect(
      semantics,
      contains('ProductCatalogSemanticResolver.canonicalizeDisplayName'),
    );
  });

  test('duplicate matching consumes canonical category and brand evidence', () {
    expect(source, contains('_duplicateMatcherCategoryName(entry)'));
    expect(source, contains('_duplicateMatcherBrandName(entry)'));

    final categoryOwner = _section(
      source,
      'String? _duplicateMatcherCategoryName',
      'String? _duplicateMatcherBrandName',
    );
    expect(categoryOwner, contains('entry.categoryUserEdited'));
    expect(
      categoryOwner,
      contains('ProductCatalogSemanticEvidenceKind.rejectedCategoryHint'),
    );

    final brandOwner = _section(
      source,
      'String? _duplicateMatcherBrandName',
      'Future<void> _checkSimilarProductsForNewEntries',
    );
    expect(brandOwner, contains('entry.brandUserEdited'));
    expect(
      brandOwner,
      contains('ProductCatalogSemanticEvidenceKind.explicitBrand'),
    );
    expect(brandOwner, isNot(contains('entry.aiSuggestedBrandName')));
  });

  test('object-first category resolution still reconciles the brand', () {
    final semantics = _section(
      source,
      'void _applyCanonicalProductSemantics',
      'ProductCategoryResolution? _resolveObjectFirstCategory',
    );
    expect(semantics, contains('var categoryOutcomeHandled = false;'));
    expect(semantics, contains('if (!categoryOutcomeHandled &&'));
    final afterObjectResolution = semantics.substring(
      semantics.indexOf('final objectCategory ='),
    );
    final beforeBrandResolution = afterObjectResolution.substring(
      0,
      afterObjectResolution.indexOf('if (!entry.brandUserEdited) {'),
    );
    expect(beforeBrandResolution, isNot(contains('continue;')));
  });

  test('only catalog reconciliation or an operator writes selectedBrand', () {
    final aiInputs = _section(
      source,
      'Future<void> _aiCleanProductNamesForEntries',
      'void _applyCanonicalProductSemantics',
    );
    expect(aiInputs, contains('entry.aiSuggestedBrandName = addonBrand'));
    expect(aiInputs, contains('entry.aiSuggestedBrandName = result.brand'));
    expect(aiInputs, isNot(contains('entry.selectedBrand =')));
    expect(aiInputs, isNot(contains('scanBrandInName')));

    final canonical = _section(
      source,
      'void _applyCanonicalProductSemantics',
      'ProductCategoryResolution? _resolveObjectFirstCategory',
    );
    expect(canonical, contains('if (!entry.brandUserEdited) {'));
    expect(
      canonical,
      contains('entry.selectedBrand = resolution.brand;'),
    );
    expect(
      canonical,
      isNot(contains('entry.aiSuggestedBrandName = resolution.brand')),
    );

    final operatorWrites = RegExp(
      r'entry\.selectedBrand\s*=(?!=)',
    ).allMatches(source).length;
    expect(
      operatorWrites,
      4,
      reason:
          'dropdown, sibling reuse, strict AI catalog lookup, and canonical reconciliation are the only writers',
    );
    expect(
      source,
      contains('event: \'investigation.catalog_brand_resolution\''),
      reason: 'la escritura AI sólo acepta una marca real del catálogo',
    );
  });

  test('row work stays cancellable and does not masquerade as active search',
      () {
    expect(source, contains('int _bulkReviewGeneration = 0;'));
    expect(source, contains('if (!_ownsBulkReview(reviewGeneration)) return;'));
    expect(source, contains('onBack: _closeBulkReview'));
    expect(
      source,
      contains(
        'OcrProductResolutionState.unsearched =>\n'
        '        OcrProductReviewStatus.needsSearch',
      ),
    );
    expect(
      workspace,
      contains("key: Key('ocr-review-copy-sibling-\${line.id}')"),
      reason: 'la variante hermana sigue reutilizable sin ocupar una tarjeta',
    );
    expect(
      workspace,
      contains("label: const Text('Buscar pendientes')"),
      reason: 'la acción de lote sigue disponible en el encabezado',
    );
    expect(
      workspace,
      contains("primaryKey: Key('ocr-review-search-\${line.id}')"),
      reason: 'y la fila sin revisar conserva la suya',
    );
  });

  test('la conciliación es una tabla fluida, no una lona de ancho fijo', () {
    expect(workspace, contains("key: const Key('ocr-review-batch')"));
    expect(workspace, contains("key: const Key('ocr-review-table')"));
    expect(workspace, contains("key: const Key('ocr-review-table-header')"));

    // Contratos rechazados por el dueño el 2026-08-09. No vuelven.
    expect(workspace, isNot(contains('_minimumWidth = 1680')));
    expect(workspace, isNot(contains('scrollDirection: Axis.horizontal')));
    expect(workspace, isNot(contains('DataTable(')));
    expect(workspace, isNot(contains('dataRowMaxHeight')));
    expect(workspace, isNot(contains('class _DesktopAlternativesBand')));
    expect(workspace, isNot(contains('_SearchableDropdown')));

    // Una fila por línea, en orden de factura, de alto uniforme.
    expect(
      workspace,
      contains('for (var index = 0; index < lines.length; index++)'),
    );
    expect(workspace, contains('static const double rowHeight = 60;'));
    expect(
      workspace,
      contains("key: ValueKey<String>('ocr-review-row-\${lines[index].id}')"),
    );
    // Alto mínimo, no fijo: una fila con una validación pendiente crece para
    // decirla en vez de recortarla.
    expect(
      workspace,
      contains('minHeight: _ReconciliationTable.rowHeight'),
    );
    expect(
        workspace,
        isNot(contains(
            'SizedBox(\n          height: _ReconciliationTable.rowHeight')));
    // El nivel de columnas se decide con el ancho real que recibe la tabla.
    expect(workspace, contains('enum _TableTier'));
    expect(workspace, contains('double _requiredWidth('));
    expect(workspace, contains('_TableTier? _tierFor(double inner)'));
  });

  test('el ancho decide la composición, no una tabla que se encoge', () {
    expect(
      workspace,
      contains('static const double touchBreakpoint = 900;'),
    );
    expect(
      workspace,
      contains('static const double fullTableBreakpoint = 1180;'),
    );
    expect(workspace, contains('class _CompactLineList'));
    // Compacto es una lista con divisores, no una pared de tarjetas.
    expect(workspace, contains('Divider(height: 1, thickness: 1'));
  });

  test('categoría y marca usan el selector canónico buscable', () {
    expect(workspace, contains('VbSearchableSelect<Category>'));
    expect(workspace, contains('VbSearchableSelect<ProductBrand>'));
    // El campo cerrado dice el nombre corto; la ruta sólo desambigua.
    expect(workspace, contains('label: category.name'));
    expect(
      workspace,
      contains("(byName[category.name] ?? 0) > 1 ? category.fullPath : null"),
    );
  });

  test('los parecidos abren un overlay centrado, nunca dentro de la fila', () {
    expect(workspace, contains('onOpenCandidates'));
    expect(
      workspace,
      contains("key: Key('ocr-review-alternatives-\${line.id}')"),
    );
    expect(source, contains('OcrCandidatePicker.show('));
    expect(source, contains('Future<void> _openCandidatePicker('));
    expect(
        source,
        contains(
            'onSearch: (query) => inventoryService.searchProductPreviews('));
  });

  test('el pie dice el siguiente paso exacto', () {
    expect(workspace, contains('String get nextStep'));
    expect(workspace, contains("key: const Key('ocr-review-next-step')"));
    expect(workspace, contains("key: const Key('ocr-review-primary')"));
    expect(workspace, contains("key: const Key('ocr-review-back')"));
  });

  test('el pie dice la verdad sobre lo que falta, no un futuro conteo', () {
    // El defecto que vio el dueño en runtime: «Crear 7 productos» antes de que
    // existiera ninguna de esas siete decisiones.
    expect(source, contains('String _bulkPrimaryLabel('));
    expect(
      source,
      contains(
        'entry.resolutionState == OcrProductResolutionState.newProduct',
      ),
      reason: 'sólo cuenta las filas realmente confirmadas como nuevas',
    );
    expect(source, contains("'Faltan \$undecidedCount '"));
    expect(source, contains("'Completa \$incompleteCount '"));
    expect(source, contains("if (confirmedNewCount == 0) return 'Continuar';"));
    expect(
      source,
      isNot(contains("'Crear \$selectedNewCount producto")),
      reason: 'el conteo viejo contaba filas sin decidir',
    );
  });

  test('decidir «nuevo» reserva el SKU AE de esa fila en ese momento', () {
    expect(source, contains('Future<void> _confirmNewProductForEntry('));
    expect(source, contains('Future<void> _ensureReservedSkuForEntry('));
    expect(source, contains('await _ensureReservedSkuForEntry(entry)'));

    // La reserva es de la fila, no de un lote: cada fila lleva su propio SKU,
    // su clave y su generación. El comportamiento lo prueban las pruebas de
    // `AliExpressSkuReservationAuthority`; aquí sólo se fija de quién es.
    expect(source, contains('AliExpressSkuReservationAuthority'));
    expect(source, contains('String? reservedSku;'));
    expect(source, contains('String? skuOperationKey;'));
    expect(source, contains('int skuReservationGeneration = 0;'));
    expect(
        source, contains('AliExpressSkuRowIdentity _reservationIdentityFor('));
    expect(source, contains('sourceRowIndex: entry.sourceRowIndex'));
    expect(
      source,
      isNot(contains('_reserveAliExpressSkusForEntries(selectedEntries)')),
      reason: 'la reserva por lote compartía una clave entre filas distintas',
    );
    // El código lo da la base: crear consume la reserva, nunca el texto.
    expect(
      source,
      contains('String get sku =>'),
    );
    expect(source, contains(r"requiresDuplicateReview ? (reservedSku ?? '')"));

    // Y la fila lo cuenta: ocupada, error y reintento.
    expect(workspace,
        contains("key: Key('ocr-review-sku-reserving-\${line.id}')"));
    expect(workspace, contains("key: Key('ocr-review-sku-retry-\${line.id}')"));
    expect(source, contains('onRetrySkuReservation: (lineId)'));
  });

  test('la categoría la decide el objeto, no una palabra vecina', () {
    // El resolvedor canónico existía pero no estaba conectado: por eso una
    // herradura reconocida en la foto terminaba archivada en «Frenos».
    expect(
        source, contains('ProductCategoryResolver(categories: _categories)'));
    expect(
        source, contains('_resolveObjectFirstCategory(entry, objectResolver)'));
    expect(
      source,
      contains('ProductCategoryRefusal.conflictingEvidence'),
      reason:
          'evidencia en conflicto se manda a revisión, no a una hoja plausible',
    );
    expect(source,
        contains('entry.categoryReviewReason = objectCategory.reviewReason'));
    // Y el motivo llega a la fila en palabras, no como un campo vacío.
    expect(
      source,
      contains('entry.categoryReviewReason ??'),
    );
  });

  test('una sola lectura de la foto alimenta nombre, categoría y matching', () {
    // Dos llamadas por producto sobre la misma imagen: una para el nombre y
    // otra para el objeto. La regla «la visión siempre corre» habría duplicado
    // eso para siempre.
    expect(source, contains('AIProductImageAnalysis? aiVisualAnalysis;'));
    expect(source, contains('entry.aiVisualAnalysis ='));
    expect(source, contains('result.visualAnalysis ?? entry.aiVisualAnalysis'));
    expect(source, contains('duplicateMatcher.primeVisualReading('));
    expect(matcher, contains('void primeVisualReading('));
    expect(
      matcher,
      isNot(contains('if (profile.familyId == null)')),
      reason: 'una familia de texto equivocada no puede suprimir la foto',
    );
  });

  test('el host real ejecuta autoridad, investigación y matching en ese orden',
      () {
    final flow = _section(
      source,
      'Future<void> _checkSimilarProductsForNewEntries',
      'void _reconcileListingGroupResults()',
    );
    _expectInOrder(flow, const <String>[
      'lookupAuthority: () async {',
      'await _resolveSupplierVariantResolution(current)',
      'investigate: () async {',
      '_investigateProductEntriesAIPrimary(',
      'match: (_) => duplicateMatcher.resolveCandidates(',
    ]);
    expect(flow, contains('ProductIdentityReviewCoordinator<'));
    expect(source, contains('requireAIPrimaryInvestigation: true'));
    expect(
      flow,
      isNot(contains('_aiCleanProductNamesForEntries(')),
      reason: 'el cleaner legado no puede sustituir la investigación primaria',
    );
  });

  test('una revisión de fila posee un receipt y una sola recomputación', () {
    final investigation = _section(
      source,
      'Future<void> _investigateProductEntriesAIPrimary',
      'Future<void> _aiCleanProductNamesForEntries',
    );
    final entry = source.substring(source.indexOf('class _NewProductEntry'));
    expect(investigation, contains('entry.resolutionRevision'));
    expect(
      investigation,
      contains('!entry.ownsInvestigationForRevision(entry.resolutionRevision)'),
    );
    expect(investigation, contains('entry.aiInvestigationRevision = revision'));
    expect(entry, contains('AIProductIdentityInvestigation? aiInvestigation;'));
    expect(entry, contains('int? aiInvestigationRevision;'));
    expect(entry, contains('resolutionRevision++;'));
    expect(entry, contains('aiInvestigation = null;'));
    expect(entry, contains('aiInvestigationRevision = null;'));
    expect(source, contains('const Duration(milliseconds: 450)'));
    expect(source, contains('_scheduleAIIdentityRecompute(entry)'));
  });

  test('el picker muestra la decisión cacheada sin recomputar al abrir', () {
    expect(source, contains('entry.duplicateResult?.operatorChoices'));
    expect(source, contains('entry.duplicateResult?.categoryConflicts'));
    expect(
      source,
      contains('!candidate.isReviewOnlyFamilyScope'),
      reason: 'recall manual sin familia no se presenta como viable',
    );
    expect(
      source,
      contains('_currentSemanticReviewSummary(entry)'),
      reason: 'la fila no debe renderizar un fallo de familia ya resuelto',
    );
    expect(
      source,
      contains(
        "replaceFirst('No se pudo determinar la familia del producto.', '')",
      ),
      reason: 'sólo se retira la cláusula obsoleta, no otros conflictos',
    );
    expect(
      source,
      contains(
        'cachedChoices.where((candidate) => candidate.isRuledOut).length',
      ),
      reason: 'los descartados conservan su propio conteo honesto',
    );
    expect(source, contains('current.markSearchResult('));
    expect(
      source,
      contains('supplierResolutionProposal: resolutionProposal'),
      reason: 'la misma decisión cacheada debe conservar la descomposición',
    );
    expect(source, isNot(contains('onLoadOptions:')));
    expect(source, isNot(contains('_loadCandidateOptions(')));
    expect(
      source,
      isNot(contains('ProductDuplicateShortlistScope.operatorChoice')),
    );
    expect(picker, isNot(contains('onLoadOptions')));
    expect(
      picker,
      contains(
        'final offered = orderOcrCandidateChoices(widget.candidates);',
      ),
      reason: 'el picker usa la misma prioridad estable que la fila',
    );
    expect(
      source,
      contains(
        'final rowCandidates = orderOcrCandidateChoices(cachedChoices);',
      ),
      reason: 'la fila no sustituye el primer resultado por un conflicto',
    );
    expect(picker, contains('ocr-candidate-ruled-out-heading'));
    expect(picker, contains('ocr-candidate-category-conflicts-heading'));
    expect(picker, contains('widget.categoryConflicts'));
    expect(source,
        contains('allowCreateNew: entry.duplicateResult?.adjudicationState'));
    expect(picker, contains('widget.allowCreateNew'));
    expect(
      picker,
      contains(
        'Buscar manualmente en todo el catálogo por nombre, SKU o marca',
      ),
    );
  });

  test('probe, categoría y resolución conservan el título del proveedor', () {
    final probe = _section(
      source,
      'ProductDuplicateProbe _duplicateProbeFor(',
      'OcrProductReviewLine _buildProductReviewLine(',
    );
    final category = _section(
      source,
      'ProductCategoryResolution? _resolveObjectFirstCategory(',
      'String? _duplicateMatcherCategoryName(',
    );
    final resolution = _section(
      source,
      'Future<SupplierVariantResolution?> _rememberAliExpressResolution(',
      'Future<void> _uploadSelectedEntryImageForCreation(',
    );

    expect(probe, contains('sourceTitle: entry.supplierIdentityTitle'));
    expect(
      probe,
      contains(
        'selectedVariant: _aliExpressVariantLabelForLine(entry.originalItem)',
      ),
      reason: 'la variante elegida viaja como evidencia propia, no se '
          'reconstruye desde el título del menú',
    );
    expect(
        category, contains('final sourceTitle = entry.supplierIdentityTitle'));
    expect(category, contains('sourceTitle: sourceTitle'));
    expect(
      resolution,
      contains("'source_title': entry.supplierIdentityTitle"),
    );
    expect(
      source,
      contains('String get supplierIdentityTitle {'),
      reason: 'los tres consumidores dependen de una sola evidencia inmutable',
    );
  });

  test('un error del grafo de proveedor no cae al matcher', () {
    final graphLookup = _section(
      source,
      'Future<SupplierVariantResolution?> _resolveSupplierVariantResolution(',
      'Future<bool> _useSupplierVariantResolutionForEntry(',
    );
    final matcherCoordinator = _section(
      source,
      'Future<void> _checkSimilarProductsForNewEntries',
      'void _reconcileListingGroupResults()',
    );

    expect(
      graphLookup,
      contains(
        'result.status == SupplierVariantResolutionStatus.notFound',
      ),
      reason: 'sólo una ausencia comprobada habilita el matcher',
    );
    expect(graphLookup, contains('throw StateError('));
    expect(
      matcherCoordinator,
      isNot(contains('catch (resolutionError)')),
      reason: 'un error de autoridad no equivale a que el alias no exista',
    );
  });

  test('la resolución exacta exige variante inmutable y receipt verificado',
      () {
    final immutableVariant = _section(
      source,
      'String? _aliExpressImmutableVariantKeyForLine(',
      'String? _aliExpressVariantLabelForLine(',
    );
    final resolveGraph = _section(
      source,
      'Future<SupplierVariantResolution?> _resolveSupplierVariantResolution(',
      'Future<bool> _useSupplierVariantResolutionForEntry(',
    );
    final rememberGraph = _section(
      source,
      'Future<SupplierVariantResolution?> _rememberAliExpressResolution(',
      'Future<void> _uploadSelectedEntryImageForCreation(',
    );

    expect(immutableVariant, contains(r"r'^VARIANT_KEY:\s*(.+)$'"));
    expect(
      immutableVariant,
      contains(
        "if (!value.startsWith('sku:') && !value.startsWith('props:'))",
      ),
    );
    expect(immutableVariant, isNot(contains("return 'default'")));
    expect(immutableVariant, isNot(contains('imageSegment')));
    expect(
      resolveGraph,
      contains('_supplierOptionEvidenceForLine(entry.originalItem)'),
    );
    expect(
      rememberGraph,
      contains('_supplierOptionEvidenceForLine(entry.originalItem)'),
    );
    expect(resolveGraph, contains('.resolve('));
    expect(resolveGraph, contains('if (result.isResolved) return result;'));
    expect(
      resolveGraph,
      contains(
        'result.status == SupplierVariantResolutionStatus.notFound',
      ),
    );
    expect(rememberGraph, contains('.remember('));
    expect(rememberGraph, contains('SupplierVariantResolutionKind.single'));
    expect(rememberGraph, contains("'source_line_key': sourceLineKey"));
    expect(source, isNot(contains('resolveSupplierProductAlias(')));
    expect(source, isNot(contains('rememberSupplierProductAlias(')));
  });

  test('el embudo de cierre devuelve a la vista previa con identidad ERP', () {
    // Vincular escribe la identidad ERP en la línea de la factura…
    final link = _section(
      source,
      'Future<bool> _useExistingProductForEntry',
      'void _changeProductDecision',
    );
    expect(link, contains('matchedProductId: productId'));
    expect(link, contains('matchedProductName: product.name'));
    expect(link, contains('existsInDatabase: true'));
    expect(link, contains('_parsedData = parsedData.copyWith(lineItems:'));

    // …y crear hace lo mismo, y sólo entonces cierra la revisión.
    final create = _section(
      source,
      'Future<void> _createBulkProducts() async {',
      'Future<void> _pickImage',
    );
    expect(create, contains('matchedProductId: savedProduct.id'));
    expect(create, contains('sku: savedProduct.sku'));
    expect(
      create,
      contains('_showBulkCreate = _newProductEntries.any('),
      reason: 'se vuelve a la factura cuando ya no queda nada por crear',
    );

    // La aplicación al borrador sigue siendo una acción explícita del dueño.
    expect(source, contains("'Usar esta factura'"));
    expect(source, contains('_handleUseParsedData(data)'));
    expect(
      RegExp(r'widget\.onComplete\(').allMatches(source),
      hasLength(1),
      reason: 'onComplete tiene un solo disparador, y es ese botón',
    );
    final apply = _section(
      source,
      'Future<void> _handleUseParsedData(',
      'Future<void> _pickImage',
    );
    expect(apply, contains('await widget.onComplete(data)'));
  });

  test('la vista previa de la factura llena su host', () {
    // El piso es aritmética de las celdas, no una cifra elegida a ojo: bajarlo
    // hacía que la tabla dijera «acá quepo» y cortara `Total línea` y `Estado`
    // con el scroll ya desactivado.
    final floor =
        RegExp(r'const double _previewTableFloor = (\d+);').firstMatch(source);
    expect(floor, isNotNull);
    expect(
      int.parse(floor!.group(1)!),
      greaterThanOrEqualTo(1286),
      reason: 'celdas 1134 + 8 separaciones de 16 + 2 márgenes de 12',
    );
    expect(source, contains('NeverScrollableScrollPhysics()'));
    expect(
      source,
      contains('available >= _previewTableFloor'),
      reason: 'la decisión sale del ancho realmente recibido',
    );
    expect(
      source,
      contains("key: const Key('ocr-preview-products-table')"),
    );
    for (final cell in const [
      'product',
      'code',
      'quantity',
      'unit-price',
      'discount',
      'total',
      'status',
    ]) {
      expect(
        source,
        contains("key: Key('ocr-preview-cell-$cell-\$index')"),
        reason: 'la columna $cell es parte del documento',
      );
    }
  });

  test('el matcher recibe las marcas y el árbol de categorías reales', () {
    expect(source,
        contains('ProductDuplicateMatcherService _buildDuplicateMatcher('));
    expect(source, contains('knownBrands: _brands.map((brand) => brand.name)'));
    expect(
      source,
      contains(
          'ProductCatalogIdentityIndex.buildCategoryAncestry(_categories)'),
    );
    expect(source, contains('persistComputedImageFingerprints: false'));
  });

  test('host preserves batch tools and blocks Back while creating', () {
    expect(
      source,
      contains('onSearchPending: pendingSimilaritySearch.isEmpty'),
    );
    expect(source, contains('onSkuChanged: (lineId, _) {'));
    expect(source, contains('onReplaceImage: (lineId) {'));
    expect(source, contains('onRemoveImage: (lineId) {'));
    expect(source, contains('void _closeBulkReview() {'));
    expect(source, contains('if (!mounted || _creatingProducts) return;'));
    expect(source, contains('readOnly: _creatingProducts'));
    expect(
      workspace,
      contains('onBack: widget.readOnly ? null : widget.callbacks.onBack'),
    );
    expect(workspace, contains("key: const Key('ocr-review-back')"));
  });

  test(
      'global pending search is filtered twice and a second click is idempotent',
      () {
    final searchPolicy = _section(
      source,
      'bool _needsSimilaritySearch(_NewProductEntry entry)',
      'Widget _buildBulkCreateScreen()',
    );
    expect(searchPolicy, contains('entry.isSelected'));
    expect(searchPolicy, contains('entry.requiresDuplicateReview'));
    expect(searchPolicy, contains('entry.linkedProduct != null'));
    expect(searchPolicy, contains('entry.isAICleaningName'));
    expect(searchPolicy, contains('entry.isCheckingSimilar'));
    expect(searchPolicy, contains('entry.isLinkingExisting'));
    expect(searchPolicy, contains('entry.isUploadingImage'));
    expect(searchPolicy, contains('OcrProductResolutionState.unsearched'));
    expect(searchPolicy, contains('OcrProductResolutionState.failed'));
    expect(
      searchPolicy,
      contains('_newProductEntries.where(_needsSimilaritySearch)'),
    );

    final host = _section(
      source,
      'Widget _buildBulkCreateScreen()',
      'OcrProductReviewLine _buildProductReviewLine',
    );
    expect(host, contains('_pendingSimilaritySearchEntries()'));
    expect(
      host,
      matches(RegExp(
        r'onSearchPending:\s*pendingSimilaritySearch\.isEmpty\s*\?\s*null',
      )),
    );
    expect(
      host,
      matches(RegExp(
        r'onSearchPending:.*?_pendingSimilaritySearchEntries\(\).*?'
        r'targetEntries:',
        dotAll: true,
      )),
    );

    final matcher = _section(
      source,
      'Future<void> _checkSimilarProductsForNewEntries',
      'Future<bool> _useExistingProductForEntry',
    );
    final failClosedFilter = matcher.indexOf('.where(_needsSimilaritySearch)');
    final startsSearch = matcher.indexOf('markSearching()');
    expect(failClosedFilter, greaterThanOrEqualTo(0));
    expect(startsSearch, greaterThan(failClosedFilter));

    // `markSearching` synchronously makes the row busy. Because every click
    // recomputes the policy and the worker filters again, an immediate second
    // click cannot enqueue a resolved or already-running row.
    expect(host, isNot(contains('targetEntries: pendingSimilaritySearch')));
  });

  test('Back and reopen reuse the exact review draft for the same OCR document',
      () {
    expect(source, contains('int _parsedInvoiceEpoch = 0;'));
    expect(source, contains('int? _productReviewDraftEpoch;'));

    final opening = _section(
      source,
      'Future<void> _openBulkCreateScreen()',
      'bool _ownsOpeningBulkReview',
    );
    expect(
        opening, contains('_productReviewDraftEpoch == _parsedInvoiceEpoch'));
    expect(opening, contains('_newProductEntries.isNotEmpty'));
    expect(opening, contains('_showBulkCreate = true'));
    expect(opening, contains('_newProductEntries.any(_needsSimilaritySearch)'));
    expect(
        opening, contains('_runAliExpressProductAnalysis(reviewGeneration)'));

    final reuseDraft = opening.indexOf(
      '_productReviewDraftEpoch == _parsedInvoiceEpoch',
    );
    final rebuildDraft = opening.indexOf('final nextEntries = newProducts');
    expect(reuseDraft, greaterThanOrEqualTo(0));
    expect(rebuildDraft, greaterThan(reuseDraft));

    final resumeDraft = _section(
      opening,
      'if (canResumeDraft)',
      '// Get new products',
    );
    expect(resumeDraft, contains('return;'));

    final closing = _section(
      source,
      'void _closeBulkReview()',
      'void _finishBulkReview()',
    );
    expect(closing, contains('entry.cancelTransientReviewWork()'));
    expect(closing, isNot(contains('entry.dispose()')));
    expect(closing, isNot(contains('_newProductEntries.clear()')));

    final transientCancellation = _section(
      source,
      'void cancelTransientReviewWork()',
      'bool _suppressNameEditTracking',
    );
    expect(transientCancellation, contains('isAICleaningName'));
    expect(transientCancellation, contains('isCheckingSimilar'));
    expect(transientCancellation, contains('isLinkingExisting'));
    expect(transientCancellation, contains('isUploadingImage'));
    expect(
      transientCancellation,
      contains('resolutionState = OcrProductResolutionState.unsearched'),
    );
    expect(transientCancellation, contains('resolutionRevision++'));
    expect(
      transientCancellation,
      isNot(contains('markNewProduct()')),
    );
    expect(
      transientCancellation,
      isNot(contains('clearLinkedProduct()')),
    );

    // Reusing the same entry objects is what preserves all mutable draft data:
    // controllers, selection, local image bytes and both resolved summaries.
    expect(resumeDraft, isNot(contains('imageBytes = null')));
    expect(resumeDraft, isNot(contains('isSelected = true')));
    expect(resumeDraft, isNot(contains('clearLinkedProduct()')));
    expect(resumeDraft, isNot(contains('markNewProduct()')));
  });

  test('critical creation blocks every OCR exit owner until it settles', () {
    expect(
      source,
      contains(
        'bool get blocksOwnerExit =>\n'
        '      _creatingProducts || _isApplyingResult || _anyRowReservingSku;',
      ),
      reason:
          'una reserva en vuelo también es una operación que no se abandona',
    );
    expect(source, contains('if (blocksOwnerExit)'));
    expect(source, contains('readOnly: _creatingProducts'));
    expect(
      workspace,
      contains('onBack: widget.readOnly ? null : widget.callbacks.onBack'),
    );

    expect(purchaseForm, contains('class PurchaseInvoiceExitGuard'));
    expect(purchaseForm, contains('PurchaseInvoiceExitGuard.register('));
    expect(purchaseForm, contains('PurchaseInvoiceExitGuard.unregister('));
    expect(purchaseForm, contains('widget.exitGuardScope'));
    expect(purchaseForm, contains('registerWorkspaceCloseGuard('));
    expect(purchaseForm, contains('unregisterWorkspaceCloseGuard('));
    expect(purchaseForm,
        contains('_ocrWorkspaceKey.currentState?.blocksOwnerExit'));
    expect(purchaseForm, contains('Future<bool> _confirmCanLeave()'));
    expect(
      purchaseForm,
      contains('onPopInvokedWithResult: (didPop, _)'),
    );
    expect(
      purchaseForm,
      contains('onPressed: _isApplyingOcrResult'),
    );
    expect(
        purchaseForm, contains('_ocrWorkspaceKey.currentState?.handleBack()'));

    for (final route in [
      '/purchases/new',
      '/purchases/:id',
      '/purchases/:id/detail',
      '/purchases/:id/edit',
    ]) {
      final routeBlock = _routeSection(router, route);
      expect(routeBlock, contains('onExit: guardPurchaseInvoiceExit'));
      expect(
        routeBlock,
        contains('exitGuardScope: purchaseInvoiceExitKey(state)'),
      );
    }
    expect(
      RegExp(r'final purchaseInvoiceExitScope = Object\(\);')
          .allMatches(router),
      hasLength(1),
    );
    expect(
      router,
      contains(
        'Object purchaseInvoiceExitKey(GoRouterState state) =>\n'
        '        (purchaseInvoiceExitScope, state.pageKey);',
      ),
    );
    expect(
      router,
      contains(
        'erp.PurchaseInvoiceExitGuard.canExit(\n'
        '        purchaseInvoiceExitKey(state),',
      ),
    );
  });

  test('excluded invoice rows remain visible and outside creation progress',
      () {
    expect(
      source,
      contains(
        'lines: _newProductEntries\n'
        '          .map(_buildProductReviewLine)\n'
        '          .toList(growable: false)',
      ),
    );
    expect(source, contains('onSelectionChanged: (lineId, selected)'));
    expect(workspace, contains('this.isSelected = true'));
    expect(
      workspace,
      contains('lines.where((line) => line.isSelected).toList()'),
    );
  });

  test('purchase host gives OCR a full in-place adaptive surface', () {
    expect(
      purchaseForm,
      contains('Positioned.fill(child: _buildOcrWorkspace())'),
    );
    expect(
      purchaseForm,
      contains("key: const Key('purchase-ocr-workspace-back')"),
    );
    expect(purchaseForm, contains('child: OCRUploadWidget('));
    expect(purchaseForm, contains('offstage: _showingOcrWorkspace'));
    expect(purchaseForm, isNot(contains('OCRCleanupPage')));
    expect(purchaseForm, isNot(contains("tooltip: 'Reparar Datos OCR'")));
  });
}

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing start: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex), reason: 'Missing end: $end');
  return source.substring(startIndex, endIndex);
}

String _routeSection(String router, String route) {
  final start = router.indexOf("path: '$route'");
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing route: $route');
  final nextRoute = router.indexOf('GoRoute(', start + 1);
  return router.substring(start, nextRoute < 0 ? router.length : nextRoute);
}

void _expectInOrder(String source, List<String> snippets) {
  var previous = -1;
  for (final snippet in snippets) {
    final index = source.indexOf(snippet, previous + 1);
    expect(index, greaterThan(previous),
        reason: 'Missing or reordered: $snippet');
    previous = index;
  }
}
