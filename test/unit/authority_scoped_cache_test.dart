import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

void main() {
  group('AuthorityCacheScope.resolve', () {
    test('keeps an exact user and tenant identity unchanged', () {
      final scope = AuthorityCacheScope()
        ..bind(userId: 'user-a', tenantId: 'tenant-a');
      final generation = scope.generation;

      final resolution = scope.resolve(
        userId: ' user-a ',
        tenantId: ' tenant-a ',
      );

      expect(resolution, AuthorityScopeResolution.unchanged);
      expect(resolution.isAccepted, isTrue);
      expect(resolution.didChange, isFalse);
      expect(scope.generation, generation);
    });

    test('clears and rejects a tenant change for the same user', () {
      final scope = AuthorityCacheScope()
        ..bind(userId: 'user-a', tenantId: 'tenant-b');
      final generation = scope.generation;

      final rejected = scope.resolve(
        userId: 'user-a',
        tenantId: 'tenant-a',
      );

      expect(rejected, AuthorityScopeResolution.rejectedTenantChange);
      expect(rejected.isAccepted, isFalse);
      expect(scope.key, isNull);
      expect(scope.generation, generation + 1);

      final coherentRetry = scope.resolve(
        userId: 'user-a',
        tenantId: 'tenant-a',
      );
      expect(coherentRetry, AuthorityScopeResolution.rebound);
      expect(scope.key?.tenantId, 'tenant-a');
    });

    test('allows a different authenticated user to establish its tenant', () {
      final scope = AuthorityCacheScope()
        ..bind(userId: 'user-a', tenantId: 'tenant-a');

      final resolution = scope.resolve(
        userId: 'user-b',
        tenantId: 'tenant-b',
      );

      expect(resolution, AuthorityScopeResolution.rebound);
      expect(resolution.isAccepted, isTrue);
      expect(scope.key?.userId, 'user-b');
      expect(scope.key?.tenantId, 'tenant-b');
    });
  });

  group('AuthorityScopedLoad', () {
    test('B publishes first and a late A result cannot overwrite it', () async {
      final scope = AuthorityCacheScope();
      final load = AuthorityScopedLoad<String>(scope);
      final tenantA = Completer<String>();
      final tenantB = Completer<String>();
      String? published;

      scope.bind(userId: 'user-a', tenantId: 'tenant-a');
      final requestA = load.run(
        load: (_) => tenantA.future,
        publish: (value, _) => published = value,
      );
      final requestAFailure = expectLater(
        requestA,
        throwsA(isA<AuthorityScopeChangedException>()),
      );

      scope.bind(userId: 'user-b', tenantId: 'tenant-b');
      load.detach();
      final requestB = load.run(
        load: (_) => tenantB.future,
        publish: (value, _) => published = value,
      );

      tenantB.complete('B');
      expect(await requestB, 'B');
      expect(published, 'B');

      tenantA.complete('A');
      await requestAFailure;
      expect(published, 'B');
    });

    test('sign-out clears ownership before a pending result completes',
        () async {
      final scope = AuthorityCacheScope();
      final load = AuthorityScopedLoad<String>(scope);
      final pending = Completer<String>();
      String? published;

      scope.bind(userId: 'user-a', tenantId: 'tenant-a');
      final request = load.run(
        load: (_) => pending.future,
        publish: (value, _) => published = value,
      );
      final failure = expectLater(
        request,
        throwsA(isA<AuthorityScopeChangedException>()),
      );

      scope.bind(userId: null, tenantId: null);
      load.detach();
      expect(scope.capture(), isNull);

      pending.complete('stale A');
      await failure;
      expect(published, isNull);
    });

    test('detaching invalidates an old request within the same authority',
        () async {
      final scope = AuthorityCacheScope();
      final load = AuthorityScopedLoad<String>(scope);
      final oldRequestCompleter = Completer<String>();
      final newRequestCompleter = Completer<String>();
      String? published;

      scope.bind(userId: 'user-a', tenantId: 'tenant-a');
      final oldRequest = load.run(
        load: (_) => oldRequestCompleter.future,
        publish: (value, _) => published = value,
      );
      final oldFailure = expectLater(
        oldRequest,
        throwsA(isA<AuthorityScopeChangedException>()),
      );

      load.detach();
      final newRequest = load.run(
        load: (_) => newRequestCompleter.future,
        publish: (value, _) => published = value,
      );
      newRequestCompleter.complete('fresh');
      expect(await newRequest, 'fresh');

      oldRequestCompleter.complete('stale');
      await oldFailure;
      expect(published, 'fresh');
    });

    test('same-generation callers share exactly one in-flight request',
        () async {
      final scope = AuthorityCacheScope();
      final load = AuthorityScopedLoad<String>(scope);
      final pending = Completer<String>();
      var starts = 0;

      scope.bind(userId: 'user-a', tenantId: 'tenant-a');
      Future<String> start(AuthorityCacheLease _) {
        starts++;
        return pending.future;
      }

      final first = load.run(load: start, publish: (_, __) {});
      final second = load.run(load: start, publish: (_, __) {});

      expect(identical(first, second), isTrue);
      expect(starts, 1);
      pending.complete('shared');
      expect(await Future.wait([first, second]), ['shared', 'shared']);
    });

    test('independent preload owners start concurrently under Future.wait',
        () async {
      final scope = AuthorityCacheScope()
        ..bind(userId: 'user-a', tenantId: 'tenant-a');
      final completers = List.generate(7, (_) => Completer<int>());
      final loads = List.generate(
        completers.length,
        (_) => AuthorityScopedLoad<int>(scope),
      );
      var starts = 0;

      final requests = List.generate(completers.length, (index) {
        return loads[index].run(
          load: (_) {
            starts++;
            return completers[index].future;
          },
          publish: (_, __) {},
        );
      });

      expect(starts, completers.length);
      for (var index = 0; index < completers.length; index++) {
        completers[index].complete(index);
      }
      expect(
        await Future.wait(requests),
        List.generate(completers.length, (index) => index),
      );
    });
  });
}
