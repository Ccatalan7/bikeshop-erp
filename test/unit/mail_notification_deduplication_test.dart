import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/mail_notification_gate.dart';

void main() {
  group('MailNotificationGate', () {
    test('baseline messages never become new after disappearing and returning',
        () {
      final gate = MailNotificationGate();
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      gate.rememberInboxBaseline(const ['zoho:old-a', 'zoho:old-b']);

      expect(gate.claimInboxEvent('zoho:old-a'), isFalse);
      expect(gate.claimInboxEvent('zoho:new-c'), isTrue);
      expect(gate.claimInboxEvent('zoho:new-c'), isFalse);

      // Simulates a transient provider page omitting old-a before it reappears.
      expect(gate.claimInboxEvent('zoho:old-a'), isFalse);
    });

    test('several routed layouts can present one mail event only once', () {
      final gate = MailNotificationGate();
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      // The hidden workspace is subscribed first but cannot consume the key.
      expect(
        gate.claimPresentationForOwner(
          isActiveOwner: false,
          eventKey: 'inbox:zoho:message-1',
        ),
        isFalse,
      );
      expect(
        gate.claimPresentationForOwner(
          isActiveOwner: true,
          eventKey: 'inbox:zoho:message-1',
        ),
        isTrue,
      );
      expect(
        gate.claimPresentationForOwner(
          isActiveOwner: true,
          eventKey: 'inbox:zoho:message-1',
        ),
        isFalse,
      );
      expect(
        gate.claimPresentationForOwner(
          isActiveOwner: true,
          eventKey: 'inbox:zoho:message-2',
        ),
        isTrue,
      );
    });

    test('bounded memory evicts only the oldest handled event', () {
      final gate = MailNotificationGate(maxRememberedEvents: 2);
      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');

      expect(gate.claimPresentation('mail-1'), isTrue);
      expect(gate.claimPresentation('mail-2'), isTrue);
      expect(gate.claimPresentation('mail-3'), isTrue);
      expect(gate.claimPresentation('mail-2'), isFalse);
      expect(gate.claimPresentation('mail-1'), isTrue);
    });

    test('fails closed and forgets provider IDs when scope changes', () {
      final gate = MailNotificationGate();

      expect(gate.claimInboxEvent('zoho:message-1'), isFalse);
      expect(gate.claimPresentation('inbox:zoho:message-1'), isFalse);

      gate.activateScope(userId: 'user-a', tenantId: 'tenant-a');
      expect(gate.claimInboxEvent('zoho:message-1'), isTrue);
      expect(gate.claimPresentation('inbox:zoho:message-1'), isTrue);
      gate.activateScope(userId: 'user-b', tenantId: 'tenant-a');
      expect(gate.claimInboxEvent('zoho:message-1'), isTrue);
      expect(gate.claimPresentation('inbox:zoho:message-1'), isTrue);
    });

    test('mail manager and the stable workspace shell own notifications', () {
      final manager = File(
        'lib/modules/mail/providers/mail_account_manager.dart',
      ).readAsStringSync();
      final layout =
          File('lib/shared/widgets/main_layout.dart').readAsStringSync();
      final shell = File('lib/main.dart').readAsStringSync();
      final registry = File(
        'docs/architecture/canonical-ui-surfaces.md',
      ).readAsStringSync();

      expect(manager, contains('rememberInboxBaseline(previousKeys)'));
      expect(manager, contains('claimInboxEvent(_emailKey(email))'));
      expect(manager, contains('final inFlight = _refreshInboxFuture'));
      expect(shell, contains("'inbox:\${email.providerId}:\${email.id}'"));
      expect(shell, contains("'push:\$provider:\$stableEventId'"));
      expect(shell, contains('newEmailStream.listen(_handleNewEmail)'));
      expect(shell, contains('refreshInbox(background: true)'));
      expect(shell, contains('backgroundRefresh()'));
      expect(layout, isNot(contains('newEmailStream.listen')));
      expect(
          layout, isNot(contains("channel('erp_online_order_notifications')")));
      expect(layout, isNot(contains('_setupOnlineOrderNotifications')));
      expect(shell, contains("table: 'erp_notifications'"));
      expect(shell, contains('ErpNotificationGate.shared.rememberBaseline'));
      expect(registry, contains('process-wide stable-event gate'));
    });
  });
}
