import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';
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
  final DateTime receivedAt;
  final int unreadCount;

  const _IncomingConversationPreview({
    required this.content,
    required this.messageType,
    required this.direction,
    required this.externalStatus,
    required this.createdAt,
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
  final UserManagementService? _userService;

  // State
  List<Conversation> _conversations = [];
  List<Message> _activeMessages = [];
  final Map<String, Message> _optimisticMessages = {};
  final Map<String, Map<String, dynamic>> _userCache = {}; // id -> user data
  final Map<String, ConversationDraft> _conversationDrafts = {};
  final Map<String, int> _conversationOpeningUnreadCounts = {};
  final Map<String, DateTime> _localReadAtByConversation = {};
  final Map<String, DateTime> _lastReadSyncByConversation = {};
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
  String? _activeConversationId;

  // Subscriptions
  StreamSubscription? _messagesSubscription;
  RealtimeChannel? _conversationsSubscription;
  StreamSubscription? _notificationSubscription;
  Timer? _conversationsRefreshTimer;
  Timer? _conversationsFollowUpRefreshTimer;
  Timer? _messagesRetryTimer;
  int _messagesRetryAttempt = 0;
  static const int _maxMessageStreamRetryAttempts = 4;

  // Getters
  List<Conversation> get conversations => _conversations;
  List<Message> get activeMessages => _mergedActiveMessages;
  bool get isLoading => _isLoading;
  String? get activeConversationId => _activeConversationId;

  List<Message> get _mergedActiveMessages {
    final merged = <Message>[..._activeMessages];
    for (final message in _optimisticMessages.values) {
      if (message.conversationId != _activeConversationId) continue;
      if (_hasMatchingServerMessage(message, merged)) continue;
      merged.add(message);
    }

    merged.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return merged;
  }

  bool _hasMatchingServerMessage(Message optimistic, List<Message> server) {
    final clientMessageId =
        optimistic.metadata['client_message_id']?.toString();
    final externalMessageId =
        optimistic.metadata['external_message_id']?.toString();

    return server.any((message) {
      if (message.id == optimistic.id) return true;
      if (message.conversationId != optimistic.conversationId) return false;

      final messageClientId = message.metadata['client_message_id']?.toString();
      if (clientMessageId != null &&
          clientMessageId.isNotEmpty &&
          messageClientId == clientMessageId) {
        return true;
      }

      final messageExternalId =
          message.metadata['external_message_id']?.toString();
      if (externalMessageId != null &&
          externalMessageId.isNotEmpty &&
          messageExternalId == externalMessageId) {
        return true;
      }

      if (message.senderId != optimistic.senderId) return false;
      if (message.content != optimistic.content) return false;

      final deltaMs = message.createdAt
          .difference(optimistic.createdAt)
          .inMilliseconds
          .abs();
      return deltaMs < const Duration(seconds: 20).inMilliseconds;
    });
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

  String _debugPreview(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 48) return compact;
    return '${compact.substring(0, 48)}...';
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
        '🔎 [WhatsAppStatus] message=${_shortDebugId(message.id)} external=${_shortDebugId(externalMessageId)} client=${_shortDebugId(clientMessageId)} status=${previousStatus ?? 'none'}->$nextStatus created=${message.createdAt.toIso8601String()} text="${_debugPreview(message.content)}"',
      );
    }
  }

  void _pruneConfirmedOptimisticMessages(List<Message> serverMessages) {
    _optimisticMessages.removeWhere(
      (_, optimistic) => _hasMatchingServerMessage(optimistic, serverMessages),
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

  ChatProvider([this._userService]) {
    _loadUserCache();
    _initConversationsListener();
  }

  /// Load user cache for resolving names
  Future<void> _loadUserCache() async {
    if (_userService == null) return;
    try {
      // Check if we are an employee/admin before trying to fetch sensitive tenant users
      // This helper check prevents 400 errors for customers
      final users = await _userService.getTenantUsers();
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
  void _initConversationsListener() {
    // Keep the first inbox pass focused on badges and previews. Context chips
    // are useful, but they should not block message delivery feedback.
    loadConversations(refreshContextHints: false);

    _conversationsSubscription = _service.subscribeToConversationsUpdates(() {
      _scheduleConversationRefresh(const Duration(milliseconds: 80));
    });

    // Also listen to NotificationService for realtime alerts (triggers badge update)
    _notificationSubscription = NotificationService().onMessageReceived.listen(
      (message) {
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
    final explicitId = message.messageId ??
        _textValue(data['id']) ??
        _textValue(data['message_id']);
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
        isIncoming && _activeConversationId != conversationId;
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
      _lastReadSyncByConversation.remove(conversationId);
      _outgoingConversationPreviews.remove(conversationId);
      _incomingConversationPreviews[conversationId] =
          _IncomingConversationPreview(
        content: content,
        messageType: messageType,
        direction: nextDirection,
        externalStatus: externalStatus,
        createdAt: createdAt,
        receivedAt: DateTime.now(),
        unreadCount: nextUnreadCount,
      );
    } else if (_activeConversationId == conversationId || isCurrentUserSender) {
      _incomingConversationPreviews.remove(conversationId);
    }

    _conversations[index] = Conversation(
      id: old.id,
      type: old.type,
      channel: old.channel,
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      updatedAt: createdAt,
      lastMessageAt: createdAt,
      staffLastReadAt: old.staffLastReadAt,
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
    _conversationsRefreshTimer?.cancel();
    _conversationsRefreshTimer = Timer(
      delay,
      () => loadConversations(refreshContextHints: refreshContextHints),
    );
  }

  void _scheduleConversationFollowUpRefresh() {
    _conversationsFollowUpRefreshTimer?.cancel();
    _conversationsFollowUpRefreshTimer = Timer(
      const Duration(milliseconds: 700),
      () => loadConversations(refreshContextHints: false),
    );
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
    if (_conversationDrafts.remove(conversationId) != null) {
      notifyListeners();
    }
  }

  /// Load conversations list
  Future<void> loadConversations({
    String? type,
    bool refreshContextHints = true,
  }) async {
    // Don't set global loading here to avoid screen flickering on updates
    if (_isLoadingConversations) {
      _pendingConversationRefreshNeedsContextHints |= refreshContextHints;
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
      return;
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
    try {
      final newConversations = await _service.getConversations(
        type: type,
        includeContextHints: refreshContextHints,
      );
      _conversations = _applyOutgoingConversationPreviews(
        _applyIncomingConversationPreviews(
          _applyLocalReadOverrides(
            refreshContextHints
                ? newConversations
                : _mergeCachedContextHints(newConversations),
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

      // Refresh cache if needed
      if (_userCache.isEmpty) await _loadUserCache();
    } catch (e) {
      _debugInboxSync(
        'loadConversations:error',
        startedAt: startedAt,
        details: {'error': e},
      );
      debugPrint('❌ Error loading conversations: $e');
    } finally {
      _isLoadingConversations = false;
      if (_hasPendingConversationRefresh) {
        _hasPendingConversationRefresh = false;
        final pendingNeedsContextHints =
            _pendingConversationRefreshNeedsContextHints;
        _pendingConversationRefreshNeedsContextHints = false;
        _debugInboxSync(
          'loadConversations:runQueued',
          details: {'refreshContextHints': pendingNeedsContextHints},
        );
        _scheduleConversationRefresh(
          const Duration(milliseconds: 80),
          pendingNeedsContextHints,
        );
      }
    }
  }

  List<Conversation> _mergeCachedContextHints(
    List<Conversation> conversations,
  ) {
    if (_conversations.isEmpty) return conversations;

    final cachedById = {
      for (final conversation in _conversations) conversation.id: conversation,
    };

    return conversations.map((conversation) {
      if (conversation.contextHint != null) return conversation;

      final cached = cachedById[conversation.id];
      final cachedHint = cached?.contextHint;
      if (cachedHint == null) return conversation;

      return Conversation(
        id: conversation.id,
        type: conversation.type,
        channel: conversation.channel,
        status: conversation.status,
        title: conversation.title,
        contextType: conversation.contextType,
        contextId: conversation.contextId,
        updatedAt: conversation.updatedAt,
        lastMessageAt: conversation.lastMessageAt,
        staffLastReadAt: conversation.staffLastReadAt,
        lastMessageContent: conversation.lastMessageContent,
        lastMessageType: conversation.lastMessageType,
        lastMessageMetadata: conversation.lastMessageMetadata,
        lastMessageIsMine: conversation.lastMessageIsMine,
        lastMessageDirection: conversation.lastMessageDirection,
        lastMessageExternalStatus: conversation.lastMessageExternalStatus,
        unreadCount: conversation.unreadCount,
        participantIds: conversation.participantIds,
        createdBy: conversation.createdBy,
        creatorName: conversation.creatorName ?? cached?.creatorName,
        contextHint: cachedHint,
      );
    }).toList(growable: false);
  }

  /// Open a conversation and subscribe to updates
  void setActiveConversation(String conversationId) {
    if (_activeConversationId == conversationId) {
      if (_messagesSubscription == null) {
        _isLoading = _activeMessages.isEmpty;
        notifyListeners();
        _subscribeToActiveMessages(conversationId);
      }
      return;
    }

    _activeConversationId = conversationId;
    _activeMessages = []; // Clear previous chat immediately
    _optimisticMessages.clear();
    _isLoading = true; // Show loader while stream connects
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
      _markConversationLocallyRead(
        conversationId,
        readAt: _conversationReadThroughAt(old),
      );
    }

    // 1. Unsubscribe from old message stream
    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messagesSubscription?.cancel();

    // 2. Subscribe to new message stream
    _subscribeToActiveMessages(conversationId);
  }

  void clearActiveConversation({
    String? conversationId,
    bool notify = true,
  }) {
    if (_activeConversationId == null) return;
    if (conversationId != null && _activeConversationId != conversationId) {
      return;
    }

    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messagesSubscription?.cancel();
    _messagesSubscription = null;

    _activeConversationId = null;
    _activeMessages = [];
    _optimisticMessages.clear();
    _isLoading = false;
    if (notify) {
      notifyListeners();
    }
  }

  void _subscribeToActiveMessages(String conversationId) {
    if (_activeConversationId != conversationId) return;

    _messagesRetryTimer?.cancel();
    _messagesSubscription?.cancel();

    try {
      _messagesSubscription = _service.getMessagesStream(conversationId).listen(
        (messages) {
          if (_activeConversationId != conversationId) return;

          _messagesRetryTimer?.cancel();
          _messagesRetryAttempt = 0;
          _debugLogWhatsAppStatusChanges(messages);
          _pruneConfirmedOptimisticMessages(messages);
          _activeMessages = messages;
          _isLoading = false;
          _markActiveConversationReadIfNeeded(conversationId, messages);
          notifyListeners();
        },
        onError: (error) {
          _handleMessageStreamError(conversationId, error);
        },
      );
    } catch (error) {
      _handleMessageStreamError(conversationId, error);
    }
  }

  void _markActiveConversationReadIfNeeded(
    String conversationId,
    List<Message> messages,
  ) {
    if (_activeConversationId != conversationId || messages.isEmpty) return;

    final latestVisibleMessageAt =
        _latestVisibleMessageFromAnotherSender(messages);
    if (latestVisibleMessageAt == null) return;

    final lastSync = _lastReadSyncByConversation[conversationId];
    if (lastSync != null && !latestVisibleMessageAt.isAfter(lastSync)) {
      return;
    }

    _markConversationReadAndRefresh(
      conversationId,
      readThrough: latestVisibleMessageAt,
      refreshAfter: false,
    );
  }

  DateTime? _latestVisibleMessageFromAnotherSender(List<Message> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.type == 'system' || message.isMe) continue;
      return message.createdAt;
    }
    return null;
  }

  void _handleMessageStreamError(String conversationId, Object error) {
    if (_activeConversationId != conversationId) return;

    if (_messagesRetryAttempt >= _maxMessageStreamRetryAttempts) {
      debugPrint('❌ Error stream messages after retries: $error');
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

    _isLoading = _activeMessages.isEmpty;
    notifyListeners();

    _messagesRetryTimer?.cancel();
    _messagesRetryTimer = Timer(delay, () {
      if (_activeConversationId == conversationId) {
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
    DateTime? readThrough,
    bool refreshAfter = true,
  }) {
    final readMarker = readThrough ?? DateTime.now();
    _lastReadSyncByConversation[conversationId] = readMarker;
    _markConversationLocallyRead(conversationId, readAt: readMarker);

    _service.markAsRead(conversationId).then((_) {
      if (refreshAfter) {
        loadConversations(refreshContextHints: false);
      } else {
        _scheduleConversationRefresh(const Duration(milliseconds: 120));
      }
    }).catchError((error) {
      if (_lastReadSyncByConversation[conversationId] == readMarker) {
        _lastReadSyncByConversation.remove(conversationId);
      }
      if (_localReadAtByConversation[conversationId] == readMarker) {
        _localReadAtByConversation.remove(conversationId);
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

      final lastActivity = conversation.lastMessageAt ?? conversation.updatedAt;
      if (lastActivity.isAfter(localReadAt)) {
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
    if (_activeConversationId == conversation.id) return true;

    final serverHasUnread = conversation.unreadCount > 0;
    final lastActivity = _conversationReadThroughAt(conversation);
    final serverHasPreviewMessage =
        lastActivity != null && !lastActivity.isBefore(preview.createdAt);
    if (serverHasUnread && serverHasPreviewMessage) return true;

    final staffLastReadAt = conversation.staffLastReadAt;
    if (conversation.isSupport &&
        conversation.unreadCount == 0 &&
        staffLastReadAt != null &&
        staffLastReadAt.isAfter(preview.receivedAt)) {
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
  }) {
    _localReadAtByConversation[conversationId] = readAt ?? DateTime.now();
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
      status: old.status,
      title: old.title,
      contextType: old.contextType,
      contextId: old.contextId,
      lastMessageAt: old.lastMessageAt,
      staffLastReadAt: old.staffLastReadAt,
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
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createInternalChat(otherUserId);
      // No need to manually load conversations, the realtime listener will pick it up
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating internal chat: $e');
      rethrow;
    } finally {
      // _isLoading handled by stream listener in setActiveConversation
      // But if we fail before that:
      if (_activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new internal group chat
  Future<void> createGroupChat(List<String> userIds, String title) async {
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createGroupChat(
        participantIds: userIds,
        title: title,
      );
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating group chat: $e');
      rethrow;
    } finally {
      if (_activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Create a new support chat with a customer
  Future<void> createCustomerChat(String customerUserId,
      {String? contextType, String? contextId}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final conversationId = await _service.createOutboundSupportChat(
          customerUserId,
          contextType: contextType,
          contextId: contextId);
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating customer chat: $e');
      rethrow;
    } finally {
      if (_activeConversationId == null) {
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

      await loadConversations(refreshContextHints: true);
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error opening WhatsApp customer chat: $e');
      rethrow;
    } finally {
      if (_activeConversationId == null) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Send a message in the active conversation
  Future<void> sendMessage(String content,
      {String type = 'text', Map<String, dynamic>? metadata}) async {
    final activeId = _activeConversationId;
    if (activeId == null || content.trim().isEmpty) return;
    final sendStartedAt = DateTime.now();

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    final messageMetadata = <String, dynamic>{
      ...?metadata,
      'client_message_id': tempId,
    };

    // 1. Optimistic Update: Add message immediately
    final tempMessage = Message(
      id: tempId,
      conversationId: activeId,
      senderId: _service.currentUserId,
      content: content,
      type: type,
      metadata: messageMetadata,
      createdAt: DateTime.now(),
      isMe: true,
    );

    _debugInboxSync(
      'sendMessage:start',
      conversationId: activeId,
      messageId: tempId,
      details: {
        'type': type,
        'text': _debugPreview(content),
      },
    );

    final previousConversation = addOptimisticMessage(tempMessage);
    _debugInboxSync(
      'sendMessage:optimisticApplied',
      conversationId: activeId,
      messageId: tempId,
      startedAt: sendStartedAt,
      details: {'hadPreviousRow': previousConversation != null},
    );

    try {
      await _service.sendMessage(
        conversationId: activeId,
        content: content,
        type: type,
        metadata: messageMetadata,
      );
      _debugInboxSync(
        'sendMessage:serverDone',
        conversationId: activeId,
        messageId: tempId,
        startedAt: sendStartedAt,
      );
      // Realtime stream will handle the validation/replacement
    } catch (e) {
      _debugInboxSync(
        'sendMessage:error',
        conversationId: activeId,
        messageId: tempId,
        startedAt: sendStartedAt,
        details: {'error': e},
      );
      debugPrint('❌ Error sending message: $e');
      // On error, remove the temp message
      removeMessageById(tempId);
      _restoreOutgoingMessagePreview(tempMessage, previousConversation);
      // TODO: Show error toast
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
        'text': _debugPreview(message.content),
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
    if (_activeConversationId != message.conversationId) {
      _debugInboxSync(
        'optimisticMessage:skipBubbleInactive',
        conversationId: message.conversationId,
        messageId: message.id,
      );
    } else {
      _optimisticMessages[message.id] = message;
    }

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
    final removedOptimistic = _optimisticMessages.remove(messageId) != null;
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
        _activeMessages.length != previousLength ||
        restoredOutgoingPreview) {
      notifyListeners();
    }
  }

  void updateMessageMetadataById(
    String messageId,
    Map<String, dynamic> metadataUpdates,
  ) {
    final index =
        _activeMessages.indexWhere((message) => message.id == messageId);
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
        isMe: optimisticMessage.isMe,
      );
      notifyListeners();
      return;
    }

    if (index == -1) {
      return;
    }

    final existing = _activeMessages[index];
    final updatedMetadata = Map<String, dynamic>.from(existing.metadata)
      ..addAll(metadataUpdates);

    _activeMessages[index] = Message(
      id: existing.id,
      conversationId: existing.conversationId,
      senderId: existing.senderId,
      content: existing.content,
      type: existing.type,
      metadata: updatedMetadata,
      createdAt: existing.createdAt,
      isMe: existing.isMe,
    );

    notifyListeners();
  }

  void updateMessageById(
    String messageId, {
    String? content,
    Map<String, dynamic>? metadataUpdates,
  }) {
    final index =
        _activeMessages.indexWhere((message) => message.id == messageId);
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
        isMe: optimisticMessage.isMe,
      );
      notifyListeners();
      return;
    }

    if (index == -1) {
      return;
    }

    final existing = _activeMessages[index];
    final updatedMetadata = Map<String, dynamic>.from(existing.metadata);
    if (metadataUpdates != null) {
      updatedMetadata.addAll(metadataUpdates);
    }

    _activeMessages[index] = Message(
      id: existing.id,
      conversationId: existing.conversationId,
      senderId: existing.senderId,
      content: content ?? existing.content,
      type: existing.type,
      metadata: updatedMetadata,
      createdAt: existing.createdAt,
      isMe: existing.isMe,
    );

    notifyListeners();
  }

  /// Create a new support ticket
  Future<void> createTicket(String title) async {
    try {
      final id = await _service.createSupportTicket(title: title);
      setActiveConversation(id);
    } catch (e) {
      debugPrint('❌ Error creating ticket: $e');
    }
  }

  /// Accept a pending chat request
  Future<void> acceptChatRequest(String conversationId) async {
    try {
      await _service.acceptChatRequest(conversationId);
      await loadConversations(); // Refresh to update status
    } catch (e) {
      debugPrint('❌ Error accepting chat request: $e');
      rethrow;
    }
  }

  /// Reject a pending chat request
  Future<void> rejectChatRequest(String conversationId, String reason) async {
    try {
      await _service.rejectChatRequest(conversationId, reason);
      await loadConversations(); // Refresh to update status
    } catch (e) {
      debugPrint('❌ Error rejecting chat request: $e');
      rethrow;
    }
  }

  /// Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    try {
      // If deleting the active conversation, clear it first
      if (_activeConversationId == conversationId) {
        _messagesRetryTimer?.cancel();
        _messagesSubscription?.cancel();
        _activeConversationId = null;
        _activeMessages = [];
      }

      // Optimistic update - remove from local list immediately
      _conversations.removeWhere((c) => c.id == conversationId);
      notifyListeners();

      // Delete from server
      await _service.deleteConversation(conversationId);
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting conversation: $e');
      // Reload to restore state on error
      await loadConversations();
      return false;
    }
  }

  @override
  void dispose() {
    _conversationsRefreshTimer?.cancel();
    _conversationsFollowUpRefreshTimer?.cancel();
    _messagesRetryTimer?.cancel();
    _messagesSubscription?.cancel();
    _conversationsSubscription?.unsubscribe();
    _notificationSubscription?.cancel();
    super.dispose();
  }
}
