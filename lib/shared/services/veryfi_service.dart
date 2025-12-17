import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Veryfi integration helper.
///
/// This is a small, configurable wrapper that uploads a document (bytes)
/// to a Veryfi-compatible endpoint and returns the parsed JSON response.
///
/// Note: supply the correct `apiUrl` and `extraHeaders` according to your
/// Veryfi account / plan. This wrapper intentionally does not hardcode
/// authentication header names — instead you provide them in `extraHeaders`.
class VeryfiConfig {
  final String apiUrl;
  final Map<String, String> extraHeaders;

  const VeryfiConfig({
    required this.apiUrl,
    this.extraHeaders = const {},
  });
}

class VeryfiService {
  final VeryfiConfig config;
  final http.Client _http;

  VeryfiService(this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Upload document bytes to Veryfi and return decoded JSON response.
  ///
  /// - `bytes`: file bytes (PDF, image, etc.)
  /// - `filename`: original filename (used for extension/content-type hints)
  /// - `fieldName`: form field name expected by the server (defaults to `file`)
  Future<Map<String, dynamic>> parseInvoiceFromBytes(
    Uint8List bytes,
    String filename, {
    String fieldName = 'file',
  }) async {
    final uri = Uri.parse(config.apiUrl);

    final request = http.MultipartRequest('POST', uri);

    // Allow callers to pass required authentication or other headers
    if (config.extraHeaders.isNotEmpty) {
      request.headers.addAll(config.extraHeaders);
    }

    // Note: Veryfi v8 API doesn't accept country_code as form field
    // Locale is auto-detected from the document

    final multipartFile = http.MultipartFile.fromBytes(
      fieldName,
      bytes,
      filename: filename,
    );

    request.files.add(multipartFile);

    debugPrint('🚀 Veryfi: Sending request to $uri');
    debugPrint('🚀 Veryfi: Client type: ${_http.runtimeType}');

    try {
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      debugPrint('🚀 Veryfi: Response status: ${response.statusCode}');

      // DEBUG: Log full response body to see what Veryfi returns
      debugPrint('📄 Veryfi RAW RESPONSE START ===');
      debugPrint(response.body);
      debugPrint('📄 Veryfi RAW RESPONSE END ===');

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Veryfi API error: ${response.statusCode} ${response.body}');
      }

      final decoded = json.decode(response.body);
      return Map<String, dynamic>.from(decoded as Map);
    } catch (e, stack) {
      debugPrint('❌ Veryfi Request Error: $e');
      debugPrint('❌ Stack trace: $stack');
      if (e is http.ClientException) {
        debugPrint('❌ ClientException URI: ${e.uri}');
        debugPrint('❌ ClientException Message: ${e.message}');
      }
      rethrow;
    }
  }

  /// Convenience: parse from a platform-provided bytes provider.
  Future<Map<String, dynamic>> parseInvoiceFromBytesProvider(
    List<int> bytes,
    String filename,
  ) async {
    return parseInvoiceFromBytes(Uint8List.fromList(bytes), filename);
  }

  void dispose() {
    _http.close();
  }
}

/*
Usage example (pseudo-code):

final cfg = VeryfiConfig(
  apiUrl: 'https://api.veryfi.com/api/v7/partner/documents/',
  extraHeaders: {
    // Provide the exact headers your Veryfi plan requires.
    // For example (fill with your real values):
    // 'Client-Id': '<CLIENT_ID>',
    // 'Authorization': 'apikey <CLIENT_ID>:<API_KEY>',
    // 'Accept': 'application/json',
  },
);

final svc = VeryfiService(cfg);
final result = await svc.parseInvoiceFromBytes(fileBytes, 'invoice.jpg');

// Map returned JSON fields to your invoice model as needed.
*/
