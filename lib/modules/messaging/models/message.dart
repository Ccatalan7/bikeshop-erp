class Message {
  final String id;
  final String conversationId;
  final String? senderId;
  final String content;
  final String type; // 'text', 'image', 'file', 'system'
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final int? messageSequence;
  final bool isMe; // Helper for UI

  Message({
    required this.id,
    required this.conversationId,
    this.senderId,
    required this.content,
    required this.type,
    required this.metadata,
    required this.createdAt,
    this.messageSequence,
    this.isMe = false,
  });

  factory Message.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final metadata = Map<String, dynamic>.from(
      (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final externalStatus = json['external_status'];
    if (externalStatus != null) {
      metadata['external_status'] = externalStatus;
    }
    final externalProvider = json['external_provider'];
    if (externalProvider != null) {
      metadata['external_provider'] = externalProvider;
    }
    final messageDirection = json['message_direction'];
    if (messageDirection != null) {
      metadata['message_direction'] = messageDirection;
    }
    final externalMessageId = json['external_message_id'];
    if (externalMessageId != null) {
      metadata['external_message_id'] = externalMessageId;
    }

    return Message(
      id: json['id'],
      conversationId: json['conversation_id'],
      senderId: json['sender_id'],
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      metadata: metadata,
      createdAt: DateTime.parse(json['created_at']).toLocal(),
      messageSequence: switch (json['message_sequence']) {
        int value => value,
        num value => value.toInt(),
        final value when value != null => int.tryParse(value.toString()),
        _ => null,
      },
      isMe: currentUserId != null && json['sender_id'] == currentUserId,
    );
  }
}

/// Canonical order inside one conversation.
///
/// Server messages use their durable per-conversation sequence. Optimistic or
/// legacy rows without one fall back deterministically to timestamp and ID.
int compareMessageTimelineOrder(Message a, Message b) {
  if (a.conversationId == b.conversationId &&
      a.messageSequence != null &&
      b.messageSequence != null) {
    final sequenceOrder = a.messageSequence!.compareTo(b.messageSequence!);
    if (sequenceOrder != 0) return sequenceOrder;
  }

  final timestampOrder = a.createdAt.compareTo(b.createdAt);
  if (timestampOrder != 0) return timestampOrder;
  return a.id.compareTo(b.id);
}
