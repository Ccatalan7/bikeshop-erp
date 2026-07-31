import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/services/website_seo_operations_service.dart';

/// These tests fix the rules that make a Google operation trustworthy:
///
/// * the client never invents success — a described failure stays a failure
///   even when it arrives with HTTP 200;
/// * an unauthorized or unconnected action reports a typed blocker with the
///   server's own reason, not a raw exception string; and
/// * no target (domain, property, account, feed) is composed client-side, so
///   the request body carries only an action name.
void main() {
  final clock = DateTime.utc(2026, 7, 28, 12, 30);

  WebsiteSeoOperationsService build(
    Future<({int status, Object? data})> Function(
      String function,
      Map<String, dynamic> body,
    ) invoke,
  ) {
    return WebsiteSeoOperationsService(invoke: invoke, clock: () => clock);
  }

  group('described failures are never promoted to success', () {
    test('a 200 carrying ok:false fails with the server message', () async {
      final service = build(
        (_, __) async => (
          status: 200,
          data: {
            'ok': false,
            'configured': false,
            'connectRequired': true,
            'error': 'Conecta Search Console antes de enviar el sitemap.',
          },
        ),
      );

      final result = await service.submitSitemap();

      expect(result.succeeded, isFalse);
      expect(
        result.humanMessage,
        'Conecta Search Console antes de enviar el sitemap.',
      );
      expect(result.blocker, WebsiteSeoOperationBlocker.notConnected);
    });

    test('a success never claims crawling or indexing', () async {
      final service = build((_, __) async => (status: 200, data: {'ok': true}));

      final result = await service.submitSitemap();

      expect(result.succeeded, isTrue);
      expect(result.observedAt, clock);
      expect(result.humanMessage, contains('No garantiza'));
      expect(result.blocker, isNull);
    });

    test('reconnectRequired outranks a generic connect hint', () async {
      final service = build(
        (_, __) async => (
          status: 200,
          data: {
            'ok': false,
            'configured': true,
            'reconnectRequired': true,
            'connectRequired': true,
          },
        ),
      );

      final result = await service.refreshMerchantFeed();

      expect(result.blocker, WebsiteSeoOperationBlocker.reconnectRequired);
    });
  });

  group('authorization failures stay typed', () {
    test('a 403 becomes notAuthorized, not a transport string', () async {
      final service = build(
        (_, __) async => (
          status: 403,
          data: {'error': 'Insufficient website settings permission'},
        ),
      );

      final result = await service.submitSitemap();

      expect(result.succeeded, isFalse);
      expect(result.blocker, WebsiteSeoOperationBlocker.notAuthorized);
      expect(
        result.blocker!.explanation,
        contains('no tiene permiso'),
      );
    });

    test('an unexpected throw never leaks the raw exception', () async {
      final service = build((_, __) async => throw StateError('boom'));

      final result = await service.submitSitemap();

      expect(result.succeeded, isFalse);
      expect(result.humanMessage, isNot(contains('boom')));
      expect(result.humanMessage, isNot(contains('StateError')));
    });
  });

  group('connection status', () {
    test('reports the backend-resolved property and account', () async {
      final service = build(
        (function, body) async {
          expect(function, WebsiteSeoOperationsService.oauthFunction);
          expect(body, {'action': 'status'});
          return (
            status: 200,
            data: {
              'connected': true,
              'connection': {
                'account_email': 'owner@example.cl',
                'site_url': 'sc-domain:example.cl',
              },
            },
          );
        },
      );

      final status = await service.connectionStatus();

      expect(status.connected, isTrue);
      expect(status.isAvailable, isTrue);
      expect(status.siteUrl, 'sc-domain:example.cl');
      expect(status.accountEmail, 'owner@example.cl');
    });

    test('an unreadable status is unavailable with a reason, not connected',
        () async {
      final service = build(
        (_, __) async => (status: 403, data: {'error': 'Unauthorized'}),
      );

      final status = await service.connectionStatus();

      expect(status.connected, isFalse);
      expect(status.isAvailable, isFalse);
      expect(status.blocker, WebsiteSeoOperationBlocker.notAuthorized);
      expect(status.unavailableReason, isNotEmpty);
    });
  });

  group('connection start', () {
    test('returns the backend URL and never composes one', () async {
      final service = build(
        (function, body) async {
          expect(function, WebsiteSeoOperationsService.oauthFunction);
          expect(body, {'action': 'start'});
          return (
            status: 200,
            data: {
              'authUrl': 'https://accounts.google.com/o/oauth2/v2/auth?x=1'
            },
          );
        },
      );

      final start = await service.startConnection();

      expect(start.isReady, isTrue);
      expect(start.authUrl!.host, 'accounts.google.com');
    });

    test('a refused start reports a reason instead of throwing', () async {
      final service = build(
        (_, __) async => (
          status: 403,
          data: {'error': 'Insufficient website settings permission'},
        ),
      );

      final start = await service.startConnection();

      expect(start.isReady, isFalse);
      expect(start.blocker, WebsiteSeoOperationBlocker.notAuthorized);
      expect(start.humanMessage, isNotEmpty);
    });

    test('a non-https authUrl is refused rather than opened', () async {
      final service = build(
        (_, __) async =>
            (status: 200, data: {'authUrl': 'javascript:alert(1)'}),
      );

      final start = await service.startConnection();

      expect(start.isReady, isFalse);
    });
  });

  test('no target is ever sent from the client', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = build((function, body) async {
      bodies.add(body);
      return (status: 200, data: {'ok': true});
    });

    await service.submitSitemap();
    await service.refreshMerchantFeed();

    expect(bodies, [
      {'action': 'submit_sitemap'},
      {'action': 'refresh_merchant_feed'},
    ]);
    for (final body in bodies) {
      expect(body.keys, ['action']);
    }
  });

  test('the production invoker translates FunctionException', () {
    // `functions_client` throws on every non-2xx instead of returning it, so
    // without this translation the typed blockers above are unreachable in
    // production and a 403 reaches the operator as raw exception text.
    final source = File(
      'lib/modules/website/services/website_seo_operations_service.dart',
    ).readAsStringSync();

    expect(source, contains('on FunctionException catch'));
    expect(source, contains('(status: error.status, data: error.details)'));
  });
}
