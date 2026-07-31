import 'package:flutter/foundation.dart';

@immutable
class ErpAuthorityScopeKey {
  const ErpAuthorityScopeKey({
    required this.userId,
    required this.tenantId,
  });

  final String userId;
  final String tenantId;

  static ErpAuthorityScopeKey? from({
    required String? userId,
    required String? tenantId,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedTenantId = tenantId?.trim();
    if (normalizedUserId == null ||
        normalizedUserId.isEmpty ||
        normalizedTenantId == null ||
        normalizedTenantId.isEmpty) {
      return null;
    }
    return ErpAuthorityScopeKey(
      userId: normalizedUserId,
      tenantId: normalizedTenantId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ErpAuthorityScopeKey &&
      other.userId == userId &&
      other.tenantId == tenantId;

  @override
  int get hashCode => Object.hash(userId, tenantId);
}

@immutable
class AuthorityCacheLease {
  const AuthorityCacheLease({
    required this.scope,
    required this.generation,
  });

  final ErpAuthorityScopeKey scope;
  final int generation;
}

enum AuthorityScopeResolution {
  unchanged,
  rebound,
  cleared,
  rejectedTenantChange;

  bool get didChange => this != AuthorityScopeResolution.unchanged;

  bool get isAccepted =>
      this == AuthorityScopeResolution.unchanged ||
      this == AuthorityScopeResolution.rebound;
}

class AuthorityCacheScope {
  ErpAuthorityScopeKey? _key;
  int _generation = 0;

  ErpAuthorityScopeKey? get key => _key;
  int get generation => _generation;

  bool bind({
    required String? userId,
    required String? tenantId,
  }) {
    final next = ErpAuthorityScopeKey.from(
      userId: userId,
      tenantId: tenantId,
    );
    if (_key == next) return false;
    _key = next;
    _generation++;
    return true;
  }

  /// Resolves a lazily discovered authority without silently crossing tenants.
  ///
  /// Explicit owners may use [bind] to install a new authority. Lazy service
  /// access must use this method: when the same authenticated user resolves to
  /// a different tenant than the currently bound tenant, the existing scope is
  /// cleared and the current operation is rejected. A subsequent coherent
  /// operation can then establish the newly resolved scope.
  AuthorityScopeResolution resolve({
    required String? userId,
    required String? tenantId,
  }) {
    final next = ErpAuthorityScopeKey.from(
      userId: userId,
      tenantId: tenantId,
    );
    final current = _key;

    if (next == null) {
      if (current == null) return AuthorityScopeResolution.unchanged;
      _key = null;
      _generation++;
      return AuthorityScopeResolution.cleared;
    }
    if (current == next) return AuthorityScopeResolution.unchanged;
    if (current != null &&
        current.userId == next.userId &&
        current.tenantId != next.tenantId) {
      _key = null;
      _generation++;
      return AuthorityScopeResolution.rejectedTenantChange;
    }

    _key = next;
    _generation++;
    return AuthorityScopeResolution.rebound;
  }

  void invalidate() {
    _generation++;
  }

  AuthorityCacheLease? capture() {
    final current = _key;
    if (current == null) return null;
    return AuthorityCacheLease(scope: current, generation: _generation);
  }

  bool owns(AuthorityCacheLease lease) =>
      lease.generation == _generation && lease.scope == _key;
}

class AuthorityScopeChangedException implements Exception {
  const AuthorityScopeChangedException();

  @override
  String toString() => 'ERP authority scope changed during load';
}

/// Owns one in-flight cache load for one exact Auth user and tenant generation.
///
/// Detaching does not cancel the underlying request. It lets the next authority
/// start immediately; the old request can complete, but cannot publish or clear
/// the replacement request.
class AuthorityScopedLoad<T> {
  AuthorityScopedLoad(this._scope);

  final AuthorityCacheScope _scope;
  Future<T>? _inFlight;
  AuthorityCacheLease? _inFlightLease;
  int _loadGeneration = 0;

  void detach() {
    _loadGeneration++;
    _inFlight = null;
    _inFlightLease = null;
  }

  Future<T> run({
    required Future<T> Function(AuthorityCacheLease lease) load,
    required void Function(T value, AuthorityCacheLease lease) publish,
  }) {
    final lease = _scope.capture();
    if (lease == null) {
      return Future<T>.error(const AuthorityScopeChangedException());
    }

    final pending = _inFlight;
    final pendingLease = _inFlightLease;
    if (pending != null &&
        pendingLease != null &&
        pendingLease.generation == lease.generation &&
        pendingLease.scope == lease.scope) {
      return pending;
    }

    final loadGeneration = _loadGeneration;
    late final Future<T> request;
    request = load(lease).then((value) {
      if (!_scope.owns(lease) || loadGeneration != _loadGeneration) {
        throw const AuthorityScopeChangedException();
      }
      publish(value, lease);
      return value;
    }).whenComplete(() {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightLease = null;
      }
    });
    _inFlight = request;
    _inFlightLease = lease;
    return request;
  }
}
