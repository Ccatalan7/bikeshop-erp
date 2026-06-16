import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WhatsAppCatalogSyncResult {
  const WhatsAppCatalogSyncResult({
    required this.action,
    required this.retailerId,
    this.syncStatus,
    this.whatsappReview,
    this.expectedUrl,
    this.storedUrl,
    this.urlMatches,
  });

  final String action;
  final String retailerId;

  /// Server lifecycle status: under_review | customer_visible | rejected |
  /// removed | pending. 'customer_visible' is the only state where the product
  /// is actually visible to customers in WhatsApp.
  final String? syncStatus;

  /// Raw Meta WhatsApp review value (APPROVED / NO_REVIEW / REJECTED / ...).
  final String? whatsappReview;
  final String? expectedUrl;
  final String? storedUrl;
  final bool? urlMatches;

  bool get wasPublished => action == 'upserted';
  bool get wasRemoved => action == 'removed' || action == 'already_absent';
  bool get isCustomerVisible => syncStatus == 'customer_visible';
  bool get isUnderReview => syncStatus == 'under_review';
}

class WhatsAppCatalogSyncService {
  WhatsAppCatalogSyncService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<WhatsAppCatalogSyncResult> syncProduct(String productId) async {
    return _runWithRetries(productId, mode: 'sync');
  }

  /// Re-reads Meta's current WhatsApp review state for an already-uploaded
  /// product WITHOUT re-uploading it. Use this to converge the stored status to
  /// real customer visibility (Meta approves catalog products asynchronously).
  Future<WhatsAppCatalogSyncResult> refreshStatus(String productId) async {
    return _runWithRetries(productId, mode: 'refresh');
  }

  Future<WhatsAppCatalogSyncResult> _runWithRetries(
    String productId, {
    required String mode,
  }) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception(
        'Tu sesión expiró. Inicia sesión nuevamente para sincronizar WhatsApp.',
      );
    }

    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        return await _invokeSync(productId, accessToken, mode);
      } catch (error) {
        lastError = error;
        final message = error.toString().replaceFirst('Exception: ', '');
        debugPrint(
          'WhatsApp catalog $mode attempt $attempt/3 failed: $message',
        );
        if (attempt == 3 || _isPermanentFailure(message)) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }

    throw lastError ?? Exception('No se pudo sincronizar WhatsApp.');
  }

  Future<WhatsAppCatalogSyncResult> _invokeSync(
    String productId,
    String accessToken,
    String mode,
  ) async {
    try {
      final response = await _client.functions.invoke(
        'whatsapp-catalog-sync',
        headers: {'Authorization': 'Bearer $accessToken'},
        body: {'productId': productId, 'mode': mode},
      );

      if (response.status >= 300) {
        throw Exception(_errorMessage(response.data));
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      return WhatsAppCatalogSyncResult(
        action: data['action']?.toString() ?? 'unknown',
        retailerId: data['retailerId']?.toString() ?? productId,
        syncStatus: data['syncStatus']?.toString(),
        whatsappReview: data['whatsappReview']?.toString(),
        expectedUrl: data['expectedUrl']?.toString(),
        storedUrl: data['storedUrl']?.toString(),
        urlMatches: data['urlMatches'] as bool?,
      );
    } on FunctionException catch (error) {
      throw Exception(_errorMessage(error.details));
    }
  }

  bool _isPermanentFailure(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('completa estos datos') ||
        normalized.contains('faltan datos obligatorios') ||
        normalized.contains('unauthorized') ||
        normalized.contains('no active whatsapp') ||
        normalized.contains('no product catalog');
  }

  String _errorMessage(dynamic value) {
    if (value == null) return 'No se pudo sincronizar el catálogo de WhatsApp.';
    if (value is String) return value;
    if (value is Map) {
      final missing = value['missing'];
      if (missing is List && missing.isNotEmpty) {
        final labels = missing.map((field) {
          return switch (field.toString()) {
            'title' || 'name' => 'título',
            'description' => 'descripción',
            'image' || 'image_url' => 'imagen',
            'price' => 'precio',
            _ => field.toString(),
          };
        }).join(', ');
        return 'Completa estos datos de WhatsApp: $labels.';
      }
      for (final key in const ['error', 'message', 'details', 'msg']) {
        if (!value.containsKey(key)) continue;
        final message = _errorMessage(value[key]);
        if (message.isNotEmpty) return message;
      }
    }
    return value.toString();
  }
}
