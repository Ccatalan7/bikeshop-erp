import '../models/ai_agent_tool.dart';
import '../models/ai_attention_report.dart';
import 'ai_tool_registry.dart';

typedef AIAttentionItemsReadTool = Future<AIAttentionReport> Function(
  AIAttentionHorizon horizon,
  AIToolAuthority authority,
);

abstract final class AIOperationalReadToolNames {
  static const String listAttentionItems = 'list_attention_items';
}

/// Registers the deterministic, authority-bound operational briefing as a
/// model-discoverable read. Exact "today/tomorrow" prompts still use the same
/// read model directly; this tool lets a broader planning turn combine that
/// evidence with other bounded ERP reads without inventing a second source.
List<AIToolRegistration> buildAIOperationalReadToolRegistrations({
  required AIAttentionItemsReadTool listAttentionItems,
}) {
  return <AIToolRegistration>[
    AIToolRegistration(
      definition: AIToolDefinition(
        name: AIOperationalReadToolNames.listAttentionItems,
        version: 'v1',
        description: 'Lista entregas y tareas que requieren atención hoy o '
            'mañana, distinguiendo fuentes parciales y no disponibles.',
        inputSchema: AIToolInputSchema.closedObject(
          properties: const <String, Object?>{
            'horizon': <String, Object?>{
              'type': 'string',
              'enum': <Object?>['today', 'tomorrow'],
              'description': 'Día operacional chileno que se debe revisar.',
            },
          },
          required: const <String>['horizon'],
        ),
        requiredPermissions: const <String>{
          AIToolPermission.operationalRead,
        },
        risk: AIToolRiskLevel.read,
        requiresApproval: false,
        timeout: const Duration(seconds: 25),
        maxResults: 6,
        maxOutputBytes: 32 * 1024,
        allowsParallelExecution: false,
        idempotency: AIToolIdempotencyPolicy.notApplicable,
      ),
      executor: (context) async {
        final horizon = switch (context.arguments['horizon']) {
          'today' => AIAttentionHorizon.today,
          'tomorrow' => AIAttentionHorizon.tomorrow,
          _ => throw const AIToolExecutorOutputException(),
        };
        final report = await listAttentionItems(horizon, context.authority);
        final data = _validatedReportJson(report, expectedHorizon: horizon);
        return AIToolExecutorResult(
          data: data,
          resultCount: report.items.length,
        );
      },
    ),
  ];
}

Map<String, Object?> _validatedReportJson(
  AIAttentionReport report, {
  required AIAttentionHorizon expectedHorizon,
}) {
  if (report.horizon != expectedHorizon ||
      report.maxItems < 1 ||
      report.maxItems > 6 ||
      report.items.length > report.maxItems ||
      report.selectedBeforeTruncation < report.items.length ||
      report.selectedBeforeTruncation > 5000 ||
      report.outcomes.length != AIAttentionSource.values.length ||
      report.outcomes.map((outcome) => outcome.source).toSet().length !=
          AIAttentionSource.values.length ||
      report.outcomes.any(
        (outcome) => outcome.examined < 0 || outcome.examined > 5000,
      )) {
    throw const AIToolExecutorOutputException();
  }

  for (final item in report.items) {
    if (item.title.trim().isEmpty ||
        item.title.length > 180 ||
        item.detail.length > 180 ||
        item.priorityRank < 0 ||
        item.priorityRank > 3) {
      throw const AIToolExecutorOutputException();
    }
  }

  final status = report.isUnavailable
      ? 'unavailable'
      : report.isPartial
          ? 'partial'
          : report.items.isEmpty
              ? 'verifiedEmpty'
              : 'success';

  return <String, Object?>{
    'status': status,
    'horizon': report.horizon.name,
    'generatedAt': report.generatedAt.toUtc().toIso8601String(),
    'selectedCount': report.selectedBeforeTruncation,
    'truncated': report.isTruncated,
    'items': <Object?>[
      for (final item in report.items)
        <String, Object?>{
          'source': item.source.name,
          'reason': item.reason.name,
          'title': item.title.trim(),
          'detail': item.detail.trim(),
          'priorityRank': item.priorityRank,
          'dueAt': item.dueAt?.toUtc().toIso8601String(),
        },
    ],
    'sources': <Object?>[
      for (final outcome in report.outcomes)
        <String, Object?>{
          'source': outcome.source.name,
          'state': outcome.state.name,
          'examined': outcome.examined,
          'reason': outcome.reason?.name,
        },
    ],
  };
}
