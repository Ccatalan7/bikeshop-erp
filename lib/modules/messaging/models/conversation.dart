class Conversation {
  final String id;
  final String type; // 'internal' or 'support'
  final String status; // 'pending', 'active', 'resolved', 'rejected'
  final String? title;
  final String? contextType;
  final String? contextId;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final int unreadCount; // Computed client-side or via view
  final List<String> participantIds;
  final String? createdBy; // Customer who created the request
  final String? creatorName; // Name of the creator (for support chats)

  Conversation({
    required this.id,
    required this.type,
    this.status = 'active',
    this.title,
    this.contextType,
    this.contextId,
    required this.updatedAt,
    this.lastMessageAt,
    this.unreadCount = 0,
    required this.participantIds,
    this.createdBy,
    this.creatorName,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    var pIds = <String>[];
    if (json['conversation_participants'] != null) {
      pIds = (json['conversation_participants'] as List)
          .map((p) => p['user_id'] as String)
          .toList();
    }

    // Extract context from relation
    String? cType = json['context_type'];
    String? cId = json['context_id'];

    if (json['conversation_contexts'] != null) {
      final contexts = (json['conversation_contexts'] as List);
      if (contexts.isNotEmpty) {
        // Try to find primary, otherwise first
        final primary = contexts.firstWhere((c) => c['is_primary'] == true,
            orElse: () => contexts.first);
        cType = primary['context_type'];
        cId = primary['context_id'];
      }
    }

    return Conversation(
      id: json['id'],
      type: json['type'],
      status: json['status'] ?? 'active',
      title: json['title'],
      contextType: cType,
      contextId: cId,
      updatedAt: DateTime.parse(json['updated_at']),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'])
          : null,
      unreadCount: json['unread_count'] ?? 0,
      participantIds: pIds,
      createdBy: json['created_by'],
      creatorName: json['creator_name'] ?? json['customers']?['name'],
    );
  }
}
