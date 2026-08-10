import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/inventory/services/product_identity/product_visual_reading.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

/// One image, one model call.
///
/// The OCR flow used to send the same photo to Gemini twice per row: once to
/// write the shop name for it, once to recognise the object for the matcher.
/// Two calls, two latencies, two invoices' worth of quota — and two answers
/// with nothing reconciling them. Making vision unconditional would have made
/// that permanent, so the cleaner now returns both halves of one reading and
/// the identity engine consumes the half it needs.
void main() {
  test('una sola llamada devuelve el nombre y lo que se ve en la foto',
      () async {
    final proxy = _VisionAwareProxy();
    final service = AIAssistantService(geminiProxy: proxy);

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'HERRADURA FRENO V-BRAKE ALUMINIO HJ-612AD7',
      imageBytes: Uint8List.fromList(List<int>.generate(64, (i) => i)),
    );

    expect(proxy.calls, 1);
    expect(result?.cleanedName, isNotEmpty);
    expect(result?.visualAnalysis, isNotNull);
    expect(result!.visualAnalysis!.primaryType, 'herradura v-brake');
    expect(result.visualAnalysis!.confidence, 0.88);
    service.dispose();
  });

  test('sin foto no se acepta una lectura visual inventada', () async {
    // With no picture the model can only be paraphrasing the title, and the
    // whole value of this evidence is that it is independent of the words.
    final proxy = _VisionAwareProxy();
    final service = AIAssistantService(geminiProxy: proxy);

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'HERRADURA FRENO V-BRAKE ALUMINIO',
    );

    expect(proxy.calls, 1);
    expect(result?.visualAnalysis, isNull);
    service.dispose();
  });

  test('una lectura visual sin confianza no se toma por evidencia', () async {
    final proxy = _VisionAwareProxy(visionConfidence: 0);
    final service = AIAssistantService(geminiProxy: proxy);

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto borroso',
      imageBytes: Uint8List.fromList(List<int>.generate(64, (i) => i)),
    );

    expect(result?.visualAnalysis, isNull);
    service.dispose();
  });

  test('la lectura ya pagada se entrega y no se vuelve a pedir', () async {
    var analyzerCalls = 0;
    final readings = ProductVisualReadingService(
      analyzer: (bytes, {fileName, typedName}) async {
        analyzerCalls++;
        return const AIProductImageAnalysis(
          primaryType: 'rotor',
          catalogTerms: <String>['rotor'],
          excludedTerms: <String>[],
          confidence: 0.9,
        );
      },
    );

    readings.prime(
      cacheKey: 'listing-1005006',
      reading: ProductVisualReadingService.fromAnalysis(
        const AIProductImageAnalysis(
          primaryType: 'herradura v-brake',
          catalogTerms: <String>['herradura', 'v-brake'],
          excludedTerms: <String>['rotor'],
          confidence: 0.88,
        ),
      ),
    );

    final reading = await readings.read(
      cacheKey: 'listing-1005006',
      bytes: Uint8List.fromList(const <int>[1, 2, 3]),
    );

    expect(analyzerCalls, 0, reason: 'esa foto ya se leyó una vez');
    expect(readings.modelCalls, 0);
    expect(readings.primedReadings, 1);
    expect(reading.familyId, 'rim_brake_arm');
  });

  test('una foto que nunca se leyó sí cuesta su llamada', () async {
    var analyzerCalls = 0;
    final readings = ProductVisualReadingService(
      analyzer: (bytes, {fileName, typedName}) async {
        analyzerCalls++;
        return const AIProductImageAnalysis(
          primaryType: 'rotor',
          catalogTerms: <String>['rotor', 'disco de freno'],
          excludedTerms: <String>[],
          confidence: 0.9,
        );
      },
    );

    final first = await readings.read(
      cacheKey: 'listing-otra',
      bytes: Uint8List.fromList(const <int>[9, 9, 9]),
    );
    final second = await readings.read(
      cacheKey: 'listing-otra',
      bytes: Uint8List.fromList(const <int>[9, 9, 9]),
    );

    expect(analyzerCalls, 1, reason: 'la segunda línea reusa la primera');
    expect(readings.modelCalls, 1);
    expect(first.familyId, second.familyId);
    expect(first.familyId, 'brake_rotor');
  });

  test('una lectura vacía no ocupa la caché ni miente al matcher', () async {
    final readings = ProductVisualReadingService(
      analyzer: (bytes, {fileName, typedName}) async => null,
    );
    readings.prime(
      cacheKey: 'listing-vacia',
      reading: ProductVisualReading.empty,
    );
    expect(readings.primedReadings, 0);
  });
}

class _VisionAwareProxy extends GeminiProxyService {
  _VisionAwareProxy({this.visionConfidence = 0.88})
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  final double visionConfidence;
  int calls = 0;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
    Map<String, dynamic>? generationConfig,
  }) async {
    calls++;
    return GeminiProxyGenerateResult(
      text: jsonEncode({
        'cleaned_name': 'Herradura V-Brake Aluminio',
        'component_type': 'herradura',
        'category_name': 'Herraduras',
        'confidence': 0.9,
        'vision': {
          'primary_type': 'herradura v-brake',
          'catalog_terms': ['herradura', 'v-brake', 'aluminio'],
          'excluded_terms': ['rotor', 'pastilla'],
          'confidence': visionConfidence,
        },
      }),
      functionCalls: const [],
    );
  }
}
