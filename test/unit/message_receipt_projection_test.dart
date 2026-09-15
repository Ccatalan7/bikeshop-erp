import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/utils/message_receipt_projection.dart';

void main() {
  test('projects latest provider receipt without reordering inbox activity',
      () {
    final originalUpdatedAt = DateTime.utc(2026, 7, 19, 12);
    final conversation = Conversation(
      id: 'conversation-1',
      type: 'support',
      channel: 'whatsapp',
      counterpartyType: 'supplier',
      updatedAt: originalUpdatedAt,
      lastMessageAt: DateTime.utc(2026, 7, 19, 11, 59),
      staffLastReadMessageSequence: 40,
      lastMessageId: 'message-1',
      lastMessageSequence: 41,
      lastMessageContent: 'Hola',
      lastMessageExternalStatus: 'sent',
      unreadCount: 3,
      participantIds: const ['user-1'],
    );
    final readReceipt = Message(
      id: 'message-1',
      conversationId: 'conversation-1',
      senderId: 'user-1',
      content: 'Hola',
      type: 'text',
      metadata: const {
        'message_direction': 'outbound',
        'external_status': 'read',
        'external_message_id': 'wamid.1',
      },
      createdAt: DateTime.utc(2026, 7, 19, 11, 59),
      messageSequence: 41,
      isMe: true,
    );

    final projected = projectLatestMessageReceipt(conversation, readReceipt);

    expect(projected.lastMessageId, 'message-1');
    expect(projected.lastMessageSequence, 41);
    expect(projected.staffLastReadMessageSequence, 40);
    expect(projected.lastMessageExternalStatus, 'read');
    expect(projected.lastMessageMetadata['external_message_id'], 'wamid.1');
    expect(projected.lastMessageDirection, 'outbound');
    expect(projected.lastMessageIsMine, isTrue);
    expect(projected.updatedAt, originalUpdatedAt);
    expect(projected.unreadCount, 3);
    expect(projected.counterpartyType, 'supplier');
    expect(projected.isSupplierConversation, isTrue);
  });

  test('ignores a receipt belonging to another conversation', () {
    final conversation = Conversation(
      id: 'conversation-1',
      type: 'support',
      channel: 'whatsapp',
      updatedAt: DateTime.utc(2026, 7, 19),
      participantIds: const [],
    );
    final unrelated = Message(
      id: 'message-2',
      conversationId: 'conversation-2',
      content: 'Otro',
      type: 'text',
      metadata: const {'external_status': 'read'},
      createdAt: DateTime.utc(2026, 7, 19),
    );

    expect(projectLatestMessageReceipt(conversation, unrelated),
        same(conversation));
  });

  Conversation deliveredTile() => Conversation(
        id: 'conversation-1',
        type: 'support',
        channel: 'whatsapp',
        updatedAt: DateTime.utc(2026, 9, 3, 23),
        lastMessageAt: DateTime.utc(2026, 9, 3, 23),
        lastMessageId: 'message-9',
        lastMessageSequence: 90,
        lastMessageContent: 'prueba',
        lastMessageMetadata: const {
          'client_message_id': 'temp-9',
          'external_status': 'delivered',
        },
        lastMessageExternalStatus: 'delivered',
        lastMessageIsMine: true,
        participantIds: const ['user-1'],
      );

  Message receipt({
    required String id,
    required int sequence,
    required String status,
  }) =>
      Message(
        id: id,
        conversationId: 'conversation-1',
        senderId: 'user-1',
        content: 'prueba',
        type: 'text',
        metadata: {'client_message_id': 'temp-9', 'external_status': status},
        createdAt: DateTime.utc(2026, 9, 3, 23),
        messageSequence: sequence,
        isMe: true,
      );

  test('a late weaker receipt for the same message never moves the tile back',
      () {
    // The reload started on "sent" and answered after realtime painted
    // "delivered": the owner saw 1 → 2 → 1 → 2 checks (2026-09-03).
    final projected = projectLatestMessageReceipt(
      deliveredTile(),
      receipt(id: 'message-9', sequence: 90, status: 'sent'),
    );
    expect(projected.lastMessageExternalStatus, 'delivered');
    expect(projected.lastMessageMetadata['external_status'], 'delivered');
  });

  test('a stronger receipt for the same message still advances the tile', () {
    final projected = projectLatestMessageReceipt(
      deliveredTile(),
      receipt(id: 'message-9', sequence: 90, status: 'read'),
    );
    expect(projected.lastMessageExternalStatus, 'read');
  });

  test('an older latest message leaves the tile untouched', () {
    final tile = deliveredTile();
    expect(
      projectLatestMessageReceipt(
        tile,
        receipt(id: 'message-8', sequence: 89, status: 'read'),
      ),
      same(tile),
    );
  });

  test('receipt rank orders the provider stages and keeps terminal ones', () {
    expect(receiptRank('queued'), lessThan(receiptRank('accepted')));
    expect(receiptRank('accepted'), lessThan(receiptRank('sent')));
    expect(receiptRank('sent'), lessThan(receiptRank('delivered')));
    expect(receiptRank('delivered'), lessThan(receiptRank('read')));
    expect(receiptRank('failed'), greaterThan(receiptRank('read')));
    expect(receiptRank(null), 0);
  });
}
