class Conversation {
  final String id;
  final String type; // 'internal' or 'support'
  final String? title;
  final String? contextType;
  final String? contextId;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final int unreadCount; // Computed client-side or via view
  final List<String> participantIds;

  Conversation({
    required this.id,
    required this.type,
    this.title,
    this.contextType,
    this.contextId,
    required this.updatedAt,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.participantIds,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    var pIds = <String>[];
    if (json['conversation_participants'] != null) {
      pIds = (json['conversation_participants'] as List)
          .map((p) => p['user_id'] as String)
          .toList();
    }

    return Conversation(
      id: json['id'],
      type: json['type'],
      title: json['title'],
      contextType: json['context_type'],
      contextId: json['context_id'],
      updatedAt: DateTime.parse(json['updated_at']),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      participantIds: pIds,
    );
  }
}
