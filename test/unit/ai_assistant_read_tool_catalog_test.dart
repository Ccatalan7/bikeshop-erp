import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_read_tool_catalog.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_tool_registry.dart';

void main() {
  final authority = AIToolAuthority(
    userId: 'user-a',
    tenantId: 'tenant-a',
    role: 'owner',
    permissions: const <String>{AIToolPermission.operationalRead},
  );

  test('advertises only currently executable first-wave tools', () {
    final registry = _registry();

    final tools = registry.advertisedToolsFor(authority);

    expect(
      tools.map((tool) => tool.name),
      <String>[
        AIAssistantReadToolNames.searchInventory,
      ],
    );
    expect(
      tools.every(
        (tool) => tool.inputSchema['additionalProperties'] == false,
      ),
      isTrue,
    );
  });

  test('public research rejects likely private ERP data before its executor',
      () async {
    var executions = 0;
    final registry = buildAIAssistantReadToolRegistry(
      searchInventory: (query) async => const <String, Object?>{},
      researchPublicWeb: (query) async {
        executions++;
        return const <String, Object?>{'result': 'should not run'};
      },
    );

    await expectLater(
      registry.execute(
        toolName: AIAssistantReadToolNames.researchPublicWeb,
        arguments: const <String, Object?>{
          'query': 'buscar contacto cliente@example.com',
        },
        authority: authority,
      ),
      throwsA(
        isA<AIToolExecutionException>().having(
          (error) => error.code,
          'code',
          AIToolFailureCode.unauthorized,
        ),
      ),
    );
    expect(executions, 0);
  });

  test('inventory query is bounded before its executor', () async {
    var executions = 0;
    final registry = buildAIAssistantReadToolRegistry(
      searchInventory: (query) async {
        executions++;
        return const <String, Object?>{};
      },
      researchPublicWeb: (query) async => const <String, Object?>{},
    );

    await expectLater(
      registry.execute(
        toolName: AIAssistantReadToolNames.searchInventory,
        arguments: <String, Object?>{'query': 'x' * 241},
        authority: authority,
      ),
      throwsA(
        isA<AIToolExecutionException>().having(
          (error) => error.code,
          'code',
          AIToolFailureCode.invalidArguments,
        ),
      ),
    );
    expect(executions, 0);
  });

  test('inventory output is bounded and gets a sanitized scoped receipt',
      () async {
    final registry = _registry();

    final execution = await registry.execute(
      toolName: AIAssistantReadToolNames.searchInventory,
      arguments: const <String, Object?>{'query': 'cadena 12v'},
      authority: authority,
    );

    expect(execution.receipt.resultCount, 1);
    expect(execution.receipt.risk, AIToolRiskLevel.read);
    expect(execution.receipt.authorityScopeHash, hasLength(64));
    expect(
      execution.receipt.toAuditJson().values,
      isNot(contains(authority.userId)),
    );
    expect(
      execution.receipt.toAuditJson().values,
      isNot(contains(authority.tenantId)),
    );
  });
}

AIToolRegistry _registry() => buildAIAssistantReadToolRegistry(
      searchInventory: (query) async => <String, Object?>{
        'count': 1,
        'products': <Object?>[
          <String, Object?>{'name': 'Cadena 12v'},
        ],
      },
      researchPublicWeb: (query) async => const <String, Object?>{
        'result': 'Ficha técnica pública',
      },
    );
