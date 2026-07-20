import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_command_idempotency_store.dart';

void main() {
  const firstKey = '11111111-1111-4111-8111-111111111111';
  const secondKey = '22222222-2222-4222-8222-222222222222';

  test('default adapter persists the opaque key in SharedPreferences',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = MessagingCommandIdempotencyStore(
      commandKeyFactory: () => firstKey,
    );

    await expectLater(
      store.execute(
        namespace: MessagingCommandNamespace.customerSupportRequest,
        userId: 'user-a',
        tenantId: 'tenant-a',
        fingerprintParts: const ['message'],
        command: (_) async => throw TimeoutException('keep pending'),
      ),
      throwsA(isA<TimeoutException>()),
    );

    final preferences = await SharedPreferences.getInstance();
    final key = preferences.getKeys().single;
    expect(
      key,
      matches(
        RegExp(
          r'^messaging-command-idempotency-v1:customer-support-request:[0-9a-f]{64}$',
        ),
      ),
    );
    expect(preferences.getString(key), firstKey);
  });

  test('lost acknowledgement reuses the durable key after process restart',
      () async {
    final persistence = _MemoryPersistence();
    var generated = 0;
    String keyFactory() => generated++ == 0 ? firstKey : secondKey;

    final firstProcess = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: keyFactory,
    );
    String? firstAttemptKey;

    await expectLater(
      firstProcess.execute(
        namespace: MessagingCommandNamespace.customerSupportRequest,
        userId: 'user-a',
        tenantId: 'tenant-a',
        fingerprintParts: const ['Necesito ayuda', 'job', 'job-1'],
        command: (commandKey) async {
          firstAttemptKey = commandKey;
          throw TimeoutException('server committed but ACK was lost');
        },
      ),
      throwsA(isA<TimeoutException>()),
    );

    expect(firstAttemptKey, firstKey);
    expect(persistence.values.values, contains(firstKey));

    final restartedProcess = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: keyFactory,
    );
    String? retryKey;
    final conversationId = await restartedProcess.execute(
      namespace: MessagingCommandNamespace.customerSupportRequest,
      userId: 'user-a',
      tenantId: 'tenant-a',
      fingerprintParts: const ['Necesito ayuda', 'job', 'job-1'],
      command: (commandKey) async {
        retryKey = commandKey;
        return 'conversation-1';
      },
    );

    expect(conversationId, 'conversation-1');
    expect(retryKey, firstKey);
    expect(generated, 1);
    expect(persistence.values, isEmpty);
  });

  test('preference key is hashed and contains no session or command PII',
      () async {
    final persistence = _MemoryPersistence();
    final store = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: () => firstKey,
    );

    await expectLater(
      store.execute(
        namespace: MessagingCommandNamespace.whatsappSupportOpen,
        userId: 'claudio.secret@example.com',
        tenantId: 'private-tenant-id',
        fingerprintParts: const [
          '+56 9 1234 5678',
          'Nombre Privado',
          'Mensaje confidencial',
        ],
        command: (_) async => throw TimeoutException('keep pending'),
      ),
      throwsA(isA<TimeoutException>()),
    );

    final preferenceKey = persistence.values.keys.single;
    expect(
      preferenceKey,
      matches(
        RegExp(
          r'^messaging-command-idempotency-v1:whatsapp-support-open:[0-9a-f]{64}$',
        ),
      ),
    );
    expect(preferenceKey, isNot(contains('claudio')));
    expect(preferenceKey, isNot(contains('private-tenant-id')));
    expect(preferenceKey, isNot(contains('1234')));
    expect(preferenceKey, isNot(contains('Nombre')));
    expect(preferenceKey, isNot(contains('Mensaje')));
    expect(persistence.values.values.single, firstKey);
  });

  test('namespace, user and tenant isolate otherwise identical commands',
      () async {
    final persistence = _MemoryPersistence();
    final generatedKeys = <String>[
      firstKey,
      secondKey,
      '33333333-3333-4333-8333-333333333333',
      '44444444-4444-4444-8444-444444444444',
      '55555555-5555-4555-8555-555555555555',
      '66666666-6666-4666-8666-666666666666',
    ].iterator;
    final store = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: () {
        generatedKeys.moveNext();
        return generatedKeys.current;
      },
    );

    Future<void> leavePending({
      required MessagingCommandNamespace namespace,
      required String userId,
      required String tenantId,
    }) async {
      await expectLater(
        store.execute(
          namespace: namespace,
          userId: userId,
          tenantId: tenantId,
          fingerprintParts: const ['same-input'],
          command: (_) async => throw TimeoutException('keep pending'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    }

    await leavePending(
      namespace: MessagingCommandNamespace.customerSupportRequest,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await leavePending(
      namespace: MessagingCommandNamespace.whatsappSupportOpen,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await leavePending(
      namespace: MessagingCommandNamespace.customerSupportRequest,
      userId: 'user-b',
      tenantId: 'tenant-a',
    );
    await leavePending(
      namespace: MessagingCommandNamespace.customerSupportRequest,
      userId: 'user-a',
      tenantId: 'tenant-b',
    );
    await leavePending(
      namespace: MessagingCommandNamespace.staffSupportCreate,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );
    await leavePending(
      namespace: MessagingCommandNamespace.staffInternalCreate,
      userId: 'user-a',
      tenantId: 'tenant-a',
    );

    expect(persistence.values, hasLength(6));
    expect(persistence.values.values.toSet(), hasLength(6));
  });

  test('identical concurrent callers share one remote command', () async {
    final persistence = _MemoryPersistence();
    final commandCompleter = Completer<String>();
    var remoteCalls = 0;
    var generatedKeys = 0;
    final store = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: () {
        generatedKeys += 1;
        return firstKey;
      },
    );

    Future<String> execute() => store.execute(
          namespace: MessagingCommandNamespace.whatsappSupportOpen,
          userId: 'user-a',
          tenantId: 'tenant-a',
          fingerprintParts: const ['56912345678', 'Cliente'],
          command: (_) {
            remoteCalls += 1;
            return commandCompleter.future;
          },
        );

    final first = execute();
    final second = execute();
    await Future<void>.delayed(Duration.zero);

    expect(remoteCalls, 1);
    expect(generatedKeys, 1);
    commandCompleter.complete('conversation-1');

    expect(await Future.wait([first, second]),
        ['conversation-1', 'conversation-1']);
    expect(persistence.values, isEmpty);
  });

  test('remote command never runs when the key cannot be persisted', () async {
    final persistence = _MemoryPersistence(failWrites: true);
    var remoteCalls = 0;
    final store = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: () => firstKey,
    );

    await expectLater(
      store.execute(
        namespace: MessagingCommandNamespace.customerSupportRequest,
        userId: 'user-a',
        tenantId: 'tenant-a',
        fingerprintParts: const ['message'],
        command: (_) async {
          remoteCalls += 1;
          return 'must-not-run';
        },
      ),
      throwsA(isA<MessagingCommandPersistenceException>()),
    );

    expect(remoteCalls, 0);
    expect(persistence.values, isEmpty);
  });

  test('cleanup failure retains the confirmed key for a safe replay', () async {
    final persistence = _MemoryPersistence(failRemovals: true);
    var generatedKeys = 0;
    final observedKeys = <String>[];
    final store = MessagingCommandIdempotencyStore(
      persistenceLoader: () async => persistence,
      commandKeyFactory: () {
        generatedKeys += 1;
        return firstKey;
      },
    );

    await expectLater(
      store.execute(
        namespace: MessagingCommandNamespace.customerSupportRequest,
        userId: 'user-a',
        tenantId: 'tenant-a',
        fingerprintParts: const ['message'],
        command: (commandKey) async {
          observedKeys.add(commandKey);
          return 'conversation-1';
        },
      ),
      throwsA(isA<MessagingCommandPersistenceException>()),
    );

    expect(persistence.values.values.single, firstKey);
    persistence.failRemovals = false;

    expect(
      await store.execute(
        namespace: MessagingCommandNamespace.customerSupportRequest,
        userId: 'user-a',
        tenantId: 'tenant-a',
        fingerprintParts: const ['message'],
        command: (commandKey) async {
          observedKeys.add(commandKey);
          return 'conversation-1';
        },
      ),
      'conversation-1',
    );
    expect(observedKeys, [firstKey, firstKey]);
    expect(generatedKeys, 1);
    expect(persistence.values, isEmpty);
  });
}

class _MemoryPersistence implements MessagingCommandKeyPersistence {
  _MemoryPersistence({
    this.failWrites = false,
    this.failRemovals = false,
  });

  final Map<String, String> values = {};
  bool failWrites;
  bool failRemovals;

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async {
    if (failRemovals) return false;
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    return true;
  }
}
