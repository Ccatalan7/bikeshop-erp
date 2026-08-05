import 'package:flutter/foundation.dart';

/// Closed error vocabulary for the local browser fallback.
///
/// Raw identifiers, URLs and loader exceptions never cross this boundary.
enum AIBrowserFallbackFailureCode {
  invalidRequest,
  portalUnavailable,
  catalogUnavailable,
  requestInvalidated,
  proposalUnavailable,
  temporarilyUnavailable,
}

extension AIBrowserFallbackFailureCopy on AIBrowserFallbackFailureCode {
  String get publicMessage => switch (this) {
        AIBrowserFallbackFailureCode.invalidRequest =>
          'No pude preparar esta apertura.',
        AIBrowserFallbackFailureCode.portalUnavailable =>
          'Ese portal no está disponible en el catálogo de proveedores.',
        AIBrowserFallbackFailureCode.catalogUnavailable =>
          'No pude consultar los portales de proveedores.',
        AIBrowserFallbackFailureCode.requestInvalidated =>
          'La sesión cambió antes de preparar la apertura.',
        AIBrowserFallbackFailureCode.proposalUnavailable =>
          'Esta propuesta ya no está disponible. Solicita una nueva.',
        AIBrowserFallbackFailureCode.temporarilyUnavailable =>
          'No pude preparar la apertura en este momento.',
      };
}

@immutable
class AIBrowserFallbackFailure {
  const AIBrowserFallbackFailure(this.code);

  final AIBrowserFallbackFailureCode code;

  String get publicMessage => code.publicMessage;
}

/// Result wrapper that exposes either a typed value or sanitized failure.
@immutable
class AIBrowserFallbackResult<T extends Object> {
  const AIBrowserFallbackResult.success(T value)
      : _value = value,
        _failure = null;

  const AIBrowserFallbackResult.failure(AIBrowserFallbackFailure failure)
      : _value = null,
        _failure = failure;

  final T? _value;
  final AIBrowserFallbackFailure? _failure;

  T? get value => _value;
  AIBrowserFallbackFailure? get failure => _failure;

  bool get isSuccess => _value != null;
}

/// Model/UI-visible proposal for an explicit future browser action.
///
/// The destination URL and assistant session ID are intentionally absent. A
/// caller must present this proposal to the operator and consume [proposalId]
/// through the service only after that explicit action.
@immutable
class AIBrowserProposal {
  const AIBrowserProposal({
    required this.proposalId,
    required this.supplierPortalId,
    required this.supplierName,
    required this.host,
    required this.expiresAt,
  });

  final String proposalId;

  /// Exact `supplierId` selected from the canonical browser portal catalog.
  final String supplierPortalId;
  final String supplierName;
  final String host;
  final DateTime expiresAt;

  bool isValidAt(DateTime value) => expiresAt.isAfter(value.toUtc());
}

/// Catalog-derived destination released by a successful one-time consume.
///
/// This is data only. It does not navigate, click, submit, authenticate or
/// access the embedded WebView.
@immutable
class AIBrowserDestination {
  const AIBrowserDestination({
    required this.supplierPortalId,
    required this.supplierName,
    required this.host,
    required this.uri,
  });

  final String supplierPortalId;
  final String supplierName;
  final String host;
  final Uri uri;
}
