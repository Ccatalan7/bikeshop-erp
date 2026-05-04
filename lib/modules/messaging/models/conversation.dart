class Conversation {
  final String id;
  final String type; // 'internal' or 'support'
  final String channel; // 'internal', 'website_portal', or 'whatsapp'
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
    required this.channel,
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

  static String normalizeChannel(dynamic rawChannel, String type) {
    final value = rawChannel?.toString().trim();
    if (value == 'internal' ||
        value == 'website_portal' ||
        value == 'whatsapp') {
      return value!;
    }

    return type == 'internal' ? 'internal' : 'website_portal';
  }

  static bool supportsContextPanel(String? contextType) {
    return contextType == 'job' ||
        contextType == 'invoice' ||
        contextType == 'order';
  }

  bool get isInternal => channel == 'internal' || type == 'internal';
  bool get isSupport => type == 'support';
  bool get isWhatsApp => channel == 'whatsapp';
  bool get isWebsitePortal => channel == 'website_portal';
  bool get hasLinkedContext => contextType != null && contextId != null;
  bool get hasSupportedContextPanel =>
      contextId != null && supportsContextPanel(contextType);

  String get channelLabel {
    if (isWhatsApp) return 'Cliente WhatsApp';
    if (isWebsitePortal) return 'Cliente web';
    return 'Chat interno';
  }

  String get shortChannelLabel {
    if (isWhatsApp) return 'WhatsApp';
    if (isWebsitePortal) return 'Web';
    return 'Interno';
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    var pIds = <String>[];
    if (json['conversation_participants'] != null) {
      pIds = (json['conversation_participants'] as List)
          .map((p) => p['user_id'] as String)
          .toList();
    }

    // Prefer the conversation's active context columns. The history table can
    // contain older links for the same WhatsApp thread.
    String? cType = json['context_type'];
    String? cId = json['context_id'];

    if ((cType == null || cId == null) &&
        json['conversation_contexts'] != null) {
      final contexts = (json['conversation_contexts'] as List);
      if (contexts.isNotEmpty) {
        // Try to find primary, otherwise first
        final primary = contexts.firstWhere((c) => c['is_primary'] == true,
            orElse: () => contexts.first);
        cType = primary['context_type'];
        cId = primary['context_id'];
      }
    }

    final type = json['type']?.toString() ?? 'support';

    return Conversation(
      id: json['id'],
      type: type,
      channel: normalizeChannel(json['channel'], type),
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
