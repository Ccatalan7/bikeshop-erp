import 'dart:convert';

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
      '{"id":"AE0145","reason":"es el caliper delantero Bucklos, misma marca y '
      'mismo lado","confidence":0.9}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'BUCKLOS-pinza de freno de disco de bicicleta, 160mm',
      options: options,
    );

    expect(decision!.productId, 'AE0145');
    expect(decision.reason, contains('caliper'));
    expect(proxy.calls, 1);
    service.dispose();
  });

  test('un id que nadie ofreció no es una elección: se descarta', () async {
    // A model that answers with a SKU nobody handed it has written a product,
    // not chosen one. Repairing that guess is how an invented code reaches the
    // catalog.
    final proxy = _ScriptedProxy(
      '{"id":"AE9999","reason":"inventado","confidence":0.99}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'BUCKLOS-pinza de freno de disco',
      options: options,
    );

    expect(decision!.hasChoice, isFalse);
    service.dispose();
  });

  test('«ninguno» es una respuesta válida, no un fallo', () async {
    final proxy = _ScriptedProxy(
      '{"id":null,"reason":"ninguno es la misma pieza","confidence":0.2}',
    );
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Producto que no existe en el catálogo',
      options: options,
    );

    expect(decision, isNotNull);
    expect(decision!.hasChoice, isFalse);
    expect(decision.reason, isNotNull);
    service.dispose();
  });

  test('sin candidatos no se gasta una llamada', () async {
    final proxy = _ScriptedProxy('{"id":null}');
    final service = AIAssistantService(geminiProxy: proxy);

    final decision = await service.adjudicateProductMatch(
      invoiceTitle: 'Cualquier cosa',
      options: const <AIProductMatchOption>[],
    );

    expect(decision, isNull);
    expect(proxy.calls, 0, reason: 'no hay nada que elegir');
    service.dispose();
  });

  test('la lista que ve el modelo está acotada', () async {
    final proxy = _ScriptedProxy('{"id":null,"confidence":0}');
    final service = AIAssistantService(geminiProxy: proxy);

    await service.adjudicateProductMatch(
      invoiceTitle: 'Rotor',
      options: <AIProductMatchOption>[
        for (var index = 0; index < 40; index++)
          AIProductMatchOption(id: 'SKU$index', name: 'Rotor $index'),
      ],
    );

    final sent = proxy.lastPrompt;
    expect(sent, contains('SKU0'));
    expect(
      sent,
      isNot(contains('SKU${AIAssistantService.maxAdjudicationCandidates}')),
      reason: 'una lista sin techo es una cuenta sin techo',
    );
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
          lastPrompt = part['text'] as String;
        }
      }
    }
    return GeminiProxyGenerateResult(text: reply, functionCalls: const []);
  }
}
