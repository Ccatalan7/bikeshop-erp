import '../../../ai_assistant/services/ai_service.dart';
import '../../models/inventory_models.dart';
import '../../../../shared/models/supplier_variant_resolution.dart';

typedef ProductSetCompositionLookup = Future<ProductSetCompositionSnapshot?>
    Function(Product setProduct);

/// One grounded inventory identity inside a supplier package.
class SupplierResolutionProposalItem {
  const SupplierResolutionProposalItem({
    required this.product,
    required this.catalogUnitsPerPurchase,
    required this.role,
  });

  final Product product;
  final int catalogUnitsPerPurchase;
  final AIProductMatchComponentRole role;
}

/// Reviewable bridge between an AI package decision and the durable supplier
/// resolution graph.
///
/// The proposal itself has no authority. Only an explicit operator
/// confirmation may persist [edges]. If an existing inventory set has exactly
/// the same component multiset, [edges] points to that canonical parent so the
/// established set stock kernel owns the eventual component movements.
class SupplierResolutionProposal {
  const SupplierResolutionProposal._({
    required this.kind,
    required this.items,
    required this.edges,
    required this.resolutionProducts,
    required this.sourcePurchaseQuantity,
    required this.reason,
    this.canonicalSetProduct,
    this.canonicalSetComposition,
  });

  final SupplierVariantResolutionKind kind;
  final List<SupplierResolutionProposalItem> items;
  final List<SupplierVariantResolutionEdge> edges;
  final List<Product> resolutionProducts;
  final double sourcePurchaseQuantity;
  final String? reason;
  final Product? canonicalSetProduct;
  final ProductSetCompositionSnapshot? canonicalSetComposition;

  bool get usesCanonicalSet => canonicalSetProduct != null;

  double get persistedQuantity =>
      sourcePurchaseQuantity *
      edges.fold<double>(
        0,
        (total, edge) => total + edge.catalogUnitsPerPurchase,
      );

  String get perPurchaseSummary => items.map(_itemLabel).join(' + ');

  String get invoiceImpactSummary {
    final source = _quantityLabel(sourcePurchaseQuantity);
    final expanded = items.map((item) {
      final quantity = sourcePurchaseQuantity * item.catalogUnitsPerPurchase;
      return '${_quantityLabel(quantity)} × ${item.product.sku}'
          '${_roleSuffix(item.role)}';
    }).join(' + ');
    return '$source ${sourcePurchaseQuantity == 1 ? 'compra' : 'compras'} → '
        '$expanded';
  }

  String get displaySummary {
    final set = canonicalSetProduct;
    if (set != null) {
      return 'Set canónico ${set.sku} · ${set.name}. '
          '$invoiceImpactSummary';
    }
    return '$perPurchaseSummary. $invoiceImpactSummary';
  }

  static String _itemLabel(SupplierResolutionProposalItem item) =>
      '${item.catalogUnitsPerPurchase} × ${item.product.sku} · '
      '${item.product.name}${_roleSuffix(item.role)}';

  static String _roleSuffix(AIProductMatchComponentRole role) => switch (role) {
        AIProductMatchComponentRole.front => ' · delantero',
        AIProductMatchComponentRole.rear => ' · trasero',
        AIProductMatchComponentRole.left => ' · izquierdo',
        AIProductMatchComponentRole.right => ' · derecho',
        AIProductMatchComponentRole.homogeneous => ' · unidades iguales',
        _ => '',
      };

  static String _quantityLabel(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}

/// Builds a proposal only from grounded catalog ids and structured package
/// evidence. Names and images may help the AI choose those ids, but never
/// author a quantity after this boundary.
class SupplierResolutionProposalBuilder {
  static const int _ratioPrecision = 1000000000000;

  static Future<SupplierResolutionProposal?> build({
    required AIProductMatchDecision decision,
    required AIProductIdentityInvestigation? investigation,
    required SupplierOptionEvidence optionEvidence,
    required double sourcePurchaseQuantity,
    required Iterable<Product> catalog,
    required ProductSetCompositionLookup lookupSetComposition,
  }) async {
    if (!sourcePurchaseQuantity.isFinite ||
        sourcePurchaseQuantity <= 0 ||
        optionEvidence.packEvidenceConflict ||
        decision.invalidProductId ||
        decision.confidence < 0.85) {
      return null;
    }
    final byId = <String, Product>{
      for (final product in catalog)
        if (product.id?.trim().isNotEmpty == true &&
            product.isActive &&
            !product.isService)
          product.id!: product,
    };

    final directItems = <SupplierResolutionProposalItem>[];
    if (decision.decision == AIProductMatchDecisionKind.composite) {
      if (decision.components.isEmpty) return null;
      for (final component in decision.components) {
        final product = byId[component.productId];
        if (product == null || product.isSet || component.quantity <= 0) {
          return null;
        }
        directItems.add(SupplierResolutionProposalItem(
          product: product,
          catalogUnitsPerPurchase: component.quantity,
          role: component.role,
        ));
      }
      if (!_packageCountAgrees(optionEvidence, investigation, directItems)) {
        return null;
      }
    } else if (decision.decision == AIProductMatchDecisionKind.same &&
        decision.productId != null &&
        optionEvidence.requiresExplicitComposition) {
      final product = byId[decision.productId!];
      if (product == null) return null;
      if (product.isSet) {
        final composition = await lookupSetComposition(product);
        if (composition == null || composition.components.isEmpty) return null;
        if (!_setCountAgrees(optionEvidence, investigation, composition)) {
          return null;
        }
        final recognized = _itemsFromSetComposition(composition, byId);
        if (recognized == null) return null;
        return SupplierResolutionProposal._(
          kind: SupplierVariantResolutionKind.single,
          items: List<SupplierResolutionProposalItem>.unmodifiable(recognized),
          edges: <SupplierVariantResolutionEdge>[
            SupplierVariantResolutionEdge(
              position: 1,
              productId: product.id!,
              catalogUnitsPerPurchase: 1,
              allocationRatio: 1,
              componentRole: 'catalog_set',
            ),
          ],
          resolutionProducts: <Product>[product],
          sourcePurchaseQuantity: sourcePurchaseQuantity,
          reason: decision.reason,
          canonicalSetProduct: product,
          canonicalSetComposition: composition,
        );
      }

      final packCount = optionEvidence.packCount;
      final packaging = investigation?.packaging;
      if (packCount == null ||
          packCount <= 1 ||
          (optionEvidence.unitClass != 'piece' &&
              optionEvidence.unitClass != 'unit') ||
          investigation?.packageKind != AIProductPackageKind.composite ||
          packaging?.count != packCount) {
        return null;
      }
      directItems.add(SupplierResolutionProposalItem(
        product: product,
        catalogUnitsPerPurchase: packCount,
        role: AIProductMatchComponentRole.homogeneous,
      ));
    } else {
      return null;
    }

    if (directItems.isEmpty) return null;

    final canonicalSet = await _findExactCanonicalSet(
      directItems: directItems,
      catalog: byId.values,
      lookupSetComposition: lookupSetComposition,
    );
    if (canonicalSet != null) {
      return SupplierResolutionProposal._(
        kind: SupplierVariantResolutionKind.single,
        items: List<SupplierResolutionProposalItem>.unmodifiable(directItems),
        edges: <SupplierVariantResolutionEdge>[
          SupplierVariantResolutionEdge(
            position: 1,
            productId: canonicalSet.$1.id!,
            catalogUnitsPerPurchase: 1,
            allocationRatio: 1,
            componentRole: 'catalog_set',
          ),
        ],
        resolutionProducts: <Product>[canonicalSet.$1],
        sourcePurchaseQuantity: sourcePurchaseQuantity,
        reason: decision.reason,
        canonicalSetProduct: canonicalSet.$1,
        canonicalSetComposition: canonicalSet.$2,
      );
    }

    final kind = directItems.length == 1
        ? SupplierVariantResolutionKind.homogeneous
        : SupplierVariantResolutionKind.composite;
    if (kind == SupplierVariantResolutionKind.homogeneous &&
        directItems.single.catalogUnitsPerPurchase <= 1) {
      return null;
    }
    final ratios = _allocationRatios(directItems);
    final edges = <SupplierVariantResolutionEdge>[
      for (var index = 0; index < directItems.length; index++)
        SupplierVariantResolutionEdge(
          position: index + 1,
          productId: directItems[index].product.id!,
          catalogUnitsPerPurchase: directItems[index].catalogUnitsPerPurchase,
          allocationRatio: ratios[index],
          componentRole: directItems[index].role.wireValue,
        ),
    ];
    if (SupplierVariantResolution.validateGraph(kind: kind, edges: edges) !=
        null) {
      return null;
    }
    return SupplierResolutionProposal._(
      kind: kind,
      items: List<SupplierResolutionProposalItem>.unmodifiable(directItems),
      edges: List<SupplierVariantResolutionEdge>.unmodifiable(edges),
      resolutionProducts: List<Product>.unmodifiable(
        directItems.map((item) => item.product),
      ),
      sourcePurchaseQuantity: sourcePurchaseQuantity,
      reason: decision.reason,
    );
  }

  static bool _packageCountAgrees(
    SupplierOptionEvidence evidence,
    AIProductIdentityInvestigation? investigation,
    List<SupplierResolutionProposalItem> items,
  ) {
    final count = evidence.packCount;
    final sourceComponentUnits = _sourceComponentUnits(investigation);
    if (items.length == 1) {
      if (items.single.role != AIProductMatchComponentRole.homogeneous) {
        return false;
      }
      if (evidence.unitClass == 'piece' || evidence.unitClass == 'unit') {
        return count != null &&
            count > 1 &&
            items.single.catalogUnitsPerPurchase == count;
      }
      return sourceComponentUnits != null &&
          sourceComponentUnits > 1 &&
          items.single.catalogUnitsPerPurchase == sourceComponentUnits;
    }
    final proposedUnits = items.fold<int>(
      0,
      (total, item) => total + item.catalogUnitsPerPurchase,
    );
    if (evidence.unitClass == 'piece' || evidence.unitClass == 'unit') {
      return count != null && proposedUnits == count;
    }
    return sourceComponentUnits != null &&
        proposedUnits == sourceComponentUnits;
  }

  static bool _setCountAgrees(
    SupplierOptionEvidence evidence,
    AIProductIdentityInvestigation? investigation,
    ProductSetCompositionSnapshot composition,
  ) {
    final count = evidence.packCount;
    final units = composition.components.fold<int>(
      0,
      (total, component) => total + component.quantityInSet,
    );
    if (evidence.unitClass == 'piece' || evidence.unitClass == 'unit') {
      return count != null && units == count;
    }
    final sourceComponentUnits = _sourceComponentUnits(investigation);
    return sourceComponentUnits != null && units == sourceComponentUnits;
  }

  static int? _sourceComponentUnits(
    AIProductIdentityInvestigation? investigation,
  ) {
    if (investigation?.packageKind != AIProductPackageKind.composite) {
      return null;
    }
    final units = investigation!.composition.components
        .where(
          (component) =>
              component.role != AIProductCompositionRole.includedAccessory,
        )
        .fold<int>(0, (total, component) => total + component.quantity);
    return units > 0 ? units : null;
  }

  static List<SupplierResolutionProposalItem>? _itemsFromSetComposition(
    ProductSetCompositionSnapshot composition,
    Map<String, Product> productsById,
  ) {
    final items = <SupplierResolutionProposalItem>[];
    for (final component in composition.components) {
      final product = productsById[component.id];
      if (product == null || product.isSet) return null;
      items.add(SupplierResolutionProposalItem(
        product: product,
        catalogUnitsPerPurchase: component.quantityInSet,
        role: _roleFromLabel(component.label),
      ));
    }
    return items;
  }

  static Future<(Product, ProductSetCompositionSnapshot)?>
      _findExactCanonicalSet({
    required List<SupplierResolutionProposalItem> directItems,
    required Iterable<Product> catalog,
    required ProductSetCompositionLookup lookupSetComposition,
  }) async {
    final expected = _componentTotals(directItems);
    final matches = <(Product, ProductSetCompositionSnapshot)>[];
    for (final setProduct in catalog.where(
      (product) => product.isSet && product.isActive && !product.isService,
    )) {
      final composition = await lookupSetComposition(setProduct);
      if (composition == null || composition.components.isEmpty) continue;
      final actual = <String, int>{};
      for (final component in composition.components) {
        actual.update(
          component.id,
          (quantity) => quantity + component.quantityInSet,
          ifAbsent: () => component.quantityInSet,
        );
      }
      if (_sameTotals(expected, actual)) {
        matches.add((setProduct, composition));
      }
    }
    return matches.length == 1 ? matches.single : null;
  }

  static Map<String, int> _componentTotals(
    Iterable<SupplierResolutionProposalItem> items,
  ) {
    final totals = <String, int>{};
    for (final item in items) {
      totals.update(
        item.product.id!,
        (quantity) => quantity + item.catalogUnitsPerPurchase,
        ifAbsent: () => item.catalogUnitsPerPurchase,
      );
    }
    return totals;
  }

  static bool _sameTotals(Map<String, int> left, Map<String, int> right) =>
      left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);

  static AIProductMatchComponentRole _roleFromLabel(String label) {
    final normalized = label.trim().toLowerCase();
    if (normalized.contains('delant') || normalized == 'front') {
      return AIProductMatchComponentRole.front;
    }
    if (normalized.contains('traser') || normalized == 'rear') {
      return AIProductMatchComponentRole.rear;
    }
    if (normalized.contains('izquier') || normalized == 'left') {
      return AIProductMatchComponentRole.left;
    }
    if (normalized.contains('derech') || normalized == 'right') {
      return AIProductMatchComponentRole.right;
    }
    return AIProductMatchComponentRole.component;
  }

  static List<double> _allocationRatios(
    List<SupplierResolutionProposalItem> items,
  ) {
    final scale = BigInt.from(_ratioPrecision);
    var weights = <BigInt>[
      for (final item in items)
        BigInt.from((item.product.cost * 1000000).round()) *
            BigInt.from(item.catalogUnitsPerPurchase),
    ];
    if (weights.every((weight) => weight <= BigInt.zero)) {
      weights = <BigInt>[
        for (final item in items) BigInt.from(item.catalogUnitsPerPurchase),
      ];
    } else {
      weights = weights
          .map((weight) => weight <= BigInt.zero ? BigInt.one : weight)
          .toList(growable: false);
    }
    final total =
        weights.fold<BigInt>(BigInt.zero, (sum, value) => sum + value);
    final shares = <BigInt>[];
    final remainders = <(int, BigInt)>[];
    var assigned = BigInt.zero;
    for (var index = 0; index < weights.length; index++) {
      final numerator = weights[index] * scale;
      final share = numerator ~/ total;
      shares.add(share);
      assigned += share;
      remainders.add((index, numerator.remainder(total)));
    }
    remainders.sort((left, right) {
      final remainderOrder = right.$2.compareTo(left.$2);
      return remainderOrder != 0 ? remainderOrder : left.$1.compareTo(right.$1);
    });
    var missing = (scale - assigned).toInt();
    for (var index = 0; index < missing; index++) {
      shares[remainders[index].$1] += BigInt.one;
    }
    return <double>[
      for (final share in shares) share.toDouble() / _ratioPrecision,
    ];
  }
}
