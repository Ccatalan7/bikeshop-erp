import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/conversation.dart';
import '../models/conversation_context_hint.dart';
import '../models/message.dart';
import '../services/conversation_context_hint_cache.dart';
import '../services/meta_messaging_service.dart';
import '../services/messaging_service.dart';
import '../utils/message_receipt_projection.dart';
import '../utils/message_receipt_refresh_coalescer.dart';
import '../utils/message_timeline_merge.dart';
import '../../../shared/services/notification_service.dart';

class ConversationDraft {
  final String body;
  final String title;
  final String subtitle;

  const ConversationDraft({
    required this.body,
    required this.title,
    required this.subtitle,
  });
}

class _IncomingConversationPreview {
  final String content;
  final String messageType;
  final String? direction;
  final String? externalStatus;
  final DateTime createdAt;
  final int? messageSequence;
  final DateTime receivedAt;
  final int unreadCount;

  const _IncomingConversationPreview({
    required this.content,
    required this.messageType,
    required this.direction,
    required this.externalStatus,
    required this.createdAt,
    required this.messageSequence,
    required this.receivedAt,
    required this.unreadCount,
  });
}

class _OutgoingConversationPreview {
  final String clientMessageId;
  final String content;
  final String messageType;
  final Map<String, dynamic> metadata;
  final String? direction;
  final String? externalStatus;
  final DateTime createdAt;
  final Conversation previousConversation;

  const _OutgoingConversationPreview({
    required this.clientMessageId,
    required this.content,
    required this.messageType,
    required this.metadata,
    required this.direction,
    required this.externalStatus,
    required this.createdAt,
    required this.previousConversation,
  });
}

class ChatProvider extends ChangeNotifier {
  final MessagingService _service = MessagingService();
  MetaMessagingService? _metaMessagingService;
  final ConversationContextHintCache _contextHintCache =
      ConversationContextHintCache();
  final UserManagementService? _userService;
  final TenantService _tenantService;
  late final MessageReceiptRefreshCoalescer _messageReceiptRefreshCoalescer;

  // State
  List<Conversation> _conversations = [];
  List<Message> _activeMessages = [];
  final Map<String, List<Message>> _messageCacheByConversation = {};
  final List<String> _messageCacheOrder = [];
  final Map<Object, String> _conversationViewByOwner = {};
  final List<Object> _visibleConversationOwnerOrder = [];
  final Set<String> _prefetchedConversationIds = {};
  final Map<String, int> _messageTimelineRevisionByConversation = {};
  final Map<String, bool> _hasMoreMessagesByConversation = {};
  final Map<String, bool> _loadingOlderMessagesByConversation = {};
  final Map<String, String> _olderMessagesErrorByConversation = {};
  final Map<String, String> _messageStreamErrorByConversation = {};
  final Map<String, int> _historyLoadEpochByConversation = {};
  final Map<String, int> _historyCursorByConversation = {};
  final Map<String, Message> _optimisticMessages = {};
  final Map<String, Map<String, dynamic>> _userCache = {}; // id -> user data
  final Map<String, ConversationDraft> _conversationDrafts = {};
  final Map<String, MetaConversationTransport> _metaConversationTransports = {};
  final Set<String> _metaOutboundReceiptSnapshots = {};
  final Set<String> _metaConversationTransportSnapshots = {};
  final Map<String, String> _metaConversationStateErrors = {};
  final Map<String, Future<void>> _metaConversationStateRefreshes = {};
  final Set<String> _pendingMetaConversationStateRefreshes = {};
  final Map<String, int> _conversationOpeningUnreadCounts = {};
  final Map<String, DateTime> _localReadAtByConversation = {};
  final Map<String, int> _localReadMessageSequenceByConversation = {};
  final Map<String, DateTime> _lastReadSyncByConversation = {};
  final Map<String, String> _lastReadSyncMessageIdByConversation = {};
  final Map<String, _IncomingConversationPreview>
      _incomingConversationPreviews = {};
  final Map<String, _OutgoingConversationPreview>
      _outgoingConversationPreviews = {};
  final Set<String> _recentIncomingNotificationKeys = {};
  final List<String> _recentIncomingNotificationKeyOrder = [];
  bool _isLoading = false;
  bool _isLoadingConversations = false;
  bool _hasPendingConversationRefresh = false;
  bool _pendingConversationRefreshNeedsContextHints = false;
  String? _pendingConversationRefreshType;
  Completer<void>? _activeConversationLoadCompleter;
  Completer<void>? _pendingConversationRefreshCompleter;
  Future<void>? _contextHintCacheLoadFuture;
  Future<void>? _contextHintsRefreshFuture;
  final Map<String, ConversationContextHint> _cachedContextHints = {};
  String? _contextHintCacheTenantId;
  String? _contextHintCacheUserId;
  String? _activeConversationId;

  // Subscriptions
  StreamSubscription? _messagesSubscription;
  RealtimeChannel? _conversationsSubscription;
  StreamSubscription? _notificationSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  Timer? _conversationsRefreshTimer;
  Timer? _conversationsFollowUpRefreshTimer;
  Timer? _messagesRetryTimer;
  Timer? _contextHintCachePersistTimer;
  int _messagesRetryAttempt = 0;
  int _sessionEpoch = 0;
  int _sessionResolutionEpoch = 0;
  String? _sessionUserId;
  String? _sessionTenantId;
  bool _hasObservedSession = false;
  bool _sessionReady = false;
  bool _disposed = false;
  bool _isApplicationForeground = true;
  bool _awaitingForegroundFrame = false;
  int _applicationForegroundEpoch = 0;
  static const int _maxMessageStreamRetryAttempts = 4;
  static const int _recentMessageCacheLimit =
      MessagingService.recentMessageStreamLimit;
  static const String _missingHistoryCursorMessage =
      'No pudimos ubicar el inicio de este historial.';

  // Getters
  List<Conversation> get conversations => _conversations;
  List<Message> get activeMessages => _mergedActiveMessages;
  bool get isLoading => _isLoading;
  String? get activeConversationId => _activeConversationId;
  bool get isApplicationForeground => _isApplicationForeground;

  bool hasMetaReplyWindowSnapshot(String conversationId) =>
      _metaConversationTransportSnapshots.contains(conversationId);

  bool hasMetaOutboundReceiptSnapshot(String conversationId) =>
      _metaOutboundReceiptSnapshots.contains(conversationId);

  bool hasCompleteMetaConversationStateSnapshot(String conversationId) =>
      hasMetaOutboundReceiptSnapshot(conversationId) &&
      hasMetaReplyWindowSnapshot(conversationId);

  String? metaConversationStateError(String conversationId) =>
      _metaConversationStateErrors[conversationId];

  DateTime? metaReplyWindowExpiresAt(String conversationId) =>
      _metaConversationTransports[conversationId]?.replyWindowExpiresAt;

  bool canReplyToMetaConversation(String conversationId) {
    final transport = _metaConversationTransports[conversationId];
    return hasCompleteMetaConversationStateSnapshot(conversationId) &&
        transport?.canReply == true &&
        MetaMessagingService.isReplyWindowOpenFromExpiry(
          transport?.replyWindowExpiresAt,
        );
  }

  bool isMetaConversationStateLoading(String conversationId) =>
      _metaConversationStateRefreshes.containsKey(conversationId);

  bool hasMoreMessages(String conversationId) {
    final known = _hasMoreMessagesByConversation[conversationId];
    if (known != null) return known;
    return (_messageCacheByConversation[conversationId]?.isNotEmpty ?? false);
  }

  bool isLoadingOlderMessages(String conversationId) =>
      _loadingOlderMessagesByConversation[conversationId] ?? false;

  String? olderMessagesErrorForConversation(String conversationId) =>
      _olderMessagesErrorByConversation[conversationId];

  String? messageStreamErrorForConversation(String conversationId) =>
      _messageStreamErrorByConversation[conversationId];

  List<Message> messagesForConversation(String conversationId) {
    final cached = _messageCacheByConversation[conversationId] ?? const [];
    final merged = <Message>[...cached];
    for (final message in _optimisticMessages.values) {
      if (message.conversationId != conversationId) continue;
      if (hasMatchingServerMessage(
        optimistic: message,
        serverMessages: merged,
      )) {
        continue;
      }
      merged.add(message);
    }
    merged.sort(compareMessageTimelineOrder);
    return merged;
  }

  bool isConversationLoading(String conversationId) {
    return _activeConversationId == conversationId && _isLoading;
  }

  bool isConversationVisible(String conversationId) {
    if (!_isApplicationForeground || _awaitingForegroundFrame) return false;
    if (_visibleConversationOwnerOrder.isEmpty) return false;
    final foregroundOwner = _visibleConversationOwnerOrder.last;
    return _conversationViewByOwner[foregroundOwner] == conversationId;
  }

  List<Message> get _mergedActiveMessages {
    final activeId = _activeConversationId;
    return activeId == null ? const [] : messagesForConversation(activeId);
  }

  bool _isWhatsAppStatusMessage(Message message) {
    final metadata = message.metadata;
    final provider = metadata['external_provider']?.toString() ??
        metadata['provider']?.toString();
    final channel = metadata['channel']?.toString();
    final externalMessageId = metadata['external_message_id']?.toString();

    return provider == 'whatsapp' ||
        channel == 'whatsapp' ||
        (externalMessageId != null && externalMessageId.startsWith('wamid.'));
  }

  String? _whatsAppStatusForDebug(Message message) {
    if (message.metadata['pending'] == true) {
      return 'pending';
    }

    return message.metadata['external_status']?.toString() ??
        message.metadata['whatsapp_status']?.toString();
  }

  String _shortDebugId(String? value) {
    if (value == null || value.isEmpty) return '-';
    if (value.length <= 18) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 6)}';
  }

  String _debugDuration(DateTime startedAt) {
    return '${DateTime.now().difference(startedAt).inMilliseconds}ms';
  }

  void _debugInboxSync(
    String event, {
    String? conversationId,
    String? messageId,
    DateTime? startedAt,
    Map<String, Object?> details = const {},
  }) {
    if (!kDebugMode) return;

    final parts = <String>[
      event,
      if (conversationId != null)
        'conversation=${_shortDebugId(conversationId)}',
      if (messageId != null) 'message=${_shortDebugId(messageId)}',
      if (startedAt != null) 'elapsed=${_debugDuration(startedAt)}',
      ...details.entries.map((entry) => '${entry.key}=${entry.value}'),
    ];

    debugPrint('[InboxSync] ${parts.join(' ')}');
  }

  String? _textValue(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  DateTime? _dateValue(dynamic value) {
    final text = _textValue(value);
    if (text == null) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _debugLogWhatsAppStatusChanges(List<Message> nextMessages) {
    if (!kDebugMode) return;

    final previousMessages = <Message>[
      ..._activeMessages,
      ..._optimisticMessages.values,
    ];
    if (previousMessages.isEmpty) return;

    final previousById = <String, Message>{
      for (final message in previousMessages) message.id: message,
    };
    final previousByExternalId = <String, Message>{};
    final previousByClientId = <String, Message>{};

    for (final message in previousMessages) {
      final externalMessageId =
          message.metadata['external_message_id']?.toString();
      if (externalMessageId != null && externalMessageId.isNotEmpty) {
        previousByExternalId[externalMessageId] = message;
      }

      final clientMessageId = message.metadata['client_message_id']?.toString();
      if (clientMessageId != null && clientMessageId.isNotEmpty) {
        previousByClientId[clientMessageId] = message;
      }
    }

    final candidates = nextMessages.where(_isWhatsAppStatusMessage).toList();
    final visibleCandidates = candidates.length > 30
        ? candidates.skip(candidates.length - 30)
        : candidates;

    for (final message in visibleCandidates) {
      final nextStatus = _whatsAppStatusForDebug(message);
      if (nextStatus == null || nextStatus.isEmpty) continue;

      final externalMessageId =
          message.metadata['external_message_id']?.toString();
      final clientMessageId = message.metadata['client_message_id']?.toString();
      final previous = previousById[message.id] ??
          (externalMessageId != null
              ? previousByExternalId[externalMessageId]
              : null) ??
          (clientMessageId != null
              ? previousByClientId[clientMessageId]
              : null);
      final previousStatus =
          previous == null ? null : _whatsAppStatusForDebug(previous);

      if (previousStatus == nextStatus) continue;

      debugPrint(
        '🔎 [WhatsAppStatus] message=${_shortDebugId(message.id)} external=${_shortDebugId(externalMessageId)} client=${_shortDebugId(clientMessageId)} status=${previousStatus ?? 'none'}->$nextStatus created=${message.createdAt.toIso8601String()}',
      );
    }
  }

  void _pruneConfirmedOptimisticMessages(List<Message> serverMessages) {
    _optimisticMessages.removeWhere(
      (_, optimistic) => hasMatchingServerMessage(
        optimistic: optimistic,
        serverMessages: serverMessages,
      ),
    );
  }

  /// Total unread messages across all conversations + pending requests
  int get totalUnreadCount => _conversations.fold(0, (sum, c) {
        // If it's a pending support chat, count it as at least 1 (even if unreadCount is 0 because user isn't participant)
        if (c.type == 'support' && c.status == 'pending') {
          return sum + (c.unreadCount > 0 ? c.unreadCount : 1);
        }
        return sum + c.unreadCount;
      });

  ChatProvider([
    this._userService,
    TenantService? tenantService,
  ]) : _tenantService = tenantService ?? TenantService() {
    _messageReceiptRefreshCoalescer = MessageReceiptRefreshCoalescer(
      onRefresh: _refreshMessageReceipts,
    );
    _authStateSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      final mustClearBeforeResolution =
          state.event == AuthChangeEvent.signedOut ||
              state.session?.user.id != _sessionUserId;
      unawaited(
        synchronizeSessionScope(
          clearBeforeResolution: mustClearBeforeResolution,
        ),
      );
    });
    unawaited(synchronizeSessionScope());
  }

  /// Synchronizes all in-memory messaging state with the authenticated user and
  /// tenant. The provider deliberately survives route changes, so a session
  /// boundary must invalidate every cache and every asynchronous callback.
  Future<void> synchronizeSessionScope({
    bool clearBeforeResolution = false,
  }) async {
    if (_disposed) return;

    final resolutionEpoch = ++_sessionResolutionEpoch;
    final userId = _service.currentUserId;
    final userChanged = !_hasObservedSession || _sessionUserId != userId;

    if (userChanged || clearBeforeResolution) {
      _invalidateSessionState(nextUserId: userId);
    }
    _hasObservedSession = true;

    if (userId == null || userId.isEmpty) return;

    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (_disposed ||
        resolutionEpoch != _sessionResolutionEpoch ||
        _service.currentUserId != userId) {
      return;
    }

    final tenantChanged = _sessionReady && _sessionTenantId != tenantId;
    if (tenantChanged) {
      _invalidateSessionState(nextUserId: userId);
    }
    if (_sessionReady &&
        _sessionUserId == userId &&
        _sessionTenantId == tenantId) {
      return;
    }

    _sessionUserId = userId;
    _sessionTenantId = tenantId;
    _sessionReady = true;
    final epoch = _sessionEpoch;
    _contextHintCacheLoadFuture = _loadContextHintCache(
      epoch: epoch,
      userId: userId,
      tenantId: tenantId,
    );
    unawaited(_loadUserCache(epoch));
    _initConversationsListener(epoch);
  }

  bool _isCurrentSession(int epoch) {
    return !_disposed && _sessionReady && epoch == _sessionEpoch;
  }

  void _invalidateSessionState({required String? nextUserId}) {
    _sessionEpoch += 1;
    _sessionReady = false;
    _sessionUserId = nextUserId;
    _sessionTenantId = null;

    _conversationsRefreshTimer?.cancel();
    _conversationsFollowUpRefreshTimer?.cancel();
    _messageReceiptRefreshCoalescer.clear();
    _messagesRetryTimer?.cancel();
    _contextHintCachePersistTimer?.cancel();
    unawaited(_messagesSubscription?.cancel() ?? Future<void>.value());
    unawaited(_notificationSubscription?.cancel() ?? Future<void>.value());
    final conversationsSubscription = _conversationsSubscription;
    if (conversationsSubscription != null) {
      unawaited(conversationsSubscription.unsubscribe());
    }
    _messagesSubscription = null;
    _notificationSubscription = null;
    _conversationsSubscription = null;

    final activeCompleter = _activeConversationLoadCompleter;
    if (activeCompleter != null && !activeCompleter.isCompleted) {
      activeCompleter.complete();
    }
    final pendingCompleter = _pendingConversationRefreshCompleter;
    if (pendingCompleter != null && !pendingCompleter.isCompleted) {
      pendingCompleter.complete();
    }

    _conversations = [];
    _activeMessages = [];
    _messageCacheByConversation.clear();
    _messageCacheOrder.clear();
    _messageTimelineRevisionByConversation.clear();
    _hasMoreMessagesByConversation.clear();
    _loadingOlderMessagesByConversation.clear();
    _olderMessagesErrorByConversation.clear();
    _messageStreamErrorByConversation.clear();
    _historyLoadEpochByConversation.clear();
    _historyCursorByConversation.clear();
    _conversationViewByOwner.clear();
    _visibleConversationOwnerOrder.clear();
    _prefetchedConversationIds.clear();
    _optimisticMessages.clear();
    _userCache.clear();
    _conversationDrafts.clear();
    _metaConversationTransports.clear();
    _metaOutboundReceiptSnapshots.clear();
    _metaConversationTransportSnapshots.clear();
    _metaConversationStateErrors.clear();
    _metaConversationStateRefreshes.clear();
    _pendingMetaConversationStateRefreshes.clear();
    _conversationOpeningUnreadCounts.clear();
    _localReadAtByConversation.clear();
    _localReadMessageSequenceByConversation.clear();
    _lastReadSyncByConversation.clear();
    _lastReadSyncMessageIdByConversation.clear();
    _incomingConversationPreviews.clear();
    _outgoingConversationPreviews.clear();
    _recentIncomingNotificationKeys.clear();
    _recentIncomingNotificationKeyOrder.clear();
    _cachedContextHints.clear();
    _contextHintCacheTenantId = null;
    _contextHintCacheUserId = null;
    _activeConversationId = null;
    _isLoading = false;
    _isLoadingConversations = false;
    _hasPendingConversationRefresh = false;
    _pendingConversationRefreshNeedsContextHints = false;
    _pendingConversationRefreshType = null;
    _activeConversationLoadCompleter = null;
    _pendingConversationRefreshCompleter = null;
    _contextHintCacheLoadFuture = null;
    _contextHintsRefreshFuture = null;
    _messagesRetryAttempt = 0;
    notifyListeners();
  }

  Future<void> _loadContextHintCache({
    required int epoch,
    required String userId,
    required String? tenantId,
  }) async {
    if (tenantId == null || tenantId.isEmpty || !_isCurrentSession(epoch)) {
      return;
    }

    _contextHintCacheUserId = userId;
    _contextHintCacheTenantId = tenantId;
    final cached = await _contextHintCache.read(
      tenantId: tenantId,
      userId: userId,
    );
    if (!_isCurrentSession(epoch)) return;
    _cachedContextHints
      ..clear()
      ..addAll(cached);

    if (_conversations.isNotEmpty && cached.isNotEmpty) {
      _conversations = _mergeCachedContextHints(_conversations);
      notifyListeners();
    }
  }

  void _scheduleContextHintCachePersist() {
    final tenantId = _contextHintCacheTenantId;
    final userId = _contextHintCacheUserId;
    if (tenantId == null || userId == null) return;
    final epoch = _sessionEpoch;

    _contextHintCachePersistTimer?.cancel();
    _contextHintCachePersistTimer = Timer(
      const Duration(milliseconds: 180),
      () {
        if (_isCurrentSession(epoch)) {
          unawaited(_persistContextHintCache(tenantId, userId));
        }
      },
    );
  }

  Future<void> _persistContextHintCache(
    String tenantId,
    String userId,
  ) async {
    try {
      await _contextHintCache.write(
        tenantId: tenantId,
        userId: userId,
        hints: Map.unmodifiable(_cachedContextHints),
      );
    } catch (error) {
      debugPrint('⚠️ Could not persist messaging context hints: $error');
    }
  }

  /// Load user cache for resolving names
  Future<void> _loadUserCache(int epoch) async {
    if (_userService == null) return;
    try {
      // Check if we are an employee/admin before trying to fetch sensitive tenant users
      // This helper check prevents 400 errors for customers
      final users = await _userService.getTenantUsers();
      if (!_isCurrentSession(epoch)) return;
      for (var u in users) {
        _userCache[u['id']] = u;
      }
      notifyListeners();
    } catch (e) {
      // Silently fail for customers or non-admins to avoid console spam [400 Bad Request]
      // This is expected for the Customer Portal.
      // debugPrint('Info: Could not load full user cache (normal for customers): $e');
    }
  }

  /// Initialize listener for conversation list updates
  void _initConversationsListener(int epoch) {
    if (!_isCurrentSession(epoch)) return;
    // Keep the first inbox pass focused on badges and previews. Context chips
    // are useful, but they should not block message delivery feedback.
    loadConversations(refreshContextHints: false);

    _conversationsSubscription = _service.subscribeToConversationsUpdates(
      () {
        if (!_isCurrentSession(epoch)) return;
        _scheduleConversationRefresh(const Duration(milliseconds: 80));
      },
      onMessageReceiptUpdate: (update) {
        if (!_isCurrentSession(epoch)) return;
        _messageReceiptRefreshCoalescer.schedule(
          conversationId: update.conversationId,
          messageId: update.messageId,
        );
      },
    );

    // Also listen to NotificationService for realtime alerts (triggers badge update)
    _notificationSubscription = NotificationService().onMessageReceived.listen(
      (message) {
        if (!_isCurrentSession(epoch)) return;
        applyIncomingNotification(message);
      },
    );
  }

  void applyIncomingNotification(RemoteMessage message) {
    final data = message.data;
    if (_isNonChatNotification(data)) return;

    final conversationId = _textValue(data['conversation_id']) ??
        _textValue(data['chat_id']) ??
        _conversationIdFromRoute(_textValue(data['route']));

    if (conversationId == null) {
      _scheduleConversationRefresh(const Duration(milliseconds: 80));
      _scheduleConversationFollowUpRefresh();
      return;
    }

    final content = _textValue(data['content']) ??
        _textValue(data['body']) ??
        message.notification?.body ??
        '';
    final createdAt = _dateValue(data['created_at']) ?? DateTime.now();
    final notificationKey = _incomingNotificationKey(
      message: message,
      data: data,
      conversationId: conversationId,
      content: content,
      createdAt: createdAt,
    );

    if (!_rememberIncomingNotificationKey(notificationKey)) {
      return;
    }

    final updated = _applyIncomingMessagePreview(
      conversationId: conversationId,
      content: content,
      messageType: _textValue(data['type']) ?? 'text',
      senderId: _textValue(data['sender_id']),
      direction: _textValue(data['message_direction']),
      externalStatus: _textValue(data['external_status']),
      createdAt: createdAt,
      messageSequence: _intValue(data['message_sequence']),
    );

    if (updated) {
      _scheduleConversationRefresh(const Duration(milliseconds: 900));
    } else {
      _scheduleConversationRefresh(const Duration(milliseconds: 80));
    }
    _scheduleConversationFollowUpRefresh();
  }

  bool _isNonChatNotification(Map<String, dynamic> data) {
    final notificationType = _textValue(data['notification_type']);
    final type = _textValue(data['type']);
    final route = _textValue(data['route']);
    return notificationType == 'mail' || type == 'mail' || route == '/mail';
  }

  String? _conversationIdFromRoute(String? route) {
    if (route == null || route.isEmpty) return null;
    final uri = Uri.tryParse(route);
    return uri?.queryParameters['conversation'];
  }

  String _incomingNotificationKey({
    required RemoteMessage message,
    required Map<String, dynamic> data,
    required String conversationId,
    required String content,
    required DateTime createdAt,
  }) {
    final explicitId = _textValue(data['id']) ??
        _textValue(data['message_id']) ??
        message.messageId;
    if (explicitId != null && explicitId.isNotEmpty) return explicitId;
    return [
      conversationId,
      _textValue(data['sender_id']) ?? '',
      createdAt.toIso8601String(),
      content,
    ].join('|');
  }

  bool _rememberIncomingNotificationKey(String key) {
    if (!_recentIncomingNotificationKeys.add(key)) return false;
    _recentIncomingNotificationKeyOrder.add(key);
    while (_recentIncomingNotificationKeyOrder.length > 80) {
      final oldest = _recentIncomingNotificationKeyOrder.removeAt(0);
      _recentIncomingNotificationKeys.remove(oldest);
    }
    return true;
  }

  bool _applyIncomingMessagePreview({
    required String conversationId,
    required String content,
    required String messageType,
    required String? senderId,
    required String? direction,
    required String? externalStatus,
    required DateTime createdAt,
    required int? messageSequence,
  }) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) return false;

    final old = _conversations[index];
    final isCurrentUserSender =
        senderId != null && senderId == _service.currentUserId;
    final isIncoming = messageType != 'system' &&
        direction != 'outbound' &&
        !isCurrentUserSender;
    final shouldIncrementUnread =
        isIncoming && !isConversationVisible(conversationId);
    final existingPreview = _incomingConversationPreviews[conversationId];
    final nextUnreadCount = shouldIncrementUnread
        ? _maxInt(
            old.unreadCount + 1,
            (existingPreview?.unreadCount ?? 0) + 1,
          )
        : old.unreadCount;
    final nextDirection = direction ??
        (isCurrentUserSender
            ? 'outbound'
            : old.isSupport
                ? 'inbound'
                : null);

    if (shouldIncrementUnread) {
      _localReadAtByConversation.remove(conversationId);
      _localReadMessageSequenceByConversation.remove(conversationId);
      _lastReadSyncByConversation.remove(conversationId);
      _lastReadSyncMessageIdByConversation.remove(conversationId);
      _outgoingConversationPreviews.remove(conversationId);
      _incomingConversationPreviews[conversationId] =
          _IncomingConversationPreview(
        content: content,
        messageType: messageType,
        direction: nextDirection,
        externalStatus: externalStatus,
        createdAt: createdAt,
        messageSequence: messageSequence,
        receivedAt: DateTime.now(),
        unreadCount: nextUnreadCount,
      );
    } else if (isConversationVisible(conversationId) || isCurrentUserSender) {
      _incomingConversationPreviews.remove(conversationId);
    }

    _conversations[index] = Conversation(
      id: old.id,
      type: old.type,
      channel: old.channel,
      isGroup: old.isGroup,
      counterpartyType: old.counterpartyType,
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      updatedAt: createdAt,
      lastMessageAt: createdAt,
      staffLastReadAt: old.staffLastReadAt,
      staffLastReadMessageSequence: old.staffLastReadMessageSequence,
      lastMessageId: old.lastMessageId,
      lastMessageSequence: messageSequence ?? old.lastMessageSequence,
      lastMessageContent: content.isNotEmpty ? content : old.lastMessageContent,
      lastMessageType: messageType,
      lastMessageMetadata: old.lastMessageMetadata,
      lastMessageIsMine: isCurrentUserSender,
      lastMessageDirection: nextDirection,
      lastMessageExternalStatus:
          externalStatus ?? old.lastMessageExternalStatus,
      unreadCount: nextUnreadCount,
      participantIds: old.participantIds,
      createdBy: old.createdBy,
      creatorName: old.creatorName,
      contextHint: old.contextHint,
    );

    _sortConversationsByRecentActivity();
    notifyListeners();
    return true;
  }

  void _sortConversationsByRecentActivity() {
    _conversations.sort((a, b) {
      final aDate = a.lastMessageAt ?? a.updatedAt;
      final bDate = b.lastMessageAt ?? b.updatedAt;
      return bDate.compareTo(aDate);
    });
  }

  void _scheduleConversationRefresh([
    Duration delay = const Duration(milliseconds: 120),
    bool refreshContextHints = false,
  ]) {
    final epoch = _sessionEpoch;
    _conversationsRefreshTimer?.cancel();
    _conversationsRefreshTimer = Timer(
      delay,
      () {
        if (_isCurrentSession(epoch)) {
          unawaited(
            loadConversations(refreshContextHints: refreshContextHints),
          );
        }
      },
    );
  }

  void _scheduleConversationFollowUpRefresh() {
    final epoch = _sessionEpoch;
    _conversationsFollowUpRefreshTimer?.cancel();
    _conversationsFollowUpRefreshTimer = Timer(
      const Duration(milliseconds: 700),
      () {
        if (_isCurrentSession(epoch)) {
          unawaited(loadConversations(refreshContextHints: false));
        }
      },
    );
  }

  Future<void> _refreshMessageReceipts(
    MessageReceiptRefreshBatch batch,
  ) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch) || batch.isEmpty) return;

    final conversationIds = batch.keys.toSet();
    final messageIds = batch.values.expand((ids) => ids).toSet();
    final startedAt = DateTime.now();
    _debugInboxSync(
      'messageReceipts:start',
      details: {
        'conversations': conversationIds.length,
        'messages': messageIds.length,
      },
    );

    try {
      final results = await Future.wait<dynamic>([
        _service.getMessagesByIds(messageIds),
        _service.getLatestMessagesForConversations(conversationIds),
      ]);
      if (!_isCurrentSession(operationEpoch)) return;

      final refreshedMessages = results[0] as Map<String, Message>;
      final latestMessages = results[1] as Map<String, Message>;
      var changed = false;

      for (final conversationId in conversationIds) {
        final cached = _messageCacheByConversation[conversationId];
        if (cached == null) continue;
        final receiptRows = refreshedMessages.values.where(
          (message) => message.conversationId == conversationId,
        );
        if (receiptRows.isEmpty) continue;
        _debugLogWhatsAppStatusChanges(receiptRows.toList(growable: false));
        final preserveFullHistory = _activeConversationId == conversationId;
        _cacheMessages(
          conversationId,
          mergeMessageTimelinesMonotonically(
            olderSnapshot: cached,
            currentTimeline: receiptRows,
            limit: preserveFullHistory ? null : _recentMessageCacheLimit,
          ),
          preserveFullHistory: preserveFullHistory,
        );
        changed = true;
      }

      if (refreshedMessages.isNotEmpty) {
        _pruneConfirmedOptimisticMessages(refreshedMessages.values.toList());
      }

      for (final entry in latestMessages.entries) {
        final conversationId = entry.key;
        final latest = entry.value;
        final index = _conversations.indexWhere(
          (conversation) => conversation.id == conversationId,
        );
        if (index == -1) continue;

        final old = _conversations[index];
        _conversations[index] = projectLatestMessageReceipt(
          old,
          latest,
        );

        final preview = _outgoingConversationPreviews[conversationId];
        final latestClientMessageId =
            latest.metadata['client_message_id']?.toString();
        if (preview != null &&
            latestClientMessageId == preview.clientMessageId) {
          _outgoingConversationPreviews.remove(conversationId);
        }
        changed = true;
      }

      if (changed) notifyListeners();
      _debugInboxSync(
        'messageReceipts:applied',
        startedAt: startedAt,
        details: {
          'receiptRows': refreshedMessages.length,
          'latestRows': latestMessages.length,
          'changed': changed,
        },
      );
    } catch (error) {
      if (!_isCurrentSession(operationEpoch)) return;
      _debugInboxSync(
        'messageReceipts:error',
        startedAt: startedAt,
        details: {'error': error},
      );
      // A later receipt or opening the conversation will read the canonical
      // server row. Do not replace this focused path with a high-volume reload.
    }
  }

  /// Get display title for a conversation
  String getChatTitle(Conversation c) {
    // For support chats, use customer name
    if (c.type == 'support') {
      final hintedSupplier = c.contextHint?.supplierLabel;
      if (c.isSupplierConversation &&
          hintedSupplier != null &&
          hintedSupplier.isNotEmpty) {
        return hintedSupplier;
      }
      if (c.creatorName != null && c.creatorName!.isNotEmpty) {
        return c.creatorName ?? 'Cliente';
      }
      final hintedCustomer = c.contextHint?.customerLabel;
      if (hintedCustomer != null && hintedCustomer.isNotEmpty) {
        return hintedCustomer;
      }
      if (c.title != null && c.title!.trim().isNotEmpty) {
        return c.title!.trim();
      }
      return 'Cliente';
    }

    if (c.title != null && c.title!.isNotEmpty) return c.title ?? '';

    // Internal chat - find other participant
    final myId = _service.currentUserId;
    final otherId = c.participantIds.firstWhere(
      (id) => id != myId,
      orElse: () => '',
    );

    if (otherId.isEmpty) return 'Chat Personal';

    final user = _userCache[otherId];
    if (user != null) {
      final name = user['employee_name'] as String?;
      if (name != null && name.isNotEmpty) return name;
      final email = user['email'] as String? ?? '';
      return email.split('@').first;
    }

    return 'Usuario Desconocido';
  }

  void setConversationDraft(
    String conversationId,
    String draft, {
    String title = 'Mensaje preparado',
    String subtitle = 'Nada se ha enviado todavía.',
  }) {
    if (_disposed) return;
    final trimmed = draft.trim();
    if (trimmed.isEmpty) return;
    _conversationDrafts[conversationId] = ConversationDraft(
      body: trimmed,
      title: title,
      subtitle: subtitle,
    );
    notifyListeners();
  }

  ConversationDraft? getConversationDraft(String conversationId) {
    return _conversationDrafts[conversationId];
  }

  int takeOpeningUnreadCount(String conversationId, {int fallback = 0}) {
    return _conversationOpeningUnreadCounts.remove(conversationId) ?? fallback;
  }

  String? takeConversationDraft(String conversationId) {
    final draft = _conversationDrafts.remove(conversationId);
    if (draft != null) notifyListeners();
    return draft?.body;
  }

  void clearConversationDraft(String conversationId) {
    if (_disposed) return;
    if (_conversationDrafts.remove(conversationId) != null) {
      notifyListeners();
    }
  }

  /// Load conversation previews and unread state. A concurrent caller now
  /// waits for the coalesced follow-up read instead of returning prematurely.
  Future<void> loadConversations({
    String? type,
    bool refreshContextHints = true,
  }) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;

    // Don't set global loading here to avoid screen flickering on updates.
    if (_isLoadingConversations) {
      if (!_hasPendingConversationRefresh) {
        _pendingConversationRefreshType = type;
      } else if (_pendingConversationRefreshType != type) {
        _pendingConversationRefreshType = null;
      }
      _pendingConversationRefreshNeedsContextHints |= refreshContextHints;
      final pendingCompleter =
          _pendingConversationRefreshCompleter ??= Completer<void>();
      _debugInboxSync(
        'loadConversations:queued',
        details: {
          'type': type ?? 'all',
          'refreshContextHints': refreshContextHints,
          'pendingNeedsContextHints':
              _pendingConversationRefreshNeedsContextHints,
          'outgoingPreviews': _outgoingConversationPreviews.length,
          'incomingPreviews': _incomingConversationPreviews.length,
        },
      );
      _hasPendingConversationRefresh = true;
      return pendingCompleter.future;
    }

    final startedAt = DateTime.now();
    _debugInboxSync(
      'loadConversations:start',
      details: {
        'type': type ?? 'all',
        'refreshContextHints': refreshContextHints,
        'active': _shortDebugId(_activeConversationId),
        'outgoingPreviews': _outgoingConversationPreviews.length,
        'incomingPreviews': _incomingConversationPreviews.length,
      },
    );

    _isLoadingConversations = true;
    final activeLoadCompleter = Completer<void>();
    _activeConversationLoadCompleter = activeLoadCompleter;
    try {
      final conversationsFuture = _service.getConversations(
        type: type,
        includeContextHints: refreshContextHints,
      );
      await _contextHintCacheLoadFuture;
      final newConversations = await conversationsFuture;
      if (!_isCurrentSession(operationEpoch)) return;
      if (refreshContextHints) {
        _replaceCachedContextHints(newConversations);
      }
      _conversations = _applyOutgoingConversationPreviews(
        _applyIncomingConversationPreviews(
          _applyLocalReadOverrides(
            _mergeCachedContextHints(newConversations),
          ),
        ),
      );
      _debugInboxSync(
        'loadConversations:applied',
        startedAt: startedAt,
        details: {
          'rows': _conversations.length,
          'refreshContextHints': refreshContextHints,
          'outgoingPreviews': _outgoingConversationPreviews.length,
          'incomingPreviews': _incomingConversationPreviews.length,
        },
      );
      notifyListeners();

      unawaited(_prefetchRecentConversations(operationEpoch));

      if (_userCache.isEmpty) await _loadUserCache(operationEpoch);
    } catch (e) {
      if (!_isCurrentSession(operationEpoch)) return;
      _debugInboxSync(
        'loadConversations:error',
        startedAt: startedAt,
        details: {'error': e},
      );
      debugPrint('❌ Error loading conversations: $e');
    } finally {
      if (!activeLoadCompleter.isCompleted) activeLoadCompleter.complete();
      if (_isCurrentSession(operationEpoch)) {
        _isLoadingConversations = false;
        if (identical(_activeConversationLoadCompleter, activeLoadCompleter)) {
          _activeConversationLoadCompleter = null;
        }

        if (_hasPendingConversationRefresh) {
          _hasPendingConversationRefresh = false;
          final pendingType = _pendingConversationRefreshType;
          _pendingConversationRefreshType = null;
          final pendingNeedsContextHints =
              _pendingConversationRefreshNeedsContextHints;
          _pendingConversationRefreshNeedsContextHints = false;
          final pendingCompleter = _pendingConversationRefreshCompleter;
          _pendingConversationRefreshCompleter = null;
          _debugInboxSync(
            'loadConversations:runQueued',
            details: {
              'type': pendingType ?? 'all',
              'refreshContextHints': pendingNeedsContextHints,
            },
          );
          unawaited(
            Future<void>.delayed(const Duration(milliseconds: 80), () async {
              try {
                if (_isCurrentSession(operationEpoch)) {
                  await loadConversations(
                    type: pendingType,
                    refreshContextHints: pendingNeedsContextHints,
                  );
                }
              } finally {
                if (pendingCompleter != null && !pendingCompleter.isCompleted) {
                  pendingCompleter.complete();
                }
              }
            }),
          );
        }
      }
    }
  }

  Future<void> _prefetchRecentConversations(int operationEpoch) async {
    if (!_isCurrentSession(operationEpoch)) return;
    final candidates = _conversations
        .where((conversation) =>
            !_messageCacheByConversation.containsKey(conversation.id) &&
            !_prefetchedConversationIds.contains(conversation.id))
        .take(3)
        .toList(growable: false);

    for (final conversation in candidates) {
      final revisionAtRequest =
          _messageTimelineRevisionByConversation[conversation.id] ?? 0;
      _prefetchedConversationIds.add(conversation.id);
      try {
        final messages = await _service.getRecentMessages(conversation.id);
        if (!_isCurrentSession(operationEpoch)) return;
        final revisionNow =
            _messageTimelineRevisionByConversation[conversation.id] ?? 0;
        if (messages.isNotEmpty &&
            revisionNow == revisionAtRequest &&
            _activeConversationId != conversation.id &&
            !isConversationVisible(conversation.id)) {
          final merged = mergeMessageTimelinesMonotonically(
            olderSnapshot: messages,
            currentTimeline:
                _messageCacheByConversation[conversation.id] ?? const [],
          );
          _cacheMessages(conversation.id, merged);
          notifyListeners();
        }
      } catch (error) {
        if (!_isCurrentSession(operationEpoch)) return;
        _prefetchedConversationIds.remove(conversation.id);
        debugPrint(
          '⚠️ Could not preload conversation ${conversation.id}: $error',
        );
      }
    }
  }

  /// Refresh only the derived job, bike, invoice, and supplier context.
  /// Repeated callers share one authoritative refresh.
  Future<void> refreshConversationContextHints() {
    final activeRefresh = _contextHintsRefreshFuture;
    if (activeRefresh != null) return activeRefresh;

    final refresh = _refreshConversationContextHints();
    _contextHintsRefreshFuture = refresh;
    unawaited(
      refresh.whenComplete(() {
        if (identical(_contextHintsRefreshFuture, refresh)) {
          _contextHintsRefreshFuture = null;
        }
      }),
    );
    return refresh;
  }

  Future<void> _refreshConversationContextHints() async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    final activeConversationLoad = _activeConversationLoadCompleter?.future;
    if (activeConversationLoad != null) await activeConversationLoad;
    if (!_isCurrentSession(operationEpoch)) return;
    if (_conversations.isEmpty) {
      await loadConversations(refreshContextHints: false);
    }
    if (!_isCurrentSession(operationEpoch)) return;

    final snapshot = List<Conversation>.of(_conversations);
    if (snapshot.isEmpty) return;
    final snapshotIds = snapshot.map((conversation) => conversation.id).toSet();
    final startedAt = DateTime.now();
    _debugInboxSync(
      'refreshContextHints:start',
      details: {'rows': snapshot.length},
    );

    try {
      final hints = await _service.getConversationContextHints(snapshot);
      if (!_isCurrentSession(operationEpoch)) return;
      var changed = false;
      _conversations = _conversations.map((conversation) {
        if (!snapshotIds.contains(conversation.id)) return conversation;
        final hint = hints[conversation.id];
        // A missing row can also mean one of the best-effort enrichment reads
        // failed. Keep the last truthful hint until the server returns an
        // explicit replacement (including a customer-only hint).
        if (hint == null) return conversation;
        if (mapEquals(
          conversation.contextHint?.toJson(),
          hint.toJson(),
        )) {
          return conversation;
        }
        changed = true;
        return _withContextHint(conversation, hint);
      }).toList(growable: false);

      for (final entry in hints.entries) {
        _cachedContextHints[entry.key] = entry.value;
      }
      _scheduleContextHintCachePersist();
      if (changed) notifyListeners();
      _debugInboxSync(
        'refreshContextHints:applied',
        startedAt: startedAt,
        details: {'rows': hints.length, 'changed': changed},
      );
    } catch (error) {
      if (!_isCurrentSession(operationEpoch)) return;
      _debugInboxSync(
        'refreshContextHints:error',
        startedAt: startedAt,
        details: {'error': error},
      );
      debugPrint('❌ Error refreshing conversation context hints: $error');
    }
  }

  void _replaceCachedContextHints(List<Conversation> conversations) {
    final conversationIds =
        conversations.map((conversation) => conversation.id).toSet();
    _cachedContextHints.removeWhere(
      (conversationId, _) => !conversationIds.contains(conversationId),
    );
    for (final conversation in conversations) {
      final hint = conversation.contextHint;
      if (hint != null) {
        _cachedContextHints[conversation.id] = hint;
      }
    }
    _scheduleContextHintCachePersist();
  }

  List<Conversation> _mergeCachedContextHints(
    List<Conversation> conversations,
  ) {
    final currentById = {
      for (final conversation in _conversations) conversation.id: conversation,
    };

    return conversations.map((conversation) {
      if (conversation.contextHint != null) return conversation;

      final current = currentById[conversation.id];
      final cachedHint =
          current?.contextHint ?? _cachedContextHints[conversation.id];
      if (cachedHint == null) return conversation;

      return _withContextHint(
        conversation,
        cachedHint,
        creatorName: conversation.creatorName ?? current?.creatorName,
      );
    }).toList(growable: false);
  }

  Conversation _withContextHint(
    Conversation conversation,
    ConversationContextHint? contextHint, {
    String? creatorName,
  }) {
    return Conversation(
      id: conversation.id,
      type: conversation.type,
      channel: conversation.channel,
      isGroup: conversation.isGroup,
      counterpartyType: conversation.counterpartyType,
      status: conversation.status,
      title: conversation.title,
      contextType: conversation.contextType,
      contextId: conversation.contextId,
      updatedAt: conversation.updatedAt,
      lastMessageAt: conversation.lastMessageAt,
      staffLastReadAt: conversation.staffLastReadAt,
      staffLastReadMessageSequence: conversation.staffLastReadMessageSequence,
      lastMessageId: conversation.lastMessageId,
      lastMessageSequence: conversation.lastMessageSequence,
      lastMessageContent: conversation.lastMessageContent,
      lastMessageType: conversation.lastMessageType,
      lastMessageMetadata: conversation.lastMessageMetadata,
      lastMessageIsMine: conversation.lastMessageIsMine,
      lastMessageDirection: conversation.lastMessageDirection,
      lastMessageExternalStatus: conversation.lastMessageExternalStatus,
      unreadCount: conversation.unreadCount,
      participantIds: conversation.participantIds,
      createdBy: conversation.createdBy,
      creatorName: creatorName ?? conversation.creatorName,
      contextHint: contextHint,
    );
  }

  /// Suspends visible-thread ownership while the application is not in the
  /// foreground. A resume waits for a rendered frame before reusing the last
  /// host report, so background Realtime events can never be acknowledged as
  /// read merely because an IndexedStack branch remains mounted.
  void setApplicationForeground(bool isForeground) {
    if (_disposed || _isApplicationForeground == isForeground) return;

    _isApplicationForeground = isForeground;
    final foregroundEpoch = ++_applicationForegroundEpoch;
    if (!isForeground) {
      _awaitingForegroundFrame = false;
      notifyListeners();
      return;
    }

    _awaitingForegroundFrame = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed ||
          !_isApplicationForeground ||
          foregroundEpoch != _applicationForegroundEpoch) {
        return;
      }

      _awaitingForegroundFrame = false;
      notifyListeners();
      final conversationId = _activeConversationId;
      if (conversationId != null && isConversationVisible(conversationId)) {
        unawaited(refreshMetaConversationState(conversationId));
        _markActiveConversationReadIfNeeded(
          conversationId,
          _messageCacheByConversation[conversationId] ?? const [],
        );
      }
    });
  }

  /// Registers a concrete timeline host. Only hosts reported as visible may
  /// clear unread state or suppress an incoming notification. This is crucial
  /// because workspace routers remain mounted inside an IndexedStack.
  void updateConversationView({
    required Object owner,
    required String conversationId,
    required bool visible,
  }) {
    final previousConversation = _conversationViewByOwner[owner];
    _conversationViewByOwner[owner] = conversationId;
    if (visible) {
      if (_isApplicationForeground) {
        _awaitingForegroundFrame = false;
      }
      _visibleConversationOwnerOrder
        ..remove(owner)
        ..add(owner);
      if (_activeConversationId != conversationId ||
          _messagesSubscription == null) {
        setActiveConversation(conversationId);
      } else {
        _markActiveConversationReadIfNeeded(
          conversationId,
          _messageCacheByConversation[conversationId] ?? const [],
        );
      }
      return;
    }

    final wasForeground = _visibleConversationOwnerOrder.isNotEmpty &&
        identical(_visibleConversationOwnerOrder.last, owner);
    _visibleConversationOwnerOrder.remove(owner);
    if (wasForeground && _visibleConversationOwnerOrder.isNotEmpty) {
      final restoredOwner = _visibleConversationOwnerOrder.last;
      final restoredConversation = _conversationViewByOwner[restoredOwner];
      if (restoredConversation != null) {
        setActiveConversation(restoredConversation);
      }
    }
    if (previousConversation != null &&
        previousConversation != conversationId &&
        !isConversationVisible(previousConversation)) {
      _trimMessageCache();
    }
  }

  void detachConversationView(Object owner) {
    final conversationId = _conversationViewByOwner.remove(owner);
    final wasForeground = _visibleConversationOwnerOrder.isNotEmpty &&
        identical(_visibleConversationOwnerOrder.last, owner);
    _visibleConversationOwnerOrder.remove(owner);
    if (wasForeground && _visibleConversationOwnerOrder.isNotEmpty) {
      final restoredOwner = _visibleConversationOwnerOrder.last;
      final restoredConversation = _conversationViewByOwner[restoredOwner];
      if (restoredConversation != null) {
        setActiveConversation(restoredConversation);
      }
    }
    if (conversationId != null &&
        _activeConversationId == conversationId &&
        !isConversationVisible(conversationId)) {
      _messagesSubscription?.cancel();
      _messagesSubscription = null;
      _isLoading = false;
      _compactConversationHistory(conversationId);
    }
    _trimMessageCache();
  }

  void _cacheMessages(
    String conversationId,
    List<Message> messages, {
    bool preserveFullHistory = false,
  }) {
    final bounded =
        !preserveFullHistory && messages.length > _recentMessageCacheLimit
            ? messages.sublist(messages.length - _recentMessageCacheLimit)
            : List<Message>.of(messages);
    _messageCacheByConversation[conversationId] = bounded;
    _messageTimelineRevisionByConversation[conversationId] =
        (_messageTimelineRevisionByConversation[conversationId] ?? 0) + 1;
    _messageCacheOrder
      ..remove(conversationId)
      ..add(conversationId);
    if (_activeConversationId == conversationId) {
      _activeMessages = bounded;
    }
    _trimMessageCache();
  }

  void _compactConversationHistory(String conversationId) {
    final cached = _messageCacheByConversation[conversationId];
    final truncated =
        cached != null && cached.length > _recentMessageCacheLimit;
    if (truncated) {
      _messageCacheByConversation[conversationId] = cached.sublist(
        cached.length - _recentMessageCacheLimit,
      );
    }
    if (_activeConversationId == conversationId) {
      _activeMessages =
          _messageCacheByConversation[conversationId] ?? const <Message>[];
    }
    if (truncated) {
      _hasMoreMessagesByConversation.remove(conversationId);
      _historyCursorByConversation.remove(conversationId);
    }
    _loadingOlderMessagesByConversation.remove(conversationId);
    _olderMessagesErrorByConversation.remove(conversationId);
    _historyLoadEpochByConversation[conversationId] =
        (_historyLoadEpochByConversation[conversationId] ?? 0) + 1;
  }

  void _trimMessageCache() {
    const maxCachedConversations = 12;
    while (_messageCacheOrder.length > maxCachedConversations) {
      final candidate = _messageCacheOrder.first;
      if (candidate == _activeConversationId ||
          isConversationVisible(candidate)) {
        _messageCacheOrder
          ..removeAt(0)
          ..add(candidate);
        if (_messageCacheOrder.every(
          (id) => id == _activeConversationId || isConversationVisible(id),
        )) {
          break;
        }
        continue;
      }
      _messageCacheOrder.removeAt(0);
      _messageCacheByConversation.remove(candidate);
      _messageTimelineRevisionByConversation.remove(candidate);
      _prefetchedConversationIds.remove(candidate);
      _hasMoreMessagesByConversation.remove(candidate);
      _loadingOlderMessagesByConversation.remove(candidate);
      _olderMessagesErrorByConversation.remove(candidate);
      _messageStreamErrorByConversation.remove(candidate);
      _historyLoadEpochByConversation.remove(candidate);
      _historyCursorByConversation.remove(candidate);
    }
  }

  /// Open a conversation and subscribe to updates
  void setActiveConversation(String conversationId) {
    if (_activeConversationId == conversationId) {
      unawaited(refreshMetaConversationState(conversationId));
      if (_messagesSubscription == null) {
        _isLoading = _activeMessages.isEmpty;
        notifyListeners();
        _subscribeToActiveMessages(conversationId);
      }
      return;
    }

    final previousConversationId = _activeConversationId;
    if (previousConversationId != null) {
      _compactConversationHistory(previousConversationId);
    }

    _activeConversationId = conversationId;
    _activeMessages =
        _messageCacheByConversation[conversationId] ?? <Message>[];
    _isLoading = _activeMessages.isEmpty;
    notifyListeners();

    // Keep the unread badge until the visible message stream confirms the chat
    // is actually open. This prevents stale selections in compact panels from
    // marking coworker/customer replies as read too early.
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final old = _conversations[index];
      if (old.unreadCount > 0) {
        _conversationOpeningUnreadCounts[conversationId] = old.unreadCount;
      } else {
        _conversationOpeningUnreadCounts.remove(conversationId);
      }
    }

    // 1. Unsubscribe from old message stream
    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messagesSubscription?.cancel();

    // 2. Subscribe to new message stream
    _subscribeToActiveMessages(conversationId);
    unawaited(refreshMetaConversationState(conversationId));
  }

  MetaMessagingService get _resolvedMetaMessagingService =>
      _metaMessagingService ??= MetaMessagingService();

  /// Rehydrates durable, unresolved Meta sends and the authoritative reply
  /// window when a conversation opens or the application resumes.
  Future<void> refreshMetaConversationState(String conversationId) {
    final existing = _metaConversationStateRefreshes[conversationId];
    if (existing != null) {
      _pendingMetaConversationStateRefreshes.add(conversationId);
      return existing;
    }

    final conversation = _conversations
        .where((candidate) => candidate.id == conversationId)
        .firstOrNull;
    if (!_sessionReady || conversation?.isMetaMessaging != true) {
      return Future<void>.value();
    }

    late final Future<void> refresh;
    refresh = _loadMetaConversationState(
      conversation: conversation!,
      operationEpoch: _sessionEpoch,
    );
    _metaConversationStateRefreshes[conversationId] = refresh;
    unawaited(
      refresh.whenComplete(() {
        if (identical(
          _metaConversationStateRefreshes[conversationId],
          refresh,
        )) {
          _metaConversationStateRefreshes.remove(conversationId);
          if (!_disposed) notifyListeners();
          if (_pendingMetaConversationStateRefreshes.remove(conversationId) &&
              !_disposed) {
            unawaited(refreshMetaConversationState(conversationId));
          }
        }
      }),
    );
    return refresh;
  }

  Future<void> _loadMetaConversationState({
    required Conversation conversation,
    required int operationEpoch,
  }) async {
    List<MetaOutboundSendReceipt>? receipts;
    MetaConversationTransport? transport;
    var receiptsFailed = false;
    var transportFailed = false;

    try {
      receipts = await _resolvedMetaMessagingService.listOutboundSendReceipts(
        conversationId: conversation.id,
      );
    } catch (error) {
      receiptsFailed = true;
      debugPrint(
        '[MetaRecovery] receipt_read_failed errorType=${error.runtimeType}',
      );
    }

    try {
      final loadedTransport =
          await _resolvedMetaMessagingService.getConversationTransport(
        conversationId: conversation.id,
      );
      if (loadedTransport.provider != conversation.channel) {
        throw const FormatException('Meta transport provider mismatch');
      }
      transport = loadedTransport;
    } catch (error) {
      transportFailed = true;
      debugPrint(
        '[MetaRecovery] window_read_failed errorType=${error.runtimeType}',
      );
    }

    if (!_isCurrentSession(operationEpoch)) return;

    var changed = false;
    if (receipts != null) {
      changed = _reconcileMetaOutboundReceipts(
            conversation: conversation,
            receipts: receipts,
          ) ||
          changed;
      changed = _metaOutboundReceiptSnapshots.add(conversation.id) || changed;
    } else {
      changed =
          _metaOutboundReceiptSnapshots.remove(conversation.id) || changed;
    }
    if (transport != null) {
      final previous = _metaConversationTransports[conversation.id];
      _metaConversationTransports[conversation.id] = transport;
      changed = previous?.provider != transport.provider ||
          previous?.replyWindowExpiresAt != transport.replyWindowExpiresAt ||
          previous?.canReply != transport.canReply ||
          changed;
      changed =
          _metaConversationTransportSnapshots.add(conversation.id) || changed;
    } else {
      changed = _metaConversationTransportSnapshots.remove(conversation.id) ||
          changed;
    }

    final nextError = switch ((receiptsFailed, transportFailed)) {
      (true, true) =>
        'No se pudieron verificar los envíos pendientes ni la ventana de Meta.',
      (true, false) =>
        'No se pudieron verificar los envíos pendientes de Meta.',
      (false, true) => 'No se pudo verificar la ventana de respuesta de Meta.',
      (false, false) => null,
    };
    final previousError = _metaConversationStateErrors[conversation.id];
    if (nextError == null) {
      changed = _metaConversationStateErrors.remove(conversation.id) != null ||
          changed;
    } else if (previousError != nextError) {
      _metaConversationStateErrors[conversation.id] = nextError;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  bool _reconcileMetaOutboundReceipts({
    required Conversation conversation,
    required List<MetaOutboundSendReceipt> receipts,
  }) {
    final unresolved = receipts
        .where((receipt) => receipt.shouldRecover)
        .toList(growable: false);
    final unresolvedClientIds =
        unresolved.map((receipt) => receipt.clientMessageId).toSet();
    var changed = false;

    _optimisticMessages.removeWhere((_, message) {
      final shouldRemove = message.conversationId == conversation.id &&
          message.metadata['recovered_outbound_attempt'] == true &&
          !unresolvedClientIds.contains(
            message.metadata['client_message_id']?.toString(),
          );
      changed = changed || shouldRemove;
      return shouldRemove;
    });

    for (final receipt in unresolved) {
      MapEntry<String, Message>? existingEntry;
      for (final entry in _optimisticMessages.entries) {
        if (entry.value.conversationId == conversation.id &&
            entry.value.metadata['client_message_id']?.toString() ==
                receipt.clientMessageId) {
          existingEntry = entry;
          break;
        }
      }

      final recovered = buildRecoveredMetaAttemptMessage(
        receipt: receipt,
        channel: conversation.channel,
        currentUserId: _service.currentUserId,
        optimisticMessageId: existingEntry?.key,
        existingMetadata: existingEntry?.value.metadata ?? const {},
      );
      _optimisticMessages[recovered.id] = recovered;

      _optimisticMessages.removeWhere((id, message) {
        if (id == recovered.id || message.conversationId != conversation.id) {
          return false;
        }
        return message.metadata['client_message_id']?.toString() ==
            receipt.clientMessageId;
      });
      changed = true;
    }

    final serverMessages =
        _messageCacheByConversation[conversation.id] ?? const <Message>[];
    final optimisticCountBeforePrune = _optimisticMessages.length;
    _pruneConfirmedOptimisticMessages(serverMessages);
    return changed || _optimisticMessages.length != optimisticCountBeforePrune;
  }

  void clearActiveConversation({
    String? conversationId,
    bool notify = true,
  }) {
    if (_activeConversationId == null) return;
    if (conversationId != null && _activeConversationId != conversationId) {
      return;
    }
    final activeId = _activeConversationId;
    if (activeId != null && isConversationVisible(activeId)) return;

    if (activeId != null) {
      _compactConversationHistory(activeId);
    }

    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messagesSubscription?.cancel();
    _messagesSubscription = null;

    _activeConversationId = null;
    _activeMessages = [];
    _isLoading = false;
    if (notify) {
      notifyListeners();
    }
  }

  void _subscribeToActiveMessages(String conversationId) {
    if (_activeConversationId != conversationId) return;
    final operationEpoch = _sessionEpoch;

    _messagesRetryTimer?.cancel();
    _messagesSubscription?.cancel();

    try {
      _messagesSubscription = _service.getMessagesStream(conversationId).listen(
        (messages) {
          if (!_isCurrentSession(operationEpoch) ||
              _activeConversationId != conversationId) {
            return;
          }

          _messagesRetryTimer?.cancel();
          _messagesRetryAttempt = 0;
          _debugLogWhatsAppStatusChanges(messages);
          _pruneConfirmedOptimisticMessages(messages);
          final cached =
              _messageCacheByConversation[conversationId] ?? const <Message>[];
          final merged = mergeMessageTimelinesMonotonically(
            olderSnapshot: cached,
            currentTimeline: messages,
            limit: null,
          );
          final knownHasMore = _hasMoreMessagesByConversation[conversationId];
          final oldestStreamSequence = oldestDurableMessageSequence(messages);
          if (knownHasMore == null) {
            final streamPageIsFull =
                messages.length >= MessagingService.recentMessageStreamLimit;
            _hasMoreMessagesByConversation[conversationId] =
                streamPageIsFull && oldestStreamSequence != null;
            if (streamPageIsFull && oldestStreamSequence == null) {
              _olderMessagesErrorByConversation[conversationId] =
                  _missingHistoryCursorMessage;
            }
          } else if (messages.length <
              MessagingService.recentMessageStreamLimit) {
            _hasMoreMessagesByConversation[conversationId] = false;
          }
          if (!_historyCursorByConversation.containsKey(conversationId) &&
              oldestStreamSequence != null) {
            _historyCursorByConversation[conversationId] = oldestStreamSequence;
          }
          if (oldestStreamSequence != null &&
              _olderMessagesErrorByConversation[conversationId] ==
                  _missingHistoryCursorMessage) {
            _olderMessagesErrorByConversation.remove(conversationId);
            _hasMoreMessagesByConversation[conversationId] =
                messages.length >= MessagingService.recentMessageStreamLimit;
          }
          _messageStreamErrorByConversation.remove(conversationId);
          _cacheMessages(
            conversationId,
            merged,
            preserveFullHistory: true,
          );
          _isLoading = false;
          _markActiveConversationReadIfNeeded(conversationId, merged);
          unawaited(refreshMetaConversationState(conversationId));
          notifyListeners();
        },
        onError: (error) {
          if (_isCurrentSession(operationEpoch)) {
            _handleMessageStreamError(conversationId, error);
          }
        },
      );
    } catch (error) {
      if (_isCurrentSession(operationEpoch)) {
        _handleMessageStreamError(conversationId, error);
      }
    }
  }

  /// Loads the next older immutable page without changing the selected chat.
  /// A session, conversation or request-epoch change discards the late result.
  Future<void> loadOlderMessages(String conversationId) async {
    if (!_sessionReady || _activeConversationId != conversationId) return;
    if (_loadingOlderMessagesByConversation[conversationId] == true ||
        _hasMoreMessagesByConversation[conversationId] == false) {
      return;
    }

    final current =
        _messageCacheByConversation[conversationId] ?? const <Message>[];
    if (current.isEmpty) return;

    final beforeSequence = _historyCursorByConversation[conversationId] ??
        oldestDurableMessageSequence(current);
    if (beforeSequence == null) {
      _hasMoreMessagesByConversation[conversationId] = false;
      _olderMessagesErrorByConversation[conversationId] =
          _missingHistoryCursorMessage;
      notifyListeners();
      return;
    }

    final operationEpoch = _sessionEpoch;
    final requestEpoch =
        (_historyLoadEpochByConversation[conversationId] ?? 0) + 1;
    _historyLoadEpochByConversation[conversationId] = requestEpoch;
    _loadingOlderMessagesByConversation[conversationId] = true;
    _olderMessagesErrorByConversation.remove(conversationId);
    notifyListeners();

    try {
      final page = await _service.getMessagesBefore(
        conversationId,
        beforeSequence: beforeSequence,
      );
      if (!_isCurrentSession(operationEpoch) ||
          _activeConversationId != conversationId ||
          _historyLoadEpochByConversation[conversationId] != requestEpoch) {
        return;
      }

      final latestTimeline =
          _messageCacheByConversation[conversationId] ?? const <Message>[];
      final merged = mergeMessageTimelinesMonotonically(
        olderSnapshot: page.messages,
        currentTimeline: latestTimeline,
        limit: null,
      );
      final nextCursor = page.nextBeforeSequence;
      if (nextCursor != null) {
        final currentCursor = _historyCursorByConversation[conversationId];
        _historyCursorByConversation[conversationId] =
            currentCursor == null || nextCursor < currentCursor
                ? nextCursor
                : currentCursor;
      }
      if (_hasMoreMessagesByConversation[conversationId] != false) {
        _hasMoreMessagesByConversation[conversationId] =
            page.hasMore && nextCursor != null && nextCursor < beforeSequence;
      }
      _cacheMessages(
        conversationId,
        merged,
        preserveFullHistory: true,
      );
    } catch (error) {
      if (!_isCurrentSession(operationEpoch) ||
          _activeConversationId != conversationId ||
          _historyLoadEpochByConversation[conversationId] != requestEpoch) {
        return;
      }
      debugPrint('❌ Error loading older messages: $error');
      _olderMessagesErrorByConversation[conversationId] =
          'No pudimos cargar los mensajes anteriores.';
    } finally {
      if (_isCurrentSession(operationEpoch) &&
          _historyLoadEpochByConversation[conversationId] == requestEpoch) {
        _loadingOlderMessagesByConversation.remove(conversationId);
        notifyListeners();
      }
    }
  }

  Future<void> retryOlderMessages(String conversationId) {
    _olderMessagesErrorByConversation.remove(conversationId);
    _hasMoreMessagesByConversation[conversationId] = true;
    return loadOlderMessages(conversationId);
  }

  void retryConversationMessages(String conversationId) {
    if (_activeConversationId != conversationId) return;
    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messageStreamErrorByConversation.remove(conversationId);
    _isLoading = messagesForConversation(conversationId).isEmpty;
    notifyListeners();
    _subscribeToActiveMessages(conversationId);
  }

  void _markActiveConversationReadIfNeeded(
    String conversationId,
    List<Message> messages,
  ) {
    if (_activeConversationId != conversationId ||
        !isConversationVisible(conversationId) ||
        messages.isEmpty) {
      return;
    }

    final latestVisibleMessage =
        _latestVisibleMessageFromAnotherSender(messages);
    if (latestVisibleMessage == null) return;

    final lastSync = _lastReadSyncByConversation[conversationId];
    if (lastSync != null) {
      final latestAt = latestVisibleMessage.createdAt;
      final alreadySyncedExactMessage =
          _lastReadSyncMessageIdByConversation[conversationId] ==
              latestVisibleMessage.id;
      if (latestAt.isBefore(lastSync) ||
          (latestAt.isAtSameMomentAs(lastSync) && alreadySyncedExactMessage)) {
        return;
      }
    }

    _markConversationReadAndRefresh(
      conversationId,
      readThroughMessage: latestVisibleMessage,
      refreshAfter: false,
    );
  }

  Message? _latestVisibleMessageFromAnotherSender(List<Message> messages) {
    return latestMessageByTimelineOrder(
      messages.where((message) => message.type != 'system' && !message.isMe),
    );
  }

  void _handleMessageStreamError(String conversationId, Object error) {
    if (_activeConversationId != conversationId) return;
    final operationEpoch = _sessionEpoch;

    if (_messagesRetryAttempt >= _maxMessageStreamRetryAttempts) {
      debugPrint('❌ Error stream messages after retries: $error');
      _messageStreamErrorByConversation[conversationId] =
          'La conversación perdió conexión. Tus mensajes visibles se conservaron.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    _messagesRetryAttempt += 1;
    final delay = _messageStreamRetryDelay(_messagesRetryAttempt);
    debugPrint(
      '⚠️ Message stream interrupted; retrying in ${delay.inSeconds}s '
      '($_messagesRetryAttempt/$_maxMessageStreamRetryAttempts): $error',
    );

    _isLoading = messagesForConversation(conversationId).isEmpty;
    notifyListeners();

    _messagesRetryTimer?.cancel();
    _messagesRetryTimer = Timer(delay, () {
      if (_isCurrentSession(operationEpoch) &&
          _activeConversationId == conversationId) {
        _subscribeToActiveMessages(conversationId);
      }
    });
  }

  Duration _messageStreamRetryDelay(int attempt) {
    return switch (attempt) {
      1 => const Duration(seconds: 1),
      2 => const Duration(seconds: 2),
      3 => const Duration(seconds: 5),
      _ => const Duration(seconds: 10),
    };
  }

  void _markConversationReadAndRefresh(
    String conversationId, {
    required Message readThroughMessage,
    bool refreshAfter = true,
  }) {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    final readMarker = readThroughMessage.createdAt;
    final readThroughMessageId = readThroughMessage.id;
    _lastReadSyncByConversation[conversationId] = readMarker;
    _lastReadSyncMessageIdByConversation[conversationId] = readThroughMessageId;
    _markConversationLocallyRead(
      conversationId,
      readAt: readMarker,
      readThroughMessageSequence: readThroughMessage.messageSequence,
    );

    _service
        .markAsRead(
      conversationId,
      readThroughMessageId: readThroughMessageId,
    )
        .then((_) {
      if (!_isCurrentSession(operationEpoch)) return;
      if (refreshAfter) {
        loadConversations(refreshContextHints: false);
      } else {
        _scheduleConversationRefresh(const Duration(milliseconds: 120));
      }
    }).catchError((error) {
      if (!_isCurrentSession(operationEpoch)) return;
      if (_lastReadSyncByConversation[conversationId] == readMarker &&
          _lastReadSyncMessageIdByConversation[conversationId] ==
              readThroughMessageId) {
        _lastReadSyncByConversation.remove(conversationId);
        _lastReadSyncMessageIdByConversation.remove(conversationId);
      }
      if (_localReadAtByConversation[conversationId] == readMarker) {
        _localReadAtByConversation.remove(conversationId);
        _localReadMessageSequenceByConversation.remove(conversationId);
      }
      debugPrint('⚠️ Error marking conversation as read: $error');
      _scheduleConversationRefresh(const Duration(milliseconds: 250));
    });
  }

  List<Conversation> _applyLocalReadOverrides(
      List<Conversation> conversations) {
    if (_localReadAtByConversation.isEmpty) return conversations;

    return conversations.map((conversation) {
      final localReadAt = _localReadAtByConversation[conversation.id];
      if (localReadAt == null || conversation.unreadCount == 0) {
        return conversation;
      }

      final localReadSequence =
          _localReadMessageSequenceByConversation[conversation.id];
      final lastMessageSequence = conversation.lastMessageSequence;
      final lastActivity = conversation.lastMessageAt ?? conversation.updatedAt;
      if (hasMessageAfterReadCursor(
        latestSequence: lastMessageSequence,
        readSequence: localReadSequence,
        latestCreatedAt: lastActivity,
        readCreatedAt: localReadAt,
      )) {
        return conversation;
      }

      return _conversationWithUnreadCount(conversation, 0);
    }).toList(growable: false);
  }

  List<Conversation> _applyIncomingConversationPreviews(
    List<Conversation> conversations,
  ) {
    if (_incomingConversationPreviews.isEmpty) return conversations;

    final previewsToClear = <String>[];
    final updated = conversations.map((conversation) {
      final preview = _incomingConversationPreviews[conversation.id];
      if (preview == null) return conversation;

      if (_shouldClearIncomingPreview(conversation, preview)) {
        _debugInboxSync(
          'incomingPreview:clear',
          conversationId: conversation.id,
          details: {
            'serverUnread': conversation.unreadCount,
            'serverLast': _conversationReadThroughAt(conversation),
          },
        );
        previewsToClear.add(conversation.id);
        return conversation;
      }

      _debugInboxSync(
        'incomingPreview:keep',
        conversationId: conversation.id,
        details: {
          'previewUnread': preview.unreadCount,
          'serverUnread': conversation.unreadCount,
        },
      );
      return _conversationWithIncomingPreview(conversation, preview);
    }).toList(growable: false);

    for (final conversationId in previewsToClear) {
      _incomingConversationPreviews.remove(conversationId);
    }

    return updated;
  }

  List<Conversation> _applyOutgoingConversationPreviews(
    List<Conversation> conversations,
  ) {
    if (_outgoingConversationPreviews.isEmpty) return conversations;

    final previewsToClear = <String>[];
    final updated = conversations.map((conversation) {
      final preview = _outgoingConversationPreviews[conversation.id];
      if (preview == null) return conversation;

      final clearReason = _outgoingPreviewClearReason(conversation, preview);
      if (clearReason != null) {
        _debugInboxSync(
          'outgoingPreview:clear',
          conversationId: conversation.id,
          messageId: preview.clientMessageId,
          details: {
            'reason': clearReason,
            'serverMine': conversation.lastMessageIsMine,
            'serverLast': _conversationReadThroughAt(conversation),
          },
        );
        previewsToClear.add(conversation.id);
        return conversation;
      }

      _debugInboxSync(
        'outgoingPreview:keep',
        conversationId: conversation.id,
        messageId: preview.clientMessageId,
        details: {
          'serverMine': conversation.lastMessageIsMine,
          'serverLast': _conversationReadThroughAt(conversation),
        },
      );
      return _conversationWithOutgoingPreview(conversation, preview);
    }).toList(growable: false);

    for (final conversationId in previewsToClear) {
      _outgoingConversationPreviews.remove(conversationId);
    }

    return updated;
  }

  bool _shouldClearIncomingPreview(
    Conversation conversation,
    _IncomingConversationPreview preview,
  ) {
    if (isConversationVisible(conversation.id)) return true;

    final serverHasUnread = conversation.unreadCount > 0;
    final lastActivity = _conversationReadThroughAt(conversation);
    final serverLastSequence = conversation.lastMessageSequence;
    final serverHasPreviewMessage =
        serverLastSequence != null && preview.messageSequence != null
            ? serverLastSequence >= preview.messageSequence!
            : lastActivity != null && !lastActivity.isBefore(preview.createdAt);
    if (serverHasUnread && serverHasPreviewMessage) return true;

    final staffLastReadAt = conversation.staffLastReadAt;
    final staffLastReadSequence = conversation.staffLastReadMessageSequence;
    if (conversation.isSupport &&
        conversation.unreadCount == 0 &&
        ((staffLastReadSequence != null &&
                preview.messageSequence != null &&
                staffLastReadSequence >= preview.messageSequence!) ||
            (staffLastReadAt != null &&
                staffLastReadAt.isAfter(preview.receivedAt)))) {
      return true;
    }

    return false;
  }

  String? _outgoingPreviewClearReason(
    Conversation conversation,
    _OutgoingConversationPreview preview,
  ) {
    final serverClientMessageId =
        conversation.lastMessageMetadata['client_message_id']?.toString();
    if (serverClientMessageId == preview.clientMessageId) {
      return 'server_confirmed_client_id';
    }

    final lastActivity = _conversationReadThroughAt(conversation);
    if (lastActivity != null &&
        lastActivity.isAfter(preview.createdAt) &&
        !conversation.lastMessageIsMine) {
      return 'newer_incoming_message';
    }

    return null;
  }

  Conversation _conversationWithIncomingPreview(
    Conversation old,
    _IncomingConversationPreview preview,
  ) {
    final lastActivity = _conversationReadThroughAt(old);
    final previewActivity = preview.receivedAt;
    final nextActivity =
        lastActivity == null || previewActivity.isAfter(lastActivity)
            ? previewActivity
            : lastActivity;

    return Conversation(
      id: old.id,
      type: old.type,
      channel: old.channel,
      isGroup: old.isGroup,
      counterpartyType: old.counterpartyType,
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      updatedAt:
          nextActivity.isAfter(old.updatedAt) ? nextActivity : old.updatedAt,
      lastMessageAt:
          old.lastMessageAt == null || nextActivity.isAfter(old.lastMessageAt!)
              ? nextActivity
              : old.lastMessageAt,
      staffLastReadAt: old.staffLastReadAt,
      staffLastReadMessageSequence: old.staffLastReadMessageSequence,
      lastMessageId: old.lastMessageId,
      lastMessageSequence: preview.messageSequence ?? old.lastMessageSequence,
      lastMessageContent:
          preview.content.isNotEmpty ? preview.content : old.lastMessageContent,
      lastMessageType: preview.messageType,
      lastMessageMetadata: old.lastMessageMetadata,
      lastMessageIsMine: false,
      lastMessageDirection: preview.direction ?? old.lastMessageDirection,
      lastMessageExternalStatus:
          preview.externalStatus ?? old.lastMessageExternalStatus,
      unreadCount: _maxInt(old.unreadCount, preview.unreadCount),
      participantIds: old.participantIds,
      createdBy: old.createdBy,
      creatorName: old.creatorName,
      contextHint: old.contextHint,
    );
  }

  Conversation _conversationWithOutgoingPreview(
    Conversation old,
    _OutgoingConversationPreview preview,
  ) {
    final lastActivity = _conversationReadThroughAt(old);
    final nextActivity =
        lastActivity == null || preview.createdAt.isAfter(lastActivity)
            ? preview.createdAt
            : lastActivity;

    return Conversation(
      id: old.id,
      type: old.type,
      channel: old.channel,
      isGroup: old.isGroup,
      counterpartyType: old.counterpartyType,
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      updatedAt:
          nextActivity.isAfter(old.updatedAt) ? nextActivity : old.updatedAt,
      lastMessageAt:
          old.lastMessageAt == null || nextActivity.isAfter(old.lastMessageAt!)
              ? nextActivity
              : old.lastMessageAt,
      staffLastReadAt: old.staffLastReadAt,
      staffLastReadMessageSequence: old.staffLastReadMessageSequence,
      lastMessageId: old.lastMessageId,
      lastMessageSequence: old.lastMessageSequence,
      lastMessageContent: preview.content,
      lastMessageType: preview.messageType,
      lastMessageMetadata: preview.metadata,
      lastMessageIsMine: true,
      lastMessageDirection: preview.direction ?? old.lastMessageDirection,
      lastMessageExternalStatus:
          preview.externalStatus ?? old.lastMessageExternalStatus,
      unreadCount: 0,
      participantIds: old.participantIds,
      createdBy: old.createdBy,
      creatorName: old.creatorName,
      contextHint: old.contextHint,
    );
  }

  void _markConversationLocallyRead(
    String conversationId, {
    DateTime? readAt,
    int? readThroughMessageSequence,
  }) {
    _localReadAtByConversation[conversationId] = readAt ?? DateTime.now();
    if (readThroughMessageSequence != null) {
      _localReadMessageSequenceByConversation[conversationId] =
          readThroughMessageSequence;
    } else {
      _localReadMessageSequenceByConversation.remove(conversationId);
    }
    _incomingConversationPreviews.remove(conversationId);
    _clearLocalUnreadCount(conversationId);
  }

  DateTime? _conversationReadThroughAt(Conversation conversation) {
    return conversation.lastMessageAt ?? conversation.updatedAt;
  }

  int _maxInt(int a, int b) => a > b ? a : b;

  void _clearLocalUnreadCount(String conversationId) {
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1 || _conversations[index].unreadCount == 0) return;

    _conversations[index] =
        _conversationWithUnreadCount(_conversations[index], 0);
    notifyListeners();
  }

  Conversation _conversationWithUnreadCount(
    Conversation old,
    int unreadCount,
  ) {
    return Conversation(
      id: old.id,
      type: old.type,
      channel: old.channel,
      isGroup: old.isGroup,
      counterpartyType: old.counterpartyType,
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      lastMessageAt: old.lastMessageAt,
      staffLastReadAt: old.staffLastReadAt,
      staffLastReadMessageSequence: old.staffLastReadMessageSequence,
      lastMessageId: old.lastMessageId,
      lastMessageSequence: old.lastMessageSequence,
      lastMessageContent: old.lastMessageContent,
      lastMessageType: old.lastMessageType,
      lastMessageMetadata: old.lastMessageMetadata,
      lastMessageIsMine: old.lastMessageIsMine,
      lastMessageDirection: old.lastMessageDirection,
      lastMessageExternalStatus: old.lastMessageExternalStatus,
      updatedAt: old.updatedAt,
      participantIds: old.participantIds,
      unreadCount: unreadCount,
      createdBy: old.createdBy,
      creatorName: old.creatorName,
      contextHint: old.contextHint,
    );
  }

  /// Create a new internal chat
  Future<void> createInternalChat(String otherUserId) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createInternalChat(otherUserId);
      if (!_isCurrentSession(operationEpoch)) return;
      // No need to manually load conversations, the realtime listener will pick it up
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating internal chat: $e');
      rethrow;
    } finally {
      // _isLoading handled by stream listener in setActiveConversation
      // But if we fail before that:
      if (_isCurrentSession(operationEpoch) && _activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new internal group chat
  Future<void> createGroupChat(List<String> userIds, String title) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createGroupChat(
        participantIds: userIds,
        title: title,
      );
      if (!_isCurrentSession(operationEpoch)) return;
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating group chat: $e');
      rethrow;
    } finally {
      if (_isCurrentSession(operationEpoch) && _activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new support chat with a customer
  Future<void> createCustomerChat(String customerUserId,
      {String? contextType, String? contextId}) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createOutboundSupportChat(
          customerUserId,
          contextType: contextType,
          contextId: contextId);
      if (!_isCurrentSession(operationEpoch)) return;
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating customer chat: $e');
      rethrow;
    } finally {
      if (_isCurrentSession(operationEpoch) && _activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Open or create a WhatsApp-backed support conversation with a CRM customer.
  Future<void> openWhatsAppCustomerChat({
    required String phoneNumber,
    required String contactName,
    String? customerId,
    String? contextType,
    String? contextId,
  }) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.openWhatsAppSupportConversation(
        phoneNumber: phoneNumber,
        contactName: contactName,
        customerId: customerId,
        contextType: contextType,
        contextId: contextId,
      );
      if (!_isCurrentSession(operationEpoch)) return;

      await loadConversations(refreshContextHints: true);
      if (!_isCurrentSession(operationEpoch)) return;
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error opening WhatsApp customer chat: $e');
      rethrow;
    } finally {
      if (_isCurrentSession(operationEpoch) && _activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Send a message in the active conversation
  Future<void> sendMessage(
    String content, {
    String type = 'text',
    Map<String, dynamic>? metadata,
    String? conversationId,
  }) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    final targetConversationId = conversationId ?? _activeConversationId;
    if (targetConversationId == null || content.trim().isEmpty) return;
    final targetConversation = _conversations
        .where((candidate) => candidate.id == targetConversationId)
        .firstOrNull;
    if (targetConversation?.isMetaMessaging == true) {
      throw StateError(
        'Instagram y Messenger requieren el transporte Meta server-side.',
      );
    }
    final sendStartedAt = DateTime.now();

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final messageMetadata = <String, dynamic>{
      ...?metadata,
      'client_message_id': tempId,
    };

    // 1. Optimistic Update: Add message immediately
    final tempMessage = Message(
      id: tempId,
      conversationId: targetConversationId,
      senderId: _service.currentUserId,
      content: content,
      type: type,
      metadata: messageMetadata,
      createdAt: DateTime.now(),
      isMe: true,
    );

    _debugInboxSync(
      'sendMessage:start',
      conversationId: targetConversationId,
      messageId: tempId,
      details: {
        'type': type,
        'characterCount': content.length,
      },
    );

    final previousConversation = addOptimisticMessage(tempMessage);
    _debugInboxSync(
      'sendMessage:optimisticApplied',
      conversationId: targetConversationId,
      messageId: tempId,
      startedAt: sendStartedAt,
      details: {'hadPreviousRow': previousConversation != null},
    );

    try {
      await _service.sendMessage(
        conversationId: targetConversationId,
        content: content,
        type: type,
        metadata: messageMetadata,
      );
      _debugInboxSync(
        'sendMessage:serverDone',
        conversationId: targetConversationId,
        messageId: tempId,
        startedAt: sendStartedAt,
      );
      // Realtime stream will handle the validation/replacement
    } catch (e) {
      _debugInboxSync(
        'sendMessage:error',
        conversationId: targetConversationId,
        messageId: tempId,
        startedAt: sendStartedAt,
        details: {'error': e},
      );
      debugPrint('❌ Error sending message: $e');
      if (_isCurrentSession(operationEpoch)) {
        // On error, remove the temp message only from the originating session.
        removeMessageById(tempId);
        _restoreOutgoingMessagePreview(tempMessage, previousConversation);
      }
      // The host owns the user-facing recovery affordance. Propagating the
      // failure is essential: otherwise it clears the composer while the
      // insert was rolled back and the user has no way to distinguish that
      // from a committed message.
      rethrow;
    }
  }

  Conversation? _applyOutgoingMessagePreview(
    Message message, {
    bool notify = true,
    String source = 'unknown',
  }) {
    final index =
        _conversations.indexWhere((c) => c.id == message.conversationId);
    if (index == -1) {
      _debugInboxSync(
        'outgoingPreview:missingConversation',
        conversationId: message.conversationId,
        messageId: message.id,
        details: {'source': source},
      );
      return null;
    }

    final old = _conversations[index];
    final externalStatus = message.metadata['external_status']?.toString() ??
        message.metadata['whatsapp_status']?.toString();
    final direction = message.metadata['message_direction']?.toString() ??
        (old.isSupport ? 'outbound' : old.lastMessageDirection);

    _incomingConversationPreviews.remove(message.conversationId);
    _localReadAtByConversation[message.conversationId] = message.createdAt;
    _localReadMessageSequenceByConversation.remove(message.conversationId);
    _outgoingConversationPreviews[message.conversationId] =
        _OutgoingConversationPreview(
      clientMessageId: message.id,
      content: message.content,
      messageType: message.type,
      metadata: message.metadata,
      direction: direction,
      externalStatus: externalStatus,
      createdAt: message.createdAt,
      previousConversation: old,
    );

    _conversations[index] = _conversationWithOutgoingPreview(
      old,
      _outgoingConversationPreviews[message.conversationId]!,
    );

    _sortConversationsByRecentActivity();
    _debugInboxSync(
      'outgoingPreview:apply',
      conversationId: message.conversationId,
      messageId: message.id,
      details: {
        'source': source,
        'type': message.type,
        'direction': direction,
        'characterCount': message.content.length,
      },
    );
    if (notify) notifyListeners();
    return old;
  }

  void _restoreOutgoingMessagePreview(
    Message failedMessage,
    Conversation? previousConversation,
  ) {
    if (previousConversation == null) return;

    final index =
        _conversations.indexWhere((c) => c.id == failedMessage.conversationId);
    if (index == -1) return;

    final restored =
        _restoreOutgoingMessagePreviewById(failedMessage.id, notify: false);
    if (restored) {
      notifyListeners();
    }
  }

  bool _restoreOutgoingMessagePreviewById(
    String messageId, {
    bool notify = true,
  }) {
    String? conversationId;
    _OutgoingConversationPreview? preview;
    for (final entry in _outgoingConversationPreviews.entries) {
      if (entry.value.clientMessageId == messageId) {
        conversationId = entry.key;
        preview = entry.value;
        break;
      }
    }

    if (conversationId == null || preview == null) return false;

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index == -1) {
      _outgoingConversationPreviews.remove(conversationId);
      return false;
    }

    final current = _conversations[index];
    final currentClientMessageId =
        current.lastMessageMetadata['client_message_id']?.toString();
    if (currentClientMessageId != messageId) return false;

    _debugInboxSync(
      'outgoingPreview:restore',
      conversationId: conversationId,
      messageId: messageId,
    );
    _outgoingConversationPreviews.remove(conversationId);
    _conversations[index] = preview.previousConversation;
    _sortConversationsByRecentActivity();
    if (notify) notifyListeners();
    return true;
  }

  Conversation? addOptimisticMessage(Message message) {
    if (_disposed) return null;
    final startedAt = DateTime.now();
    _debugInboxSync(
      'optimisticMessage:add',
      conversationId: message.conversationId,
      messageId: message.id,
      details: {
        'activeMatches': _activeConversationId == message.conversationId,
        'isMe': message.isMe,
        'type': message.type,
        'pending': message.metadata['pending'],
      },
    );

    Conversation? previousConversation;
    _optimisticMessages[message.id] = message;

    if (message.isMe) {
      previousConversation = _applyOutgoingMessagePreview(
        message,
        notify: false,
        source: 'addOptimisticMessage',
      );
    }

    notifyListeners();
    _debugInboxSync(
      'optimisticMessage:notified',
      conversationId: message.conversationId,
      messageId: message.id,
      startedAt: startedAt,
      details: {'hadPreviousRow': previousConversation != null},
    );
    return previousConversation;
  }

  void removeMessageById(String messageId) {
    if (_disposed) return;
    final removedOptimistic = _optimisticMessages.remove(messageId) != null;
    var removedCached = false;
    for (final messages in _messageCacheByConversation.values) {
      final previousLength = messages.length;
      messages.removeWhere((message) => message.id == messageId);
      removedCached |= messages.length != previousLength;
    }
    final previousLength = _activeMessages.length;
    _activeMessages.removeWhere((message) => message.id == messageId);
    final restoredOutgoingPreview =
        _restoreOutgoingMessagePreviewById(messageId, notify: false);
    _debugInboxSync(
      'optimisticMessage:remove',
      messageId: messageId,
      details: {
        'removedBubble': removedOptimistic,
        'removedActive': previousLength != _activeMessages.length,
        'restoredInboxPreview': restoredOutgoingPreview,
      },
    );
    if (removedOptimistic ||
        removedCached ||
        _activeMessages.length != previousLength ||
        restoredOutgoingPreview) {
      notifyListeners();
    }
  }

  void updateMessageMetadataById(
    String messageId,
    Map<String, dynamic> metadataUpdates,
  ) {
    if (_disposed) return;
    final optimisticMessage = _optimisticMessages[messageId];
    if (optimisticMessage != null) {
      final updatedMetadata = Map<String, dynamic>.from(
        optimisticMessage.metadata,
      )..addAll(metadataUpdates);

      _optimisticMessages[messageId] = Message(
        id: optimisticMessage.id,
        conversationId: optimisticMessage.conversationId,
        senderId: optimisticMessage.senderId,
        content: optimisticMessage.content,
        type: optimisticMessage.type,
        metadata: updatedMetadata,
        createdAt: optimisticMessage.createdAt,
        messageSequence: optimisticMessage.messageSequence,
        isMe: optimisticMessage.isMe,
      );
      notifyListeners();
      return;
    }

    final cachedLocation = _cachedMessageLocation(messageId);
    if (cachedLocation == null) return;
    final messages = cachedLocation.$1;
    final index = cachedLocation.$2;
    final existing = messages[index];
    final updatedMetadata = Map<String, dynamic>.from(existing.metadata)
      ..addAll(metadataUpdates);

    messages[index] = Message(
      id: existing.id,
      conversationId: existing.conversationId,
      senderId: existing.senderId,
      content: existing.content,
      type: existing.type,
      metadata: updatedMetadata,
      createdAt: existing.createdAt,
      messageSequence: existing.messageSequence,
      isMe: existing.isMe,
    );

    notifyListeners();
  }

  void updateMessageById(
    String messageId, {
    String? content,
    Map<String, dynamic>? metadataUpdates,
  }) {
    if (_disposed) return;
    final optimisticMessage = _optimisticMessages[messageId];
    if (optimisticMessage != null) {
      final updatedMetadata = Map<String, dynamic>.from(
        optimisticMessage.metadata,
      );
      if (metadataUpdates != null) {
        updatedMetadata.addAll(metadataUpdates);
      }

      _optimisticMessages[messageId] = Message(
        id: optimisticMessage.id,
        conversationId: optimisticMessage.conversationId,
        senderId: optimisticMessage.senderId,
        content: content ?? optimisticMessage.content,
        type: optimisticMessage.type,
        metadata: updatedMetadata,
        createdAt: optimisticMessage.createdAt,
        messageSequence: optimisticMessage.messageSequence,
        isMe: optimisticMessage.isMe,
      );
      notifyListeners();
      return;
    }

    final cachedLocation = _cachedMessageLocation(messageId);
    if (cachedLocation == null) return;
    final messages = cachedLocation.$1;
    final index = cachedLocation.$2;
    final existing = messages[index];
    final updatedMetadata = Map<String, dynamic>.from(existing.metadata);
    if (metadataUpdates != null) {
      updatedMetadata.addAll(metadataUpdates);
    }

    messages[index] = Message(
      id: existing.id,
      conversationId: existing.conversationId,
      senderId: existing.senderId,
      content: content ?? existing.content,
      type: existing.type,
      metadata: updatedMetadata,
      createdAt: existing.createdAt,
      messageSequence: existing.messageSequence,
      isMe: existing.isMe,
    );

    notifyListeners();
  }

  (List<Message>, int)? _cachedMessageLocation(String messageId) {
    for (final messages in _messageCacheByConversation.values) {
      final index = messages.indexWhere((message) => message.id == messageId);
      if (index != -1) return (messages, index);
    }
    return null;
  }

  /// Create a new support ticket
  Future<void> createTicket(String title) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      final id = await _service.createSupportTicket(title: title);
      if (!_isCurrentSession(operationEpoch)) return;
      setActiveConversation(id);
    } catch (e) {
      debugPrint('❌ Error creating ticket: $e');
    }
  }

  /// Accept a pending chat request
  Future<void> acceptChatRequest(String conversationId) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      await _service.acceptChatRequest(conversationId);
      if (!_isCurrentSession(operationEpoch)) return;
      await loadConversations(); // Refresh to update status
    } catch (e) {
      debugPrint('❌ Error accepting chat request: $e');
      rethrow;
    }
  }

  /// Reject a pending chat request
  Future<void> rejectChatRequest(String conversationId, String reason) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return;
    try {
      await _service.rejectChatRequest(conversationId, reason);
      if (!_isCurrentSession(operationEpoch)) return;
      await loadConversations(); // Refresh to update status
    } catch (e) {
      debugPrint('❌ Error rejecting chat request: $e');
      rethrow;
    }
  }

  /// Archive a conversation without destroying messages or audit evidence.
  Future<bool> archiveConversation(String conversationId) async {
    final operationEpoch = _sessionEpoch;
    if (!_isCurrentSession(operationEpoch)) return false;
    try {
      // If archiving the active conversation, detach its live stream first.
      if (_activeConversationId == conversationId) {
        _messagesRetryTimer?.cancel();
        _messagesSubscription?.cancel();
        _activeConversationId = null;
        _activeMessages = [];
      }

      // Optimistic update - remove from local list immediately
      _conversations.removeWhere((c) => c.id == conversationId);
      notifyListeners();

      await _service.archiveConversation(conversationId);
      return _isCurrentSession(operationEpoch);
    } catch (e) {
      if (!_isCurrentSession(operationEpoch)) return false;
      debugPrint('❌ Error archiving conversation: $e');
      // Reload to restore state on error
      await loadConversations();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionResolutionEpoch += 1;
    _conversationsRefreshTimer?.cancel();
    _conversationsFollowUpRefreshTimer?.cancel();
    _messagesRetryTimer?.cancel();
    _contextHintCachePersistTimer?.cancel();
    _messageReceiptRefreshCoalescer.dispose();
    _messagesSubscription?.cancel();
    _conversationsSubscription?.unsubscribe();
    _notificationSubscription?.cancel();
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
