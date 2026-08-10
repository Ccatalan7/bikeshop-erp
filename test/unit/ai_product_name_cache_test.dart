import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/shared/services/gemini_proxy_service.dart';

void main() {
  test(
      'different images with identical headers never share a clean-name result',
      () async {
    final proxy = _CountingGeminiProxy();
    final service = AIAssistantService(geminiProxy: proxy);
    final commonHeader = List<int>.generate(64, (index) => index);

    final first = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto de prueba',
      imageBytes: Uint8List.fromList([...commonHeader, 1]),
    );
    final second = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto de prueba',
      imageBytes: Uint8List.fromList([...commonHeader, 2]),
    );

    expect(proxy.calls, 2);
    expect(first?.cleanedName, 'Producto 1');
    expect(second?.cleanedName, 'Producto 2');
    service.dispose();
  });

  test('identical concurrent requests share one in-flight Gemini call',
      () async {
    final proxy = _CountingGeminiProxy()..gate = Completer<void>();
    final service = AIAssistantService(geminiProxy: proxy);
    final bytes = Uint8List.fromList(List<int>.generate(80, (index) => index));

    final first = service.cleanProductTitleFromImage(
      rawTitle: 'Mismo producto',
      imageBytes: bytes,
    );
    final second = service.cleanProductTitleFromImage(
      rawTitle: 'Mismo producto',
      imageBytes: bytes,
    );
    await Future<void>.delayed(Duration.zero);

    expect(proxy.calls, 1);
    proxy.gate!.complete();
    final results = await Future.wait([first, second]);
    expect(results[0]?.cleanedName, results[1]?.cleanedName);
    expect(proxy.calls, 1);
    service.dispose();
  });

  test('stalled image URL is bounded and identical requests share the fallback',
      () async {
    final proxy = _CountingGeminiProxy();
    var clientCount = 0;
    late _StalledImageClient imageClient;
    final service = AIAssistantService(
      geminiProxy: proxy,
      imageDownloadTimeout: const Duration(milliseconds: 10),
      imageHttpClientFactory: () {
        clientCount++;
        return imageClient = _StalledImageClient();
      },
    );

    final first = service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/product.jpg',
    );
    final second = service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/product.jpg',
    );
    final results = await Future.wait([first, second]).timeout(
      const Duration(seconds: 1),
    );

    expect(clientCount, 1);
    expect(imageClient.isClosed, isTrue);
    expect(proxy.calls, 1);
    expect(proxy.callsWithInlineImage, 0);
    expect(results[0]?.cleanedName, results[1]?.cleanedName);

    await service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/product.jpg',
    );
    expect(clientCount, 1);
    expect(proxy.calls, 1);
    service.dispose();
  });

  test('non-image URL response is excluded from the Gemini request', () async {
    final proxy = _CountingGeminiProxy();
    final service = AIAssistantService(
      geminiProxy: proxy,
      imageHttpClientFactory: () => MockClient(
        (_) async => http.Response(
          '<html>not an image</html>',
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/product.jpg',
    );

    expect(result, isNotNull);
    expect(proxy.calls, 1);
    expect(proxy.callsWithInlineImage, 0);
    service.dispose();
  });

  test('oversized image URL response is excluded from the Gemini request',
      () async {
    final proxy = _CountingGeminiProxy();
    final service = AIAssistantService(
      geminiProxy: proxy,
      imageHttpClientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          const [0xFF, 0xD8, 0xFF, 0xD9],
          200,
          headers: const {
            'content-type': 'image/jpeg',
            'content-length': '${8 * 1024 * 1024 + 1}',
          },
        ),
      ),
    );

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/oversized.jpg',
    );

    expect(result, isNotNull);
    expect(proxy.calls, 1);
    expect(proxy.callsWithInlineImage, 0);
    service.dispose();
  });

  test('bounded downloader still forwards a valid raster image', () async {
    final proxy = _CountingGeminiProxy();
    final service = AIAssistantService(
      geminiProxy: proxy,
      imageHttpClientFactory: () => MockClient(
        (_) async => http.Response.bytes(
          const [0xFF, 0xD8, 0xFF, 0xD9],
          200,
          headers: const {'content-type': 'image/jpeg'},
        ),
      ),
    );

    final result = await service.cleanProductTitleFromImage(
      rawTitle: 'Producto remoto',
      imageUrl: 'https://example.com/product.jpg',
    );

    expect(result, isNotNull);
    expect(proxy.calls, 1);
    expect(proxy.callsWithInlineImage, 1);
    service.dispose();
  });
}

class _StalledImageClient extends http.BaseClient {
  final StreamController<List<int>> _body = StreamController<List<int>>();
  bool isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      _body.stream,
      200,
      headers: const {'content-type': 'image/jpeg'},
    );
  }

  @override
  void close() {
    isClosed = true;
    unawaited(_body.close());
    super.close();
  }
}

class _CountingGeminiProxy extends GeminiProxyService {
  _CountingGeminiProxy()
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
          ),
        );

  int calls = 0;
  int callsWithInlineImage = 0;
  Completer<void>? gate;

  @override
  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
    Map<String, dynamic>? generationConfig,
  }) async {
    final sequence = ++calls;
    if (_containsInlineImage(contents)) callsWithInlineImage++;
    await gate?.future;
    return GeminiProxyGenerateResult(
      text: jsonEncode({
        'cleaned_name': 'Producto $sequence',
        'component_type': 'componente',
        'category_name': 'Componentes',
        'confidence': 0.9,
      }),
      functionCalls: const [],
    );
  }

  bool _containsInlineImage(List<Map<String, dynamic>> contents) {
    for (final content in contents) {
      final parts = content['parts'];
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is Map && part.containsKey('inlineData')) return true;
      }
    }
    return false;
  }
}
