import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'storefront_config.dart';

/// The two reads a product page needs, made at the same time so the page
/// costs one round trip (`20261004180000_public_storefront_page_reads.sql`).
typedef ProductPageReads = ({
  Map<String, dynamic> shell,
  Map<String, dynamic>? page,
});

abstract interface class PublicReads {
  Future<ProductPageReads> productPage(String sku);
}

class PublicReadException implements Exception {
  PublicReadException(this.message);
  final String message;
  @override
  String toString() => 'PublicReadException: $message';
}

/// Calls the public Supabase functions with the publishable key, as `anon`.
class SupabasePublicReads implements PublicReads {
  SupabasePublicReads(this.config, {HttpClient? client})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..idleTimeout = const Duration(seconds: 60));

  final StorefrontConfig config;
  final HttpClient _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<ProductPageReads> productPage(String sku) async {
    final results = await Future.wait([
      _rpc('get_public_storefront_shell_v1', {'p_tenant_id': config.tenantId}),
      _rpc('get_public_product_page_v1', {
        'p_tenant_id': config.tenantId,
        'p_sku': sku,
      }),
    ]);
    final shell = results[0];
    final page = results[1];
    if (shell is! Map) {
      throw PublicReadException('shell is not an object');
    }
    return (
      shell: Map<String, dynamic>.from(shell),
      page: page is Map ? Map<String, dynamic>.from(page) : null,
    );
  }

  Future<Object?> _rpc(String function, Map<String, Object?> body) async {
    final uri = Uri.parse('${config.supabaseUrl}/rest/v1/rpc/$function');
    final request = await _client.postUrl(uri).timeout(_timeout);
    request.headers
      ..set('apikey', config.publishableKey)
      ..set('authorization', 'Bearer ${config.publishableKey}')
      ..contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(_timeout);
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_timeout);
    if (response.statusCode >= 300) {
      throw PublicReadException('$function → ${response.statusCode}');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}
