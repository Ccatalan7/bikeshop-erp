import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'dart:ui'; // For VoidCallback

class MessagingService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Fetch conversations for the current user with unread counts
  /// [type] filter: 'internal' or 'support'
  Future<List<Conversation>> getConversations({String? type}) async {
    final userId = currentUserId;
    if (userId == null) return [];

    // First get conversations
    dynamic query = _client.from('conversations').select('''
      *,
      conversation_participants!inner(user_id)
    ''');

    // Filter by type if provided
    if (type != null) {
      query = query.eq('type', type);
    }

    // Order by latest message
    query = query.order('last_message_at', ascending: false);

    final response = await query;
    final List<dynamic> data = response as List<dynamic>;

    // Fetch unread counts for current user
    final unreadResponse = await _client
        .from('conversation_unread_counts')
        .select('conversation_id, unread_count')
        .eq('user_id', userId);

    final Map<String, int> unreadMap = {};
    for (var row in unreadResponse) {
      unreadMap[row['conversation_id']] = row['unread_count'] ?? 0;
    }

    return data.map((json) {
      // Inject unread count into json before parsing
      json['unread_count'] = unreadMap[json['id']] ?? 0;
      return Conversation.fromJson(json);
    }).toList();
  }

  /// Mark a conversation as read for the current user
  Future<void> markAsRead(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _client.rpc('mark_conversation_read', params: {
      'p_conversation_id': conversationId,
    });
  }

  /// Get messages stream for a specific conversation
  Stream<List<Message>> getMessagesStream(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .map((data) => data
            .map((json) => Message.fromJson(json, currentUserId: currentUserId))
            .toList());
  }

  /// Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? metadata,
    List<String>? participantIds, // Optional: for push notifications
  }) async {
    if (currentUserId == null) throw Exception('Not authenticated');

    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': currentUserId,
      'content': content,
      'type': type,
      'metadata': metadata ?? {},
    });
    // Trigger updates conversation timestamp automatically via DB trigger
  }

  /// Listen for ANY changes to the conversations table (for list re-fetch)
  RealtimeChannel subscribeToConversationsUpdates(VoidCallback onUpdate) {
    // We listen to the global 'conversations' table changes
    // Ideally, we would filter by 'participant', but Supabase Realtime filters are limited on joins.
    // So we listen to ALL 'conversations' changes, and the client will re-fetch.
    // Optimization: Listen to specific IDs if list is small, or just accept the overhead for now.
    // Better: Filter where 'id' is in the user's conversation list? Hard to maintain.
    // Simplest robust solution: Listen to 'conversations' table.
    return _client
        .channel('public:conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (payload) {
            // Trigger update regardless of payload for simplicity,
            // the Provider will re-fetch the user's specific list.
            onUpdate();
          },
        )
        .subscribe();
  }

  /// Create a new "Support" conversation (for Customer Portal)
  Future<String> createSupportTicket({
    required String title,
    String? contextType,
    String? contextId,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // 1. Create Conversation
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'support',
          'title': title,
          'context_type': contextType,
          'context_id': contextId,
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'];

    // 2. Add creator as participant
    await _client.from('conversation_participants').insert({
      'conversation_id': conversationId,
      'user_id': userId,
      'role': 'admin', // Creator is admin of the thread
    });

    return conversationId;
  }

  /// Create or get existing "Internal" chat with another employee
  Future<String> createInternalChat(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    // First, try to find an existing 1:1 internal conversation between these two users
    // We need to find a conversation where:
    // - type = 'internal'
    // - both users are participants
    // - only these two users are participants (1:1 chat)

    try {
      // Get all internal conversations where current user is participant
      final myConversations = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', userId);

      // Get all internal conversations where other user is participant
      final otherConversations = await _client
          .from('conversation_participants')
          .select('conversation_id')
          .eq('user_id', otherUserId);

      // Find intersection
      final myIds = (myConversations as List)
          .map((c) => c['conversation_id'] as String)
          .toSet();
      final otherIds = (otherConversations as List)
          .map((c) => c['conversation_id'] as String)
          .toSet();
      final commonIds = myIds.intersection(otherIds);

      if (commonIds.isNotEmpty) {
        // Check if any of these are internal 1:1 chats
        for (final conversationId in commonIds) {
          final conversation = await _client
              .from('conversations')
              .select('id, type')
              .eq('id', conversationId)
              .eq('type', 'internal')
              .maybeSingle();

          if (conversation != null) {
            // Verify it's a 1:1 chat (only 2 participants)
            final participants = await _client
                .from('conversation_participants')
                .select('user_id')
                .eq('conversation_id', conversationId);

            if ((participants as List).length == 2) {
              // Found existing 1:1 chat, return it
              return conversationId;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking existing conversations: $e');
      // Continue to create new if check fails
    }

    // No existing chat found, create new one
    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'internal',
          'last_message_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    final conversationId = conversation['id'];

    // Add participants
    await _client.from('conversation_participants').insert([
      {
        'conversation_id': conversationId,
        'user_id': userId,
        'role': 'admin',
      },
      {
        'conversation_id': conversationId,
        'user_id': otherUserId,
        'role': 'member',
      }
    ]);

    return conversationId;
  }

  /// Delete a conversation and all its messages
  /// Uses RPC function for proper permission handling
  Future<void> deleteConversation(String conversationId) async {
    final userId = currentUserId;
    if (userId == null) throw Exception('Not authenticated');

    debugPrint('🗑️ Deleting conversation: $conversationId');

    try {
      await _client.rpc('delete_conversation', params: {
        'p_conversation_id': conversationId,
      });
      debugPrint('✅ Conversation deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting conversation: $e');
      rethrow;
    }
  }
}
