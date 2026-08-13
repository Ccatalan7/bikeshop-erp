import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/supplier_resolution_proposal.dart';
import 'package:vinabike_erp/shared/models/supplier_variant_resolution.dart';

void main() {
  group('supplier resolution proposal', () {
    test('3 caliper sets become 3 front + 3 rear through canonical set',
        () async {
      final front = _product(_frontId, 'AE0145', 'Caliper delantero', cost: 10);
      final rear = _product(_rearId, 'AE0144', 'Caliper trasero', cost: 10);
      final set = _product(
        _setId,
        'SET001',
        'Juego calipers delantero y trasero',
        isSet: true,
        setType: 'front_rear',
      );
      final composition = ProductSetCompositionSnapshot(
        setProductId: _setId,
        fullSetsAvailable: 4,
        components: <ProductSetCompositionItem>[
          _setItem(front, position: 1, label: 'Delantero'),
          _setItem(rear, position: 2, label: 'Trasero'),
        ],
      );
      const decision = AIProductMatchDecision(
        decision: AIProductMatchDecisionKind.composite,
        productId: null,
        components: <AIProductMatchComponent>[
          AIProductMatchComponent(
            productId: _frontId,
            quantity: 1,
            role: AIProductMatchComponentRole.front,
          ),
          AIProductMatchComponent(
            productId: _rearId,
            quantity: 1,
            role: AIProductMatchComponentRole.rear,
          ),
        ],
        reason: 'La publicación vende ambos lados.',
        confidence: 0.96,
      );

      final proposal = await SupplierResolutionProposalBuilder.build(
        decision: decision,
        investigation: null,
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:caliper-pair',
          packCount: 2,
          rawUnitToken: 'pcs',
        ),
        sourcePurchaseQuantity: 3,
        catalog: <Product>[front, rear, set],
        lookupSetComposition: (product) async =>
            product.id == _setId ? composition : null,
      );

      expect(proposal, isNotNull);
      expect(proposal!.usesCanonicalSet, isTrue);
      expect(proposal.kind, SupplierVariantResolutionKind.single);
      expect(proposal.edges.single.productId, _setId);
      expect(proposal.edges.single.componentRole, 'catalog_set');
      expect(proposal.invoiceImpactSummary, contains('3 × AE0145 · delantero'));
      expect(proposal.invoiceImpactSummary, contains('3 × AE0144 · trasero'));
      expect(proposal.persistedQuantity, 3);
    });

    test('without a canonical set the same pair uses ordered direct edges',
        () async {
      final front = _product(_frontId, 'AE0145', 'Caliper delantero', cost: 20);
      final rear = _product(_rearId, 'AE0144', 'Caliper trasero', cost: 10);
      const decision = AIProductMatchDecision(
        decision: AIProductMatchDecisionKind.composite,
        productId: null,
        components: <AIProductMatchComponent>[
          AIProductMatchComponent(
            productId: _frontId,
            quantity: 1,
            role: AIProductMatchComponentRole.front,
          ),
          AIProductMatchComponent(
            productId: _rearId,
            quantity: 1,
            role: AIProductMatchComponentRole.rear,
          ),
        ],
        reason: 'Dos componentes independientes.',
        confidence: 0.94,
      );

      final proposal = await SupplierResolutionProposalBuilder.build(
        decision: decision,
        investigation: null,
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:caliper-pair-direct',
          packCount: 2,
          rawUnitToken: 'pieces',
        ),
        sourcePurchaseQuantity: 3,
        catalog: <Product>[front, rear],
        lookupSetComposition: (_) async => null,
      );

      expect(proposal!.kind, SupplierVariantResolutionKind.composite);
      expect(
        proposal.edges.map((edge) => edge.componentRole),
        <String>['front', 'rear'],
      );
      expect(
        proposal.edges.fold<double>(
          0,
          (total, edge) => total + edge.allocationRatio,
        ),
        1,
      );
      expect(
        SupplierVariantResolution.validateGraph(
          kind: proposal.kind,
          edges: proposal.edges,
        ),
        isNull,
      );
    });

    test('BH59 10PCS becomes ten catalog units after grounded same identity',
        () async {
      final olive = _product(_oliveId, 'OL03', 'Oliva y pin Shimano BH59');
      const decision = AIProductMatchDecision(
        decision: AIProductMatchDecisionKind.same,
        productId: _oliveId,
        picks: <AIProductMatchPick>[
          AIProductMatchPick(
            productId: _oliveId,
            quantity: 1,
            role: AIProductMatchComponentRole.primary,
            basis: <AIProductMatchBasis>[
              AIProductMatchBasis.model,
              AIProductMatchBasis.image,
            ],
          ),
        ],
        reason: 'Es la oliva BH59 ofrecida.',
        confidence: 0.97,
      );

      final proposal = await SupplierResolutionProposalBuilder.build(
        decision: decision,
        investigation: _packInvestigation(count: 10),
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:bh59-10pcs',
          packCount: 10,
          rawUnitToken: 'pcs',
        ),
        sourcePurchaseQuantity: 1,
        catalog: <Product>[olive],
        lookupSetComposition: (_) async => null,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, SupplierVariantResolutionKind.homogeneous);
      expect(proposal.edges.single.productId, _oliveId);
      expect(proposal.edges.single.catalogUnitsPerPurchase, 10);
      expect(proposal.edges.single.componentRole, 'homogeneous');
      expect(proposal.persistedQuantity, 10);
      expect(proposal.invoiceImpactSummary, contains('10 × OL03'));
    });

    test('one pair without known composition stays unresolved', () async {
      final olive = _product(_oliveId, 'OL03', 'Oliva BH59');
      final proposal = await SupplierResolutionProposalBuilder.build(
        decision: const AIProductMatchDecision(
          decision: AIProductMatchDecisionKind.same,
          productId: _oliveId,
          reason: 'Misma pieza, paquete incierto.',
          confidence: 0.97,
        ),
        investigation: _packInvestigation(count: 1),
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:unknown-pair',
          packCount: 1,
          rawUnitToken: 'pair',
        ),
        sourcePurchaseQuantity: 1,
        catalog: <Product>[olive],
        lookupSetComposition: (_) async => null,
      );

      expect(proposal, isNull);
    });

    test('one left-right pair follows its proven two-component composition',
        () async {
      final left = _product(
        '00000000-0000-4000-8000-000000000021',
        'LR01-L',
        'Manilla izquierda',
      );
      final right = _product(
        '00000000-0000-4000-8000-000000000022',
        'LR01-R',
        'Manilla derecha',
      );
      final proposal = await SupplierResolutionProposalBuilder.build(
        decision: AIProductMatchDecision(
          decision: AIProductMatchDecisionKind.composite,
          productId: null,
          components: <AIProductMatchComponent>[
            AIProductMatchComponent(
              productId: left.id!,
              quantity: 1,
              role: AIProductMatchComponentRole.left,
            ),
            AIProductMatchComponent(
              productId: right.id!,
              quantity: 1,
              role: AIProductMatchComponentRole.right,
            ),
          ],
          reason: 'La fuente muestra ambas manos.',
          confidence: 0.96,
        ),
        investigation: _twoPartInvestigation(),
        optionEvidence: SupplierOptionEvidence(
          variantKey: 'sku:left-right-pair',
          packCount: 1,
          rawUnitToken: 'pair',
        ),
        sourcePurchaseQuantity: 4,
        catalog: <Product>[left, right],
        lookupSetComposition: (_) async => null,
      );

      expect(proposal, isNotNull);
      expect(proposal!.kind, SupplierVariantResolutionKind.composite);
      expect(
        proposal.edges.map((edge) => edge.componentRole),
        <String>['left', 'right'],
      );
      expect(proposal.invoiceImpactSummary, contains('4 × LR01-L · izquierdo'));
      expect(proposal.invoiceImpactSummary, contains('4 × LR01-R · derecho'));
    });
  });
}

AIProductIdentityInvestigation _twoPartInvestigation() {
  final base = _packInvestigation(count: 2);
  return AIProductIdentityInvestigation(
    schemaVersion: base.schemaVersion,
    promptVersion: base.promptVersion,
    modelId: base.modelId,
    cleanedName: 'Par de manillas izquierda y derecha',
    object: base.object,
    manufacturer: base.manufacturer,
    models: base.models,
    specs: base.specs,
    fitment: base.fitment,
    composition: const AIProductCompositionIdentity(
      kind: AIProductPackageKind.composite,
      components: <AIProductCompositionComponent>[
        AIProductCompositionComponent(
          label: 'manilla izquierda',
          role: AIProductCompositionRole.primary,
          quantity: 1,
        ),
        AIProductCompositionComponent(
          label: 'manilla derecha',
          role: AIProductCompositionRole.component,
          quantity: 1,
        ),
      ],
    ),
    packaging: const AIProductPackagingIdentity(
      count: 1,
      unitToken: 'pair',
      source: AIProductSpecSource.option,
    ),
    leafProposals: base.leafProposals,
    evidenceUsed: base.evidenceUsed,
    abstainReason: null,
    receipt: base.receipt,
    reason: 'La publicación identifica ambos lados.',
  );
}

AIProductIdentityInvestigation _packInvestigation({required int count}) {
  return AIProductIdentityInvestigation(
    schemaVersion: AIAssistantService.productIdentitySchemaVersion,
    promptVersion: AIAssistantService.productIdentityPromptKey,
    modelId: 'fake-pack-investigator',
    cleanedName: 'Oliva Shimano BH59',
    object: const AIProductObjectIdentity(label: 'oliva', confidence: 1),
    manufacturer: const AIProductManufacturerIdentity(
      value: 'Shimano',
      asserted: true,
      evidence: AIProductManufacturerEvidence.identity,
    ),
    models: const <AIProductModelIdentity>[
      AIProductModelIdentity(code: 'BH59', role: AIProductModelRole.identity),
    ],
    specs: const <AIProductSpecificationIdentity>[],
    fitment: const <String>[],
    composition: AIProductCompositionIdentity(
      kind: AIProductPackageKind.composite,
      components: <AIProductCompositionComponent>[
        AIProductCompositionComponent(
          label: 'oliva BH59',
          role: AIProductCompositionRole.component,
          quantity: count,
        ),
      ],
    ),
    packaging: AIProductPackagingIdentity(
      count: count,
      unitToken: 'pcs',
      source: AIProductSpecSource.option,
    ),
    leafProposals: const <AIProductLeafProposal>[],
    evidenceUsed: const <String>['selected_option', 'photo'],
    abstainReason: null,
    receipt: const AIProductIdentityReceipt(
      rowRevision: '1',
      catalogVersion: 'catalog',
      treeVersion: 'tree',
      promptVersion: AIAssistantService.productIdentityPromptKey,
      modelId: 'fake-pack-investigator',
      listingId: 'listing',
      variantKey: 'sku:variant',
      imageIdentity: 'image',
    ),
    reason: 'Pack visible y variante seleccionada.',
  );
}

Product _product(
  String id,
  String sku,
  String name, {
  double cost = 1,
  bool isSet = false,
  String? setType,
}) {
  return Product(
    id: id,
    tenantId: _tenantId,
    name: name,
    sku: sku,
    price: cost * 2,
    cost: cost,
    isSet: isSet,
    setType: setType,
  );
}

ProductSetCompositionItem _setItem(
  Product product, {
  required int position,
  required String label,
}) {
  return ProductSetCompositionItem(
    id: product.id!,
    sku: product.sku,
    name: product.name,
    label: label,
    position: position,
    quantityInSet: 1,
    price: product.price,
    cost: product.cost,
    stockQuantity: product.inventoryQty,
  );
}

const _tenantId = '00000000-0000-4000-8000-000000000001';
const _frontId = '00000000-0000-4000-8000-000000000011';
const _rearId = '00000000-0000-4000-8000-000000000012';
const _setId = '00000000-0000-4000-8000-000000000013';
const _oliveId = '00000000-0000-4000-8000-000000000014';
