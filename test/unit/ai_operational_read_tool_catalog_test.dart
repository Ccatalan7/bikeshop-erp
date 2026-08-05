import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_attention_report.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_read_tool_catalog.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_operational_read_tool_catalog.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_tool_registry.dart';

void main() {
  final authority = AIToolAuthority(
    userId: 'user-a',
    tenantId: 'tenant-a',
    role: 'owner',
    permissions: const <String>{AIToolPermission.operationalRead},
  );

  test('advertises one closed read tool only to operational readers', () {
    final registry = _registry();
    final advertisement = registry.advertisedToolsFor(authority).single;

    expect(advertisement.name, AIOperationalReadToolNames.listAttentionItems);
    expect(advertisement.inputSchema['additionalProperties'], isFalse);
    expect(advertisement.inputSchema['required'], <Object?>['horizon']);
    final properties =
        advertisement.inputSchema['properties']! as Map<String, Object?>;
    expect(
      (properties['horizon']! as Map<String, Object?>)['enum'],
      <Object?>['today', 'tomorrow'],
    );

    final denied = AIToolAuthority(
      userId: 'user-a',
      tenantId: 'tenant-a',
      role: 'restricted',
      permissions: const <String>{},
    );
    expect(registry.advertisedToolsFor(denied), isEmpty);
  });

  test('routes the exact horizon and emits bounded source-aware evidence',
      () async {
    AIAttentionHorizon? observedHorizon;
    AIToolAuthority? observedAuthority;
    final registry = _registry(
      reader: (horizon, callbackAuthority) async {
        observedHorizon = horizon;
        observedAuthority = callbackAuthority;
        return _report(
          horizon: horizon,
          items: <AIAttentionItem>[
            AIAttentionItem(
              stableId: 'private-row-id',
              source: AIAttentionSource.workshop,
              reason: AIAttentionReason.workshopDueOnDay,
              title: 'PG-00492',
              detail: 'En curso',
              priorityRank: 1,
              dueAt: DateTime.utc(2026, 8, 5, 17),
              createdAt: DateTime.utc(2026, 8, 1),
            ),
          ],
        );
      },
    );

    final execution = await registry.execute(
      toolName: AIOperationalReadToolNames.listAttentionItems,
      arguments: const <String, Object?>{'horizon': 'tomorrow'},
      authority: authority,
    );

    expect(observedHorizon, AIAttentionHorizon.tomorrow);
    expect(observedAuthority?.auditScopeHash, authority.auditScopeHash);
    expect(execution.data['status'], 'success');
    expect(execution.data['horizon'], 'tomorrow');
    expect(execution.receipt.resultCount, 1);
    final items = execution.data['items']! as List<Object?>;
    expect(items, hasLength(1));
    expect(items.single.toString(), isNot(contains('private-row-id')));
    expect(execution.data['sources'], hasLength(2));
  });

  test('preserves partial, unavailable and verified-empty outcomes', () async {
    for (final entry in <({AIAttentionReport report, String status})>[
      (
        report: _report(
          outcomes: const <AIAttentionSourceOutcome>[
            AIAttentionSourceOutcome.success(
              source: AIAttentionSource.workshop,
              examined: 3,
            ),
            AIAttentionSourceOutcome.unavailable(
              AIAttentionSource.tasks,
              AIAttentionUnavailableReason.readFailed,
            ),
          ],
        ),
        status: 'partial',
      ),
      (
        report: _report(
          outcomes: const <AIAttentionSourceOutcome>[
            AIAttentionSourceOutcome.unavailable(
              AIAttentionSource.workshop,
              AIAttentionUnavailableReason.couldNotVerify,
            ),
            AIAttentionSourceOutcome.unavailable(
              AIAttentionSource.tasks,
              AIAttentionUnavailableReason.readFailed,
            ),
          ],
        ),
        status: 'unavailable',
      ),
      (report: _report(), status: 'verifiedEmpty'),
    ]) {
      final registry = _registry(reader: (_, __) async => entry.report);
      final execution = await registry.execute(
        toolName: AIOperationalReadToolNames.listAttentionItems,
        arguments: const <String, Object?>{'horizon': 'today'},
        authority: authority,
      );
      expect(execution.data['status'], entry.status);
    }
  });

  test('invalid arguments and malformed reader output fail closed', () async {
    var calls = 0;
    final registry = _registry(
      reader: (_, __) async {
        calls++;
        return _report(
          items: List<AIAttentionItem>.generate(
            7,
            (index) => AIAttentionItem(
              stableId: '$index',
              source: AIAttentionSource.tasks,
              reason: AIAttentionReason.taskDueOnDay,
              title: 'Tarea $index',
              detail: 'Pendiente',
              priorityRank: 2,
              dueAt: null,
              createdAt: null,
            ),
          ),
          maxItems: 7,
        );
      },
    );

    await expectLater(
      registry.execute(
        toolName: AIOperationalReadToolNames.listAttentionItems,
        arguments: const <String, Object?>{'horizon': 'next_week'},
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
    expect(calls, 0);

    await expectLater(
      registry.execute(
        toolName: AIOperationalReadToolNames.listAttentionItems,
        arguments: const <String, Object?>{'horizon': 'today'},
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
    expect(calls, 1);
  });
}

AIToolRegistry _registry({AIAttentionItemsReadTool? reader}) {
  return AIToolRegistry(
    policy: const AIAssistantRuntimeToolPolicy(),
    registrations: buildAIOperationalReadToolRegistrations(
      listAttentionItems: reader ?? (_, __) async => _report(),
    ),
  );
}

AIAttentionReport _report({
  AIAttentionHorizon horizon = AIAttentionHorizon.today,
  List<AIAttentionItem> items = const <AIAttentionItem>[],
  List<AIAttentionSourceOutcome> outcomes = const <AIAttentionSourceOutcome>[
    AIAttentionSourceOutcome.empty(AIAttentionSource.workshop),
    AIAttentionSourceOutcome.empty(AIAttentionSource.tasks),
  ],
  int maxItems = 6,
}) {
  return AIAttentionReport(
    horizon: horizon,
    generatedAt: DateTime.utc(2026, 8, 4, 18, 30),
    items: items,
    outcomes: outcomes,
    selectedBeforeTruncation: items.length,
    maxItems: maxItems,
  );
}
