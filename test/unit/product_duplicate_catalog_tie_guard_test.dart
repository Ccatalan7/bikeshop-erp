import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

void main() {
  test('identical catalog rows abstain before AI and keep every choice',
      () async {
    final proxy = _CountingProxy();
    final ai = AIAssistantService(geminiProxy: proxy);
    final matcher = _matcher(ai: ai, enableAdjudication: true);

    final result = await matcher.resolveCandidates(
      probe: const ProductDuplicateProbe(
        name: 'Pastillas Shimano B01S orgánicas',
        brandName: 'Shimano',
      ),
      products: <Product>[
        _product(
          id: 'row-b',
          sku: 'AE0362',
          name: 'Pastillas Shimano B01S orgánicas',
          brand: 'Shimano',
          model: 'B01S',
          imageUrl: null,
        ),
        _product(
          id: 'row-a',
          sku: 'AE0361',
          name: 'Pastillas Shimano B01S orgánicas',
          brand: 'Shimano',
          model: 'B01S',
          imageUrl: null,
        ),
      ],
    );

    expect(result.kind, ProductDuplicateDecisionKind.abstained);
    expect(result.recommendations, isEmpty);
    expect(
      result.operatorChoices.map((candidate) => candidate.product.sku),
      <String>['AE0361', 'AE0362'],
    );
    expect(
      result.adjudicationState,
      ProductDuplicateAdjudicationState.notNeeded,
    );
    expect(result.reason, contains('duplicate-catalog-rows'));
    expect(proxy.calls, 0);
    expect(matcher.adjudicationCalls, 0);
    ai.dispose();
  });

  test('a typed specification difference follows the normal matcher path',
      () async {
    final result = await _matcher().resolveCandidates(
      probe: const ProductDuplicateProbe(name: 'Maza ZTTO 32H'),
      products: <Product>[
        _product(
          id: 'hub-36',
          sku: 'HUB-36',
          name: 'Maza ZTTO 36H',
          brand: 'ZTTO',
          imageUrl: 'https://catalog.test/kf/HHUB.jpg',
        ),
        _product(
          id: 'hub-32',
          sku: 'HUB-32',
          name: 'Maza ZTTO 32H',
          brand: 'ZTTO',
          imageUrl: 'https://catalog.test/kf/HHUB.jpg',
        ),
      ],
    );

    expect(result.kind, ProductDuplicateDecisionKind.recommendation);
    expect(result.recommendations.single.product.id, 'hub-32');
    expect(result.reason, isNot(contains('duplicate-catalog-rows')));
    expect(
      result.operatorChoices
          .singleWhere((candidate) => candidate.product.id == 'hub-36')
          .isRuledOut,
      isTrue,
    );
  });

  test('equal evidence is ordered by SKU on every retrieval permutation',
      () async {
    final products = <Product>[
      _product(
        id: 'row-c',
        sku: 'SKU-C',
        name: 'Pastillas de freno genéricas',
        imageUrl: 'https://catalog.test/c.jpg',
      ),
      _product(
        id: 'row-a',
        sku: 'SKU-A',
        name: 'Pastillas de freno genéricas',
        imageUrl: 'https://catalog.test/a.jpg',
      ),
      _product(
        id: 'row-b',
        sku: 'SKU-B',
        name: 'Pastillas de freno genéricas',
        imageUrl: 'https://catalog.test/b.jpg',
      ),
    ];
    final permutations = <List<Product>>[
      products,
      <Product>[products[1], products[2], products[0]],
      products.reversed.toList(growable: false),
    ];

    for (final input in permutations) {
      final result = await _matcher().resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas de freno genéricas',
        ),
        products: input,
      );
      expect(
        result.recommendations.map((candidate) => candidate.product.sku),
        <String>['SKU-A', 'SKU-B', 'SKU-C'],
      );
    }
  });
}

ProductDuplicateMatcherService _matcher({
  AIAssistantService? ai,
  bool enableAdjudication = false,
}) {
  return ProductDuplicateMatcherService(
    inventoryService: _FakeInventoryService(),
    aiAssistantService: ai,
    knownBrands: const <String>['Shimano', 'ZTTO'],
    enableVisualReading: false,
    enableMatchAdjudication: enableAdjudication,
    requireAIPrimaryInvestigation: false,
    persistComputedImageFingerprints: false,
  );
}

Product _product({
  required String id,
  required String sku,
  required String name,
  String? brand,
  String? model,
  String? imageUrl,
}) {
  return Product(
    id: id,
    tenantId: 'tenant-test',
    sku: sku,
    name: name,
    brand: brand,
    model: model,
    imageUrl: imageUrl,
    imageFingerprint: imageUrl == null
        ? null
        : const <String, dynamic>{
            'ah': '1234',
            'dh': '5678',
            'r': 100.0,
            'g': 101.0,
            'b': 102.0,
            'ar': 1.0,
          },
    price: 1000,
    cost: 500,
  );
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingProxy extends GeminiProxyService {
  _CountingProxy()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  int calls = 0;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Map<String, dynamic>? generationConfig,
  }) async {
    calls++;
    return const GeminiProxyGenerateResult(
      text: '{"id":null,"confidence":0}',
      functionCalls: <GeminiProxyFunctionCall>[],
    );
  }
}
