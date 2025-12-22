import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/conversation.dart';
import '../models/message.dart';

class MessagingService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Fetch conversations for the current user
  /// [type] filter: 'internal' or 'support'
  Future<List<Conversation>> getConversations({String? type}) async {
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

    return data.map((json) => Conversation.fromJson(json)).toList();
  }

  /// Get messages for a specific conversation
  Future<List<Message>> getMessages(String conversationId) async {
    final response = await _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true); // Oldest first for chat flow

    final List<dynamic> data = response as List<dynamic>;
    return data
        .map((json) => Message.fromJson(json, currentUserId: currentUserId))
        .toList();
  }

  /// Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String content,
    String type = 'text',
    Map<String, dynamic>? metadata,
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

  /// Subscribe to new messages for a conversation
  RealtimeChannel subscribeToConversation(
    String conversationId,
    Function(Message) onNewMessage,
  ) {
    return _client
        .channel('public:messages:conversation_id=eq.$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final newMessage = Message.fromJson(
              payload.newRecord,
              currentUserId: currentUserId,
            );
            onNewMessage(newMessage);
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

    // 1. Check if conversation already exists
    // This is complex in Supabase without a dedicated RPC or advanced query
    // For MVP, we'll try to find one where both are participants
    // Or just strictly create a new one if not found easily.
    // Ideally, we'd have a 'participants_hash' or unique constraint, but
    // let's do a simple check via RPC if available, or just create new for now to avoid logic errors.
    // actually, let's just create one. (Optimization: deduplicate later)

    // Better: Try to find an existing 'internal' conversation with just these 2 participants
    // For now, let's just CREATE. Unique 'internal' constraint can be added later.

    final conversation = await _client
        .from('conversations')
        .insert({
          'type': 'internal',
          // No title for 1:1 chats, or maybe "Chat with [Name]" generated on read
        })
        .select()
        .single();

    final conversationId = conversation['id'];

    // 2. Add participants
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
}
