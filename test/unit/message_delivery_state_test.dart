import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/message.dart';
import 'package:vinabike_erp/modules/messaging/models/message_delivery_state.dart';

void main() {
  Message whatsappMessage({
    Map<String, dynamic> metadata = const {},
  }) {
    return Message(
      id: 'message-1',
      conversationId: 'conversation-1',
      content: 'Hola',
      type: 'text',
      metadata: <String, dynamic>{
        'external_provider': 'whatsapp',
        ...metadata,
      },
      createdAt: DateTime.utc(2026, 7, 19),
      isMe: true,
    );
  }

  group('MessageDeliveryState', () {
    test('database receipt is a first check, never provider delivery', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(metadata: const {'external_status': 'queued'}),
      );
      expect(state.stage, MessageDeliveryStage.queued);
    });
    test('queued receipt never hides a later failure or unknown outcome', () {
      for (final status in ['failed', 'outcome_unknown']) {
        final state = MessageDeliveryState.fromValues(
          metadata: {'whatsapp_status': status},
          explicitStatus: 'queued',
          isExternalTransport: true,
        );
        expect(
            state.stage,
            status == 'failed'
                ? MessageDeliveryStage.failed
                : MessageDeliveryStage.outcomeUnknown);
      }
    });
    test('keeps an optimistic WhatsApp message pending', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(metadata: const {'pending': true}),
      );

      expect(state.stage, MessageDeliveryStage.pending);
      expect(state.isVisible, isTrue);
    });

    test('maps provider sent to the one-check semantic stage', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(metadata: const {'external_status': 'sent'}),
      );

      // The shared indicator renders [sent] as one check. Double checks are
      // reserved for provider-confirmed delivery and read receipts.
      expect(state.stage, MessageDeliveryStage.sent);
      expect(state.stage, isNot(MessageDeliveryStage.delivered));
      expect(state.stage, isNot(MessageDeliveryStage.read));
    });

    test('maps provider delivered to the double-check delivery stage', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(metadata: const {'external_status': 'delivered'}),
      );

      expect(state.stage, MessageDeliveryStage.delivered);
    });

    test('confirmed provider evidence outranks stale optimistic metadata', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {
            'pending': true,
            'external_status': 'read',
          },
        ),
      );

      expect(state.stage, MessageDeliveryStage.read);
    });

    test('never infers read from a later customer reply', () {
      final replyOnly = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {
            'customer_replied_at': '2026-07-19T10:00:00Z',
            'has_later_inbound_message': true,
          },
        ),
      );
      final providerConfirmed = MessageDeliveryState.fromMessage(
        whatsappMessage(metadata: const {'external_status': 'read'}),
      );

      expect(replyOnly.stage, MessageDeliveryStage.none);
      expect(providerConfirmed.stage, MessageDeliveryStage.read);
    });

    test('preserves stronger positive provider evidence over a late failure',
        () {
      final state = MessageDeliveryState.fromValues(
        metadata: const {
          'external_provider': 'whatsapp',
          'whatsapp_status': 'delivered',
          'external_error_message': 'Late duplicate webhook',
        },
        explicitStatus: 'failed',
        isExternalTransport: true,
        providerLabel: 'WhatsApp',
      );

      expect(state.stage, MessageDeliveryStage.delivered);
      expect(state.failureMessage, isNull);
    });

    test('surfaces failure when there is no positive delivery evidence', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {
            'external_status': 'failed',
            'external_error_message': 'Número inválido',
          },
        ),
      );

      expect(state.stage, MessageDeliveryStage.failed);
      expect(state.failureMessage, contains('Número inválido'));
    });

    test('surfaces an ambiguous provider result without implying failure', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {'external_status': 'outcome_unknown'},
        ),
      );

      expect(state.stage, MessageDeliveryStage.outcomeUnknown);
      expect(state.failureMessage, contains('verifica'));
    });

    test('later provider evidence reconciles an ambiguous result', () {
      final state = MessageDeliveryState.fromValues(
        metadata: const {
          'external_provider': 'whatsapp',
          'whatsapp_status': 'accepted',
        },
        explicitStatus: 'outcome_unknown',
        isExternalTransport: true,
        providerLabel: 'WhatsApp',
      );

      expect(state.stage, MessageDeliveryStage.accepted);
    });

    test('uses Instagram provider evidence without inferring a receipt', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {
            'external_provider': 'instagram',
            'external_status': 'delivered',
          },
        ),
      );

      expect(state.stage, MessageDeliveryStage.delivered);
      expect(state.providerLabel, 'Instagram');
    });

    test('uses Messenger failure evidence and provider-specific copy', () {
      final state = MessageDeliveryState.fromMessage(
        whatsappMessage(
          metadata: const {
            'external_provider': 'facebook_messenger',
            'external_status': 'failed',
            'external_error_message': 'Ventana cerrada',
          },
        ),
      );

      expect(state.stage, MessageDeliveryStage.failed);
      expect(state.providerLabel, 'Messenger');
      expect(state.failureMessage, contains('Messenger'));
      expect(state.failureMessage, contains('Ventana cerrada'));
    });
  });
}
