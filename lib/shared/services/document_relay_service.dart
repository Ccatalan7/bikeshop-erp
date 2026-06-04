import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_service.dart';

class DocumentRelayConfig {
  final bool enabled;
  final String endpointUrl;
  final String sharedToken;

  const DocumentRelayConfig({
    required this.enabled,
    required this.endpointUrl,
    this.sharedToken = '',
  });

  bool get isConfigured => enabled && endpointUrl.trim().isNotEmpty;

  DocumentRelayConfig copyWith({
    bool? enabled,
    String? endpointUrl,
    String? sharedToken,
  }) {
    return DocumentRelayConfig(
      enabled: enabled ?? this.enabled,
      endpointUrl: endpointUrl ?? this.endpointUrl,
      sharedToken: sharedToken ?? this.sharedToken,
    );
  }
}

class DocumentRelayResult {
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String sourceUrl;
  final int remoteStatusCode;

  const DocumentRelayResult({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.sourceUrl,
    required this.remoteStatusCode,
  });
}

class DocumentRelayNotConfiguredException implements Exception {
  const DocumentRelayNotConfiguredException();

  @override
  String toString() => 'El relay de documentos Chile no esta configurado.';
}

class DocumentRelayException implements Exception {
  final String message;

  const DocumentRelayException(this.message);

  @override
  String toString() => message;
}

class DocumentRelayService {
  DocumentRelayService({
    SupabaseClient? client,
    TenantService? tenantService,
    http.Client? httpClient,
  })  : _supabase = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService(),
        _httpClient = httpClient ?? http.Client();

  static const relayEnabledKey = 'document_relay_enabled';
  static const relayEndpointKey = 'document_relay_url';
  static const relayTokenKey = 'document_relay_token';
  static const _compileTimeEndpoint =
      String.fromEnvironment('VINABIKE_DOCUMENT_RELAY_URL');
  static const _compileTimeToken =
      String.fromEnvironment('VINABIKE_DOCUMENT_RELAY_TOKEN');
  static const _requestTimeout = Duration(seconds: 80);
  static const _maxPreviewBytes = 25 * 1024 * 1024;

  final SupabaseClient _supabase;
  final TenantService _tenantService;
  final http.Client _httpClient;

  static bool isLikelyRelayCandidate(Uri? uri) {
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();
    return host == '186.67.65.199' ||
        path.contains('getpdf') ||
        query.contains('doc=');
  }

  Future<DocumentRelayConfig> loadConfig() async {
    final tenantId = await _requireTenantId();
    final rows = await _supabase
        .from('company_settings')
        .select('key, value')
        .eq('tenant_id', tenantId)
        .inFilter('key', [
      relayEnabledKey,
      relayEndpointKey,
      relayTokenKey,
    ]);

    final values = <String, String>{};
    for (final row in rows as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      final key = map['key']?.toString();
      final value = map['value']?.toString();
      if (key != null && value != null) values[key] = value;
    }

    final endpoint = (values[relayEndpointKey]?.trim().isNotEmpty == true)
        ? values[relayEndpointKey]!.trim()
        : _compileTimeEndpoint.trim();
    final token = (values[relayTokenKey]?.trim().isNotEmpty == true)
        ? values[relayTokenKey]!.trim()
        : _compileTimeToken.trim();
    final enabled = values.containsKey(relayEnabledKey)
        ? _parseBool(values[relayEnabledKey])
        : endpoint.isNotEmpty;

    return DocumentRelayConfig(
      enabled: enabled,
      endpointUrl: endpoint,
      sharedToken: token,
    );
  }

  Future<void> saveConfig(DocumentRelayConfig config) async {
    final tenantId = await _requireTenantId();
    await _upsertSetting(
      tenantId: tenantId,
      key: relayEnabledKey,
      value: config.enabled ? 'true' : 'false',
    );
    await _upsertSetting(
      tenantId: tenantId,
      key: relayEndpointKey,
      value: config.endpointUrl.trim(),
    );
    await _upsertSetting(
      tenantId: tenantId,
      key: relayTokenKey,
      value: config.sharedToken.trim(),
    );
  }

  Future<DocumentRelayResult> fetchDocument(String sourceUrl) async {
    final config = await loadConfig();
    if (!config.isConfigured) {
      throw const DocumentRelayNotConfiguredException();
    }

    final sourceUri = Uri.tryParse(sourceUrl);
    if (!isLikelyRelayCandidate(sourceUri)) {
      throw const DocumentRelayException(
        'Este enlace no parece ser un documento compatible con relay.',
      );
    }

    final endpoint = Uri.tryParse(config.endpointUrl.trim());
    if (endpoint == null ||
        (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
      throw const DocumentRelayException(
        'La URL del relay de documentos no es valida.',
      );
    }

    final session = _supabase.auth.currentSession;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/pdf, application/octet-stream, application/json',
      if (session?.accessToken.trim().isNotEmpty == true)
        'Authorization': 'Bearer ${session!.accessToken}',
      if (config.sharedToken.trim().isNotEmpty)
        'X-Vinabike-Relay-Token': config.sharedToken.trim(),
    };

    final response = await _httpClient
        .post(
          endpoint,
          headers: headers,
          body: jsonEncode({
            'url': sourceUri!.toString(),
            'tenantId': await _requireTenantId(),
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DocumentRelayException(
        'El relay respondio HTTP ${response.statusCode}: '
        '${_responseSnippet(response.bodyBytes)}',
      );
    }

    final parsed = _parseRelayResponse(response, sourceUri);
    if (parsed.bytes.isEmpty) {
      throw const DocumentRelayException('El relay devolvio un archivo vacio.');
    }
    if (parsed.bytes.length > _maxPreviewBytes) {
      throw const DocumentRelayException(
        'El documento recibido es demasiado grande para previsualizar aqui.',
      );
    }

    return parsed;
  }

  DocumentRelayResult _parseRelayResponse(
    http.Response response,
    Uri sourceUri,
  ) {
    final contentType = _cleanMimeType(response.headers['content-type']);
    if (contentType == 'application/json' ||
        contentType == 'text/json' ||
        contentType == null && _looksLikeJson(response.bodyBytes)) {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final encoded =
          (data['bytesBase64'] ?? data['contentBase64'] ?? data['bodyBase64'])
              ?.toString();
      if (encoded == null || encoded.trim().isEmpty) {
        throw const DocumentRelayException(
          'El relay JSON no incluyo bytesBase64.',
        );
      }

      return DocumentRelayResult(
        bytes: Uint8List.fromList(base64Decode(encoded)),
        fileName: _safeFileName(
          data['fileName']?.toString(),
          fallback: _fallbackFileName(sourceUri),
        ),
        mimeType:
            _cleanMimeType(data['mimeType']?.toString()) ?? 'application/pdf',
        sourceUrl: data['sourceUrl']?.toString() ?? sourceUri.toString(),
        remoteStatusCode:
            int.tryParse(data['remoteStatusCode']?.toString() ?? '') ??
                response.statusCode,
      );
    }

    final dispositionName = _fileNameFromContentDisposition(
        response.headers['content-disposition']);
    return DocumentRelayResult(
      bytes: response.bodyBytes,
      fileName: _safeFileName(
        dispositionName,
        fallback: _fallbackFileName(sourceUri),
      ),
      mimeType: contentType ?? 'application/pdf',
      sourceUrl: sourceUri.toString(),
      remoteStatusCode: response.statusCode,
    );
  }

  bool _looksLikeJson(Uint8List bytes) {
    final decoded = utf8.decode(bytes.take(32).toList(), allowMalformed: true);
    return decoded.trimLeft().startsWith('{');
  }

  Future<void> _upsertSetting({
    required String tenantId,
    required String key,
    required String value,
  }) async {
    final existing = await _supabase
        .from('company_settings')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('key', key)
        .maybeSingle();
    final now = DateTime.now().toUtc().toIso8601String();

    if (existing != null) {
      await _supabase
          .from('company_settings')
          .update({'value': value, 'updated_at': now})
          .eq('tenant_id', tenantId)
          .eq('key', key);
      return;
    }

    await _supabase.from('company_settings').insert({
      'tenant_id': tenantId,
      'key': key,
      'value': value,
      'updated_at': now,
    });
  }

  Future<String> _requireTenantId() async {
    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw const DocumentRelayException(
        'No se pudo resolver el tenant actual.',
      );
    }
    return tenantId;
  }

  static bool _parseBool(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'si';
  }

  String? _cleanMimeType(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.split(';').first.trim().toLowerCase();
  }

  String _responseSnippet(Uint8List bytes) {
    final text = utf8.decode(bytes.take(220).toList(), allowMalformed: true);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _fileNameFromContentDisposition(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final utfMatch = RegExp(
      r'''filename\*=UTF-8''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(value);
    if (utfMatch != null) {
      return Uri.decodeFull(utfMatch.group(1)!.replaceAll('"', '').trim());
    }
    final match = RegExp(
      r'''filename="?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim();
  }

  String _safeFileName(String? value, {required String fallback}) {
    final raw = value?.trim().isNotEmpty == true ? value!.trim() : fallback;
    final clean = raw
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    if (clean.isEmpty) return fallback;
    return clean.toLowerCase().endsWith('.pdf') ? clean : '$clean.pdf';
  }

  String _fallbackFileName(Uri sourceUri) {
    final host = sourceUri.host.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return 'documento_${host}_$stamp.pdf';
  }
}
