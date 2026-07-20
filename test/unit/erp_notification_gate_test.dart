import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/erp_notification_gate.dart';

void main() {
  group('ErpNotificationGate', () {
    test('baseline rows are visible but never re-announced', () {
      final gate = ErpNotificationGate();
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');
      gate.rememberBaseline(const ['erp:old-1', 'erp:old-2']);

      expect(gate.claimPresentation('erp:old-1'), isFalse);
      expect(gate.claimPresentation('erp:new-1'), isTrue);
      expect(gate.claimPresentation('erp:new-1'), isFalse);
    });

    test('fails closed and resets only when user or tenant changes', () {
      final gate = ErpNotificationGate();

      expect(gate.claimPresentation('erp:row-1'), isFalse);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');
      expect(gate.claimPresentation('erp:row-1'), isTrue);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');
      expect(gate.claimPresentation('erp:row-1'), isFalse);

      gate.activateScope(userId: 'user-a', tenantId: 'tenant-b');
      expect(gate.claimPresentation('erp:row-1'), isTrue);
      gate.clearScope();
      expect(gate.claimPresentation('erp:row-2'), isFalse);
    });

    test('bounded memory evicts the oldest row inside one scope', () {
      final gate = ErpNotificationGate(maxRememberedEvents: 2);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      expect(gate.claimPresentation('erp:1'), isTrue);
      expect(gate.claimPresentation('erp:2'), isTrue);
      expect(gate.claimPresentation('erp:3'), isTrue);
      expect(gate.claimPresentation('erp:2'), isFalse);
      expect(gate.claimPresentation('erp:1'), isTrue);
    });
  });
}
