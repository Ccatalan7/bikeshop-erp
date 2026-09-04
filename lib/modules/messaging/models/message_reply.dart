import 'message.dart';

/// A quoted message remains in the ordinary timeline. It is independent from
/// an internal task's thread_root_message_id.
class MessageReply {
  const MessageReply({
    required this.conversationId,
    this.messageId,
    this.externalMessageId,
    this.content = '',
    this.type = 'text',
    this.senderId,
    this.senderName,
    this.direction,
    this.unavailable = false,
  });

  final String conversationId;
  final String? messageId;
  final String? externalMessageId;
  final String content;
  final String type;
  final String? senderId;
  final String? senderName;
  final String? direction;
  final bool unavailable;

  factory MessageReply.fromMessage(Message message, {String? senderName}) =>
      MessageReply(
        conversationId: message.conversationId,
        messageId: message.id,
        externalMessageId: message.metadata['external_message_id']?.toString(),
        content: message.content,
        type: message.type,
        senderId: message.senderId,
        senderName: senderName ?? message.metadata['contact_name']?.toString(),
        direction: message.metadata['message_direction']?.toString(),
      );

  static MessageReply? fromMetadata(
      Message message, Iterable<Message> history) {
    final raw = message.metadata['reply_to'];
    if (raw is Map && raw['conversation_id'] == message.conversationId) {
      return MessageReply(
        conversationId: message.conversationId,
        messageId: raw['message_id']?.toString(),
        externalMessageId: raw['external_message_id']?.toString(),
        content: raw['content']?.toString() ?? '',
        type: raw['type']?.toString() ?? 'text',
        senderId: raw['sender_id']?.toString(),
        senderName: raw['sender_name']?.toString(),
        direction: raw['message_direction']?.toString(),
        unavailable: raw['unavailable'] == true,
      );
    }
    // Historical inbound rows already retain Meta's context, even though the
    // old UI never rendered it. Resolve within this conversation only.
    final payload = message.metadata['raw_payload'];
    final inbound = payload is Map ? payload['message'] : null;
    final context = inbound is Map ? inbound['context'] : null;
    final externalId = context is Map ? context['id']?.toString() : null;
    if (externalId == null || externalId.isEmpty) return null;
    for (final candidate in history) {
      if (candidate.conversationId == message.conversationId &&
          candidate.metadata['external_message_id'] == externalId) {
        return MessageReply.fromMessage(candidate);
      }
    }
    return MessageReply(
      conversationId: message.conversationId,
      externalMessageId: externalId,
      unavailable: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        if (messageId != null) 'message_id': messageId,
        if (externalMessageId != null) 'external_message_id': externalMessageId,
        'content': content,
        'type': type,
        if (senderId != null) 'sender_id': senderId,
        if (senderName != null) 'sender_name': senderName,
        if (direction != null) 'message_direction': direction,
        if (unavailable) 'unavailable': true,
      };

  String get preview {
    if (unavailable) return 'Mensaje anterior no disponible';
    if (content.trim().isNotEmpty) return content;
    return switch (type) {
      'image' => 'Foto',
      'audio' => 'Mensaje de voz',
      'video' => 'Video',
      'file' || 'document' => 'Archivo',
      'sticker' => 'Sticker',
      _ => 'Mensaje',
    };
  }
}

class ChatComposerDraft {
  const ChatComposerDraft({required this.text, this.reply});
  final String text;
  final MessageReply? reply;
}
