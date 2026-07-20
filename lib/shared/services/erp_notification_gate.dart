import 'dart:collection';

/// Process-wide discovery/presentation gate for rows in `erp_notifications`.
///
/// The gate is deliberately scoped to the authenticated user and tenant. A
/// route can be rebuilt or retained without resetting the remembered rows,
/// while an identity boundary always starts from a clean baseline.
class ErpNotificationGate {
  ErpNotificationGate({int maxRememberedEvents = 4096})
      : assert(maxRememberedEvents > 0),
        _maxRememberedEvents = maxRememberedEvents;

  static final ErpNotificationGate shared = ErpNotificationGate();

  final int _maxRememberedEvents;
  final LinkedHashSet<String> _discoveredEvents = LinkedHashSet<String>();
  String? _scopeKey;

  String? get scopeKey => _scopeKey;

  void activateScope({
    required String userId,
    required String tenantId,
  }) {
    final nextScope = _normalizedScope(userId, tenantId);
    if (nextScope == _scopeKey) return;
    _scopeKey = nextScope;
    _discoveredEvents.clear();
  }

  /// Seeds rows already present when the stable shell starts. Existing unread
  /// rows remain visible in the notification center, but are not re-announced.
  void rememberBaseline(Iterable<String> eventKeys) {
    if (_scopeKey == null) return;
    for (final eventKey in eventKeys) {
      _remember(eventKey);
    }
  }

  /// Returns true only for the first discovery of a row in the active scope.
  bool claimPresentation(String eventKey) {
    if (_scopeKey == null) return false;
    return _remember(eventKey);
  }

  void clearScope() {
    _scopeKey = null;
    _discoveredEvents.clear();
  }

  bool _remember(String rawEventKey) {
    final eventKey = rawEventKey.trim();
    if (eventKey.isEmpty || _discoveredEvents.contains(eventKey)) return false;

    _discoveredEvents.add(eventKey);
    while (_discoveredEvents.length > _maxRememberedEvents) {
      _discoveredEvents.remove(_discoveredEvents.first);
    }
    return true;
  }

  String _normalizedScope(String userId, String tenantId) {
    final normalizedUserId = userId.trim();
    final normalizedTenantId = tenantId.trim();
    if (normalizedUserId.isEmpty || normalizedTenantId.isEmpty) {
      throw ArgumentError('Notification scope requires user and tenant IDs.');
    }
    return '$normalizedUserId:$normalizedTenantId';
  }
}
