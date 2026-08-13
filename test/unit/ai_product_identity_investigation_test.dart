import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

const _identityLeaves = <AIProductCategoryLeaf>[
  AIProductCategoryLeaf(
    id: 'leaf-hubs',
    path: 'Componentes / Mazas',
  ),
];

final Uint8List _identityImage =
    Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF, 0xD9]);

void main() {
  test('una llamada devuelve nombre, visión e identidad estructurada',
      () async {
    final proxy = _IdentityProxy(_validIdentityReply());
    final service = AIAssistantService(geminiProxy: proxy);
    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'NOVATEC D042SB rear hub 32H options 28/32/36H',
      imageBytes: _identityImage,
      supplierName: 'AliExpress',
      supplierCode: '1005007001',
      selectedVariant: 'QR 10x135, MicroSpline, 32H',
      quantity: 2,
      lineContext: 'línea 4 de la orden; variante comprada separada del título',
      cacheContext: 'invoice-2024-12-03-row-4',
      cacheRevision: '3',
      rowRevision: '3',
      categoryTreeKey: 'tenant-tree-sha256',
      catalogKey: 'catalog-revision-81',
      activeLeafCategories: _identityLeaves,
      requireLeafAuthority: true,
    );

    expect(proxy.calls, 1);
    expect(result, isNotNull);
    final identity = result!.identityInvestigation!;
    expect(identity.objectLabel, 'maza trasera');
    expect(identity.categoryLeafIntent, 'leaf-hubs');
    expect(identity.maker, 'Novatec');
    expect(identity.modelCodes, <String>{'D042SB'});
    expect(identity.specifications['eje'], 'QR 10x135');
    expect(identity.packageKind, AIProductPackageKind.single);
    expect(
      identical(identity, result.visualAnalysis!.identityInvestigation),
      isTrue,
      reason: 'la lectura pagada una vez se transporta, no se reconstruye',
    );
    expect(proxy.lastPrompt,
        contains('"selected_variant":"QR 10x135, MicroSpline, 32H"'));
    expect(proxy.lastPrompt, contains('"supplier_code":"1005007001"'));
    expect(proxy.lastPrompt, contains('"quantity":2'));
    expect(proxy.lastPrompt, contains('BEGIN_UNTRUSTED_SOURCE_DATA_JSON'));
    expect(
      proxy.lastPrompt,
      contains(AIAssistantService.productIdentityPromptKey),
    );
    service.dispose();
  });

  test('sin foto la investigación primaria falla antes de gastar IA', () async {
    final proxy = _IdentityProxy(_validIdentityReply());
    final service = AIAssistantService(geminiProxy: proxy);

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'NOVATEC D042SB rear hub',
      selectedVariant: 'QR 10x135',
      rowRevision: '1',
      categoryTreeKey: 'tree',
      catalogKey: 'catalog',
      activeLeafCategories: _identityLeaves,
      requireLeafAuthority: true,
    );

    expect(result, isNull);
    expect(proxy.calls, 0);
    service.dispose();
  });

  test('la caché incluye cada contexto que puede cambiar la identidad',
      () async {
    final proxy = _IdentityProxy(_validIdentityReply(includeVision: false));
    final service = AIAssistantService(geminiProxy: proxy);

    Future<void> load({
      String selectedVariant = 'QR 10x135',
      String supplierCode = 'LISTING-A',
      num quantity = 1,
      String lineContext = 'row 1',
      String cacheContext = 'invoice A',
      String cacheRevision = '1',
      String categoryTreeKey = 'tree A',
      String catalogKey = 'catalog A',
      String supplierName = 'AliExpress',
      String visionModel = 'gemini-2.5-flash',
    }) async {
      await service.cleanProductTitleFromImage(
        rawTitle: 'NOVATEC D042SB rear hub',
        imageBytes: _identityImage,
        supplierName: supplierName,
        selectedVariant: selectedVariant,
        supplierCode: supplierCode,
        quantity: quantity,
        lineContext: lineContext,
        cacheContext: cacheContext,
        cacheRevision: cacheRevision,
        rowRevision: cacheRevision,
        categoryTreeKey: categoryTreeKey,
        catalogKey: catalogKey,
        activeLeafCategories: _identityLeaves,
        requireLeafAuthority: true,
        visionModel: visionModel,
      );
    }

    await load();
    await load();
    expect(proxy.calls, 1, reason: 'un contexto idéntico reusa la lectura');

    await load(selectedVariant: 'Boost 12x148');
    await load(supplierCode: 'LISTING-B');
    await load(quantity: 2);
    await load(lineContext: 'row 2');
    await load(cacheContext: 'invoice B');
    await load(cacheRevision: '2');
    await load(categoryTreeKey: 'tree B');
    await load(catalogKey: 'catalog B');
    await load(supplierName: 'Proveedor B');
    await load(visionModel: 'gemini-2.5-pro');

    expect(proxy.calls, 11);
    expect(
        proxy.models,
        containsAll(<String>[
          'gemini-2.5-flash',
          'gemini-2.5-pro',
        ]));
    service.dispose();
  });

  test('un bloque de identidad ausente o malformado falla cerrado', () async {
    final malformedReplies = <String>[
      jsonEncode(<String, Object?>{
        'cleaned_name': 'Maza Novatec',
        'component_type': 'maza',
        'confidence': 0.9,
      }),
      _validIdentityReply(packageKind: 'guess'),
      _validIdentityReply(specifications: <String, Object?>{'eje': 135}),
      _validIdentityReply(identityConfidence: 92),
    ];

    for (final reply in malformedReplies) {
      final proxy = _IdentityProxy(reply);
      final service = AIAssistantService(geminiProxy: proxy);
      final result = await service.cleanProductTitleFromImage(
        rawTitle: 'Maza Novatec',
        imageBytes: _identityImage,
        rowRevision: '1',
        categoryTreeKey: 'tree',
        catalogKey: 'catalog',
        activeLeafCategories: _identityLeaves,
        requireLeafAuthority: true,
      );
      expect(result, isNull, reason: reply);
      service.dispose();
    }
  });

  test('una cantidad fuente inválida no gasta una llamada', () async {
    final proxy = _IdentityProxy(_validIdentityReply());
    final service = AIAssistantService(geminiProxy: proxy);

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'Maza Novatec',
      imageBytes: _identityImage,
      quantity: 0,
      rowRevision: '1',
      categoryTreeKey: 'tree',
      catalogKey: 'catalog',
      activeLeafCategories: _identityLeaves,
      requireLeafAuthority: true,
    );

    expect(result, isNull);
    expect(proxy.calls, 0);
    service.dispose();
  });
}

String _validIdentityReply({
  bool includeVision = true,
  String packageKind = 'single',
  Map<String, Object?> specifications = const <String, Object?>{
    'eje': 'QR 10x135',
    'agujeros': '32H',
  },
  num identityConfidence = 0.96,
}) {
  return jsonEncode(<String, Object?>{
    'schema_version': AIAssistantService.productIdentitySchemaVersion,
    'prompt_version': AIAssistantService.productIdentityPromptKey,
    'model_id': 'gemini-2.5-flash',
    'cleaned_name': 'Maza trasera Novatec D042SB 32H',
    'identity': <String, Object?>{
      'object': <String, Object?>{
        'label': 'maza trasera',
        'confidence': identityConfidence,
      },
      'manufacturer': <String, Object?>{
        'value': 'Novatec',
        'asserted': true,
        'evidence': 'identity',
      },
      'models': <Map<String, Object?>>[
        <String, Object?>{'code': 'D042SB', 'role': 'identity'},
      ],
      'specs': <Map<String, Object?>>[
        for (final entry in specifications.entries)
          <String, Object?>{
            'key': entry.key,
            'value': entry.value,
            'unit': null,
            'source': 'option',
            'exclusive': false,
          },
      ],
      'fitment': <String>[],
      'composition': <String, Object?>{
        'kind': packageKind,
        'components': <Map<String, Object?>>[
          <String, Object?>{
            'label': 'maza trasera',
            'role': 'primary',
            'qty': 1,
          },
        ],
      },
      'packaging': <String, Object?>{
        'count': 1,
        'unit_token': 'pieza',
        'source': 'name',
      },
      'leaf_proposals': <Map<String, Object?>>[
        <String, Object?>{
          'category_id': 'L001',
          'confidence': 0.96,
          'basis': <String>['object', 'name'],
        },
      ],
      'evidence_used': <String>[
        'photo',
        'original_supplier_title',
        'selected_variant',
      ],
      'abstain_reason': null,
      'reason': 'La forma, D042SB y QR 10x135 identifican una maza trasera.',
    },
    'vision': <String, Object?>{
      'primary_type': includeVision ? 'maza trasera' : '',
      'catalog_terms': includeVision
          ? <String>['maza trasera', 'cuerpo de cassette']
          : <String>[],
      'excluded_terms':
          includeVision ? <String>['llanta', 'cassette'] : <String>[],
      'confidence': includeVision ? 0.91 : 0,
      'visual_summary':
          includeVision ? 'Maza con cuerpo de cassette y eje QR' : null,
    },
  });
}

class _IdentityProxy extends GeminiProxyService {
  _IdentityProxy(this.reply)
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  final String reply;
  int calls = 0;
  String lastPrompt = '';
  final List<String> models = <String>[];

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
    Map<String, dynamic>? generationConfig,
  }) async {
    calls++;
    models.add(model);
    for (final content in contents) {
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is Map && part['text'] is String) {
          final text = part['text'] as String;
          lastPrompt = lastPrompt.isEmpty ? text : '$lastPrompt\n$text';
        }
      }
    }
    var responseText = reply;
    try {
      final decoded = jsonDecode(reply);
      if (decoded is Map<String, dynamic> && decoded.containsKey('model_id')) {
        decoded['model_id'] = model;
        responseText = jsonEncode(decoded);
      }
    } on FormatException {
      // Malformed response fixtures must stay malformed.
    }
    return GeminiProxyGenerateResult(
      text: responseText,
      functionCalls: const [],
    );
  }
}
