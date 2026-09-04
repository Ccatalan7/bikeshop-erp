import '../models/conversation.dart';
import '../models/message.dart';

const Map<String, int> _receiptRank = {
  'queued': 1,
  'accepted': 2,
  'sent': 3,
  'delivered': 4,
  'read': 5,
  // Terminal outcomes: a late, weaker read model must not hide them either.
  'failed': 6,
  'outcome_unknown': 6,
};

/// Order in which a provider receipt can advance. Unknown or absent is 0.
int receiptRank(String? status) =>
    _receiptRank[status?.trim().toLowerCase()] ?? 0;

/// Projects the authoritative latest message into one inbox row without
/// changing conversation activity ordering or unrelated unread/context state.
///
/// A read model can answer late. An older latest message, or the same message
/// with a weaker receipt, never moves the tile backwards: the owner watched a
/// tile go 1 → 2 → 1 → 2 checks while a reload started before "delivered"
/// landed after it (2026-09-03).
Conversation projectLatestMessageReceipt(
  Conversation conversation,
  Message latestMessage,
) {
  if (conversation.id != latestMessage.conversationId) return conversation;

  final currentSequence = conversation.lastMessageSequence;
  final nextSequence = latestMessage.messageSequence;
  if (currentSequence != null &&
      nextSequence != null &&
      nextSequence < currentSequence) {
    return conversation;
  }

  final incomingStatus = latestMessage.metadata['external_status']?.toString();
  final keepsCurrentReceipt = conversation.lastMessageId == latestMessage.id &&
      receiptRank(conversation.lastMessageExternalStatus) >
          receiptRank(incomingStatus);

  return Conversation(
    id: conversation.id,
    type: conversation.type,
    channel: conversation.channel,
    isGroup: conversation.isGroup,
    counterpartyType: conversation.counterpartyType,
    status: conversation.status,
    title: conversation.title,
    contextType: conversation.contextType,
    contextId: conversation.contextId,
    updatedAt: conversation.updatedAt,
    lastMessageAt: latestMessage.createdAt,
    staffLastReadAt: conversation.staffLastReadAt,
    staffLastReadMessageSequence: conversation.staffLastReadMessageSequence,
    lastMessageId: latestMessage.id,
    lastMessageSequence: latestMessage.messageSequence,
    lastMessageContent: latestMessage.content,
    lastMessageType: latestMessage.type,
    lastMessageMetadata: keepsCurrentReceipt
        ? conversation.lastMessageMetadata
        : latestMessage.metadata,
    lastMessageIsMine: latestMessage.isMe,
    lastMessageDirection:
        latestMessage.metadata['message_direction']?.toString(),
    lastMessageExternalStatus: keepsCurrentReceipt
        ? conversation.lastMessageExternalStatus
        : incomingStatus,
    unreadCount: conversation.unreadCount,
    participantIds: conversation.participantIds,
    createdBy: conversation.createdBy,
    creatorName: conversation.creatorName,
    contextHint: conversation.contextHint,
    taskThreadContexts: conversation.taskThreadContexts,
  );
}
