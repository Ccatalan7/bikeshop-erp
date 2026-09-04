import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/whatsapp_send_receipt.dart';

void main() {
  test('explicit database acceptance is durable without a Meta identifier', () {
    final receipt = parseDurableWhatsAppSendReceipt({
      'ok': true,
      'accepted': true,
      'queued': true,
      'message_id': 'database-message',
      'external_status': 'queued',
    });
    expect(receipt.isDurable, isTrue);
    expect(receipt.isQueued, isTrue);
    expect(receipt.externalStatus, 'queued');
    expect(receipt.externalMessageId, isNull);
    expect(receipt.unsafeToFallback, isTrue);
    expect(receipt.copyWith(resolvedMessageText: 'Hola').isQueued, isTrue);
    expect(
        isDurableWhatsAppSendPayload({
          'ok': true,
          'accepted': true,
          'queued': true,
          'message_id': 'database-message',
        }),
        isFalse);
  });
  test('2xx contract needs explicit acceptance and both durable identifiers',
      () {
    expect(isDurableWhatsAppSendPayload(null), isFalse);
    expect(isDurableWhatsAppSendPayload({'ok': true}), isFalse);
    expect(
      isDurableWhatsAppSendPayload({
        'ok': true,
        'accepted': true,
        'message_id': 'message-1',
      }),
      isFalse,
    );
    expect(
      isDurableWhatsAppSendPayload({
        'ok': true,
        'accepted': true,
        'message_id': 'message-1',
        'external_message_id': 'wamid.1',
        'delivery_strategy': 'direct_send_utility',
      }),
      isTrue,
    );
  });

  test('ambiguous or provider-accepted failures prohibit manual fallback', () {
    expect(isUnsafeWhatsAppManualFallback({'outcome_unknown': true}), isTrue);
    expect(isUnsafeWhatsAppManualFallback({'provider_accepted': true}), isTrue);
    expect(isUnsafeWhatsAppManualFallback({'retry_safe': false}), isTrue);
    expect(isUnsafeWhatsAppManualFallback({'accepted': false}), isFalse);
  });

  test('durable payload becomes an immutable per-call receipt', () {
    final receipt = parseDurableWhatsAppSendReceipt(
      {
        'ok': true,
        'accepted': true,
        'message_id': 'message-1',
        'external_message_id': 'wamid.1',
        'delivery_strategy': 'direct_send_utility',
      },
      resolvedMessageText: 'hola',
    );

    expect(receipt.isSuccess, isTrue);
    expect(receipt.isDurable, isTrue);
    expect(receipt.deliveryMethod, WhatsAppDeliveryMethod.cloudApi);
    expect(receipt.messageId, 'message-1');
    expect(receipt.externalMessageId, 'wamid.1');
    expect(receipt.deliveryStrategy, 'direct_send_utility');
    expect(receipt.resolvedMessageText, 'hola');

    final second = receipt.copyWith(
      messageId: 'message-2',
      externalMessageId: 'wamid.2',
    );
    expect(receipt.messageId, 'message-1');
    expect(receipt.externalMessageId, 'wamid.1');
    expect(second.messageId, 'message-2');
    expect(second.externalMessageId, 'wamid.2');
  });

  test('failure policy belongs to the returned receipt', () {
    const tokenFailure = WhatsAppSendReceipt(
      deliveryMethod: WhatsAppDeliveryMethod.failed,
      errorCode: WhatsAppSendReceipt.expiredAccessTokenErrorCode,
    );
    const windowFailure = WhatsAppSendReceipt(
      deliveryMethod: WhatsAppDeliveryMethod.failed,
      errorCode: WhatsAppSendReceipt.reengagementErrorCode,
    );

    expect(tokenFailure.isSuccess, isFalse);
    expect(tokenFailure.errorRequiresServerFix, isTrue);
    expect(windowFailure.errorRequiresCustomerReply, isTrue);
  });
}
