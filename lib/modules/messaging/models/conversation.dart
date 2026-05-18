import 'conversation_context_hint.dart';

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
  final DateTime? staffLastReadAt;
  final String? lastMessageContent;
  final String? lastMessageType;
  final Map<String, dynamic> lastMessageMetadata;
  final bool lastMessageIsMine;
  final String? lastMessageDirection;
  final String? lastMessageExternalStatus;
  final int unreadCount; // Computed client-side or via view
  final List<String> participantIds;
  final String? createdBy; // Customer who created the request
  final String? creatorName; // Name of the creator (for support chats)
  final ConversationContextHint? contextHint;

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
    this.staffLastReadAt,
    this.lastMessageContent,
    this.lastMessageType,
    this.lastMessageMetadata = const {},
    this.lastMessageIsMine = false,
    this.lastMessageDirection,
    this.lastMessageExternalStatus,
    this.unreadCount = 0,
    required this.participantIds,
    this.createdBy,
    this.creatorName,
    this.contextHint,
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
  bool get hasDetectedContext => contextHint?.hasOperationalContext ?? false;
  bool get hasAnyContext =>
      effectiveContextType != null && effectiveContextId != null;
  String? get effectiveContextType {
    if (contextType != null &&
        contextId != null &&
        supportsContextPanel(contextType)) {
      return contextType;
    }
    if (contextHint?.hasJob == true) return 'job';
    if (contextHint?.hasInvoice == true) return 'invoice';
    return contextType ?? contextHint?.effectiveContextType;
  }

  String? get effectiveContextId {
    if (contextType != null &&
        contextId != null &&
        supportsContextPanel(contextType)) {
      return contextId;
    }
    if (contextHint?.hasJob == true) return contextHint?.jobId;
    if (contextHint?.hasInvoice == true) return contextHint?.invoiceId;
    return contextId ?? contextHint?.effectiveContextId;
  }

  bool get hasSupportedContextPanel =>
      effectiveContextId != null && supportsContextPanel(effectiveContextType);

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
      staffLastReadAt: json['staff_last_read_at'] != null
          ? DateTime.parse(json['staff_last_read_at'])
          : null,
      lastMessageContent: json['last_message_content']?.toString(),
      lastMessageType: json['last_message_type']?.toString(),
      lastMessageMetadata: Map<String, dynamic>.from(
        (json['last_message_metadata'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      lastMessageIsMine: json['last_message_is_mine'] == true,
      lastMessageDirection: json['last_message_direction']?.toString(),
      lastMessageExternalStatus:
          json['last_message_external_status']?.toString(),
      unreadCount: json['unread_count'] ?? 0,
      participantIds: pIds,
      createdBy: json['created_by'],
      creatorName: json['creator_name'] ?? json['customers']?['name'],
      contextHint: json['context_hint'] is Map
          ? ConversationContextHint.fromJson(
              Map<String, dynamic>.from(json['context_hint'] as Map),
            )
          : null,
    );
  }
}
