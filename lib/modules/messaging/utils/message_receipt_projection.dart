import '../models/conversation.dart';
import '../models/message.dart';

/// Projects the authoritative latest message into one inbox row without
/// changing conversation activity ordering or unrelated unread/context state.
Conversation projectLatestMessageReceipt(
  Conversation conversation,
  Message latestMessage,
) {
  if (conversation.id != latestMessage.conversationId) return conversation;

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
    lastMessageMetadata: latestMessage.metadata,
    lastMessageIsMine: latestMessage.isMe,
    lastMessageDirection:
        latestMessage.metadata['message_direction']?.toString(),
    lastMessageExternalStatus:
        latestMessage.metadata['external_status']?.toString(),
    unreadCount: conversation.unreadCount,
    participantIds: conversation.participantIds,
    createdBy: conversation.createdBy,
    creatorName: conversation.creatorName,
    contextHint: conversation.contextHint,
  );
}
