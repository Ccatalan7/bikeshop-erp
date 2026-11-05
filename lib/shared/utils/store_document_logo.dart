import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:vinabike_public_core/public_store/documents/store_document_style.dart';

/// The store's logo for a customer document —comprobante, cotización,
/// resumen de pedido— by the documents' one rule ([storeDocumentLogoSource]):
/// the site's logo, or the bundled one of the canonical store. [fallbackUrl]
/// (the ERP's company logo) counts only when the site has none. Null: the
/// letterhead writes the store's name.
Future<Uint8List?> loadStoreDocumentLogo({
  String? identityLogoUrl,
  String? tenantId,
  String? fallbackUrl,
}) async {
  final source = storeDocumentLogoSource(
        identityLogoUrl: identityLogoUrl,
        tenantId: tenantId,
      ) ??
      _https(fallbackUrl);
  if (source == null) return null;
  final pending = _logos.putIfAbsent(source, () => _read(source));
  try {
    return await pending;
  } catch (error) {
    // A failed read is tried again the next time.
    if (identical(_logos[source], pending)) _logos.remove(source);
    debugPrint('⚠️ [Membrete] sin logo ($source): $error');
    return null;
  }
}

final Map<String, Future<Uint8List?>> _logos = {};

Future<Uint8List?> _read(String source) async {
  // `assets/assets/images/…` is the web path of a bundled asset; the bundle
  // knows it without the first `assets/`.
  if (source.startsWith('assets/')) {
    final data = await rootBundle.load(source.substring('assets/'.length));
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  final response =
      await http.get(Uri.parse(source)).timeout(const Duration(seconds: 8));
  if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
    throw StateError('HTTP ${response.statusCode}');
  }
  return response.bodyBytes;
}

String? _https(String? url) {
  final value = url?.trim() ?? '';
  return value.startsWith('https://') ? value : null;
}

@visibleForTesting
void resetStoreDocumentLogosForTest() => _logos.clear();
