import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_business_read_tool_catalog.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_tool_registry.dart';

void main() {
  final authority = AIToolAuthority(
    userId: 'business-user-secret',
    tenantId: 'business-tenant-secret',
    role: 'owner',
    permissions: const <String>{
      AIToolPermission.operationalRead,
      AIToolPermission.salesRead,
      AIToolPermission.purchasesRead,
    },
  );

  test('advertises the six bounded read tools with closed strict schemas', () {
    final policy = _CapturingPolicy();
    final registry = _registry(policy: policy);

    final tools = registry.advertisedToolsFor(authority);

    expect(
      tools.map((tool) => tool.name),
      const <String>[
        AIBusinessReadToolNames.searchWorkshopJobs,
        AIBusinessReadToolNames.searchTasks,
        AIBusinessReadToolNames.searchCustomers,
        AIBusinessReadToolNames.searchSuppliers,
        AIBusinessReadToolNames.searchSalesInvoices,
        AIBusinessReadToolNames.searchPurchaseInvoices,
      ],
    );
    for (final tool in tools) {
      final schema = tool.inputSchema;
      expect(schema['additionalProperties'], isFalse);
      expect(schema['required'], const <Object?>['query', 'limit']);
      expect(
        (schema['properties']! as Map<String, Object?>).keys,
        const <String>['query', 'limit'],
      );
      final limit = (schema['properties']! as Map<String, Object?>)['limit']!
          as Map<String, Object?>;
      expect(limit['type'], const <Object?>['integer', 'null']);
      expect(limit['maximum'], AIBusinessReadRequest.maxLimit);
    }

    expect(policy.discoveredDefinitions, hasLength(6));
    for (final definition in policy.discoveredDefinitions) {
      expect(definition.requiredPermissions, hasLength(1));
      expect(definition.risk, AIToolRiskLevel.read);
      expect(definition.requiresApproval, isFalse);
      expect(definition.maxResults, 10);
      expect(definition.timeout, const Duration(seconds: 15));
    }
  });

  test('routes every tool to its injected reader with normalized input',
      () async {
    final calls = <String>[];
    AIBusinessReadTool reader(String name) =>
        (request, callbackAuthority) async {
          expect(callbackAuthority.auditScopeHash, authority.auditScopeHash);
          calls.add('$name:${request.query}:${request.limit}');
          return AIBusinessReadToolResult.success(<Map<String, Object?>>[
            _itemForSource(name),
          ]);
        };

    final registry = buildAIBusinessReadToolRegistry(
      searchWorkshopJobs: reader('jobs'),
      searchTasks: reader('tasks'),
      searchCustomers: reader('customers'),
      searchSuppliers: reader('suppliers'),
      searchSalesInvoices: reader('sales'),
      searchPurchaseInvoices: reader('purchases'),
      policy: const AIToolAllowAuthorizedPolicy(),
    );
    final names = <String>[
      AIBusinessReadToolNames.searchWorkshopJobs,
      AIBusinessReadToolNames.searchTasks,
      AIBusinessReadToolNames.searchCustomers,
      AIBusinessReadToolNames.searchSuppliers,
      AIBusinessReadToolNames.searchSalesInvoices,
      AIBusinessReadToolNames.searchPurchaseInvoices,
    ];

    for (final name in names) {
      final execution = await registry.execute(
        toolName: name,
        arguments: const <String, Object?>{
          'query': '  bicicleta  ',
          'limit': null,
        },
        authority: authority,
      );
      expect(execution.data['status'], 'success');
      expect(execution.receipt.resultCount, 1);
    }

    expect(calls, <String>[
      'jobs:bicicleta:10',
      'tasks:bicicleta:10',
      'customers:bicicleta:10',
      'suppliers:bicicleta:10',
      'sales:bicicleta:10',
      'purchases:bicicleta:10',
    ]);
  });

  test('uses the standard verifiedEmpty and unavailable result shapes',
      () async {
    final registry = _registry(
      taskResult: const AIBusinessReadToolResult.verifiedEmpty(),
      supplierResult: const AIBusinessReadToolResult.unavailable(),
    );

    final empty = await registry.execute(
      toolName: AIBusinessReadToolNames.searchTasks,
      arguments: const <String, Object?>{'query': 'nada', 'limit': 3},
      authority: authority,
    );
    final unavailable = await registry.execute(
      toolName: AIBusinessReadToolNames.searchSuppliers,
      arguments: const <String, Object?>{'query': 'nada', 'limit': 3},
      authority: authority,
    );

    expect(
      empty.data,
      const <String, Object?>{
        'status': 'verifiedEmpty',
        'items': <Object?>[],
      },
    );
    expect(
      unavailable.data,
      const <String, Object?>{
        'status': 'unavailable',
        'items': <Object?>[],
      },
    );
    expect(empty.receipt.resultCount, 0);
    expect(unavailable.receipt.resultCount, 0);
  });

  test('rejects rows beyond the request-specific result bound', () async {
    final registry = _registry(
      jobResult: AIBusinessReadToolResult.success(
        List<Map<String, Object?>>.generate(
          11,
          (index) => <String, Object?>{'jobNumber': 'PG-$index'},
        ),
      ),
    );

    await expectLater(
      registry.execute(
        toolName: AIBusinessReadToolNames.searchWorkshopJobs,
        arguments: const <String, Object?>{'query': 'todos', 'limit': 10},
        authority: authority,
      ),
      throwsA(
        isA<AIToolExecutionException>()
            .having(
              (error) => error.code,
              'code',
              AIToolFailureCode.invalidOutput,
            )
            .having(
              (error) => error.receipt.status,
              'status',
              AIToolReceiptStatus.failed,
            ),
      ),
    );
  });

  test('success receipt omits authority, query and result payload', () async {
    final registry = _registry();

    final execution = await registry.execute(
      toolName: AIBusinessReadToolNames.searchCustomers,
      arguments: const <String, Object?>{
        'query': 'private-customer-query',
        'limit': 1,
      },
      authority: authority,
    );
    final receipt = jsonEncode(execution.receipt.toAuditJson());

    expect(execution.receipt.approvalUsed, isFalse);
    expect(execution.receipt.idempotencyUsed, isFalse);
    expect(execution.receipt.authorityScopeHash, hasLength(64));
    expect(receipt, isNot(contains(authority.userId)));
    expect(receipt, isNot(contains(authority.tenantId)));
    expect(receipt, isNot(contains('private-customer-query')));
    expect(receipt, isNot(contains('customer-private-result')));
  });

  test('rejects non-allowlisted fields before model exposure', () async {
    final registry = _registry(
      jobResult: AIBusinessReadToolResult.success(
        const <Map<String, Object?>>[
          <String, Object?>{
            'jobNumber': 'PG-1',
            'privateSecret': 'never expose',
          },
        ],
      ),
    );

    final error = await _executionError(
      registry.execute(
        toolName: AIBusinessReadToolNames.searchWorkshopJobs,
        arguments: const <String, Object?>{
          'query': 'pendiente',
          'limit': 3,
        },
        authority: authority,
      ),
    );

    expect(error.code, AIToolFailureCode.invalidOutput);
    expect(jsonEncode(error.receipt.toAuditJson()), isNot(contains('secret')));
  });
}

AIToolRegistry _registry({
  AIToolPolicy policy = const AIToolAllowAuthorizedPolicy(),
  AIBusinessReadToolResult? jobResult,
  AIBusinessReadToolResult? taskResult,
  AIBusinessReadToolResult? supplierResult,
}) {
  AIBusinessReadTool reader(
    String source, [
    AIBusinessReadToolResult? result,
  ]) {
    return (request, authority) async =>
        result ??
        AIBusinessReadToolResult.success(<Map<String, Object?>>[
          _itemForSource(source),
        ]);
  }

  return buildAIBusinessReadToolRegistry(
    searchWorkshopJobs: reader('job', jobResult),
    searchTasks: reader('task', taskResult),
    searchCustomers: reader('customer'),
    searchSuppliers: reader('supplier', supplierResult),
    searchSalesInvoices: reader('sales'),
    searchPurchaseInvoices: reader('purchase'),
    policy: policy,
  );
}

Map<String, Object?> _itemForSource(String source) => switch (source) {
      'jobs' || 'job' => <String, Object?>{'jobNumber': 'PG-1'},
      'tasks' || 'task' => <String, Object?>{'title': 'Tarea privada'},
      'customers' || 'customer' => <String, Object?>{
          'name': 'customer-private-result'
        },
      'suppliers' || 'supplier' => <String, Object?>{
          'name': 'Proveedor privado'
        },
      'sales' => <String, Object?>{'invoiceNumber': 'FV-1'},
      'purchases' || 'purchase' => <String, Object?>{'invoiceNumber': 'FC-1'},
      _ => throw StateError('Unknown test source.'),
    };

class _CapturingPolicy implements AIToolPolicy {
  final List<AIToolDefinition> discoveredDefinitions = <AIToolDefinition>[];

  @override
  AIToolPolicyDecision discover({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
  }) {
    discoveredDefinitions.add(definition);
    return const AIToolPolicyDecision.allow();
  }

  @override
  AIToolPolicyDecision authorize({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
  }) {
    return const AIToolPolicyDecision.allow();
  }
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
