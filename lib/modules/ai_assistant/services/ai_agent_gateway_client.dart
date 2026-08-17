import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/config/supabase_config.dart';
import '../models/ai_agent_gateway_contracts.dart';

const int _maxGatewayResponseBytes = 128 * 1024;

class AIAgentGatewayException implements Exception {
  const AIAgentGatewayException({
    required this.code,
    this.statusCode,
    this.outcomeUnknown = false,
  });

  final String code;
  final int? statusCode;

  /// True only when the transport cannot prove whether the server admitted or
  /// completed the request. A retry must reuse the same clientRequestId.
  final bool outcomeUnknown;

  @override
  String toString() => 'AI agent gateway request failed ($code)';
}

abstract interface class AIAgentGatewayTransport {
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  });
}

class SupabaseAIAgentGatewayTransport implements AIAgentGatewayTransport {
  SupabaseAIAgentGatewayTransport({
    String supabaseUrl = SupabaseConfig.url,
    String publishableKey = SupabaseConfig.publishableKey,
    Future<String?> Function()? accessTokenProvider,
    http.Client Function()? httpClientFactory,
    Duration timeout = const Duration(seconds: 95),
  })  : _endpoint = _gatewayEndpoint(supabaseUrl),
        _publishableKey = _requiredSecret(publishableKey),
        _accessTokenProvider = accessTokenProvider ?? _currentAccessToken,
        _httpClientFactory = httpClientFactory ?? http.Client.new,
        _timeout = timeout;

  final Uri _endpoint;
  final String _publishableKey;
  final Future<String?> Function() _accessTokenProvider;
  final http.Client Function() _httpClientFactory;
  final Duration _timeout;

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    final token = (await _accessTokenProvider())?.trim();
    if (token == null || token.isEmpty) {
      throw const AIAgentGatewayException(
        code: 'invalid_session',
        statusCode: 401,
      );
    }

    final timeoutCompleter = Completer<void>();
    final timeoutTimer = Timer(_timeout, timeoutCompleter.complete);
    final request = http.AbortableRequest(
      'POST',
      _endpoint,
      abortTrigger: Future.any<void>(<Future<void>>[
        abortTrigger,
        timeoutCompleter.future,
      ]),
    )
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'apikey': _publishableKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Capability negotiation keeps older strict card decoders compatible
        // while desktop, mobile and web clients roll forward independently.
        'x-vinabike-ai-result-lists': '1',
        'x-vinabike-ai-structured-clarifications': '1',
      })
      ..body = jsonEncode(body);

    final client = _httpClientFactory();
    try {
      final response = await client.send(request);
      final bytes = await _readBoundedResponse(response);
      final decoded = _decodeJson(bytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final code =
            _safeErrorCode(decoded) ?? _codeForStatus(response.statusCode);
        throw AIAgentGatewayException(
          code: code,
          statusCode: response.statusCode,
          // The gateway uses this code only when a run was admitted but its
          // terminal commit could not be confirmed. Replaying with the same
          // client identifier is the sole safe reconciliation path. Approval
          // actions have their own stable clientActionId.
          outcomeUnknown: code == 'run_finalization_pending' ||
              code == 'approval_unavailable',
        );
      }
      return decoded;
    } on http.RequestAbortedException {
      if (timeoutCompleter.isCompleted) {
        throw const AIAgentGatewayException(
          code: 'request_timeout',
          statusCode: 504,
          outcomeUnknown: true,
        );
      }
      throw const AIAgentGatewayException(
        code: 'request_aborted',
        outcomeUnknown: true,
      );
    } on AIAgentGatewayException {
      rethrow;
    } catch (_) {
      throw const AIAgentGatewayException(
        code: 'gateway_unavailable',
        outcomeUnknown: true,
      );
    } finally {
      timeoutTimer.cancel();
      client.close();
    }
  }

  static Future<String?> _currentAccessToken() async =>
      Supabase.instance.client.auth.currentSession?.accessToken;
}

class AIAgentGatewayClient {
  AIAgentGatewayClient({AIAgentGatewayTransport? transport})
      : _transport = transport ?? SupabaseAIAgentGatewayTransport();

  final AIAgentGatewayTransport _transport;

  Future<AIAgentGatewayResponse> complete(
    AIAgentGatewayRequest request, {
    required Future<void> abortTrigger,
  }) async {
    final raw = await _transport.send(
      request.toJson(),
      abortTrigger: abortTrigger,
    );
    if (raw is! Map) throw const AIAgentGatewayContractException();
    return AIAgentGatewayResponse.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<AIAgentGatewayApprovalResponse> resolveApproval(
    AIAgentGatewayApprovalRequest request, {
    required Future<void> abortTrigger,
  }) async {
    final raw = await _transport.send(
      request.toJson(),
      abortTrigger: abortTrigger,
    );
    if (raw is! Map) throw const AIAgentGatewayContractException();
    return AIAgentGatewayApprovalResponse.fromJson(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

Future<Uint8List> _readBoundedResponse(http.StreamedResponse response) async {
  final builder = BytesBuilder(copy: false);
  var count = 0;
  await for (final chunk in response.stream) {
    count += chunk.length;
    if (count > _maxGatewayResponseBytes) {
      throw const AIAgentGatewayException(
        code: 'response_too_large',
        outcomeUnknown: true,
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Object? _decodeJson(Uint8List bytes) {
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: false));
  } catch (_) {
    throw const AIAgentGatewayException(
      code: 'invalid_response',
      outcomeUnknown: true,
    );
  }
}

String? _safeErrorCode(Object? value) {
  if (value is! Map) return null;
  final code = value['code'];
  if (code is! String || !RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(code)) {
    return null;
  }
  return code;
}

String _codeForStatus(int status) => switch (status) {
      401 => 'invalid_session',
      403 => 'forbidden',
      408 || 504 => 'request_timeout',
      429 => 'rate_limited',
      _ => 'gateway_unavailable',
    };

Uri _gatewayEndpoint(String rawBaseUrl) {
  final base = Uri.tryParse(rawBaseUrl.trim());
  if (base == null || !base.hasAuthority) {
    throw ArgumentError('A valid Supabase URL is required.');
  }
  final local = const <String>{'localhost', '127.0.0.1', '::1'}
      .contains(base.host.toLowerCase());
  if (base.scheme != 'https' && !(local && base.scheme == 'http')) {
    throw ArgumentError('Supabase URL must use HTTPS.');
  }
  return base.replace(
    path:
        '${base.path.replaceFirst(RegExp(r'/$'), '')}/functions/v1/ai-agent-gateway',
    query: null,
    fragment: null,
  );
}

String _requiredSecret(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError('Supabase publishable key is required.');
  }
  return normalized;
}
