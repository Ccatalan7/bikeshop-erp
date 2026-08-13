import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/inventory/models/inventory_models.dart';
import 'package:vinabike_erp/modules/inventory/models/product_duplicate_candidate.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart'
    as inv_service;
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/canonical_product_identity_resolver.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_catalog_identity_index.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_extractor.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_identity_profile.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_visual_reading.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

void main() {
  group('canonical identity authority', () {
    test('a visual/text family conflict is an abstention, not an override', () {
      final resolver = CanonicalProductIdentityResolver();
      final identity = resolver.resolve(
        const ProductIdentityInput(name: 'Pastillas de freno'),
        reading: const ProductVisualReading(
          familyId: 'seatpost',
          terms: <String>{'tija'},
          excludedTerms: <String>{},
          confidence: 0.95,
        ),
      );

      expect(identity.familyState, CanonicalProductFamilyState.conflicting);
      expect(identity.resolvedFamilyId, isNull);
      expect(identity.profile.visualFamilyId, 'seatpost');
    });

    test('a precise spacer title accepts the broader visible assembly', () {
      final resolver = CanonicalProductIdentityResolver();
      for (final visualFamily in const <String>['headset', 'stem']) {
        final identity = resolver.resolve(
          const ProductIdentityInput(
            name: 'Espaciadores de dirección aluminio 1 1/8',
          ),
          reading: ProductVisualReading(
            familyId: visualFamily,
            terms: const <String>{},
            excludedTerms: const <String>{},
            confidence: 0.95,
          ),
        );

        expect(identity.familyState, CanonicalProductFamilyState.resolved);
        expect(identity.resolvedFamilyId, 'stem_spacer');
        expect(identity.familyHypotheses, <String>{'stem_spacer'});
      }
    });

    test('an unambiguous supplier title outranks a mistaken listing photo', () {
      final resolver = CanonicalProductIdentityResolver();
      final identity = resolver.resolve(
        const ProductIdentityInput(
          name: 'Tope de piola cambio RISK Basic 4mm',
          sourceTitle:
              'RISK-Tapas básicas para Cable de bicicleta, cubierta para Cable de freno de 4mm (100pcs 4mm Shift Cap)',
        ),
        reading: const ProductVisualReading(
          familyId: 'tire',
          terms: <String>{'neumático'},
          excludedTerms: <String>{},
          confidence: 0.95,
        ),
      );

      expect(
        identity.profile.supplierTitleFamilyIsAuthoritative,
        isTrue,
      );
      expect(identity.profile.familyEvidenceConflicts, isFalse);
      expect(identity.familyState, CanonicalProductFamilyState.resolved);
      expect(identity.resolvedFamilyId, 'cable_end_cap');
    });

    test('una categoría ancestro incluye sus descendientes por árbol', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final parent = resolver.resolveCategory(id: 'brakes');
      final child = resolver.resolveCategory(id: 'rotors');
      final elsewhere = resolver.resolveCategory(id: 'drivetrain');

      expect(parent, isNotNull);
      expect(parent!.scopes(child!), isTrue);
      expect(parent.scopes(elsewhere!), isFalse);
    });

    test('una hoja con una sola familia llena un vacío de texto', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final identity = resolver.resolve(
        const ProductIdentityInput(name: 'Producto XZ-9 negro'),
        categoryId: 'missinglink',
      );

      expect(identity.familyState, CanonicalProductFamilyState.resolved);
      expect(identity.resolvedFamilyId, 'chain_link');
      expect(identity.categoryFamilyHypotheses, <String>{'chain_link'});
    });

    test('una hoja compartida por varias familias no decide el objeto', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final identity = resolver.resolve(
        const ProductIdentityInput(name: 'Producto XZ-9 negro'),
        categoryId: 'adapters',
      );

      expect(identity.familyState, CanonicalProductFamilyState.unknown);
      expect(identity.resolvedFamilyId, isNull);
      expect(
        identity.categoryFamilyHypotheses,
        containsAll(<String>['brake_adapter', 'valve_adapter']),
      );
    });

    test('una categoría genérica no inventa la identidad de un catálogo', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final unresolved = resolver.resolve(
        const ProductIdentityInput(name: 'Producto XZ-9 negro'),
        categoryId: 'adapters',
      );

      expect(unresolved.contextualizedFor('valve_adapter'), isNull);
      expect(unresolved.contextualizedFor('brake_pad'), isNull);
    });

    test('el nombre legado bare spacer es dirección, no cassette', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final unresolved = resolver.resolve(
        const ProductIdentityInput(name: 'Espaciador Genérico 5mm Negro'),
        categoryId: 'spacers',
      );

      expect(unresolved.familyState, CanonicalProductFamilyState.resolved);
      expect(unresolved.resolvedFamilyId, 'stem_spacer');
      expect(unresolved.contextualizedFor('stem_spacer'), isNotNull);
      expect(unresolved.contextualizedFor('cassette_spacer'), isNull);
    });

    test('el espesor elegido distingue espaciadores de la misma repisa', () {
      final source = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'Espaciadores de tee aluminio',
          sourceTitle: 'Espaciadores de vástago aluminio 5MM 10MM 20MM',
          variantText: '5mm 5pcs',
        ),
      );
      final five = ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Espaciador Genérico 5mm Negro'),
      );
      final ten = ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Espaciador Genérico 10mm Negro'),
      );
      final polycarbonate = ProductIdentityExtractor.extract(
        const ProductIdentityInput(
          name: 'ESPACIADOR POLYCARBONATO 5MM TRANSP. NEGRO',
        ),
      );

      expect(source.lineSpecs[PartSpecKind.spacerThicknessMm], isNull);
      expect(source.variantSpecs[PartSpecKind.spacerThicknessMm], '5');
      expect(five.lineSpecs[PartSpecKind.spacerThicknessMm], '5');
      expect(ten.lineSpecs[PartSpecKind.spacerThicknessMm], '10');
      expect(polycarbonate.effectiveFamilyId, 'stem_spacer');
      expect(
        polycarbonate.lineSpecs[PartSpecKind.constructionMaterial],
        'plastic',
        reason: polycarbonate.identityText,
      );
    });

    test('una categoría no reemplaza ni pelea con la familia del título', () {
      final resolver = CanonicalProductIdentityResolver(
        categories: _categories,
      );
      final identity = resolver.resolve(
        const ProductIdentityInput(name: 'Pastillas de freno'),
        categoryId: 'missinglink',
      );

      expect(identity.familyState, CanonicalProductFamilyState.resolved);
      expect(identity.resolvedFamilyId, 'brake_pad');
      expect(identity.familyHypotheses, <String>{'brake_pad'});
      expect(identity.categoryFamilyHypotheses, <String>{'chain_link'});
    });
  });

  test('the index scans every active non-service row after ordering hits', () {
    final index = ProductCatalogIdentityIndex(maxShortlist: 2);
    index.sync(<Product>[
      for (var index = 0; index < 135; index++)
        _product(
          id: 'active-$index',
          sku: 'SKU-$index',
          name: 'Pastillas freno $index',
        ),
      _product(
        id: 'inactive',
        sku: 'INACTIVE',
        name: 'Pastillas freno inactivas',
        isActive: false,
      ),
      _product(
        id: 'service',
        sku: 'SERVICE',
        name: 'Servicio de frenos',
        productType: ProductType.service,
      ),
    ]);

    final retrieved = index.retrieve(
      ProductIdentityExtractor.extract(
        const ProductIdentityInput(name: 'Texto sin familia reconocible'),
      ),
    );

    expect(retrieved, hasLength(135));
    expect(retrieved.map((product) => product.id), isNot(contains('inactive')));
    expect(retrieved.map((product) => product.id), isNot(contains('service')));
  });

  group('one immutable search decision', () {
    test('supplier SKU is not exact; catalog SKU and immutable alias are',
        () async {
      final service = _matcher();
      final products = <Product>[
        _product(
          id: 'catalog-product',
          sku: 'AE-100',
          name: 'Pastillas freno orgánicas',
        ),
      ];

      final supplierOnly = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas freno orgánicas',
          sku: 'AE-100',
        ),
        products: products,
      );
      expect(
        supplierOnly.recommendations.single.matchTier,
        isNot(ProductDuplicateMatchTier.exact),
      );

      final catalogSku = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Texto ilegible',
          catalogSku: 'AE-100',
        ),
        products: products,
      );
      expect(catalogSku.kind, ProductDuplicateDecisionKind.authoritativeExact);

      final mutableAlias = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Texto ilegible',
          confirmedProductId: 'catalog-product',
        ),
        products: products,
      );
      expect(mutableAlias.kind, ProductDuplicateDecisionKind.abstained);

      final immutableAlias = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Texto ilegible',
          confirmedProductId: 'catalog-product',
          confirmedAliasIsImmutable: true,
        ),
        products: products,
      );
      expect(
        immutableAlias.kind,
        ProductDuplicateDecisionKind.authoritativeExact,
      );
    });

    test('category authority scopes recommendations and preserves unknowns',
        () async {
      final service = _matcher(categories: _categories);
      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Disco rotor freno 160mm',
          categoryId: 'brakes',
        ),
        products: <Product>[
          _product(
            id: 'descendant',
            sku: 'DISC-1',
            name: 'Disco rotor freno 160mm',
            categoryId: 'rotors',
            categoryName: 'Discos',
          ),
          _product(
            id: 'uncategorized',
            sku: 'DISC-2',
            name: 'Disco rotor freno 160mm genérico',
          ),
          _product(
            id: 'other-shelf',
            sku: 'DISC-3',
            name: 'Disco rotor freno 160mm alternativo',
            categoryId: 'drivetrain',
            categoryName: 'Transmisión',
          ),
        ],
      );

      expect(
        result.operatorChoices.map((candidate) => candidate.product.id),
        containsAll(<String>['descendant', 'uncategorized']),
      );
      final uncategorized = result.operatorChoices.singleWhere(
        (candidate) => candidate.product.id == 'uncategorized',
      );
      expect(
          uncategorized.objections.join(' '), contains('no tiene categoría'));
      expect(result.categoryConflicts.single.product.id, 'other-shelf');
      expect(
        result.categoryConflicts.single.objections.join(' '),
        contains('otra categoría'),
      );
      expect(
        () => result.operatorChoices.add(result.operatorChoices.first),
        throwsUnsupportedError,
      );
    });

    test('AI none fails closed but keeps deterministic operator choices',
        () async {
      final proxy = _ScriptedProxy(
        '{"id":null,"reason":"evidencia insuficiente","confidence":0.2}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          _product(id: 'product-a', sku: 'SKU-A', name: 'Pastillas freno A'),
          _product(id: 'product-b', sku: 'SKU-B', name: 'Pastillas freno B'),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(result.recommendations, isEmpty);
      expect(result.operatorChoices, hasLength(2));
      expect(
        result.adjudicationState,
        ProductDuplicateAdjudicationState.abstained,
      );
      expect(proxy.calls, 1);
      ai.dispose();
    });

    test('variant ULP does not change the AI tie admission boundary', () async {
      final proxy = _ScriptedProxy(
        '{"id":"product-b","reason":"variante","confidence":0.9}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Puños ODI-1 135mm',
          selectedVariant: 'Black',
        ),
        products: <Product>[
          _product(
            id: 'product-a',
            sku: 'SKU-A',
            name: 'Puños ODI-1 Negros 135mm',
          ),
          _product(
            id: 'product-b',
            sku: 'SKU-B',
            name: 'Puños ODI-1 135mm',
          ),
        ],
      );

      expect(proxy.calls, 1);
      expect(
          result.adjudicationState, ProductDuplicateAdjudicationState.accepted);
      expect(result.recommendations, hasLength(1));
      expect(result.recommendations.single.product.id, 'product-b');
      expect(
        result.deterministicTopCandidate?.product.id,
        'product-a',
        reason: 'el líder pre-IA debe conservarse como procedencia separada',
      );
      expect(
        result.operatorChoices.map((candidate) => candidate.product.id),
        containsAll(<String>['product-a', 'product-b']),
        reason: 'la IA elige uno; el picker conserva todo el recall',
      );
      ai.dispose();
    });

    test('matcher detects a 13-way AI tie before the six-row UI limit',
        () async {
      final proxy = _ScriptedProxy(
        '{"id":"product-0","reason":"primero","confidence":0.99}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          for (var index = 0; index < 13; index++)
            _product(
              id: 'product-$index',
              sku: 'SKU-$index',
              name: 'Pastillas freno alternativa $index',
            ),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(
        result.adjudicationState,
        ProductDuplicateAdjudicationState.tieOverflow,
      );
      expect(result.recommendations, isEmpty);
      expect(result.operatorChoices, hasLength(13));
      expect(proxy.calls, 0, reason: 'un empate incompleto no se adjudica');
      ai.dispose();
    });

    test('AI failure also fails closed but keeps deterministic choices',
        () async {
      final proxy = _ScriptedProxy('respuesta ilegible');
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          _product(id: 'product-a', sku: 'SKU-A', name: 'Pastillas freno A'),
          _product(id: 'product-b', sku: 'SKU-B', name: 'Pastillas freno B'),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(result.recommendations, isEmpty);
      expect(result.operatorChoices, hasLength(2));
      expect(
        result.adjudicationState,
        ProductDuplicateAdjudicationState.failed,
      );
      expect(proxy.calls, 1);
      ai.dispose();
    });

    test('AI options use opaque refs and map the selection back to product ids',
        () async {
      final proxy = _ScriptedProxy(
        '{"id":"product-b","reason":"mejor descriptor","confidence":0.9}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          _product(id: 'product-a', sku: 'SKU-A', name: 'Pastillas freno A'),
          _product(id: 'product-b', sku: 'SKU-B', name: 'Pastillas freno B'),
        ],
      );

      expect(result.recommendations.first.product.id, 'product-b');
      expect(proxy.lastPrompt, contains('"id":"C002"'));
      expect(proxy.lastPrompt, isNot(contains('product-a')));
      expect(proxy.lastPrompt, isNot(contains('product-b')));
      expect(proxy.lastPrompt, contains('SKU-B'),
          reason: 'el SKU queda como evidencia descriptiva, no autoridad');
      expect(proxy.calls, 1);
      ai.dispose();
    });

    test('AI low confidence abstains and preserves operator choices', () async {
      final proxy = _ScriptedProxy(
        '{"id":"product-b","reason":"podría ser","confidence":0.4}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          _product(id: 'product-a', sku: 'SKU-A', name: 'Pastillas freno A'),
          _product(id: 'product-b', sku: 'SKU-B', name: 'Pastillas freno B'),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(result.recommendations, isEmpty);
      expect(result.operatorChoices, hasLength(2));
      expect(
        result.adjudicationState,
        ProductDuplicateAdjudicationState.lowConfidence,
      );
      expect(proxy.calls, 1);
      ai.dispose();
    });

    test('a strong deterministic tie still receives labeled candidate images',
        () async {
      final proxy = _ScriptedProxy(
        '{"id":"product-b","reason":"el compuesto coincide",'
        '"confidence":0.91}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final loadedUrls = <String>[];
      final service = _matcher(
        ai: ai,
        enableAdjudication: true,
        imageLoader: (url) async {
          loadedUrls.add(url);
          return Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
        },
      );

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(
          name: 'Pastillas de freno Shimano B01S',
        ),
        products: <Product>[
          _product(
            id: 'product-a',
            sku: 'SKU-A',
            name: 'Pastillas de freno Shimano B01S orgánicas',
            model: 'B01S',
            imageUrl: 'https://catalog.test/a.jpg',
          ),
          _product(
            id: 'product-b',
            sku: 'SKU-B',
            name: 'Pastillas de freno Shimano B01S resina',
            model: 'B01S',
            imageUrl: 'https://catalog.test/b.jpg',
          ),
        ],
      );

      expect(
          result.adjudicationState, ProductDuplicateAdjudicationState.accepted);
      expect(result.recommendations.first.product.id, 'product-b');
      expect(
          loadedUrls,
          containsAll(<String>[
            'https://catalog.test/a.jpg',
            'https://catalog.test/b.jpg',
          ]));
      expect(
          proxy.imageLabels,
          contains(
            'IMAGEN COMPARTIDA POR LOS CANDIDATOS ids=C001,C002:',
          ));
      expect(proxy.inlineDataParts, 1,
          reason: 'bytes idénticos se envían una vez con ambas referencias');
      expect(proxy.calls, 1);
      ai.dispose();
    });

    test('an invented AI id fails closed instead of becoming none', () async {
      final proxy = _ScriptedProxy(
        '{"id":"not-offered","reason":"inventado","confidence":0.99}',
      );
      final ai = AIAssistantService(geminiProxy: proxy);
      final service = _matcher(ai: ai, enableAdjudication: true);

      final result = await service.resolveCandidates(
        probe: const ProductDuplicateProbe(name: 'Pastillas freno'),
        products: <Product>[
          _product(id: 'product-a', sku: 'SKU-A', name: 'Pastillas freno A'),
          _product(id: 'product-b', sku: 'SKU-B', name: 'Pastillas freno B'),
        ],
      );

      expect(result.kind, ProductDuplicateDecisionKind.abstained);
      expect(
          result.adjudicationState, ProductDuplicateAdjudicationState.failed);
      expect(result.reason, contains('no estaba entre los candidatos'));
      expect(result.operatorChoices, hasLength(2));
      ai.dispose();
    });
  });
}

final _categories = <Category>[
  Category(
    id: 'components',
    tenantId: 'tenant-test',
    name: 'Componentes',
    fullPath: 'Componentes',
  ),
  Category(
    id: 'brakes',
    tenantId: 'tenant-test',
    name: 'Frenos',
    fullPath: 'Componentes / Frenos',
    parentId: 'components',
    level: 1,
  ),
  Category(
    id: 'rotors',
    tenantId: 'tenant-test',
    name: 'Discos',
    fullPath: 'Componentes / Frenos / Discos',
    parentId: 'brakes',
    level: 2,
  ),
  Category(
    id: 'drivetrain',
    tenantId: 'tenant-test',
    name: 'Transmisión',
    fullPath: 'Componentes / Transmisión',
    parentId: 'components',
    level: 1,
  ),
  Category(
    id: 'missinglink',
    tenantId: 'tenant-test',
    name: 'Missinglink',
    fullPath: 'Componentes / Transmisión / Missinglink',
    parentId: 'drivetrain',
    level: 2,
  ),
  Category(
    id: 'adapters',
    tenantId: 'tenant-test',
    name: 'Adaptadores',
    fullPath: 'Componentes / Adaptadores',
    parentId: 'components',
    level: 1,
  ),
  Category(
    id: 'spacers',
    tenantId: 'tenant-test',
    name: 'Espaciadores',
    fullPath: 'Componentes / Espaciadores',
    parentId: 'components',
    level: 1,
  ),
];

ProductDuplicateMatcherService _matcher({
  Iterable<Category> categories = const <Category>[],
  AIAssistantService? ai,
  bool enableAdjudication = false,
  ProductDuplicateImageLoader? imageLoader,
}) {
  return ProductDuplicateMatcherService(
    inventoryService: _FakeInventoryService(),
    aiAssistantService: ai,
    categories: categories,
    knownBrands: const <String>['Shimano', 'ZTTO'],
    enableVisualReading: false,
    enableMatchAdjudication: enableAdjudication,
    requireAIPrimaryInvestigation: false,
    persistComputedImageFingerprints: false,
    imageLoader: imageLoader,
  );
}

Product _product({
  required String id,
  required String sku,
  required String name,
  String? categoryId,
  String? categoryName,
  String? model,
  String? imageUrl,
  bool isActive = true,
  ProductType productType = ProductType.product,
}) {
  return Product(
    id: id,
    tenantId: 'tenant-test',
    sku: sku,
    name: name,
    categoryId: categoryId,
    categoryName: categoryName,
    model: model,
    imageUrl: imageUrl,
    price: 1000,
    cost: 500,
    isActive: isActive,
    productType: productType,
  );
}

class _FakeInventoryService implements inv_service.InventoryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScriptedProxy extends GeminiProxyService {
  _ScriptedProxy(this.reply)
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  final String reply;
  int calls = 0;
  String lastPrompt = '';
  final List<String> imageLabels = <String>[];
  int inlineDataParts = 0;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
    Map<String, dynamic>? generationConfig,
  }) async {
    calls++;
    for (final content in contents) {
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is Map && part['text'] is String) {
          final text = part['text'] as String;
          lastPrompt = lastPrompt.isEmpty ? text : '$lastPrompt\n$text';
          if (text.startsWith('IMAGEN DEL CANDIDATO id=') ||
              text.startsWith('IMAGEN COMPARTIDA POR LOS CANDIDATOS ids=')) {
            imageLabels.add(text);
          }
        }
        if (part is Map && part['inlineData'] is Map) {
          inlineDataParts++;
        }
      }
    }
    return GeminiProxyGenerateResult(text: reply, functionCalls: const []);
  }
}
