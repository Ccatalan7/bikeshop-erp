import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/mail/providers/mail_account_manager.dart';

void main() {
  group('MailSessionTransition', () {
    test('does not publish the next user when cache invalidation fails',
        () async {
      String? activeUserId = 'user-a';
      var scopeReady = true;
      var transportTeardownAttempted = false;
      var committed = false;

      final transition = MailSessionTransition.run(
        nextUserId: 'user-b',
        invalidateSession: () {
          activeUserId = null;
          scopeReady = false;
        },
        unsubscribeTransport: () async {
          transportTeardownAttempted = true;
        },
        invalidateCache: () async {
          throw StateError('cache clear failed');
        },
        commitSession: (userId) {
          committed = true;
          activeUserId = userId;
          scopeReady = true;
        },
      );

      await expectLater(transition, throwsStateError);
      expect(transportTeardownAttempted, isTrue);
      expect(committed, isFalse);
      expect(activeUserId, isNull);
      expect(scopeReady, isFalse);
    });

    test('transport failure is tolerated but cache invalidation is mandatory',
        () async {
      final events = <String>[];
      String? activeUserId = 'user-a';
      Object? reportedTransportError;

      await MailSessionTransition.run(
        nextUserId: 'user-b',
        invalidateSession: () {
          activeUserId = null;
          events.add('scope-invalidated');
        },
        unsubscribeTransport: () async {
          events.add('transport-teardown');
          throw StateError('channel already closed');
        },
        invalidateCache: () async {
          events.add('cache-invalidated');
        },
        commitSession: (userId) {
          activeUserId = userId;
          events.add('scope-committed');
        },
        onTransportError: (error, _) {
          reportedTransportError = error;
          events.add('transport-error-tolerated');
        },
      );

      expect(activeUserId, 'user-b');
      expect(reportedTransportError, isA<StateError>());
      expect(events.first, 'scope-invalidated');
      expect(
        events.indexOf('scope-committed'),
        greaterThan(events.indexOf('cache-invalidated')),
      );
      expect(
        events.indexOf('scope-committed'),
        greaterThan(events.indexOf('transport-error-tolerated')),
      );
    });

    test('does not commit while transport teardown is still pending', () async {
      final teardown = Completer<void>();
      String? activeUserId = 'user-a';

      final transition = MailSessionTransition.run(
        nextUserId: 'user-b',
        invalidateSession: () => activeUserId = null,
        unsubscribeTransport: () => teardown.future,
        invalidateCache: () async {},
        commitSession: (userId) => activeUserId = userId,
      );

      await Future<void>.delayed(Duration.zero);
      expect(activeUserId, isNull);

      teardown.complete();
      await transition;
      expect(activeUserId, 'user-b');
    });
  });
}
