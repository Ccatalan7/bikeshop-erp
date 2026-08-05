import '../models/ai_agent_tool.dart';
import 'ai_tool_registry.dart';

typedef AIAssistantReadTool = Future<Map<String, Object?>> Function(
  String query,
);

/// Stable tool names owned by Viñabike, not by a model provider.
abstract final class AIAssistantReadToolNames {
  static const String searchInventory = 'search_inventory';
  static const String researchPublicWeb = 'research_public_web';
}

/// Builds the first provider-neutral, read-only tool catalog.
///
/// Executors are injected because the current domain services are captured by
/// one authority-bound turn. A later backend gateway can publish the same
/// definitions while replacing these callbacks with server-side executors.
AIToolRegistry buildAIAssistantReadToolRegistry({
  required AIAssistantReadTool searchInventory,
  required AIAssistantReadTool researchPublicWeb,
  AIToolPolicy policy = const AIAssistantRuntimeToolPolicy(),
}) {
  return AIToolRegistry(
    policy: policy,
    registrations: buildAIAssistantReadToolRegistrations(
      searchInventory: searchInventory,
      researchPublicWeb: researchPublicWeb,
    ),
  );
}

/// Returns the registrations so the runtime can compose one closed registry
/// from several domain catalogs without exposing the registry's internals.
List<AIToolRegistration> buildAIAssistantReadToolRegistrations({
  required AIAssistantReadTool searchInventory,
  required AIAssistantReadTool researchPublicWeb,
}) {
  return <AIToolRegistration>[
    AIToolRegistration(
      definition: AIToolDefinition(
        name: AIAssistantReadToolNames.searchInventory,
        version: 'v1',
        description:
            'Busca productos, precio y stock en el inventario autorizado '
            'del taller. Úsala antes de responder preguntas de productos.',
        inputSchema: _querySchema(),
        requiredPermissions: const <String>{
          AIToolPermission.operationalRead,
        },
        risk: AIToolRiskLevel.read,
        requiresApproval: false,
        timeout: const Duration(seconds: 25),
        maxResults: 15,
        maxOutputBytes: 64 * 1024,
        allowsParallelExecution: false,
        idempotency: AIToolIdempotencyPolicy.notApplicable,
      ),
      executor: (context) async {
        final data = await searchInventory(
          context.arguments['query']! as String,
        );
        return AIToolExecutorResult(
          data: data,
          resultCount: _resultCount(data, listKey: 'products'),
        );
      },
    ),
    AIToolRegistration(
      definition: AIToolDefinition(
        name: AIAssistantReadToolNames.researchPublicWeb,
        version: 'v1',
        description: 'Comprueba si la investigación pública aislada está '
            'disponible. Actualmente devuelve un límite explícito hasta que '
            'el worker seguro sea activado; no navega ni envía datos.',
        inputSchema: _querySchema(),
        requiredPermissions: const <String>{
          AIToolPermission.operationalRead,
        },
        risk: AIToolRiskLevel.publicResearch,
        requiresApproval: false,
        timeout: const Duration(seconds: 15),
        maxResults: 5,
        maxOutputBytes: 24 * 1024,
        allowsParallelExecution: true,
        idempotency: AIToolIdempotencyPolicy.notApplicable,
      ),
      executor: (context) async {
        final data = await researchPublicWeb(
          context.arguments['query']! as String,
        );
        return AIToolExecutorResult(
          data: data,
          resultCount: _resultCount(data, listKey: 'sources'),
        );
      },
    ),
  ];
}

AIToolInputSchema _querySchema() => AIToolInputSchema.closedObject(
      properties: const <String, Object?>{
        'query': <String, Object?>{
          'type': 'string',
          'description': 'Consulta breve y específica.',
          'minLength': 1,
          'maxLength': 240,
        },
      },
      required: const <String>['query'],
    );

int _resultCount(Map<String, Object?> data, {required String listKey}) {
  final rows = data[listKey];
  if (rows is List) return rows.length;
  return data.isEmpty ? 0 : 1;
}

/// Local fail-closed risk policy until the server-side authority gateway owns
/// discovery and execution.
class AIAssistantRuntimeToolPolicy implements AIToolPolicy {
  const AIAssistantRuntimeToolPolicy();

  @override
  AIToolPolicyDecision discover({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
  }) {
    if (_isClientForbiddenRisk(definition.risk) ||
        definition.risk == AIToolRiskLevel.publicResearch) {
      return const AIToolPolicyDecision.deny();
    }
    return const AIToolPolicyDecision.allow();
  }

  @override
  AIToolPolicyDecision authorize({
    required AIToolDefinition definition,
    required AIToolAuthority authority,
    required Map<String, Object?> arguments,
  }) {
    if (_isClientForbiddenRisk(definition.risk) ||
        definition.risk == AIToolRiskLevel.publicResearch) {
      // An unavailable tool is not advertised as a capability. If a provider
      // nevertheless emits a stale or fabricated call, execution still
      // rejects before arguments or egress reach the executor.
      return const AIToolPolicyDecision.deny();
    }
    return const AIToolPolicyDecision.allow();
  }

  bool _isClientForbiddenRisk(AIToolRiskLevel risk) {
    return risk == AIToolRiskLevel.reversibleWrite ||
        risk == AIToolRiskLevel.sensitiveWrite ||
        risk == AIToolRiskLevel.authenticatedBrowser;
  }
}
