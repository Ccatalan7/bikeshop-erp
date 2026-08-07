import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_tool_registry.dart';

void main() {
  group('AIToolAuthority', () {
    test('audit identity survives role and permission changes', () {
      final before = AIToolAuthority(
        userId: 'user-1',
        tenantId: 'tenant-1',
        role: 'mechanic',
        permissions: const <String>{'jobs.read'},
      );
      final after = AIToolAuthority(
        userId: 'user-1',
        tenantId: 'tenant-1',
        role: 'manager',
        permissions: const <String>{'jobs.read', 'sales.read'},
      );
      final otherActor = AIToolAuthority(
        userId: 'user-2',
        tenantId: 'tenant-1',
        role: 'manager',
        permissions: const <String>{'jobs.read', 'sales.read'},
      );

      expect(before.auditScopeHash, after.auditScopeHash);
      expect(before.auditScopeHash, isNot(otherActor.auditScopeHash));
    });
  });

  group('AIToolInputSchema', () {
    test('rejects open object schemas at every depth', () {
      expect(
        () => AIToolInputSchema.fromJson(const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        }),
        throwsArgumentError,
      );
      expect(
        () => AIToolInputSchema.fromJson(const <String, Object?>{
          'type': 'object',
          'additionalProperties': false,
          'properties': <String, Object?>{
            'filter': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
          },
        }),
        throwsArgumentError,
      );
    });

    test('validates required fields, types, and additional properties', () {
      final schema = AIToolInputSchema.closedObject(
        properties: const <String, Object?>{
          'query': <String, Object?>{
            'type': 'string',
            'minLength': 2,
            'maxLength': 8,
          },
          'limit': <String, Object?>{
            'type': <Object?>['integer', 'null'],
          },
        },
        required: const <String>['query', 'limit'],
      );

      expect(schema.accepts(const {'query': 'cadena', 'limit': 2}), isTrue);
      expect(schema.accepts(const {'query': 'cadena', 'limit': null}), isTrue);
      expect(schema.accepts(const {'query': 'cadena'}), isFalse);
      expect(schema.accepts(const {'limit': 2}), isFalse);
      expect(schema.accepts(const {'query': 'cadena', 'limit': '2'}), isFalse);
      expect(schema.accepts(const {'query': 'x', 'limit': 2}), isFalse);
      expect(schema.accepts(const {'query': 'demasiado largo', 'limit': 2}),
          isFalse);
      expect(
          schema.accepts(const {'query': 'cadena', 'secret': true}), isFalse);
      expect(schema.json['additionalProperties'], isFalse);
    });

    test('requires every property schema to declare a closed JSON type', () {
      expect(
        () => AIToolInputSchema.closedObject(
          properties: const <String, Object?>{
            'query': <String, Object?>{
              'description': 'A description is not a runtime type.',
            },
          },
          required: const <String>['query'],
        ),
        throwsArgumentError,
      );
    });

    test('enforces enum, numeric, string, array, and integer constraints', () {
      final schema = AIToolInputSchema.closedObject(
        properties: const <String, Object?>{
          'period': <String, Object?>{
            'type': 'string',
            'enum': <Object?>['hoy', 'manana'],
            'pattern': r'^[a-z]+$',
          },
          'limit': <String, Object?>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 10,
          },
          'tags': <String, Object?>{
            'type': 'array',
            'minItems': 1,
            'maxItems': 2,
            'items': <String, Object?>{'type': 'string'},
          },
        },
        required: const <String>['period', 'limit', 'tags'],
      );

      expect(
        schema.accepts(const <String, Object?>{
          'period': 'hoy',
          'limit': 3.0,
          'tags': <Object?>['taller'],
        }),
        isTrue,
      );
      expect(
        schema.accepts(const <String, Object?>{
          'period': 'ayer',
          'limit': 3,
          'tags': <Object?>['taller'],
        }),
        isFalse,
      );
      expect(
        schema.accepts(const <String, Object?>{
          'period': 'hoy',
          'limit': 11,
          'tags': <Object?>['taller'],
        }),
        isFalse,
      );
      expect(
        schema.accepts(const <String, Object?>{
          'period': 'hoy',
          'limit': 3.5,
          'tags': <Object?>['taller'],
        }),
        isFalse,
      );
      expect(
        schema.accepts(const <String, Object?>{
          'period': 'hoy',
          'limit': 3,
          'tags': <Object?>[],
        }),
        isFalse,
      );
    });
  });

  group('AIToolDefinition', () {
    test('write definitions cannot remove approval or idempotency', () {
      expect(
        () => _definition(
          name: 'create_task',
          risk: AIToolRiskLevel.reversibleWrite,
          requiresApproval: false,
          idempotency: AIToolIdempotencyPolicy.required,
        ),
        throwsArgumentError,
      );
      expect(
        () => _definition(
          name: 'create_task',
          requiredPermissions: const {'tasks.write'},
          risk: AIToolRiskLevel.reversibleWrite,
          requiresApproval: true,
          idempotency: AIToolIdempotencyPolicy.required,
          requiresReadBack: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => _definition(
          name: 'create_task',
          risk: AIToolRiskLevel.reversibleWrite,
          requiresApproval: true,
          idempotency: AIToolIdempotencyPolicy.optional,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AIToolRegistry', () {
    test('rejects duplicate stable names', () {
      final definition = _definition(name: 'search_inventory');
      final registration = AIToolRegistration(
        definition: definition,
        executor: _successfulExecutor,
      );

      expect(
        () => AIToolRegistry(registrations: [registration, registration]),
        throwsA(
          isA<AIToolRegistryException>().having(
            (error) => error.code,
            'code',
            AIToolFailureCode.duplicateTool,
          ),
        ),
      );
    });

    test('announces only permitted tools and rechecks before execution',
        () async {
      var executions = 0;
      final registry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(
              name: 'search_inventory',
              requiredPermissions: const {'inventory.read'},
            ),
            executor: (context) async {
              executions++;
              return _successfulExecutor(context);
            },
          ),
        ],
      );
      final unauthorized = _authority(permissions: const <String>{});

      expect(registry.advertisedToolsFor(unauthorized), isEmpty);
      final error = await _executionError(
        registry.execute(
          toolName: 'search_inventory',
          arguments: const {'query': 'cadena'},
          authority: unauthorized,
        ),
      );
      expect(error.code, AIToolFailureCode.unauthorized);
      expect(executions, 0);

      final advertised = registry.advertisedToolsFor(
        _authority(permissions: const {'inventory.read'}),
      );
      expect(advertised.map((tool) => tool.name), ['search_inventory']);
      expect(advertised.single.inputSchema['additionalProperties'], isFalse);
    });

    test('unknown tool and invalid arguments fail before the executor',
        () async {
      var executions = 0;
      final registry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'search_inventory'),
            executor: (context) async {
              executions++;
              return _successfulExecutor(context);
            },
          ),
        ],
      );

      final unknown = await _executionError(
        registry.execute(
          toolName: 'steal_api_key',
          arguments: const <String, Object?>{},
          authority: _authority(),
        ),
      );
      expect(unknown.code, AIToolFailureCode.unknownTool);
      expect(unknown.receipt.toolName, 'unknown_tool');
      expect(unknown.toString(), isNot(contains('steal_api_key')));

      final invalid = await _executionError(
        registry.execute(
          toolName: 'search_inventory',
          arguments: const {'query': 'cadena', 'extra': 'not allowed'},
          authority: _authority(),
        ),
      );
      expect(invalid.code, AIToolFailureCode.invalidArguments);
      expect(executions, 0);
    });

    test('executor output is deeply detached before it reaches the model',
        () async {
      final sourceItems = <Object?>['one'];
      final registry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'detached_output'),
            executor: (context) async => AIToolExecutorResult(
              data: <String, Object?>{'items': sourceItems},
              resultCount: 1,
            ),
          ),
        ],
      );

      final execution = await registry.execute(
        toolName: 'detached_output',
        arguments: const {'query': 'cadena'},
        authority: _authority(),
      );
      sourceItems.add('two');

      expect(execution.data['items'], const ['one']);
      expect(
        () => (execution.data['items']! as List<Object?>).add('three'),
        throwsUnsupportedError,
      );
    });

    test('write requires idempotency and a matching unexpired approval',
        () async {
      final now = DateTime.utc(2026, 8, 4, 20);
      final authority = _authority(permissions: const {'tasks.write'});
      final definition = _definition(
        name: 'create_task',
        requiredPermissions: const {'tasks.write'},
        risk: AIToolRiskLevel.reversibleWrite,
        requiresApproval: true,
        idempotency: AIToolIdempotencyPolicy.required,
        requiresReadBack: true,
      );
      var executions = 0;
      final registry = AIToolRegistry(
        now: () => now,
        approvalVerifier: const _TestApprovalVerifier(),
        registrations: [
          AIToolRegistration(
            definition: definition,
            executor: (context) async {
              executions++;
              expect(context.idempotencyKey, 'operation-1');
              return AIToolExecutorResult(
                data: const {'taskId': 'task-1'},
                resultCount: 1,
                readBackVerified: true,
              );
            },
          ),
        ],
      );

      final missingKey = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
        ),
      );
      expect(missingKey.code, AIToolFailureCode.idempotencyKeyRequired);

      final missingApproval = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
          idempotencyKey: 'operation-1',
        ),
      );
      expect(missingApproval.code, AIToolFailureCode.approvalRequired);
      expect(executions, 0);

      final result = await registry.execute(
        toolName: definition.name,
        arguments: const {'query': 'llamar cliente'},
        authority: authority,
        idempotencyKey: 'operation-1',
        approval: AIToolApproval(
          approvalId: 'approval-secret-reference',
          toolName: definition.name,
          toolVersion: definition.version,
          userId: authority.userId,
          tenantId: authority.tenantId,
          arguments: const {'query': 'llamar cliente'},
          idempotencyKey: 'operation-1',
          expiresAt: now.add(const Duration(minutes: 5)),
        ),
      );

      expect(result.data, const {'taskId': 'task-1'});
      expect(result.receipt.status, AIToolReceiptStatus.succeeded);
      expect(result.receipt.approvalUsed, isTrue);
      expect(result.receipt.idempotencyUsed, isTrue);
      expect(result.receipt.readBackVerified, isTrue);
      final serializedReceipt = jsonEncode(result.receipt.toAuditJson());
      expect(serializedReceipt, isNot(contains(authority.userId)));
      expect(serializedReceipt, isNot(contains(authority.tenantId)));
      expect(result.receipt.authorityScopeHash, hasLength(64));
      expect(serializedReceipt, isNot(contains('approval-secret-reference')));
      expect(serializedReceipt, isNot(contains('operation-1')));
      expect(serializedReceipt, isNot(contains('llamar cliente')));
      expect(serializedReceipt, isNot(contains('task-1')));

      final replay = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
          idempotencyKey: 'operation-1',
          approval: AIToolApproval(
            approvalId: 'approval-secret-reference',
            toolName: definition.name,
            toolVersion: definition.version,
            userId: authority.userId,
            tenantId: authority.tenantId,
            arguments: const {'query': 'llamar cliente'},
            idempotencyKey: 'operation-1',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
        ),
      );
      expect(replay.code, AIToolFailureCode.approvalRequired);

      final changedArguments = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'otra tarea'},
          authority: authority,
          idempotencyKey: 'operation-2',
          approval: AIToolApproval(
            approvalId: 'approval-for-original-payload',
            toolName: definition.name,
            toolVersion: definition.version,
            userId: authority.userId,
            tenantId: authority.tenantId,
            arguments: const {'query': 'llamar cliente'},
            idempotencyKey: 'operation-1',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
        ),
      );
      expect(changedArguments.code, AIToolFailureCode.approvalRequired);
    });

    test('policy can deny discovery and elevate approval', () async {
      final registry = AIToolRegistry(
        policy: const _ApprovalPolicy(),
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'search_inventory'),
            executor: _successfulExecutor,
          ),
          AIToolRegistration(
            definition: _definition(name: 'blocked_tool'),
            executor: _successfulExecutor,
          ),
        ],
      );
      final authority = _authority();

      expect(
        registry.advertisedToolsFor(authority).map((tool) => tool.name),
        ['search_inventory'],
      );
      final error = await _executionError(
        registry.execute(
          toolName: 'search_inventory',
          arguments: const {'query': 'cadena'},
          authority: authority,
        ),
      );
      expect(error.code, AIToolFailureCode.approvalRequired);

      final hidden = await _executionError(
        registry.execute(
          toolName: 'blocked_tool',
          arguments: const {'query': 'cadena'},
          authority: authority,
        ),
      );
      expect(hidden.code, AIToolFailureCode.unauthorized);
    });

    test('client-constructed approval is rejected without a server verifier',
        () async {
      final now = DateTime.utc(2026, 8, 4, 20);
      final authority = _authority(permissions: const {'tasks.write'});
      final definition = _definition(
        name: 'create_task',
        requiredPermissions: const {'tasks.write'},
        risk: AIToolRiskLevel.reversibleWrite,
        requiresApproval: true,
        idempotency: AIToolIdempotencyPolicy.required,
        requiresReadBack: true,
      );
      final registry = AIToolRegistry(
        now: () => now,
        registrations: <AIToolRegistration>[
          AIToolRegistration(
            definition: definition,
            executor: _successfulExecutor,
          ),
        ],
      );

      final error = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
          idempotencyKey: 'operation-1',
          approval: AIToolApproval(
            approvalId: 'fabricated-in-client',
            toolName: definition.name,
            toolVersion: definition.version,
            userId: authority.userId,
            tenantId: authority.tenantId,
            arguments: const {'query': 'llamar cliente'},
            idempotencyKey: 'operation-1',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
        ),
      );

      expect(error.code, AIToolFailureCode.approvalRequired);
    });

    test('expired execution budget never starts approval or executor',
        () async {
      final now = DateTime.utc(2026, 8, 4, 20);
      final authority = _authority(permissions: const {'tasks.write'});
      final definition = _definition(
        name: 'create_task',
        requiredPermissions: const {'tasks.write'},
        risk: AIToolRiskLevel.reversibleWrite,
        requiresApproval: true,
        idempotency: AIToolIdempotencyPolicy.required,
        requiresReadBack: true,
      );
      var executions = 0;
      final verifier = _CountingApprovalVerifier();
      final registry = AIToolRegistry(
        now: () => now,
        approvalVerifier: verifier,
        registrations: <AIToolRegistration>[
          AIToolRegistration(
            definition: definition,
            executor: (context) async {
              executions++;
              return AIToolExecutorResult(
                data: const {'taskId': 'task-1'},
                resultCount: 1,
                readBackVerified: true,
              );
            },
          ),
        ],
      );
      final approval = AIToolApproval(
        approvalId: 'approval-zero-budget',
        toolName: definition.name,
        toolVersion: definition.version,
        userId: authority.userId,
        tenantId: authority.tenantId,
        arguments: const {'query': 'llamar cliente'},
        idempotencyKey: 'operation-zero',
        expiresAt: now.add(const Duration(minutes: 5)),
      );

      final error = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
          idempotencyKey: 'operation-zero',
          approval: approval,
          executionTimeout: Duration.zero,
        ),
      );

      expect(error.code, AIToolFailureCode.timeout);
      expect(verifier.calls, 0);
      expect(executions, 0);
    });

    test('approval latency is deducted before the executor can start',
        () async {
      final now = DateTime.utc(2026, 8, 4, 20);
      final authority = _authority(permissions: const {'tasks.write'});
      final definition = _definition(
        name: 'create_task',
        requiredPermissions: const {'tasks.write'},
        risk: AIToolRiskLevel.reversibleWrite,
        requiresApproval: true,
        idempotency: AIToolIdempotencyPolicy.required,
        requiresReadBack: true,
      );
      var executions = 0;
      final verifier = _CountingApprovalVerifier(
        // Márgenes holgados a propósito: lo que el test afirma es que la
        // latencia de aprobación se descuenta del presupuesto, no que el reloj
        // real acierte al milisegundo. Con 10 ms contra 2 ms, un corredor
        // cargado agotaba el presupuesto ANTES de invocar al verificador y el
        // test fallaba sin que nada estuviera roto (2026-08-07, al partir la
        // suite en cuatro procesos paralelos).
        delay: const Duration(milliseconds: 400),
      );
      final registry = AIToolRegistry(
        now: () => now,
        approvalVerifier: verifier,
        registrations: <AIToolRegistration>[
          AIToolRegistration(
            definition: definition,
            executor: (context) async {
              executions++;
              return AIToolExecutorResult(
                data: const {'taskId': 'task-1'},
                resultCount: 1,
                readBackVerified: true,
              );
            },
          ),
        ],
      );

      final error = await _executionError(
        registry.execute(
          toolName: definition.name,
          arguments: const {'query': 'llamar cliente'},
          authority: authority,
          idempotencyKey: 'operation-slow-approval',
          approval: AIToolApproval(
            approvalId: 'approval-slow-budget',
            toolName: definition.name,
            toolVersion: definition.version,
            userId: authority.userId,
            tenantId: authority.tenantId,
            arguments: const {'query': 'llamar cliente'},
            idempotencyKey: 'operation-slow-approval',
            expiresAt: now.add(const Duration(minutes: 5)),
          ),
          executionTimeout: const Duration(milliseconds: 80),
        ),
      );

      expect(error.code, AIToolFailureCode.timeout);
      expect(verifier.calls, 1);
      expect(executions, 0);
    });

    test('timeout and executor failures expose only fixed sanitized copy',
        () async {
      final slowCompleter = Completer<AIToolExecutorResult>();
      final timeoutRegistry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(
              name: 'slow_tool',
              timeout: const Duration(milliseconds: 5),
              allowsParallelExecution: false,
            ),
            executor: (context) => slowCompleter.future,
          ),
        ],
      );
      final timeout = await _executionError(
        timeoutRegistry.execute(
          toolName: 'slow_tool',
          arguments: const {'query': 'cadena'},
          authority: _authority(),
        ),
      );
      expect(timeout.code, AIToolFailureCode.timeout);
      expect(timeout.receipt.status, AIToolReceiptStatus.timedOut);

      final retryWhileUnderlyingWorkIsActive = await _executionError(
        timeoutRegistry.execute(
          toolName: 'slow_tool',
          arguments: const {'query': 'cadena'},
          authority: _authority(),
          executionTimeout: const Duration(milliseconds: 2),
        ),
      );
      expect(
        retryWhileUnderlyingWorkIsActive.code,
        AIToolFailureCode.concurrentExecutionDenied,
      );

      slowCompleter.complete(
        AIToolExecutorResult(
          data: const {'items': <Object?>[]},
          resultCount: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final retryAfterUnderlyingWorkSettles = await timeoutRegistry.execute(
        toolName: 'slow_tool',
        arguments: const {'query': 'cadena'},
        authority: _authority(),
      );
      expect(
        retryAfterUnderlyingWorkSettles.receipt.status,
        AIToolReceiptStatus.succeeded,
      );

      final failureRegistry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'failing_tool'),
            executor: (context) async =>
                throw StateError('server-key-is-super-secret'),
          ),
        ],
      );
      final failure = await _executionError(
        failureRegistry.execute(
          toolName: 'failing_tool',
          arguments: const {'query': 'cadena'},
          authority: _authority(),
        ),
      );
      expect(failure.code, AIToolFailureCode.executionFailed);
      expect(failure.toString(), isNot(contains('server-key-is-super-secret')));
      expect(
        jsonEncode(failure.receipt.toAuditJson()),
        isNot(contains('server-key-is-super-secret')),
      );
    });

    test('result and byte limits reject oversized output', () async {
      final resultLimitRegistry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'too_many', maxResults: 1),
            executor: (context) async => AIToolExecutorResult(
              data: const {
                'items': [1, 2]
              },
              resultCount: 2,
            ),
          ),
        ],
      );
      final tooMany = await _executionError(
        resultLimitRegistry.execute(
          toolName: 'too_many',
          arguments: const {'query': 'cadena'},
          authority: _authority(),
        ),
      );
      expect(tooMany.code, AIToolFailureCode.oversizedOutput);
      expect(tooMany.receipt.status, AIToolReceiptStatus.failed);

      final byteLimitRegistry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(name: 'too_large', maxOutputBytes: 8),
            executor: (context) async => AIToolExecutorResult(
              data: const {'value': 'contenido largo'},
              resultCount: 1,
            ),
          ),
        ],
      );
      final tooLarge = await _executionError(
        byteLimitRegistry.execute(
          toolName: 'too_large',
          arguments: const {'query': 'cadena'},
          authority: _authority(),
        ),
      );
      expect(tooLarge.code, AIToolFailureCode.oversizedOutput);
      expect(tooLarge.receipt.status, AIToolReceiptStatus.failed);
    });

    test('non-parallel tools reject overlap until the executor finishes',
        () async {
      final completer = Completer<AIToolExecutorResult>();
      final registry = AIToolRegistry(
        registrations: [
          AIToolRegistration(
            definition: _definition(
              name: 'single_flight',
              allowsParallelExecution: false,
              timeout: const Duration(seconds: 1),
            ),
            executor: (context) => completer.future,
          ),
        ],
      );
      final first = registry.execute(
        toolName: 'single_flight',
        arguments: const {'query': 'primera'},
        authority: _authority(),
      );
      await Future<void>.delayed(Duration.zero);
      final overlap = await _executionError(
        registry.execute(
          toolName: 'single_flight',
          arguments: const {'query': 'segunda'},
          authority: _authority(),
        ),
      );
      expect(overlap.code, AIToolFailureCode.concurrentExecutionDenied);

      completer.complete(await _successfulExecutor(
        AIToolExecutionContext(
          definition: _definition(name: 'single_flight'),
          authority: _authority(),
          arguments: const {'query': 'primera'},
          idempotencyKey: null,
        ),
      ));
      await first;
    });
  });
}

AIToolDefinition _definition({
  required String name,
  Set<String> requiredPermissions = const <String>{},
  AIToolRiskLevel risk = AIToolRiskLevel.read,
  bool requiresApproval = false,
  AIToolIdempotencyPolicy idempotency = AIToolIdempotencyPolicy.notApplicable,
  Duration timeout = const Duration(seconds: 1),
  int maxResults = 10,
  int maxOutputBytes = 4096,
  bool allowsParallelExecution = true,
  bool requiresReadBack = false,
}) {
  return AIToolDefinition(
    name: name,
    version: '1.0.0',
    description: 'Descripción operacional verificable.',
    inputSchema: AIToolInputSchema.closedObject(
      properties: const <String, Object?>{
        'query': <String, Object?>{'type': 'string'},
      },
      required: const <String>['query'],
    ),
    requiredPermissions: requiredPermissions,
    risk: risk,
    requiresApproval: requiresApproval,
    timeout: timeout,
    maxResults: maxResults,
    maxOutputBytes: maxOutputBytes,
    allowsParallelExecution: allowsParallelExecution,
    idempotency: idempotency,
    requiresReadBack: requiresReadBack,
  );
}

AIToolAuthority _authority({
  Set<String> permissions = const <String>{},
}) {
  return AIToolAuthority(
    userId: 'user-1',
    tenantId: 'tenant-1',
    role: 'admin',
    permissions: permissions,
  );
}

Future<AIToolExecutorResult> _successfulExecutor(
  AIToolExecutionContext context,
) async {
  return AIToolExecutorResult(
    data: const {'items': <Object?>[]},
    resultCount: 0,
  );
}

Future<AIToolExecutionException> _executionError(
  Future<AIToolExecution> future,
) async {
  try {
    await future;
  } on AIToolExecutionException catch (error) {
    return error;
  }
  throw StateError('Expected AIToolExecutionException.');
}

class _TestApprovalVerifier implements AIToolApprovalVerifier {
  const _TestApprovalVerifier();

  @override
  Future<bool> consume({
    required AIToolApproval approval,
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime now,
  }) async {
    return idempotencyKey == 'operation-1' &&
        arguments['query'] == 'llamar cliente' &&
        approval.authorizes(
          definition: definition,
          authority: authority,
          arguments: arguments,
          idempotencyKey: idempotencyKey,
          now: now,
        );
  }
}

class _CountingApprovalVerifier implements AIToolApprovalVerifier {
  _CountingApprovalVerifier({this.delay = Duration.zero});

  final Duration delay;
  int calls = 0;

  @override
  Future<bool> consume({
    required AIToolApproval approval,
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
    required String? idempotencyKey,
    required DateTime now,
  }) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return true;
  }
}

class _ApprovalPolicy implements AIToolPolicy {
  const _ApprovalPolicy();

  @override
  AIToolPolicyDecision discover({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
  }) {
    return definition.name == 'blocked_tool'
        ? const AIToolPolicyDecision.deny()
        : const AIToolPolicyDecision.allow();
  }

  @override
  AIToolPolicyDecision authorize({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
  }) {
    return const AIToolPolicyDecision.allow(requiresApproval: true);
  }
}
