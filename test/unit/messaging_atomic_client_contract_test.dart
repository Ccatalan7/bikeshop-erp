import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';

void main() {
  late String serviceSource;
  late String providerSource;
  late String chatWindowSource;

  setUpAll(() {
    serviceSource = File(
      'lib/modules/messaging/services/messaging_service.dart',
    ).readAsStringSync();
    providerSource = File(
      'lib/modules/messaging/providers/chat_provider.dart',
    ).readAsStringSync();
    chatWindowSource = File(
      'lib/modules/messaging/widgets/chat_window.dart',
    ).readAsStringSync();
  });

  test('read acknowledgement carries the exact visible message evidence', () {
    expect(serviceSource, contains("rpc('mark_conversation_read'"));
    expect(
      serviceSource,
      contains("'p_read_through_message_id': readThroughMessageId"),
    );
    expect(providerSource, contains('required Message readThroughMessage'));
    expect(providerSource, contains('readThroughMessage.id'));
    expect(
      providerSource,
      contains('readThroughMessageId: readThroughMessageId'),
    );
  });

  test('message sequence survives client projections and orders reads', () {
    expect(providerSource, contains('latestMessageByTimelineOrder('));
    expect(
      RegExp(r'messageSequence: (?:optimisticMessage|existing)\.messageSequence')
          .allMatches(providerSource),
      hasLength(4),
    );
    expect(
      serviceSource,
      contains(".order('message_sequence', ascending: false)"),
    );
  });

  test('aggregate creation and context changes use atomic RPC commands', () {
    expect(
      serviceSource,
      contains("'open_whatsapp_support_conversation'"),
    );
    expect(serviceSource, contains("'create_customer_support_request'"));
    expect(serviceSource, contains("'create_staff_support_conversation'"));
    expect(serviceSource, contains("'create_staff_internal_conversation'"));
    expect(serviceSource, contains("rpc('set_conversation_primary_context'"));
    expect(
        serviceSource, isNot(contains('ensure_whatsapp_conversation_binding')));
    expect(serviceSource, contains("'p_idempotency_key': commandKey"));
    expect(serviceSource, contains('_commandIdempotencyStore.execute('));
    expect(
      serviceSource,
      contains('MessagingCommandNamespace.customerSupportRequest'),
    );
    expect(
      serviceSource,
      contains('MessagingCommandNamespace.whatsappSupportOpen'),
    );
    expect(
      serviceSource,
      contains('MessagingCommandNamespace.staffSupportCreate'),
    );
    expect(
      serviceSource,
      contains('MessagingCommandNamespace.staffInternalCreate'),
    );
    expect(
      serviceSource,
      isNot(contains(".from('conversations')\n        .insert")),
    );
    expect(
      serviceSource,
      isNot(contains(".from('conversation_contexts').insert")),
    );
    expect(serviceSource, isNot(contains('_maxPendingCommandKeys')));
    expect(serviceSource, isNot(contains('_pendingCustomerRequestKeys')));
    expect(serviceSource, isNot(contains('_pendingWhatsAppOpenKeys')));
    expect(
      RegExp(r'await _assertMessagingCommandSession\(')
          .allMatches(serviceSource),
      hasLength(4),
    );
  });

  test('one-recipient groups keep explicit shape instead of title inference',
      () {
    final conversation = Conversation.fromJson({
      'id': 'group-chat',
      'type': 'internal',
      'channel': 'internal',
      'is_group': true,
      'status': 'active',
      'updated_at': '2026-07-19T12:00:00Z',
      'conversation_participants': const [],
    });

    expect(conversation.isGroup, isTrue);
  });

  test('realtime lifecycle and participant updates refresh the inbox', () {
    expect(
      serviceSource,
      contains('onMessageReceiptUpdate?.call(receiptUpdate)'),
    );
    expect(
      serviceSource,
      contains('no state-bearing UPDATE is silently discarded here'),
    );
    expect(
      serviceSource,
      isNot(
        contains(
          "'messages' || 'conversations' || 'conversation_participants' => false",
        ),
      ),
    );
  });

  test('background apps never own visible read acknowledgement', () {
    expect(providerSource, contains('void setApplicationForeground('));
    expect(
      providerSource,
      contains(
        'if (!_isApplicationForeground || _awaitingForegroundFrame) return false;',
      ),
    );
    expect(providerSource,
        contains('WidgetsBinding.instance.addPostFrameCallback'));
    expect(
      providerSource,
      contains('background Realtime events can never be acknowledged'),
    );
  });

  test('stored counterparty capability wins over mutable context hints', () {
    final conversation = Conversation(
      id: 'supplier-chat',
      type: 'support',
      channel: 'whatsapp',
      counterpartyType: 'supplier',
      contextType: 'job',
      contextId: 'legacy-invalid-context',
      updatedAt: DateTime.utc(2026, 7, 19),
      participantIds: const [],
    );

    expect(conversation.isSupplierConversation, isTrue);
    expect(conversation.isCustomerConversation, isFalse);
  });

  test('supplier chats cannot open the customer job or invoice linker', () {
    expect(
      chatWindowSource,
      contains('if (!conversation.isSupplierConversation)'),
    );
    expect(
      chatWindowSource,
      contains('if (widget.conversation.isSupplierConversation)'),
    );
    expect(
      chatWindowSource,
      contains('El contexto de proveedor se administra desde su ficha'),
    );
  });
}
