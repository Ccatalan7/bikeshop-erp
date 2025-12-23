import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';
import '../../../shared/services/notification_service.dart';

class ChatProvider extends ChangeNotifier {
  final MessagingService _service = MessagingService();
  final UserManagementService _userService;

  // State
  List<Conversation> _conversations = [];
  List<Message> _activeMessages = [];
  Map<String, Map<String, dynamic>> _userCache = {}; // id -> user data
  bool _isLoading = false;
  String? _activeConversationId;

  // Subscriptions
  StreamSubscription? _messagesSubscription;
  RealtimeChannel? _conversationsSubscription;

  // Getters
  List<Conversation> get conversations => _conversations;
  List<Message> get activeMessages => _activeMessages;
  bool get isLoading => _isLoading;
  String? get activeConversationId => _activeConversationId;

  /// Total unread messages across all conversations
  int get totalUnreadCount =>
      _conversations.fold(0, (sum, c) => sum + c.unreadCount);

  ChatProvider(this._userService) {
    _loadUserCache();
    _initConversationsListener();
  }

  /// Load user cache for resolving names
  Future<void> _loadUserCache() async {
    try {
      final users = await _userService.getTenantUsers();
      for (var u in users) {
        _userCache[u['id']] = u;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user cache: $e');
    }
  }

  /// Initialize listener for conversation list updates
  void _initConversationsListener() {
    loadConversations(); // Initial load

    _conversationsSubscription = _service.subscribeToConversationsUpdates(() {
      loadConversations(); // Re-fetch on any change
    });

    // Also listen to NotificationService for realtime alerts (triggers badge update)
    NotificationService().onMessageReceived.listen((_) {
      // Small delay to ensure DB view is updated by trigger
      Future.delayed(const Duration(milliseconds: 500), () {
        loadConversations();
      });
    });
  }

  /// Get display title for a conversation
  String getChatTitle(Conversation c) {
    if (c.title != null && c.title!.isNotEmpty) return c.title!;
    if (c.type == 'support') return 'Ticket de Soporte';

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
    _isLoading = true; // Show loader while stream connects
    notifyListeners();

    // Optimistically update local state to clear badge immediately
    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index != -1) {
      final old = _conversations[index];
      // Create copy with unreadCount = 0
      _conversations[index] = Conversation(
        id: old.id,
        type: old.type,
        title: old.title,
        contextType: old.contextType,
        contextId: old.contextId,
        lastMessageAt: old.lastMessageAt,
        updatedAt: old.updatedAt,
        participantIds: old.participantIds,
        unreadCount: 0, // Force clear
      );
      notifyListeners();
    }

    // Mark conversation as read on server
    _service.markAsRead(conversationId).then((_) {
      // Refresh conversations to ensure server sync (optional but good for consistency)
      loadConversations();
    });

    // 1. Unsubscribe from old message stream
    _messagesSubscription?.cancel();

    // 2. Subscribe to new message stream
    try {
      _messagesSubscription = _service.getMessagesStream(conversationId).listen(
        (messages) {
          _activeMessages = messages;
          _isLoading = false;
          notifyListeners();
        },
        onError: (error) {
          debugPrint('❌ Error stream messages: $error');
          _isLoading = false;
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('❌ Error setting up message stream: $e');
      _isLoading = false;
      notifyListeners();
    }
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

  /// Send a message in the active conversation
  Future<void> sendMessage(String content,
      {String type = 'text', Map<String, dynamic>? metadata}) async {
    if (_activeConversationId == null || content.trim().isEmpty) return;

    final tempId = 'temp-${DateTime.now().millisecondsSinceEpoch}';

    // 1. Optimistic Update: Add message immediately
    final tempMessage = Message(
      id: tempId,
      conversationId: _activeConversationId!,
      senderId: _service.currentUserId,
      content: content,
      type: type,
      metadata: metadata ?? {},
      createdAt: DateTime.now(),
      isMe: true,
    );

    _activeMessages.add(tempMessage);
    notifyListeners();

    try {
      await _service.sendMessage(
        conversationId: _activeConversationId!,
        content: content,
        type: type,
        metadata: metadata,
      );
      // Realtime stream will handle the validation/replacement
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      // On error, remove the temp message
      _activeMessages.removeWhere((m) => m.id == tempId);
      notifyListeners();
      // TODO: Show error toast
    }
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

  /// Delete a conversation
  Future<bool> deleteConversation(String conversationId) async {
    try {
      // If deleting the active conversation, clear it first
      if (_activeConversationId == conversationId) {
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
    _messagesSubscription?.cancel();
    _conversationsSubscription?.unsubscribe();
    super.dispose();
  }
}
