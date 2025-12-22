import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/user_management_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/messaging_service.dart';

class ChatProvider extends ChangeNotifier {
  final MessagingService _service = MessagingService();
  final UserManagementService _userService;

  // State
  List<Conversation> _conversations = [];
  List<Message> _activeMessages = [];
  Map<String, Map<String, dynamic>> _userCache = {}; // id -> user data
  bool _isLoading = false;
  String? _activeConversationId;
  RealtimeChannel? _subscription;

  // Getters
  List<Conversation> get conversations => _conversations;
  List<Message> get activeMessages => _activeMessages;
  bool get isLoading => _isLoading;
  String? get activeConversationId => _activeConversationId;

  ChatProvider(this._userService) {
    _loadUserCache();
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
    _isLoading = true;
    notifyListeners();

    try {
      _conversations = await _service.getConversations(type: type);
      // Refresh cache if needed, or rely on distinct fetch
      if (_userCache.isEmpty) await _loadUserCache();
    } catch (e) {
      debugPrint('❌ Error loading conversations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Open a conversation and subscribe to updates
  Future<void> setActiveConversation(String conversationId) async {
    if (_activeConversationId == conversationId) return;

    _activeConversationId = conversationId;
    _activeMessages = []; // Clear previous chat
    _isLoading = true;
    notifyListeners();

    // 1. Unsubscribe from old
    _subscription?.unsubscribe();

    try {
      // 2. Load history
      _activeMessages = await _service.getMessages(conversationId);

      // 3. Subscribe to new
      _subscription = _service.subscribeToConversation(
        conversationId,
        (newMessage) {
          _activeMessages.add(newMessage);
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
    } finally {
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
      await loadConversations();
      setActiveConversation(conversationId);
    } catch (e) {
      debugPrint('❌ Error creating internal chat: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Send a message in the active conversation
  Future<void> sendMessage(String content,
      {String type = 'text', Map<String, dynamic>? metadata}) async {
    if (_activeConversationId == null || content.trim().isEmpty) return;

    try {
      await _service.sendMessage(
        conversationId: _activeConversationId!,
        content: content,
        type: type,
        metadata: metadata,
      );
      // Realtime subscription will handle the UI update
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      // TODO: Handle error UI
    }
  }

  /// Create a new support ticket
  Future<void> createTicket(String title) async {
    try {
      final id = await _service.createSupportTicket(title: title);
      await loadConversations(); // Refresh list
      setActiveConversation(id); // Open it
    } catch (e) {
      debugPrint('❌ Error creating ticket: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}
