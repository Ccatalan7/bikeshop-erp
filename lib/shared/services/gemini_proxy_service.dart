import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GeminiProxyFunctionCall {
  const GeminiProxyFunctionCall({
    required this.name,
    required this.args,
  });

  final String name;
  final Map<String, dynamic> args;

  factory GeminiProxyFunctionCall.fromJson(Map<String, dynamic> json) {
    final rawArgs = json['args'];
    return GeminiProxyFunctionCall(
      name: (json['name'] ?? '').toString(),
      args: rawArgs is Map
          ? Map<String, dynamic>.from(rawArgs)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'args': args,
      };
}

class GeminiProxyGenerateResult {
  const GeminiProxyGenerateResult({
    required this.text,
    required this.functionCalls,
  });

  final String text;
  final List<GeminiProxyFunctionCall> functionCalls;
}

class GeminiProxyService {
  GeminiProxyService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<GeminiProxyGenerateResult> generateContent({
    required String model,
    required List<Map<String, dynamic>> contents,
    Map<String, dynamic>? systemInstruction,
    List<Map<String, dynamic>> tools = const [],
    Map<String, dynamic>? generationConfig,
  }) async {
    final data = await _invoke('generate-content', {
      'model': model,
      'contents': contents,
      if (systemInstruction != null) 'systemInstruction': systemInstruction,
      if (tools.isNotEmpty) 'tools': tools,
      if (generationConfig != null) 'generationConfig': generationConfig,
    });

    final rawFunctionCalls = data['functionCalls'];
    final functionCalls = rawFunctionCalls is List
        ? rawFunctionCalls
            .whereType<Map>()
            .map((item) => GeminiProxyFunctionCall.fromJson(
                Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <GeminiProxyFunctionCall>[];

    return GeminiProxyGenerateResult(
      text: (data['text'] ?? '').toString(),
      functionCalls: functionCalls,
    );
  }

  Future<String> generateText({
    required String prompt,
    required String model,
  }) async {
    final result = await generateContent(
      model: model,
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    );

    final text = result.text.trim();
    if (text.isEmpty) {
      throw StateError('Empty AI response');
    }
    return text;
  }

  Future<List<double>> generateEmbedding({
    required String text,
    String model = 'gemini-embedding-001',
    int outputDimensionality = 768,
  }) async {
    final data = await _invoke('embed-text', {
      'model': model,
      'text': text,
      'outputDimensionality': outputDimensionality,
    });

    final rawEmbedding = data['embedding'];
    if (rawEmbedding is! List) {
      throw StateError('Invalid embedding response from Gemini proxy');
    }

    return rawEmbedding
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _invoke(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final response = await _client.functions.invoke(
      'gemini-proxy',
      body: {
        'action': action,
        ...payload,
      },
    );

    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      final message = data is Map<String, dynamic>
          ? (data['error']?.toString() ?? 'Unknown Gemini proxy error')
          : data?.toString() ?? 'Unknown Gemini proxy error';
      throw Exception('Gemini proxy error: $message');
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    debugPrint('Unexpected Gemini proxy response type: ${data.runtimeType}');
    throw Exception('Gemini proxy error: Invalid response');
  }
}
