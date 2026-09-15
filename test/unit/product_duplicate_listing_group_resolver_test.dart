import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_listing_group_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/canonical_product_identity_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_matcher.dart';

void main() {
  const resolver = ProductDuplicateListingGroupResolver();

  test('deterministic majority degrades an AI-accepted dissent', () {
    final ae0275 = _candidate(
      'AE0275',
      'Porta Caramagiola ZTTO w216 Aluminio Colores',
    );
    final ae0123 = _candidate(
      'AE0123',
      'Porta Caramagiola ZTTO Aluminio Negro',
    );
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'blue',
        variantKey: 'sku:blue',
        title: 'Portabotellas ZTTO aluminio azul',
        choices: <ProductDuplicateCandidate>[ae0275],
        recommendation: ae0275,
        deterministicTopCandidate: ae0275,
      ),
      _row(
        id: 'red',
        variantKey: 'sku:red',
        title: 'Portabotellas ZTTO aluminio rojo',
        choices: <ProductDuplicateCandidate>[ae0275],
        recommendation: ae0275,
        deterministicTopCandidate: ae0275,
      ),
      _row(
        id: 'black',
        variantKey: 'sku:black',
        title: 'Portabotellas ZTTO aluminio negro',
        choices: <ProductDuplicateCandidate>[ae0123, ae0275],
        recommendation: ae0123,
        deterministicTopCandidate: ae0123,
        adjudicationState: ProductDuplicateAdjudicationState.accepted,
        reason: 'La IA prefirió AE0123 por el color negro.',
      ),
    ];

    final resolved = resolver.resolve(rows);

    expect(resolved.keys, <String>['black']);
    expect(resolved['black']!.kind, ProductDuplicateDecisionKind.abstained);
    expect(resolved['black']!.recommendations, isEmpty);
    expect(resolved['black']!.operatorChoices.first.product.sku, 'AE0275');
    expect(resolved['black']!.operatorChoices[1].product.sku, 'AE0123');
    expect(
      resolved['black']!.adjudicationState,
      ProductDuplicateAdjudicationState.accepted,
    );
    expect(resolved['black']!.reason, startsWith('La IA prefirió AE0123'));
    expect(resolved['black']!.reason, contains('revisa ambas opciones'));
  });

  test(
      'deterministic listing majority cannot undo an AI choice that rejected its row leader',
      () {
    final repeatedLeader = _candidate(
      'AE3000',
      'Maza trasera genérica que lidera por texto',
    );
    final groundedVariant = _candidate(
      'AE3001',
      'Maza trasera exacta para la variante comprada',
    );
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'variant-a',
        variantKey: 'sku:variant-a',
        title: 'Maza trasera variante A',
        choices: <ProductDuplicateCandidate>[repeatedLeader],
        recommendation: repeatedLeader,
        deterministicTopCandidate: repeatedLeader,
      ),
      _row(
        id: 'variant-b',
        variantKey: 'sku:variant-b',
        title: 'Maza trasera variante B',
        choices: <ProductDuplicateCandidate>[repeatedLeader],
        recommendation: repeatedLeader,
        deterministicTopCandidate: repeatedLeader,
      ),
      _row(
        id: 'variant-c',
        variantKey: 'sku:variant-c',
        title: 'Maza trasera variante C',
        choices: <ProductDuplicateCandidate>[
          groundedVariant,
          repeatedLeader,
        ],
        recommendation: groundedVariant,
        deterministicTopCandidate: repeatedLeader,
        adjudicationState: ProductDuplicateAdjudicationState.accepted,
        reason: 'La IA eligió la variante exacta por imagen y medidas.',
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('WAKE listing keeps distinct colour SKUs without a majority', () {
    final red = _candidate('AE0137', 'Tee WAKE 31.8 Roja');
    final purple = _candidate('AE0138', 'Tee WAKE 31.8 Morada');
    final black = _candidate('AE0136', 'Tee WAKE 31.8 Negra');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'wake-red',
        listingId: '1005007336672891',
        variantKey: 'sku:wake-red',
        title: 'Tee WAKE 31.8 roja',
        choices: <ProductDuplicateCandidate>[red, purple, black],
        recommendation: red,
        deterministicTopCandidate: red,
      ),
      _row(
        id: 'wake-purple',
        listingId: '1005007336672891',
        variantKey: 'sku:wake-purple',
        title: 'Tee WAKE 31.8 morada',
        choices: <ProductDuplicateCandidate>[purple, red, black],
        recommendation: purple,
        deterministicTopCandidate: purple,
      ),
      _row(
        id: 'wake-black',
        listingId: '1005007336672891',
        variantKey: 'sku:wake-black',
        title: 'Tee WAKE 31.8 negra',
        choices: <ProductDuplicateCandidate>[black, red, purple],
        recommendation: black,
        deterministicTopCandidate: black,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('front and rear specs prevent listing-level reconciliation', () {
    final rear = _candidate('AE0010', 'Freno hidráulico MT200 trasero');
    final front = _candidate('AE0009', 'Freno hidráulico MT200 delantero');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'rear-a',
        listingId: 'mt200',
        variantKey: 'sku:rear-a',
        title: 'Freno hidráulico MT200 trasero',
        choices: <ProductDuplicateCandidate>[rear, front],
        recommendation: rear,
        deterministicTopCandidate: rear,
      ),
      _row(
        id: 'rear-b',
        listingId: 'mt200',
        variantKey: 'sku:rear-b',
        title: 'Freno hidráulico MT200 trasero',
        choices: <ProductDuplicateCandidate>[rear, front],
        recommendation: rear,
        deterministicTopCandidate: rear,
      ),
      _row(
        id: 'front',
        listingId: 'mt200',
        variantKey: 'sku:front',
        title: 'Freno hidráulico MT200 delantero',
        choices: <ProductDuplicateCandidate>[front, rear],
        recommendation: front,
        deterministicTopCandidate: front,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('shift and brake cable terminals are not a safe variant group', () {
    final shift = _candidate('AE0360', 'Capuchón piola cambio 4mm');
    final brake = _candidate('AE0363', 'Terminal de piola freno 5mm');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'shift-a',
        listingId: 'cable-caps',
        variantKey: 'sku:shift-a',
        title: 'Capuchón piola cambio 4mm',
        choices: <ProductDuplicateCandidate>[shift, brake],
        recommendation: shift,
        deterministicTopCandidate: shift,
      ),
      _row(
        id: 'shift-b',
        listingId: 'cable-caps',
        variantKey: 'sku:shift-b',
        title: 'Capuchón piola cambio 4mm',
        choices: <ProductDuplicateCandidate>[shift, brake],
        recommendation: shift,
        deterministicTopCandidate: shift,
      ),
      _row(
        id: 'brake',
        listingId: 'cable-caps',
        variantKey: 'sku:brake',
        title: 'Terminal de piola freno 5mm',
        choices: <ProductDuplicateCandidate>[brake, shift],
        recommendation: brake,
        deterministicTopCandidate: brake,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('unanimous AI choice cannot manufacture deterministic consensus', () {
    final aiWinner = _candidate('AE1000', 'Puños elegidos por IA');
    final x = _candidate('AE1001', 'Puños deterministas X');
    final y = _candidate('AE1002', 'Puños deterministas Y');
    final z = _candidate('AE1003', 'Puños deterministas Z');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'a',
        variantKey: 'sku:a',
        title: 'Puños negros',
        choices: <ProductDuplicateCandidate>[aiWinner, x, y, z],
        recommendation: aiWinner,
        deterministicTopCandidate: x,
        adjudicationState: ProductDuplicateAdjudicationState.accepted,
      ),
      _row(
        id: 'b',
        variantKey: 'sku:b',
        title: 'Puños morados',
        choices: <ProductDuplicateCandidate>[aiWinner, y, x, z],
        recommendation: aiWinner,
        deterministicTopCandidate: y,
        adjudicationState: ProductDuplicateAdjudicationState.accepted,
      ),
      _row(
        id: 'c',
        variantKey: 'sku:c',
        title: 'Puños rojos',
        choices: <ProductDuplicateCandidate>[aiWinner, z, x, y],
        recommendation: aiWinner,
        deterministicTopCandidate: z,
        adjudicationState: ProductDuplicateAdjudicationState.accepted,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('repeated immutable key cannot manufacture a majority', () {
    final x = _candidate('AE1100', 'Puños deterministas X');
    final y = _candidate('AE1101', 'Puños deterministas Y');
    final z = _candidate('AE1102', 'Puños deterministas Z');
    final rows = <ProductDuplicateListingGroupRow>[
      for (var index = 0; index < 3; index++)
        _row(
          id: 'repeat-$index',
          variantKey: 'sku:repeated-x',
          title: 'Puños negros',
          choices: <ProductDuplicateCandidate>[x, y, z],
          recommendation: x,
          deterministicTopCandidate: x,
        ),
      _row(
        id: 'unique-y',
        variantKey: 'sku:unique-y',
        title: 'Puños morados',
        choices: <ProductDuplicateCandidate>[y, x, z],
        recommendation: y,
        deterministicTopCandidate: y,
      ),
      _row(
        id: 'unique-z',
        variantKey: 'sku:unique-z',
        title: 'Puños rojos',
        choices: <ProductDuplicateCandidate>[z, x, y],
        recommendation: z,
        deterministicTopCandidate: z,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('conflicting votes for one immutable key reject the group', () {
    final x = _candidate('AE1200', 'Puños deterministas X');
    final y = _candidate('AE1201', 'Puños deterministas Y');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'x-first',
        variantKey: 'sku:conflicted',
        title: 'Puños negros',
        choices: <ProductDuplicateCandidate>[x, y],
        recommendation: x,
        deterministicTopCandidate: x,
      ),
      _row(
        id: 'y-same-key',
        variantKey: 'sku:conflicted',
        title: 'Puños negros',
        choices: <ProductDuplicateCandidate>[y, x],
        recommendation: y,
        deterministicTopCandidate: y,
      ),
      _row(
        id: 'x-second-variant',
        variantKey: 'sku:second',
        title: 'Puños rojos',
        choices: <ProductDuplicateCandidate>[x, y],
        recommendation: x,
        deterministicTopCandidate: x,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });

  test('review-only category recall cannot become the shared option', () {
    final common = _candidate(
      'AE2000',
      'Ficha genérica sin familia',
      isReviewOnlyFamilyScope: true,
    );
    final explicit = _candidate('AE2001', 'Portabotellas explícito');
    final rows = <ProductDuplicateListingGroupRow>[
      _row(
        id: 'one',
        variantKey: 'sku:one',
        title: 'Portabotellas azul',
        choices: <ProductDuplicateCandidate>[explicit],
        recommendation: explicit,
        deterministicTopCandidate: explicit,
      ),
      _row(
        id: 'two',
        variantKey: 'sku:two',
        title: 'Portabotellas rojo',
        choices: <ProductDuplicateCandidate>[explicit],
        recommendation: explicit,
        deterministicTopCandidate: explicit,
      ),
      _row(
        id: 'three',
        variantKey: 'sku:three',
        title: 'Portabotellas negro',
        choices: <ProductDuplicateCandidate>[common, explicit],
        recommendation: common,
        deterministicTopCandidate: common,
      ),
    ];

    expect(resolver.resolve(rows), isEmpty);
  });
}

ProductDuplicateListingGroupRow _row({
  required String id,
  String supplierId = 'supplier-aliexpress',
  String listingId = 'ztto-listing',
  required String variantKey,
  required String title,
  required List<ProductDuplicateCandidate> choices,
  ProductDuplicateCandidate? recommendation,
  ProductDuplicateCandidate? deterministicTopCandidate,
  ProductDuplicateAdjudicationState adjudicationState =
      ProductDuplicateAdjudicationState.notNeeded,
  String? reason,
}) {
  final identity = CanonicalProductIdentityResolver().resolve(
    ProductIdentityInput(name: title),
  );
  return ProductDuplicateListingGroupRow(
    rowId: id,
    supplierId: supplierId,
    supplierListingId: listingId,
    immutableVariantKey: variantKey,
    deterministicTopCandidate: deterministicTopCandidate,
    result: ProductDuplicateSearchResult(
      probeIdentity: identity,
      kind: recommendation == null
          ? ProductDuplicateDecisionKind.abstained
          : ProductDuplicateDecisionKind.recommendation,
      recommendations: recommendation == null
          ? const <ProductDuplicateCandidate>[]
          : <ProductDuplicateCandidate>[recommendation],
      operatorChoices: choices,
      categoryConflicts: const <ProductDuplicateCandidate>[],
      adjudicationState: adjudicationState,
      reason: reason,
    ),
  );
}

ProductDuplicateCandidate _candidate(
  String sku,
  String name, {
  bool isReviewOnlyFamilyScope = false,
}) {
  return ProductDuplicateCandidate(
    product: Product(
      id: 'id-$sku',
      tenantId: 'tenant-test',
      sku: sku,
      name: name,
      price: 1000,
      cost: 500,
    ),
    matchTier: ProductDuplicateMatchTier.possible,
    confidence: 0.6,
    reasons: const <String>[],
    objections: const <String>[],
    gates: const <IdentityGate>[],
    variantMismatch: false,
    hasProductImage: true,
    isReviewOnlyFamilyScope: isReviewOnlyFamilyScope,
  );
}
