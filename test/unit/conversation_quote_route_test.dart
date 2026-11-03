// «Crear cotización» desde un chat (2026-11-03) abre la «Cotización» de
// Trabajos, su dueño, con el cliente que escribe ya elegido cuando se sabe.
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation.dart';
import 'package:vinabike_erp/modules/messaging/models/conversation_context_hint.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_quote_route.dart';

Conversation _chat({
  String counterparty = 'customer',
  String channel = 'whatsapp',
  ConversationContextHint? hint,
}) =>
    Conversation(
      id: 'conv-1',
      type: 'support',
      channel: channel,
      counterpartyType: counterparty,
      title: 'Pía Contreras',
      updatedAt: DateTime(2026, 11, 3),
      participantIds: const [],
      contextHint: hint,
    );

void main() {
  test(
      'the quote is for whoever writes, even in a chat linked to someone '
      'else\'s job', () {
    final chat = _chat(
      hint: const ConversationContextHint(customerId: 'cus-job'),
    );

    expect(canCreateQuoteFromConversation(chat), isTrue);
    expect(
      newQuoteRouteForConversation(chat, contactCustomerId: ' cus-writer '),
      '/taller/pegas/nueva?type=quotation&customer_id=cus-writer',
    );
    expect(
      newQuoteRouteForConversation(chat),
      '/taller/pegas/nueva?type=quotation&customer_id=cus-job',
      reason: 'a contact without a record falls back to the linked customer',
    );
  });

  test('with neither a contact record nor a linked customer, the form asks',
      () {
    expect(
      newQuoteRouteForConversation(_chat(), contactCustomerId: ''),
      '/taller/pegas/nueva?type=quotation',
    );
  });

  test('a supplier chat or the team\'s has no quote to create', () {
    expect(canCreateQuoteFromConversation(_chat(counterparty: 'supplier')),
        isFalse);
    expect(canCreateQuoteFromConversation(_chat(counterparty: 'internal')),
        isFalse);
  });
}
