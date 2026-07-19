import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/order_communication.dart';

void main() {
  test('communication model exposes operational evidence without send actions',
      () {
    final communication = OrderCommunication.fromJson({
      'id': 'outbox-1',
      'order_id': 'order-1',
      'message_kind': 'payment_confirmed',
      'template_version': 1,
      'recipient_email': 'customer@example.invalid',
      'subject': 'Pago confirmado',
      'delivery_mode': 'send',
      'state': 'delivered',
      'attempt_count': 1,
      'provider': 'resend',
      'provider_message_id': 'email-1',
      'created_at': '2026-07-18T18:00:00.000Z',
      'delivered_at': '2026-07-18T18:00:05.000Z',
    });

    expect(communication.messageLabel, 'Pago confirmado');
    expect(communication.isDryRun, isFalse);
    expect(communication.needsAttention, isFalse);
    expect(communication.deliveredAt, isNotNull);
  });

  test('failed communication is visible as requiring attention', () {
    final communication = OrderCommunication.fromJson({
      'id': 'outbox-2',
      'order_id': 'order-1',
      'message_kind': 'shipped',
      'recipient_email': 'customer@example.invalid',
      'subject': 'Pedido enviado',
      'delivery_mode': 'dry_run',
      'state': 'dead_letter',
      'attempt_count': 6,
      'created_at': '2026-07-18T18:00:00.000Z',
    });

    expect(communication.messageLabel, 'Pedido enviado');
    expect(communication.isDryRun, isTrue);
    expect(communication.needsAttention, isTrue);
  });
}
