import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_duplicate_matcher_service.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

/// The model is allowed to choose, never to invent.
///
/// Letting it decide is what closes the gap a dictionary can never close — no
/// list of head nouns will ever contain every word a supplier writes. But the
/// decision has to be grounded in rows that really exist, bounded in cost, and
/// refusable. These tests pin exactly that boundary.
void main() {
  const options = <AIProductMatchOption>[
    AIProductMatchOption(
      id: 'AE0145',
      name: 'Caliper Freno Delantero Mecánico Bucklos AE',
      brand: 'Bucklos',
      category: 'Calipers',
    ),
    AIProductMatchOption(
      id: 'NNV128',
      name: 'Pinzas Industriales Precisión',
      brand: 'Aliexpress',
      category: 'Herramientas',
    ),
  ];

  test('elige uno de los candidatos y dice por qué', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"same","product_id":"AE0145","components":[],'
      '"reason":"es el caliper delantero Bucklos, misma marca y mismo lado",'
      '"confidence":0.9}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'BUCKLOS-pinza de freno de disco de bicicleta, 160mm',
      options: options,
    );

    expect(decision!.productId, 'AE0145');
    expect(decision.decision, AIProductMatchDecisionKind.same);
    expect(decision.reason, contains('caliper'));
    expect(proxy.calls, 1);
    service.dispose();
  });

  test('un id que nadie ofreció no es una elección: se descarta', () async {
    // A model that answers with a SKU nobody handed it has written a product,
    // not chosen one. Repairing that guess is how an invented code reaches the
    // catalog.
    final proxy = _ScriptedProxy(
      '{"decision":"same","product_id":"AE9999","components":[],'
      '"reason":"inventado","confidence":0.99}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'BUCKLOS-pinza de freno de disco',
      options: options,
    );

    expect(decision!.hasChoice, isFalse);
    expect(decision.invalidProductId, isTrue);
    service.dispose();
  });

  test('«ninguno» es una respuesta válida, no un fallo', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"different","product_id":null,"components":[],'
      '"reason":"ninguno es la misma pieza","confidence":0.2}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Producto que no existe en el catálogo',
      options: options,
    );

    expect(decision, isNotNull);
    expect(decision!.hasChoice, isFalse);
    expect(decision.decision, AIProductMatchDecisionKind.different);
    expect(decision.invalidProductId, isFalse);
    expect(decision.reason, isNotNull);
    service.dispose();
  });

  test('sin candidatos no se gasta una llamada', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"insufficient","product_id":null,"components":[],'
      '"reason":"sin evidencia","confidence":0}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Cualquier cosa',
      options: const <AIProductMatchOption>[],
    );

    expect(decision, isNull);
    expect(proxy.calls, 0, reason: 'no hay nada que elegir');
    service.dispose();
  });

  test('un empate que supera el límite se rechaza sin truncarlo', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"insufficient","product_id":null,"components":[],'
      '"reason":"sin evidencia","confidence":0}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    await service.adjudicateProductMatch(
      invoiceTitle: 'Rotor',
      options: <AIProductMatchOption>[
        for (var index = 0;
            index <= AIAssistantService.maxAdjudicationCandidates;
            index++)
          AIProductMatchOption(id: 'SKU$index', name: 'Rotor $index'),
      ],
    );

    expect(proxy.calls, 0);
    expect(proxy.lastPrompt, isEmpty);
    service.dispose();
  });

  test('envía evidencia tipada e imágenes etiquetadas por candidato', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"same","product_id":"AE0145","components":[],'
      '"reason":"misma pinza Bucklos","confidence":0.92}',
    );
    final service = AIAssistantService(geminiProxy: proxy);
    final image = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Pinza Bucklos delantera 160 mm (Negro)',
      invoiceBrand: 'Bucklos',
      invoiceFamily: 'disc_brake_caliper',
      invoiceModelCodes: const <String>{'bk02'},
      invoiceSpecifications: const <String, String>{
        'posición': 'delantera',
        'rotor': '160 mm',
      },
      selectedVariant: 'Negro',
      quantity: 2,
      lineContext: 'segunda de seis líneas del mismo pedido',
      imageBytes: image,
      options: <AIProductMatchOption>[
        AIProductMatchOption(
          id: 'AE0145',
          name: 'Caliper Freno Delantero Mecánico Bucklos AE',
          brand: 'Bucklos',
          family: 'disc_brake_caliper',
          model: 'BK02',
          variant: 'Negro',
          specifications: const <String, String>{'rotor': '160 mm'},
          imageBytes: image,
        ),
        AIProductMatchOption(
          id: 'NNV128',
          name: 'Pinzas Industriales Precisión',
          family: 'tool_pliers',
          imageBytes: image,
        ),
      ],
    );

    expect(decision!.productId, 'AE0145');
    expect(proxy.lastPrompt, contains('"invoice_family":"disc_brake_caliper"'));
    expect(proxy.lastPrompt, contains('"invoice_model_codes":["bk02"]'));
    expect(proxy.lastPrompt, contains('"selected_variant":"Negro"'));
    expect(proxy.lastPrompt, contains('"quantity":2'));
    expect(proxy.lastPrompt, contains('BEGIN_UNTRUSTED_CATALOG_DATA_JSON'));
    expect(
      proxy.lastPrompt,
      contains('Incluye como máximo 5'),
      reason: 'todos los candidatos se comparan, pero no se narran 40 rechazos',
    );
    expect(
      proxy.lastPrompt,
      contains('rotor: coincide (160 mm)'),
    );
    expect(
      proxy.lastPrompt,
      contains('posición: fuente=delantera, candidato sin dato'),
    );
    expect(
      proxy.textParts,
      containsAll(<String>[
        'IMAGEN DE LA LÍNEA DE FACTURA:',
        'IMAGEN COMPARTIDA POR LOS CANDIDATOS ids=C001,C002:',
      ]),
    );
    expect(proxy.inlineDataParts, 2);
    service.dispose();
  });

  test('la evidencia de rechazo queda acotada sin perder la elección',
      () async {
    final rejected = <String>[
      for (var index = 2; index <= 7; index++)
        '{"product_id":"C00$index","reason":"diferencia $index",'
            '"basis":["spec"]}',
    ].join(',');
    final proxy = _ScriptedProxy(
      '{"decision":"same","picks":['
      '{"product_id":"C001","qty":1,"basis":["model","image"]}],'
      '"rejected":[$rejected],"confidence":0.96,'
      '"prompt_version":"${AIAssistantService.productMatchPromptKey}",'
      '"model_id":"gemini-2.5-flash"}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Maza trasera exacta',
      imageBytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
      requireTypedBasis: true,
      options: <AIProductMatchOption>[
        for (var index = 1; index <= 7; index++)
          AIProductMatchOption(
            id: 'product-$index',
            name: 'Maza candidata $index',
          ),
      ],
    );

    expect(decision, isNotNull);
    expect(decision!.productId, 'product-1');
    expect(
      decision.rejected.map((item) => item.productId),
      <String>[
        'product-2',
        'product-3',
        'product-4',
        'product-5',
        'product-6',
      ],
    );
    service.dispose();
  });

  test('propone un conjunto sólo con ids ofrecidos y cantidades positivas',
      () async {
    final proxy = _ScriptedProxy(
      '{"decision":"composite","product_id":null,"components":['
      '{"product_id":"LEFT","quantity":1},'
      '{"product_id":"RIGHT","quantity":1}],'
      '"reason":"el set trae manilla izquierda y derecha",'
      '"confidence":0.87}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Shimano ST-EF500 3x7 pair',
      options: const <AIProductMatchOption>[
        AIProductMatchOption(id: 'LEFT', name: 'Manilla ST-EF500 izquierda'),
        AIProductMatchOption(id: 'RIGHT', name: 'Manilla ST-EF500 derecha'),
      ],
    );

    expect(decision, isNotNull);
    expect(decision!.decision, AIProductMatchDecisionKind.composite);
    expect(decision.productId, isNull);
    expect(decision.hasChoice, isFalse);
    expect(
      decision.components
          .map((component) => '${component.productId}:${component.quantity}'),
      <String>['LEFT:1', 'RIGHT:1'],
    );
    service.dispose();
  });

  test('el contrato tipado representa un pack homogéneo de diez unidades',
      () async {
    final proxy = _ScriptedProxy(
      '{"decision":"composite","picks":['
      '{"product_id":"C001","qty":10,"role":"homogeneous",'
      '"basis":["model","spec"]}],"rejected":[],'
      '"confidence":0.98,'
      '"prompt_version":"${AIAssistantService.productMatchPromptKey}",'
      '"model_id":"gemini-2.5-flash"}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Oliva Shimano BH59',
      selectedVariant: 'for BH59-10pcs',
      supplierPackCount: 10,
      supplierUnitClass: 'piece',
      imageBytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
      requireTypedBasis: true,
      options: const <AIProductMatchOption>[
        AIProductMatchOption(id: 'OL03-ID', name: 'Oliva y pin Shimano BH59'),
      ],
    );

    expect(decision, isNotNull);
    expect(decision!.decision, AIProductMatchDecisionKind.composite);
    expect(decision.components, hasLength(1));
    expect(decision.components.single.productId, 'OL03-ID');
    expect(decision.components.single.quantity, 10);
    expect(
      decision.components.single.role,
      AIProductMatchComponentRole.homogeneous,
    );
    expect(proxy.lastPrompt, contains('"count":10'));
    expect(proxy.lastPrompt, contains('"unit_class":"piece"'));
    expect(proxy.lastPrompt, contains('role=`homogeneous`'));
    service.dispose();
  });

  test('roles delantero y trasero sobreviven la adjudicación tipada', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"composite","picks":['
      '{"product_id":"C001","qty":1,"role":"front",'
      '"basis":["image","spec"]},'
      '{"product_id":"C002","qty":1,"role":"rear",'
      '"basis":["image","spec"]}],"rejected":[],'
      '"confidence":0.96,'
      '"prompt_version":"${AIAssistantService.productMatchPromptKey}",'
      '"model_id":"gemini-2.5-flash"}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Juego pinzas Bucklos delantera y trasera',
      imageBytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
      requireTypedBasis: true,
      options: const <AIProductMatchOption>[
        AIProductMatchOption(id: 'FRONT-ID', name: 'Pinza delantera'),
        AIProductMatchOption(id: 'REAR-ID', name: 'Pinza trasera'),
      ],
    );

    expect(
      decision!.components.map((component) => component.role),
      <AIProductMatchComponentRole>[
        AIProductMatchComponentRole.front,
        AIProductMatchComponentRole.rear,
      ],
    );
    service.dispose();
  });

  test('un id inventado dentro del conjunto falla cerrado y queda marcado',
      () async {
    final proxy = _ScriptedProxy(
      '{"decision":"composite","product_id":null,"components":['
      '{"product_id":"LEFT","quantity":1},'
      '{"product_id":"INVENTED","quantity":1}],'
      '"reason":"parece un par","confidence":0.9}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Par de manillas',
      options: const <AIProductMatchOption>[
        AIProductMatchOption(id: 'LEFT', name: 'Manilla izquierda'),
        AIProductMatchOption(id: 'RIGHT', name: 'Manilla derecha'),
      ],
    );

    expect(decision, isNotNull);
    expect(decision!.decision, AIProductMatchDecisionKind.insufficient);
    expect(decision.invalidProductId, isTrue);
    expect(decision.components, isEmpty);
    service.dispose();
  });

  test('una cantidad compuesta no positiva o fraccionaria es salida inválida',
      () async {
    for (final quantity in <num>[0, -1, 1.5]) {
      final proxy = _ScriptedProxy(
        '{"decision":"composite","product_id":null,"components":['
        '{"product_id":"LEFT","quantity":$quantity}],'
        '"reason":"set","confidence":0.8}',
      );
      final service = AIAssistantService(geminiProxy: proxy);

      final decision = await service.adjudicateProductMatch(
        invoiceTitle: 'Set',
        options: const <AIProductMatchOption>[
          AIProductMatchOption(id: 'LEFT', name: 'Manilla izquierda'),
        ],
      );

      expect(decision, isNull, reason: 'quantity=$quantity');
      service.dispose();
    }
  });

  test('different e insufficient son decisiones distintas y cerradas',
      () async {
    for (final kind in <String>['different', 'insufficient']) {
      final proxy = _ScriptedProxy(
        '{"decision":"$kind","product_id":null,"components":[],'
        '"reason":"evidencia declarada","confidence":0.4}',
      );
      final service = AIAssistantService(geminiProxy: proxy);
      final decision = await service.adjudicateProductMatch(
        invoiceTitle: 'Producto',
        options: options,
      );

      expect(decision, isNotNull);
      expect(
        decision!.decision,
        kind == 'different'
            ? AIProductMatchDecisionKind.different
            : AIProductMatchDecisionKind.insufficient,
      );
      expect(decision.hasChoice, isFalse);
      service.dispose();
    }
  });

  test('una forma de decisión contradictoria no se repara', () async {
    final proxy = _ScriptedProxy(
      '{"decision":"different","product_id":"AE0145","components":[],'
      '"reason":"contradictorio","confidence":0.9}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Producto',
      options: options,
    );

    expect(decision, isNull);
    service.dispose();
  });

  test('el modelo desempata, no manda sobre un orden ya decidido', () {
    // Medido sobre AE150626: el motor tenía el producto correcto en 0.64
    // —misma marca y mismo modelo que la factura— y el modelo promovió un tubo
    // de V-Brake que estaba en 0.37. Una opinión no pisa una evidencia.
    const band = ProductDuplicateMatcherService.adjudicationTieBand;
    expect(0.37 < 0.64 - band, isTrue,
        reason: 'esa distancia no es un empate: el motor ya decidió');
    expect(0.62 < 0.64 - band, isFalse,
        reason: 'esto sí es un empate y ahí el modelo aporta');
  });

  test('una respuesta ilegible no rompe la fila', () async {
    final proxy = _ScriptedProxy('lo siento, no puedo');
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Rotor RT56',
      options: options,
    );

    expect(decision, isNull);
    service.dispose();
  });
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
  final List<String> textParts = <String>[];
  int inlineDataParts = 0;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
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
          textParts.add(text);
        }
        if (part is Map && part['inlineData'] is Map) {
          inlineDataParts++;
        }
      }
    }
    return GeminiProxyGenerateResult(text: reply, functionCalls: const []);
  }
}
