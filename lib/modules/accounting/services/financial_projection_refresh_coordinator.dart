import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/services/tenant_service.dart';
import 'financial_projection_realtime_transport.dart';

/// Canonical financial projections affected by a durable business mutation.
///
/// The dashboard and reports remain read-only projections. Writers publish a
/// post-commit hint through [FinancialProjectionRefreshCoordinator] instead of
/// importing or reaching into a dashboard widget.
enum FinancialProjectionChangeKind {
  tenantScope,
  revalidation,
  salesInvoice,
  salesPayment,
  purchaseInvoice,
  purchasePayment,
  expense,
  expensePayment,
  payroll,
  journalEntry,
  account,
}

enum FinancialProjectionChangeOrigin {
  localCommit,
  remoteRealtime,
  lifecycleRevalidation,
}

@immutable
class FinancialProjectionChange {
  const FinancialProjectionChange({
    required this.kind,
    required this.origin,
    this.entityId,
    this.tenantId,
    this.eventId,
  });

  final FinancialProjectionChangeKind kind;
  final FinancialProjectionChangeOrigin origin;
  final String? entityId;
  final String? tenantId;
  final String? eventId;

  /// Stable command/event identity, never merely the mutable row identity.
  ///
  /// Two real commits may update the same entity within milliseconds, so an
  /// entity id is not sufficient evidence that an event is a duplicate.
  String? get deduplicationKey {
    final identity = eventId;
    if (identity == null || identity.isEmpty) return null;
    return '${kind.name}:$identity';
  }
}

@immutable
class FinancialProjectionRefreshSignal {
  const FinancialProjectionRefreshSignal({
    required this.revision,
    required this.changes,
  });

  final int revision;
  final Set<FinancialProjectionChangeKind> changes;
}

/// Process-scoped invalidation owner for accounting/dashboard read models.
///
/// Confirmed local commands call [recordCommitted] immediately after their
/// database acknowledgement. Cross-device changes arrive through one
/// tenant-private Broadcast channel carrying only invalidation metadata.
/// Closely related rows emitted by one command are coalesced so a single sale
/// does not trigger an RPC storm.
class FinancialProjectionRefreshCoordinator {
  FinancialProjectionRefreshCoordinator({
    this.coalesceWindow = const Duration(milliseconds: 120),
    this.duplicateWindow = const Duration(milliseconds: 400),
    FinancialProjectionRealtimeTransport? realtimeTransport,
  }) : _realtimeTransport = realtimeTransport;

  static final FinancialProjectionRefreshCoordinator fallback =
      FinancialProjectionRefreshCoordinator();

  final Duration coalesceWindow;
  final Duration duplicateWindow;
  final FinancialProjectionRealtimeTransport? _realtimeTransport;

  final StreamController<FinancialProjectionRefreshSignal> _signals =
      StreamController<FinancialProjectionRefreshSignal>.broadcast();
  final Set<FinancialProjectionChangeKind> _pendingKinds = {};
  final Map<String, DateTime> _recentChanges = {};

  Timer? _coalesceTimer;
  FinancialProjectionRealtimeSubscription? _realtimeSubscription;
  int? _realtimeSubscriptionStartingGeneration;
  String? _tenantId;
  int _tenantResolutionGeneration = 0;
  int _realtimeSubscriptionGeneration = 0;
  int _revision = 0;
  bool _applicationActive = true;
  bool _disposed = false;

  Stream<FinancialProjectionRefreshSignal> get signals => _signals.stream;
  int get revision => _revision;
  String? get tenantId => _tenantId;

  /// Revalidates process-scoped projections after the OS may have suspended
  /// the Realtime socket. The SDK reconnects the socket; this signal closes the
  /// event gap without reloading the current page or route.
  void recordLifecycleResume() {
    final tenantId = _tenantId;
    if (_disposed || tenantId == null) return;
    recordCommitted(
      FinancialProjectionChange(
        kind: FinancialProjectionChangeKind.revalidation,
        origin: FinancialProjectionChangeOrigin.lifecycleRevalidation,
        tenantId: tenantId,
      ),
    );
  }

  /// Prevents background socket callbacks from starting report queries while
  /// the OS has paused the UI. Returning to the foreground produces exactly
  /// one bounded revalidation, including when no Dashboard widget was mounted
  /// during the suspension.
  void setApplicationActive(bool isActive) {
    if (_disposed || _applicationActive == isActive) return;
    _applicationActive = isActive;
    if (!isActive) return;
    final tenantId = _tenantId;
    recordLifecycleResume();
    if (tenantId != null &&
        _realtimeTransport != null &&
        _realtimeSubscription == null &&
        _realtimeSubscriptionStartingGeneration !=
            _realtimeSubscriptionGeneration) {
      unawaited(_retryMissingRealtimeSubscription(tenantId));
    }
  }

  Future<void> _retryMissingRealtimeSubscription(String tenantId) async {
    // A foreground retry only repairs the transport for the already-resolved
    // scope. It must not supersede an authoritative tenant resolution that may
    // already be in flight (for example, an account/tenant switch).
    final resolutionGeneration = _tenantResolutionGeneration;
    try {
      await _synchronizeTenant(
        tenantId,
        resolutionGeneration: resolutionGeneration,
        revalidateOnSubscribe: false,
      );
    } catch (error, stackTrace) {
      if (_disposed || resolutionGeneration != _tenantResolutionGeneration) {
        return;
      }
      debugPrint(
        'Financial projection Realtime resume retry failed: $error\n'
        '$stackTrace',
      );
    }
  }

  void recordCommitted(FinancialProjectionChange change) {
    if (_disposed) return;
    if (_tenantId != null &&
        change.tenantId != null &&
        change.tenantId != _tenantId) {
      return;
    }

    final deduplicationKey = change.deduplicationKey;
    if (deduplicationKey != null) {
      final now = DateTime.now();
      _recentChanges.removeWhere(
        (_, recordedAt) => now.difference(recordedAt) > duplicateWindow,
      );
      final lastSeen = _recentChanges[deduplicationKey];
      if (lastSeen != null && now.difference(lastSeen) <= duplicateWindow) {
        return;
      }
      _recentChanges[deduplicationKey] = now;
    }

    if (_pendingKinds.isEmpty) {
      // Cache users can see the dirty revision immediately, before the
      // coalesced signal is delivered.
      _revision++;
    }
    _pendingKinds.add(change.kind);
    _coalesceTimer?.cancel();
    _coalesceTimer = Timer(coalesceWindow, _flush);
  }

  Future<void> synchronizeTenantFrom(TenantService tenantService) async {
    await synchronizeTenantFromResolver(tenantService.getTenantId);
  }

  @visibleForTesting
  Future<void> synchronizeTenantFromResolver(
    Future<String?> Function() resolveTenantId,
  ) async {
    final resolutionGeneration = ++_tenantResolutionGeneration;
    try {
      final tenantId = await resolveTenantId();
      if (_disposed || resolutionGeneration != _tenantResolutionGeneration) {
        return;
      }
      await _synchronizeTenant(
        tenantId,
        resolutionGeneration: resolutionGeneration,
      );
    } catch (error, stackTrace) {
      if (_disposed || resolutionGeneration != _tenantResolutionGeneration) {
        return;
      }
      debugPrint(
        'Financial projection tenant synchronization failed: $error\n'
        '$stackTrace',
      );
    }
  }

  Future<void> synchronizeTenant(String? tenantId) async {
    final resolutionGeneration = ++_tenantResolutionGeneration;
    await _synchronizeTenant(
      tenantId,
      resolutionGeneration: resolutionGeneration,
    );
  }

  Future<void> _synchronizeTenant(
    String? tenantId, {
    required int resolutionGeneration,
    bool revalidateOnSubscribe = true,
  }) async {
    if (_disposed || resolutionGeneration != _tenantResolutionGeneration) {
      return;
    }
    if (_tenantId == tenantId &&
        (tenantId == null ||
            _realtimeTransport == null ||
            _realtimeSubscription != null)) {
      return;
    }

    final scopeChanged = _tenantId != tenantId;
    final subscriptionGeneration = ++_realtimeSubscriptionGeneration;
    _realtimeSubscriptionStartingGeneration = null;
    _tenantId = tenantId;
    if (scopeChanged) {
      _recentChanges.clear();
      _pendingKinds.clear();
      _coalesceTimer?.cancel();
      _coalesceTimer = null;
    }

    final previousSubscription = _realtimeSubscription;
    _realtimeSubscription = null;

    if (scopeChanged) {
      // Clear the visible/cache scope before any network-bound channel
      // teardown. A stalled removeChannel must never leave prior-tenant
      // financial data on screen.
      _revision++;
      _signals.add(
        FinancialProjectionRefreshSignal(
          revision: _revision,
          changes: const {FinancialProjectionChangeKind.tenantScope},
        ),
      );
    }

    if (previousSubscription != null) {
      await _cancelRealtimeSubscription(
        previousSubscription,
        context: 'teardown',
      );
    }
    if (!_isCurrentRealtimeScope(tenantId, subscriptionGeneration)) return;

    final realtimeTransport = _realtimeTransport;
    if (tenantId == null || realtimeTransport == null) return;

    _realtimeSubscriptionStartingGeneration = subscriptionGeneration;
    var suppressNextSubscribedRevalidation = !revalidateOnSubscribe;
    try {
      final subscription = await realtimeTransport.subscribe(
        tenantId: tenantId,
        onEvent: (event) => _handleRealtimeEvent(
          event,
          tenantId: tenantId,
          subscriptionGeneration: subscriptionGeneration,
        ),
        onStatus: (status, error) {
          final shouldRevalidate =
              status != FinancialProjectionRealtimeStatus.subscribed ||
                  !suppressNextSubscribedRevalidation;
          if (status == FinancialProjectionRealtimeStatus.subscribed) {
            suppressNextSubscribedRevalidation = false;
          }
          _handleRealtimeStatus(
            status,
            error,
            tenantId: tenantId,
            subscriptionGeneration: subscriptionGeneration,
            revalidateOnSubscribe: shouldRevalidate,
          );
        },
      );
      if (!_isCurrentRealtimeScope(tenantId, subscriptionGeneration)) {
        await _cancelRealtimeSubscription(
          subscription,
          context: 'stale subscription',
        );
        return;
      }
      _realtimeSubscription = subscription;
    } catch (error, stackTrace) {
      if (!_isCurrentRealtimeScope(tenantId, subscriptionGeneration)) return;
      debugPrint(
        'Financial projection Realtime subscription failed: $error\n'
        '$stackTrace',
      );
    } finally {
      if (_realtimeSubscriptionStartingGeneration == subscriptionGeneration) {
        _realtimeSubscriptionStartingGeneration = null;
      }
    }
  }

  Future<void> _cancelRealtimeSubscription(
    FinancialProjectionRealtimeSubscription subscription, {
    required String context,
  }) async {
    try {
      await subscription.cancel();
    } catch (error, stackTrace) {
      debugPrint(
        'Financial projection Realtime $context failed: $error\n'
        '$stackTrace',
      );
    }
  }

  bool _isCurrentRealtimeScope(
    String? tenantId,
    int subscriptionGeneration,
  ) {
    return !_disposed &&
        _tenantId == tenantId &&
        _realtimeSubscriptionGeneration == subscriptionGeneration;
  }

  void _handleRealtimeEvent(
    Map<String, dynamic> envelope, {
    required String tenantId,
    required int subscriptionGeneration,
  }) {
    if (!_isCurrentRealtimeScope(tenantId, subscriptionGeneration)) return;
    if (!_applicationActive) {
      return;
    }

    final rawPayload = envelope['payload'];
    if (rawPayload is! Map) return;
    final payload = Map<String, dynamic>.from(rawPayload);
    final rawKind = payload['kind']?.toString();
    final kind = _parseChangeKind(rawKind);
    if (kind == null ||
        kind == FinancialProjectionChangeKind.tenantScope ||
        kind == FinancialProjectionChangeKind.revalidation) {
      return;
    }

    recordCommitted(
      FinancialProjectionChange(
        kind: kind,
        origin: FinancialProjectionChangeOrigin.remoteRealtime,
        entityId: payload['entity_id']?.toString(),
        tenantId: tenantId,
        eventId: payload['event_id']?.toString(),
      ),
    );
  }

  FinancialProjectionChangeKind? _parseChangeKind(String? rawKind) {
    if (rawKind == null || rawKind.isEmpty) return null;
    for (final kind in FinancialProjectionChangeKind.values) {
      if (kind.name == rawKind) return kind;
    }
    return null;
  }

  void _handleRealtimeStatus(
    FinancialProjectionRealtimeStatus status,
    Object? error, {
    required String tenantId,
    required int subscriptionGeneration,
    required bool revalidateOnSubscribe,
  }) {
    if (!_isCurrentRealtimeScope(tenantId, subscriptionGeneration)) return;
    switch (status) {
      case FinancialProjectionRealtimeStatus.subscribed:
        // Close the race between the last projection query and channel join,
        // and do the same after an SDK-managed reconnect.
        if (!_applicationActive || !revalidateOnSubscribe) {
          break;
        }
        recordCommitted(
          FinancialProjectionChange(
            kind: FinancialProjectionChangeKind.revalidation,
            origin: FinancialProjectionChangeOrigin.remoteRealtime,
            tenantId: tenantId,
          ),
        );
        break;
      case FinancialProjectionRealtimeStatus.degraded:
        debugPrint('Financial projection Realtime degraded: $error');
        break;
      case FinancialProjectionRealtimeStatus.closed:
        _realtimeSubscription = null;
        break;
    }
  }

  void _flush() {
    _coalesceTimer = null;
    if (_disposed || _pendingKinds.isEmpty) return;
    final kinds = Set<FinancialProjectionChangeKind>.unmodifiable(
      _pendingKinds,
    );
    _pendingKinds.clear();
    _signals.add(
      FinancialProjectionRefreshSignal(
        revision: _revision,
        changes: kinds,
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tenantResolutionGeneration++;
    _realtimeSubscriptionGeneration++;
    _realtimeSubscriptionStartingGeneration = null;
    _coalesceTimer?.cancel();
    _coalesceTimer = null;
    final realtimeSubscription = _realtimeSubscription;
    _realtimeSubscription = null;
    if (realtimeSubscription != null) {
      unawaited(
        _cancelRealtimeSubscription(
          realtimeSubscription,
          context: 'dispose',
        ),
      );
    }
    unawaited(_signals.close());
  }
}
