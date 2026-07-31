import 'package:flutter/foundation.dart';

enum CheckoutExitPhase {
  preparingOrder,
  recoveringOrder,
  orderCreated,
}

@immutable
class CheckoutExitLease {
  const CheckoutExitLease._({
    required CheckoutExitGuard guard,
    required Object owner,
    required int generation,
  })  : _guard = guard,
        _owner = owner,
        _generation = generation;

  final CheckoutExitGuard _guard;
  final Object _owner;
  final int _generation;

  bool get isCurrent => _guard._owns(this);

  void updatePhase(CheckoutExitPhase phase) {
    _guard._updatePhase(this, phase);
  }

  void release() {
    _guard._release(this);
  }
}

/// Single authority for destructive exits while a durable checkout is active.
///
/// A generation-bound lease prevents an old CheckoutPage State from releasing
/// a newer page's lock during route replacement or delayed disposal.
class CheckoutExitGuard extends ChangeNotifier {
  Object? _owner;
  int _generation = 0;
  CheckoutExitPhase? _phase;
  Future<bool>? _confirmationInFlight;
  int? _navigationPermitGeneration;

  bool get isLocked => _owner != null;
  CheckoutExitPhase? get phase => _phase;
  bool get hasNavigationPermit =>
      isLocked && _navigationPermitGeneration == _generation;

  CheckoutExitLease acquire({
    required Object owner,
    required CheckoutExitPhase phase,
  }) {
    if (identical(_owner, owner)) {
      _phase = phase;
      return CheckoutExitLease._(
        guard: this,
        owner: owner,
        generation: _generation,
      );
    }

    _owner = owner;
    _phase = phase;
    _generation++;
    _navigationPermitGeneration = null;
    notifyListeners();
    return CheckoutExitLease._(
      guard: this,
      owner: owner,
      generation: _generation,
    );
  }

  Future<bool> requestExitAuthorization(
    Future<bool> Function(CheckoutExitPhase phase) confirm, {
    bool permitNextNavigation = false,
  }) {
    if (!isLocked) return Future.value(true);
    final existing = _confirmationInFlight;
    if (existing != null) return existing;

    final requestedGeneration = _generation;
    final requestedPhase = _phase!;
    final pending = confirm(requestedPhase).then((confirmed) {
      if (!confirmed || _generation != requestedGeneration || !isLocked) {
        return false;
      }
      if (permitNextNavigation) {
        _navigationPermitGeneration = requestedGeneration;
        notifyListeners();
      }
      return true;
    }).whenComplete(() {
      _confirmationInFlight = null;
    });
    _confirmationInFlight = pending;
    return pending;
  }

  bool consumeNavigationPermit() {
    if (_navigationPermitGeneration != _generation || !isLocked) return false;
    _navigationPermitGeneration = null;
    notifyListeners();
    return true;
  }

  void revokeNavigationPermit() {
    if (_navigationPermitGeneration == null) return;
    _navigationPermitGeneration = null;
    notifyListeners();
  }

  bool _owns(CheckoutExitLease lease) {
    return identical(_owner, lease._owner) && _generation == lease._generation;
  }

  void _updatePhase(CheckoutExitLease lease, CheckoutExitPhase phase) {
    if (!_owns(lease) || _phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  void _release(CheckoutExitLease lease) {
    if (!_owns(lease)) return;
    _owner = null;
    _phase = null;
    _navigationPermitGeneration = null;
    notifyListeners();
  }
}
