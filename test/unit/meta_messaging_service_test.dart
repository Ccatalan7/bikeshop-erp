import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/services/meta_messaging_service.dart';

void main() {
  group('Meta send receipt contract', () {
    test('accepts only a durable provider and ERP receipt', () {
      final receipt = parseMetaSendPayload(
        const {
          'ok': true,
          'accepted': true,
          'provider_accepted': true,
          'message_id': 'message-1',
          'external_message_id': 'mid.123',
          'external_status': 'accepted',
        },
      );

      expect(receipt.outcome, MetaSendOutcome.accepted);
      expect(receipt.isDurable, isTrue);
      expect(receipt.messageId, 'message-1');
      expect(receipt.externalMessageId, 'mid.123');
    });

    test('treats malformed 2xx as unknown instead of retry-safe failure', () {
      final receipt = parseMetaSendPayload(
        const {'ok': true, 'accepted': true},
      );

      expect(receipt.outcome, MetaSendOutcome.outcomeUnknown);
      expect(receipt.isDurable, isFalse);
    });

    test('keeps a persistence-pending provider acceptance ambiguous', () {
      final receipt = parseMetaSendPayload(const {
        'ok': true,
        'accepted': true,
        'provider_accepted': true,
        'persistence_pending': true,
        'retry_safe': false,
        'message_id': null,
        'external_message_id': 'mid.pending',
      });

      expect(receipt.outcome, MetaSendOutcome.outcomeUnknown);
      expect(receipt.isDurable, isFalse);
      expect(receipt.externalMessageId, 'mid.pending');
    });

    test('preserves an explicit retry-safe provider rejection', () {
      final receipt = parseMetaSendPayload(const {
        'ok': false,
        'accepted': false,
        'provider_accepted': false,
        'outcome_unknown': false,
        'retry_safe': true,
        'error': {
          'code': 'reply_window_closed',
          'message': 'La ventana se cerró',
        },
      });

      expect(receipt.outcome, MetaSendOutcome.rejected);
      expect(receipt.replyWindowClosed, isTrue);
      expect(receipt.errorMessage, 'La ventana se cerró');
    });

    test('never turns a non-retry-safe response into a rejection', () {
      final receipt = parseMetaSendPayload(const {
        'ok': false,
        'accepted': false,
        'provider_accepted': false,
        'outcome_unknown': true,
        'retry_safe': false,
        'attempt_id': 'attempt-1',
      });

      expect(receipt.outcome, MetaSendOutcome.outcomeUnknown);
      expect(receipt.attemptId, 'attempt-1');
    });

    test('defaults text, empty, and generic failures to outcome unknown', () {
      for (final payload in <Object?>[
        null,
        '',
        'Bad gateway',
        const {
          'ok': false,
          'error': {'code': 'generic'}
        },
      ]) {
        final receipt = parseMetaSendPayload(payload);
        expect(
          receipt.outcome,
          MetaSendOutcome.outcomeUnknown,
          reason: 'Payload $payload has no complete rejection receipt.',
        );
      }
    });

    test('decodes an explicit rejection supplied as a JSON string', () {
      final receipt = parseMetaSendPayload('''
        {
          "retry_safe": true,
          "provider_accepted": false,
          "outcome_unknown": false,
          "error": {"code": "forbidden"}
        }
      ''');

      expect(receipt.outcome, MetaSendOutcome.rejected);
      expect(receipt.errorCode, 'forbidden');
    });
  });

  group('Meta outbound recovery receipts', () {
    Map<String, Object?> receiptJson(
      String state, {
      String actorId = 'user-1',
      String conversationId = 'conversation-1',
      String? messageId,
      String? externalMessageId,
    }) {
      return {
        'attempt_id': 'attempt-$state',
        'conversation_id': conversationId,
        'actor_id': actorId,
        'client_message_id': 'client-$state',
        'state': state,
        'message_text': 'Texto repetido',
        'message_id': messageId,
        'external_message_id': externalMessageId,
        'created_at': '2026-07-21T10:00:00Z',
        'updated_at': '2026-07-21T10:01:00Z',
      };
    }

    MetaOutboundSendReceipt receipt(
      String state, {
      String actorId = 'user-1',
      String? messageId,
      String? externalMessageId,
    }) {
      return MetaOutboundSendReceipt.fromJson(receiptJson(
        state,
        actorId: actorId,
        messageId: messageId,
        externalMessageId: externalMessageId,
      ))!;
    }

    test('invalidates the complete receipt snapshot when any row is malformed',
        () {
      expect(
        () => parseMetaOutboundSendReceiptsPayload(
          [
            receiptJson('prepared'),
            {'state': 'outcome_unknown'},
          ],
          conversationId: 'conversation-1',
        ),
        throwsFormatException,
      );
      expect(
        () => parseMetaOutboundSendReceiptsPayload(
          [receiptJson('prepared', conversationId: 'conversation-other')],
          conversationId: 'conversation-1',
        ),
        throwsFormatException,
      );
    });

    test('accepts a complete receipt snapshot with every recoverable state',
        () {
      final receipts = parseMetaOutboundSendReceiptsPayload(
        [
          receiptJson('prepared'),
          receiptJson('preflight_failed'),
          receiptJson('outcome_unknown'),
        ],
        conversationId: 'conversation-1',
      );

      expect(
        receipts.map((receipt) => receipt.state),
        [
          MetaOutboundAttemptState.prepared,
          MetaOutboundAttemptState.preflightFailed,
          MetaOutboundAttemptState.outcomeUnknown,
        ],
      );
    });

    test('reconstructs every unresolved state without claiming sent/read', () {
      final prepared = buildRecoveredMetaAttemptMessage(
        receipt: receipt('prepared'),
        channel: 'instagram',
        currentUserId: 'user-1',
      );
      final unknown = buildRecoveredMetaAttemptMessage(
        receipt: receipt('outcome_unknown'),
        channel: 'instagram',
        currentUserId: 'user-1',
      );
      final accepted = buildRecoveredMetaAttemptMessage(
        receipt: receipt(
          'provider_accepted',
          externalMessageId: 'mid.1',
        ),
        channel: 'facebook_messenger',
        currentUserId: 'user-1',
      );
      final rejected = buildRecoveredMetaAttemptMessage(
        receipt: receipt('provider_rejected'),
        channel: 'facebook_messenger',
        currentUserId: 'user-1',
      );
      final preflightFailed = buildRecoveredMetaAttemptMessage(
        receipt: receipt('preflight_failed'),
        channel: 'instagram',
        currentUserId: 'user-1',
      );

      expect(prepared.metadata['pending'], isFalse);
      expect(prepared.metadata['external_status'], 'outcome_unknown');
      expect(prepared.metadata['outcome_unknown'], isTrue);
      expect(prepared.metadata['retry_disabled'], isTrue);
      expect(unknown.metadata['external_status'], 'outcome_unknown');
      expect(accepted.metadata['external_status'], 'accepted');
      expect(accepted.metadata['server_ack_durable'], isFalse);
      expect(rejected.metadata['external_status'], 'failed');
      expect(preflightFailed.metadata['external_status'], 'failed');
      expect(preflightFailed.metadata['retry_disabled'], isFalse);
      for (final message in [
        prepared,
        unknown,
        accepted,
        rejected,
        preflightFailed,
      ]) {
        expect(message.metadata['recovered_outbound_attempt'], isTrue);
        expect(message.metadata['client_message_id'], isNotEmpty);
        expect(message.metadata['external_status'], isNot('sent'));
        expect(message.metadata['external_status'], isNot('delivered'));
        expect(message.metadata['external_status'], isNot('read'));
      }
    });

    test('provider accepted without external ID stays outcome unknown', () {
      final recovered = buildRecoveredMetaAttemptMessage(
        receipt: receipt('provider_accepted'),
        channel: 'instagram',
        currentUserId: 'user-1',
      );

      expect(recovered.metadata['external_status'], 'outcome_unknown');
      expect(recovered.metadata['retry_disabled'], isTrue);
    });

    test('attributes recovered attempts only to their exact actor', () {
      final ownAttempt = buildRecoveredMetaAttemptMessage(
        receipt: receipt('prepared', actorId: 'user-current'),
        channel: 'instagram',
        currentUserId: 'user-current',
      );
      final coworkerAttempt = buildRecoveredMetaAttemptMessage(
        receipt: receipt('outcome_unknown', actorId: 'user-coworker'),
        channel: 'instagram',
        currentUserId: 'user-current',
      );

      expect(ownAttempt.isMe, isTrue);
      expect(coworkerAttempt.isMe, isFalse);
      expect(coworkerAttempt.senderId, 'user-coworker');
    });

    test('finalized receipts are not reconstructed as optimistic bubbles', () {
      expect(
          receipt('finalized', messageId: 'message-1').shouldRecover, isFalse);
    });
  });

  group('Meta conversation transport', () {
    test('parses only the least-privilege reply-window fields', () {
      final transport = MetaConversationTransport.fromJson(const {
        'provider': 'instagram',
        'reply_window_expires_at': '2026-07-21T13:00:00Z',
        'can_reply': true,
      });

      expect(transport, isNotNull);
      expect(transport!.provider, 'instagram');
      expect(transport.replyWindowExpiresAt?.toUtc(),
          DateTime.utc(2026, 7, 21, 13));
      expect(transport.canReply, isTrue);
    });

    test('allows a closed transport without an expiry', () {
      final transport = MetaConversationTransport.fromJson(const {
        'provider': 'facebook_messenger',
        'reply_window_expires_at': null,
        'can_reply': false,
      });

      expect(transport, isNotNull);
      expect(transport!.replyWindowExpiresAt, isNull);
      expect(transport.canReply, isFalse);
    });

    test('rejects malformed or internally inconsistent transport rows', () {
      for (final row in <Map<String, Object?>>[
        const {
          'provider': 'instagram',
          'reply_window_expires_at': null,
          'can_reply': true,
        },
        const {
          'provider': 'unknown',
          'reply_window_expires_at': null,
          'can_reply': false,
        },
        const {
          'provider': 'instagram',
          'reply_window_expires_at': 'not-a-date',
          'can_reply': false,
        },
      ]) {
        expect(MetaConversationTransport.fromJson(row), isNull);
      }
    });
  });

  group('Meta standard reply window', () {
    final now = DateTime.utc(2026, 7, 21, 12);

    test('is open before 24 hours and closed at the boundary', () {
      expect(
        MetaMessagingService.isStandardReplyWindowOpen(
          now.subtract(const Duration(hours: 23, minutes: 59)),
          now: now,
        ),
        isTrue,
      );
      expect(
        MetaMessagingService.isStandardReplyWindowOpen(
          now.subtract(const Duration(hours: 24)),
          now: now,
        ),
        isFalse,
      );
      expect(
        MetaMessagingService.isStandardReplyWindowOpen(null, now: now),
        isFalse,
      );
    });

    test('future inbound timestamps fail closed beyond clock skew', () {
      expect(
        MetaMessagingService.isStandardReplyWindowOpen(
          now.add(const Duration(minutes: 2)),
          now: now,
        ),
        isTrue,
      );
      expect(
        MetaMessagingService.isStandardReplyWindowOpen(
          now.add(const Duration(minutes: 6)),
          now: now,
        ),
        isFalse,
      );
    });

    test('authoritative expiry opens only a plausible future window', () {
      expect(
        MetaMessagingService.isReplyWindowOpenFromExpiry(
          now.add(const Duration(hours: 1)),
          now: now,
        ),
        isTrue,
      );
      expect(
        MetaMessagingService.isReplyWindowOpenFromExpiry(
          now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        isFalse,
      );
      expect(
        MetaMessagingService.isReplyWindowOpenFromExpiry(
          now.add(const Duration(hours: 25)),
          now: now,
        ),
        isFalse,
      );
    });
  });
}
