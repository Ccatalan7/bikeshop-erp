import 'dart:collection';

/// Process-wide idempotency gate for incoming-mail notifications.
///
/// Mail data is observed through more than one UI surface and more than one
/// transport (provider refresh, Realtime and FCM). Route changes rebuild
/// [MainLayout] instances, so notification ownership cannot live in a page
/// state object. This gate remembers stable provider/event identifiers and
/// keeps both discovery and presentation idempotent for the active session.
class MailNotificationGate {
  MailNotificationGate({int maxRememberedEvents = 2048})
      : assert(maxRememberedEvents > 0),
        _maxRememberedEvents = maxRememberedEvents;

  static final MailNotificationGate shared = MailNotificationGate();

  final int _maxRememberedEvents;
  final LinkedHashSet<String> _discoveredInboxEvents = LinkedHashSet<String>();
  final LinkedHashSet<String> _presentedAlerts = LinkedHashSet<String>();
  String? _scopeKey;

  String? get scopeKey => _scopeKey;

  /// Binds remembered provider/message IDs to one authenticated tenant.
  void activateScope({
    required String userId,
    required String tenantId,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedTenantId = tenantId.trim();
    if (normalizedUserId.isEmpty || normalizedTenantId.isEmpty) {
      throw ArgumentError('Mail notification scope requires user and tenant.');
    }
    final nextScope = '$normalizedUserId:$normalizedTenantId';
    if (_scopeKey == nextScope) return;
    _scopeKey = nextScope;
    reset();
  }

  /// Seeds messages already present when a refresh begins or the inbox first
  /// loads. Baseline messages must never be announced as newly arrived.
  void rememberInboxBaseline(Iterable<String> eventKeys) {
    if (_scopeKey == null) return;
    for (final eventKey in eventKeys) {
      _remember(_discoveredInboxEvents, eventKey);
    }
  }

  /// Returns true only the first time this provider message is discovered.
  bool claimInboxEvent(String eventKey) {
    if (_scopeKey == null) return false;
    return _remember(_discoveredInboxEvents, eventKey);
  }

  /// Returns true only once for a visible alert, even when several routed
  /// layouts are listening to the same broadcast stream.
  bool claimPresentation(String eventKey) {
    if (_scopeKey == null) return false;
    return _remember(_presentedAlerts, eventKey);
  }

  /// Hidden workspaces must not consume an event before the visible workspace
  /// can present it.
  bool claimPresentationForOwner({
    required bool isActiveOwner,
    required String eventKey,
  }) {
    if (!isActiveOwner) return false;
    return claimPresentation(eventKey);
  }

  /// Clears user-scoped notification memory during an explicit mail reset.
  void reset() {
    _discoveredInboxEvents.clear();
    _presentedAlerts.clear();
  }

  void clearScope() {
    _scopeKey = null;
    reset();
  }

  bool _remember(LinkedHashSet<String> target, String rawEventKey) {
    final eventKey = rawEventKey.trim();
    if (eventKey.isEmpty || target.contains(eventKey)) return false;

    target.add(eventKey);
    while (target.length > _maxRememberedEvents) {
      target.remove(target.first);
    }
    return true;
  }
}
