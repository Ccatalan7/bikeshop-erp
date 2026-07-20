import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/chat_notification_gate.dart';

void main() {
  group('ChatNotificationGate', () {
    test('presents each stable event key only once', () {
      final gate = ChatNotificationGate(maxRememberedEvents: 4);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      expect(gate.claimPresentation('message-1'), isTrue);
      expect(gate.claimPresentation('message-1'), isFalse);
      expect(gate.claimPresentation('  message-1  '), isFalse);
      expect(gate.claimPresentation(''), isFalse);
    });

    test('evicts the oldest key when its bounded memory is full', () {
      final gate = ChatNotificationGate(maxRememberedEvents: 2);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      expect(gate.claimPresentation('message-1'), isTrue);
      expect(gate.claimPresentation('message-2'), isTrue);
      expect(gate.claimPresentation('message-3'), isTrue);

      expect(
        gate.claimPresentation('message-1'),
        isTrue,
        reason: 'the oldest key must be claimable again after eviction',
      );
    });

    test('reset starts a new presentation session', () {
      final gate = ChatNotificationGate(maxRememberedEvents: 2);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      expect(gate.claimPresentation('message-1'), isTrue);
      gate.reset();
      expect(gate.claimPresentation('message-1'), isTrue);
    });

    test('fails closed without scope and resets at an identity boundary', () {
      final gate = ChatNotificationGate();

      expect(gate.claimPresentation('message-1'), isFalse);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');
      expect(gate.claimPresentation('message-1'), isTrue);
      expect(gate.claimPresentation('message-1'), isFalse);

      gate.activateScope(userId: 'user-b', tenantId: 'tenant-a');
      expect(gate.claimPresentation('message-1'), isTrue);
      gate.clearScope();
      expect(gate.claimPresentation('message-2'), isFalse);
    });
  });
}
