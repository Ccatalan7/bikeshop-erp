import 'web_data_bridge_stub.dart'
    if (dart.library.js_interop) 'web_data_bridge_web.dart';

/// Bridge to access data pre-fetched by index.html
/// Uses conditional imports to be safe for Android/iOS
class WebDataBridge {
  /// Returns the tenant-owned public-store payload preloaded by index.html.
  ///
  /// A missing, malformed, or differently owned envelope fails closed so a
  /// bootstrap response can never be projected into another tenant.
  static Future<Map<String, dynamic>?> getPreloadedStoreData({
    required String expectedTenantId,
  }) async {
    final envelope = await getPreloadedStoreDataImpl();
    return validatePreloadedStoreEnvelope(
      envelope,
      expectedTenantId: expectedTenantId,
    );
  }
}

/// Validates the ownership and shape of a public-store preload envelope.
///
/// Kept platform-neutral so the same fail-closed contract can be exercised by
/// unit tests without a browser runtime.
Map<String, dynamic>? validatePreloadedStoreEnvelope(
  Object? envelope, {
  required String expectedTenantId,
}) {
  final normalizedExpectedTenantId = expectedTenantId.trim();
  if (normalizedExpectedTenantId.isEmpty || envelope is! Map<String, dynamic>) {
    return null;
  }

  final envelopeTenantId = envelope['tenant_id'];
  final payload = envelope['payload'];
  if (envelopeTenantId is! String ||
      envelopeTenantId.trim() != normalizedExpectedTenantId ||
      payload is! Map<String, dynamic>) {
    return null;
  }

  final payloadTenantId = payload['tenant_id'];
  if (payloadTenantId is! String ||
      payloadTenantId.trim() != normalizedExpectedTenantId) {
    return null;
  }

  return Map<String, dynamic>.from(payload);
}
