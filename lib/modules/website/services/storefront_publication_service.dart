import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/storefront_publication_status.dart';

typedef StorefrontPublicationRpcInvoker = Future<Object?> Function(
  String rpc,
  Map<String, dynamic> params,
);

typedef StorefrontPublicationClock = DateTime Function();

/// Reads and retries the server-owned storefront publication operation.
///
/// Tenant is the only target identity accepted by the client. Repository,
/// workflow, branch, deployment target, domain and revision are resolved and
/// authorized by PostgreSQL and the private dispatcher.
class StorefrontPublicationService {
  StorefrontPublicationService({
    StorefrontPublicationRpcInvoker? invoke,
    StorefrontPublicationClock? clock,
  })  : _invoke = invoke ?? _defaultInvoke,
        _clock = clock ?? DateTime.now;

  static const statusRpc = 'get_storefront_publication_status';
  static const retryRpc = 'retry_storefront_publication';

  final StorefrontPublicationRpcInvoker _invoke;
  final StorefrontPublicationClock _clock;

  Future<StorefrontPublicationStatus> loadStatus(String tenantId) async {
    final normalized = tenantId.trim();
    final observedAt = _clock().toUtc();
    if (normalized.isEmpty) {
      return StorefrontPublicationStatus.readFailure(
        statusMessage: 'No hay una tienda activa para consultar.',
        observedAt: observedAt,
      );
    }
    try {
      final raw = await _invoke(statusRpc, {'p_tenant_id': normalized});
      final status = StorefrontPublicationStatus.fromJson(raw);
      return status.observedAt == null
          ? status.withObservedAt(observedAt)
          : status;
    } catch (_) {
      return StorefrontPublicationStatus.readFailure(
        statusMessage: 'No se pudo consultar la publicación de la tienda.',
        observedAt: observedAt,
      );
    }
  }

  Future<StorefrontPublicationRetryResult> retry({
    required String tenantId,
    String? failedRequestId,
  }) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) {
      return StorefrontPublicationRetryResult(
        accepted: false,
        enqueued: false,
        reason: 'missing_tenant',
        message: 'No hay una tienda activa para reintentar.',
        status: StorefrontPublicationStatus.readFailure(
          statusMessage: 'No hay una tienda activa para reintentar.',
          observedAt: _clock().toUtc(),
        ),
      );
    }
    try {
      final raw = await _invoke(retryRpc, {
        'p_tenant_id': normalizedTenant,
        'p_failed_request_id': switch (failedRequestId?.trim()) {
          final value? when value.isNotEmpty => value,
          _ => null,
        },
      });
      final json = _stringMap(raw);
      final status = StorefrontPublicationStatus.fromJson(
        json['status'] ?? raw,
      );
      final accepted = json['accepted'] == true;
      final enqueued = json['enqueued'] == true;
      final reason = _text(json['reason']);
      return StorefrontPublicationRetryResult(
        accepted: accepted,
        enqueued: enqueued,
        reason: reason,
        message: _retryMessage(reason, accepted: accepted),
        status: status.observedAt == null
            ? status.withObservedAt(_clock().toUtc())
            : status,
      );
    } on PostgrestException catch (error) {
      final reason = switch (error.code?.trim().toUpperCase()) {
        'PT429' => 'rate_limited',
        '42501' => 'forbidden',
        '22023' => 'invalid_failed_request',
        _ => 'rpc_failed',
      };
      return StorefrontPublicationRetryResult(
        accepted: false,
        enqueued: false,
        reason: reason,
        message: _retryMessage(reason, accepted: false),
        status: StorefrontPublicationStatus.readFailure(
          statusMessage: _retryMessage(reason, accepted: false),
          observedAt: _clock().toUtc(),
        ),
      );
    } catch (_) {
      return StorefrontPublicationRetryResult(
        accepted: false,
        enqueued: false,
        reason: 'transport_failed',
        message: _retryMessage('transport_failed', accepted: false),
        status: StorefrontPublicationStatus.readFailure(
          statusMessage: _retryMessage(
            'transport_failed',
            accepted: false,
          ),
          observedAt: _clock().toUtc(),
        ),
      );
    }
  }

  static Future<Object?> _defaultInvoke(
    String rpc,
    Map<String, dynamic> params,
  ) {
    return Supabase.instance.client.rpc(rpc, params: params);
  }
}

Map<String, dynamic> _stringMap(Object? raw) {
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  if (raw is List && raw.length == 1) return _stringMap(raw.single);
  return const {};
}

String _text(Object? raw) => raw?.toString().trim() ?? '';

String _retryMessage(String reason, {required bool accepted}) {
  return switch (reason) {
    'manual_retry' => 'El reintento quedó en cola.',
    'dispatch_disabled' =>
      'La automatización está preparada, pero desactivada.',
    'request_already_active' => 'Ya hay una publicación en curso.',
    'already_published' => 'La revisión editorial actual ya está publicada.',
    'no_editorial_revision' =>
      'Todavía no existe una revisión editorial para publicar.',
    'rate_limited' => 'Espera cinco minutos antes de solicitar otro reintento.',
    'forbidden' => 'Tu cuenta no tiene permiso para reintentar publicaciones.',
    'invalid_failed_request' =>
      'Ese intento fallido ya no está disponible para reintentar.',
    'missing_tenant' => 'No hay una tienda activa para reintentar.',
    'transport_failed' || 'rpc_failed' => 'No se pudo solicitar el reintento.',
    _ when accepted => 'El reintento quedó en cola.',
    _ => 'El reintento no está disponible.',
  };
}
