import 'dart:convert';

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

class GeminiProxyException implements Exception {
  const GeminiProxyException({
    required this.message,
    this.statusCode,
    this.functionStatus,
    this.apiStatus,
    this.details,
  });

  final String message;
  final int? statusCode;
  final int? functionStatus;
  final String? apiStatus;
  final Object? details;

  bool get isAuthenticationError => functionStatus == 401 || statusCode == 401;

  bool get isConfigurationError =>
      statusCode == 500 && message.toLowerCase().contains('not configured');

  bool get isTransient {
    if (isAuthenticationError || isConfigurationError) {
      return false;
    }

    final status = statusCode;
    if (status != null &&
        const {408, 429, 500, 502, 503, 504}.contains(status)) {
      return true;
    }

    final lower = message.toLowerCase();
    return lower.contains('unavailable') ||
        lower.contains('high demand') ||
        lower.contains('overloaded') ||
        lower.contains('rate limit') ||
        lower.contains('quota');
  }

  @override
  String toString() {
    final status = statusCode != null ? 'statusCode: $statusCode, ' : '';
    final api = apiStatus != null ? 'apiStatus: $apiStatus, ' : '';
    return 'GeminiProxyException($status$api'
        'message: $message)';
  }
}

class GeminiProxyService {
  GeminiProxyService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  static const int _maxAttempts = 3;

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
    GeminiProxyException? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        return await _invokeOnce(action, payload);
      } on GeminiProxyException catch (error) {
        lastError = error;
        final shouldRetry = error.isTransient && attempt < _maxAttempts - 1;
        if (!shouldRetry) {
          rethrow;
        }

        final delay = Duration(milliseconds: 700 * (1 << attempt));
        debugPrint(
          'Gemini proxy transient error '
          '(${error.statusCode ?? error.functionStatus ?? 'unknown'}), '
          'retrying in ${delay.inMilliseconds}ms: ${error.message}',
        );
        await Future.delayed(delay);
      }
    }

    throw lastError ??
        const GeminiProxyException(message: 'Unknown Gemini proxy error');
  }

  Future<Map<String, dynamic>> _invokeOnce(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'gemini-proxy',
        body: {
          'action': action,
          ...payload,
        },
      );
    } on FunctionException catch (error) {
      throw _exceptionFromFunctionException(error);
    }

    final data = response.data;
    if (response.status < 200 || response.status >= 300) {
      throw _exceptionFromProxyPayload(response.status, data);
    }

    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    debugPrint('Unexpected Gemini proxy response type: ${data.runtimeType}');
    throw const GeminiProxyException(
      message: 'Invalid response from Gemini proxy',
    );
  }

  GeminiProxyException _exceptionFromFunctionException(
    FunctionException error,
  ) {
    return _exceptionFromProxyPayload(
      error.status,
      error.details,
      fallbackReason: error.reasonPhrase,
    );
  }

  GeminiProxyException _exceptionFromProxyPayload(
    int functionStatus,
    Object? data, {
    String? fallbackReason,
  }) {
    final map = _asStringKeyMap(data);
    final rawMessage = map?['error']?.toString() ??
        data?.toString() ??
        fallbackReason ??
        'Unknown Gemini proxy error';
    final message = _cleanProxyErrorMessage(rawMessage);
    final upstreamStatus = _asInt(map?['upstreamStatus']) ??
        _asInt(map?['upstreamCode']) ??
        _parseStatusFromMessage(rawMessage);
    final apiStatus = map?['upstreamStatusText']?.toString() ??
        _parseApiStatusFromMessage(rawMessage);

    return GeminiProxyException(
      message: message.isEmpty ? 'Unknown Gemini proxy error' : message,
      statusCode: upstreamStatus ?? functionStatus,
      functionStatus: functionStatus,
      apiStatus: apiStatus,
      details: data,
    );
  }

  Map<String, dynamic>? _asStringKeyMap(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return null;
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _parseStatusFromMessage(String message) {
    final patterns = [
      RegExp(r'Gemini API error:\s*(\d{3})'),
      RegExp(r'"code"\s*:\s*(\d{3})'),
      RegExp(r'\bcode\s*:\s*(\d{3})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return int.tryParse(match.group(1) ?? '');
      }
    }
    return null;
  }

  String? _parseApiStatusFromMessage(String message) {
    final jsonStyle = RegExp(r'"status"\s*:\s*"([^"]+)"').firstMatch(message);
    if (jsonStyle != null) {
      return jsonStyle.group(1);
    }

    final plainStyle = RegExp(r'\bstatus\s*:\s*([A-Z_]+)').firstMatch(message);
    return plainStyle?.group(1);
  }

  String _cleanProxyErrorMessage(String message) {
    final trimmed = message.trim();
    final jsonStart = trimmed.indexOf('{');
    if (jsonStart != -1) {
      try {
        final decoded = jsonDecode(trimmed.substring(jsonStart));
        if (decoded is Map) {
          final nestedMessage = decoded['message']?.toString().trim();
          if (nestedMessage != null && nestedMessage.isNotEmpty) {
            return nestedMessage;
          }
        }
      } catch (_) {
        // Fall through to the plain text cleanup below.
      }
    }

    return trimmed
        .replaceFirst(RegExp(r'^Gemini API error:\s*\d{3}\s*'), '')
        .trim();
  }
}
