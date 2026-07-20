import 'dart:collection';

/// Process-wide presentation gate for incoming chat events.
///
/// The workspace shell is long-lived while routed [MainLayout] instances are
/// kept alive. Remembering durable message IDs here guarantees that a Realtime
/// event, an FCM replay, or a workspace change cannot present the same chat
/// alert more than once in the current session.
class ChatNotificationGate {
  ChatNotificationGate({int maxRememberedEvents = 2048})
      : assert(maxRememberedEvents > 0),
        _maxRememberedEvents = maxRememberedEvents;

  static final ChatNotificationGate shared = ChatNotificationGate();

  final int _maxRememberedEvents;
  final LinkedHashSet<String> _presentedEvents = LinkedHashSet<String>();
  String? _scopeKey;

  String? get scopeKey => _scopeKey;

  /// Binds presentation memory to one authenticated tenant.
  void activateScope({
    required String userId,
    required String tenantId,
  }) {
    final normalizedUserId = userId.trim();
    final normalizedTenantId = tenantId.trim();
    if (normalizedUserId.isEmpty || normalizedTenantId.isEmpty) {
      throw ArgumentError('Chat notification scope requires user and tenant.');
    }
    final nextScope = '$normalizedUserId:$normalizedTenantId';
    if (_scopeKey == nextScope) return;
    _scopeKey = nextScope;
    reset();
  }

  bool claimPresentation(String eventKey) {
    if (_scopeKey == null) return false;
    final normalized = eventKey.trim();
    if (normalized.isEmpty || _presentedEvents.contains(normalized)) {
      return false;
    }

    _presentedEvents.add(normalized);
    while (_presentedEvents.length > _maxRememberedEvents) {
      _presentedEvents.remove(_presentedEvents.first);
    }
    return true;
  }

  void reset() => _presentedEvents.clear();

  void clearScope() {
    _scopeKey = null;
    reset();
  }
}
