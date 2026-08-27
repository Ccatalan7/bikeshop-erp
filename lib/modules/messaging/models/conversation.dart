import 'conversation_context_hint.dart';

class Conversation {
  final String id;
  final String type; // 'internal' or 'support'
  /// Canonical transport for this thread.
  ///
  /// Provider-backed customer channels must never fall back to the native
  /// `messages` insert path: their outbound command is owned by the matching
  /// server-side transport.
  final String channel;
  final bool isGroup; // Immutable shape for internal conversations
  final String? counterpartyType; // 'internal', 'customer', or 'supplier'
  final String status; // 'pending', 'active', 'resolved', 'rejected'
  final String? title;
  final String? contextType;
  final String? contextId;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final DateTime? staffLastReadAt;
  final int? staffLastReadMessageSequence;
  final String? lastMessageId;
  final int? lastMessageSequence;
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
    this.isGroup = false,
    this.counterpartyType,
    this.status = 'active',
    this.title,
    this.contextType,
    this.contextId,
    required this.updatedAt,
    this.lastMessageAt,
    this.staffLastReadAt,
    this.staffLastReadMessageSequence,
    this.lastMessageId,
    this.lastMessageSequence,
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
        value == 'whatsapp' ||
        value == 'instagram' ||
        value == 'facebook_messenger') {
      return value!;
    }

    return type == 'internal' ? 'internal' : 'website_portal';
  }

  static bool supportsContextPanel(String? contextType) {
    return contextType == 'job' ||
        contextType == 'invoice' ||
        contextType == 'order' ||
        contextType == 'purchase_invoice' ||
        contextType == 'supplier' ||
        contextType == 'task';
  }

  bool get isInternal => channel == 'internal' || type == 'internal';
  bool get isSupport => type == 'support';
  bool get isWhatsApp => channel == 'whatsapp';
  bool get isInstagram => channel == 'instagram';
  bool get isFacebookMessenger => channel == 'facebook_messenger';
  bool get isMetaMessaging => isInstagram || isFacebookMessenger;
  bool get usesExternalMessagingTransport => isWhatsApp || isMetaMessaging;
  bool get isWebsitePortal => channel == 'website_portal';
  String get effectiveCounterpartyType {
    final stored = counterpartyType?.trim().toLowerCase();
    if (stored == 'internal' || stored == 'customer' || stored == 'supplier') {
      return stored!;
    }
    if (isInternal) return 'internal';
    if (contextType == 'supplier' ||
        contextType == 'purchase_invoice' ||
        contextHint?.hasSupplier == true ||
        contextHint?.hasPurchaseInvoice == true) {
      return 'supplier';
    }
    return 'customer';
  }

  bool get isSupplierConversation => effectiveCounterpartyType == 'supplier';
  bool get isCustomerConversation => effectiveCounterpartyType == 'customer';
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
    if (contextHint?.hasPurchaseInvoice == true) return 'purchase_invoice';
    if (contextHint?.hasSupplier == true) return 'supplier';
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
    if (contextHint?.hasPurchaseInvoice == true) {
      return contextHint?.purchaseInvoiceId;
    }
    if (contextHint?.hasSupplier == true) return contextHint?.supplierId;
    return contextId ?? contextHint?.effectiveContextId;
  }

  bool get hasSupportedContextPanel =>
      effectiveContextId != null && supportsContextPanel(effectiveContextType);

  String get channelLabel {
    if (isWhatsApp) {
      return isSupplierConversation ? 'Proveedor WhatsApp' : 'Cliente WhatsApp';
    }
    if (isInstagram) return 'Cliente Instagram';
    if (isFacebookMessenger) return 'Cliente Facebook Messenger';
    if (isWebsitePortal) return 'Cliente web';
    return 'Chat interno';
  }

  String get shortChannelLabel {
    if (isWhatsApp) return 'WhatsApp';
    if (isInstagram) return 'Instagram';
    if (isFacebookMessenger) return 'Messenger';
    if (isWebsitePortal) return 'Web';
    return 'Interno';
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    int? intValue(dynamic value) => switch (value) {
          int parsed => parsed,
          num parsed => parsed.toInt(),
          final raw when raw != null => int.tryParse(raw.toString()),
          _ => null,
        };

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
      isGroup: json['is_group'] == true,
      counterpartyType: json['counterparty_type']?.toString(),
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
      staffLastReadMessageSequence:
          intValue(json['staff_last_read_message_sequence']),
      lastMessageId: json['last_message_id']?.toString(),
      lastMessageSequence: intValue(json['last_message_sequence']),
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
