import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_audit_event.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/providers/ai_agent_model_provider.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/in_memory_ai_agent_audit_sink.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

void main() {
  const scope = ErpAuthorityScopeKey(
    userId: 'user-a',
    tenantId: 'tenant-a',
  );
  const authority = AIAssistantTurnAuthority(
    scope,
    permissions: <String>{AIToolPermission.operationalRead},
  );

  test('the conversation loop depends on a provider-neutral contract',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Hola desde el proveedor neutral.',
        toolCalls: <AIAgentToolCall>[],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Recuerdo el turno anterior.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);

    final first = await service.sendMessage(
      'Responde únicamente con un saludo.',
      authority: authority,
    );
    final second = await service.sendMessage(
      '¿Qué acabas de responder?',
      authority: authority,
    );

    expect(first.text, 'Hola desde el proveedor neutral.');
    expect(second.text, 'Recuerdo el turno anterior.');
    expect(provider.requests, hasLength(2));
    expect(provider.requests.first.modelRole, AIAgentModelRole.fast);
    expect(provider.requests.first.messages, hasLength(1));
    expect(
      provider.requests.first.messages.single.role,
      AIAgentMessageRole.user,
    );
    expect(
      provider.requests.first.tools.map((tool) => tool.name),
      <String>[
        'search_inventory',
        'list_attention_items',
        'search_workshop_jobs',
        'search_tasks',
        'search_customers',
      ],
    );
    expect(
      provider.requests.first.tools.every(
        (tool) => tool.inputSchema['additionalProperties'] == false,
      ),
      isTrue,
    );
    expect(provider.requests[1].messages, hasLength(3));
    expect(
      provider.requests[1].messages.map((item) => item.role),
      <AIAgentMessageRole>[
        AIAgentMessageRole.user,
        AIAgentMessageRole.assistant,
        AIAgentMessageRole.user,
      ],
    );
  });

  test('an unknown model-requested tool fails closed and never dispatches',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: '',
        toolCalls: <AIAgentToolCall>[
          AIAgentToolCall(
            id: 'call-unknown',
            name: 'erp.database.query_anything',
            arguments: <String, Object?>{
              'sql': 'delete from products',
            },
          ),
        ],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'No ejecuté esa operación.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);

    final response = await service.sendMessage(
      'Haz una operación no registrada.',
      authority: authority,
    );

    expect(response.text, 'No ejecuté esa operación.');
    expect(provider.requests, hasLength(2));
    final toolMessage = provider.requests.last.messages.last;
    expect(toolMessage.role, AIAgentMessageRole.tool);
    expect(toolMessage.toolOutputs, hasLength(1));
    expect(toolMessage.toolOutputs.single.callId, 'call-unknown');
    expect(
      toolMessage.toolOutputs.single.output,
      <String, Object?>{
        'status': 'rejected',
        'errorCode': 'unknownTool',
        'message': 'La herramienta solicitada no está disponible.',
      },
    );
  });

  test('a model-selected ERP read returns bounded data and code-owned cards',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: '',
        toolCalls: <AIAgentToolCall>[
          AIAgentToolCall(
            id: 'call-jobs',
            name: 'search_workshop_jobs',
            arguments: <String, Object?>{
              'query': 'pendiente',
              'limit': 3,
            },
          ),
        ],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Encontré un trabajo pendiente.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);
    final job = MechanicJob(
      id: 'internal-job-id',
      tenantId: scope.tenantId,
      jobNumber: 'PG-00492',
      customerId: 'private-customer-id',
      status: JobStatus.pendiente,
      clientRequest: 'Ajustar frenos',
      totalCost: 22000,
    );

    final response = await service.sendMessage(
      'Necesito evidencia operacional combinada.',
      authority: authority,
      bikeshopService:
          _FakeBikeshopService(scope: scope, jobs: <MechanicJob>[job]),
    );

    expect(response.text, 'Encontré un trabajo pendiente.');
    expect(response.cards, hasLength(1));
    expect(response.cards.single.title, 'PG-00492');
    expect(
      response.cards.single.destination,
      AIAssistantDestination.workshopJobs,
    );
    final output =
        provider.requests.last.messages.last.toolOutputs.single.output;
    expect(output['status'], 'success');
    final encoded = jsonEncode(output);
    expect(encoded, contains('PG-00492'));
    expect(encoded, isNot(contains('internal-job-id')));
    expect(encoded, isNot(contains('private-customer-id')));
    expect(encoded, isNot(contains(scope.tenantId)));
  });

  test('public research is explicit and fail-closed until isolation exists',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: '',
        toolCalls: <AIAgentToolCall>[
          AIAgentToolCall(
            id: 'call-public-web',
            name: 'research_public_web',
            arguments: <String, Object?>{
              'query': 'manual técnico Shimano Deore',
            },
          ),
        ],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'La investigación pública aislada aún no está activada.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);

    final response = await service.sendMessage(
      'Busca el manual técnico público.',
      authority: authority,
    );

    expect(
      response.text,
      'La investigación pública aislada aún no está activada.',
    );
    final output =
        provider.requests.last.messages.last.toolOutputs.single.output;
    expect(output['status'], 'rejected');
    expect(output['errorCode'], AIToolFailureCode.unauthorized.name);
    expect(output.toString(), isNot(contains('manual técnico')));
  });

  test('too many model tool calls stop before any dispatch', () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'ignorar',
        toolCalls: <AIAgentToolCall>[
          for (var index = 0; index < 13; index++)
            AIAgentToolCall(
              id: 'call-$index',
              name: 'unknown_tool_$index',
              arguments: const <String, Object?>{},
            ),
        ],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);

    final response = await service.sendMessage(
      'Haz demasiadas consultas.',
      authority: authority,
    );

    expect(response.text, contains('límite seguro de herramientas'));
    expect(provider.requests, hasLength(1));
    expect(service.history, hasLength(2));
    expect(service.history.last.toolCalls, isEmpty);
  });

  test('model and tool attempts emit only hashed, allowlisted audit events',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: '',
        toolCalls: <AIAgentToolCall>[
          AIAgentToolCall(
            id: 'private-call-id',
            name: 'unknown_private_tool',
            arguments: <String, Object?>{
              'customer': 'cliente@example.com',
            },
          ),
        ],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Operación rechazada de forma segura.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final sink = InMemoryAIAgentAuditSink();
    final ids = <String>['session-private', 'request-private'].iterator;
    final service = AIAssistantService(
      modelProvider: provider,
      auditSink: sink,
      idFactory: () {
        if (!ids.moveNext()) throw StateError('No audit id queued.');
        return ids.current;
      },
    );

    await service.sendMessage(
      'Busca información privada de cliente@example.com',
      authority: authority,
    );

    expect(sink.events, hasLength(3));
    expect(
      sink.events.map((event) => event.kind),
      <AIAgentAuditEventKind>[
        AIAgentAuditEventKind.modelInvocation,
        AIAgentAuditEventKind.toolPolicyDecision,
        AIAgentAuditEventKind.modelInvocation,
      ],
    );
    final encoded = jsonEncode(
      sink.events.map((event) => event.toSafeMap()).toList(),
    );
    for (final rawValue in <String>[
      'cliente@example.com',
      'session-private',
      'request-private',
      'private-call-id',
      'user-a',
      'tenant-a',
    ]) {
      expect(encoded, isNot(contains(rawValue)));
    }
    expect(
      sink.events.every((event) => event.sessionIdHash.hex.length == 64),
      isTrue,
    );
  });

  test('reset drops canonical model history and restarts local turn identity',
      () async {
    final provider = _FakeProvider(<AIAgentProviderTurn>[
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Primero.',
        toolCalls: <AIAgentToolCall>[],
      ),
      const AIAgentProviderTurn(
        provider: 'fake',
        model: 'fake-fast',
        text: 'Sesión nueva.',
        toolCalls: <AIAgentToolCall>[],
      ),
    ]);
    final service = AIAssistantService(modelProvider: provider);

    await service.sendMessage('Primer turno neutral.', authority: authority);
    expect(service.history, hasLength(2));

    service.resetChat();
    expect(service.history, isEmpty);

    await service.sendMessage('Nuevo turno neutral.', authority: authority);
    expect(provider.requests.last.messages, hasLength(1));
    expect(provider.requests.last.turnId, 'turn-1/model-0');
  });
}

class _FakeProvider implements AIAgentModelProvider {
  _FakeProvider(this._turns);

  final List<AIAgentProviderTurn> _turns;
  final List<AIAgentProviderRequest> requests = <AIAgentProviderRequest>[];

  @override
  String get providerId => 'fake';

  @override
  Future<AIAgentProviderTurn> complete(AIAgentProviderRequest request) async {
    requests.add(request);
    if (_turns.isEmpty) {
      throw StateError('No fake provider turn was queued.');
    }
    return _turns.removeAt(0);
  }
}

class _FakeBikeshopService implements BikeshopService {
  _FakeBikeshopService({required this.scope, required this.jobs});

  final ErpAuthorityScopeKey scope;
  final List<MechanicJob> jobs;

  @override
  ErpAuthorityScopeKey get authorityScope => scope;

  @override
  bool get hasJobsCache => false;

  @override
  List<MechanicJob> get cachedJobs => const <MechanicJob>[];

  @override
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async =>
      jobs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
