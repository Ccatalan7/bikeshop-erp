import 'dart:async';
import 'package:flutter/foundation.dart';
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
  bool _isLoading = false;
  String? _activeConversationId;

  // Subscriptions
  StreamSubscription? _messagesSubscription;
  RealtimeChannel? _conversationsSubscription;
  StreamSubscription? _notificationSubscription;
  Timer? _conversationsRefreshTimer;
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

  void _debugLogWhatsAppStatusChanges(List<Message> nextMessages) {
    final previousMessages = <Message>[
      ..._activeMessages,
      ..._optimisticMessages.values,
    ];
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
    loadConversations(); // Initial load

    _conversationsSubscription = _service.subscribeToConversationsUpdates(() {
      // Refresh immediately for fast list reordering, then once more after the
      // unread-count view has caught up to the message/conversation triggers.
      loadConversations();
      _scheduleConversationRefresh();
    });

    // Also listen to NotificationService for realtime alerts (triggers badge update)
    _notificationSubscription = NotificationService().onMessageReceived.listen(
      (_) {
        _scheduleConversationRefresh();
      },
    );
  }

  void _scheduleConversationRefresh() {
    _conversationsRefreshTimer?.cancel();
    _conversationsRefreshTimer = Timer(
      const Duration(milliseconds: 500),
      loadConversations,
    );
  }

  /// Get display title for a conversation
  String getChatTitle(Conversation c) {
    // For support chats, use customer name
    if (c.type == 'support') {
      if (c.creatorName != null && c.creatorName!.isNotEmpty) {
        return c.creatorName ?? 'Cliente';
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
  Future<void> loadConversations({String? type}) async {
    // Don't set global loading here to avoid screen flickering on updates
    try {
      final newConversations = await _service.getConversations(type: type);
      _conversations = newConversations;
      notifyListeners();

      // Refresh cache if needed
      if (_userCache.isEmpty) await _loadUserCache();
    } catch (e) {
      debugPrint('❌ Error loading conversations: $e');
    }
  }

  /// Open a conversation and subscribe to updates
  void setActiveConversation(String conversationId) {
    if (_activeConversationId == conversationId) return;

    _activeConversationId = conversationId;
    _activeMessages = []; // Clear previous chat immediately
    _optimisticMessages.clear();
    _isLoading = true; // Show loader while stream connects
    notifyListeners();

    // Optimistically update local state to clear badge immediately
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final old = _conversations[index];
      if (old.unreadCount > 0) {
        _conversationOpeningUnreadCounts[conversationId] = old.unreadCount;
      } else {
        _conversationOpeningUnreadCounts.remove(conversationId);
      }
      // Create copy with unreadCount = 0
      _conversations[index] = Conversation(
        id: old.id,
        type: old.type,
        channel: old.channel,
        status: old.status,
        title: old.title,
        contextType: old.contextType,
        contextId: old.contextId,
        lastMessageAt: old.lastMessageAt,
        lastMessageContent: old.lastMessageContent,
        lastMessageType: old.lastMessageType,
        lastMessageMetadata: old.lastMessageMetadata,
        lastMessageIsMine: old.lastMessageIsMine,
        lastMessageDirection: old.lastMessageDirection,
        lastMessageExternalStatus: old.lastMessageExternalStatus,
        updatedAt: old.updatedAt,
        participantIds: old.participantIds,
        unreadCount: 0, // Force clear
        createdBy: old.createdBy,
        creatorName: old.creatorName,
      );
      notifyListeners();
    }

    _markConversationReadAndRefresh(conversationId);

    // 1. Unsubscribe from old message stream
    _messagesRetryTimer?.cancel();
    _messagesRetryAttempt = 0;
    _messagesSubscription?.cancel();

    // 2. Subscribe to new message stream
    _subscribeToActiveMessages(conversationId);
  }

  void clearActiveConversation({String? conversationId}) {
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
    notifyListeners();
  }

  void _subscribeToActiveMessages(String conversationId) {
    if (_activeConversationId != conversationId) return;

    _messagesRetryTimer?.cancel();
    _messagesSubscription?.cancel();

    try {
      _messagesSubscription = _service.getMessagesStream(conversationId).listen(
        (messages) {
          _messagesRetryTimer?.cancel();
          _messagesRetryAttempt = 0;
          _debugLogWhatsAppStatusChanges(messages);
          _pruneConfirmedOptimisticMessages(messages);
          _activeMessages = messages;
          _isLoading = false;
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

  void _markConversationReadAndRefresh(String conversationId) {
    _service.markAsRead(conversationId).then((_) {
      if (_activeConversationId == conversationId) {
        loadConversations();
      }
    }).catchError((error) {
      debugPrint('⚠️ Error marking conversation as read: $error');
    });
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

      await loadConversations();
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

    addOptimisticMessage(tempMessage);

    try {
      await _service.sendMessage(
        conversationId: activeId,
        content: content,
        type: type,
        metadata: messageMetadata,
      );
      // Realtime stream will handle the validation/replacement
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      // On error, remove the temp message
      removeMessageById(tempId);
      // TODO: Show error toast
    }
  }

  void addOptimisticMessage(Message message) {
    if (_activeConversationId != message.conversationId) {
      return;
    }

    _optimisticMessages[message.id] = message;
    notifyListeners();
  }

  void removeMessageById(String messageId) {
    final removedOptimistic = _optimisticMessages.remove(messageId) != null;
    final previousLength = _activeMessages.length;
    _activeMessages.removeWhere((message) => message.id == messageId);
    if (removedOptimistic || _activeMessages.length != previousLength) {
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
    _messagesRetryTimer?.cancel();
    _messagesSubscription?.cancel();
    _conversationsSubscription?.unsubscribe();
    _notificationSubscription?.cancel();
    super.dispose();
  }
}
