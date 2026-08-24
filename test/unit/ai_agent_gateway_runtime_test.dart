import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_gateway_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_turn_contracts.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_agent_gateway_client.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_session_service.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_assistant_turn_engine.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/gateway_ai_assistant_turn_engine.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/crm/services/customer_service.dart';
import 'package:vinabike_erp/modules/inventory/services/inventory_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

const _threadA = '11111111-1111-4111-8111-111111111111';
const _runA = '22222222-2222-4222-8222-222222222222';
const _runB = '33333333-3333-4333-8333-333333333333';
const _requestA = '44444444-4444-4444-8444-444444444444';
const _requestB = '55555555-5555-4555-8555-555555555555';
const _jobA = '66666666-6666-4666-8666-666666666666';
const _customerA = '77777777-7777-4777-8777-777777777777';
const _expenseA = '88888888-8888-4888-8888-888888888888';
const _conversationA = '99999999-9999-4999-8999-999999999999';
const _approvalA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _actionA = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _actionB = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _approvalExpiryWire = '2026-08-12T03:45:00.000Z';

final _pendingTaskApproval = AIAssistantApprovalRef(
  id: _approvalA,
  action: AIAssistantApprovalAction.createTask,
  expiresAt: DateTime.parse(_approvalExpiryWire),
  state: AIAssistantApprovalState.pending,
);

Map<String, Object?> _response({
  String threadId = _threadA,
  String runId = _runA,
  List<Object?> cards = const <Object?>[],
}) {
  return <String, Object?>{
    'version': 1,
    'threadId': threadId,
    'runId': runId,
    'text': 'Respuesta verificada',
    'cards': cards,
    'status': 'completed',
  };
}

Map<String, Object?> _taskPreviewCard({
  Object? approvalRef,
  String kind = 'task_preview',
  String destination = 'tasks',
}) =>
    <String, Object?>{
      'kind': kind,
      'eyebrow': 'Tarea propuesta',
      'title': 'Llamar a Claudia',
      'subtitle': 'Mañana · Prioridad alta',
      'description': 'Confirmar repuesto antes de comenzar PG-00484.',
      'destination': destination,
      'chips': <String>['Mañana', 'Alta'],
      'approvalRef': approvalRef ??
          <String, Object?>{
            'id': _approvalA,
            'action': 'create_task',
            'expiresAt': _approvalExpiryWire,
            'state': 'pending',
          },
    };

Map<String, Object?> _supplyNeedDraftCard({Object? draft}) => <String, Object?>{
      'kind': 'supply_need_draft',
      'title': '2 necesidades para revisar',
      'destination': 'purchases',
      'chips': <String>['Equilibrio', '1 por precisar'],
      'supplyNeedDraft': draft ??
          <String, Object?>{
            'profile': 'balanced',
            'lines': <Object?>[
              <String, Object?>{
                'lineRef': 'line-1',
                'description': 'Neumático 27,5 ancho mayor a 2,0',
                'productId': _customerA,
                'productName': 'Kenda Kwick 27,5 × 2,10',
                'productSku': 'KEN-275-210',
                'identityState': 'confirmed',
                'categoryId': null,
                'categoryPath': null,
                'technicalFamily': null,
                'quantity': 2,
                'unit': 'unit',
                'technicalPredicates': <Object?>[
                  <String, Object?>{
                    'field': 'tire_width',
                    'operator': 'gt',
                    'values': <Object?>[2.0],
                  },
                ],
                'preference': 'gama económica',
                'clarification': null,
                'clarificationRequired': false,
                'clarificationPrompts': <Object?>[],
              },
              <String, Object?>{
                'lineRef': 'line-2',
                'description': 'Rayos 27,5',
                'productId': null,
                'productName': null,
                'productSku': null,
                'identityState': 'unresolved',
                'categoryId': null,
                'categoryPath': null,
                'technicalFamily': null,
                'quantity': 1,
                'unit': 'set',
                'technicalPredicates': <Object?>[],
                'preference': null,
                'clarification':
                    '¿Te refieres a rayos de medida 27,5 o para una rueda 27,5?',
                'clarificationRequired': true,
                'clarificationPrompts': <Object?>[
                  <String, Object?>{
                    'id': 'measurement_meaning',
                    'question':
                        '¿La medida pertenece al producto o al contexto donde se instalará?',
                    'inputKind': 'single_choice',
                    'options': <Object?>[
                      <String, Object?>{
                        'value': 'product',
                        'label': 'Al producto',
                      },
                      <String, Object?>{
                        'value': 'fitment',
                        'label': 'Al contexto',
                      },
                    ],
                    'unit': null,
                    'allowUnknown': false,
                  },
                ],
              },
            ],
          },
    };

Map<String, Object?> _workshopPreviewCard({
  String kind = 'diagnosis_preview',
  String action = 'update_diagnosis',
}) =>
    <String, Object?>{
      'kind': kind,
      'eyebrow': 'Cambio por confirmar',
      'title': 'Desgaste de cadena',
      'subtitle': 'PG-00420 · Trek Marlin 7',
      'description': 'Sin valor anterior · Nuevo: 0.60',
      'destination': 'workshop_jobs',
      'chips': <String>['Requiere confirmación'],
      'approvalRef': <String, Object?>{
        'id': _approvalA,
        'action': action,
        'expiresAt': _approvalExpiryWire,
        'state': 'pending',
      },
    };

Map<String, Object?> _approvalResponse({
  String approvalId = _approvalA,
  String clientActionId = _actionA,
  String state = 'approved',
  List<Object?>? cards,
}) =>
    <String, Object?>{
      'version': 1,
      'operation': 'approval_action',
      'approvalId': approvalId,
      'clientActionId': clientActionId,
      'approvalState': state,
      'text': state == 'approved' ? 'Tarea creada.' : 'Propuesta descartada.',
      'cards': cards ??
          <Object?>[
            <String, Object?>{
              'kind': 'task',
              'title': 'Tareas pendientes',
              'destination': 'tasks',
              'chips': <String>['1 creada'],
            },
          ],
      'status': 'completed',
    };

class _QueueTransport implements AIAgentGatewayTransport {
  _QueueTransport(this.responses);

  final List<Object?> responses;
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    bodies.add(body);
    return responses.removeAt(0);
  }
}

class _BlockingTransport implements AIAgentGatewayTransport {
  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    await abortTrigger;
    throw const AIAgentGatewayException(code: 'request_aborted');
  }
}

class _AmbiguousOnceTransport implements AIAgentGatewayTransport {
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  var attempts = 0;

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    bodies.add(body);
    attempts++;
    if (attempts == 1) {
      throw const AIAgentGatewayException(
        code: 'gateway_unavailable',
        outcomeUnknown: true,
      );
    }
    return _response(runId: attempts == 2 ? _runA : _runB);
  }
}

class _AmbiguousApprovalOnceTransport implements AIAgentGatewayTransport {
  final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
  var attempts = 0;

  @override
  Future<Object?> send(
    Map<String, Object?> body, {
    required Future<void> abortTrigger,
  }) async {
    bodies.add(body);
    attempts++;
    if (attempts == 1) {
      throw const AIAgentGatewayException(
        code: 'approval_unavailable',
        outcomeUnknown: true,
      );
    }
    return _approvalResponse(
      approvalId: body['approvalId']! as String,
      clientActionId: body['clientActionId']! as String,
    );
  }
}

class _MarkerEngine implements AIAssistantTurnEngine {
  var resetCount = 0;

  @override
  void resetChat() => resetCount++;

  @override
  Future<AIAssistantResponse> sendMessage(
    String message, {
    List<MechanicJob>? jobs,
    CustomerService? customerService,
    InventoryService? inventoryService,
    BikeshopService? bikeshopService,
    bool jobsAreCurrentView = false,
    String? jobSummaryScopeLabel,
    PurchaseService? purchaseService,
    SalesService? salesService,
    bool allowJobCacheFallback = true,
    bool visibleJobsSourceUnavailable = false,
    TaskService? taskService,
    required AIAssistantTurnAuthority authority,
  }) async {
    return const AIAssistantResponse(text: 'marker');
  }
}

const _authority = AIAssistantTurnAuthority(
  ErpAuthorityScopeKey(userId: 'user-a', tenantId: 'tenant-a'),
  role: 'owner',
  permissions: <String>{'ai.read.operational'},
);

void main() {
  test('HTTP transport sends only caller auth and the public project key',
      () async {
    late http.Request captured;
    final transport = SupabaseAIAgentGatewayTransport(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'public-project-key',
      accessTokenProvider: () async => 'caller-jwt',
      httpClientFactory: () => MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_response()), 200);
      }),
    );

    final response = await transport.send(
      <String, Object?>{'version': 1},
      abortTrigger: Completer<void>().future,
    );

    expect(response, isA<Map>());
    expect(
      captured.url.toString(),
      'https://project.supabase.co/functions/v1/ai-agent-gateway',
    );
    expect(captured.headers['authorization'], 'Bearer caller-jwt');
    expect(captured.headers['apikey'], 'public-project-key');
    expect(captured.headers['x-vinabike-ai-result-lists'], '1');
    expect(
      captured.headers['x-vinabike-ai-structured-clarifications'],
      '1',
    );
    expect(captured.headers.values, isNot(contains('service-role')));
    expect(jsonDecode(captured.body), <String, Object?>{'version': 1});
  });

  test('HTTP transport never exposes upstream error details', () async {
    final transport = SupabaseAIAgentGatewayTransport(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'public-project-key',
      accessTokenProvider: () async => 'caller-jwt',
      httpClientFactory: () => MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': 'private database detail',
            'code': 'invalid code with spaces',
          }),
          500,
        ),
      ),
    );

    await expectLater(
      transport.send(
        <String, Object?>{'version': 1},
        abortTrigger: Completer<void>().future,
      ),
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.code, 'code', 'gateway_unavailable')
            .having(
              (error) => error.toString(),
              'safe text',
              isNot(contains('private database detail')),
            ),
      ),
    );
  });

  test('HTTP response limit counts raw UTF-8 bytes', () async {
    final transport = SupabaseAIAgentGatewayTransport(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'public-project-key',
      accessTokenProvider: () async => 'caller-jwt',
      httpClientFactory: () => MockClient(
        (_) async => http.Response(
          '🚀' * (33 * 1024),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        ),
      ),
    );

    await expectLater(
      transport.send(
        <String, Object?>{'version': 1},
        abortTrigger: Completer<void>().future,
      ),
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.code, 'code', 'response_too_large'),
      ),
    );
  });

  test('unconfirmed durable finalization is an ambiguous HTTP outcome',
      () async {
    final transport = SupabaseAIAgentGatewayTransport(
      supabaseUrl: 'https://project.supabase.co',
      publishableKey: 'public-project-key',
      accessTokenProvider: () async => 'caller-jwt',
      httpClientFactory: () => MockClient(
        (_) async => http.Response(
          jsonEncode(<String, Object?>{
            'error': 'Assistant request outcome is pending',
            'code': 'run_finalization_pending',
          }),
          503,
        ),
      ),
    );

    await expectLater(
      transport.send(
        <String, Object?>{'version': 1},
        abortTrigger: Completer<void>().future,
      ),
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.code, 'code', 'run_finalization_pending')
            .having((error) => error.outcomeUnknown, 'ambiguous', isTrue),
      ),
    );
  });

  test('request is closed and carries no client-authored authority or history',
      () async {
    final transport = _QueueTransport(<Object?>[_response()]);
    final client = AIAgentGatewayClient(transport: transport);

    await client.complete(
      AIAgentGatewayRequest(
        clientRequestId: _requestA,
        threadId: null,
        message: '  Organiza el taller para hoy  ',
        viewContext: AIAgentGatewayViewContext.none(),
      ),
      abortTrigger: Completer<void>().future,
    );

    expect(transport.bodies, hasLength(1));
    final body = transport.bodies.single;
    expect(
      body.keys,
      unorderedEquals(<String>{
        'version',
        'clientRequestId',
        'modelRole',
        'message',
        'viewContext',
      }),
    );
    expect(body['message'], 'Organiza el taller para hoy');
    expect(body['modelRole'], 'deep');
    expect(body, isNot(contains('tenantId')));
    expect(body, isNot(contains('userId')));
    expect(body, isNot(contains('permissions')));
    expect(body, isNot(contains('messages')));
    expect(body, isNot(contains('tools')));
  });

  test('response accepts only registered cards with the matching closed kind',
      () {
    final valid = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[
        <String, Object?>{
          'kind': 'job',
          'title': 'Trabajos del taller',
          'destination': 'workshop_jobs',
          'chips': <String>['3 pendientes'],
          'entityRef': <String, Object?>{
            'kind': 'workshopJob',
            'id': _jobA,
          },
        },
      ]),
    );

    expect(valid.cards, hasLength(1));
    expect(valid.cards.single.destination.isRegistered, isTrue);
    expect(
        valid.cards.single.entityRef?.kind, AIAssistantEntityKind.workshopJob);
    expect(valid.cards.single.entityRef?.id, _jobA);
    expect(
      () => AIAgentGatewayResponse.fromJson(
        _response(cards: <Object?>[
          <String, Object?>{
            'kind': 'job',
            'title': 'Ruta inventada',
            'destination': '/admin/secrets',
            'chips': <String>[],
          },
        ]),
      ),
      throwsA(isA<AIAgentGatewayContractException>()),
    );
  });

  test('cards without entityRef preserve the aggregate rollout contract', () {
    final response = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[
        <String, Object?>{
          'kind': 'customer',
          'title': 'Clientes encontrados',
          'destination': 'customers',
          'chips': <String>[],
        },
      ]),
    );

    expect(response.cards.single.entityRef, isNull);
    expect(response.cards.single.ctaLabel, 'Abrir Clientes');
  });

  test('inventory list reference decodes one exact bounded result set', () {
    final response = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[
        <String, Object?>{
          'kind': 'inventory',
          'title': '2 resultados',
          'destination': 'inventory_products',
          'chips': <String>['En stock'],
          'listRef': <String, Object?>{
            'kind': 'inventory',
            'query': 'camara 29',
            'availability': 'in_stock',
            'resultCount': 2,
            'hasMore': false,
            'entityIds': <String>[_customerA, _jobA],
            'autoOpen': true,
          },
        },
      ]),
    );

    final list = response.cards.single.inventoryListRef!;
    expect(list.query, 'camara 29');
    expect(list.availability, AIAssistantInventoryAvailability.inStock);
    expect(list.entityIds, <String>[_customerA, _jobA]);
    expect(list.autoOpen, isTrue);
    expect(response.cards.single.entityRef, isNull);
    expect(response.cards.single.ctaLabel, 'Ver resultados');
  });

  test('inventory list reference rejects broadened or contradictory payloads',
      () {
    final base = <String, Object?>{
      'kind': 'inventory',
      'query': 'camara 29',
      'availability': 'in_stock',
      'resultCount': 1,
      'hasMore': false,
      'entityIds': <String>[_customerA],
      'autoOpen': true,
    };
    for (final listRef in <Object?>[
      null,
      <String, Object?>{...base, 'availability': 'available-ish'},
      <String, Object?>{...base, 'resultCount': 2},
      // `hasMore: true` con ids ya NO es contradictorio: son las filas que se
      // pudieron mostrar, y sin ellas la pantalla caía a buscar la frase como
      // texto y abría una lista vacía. Lo que sigue siendo imposible es
      // declarar la lista completa sin decir de cuáles filas se trata.
      <String, Object?>{...base, 'entityIds': null},
      <String, Object?>{
        ...base,
        'entityIds': <String>['../../product']
      },
      <String, Object?>{...base, 'route': '/admin'},
    ]) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(cards: <Object?>[
            <String, Object?>{
              'kind': 'inventory',
              'title': 'Resultado',
              'destination': 'inventory_products',
              'chips': <String>[],
              'listRef': listRef,
            },
          ]),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$listRef',
      );
    }
  });

  test('supply request draft decodes exact and unresolved lines separately',
      () {
    final response = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[_supplyNeedDraftCard()]),
    );

    final card = response.cards.single;
    final draft = card.supplyNeedDraft!;
    expect(card.kind, 'supply_need_draft');
    expect(card.destination, AIAssistantDestination.purchases);
    expect(card.entityRef, isNull);
    expect(card.inventoryListRef, isNull);
    expect(card.ctaLabel, 'Revisar petición');
    expect(draft.profile, AIAssistantSupplyNeedProfile.balanced);
    expect(draft.lines, hasLength(2));
    expect(draft.lines.first.hasConfirmedProduct, isTrue);
    expect(draft.lines.first.productId, _customerA);
    expect(draft.lines.first.technicalPredicates.single.field, 'tire_width');
    expect(draft.lines.last.hasConfirmedProduct, isFalse);
    expect(draft.lines.last.clarificationRequired, isTrue);
    expect(draft.lines.last.clarificationPrompts, hasLength(1));
    expect(
      draft.lines.last.clarificationPrompts.single.inputKind,
      AIAssistantSupplyNeedClarificationInputKind.singleChoice,
    );
    expect(draft.lines.last.toCommandJson(), isNot(contains('productName')));
  });

  test('supply request draft keeps the negotiated v1 rollout compatible', () {
    final card = _supplyNeedDraftCard();
    final draft = card['supplyNeedDraft']! as Map<String, Object?>;
    final lines = draft['lines']! as List<Object?>;
    final legacyLines = lines
        .map(
          (line) => Map<String, Object?>.from(
            line! as Map<String, Object?>,
          )..remove('clarificationPrompts'),
        )
        .toList(growable: false);
    final response = AIAgentGatewayResponse.fromJson(
      _response(
        cards: <Object?>[
          <String, Object?>{
            ...card,
            'supplyNeedDraft': <String, Object?>{
              ...draft,
              'lines': legacyLines,
            },
          },
        ],
      ),
    );
    expect(
      response.cards.single.supplyNeedDraft!.lines.last.clarificationPrompts,
      isEmpty,
    );
  });

  test('supply request draft rejects missing or contradictory identity proof',
      () {
    final validDraft =
        _supplyNeedDraftCard()['supplyNeedDraft']! as Map<String, Object?>;
    final validLines = validDraft['lines']! as List<Object?>;
    final unresolved = Map<String, Object?>.from(
      validLines.last! as Map<String, Object?>,
    );
    for (final card in <Map<String, Object?>>[
      <String, Object?>{
        'kind': 'supply_need_draft',
        'title': 'Sin contenido',
        'destination': 'purchases',
        'chips': <String>[],
      },
      _supplyNeedDraftCard(
        draft: <String, Object?>{
          ...validDraft,
          'lines': <Object?>[
            ...validLines.take(1),
            <String, Object?>{
              ...unresolved,
              'productName': 'Nombre sin identidad',
            },
          ],
        },
      ),
      _supplyNeedDraftCard(
        draft: <String, Object?>{
          ...validDraft,
          'lines': <Object?>[
            <String, Object?>{
              ...(validLines.first! as Map<String, Object?>),
              'clarification': 'Pregunta bloqueante',
              'clarificationRequired': true,
            },
          ],
        },
      ),
      _supplyNeedDraftCard(
        draft: <String, Object?>{
          ...validDraft,
          'lines': <Object?>[
            ...validLines.take(1),
            <String, Object?>{
              ...unresolved,
              'clarificationRequired': false,
            },
          ],
        },
      ),
      _supplyNeedDraftCard(
        draft: <String, Object?>{
          ...validDraft,
          'lines': <Object?>[
            ...validLines.take(1),
            <String, Object?>{
              ...unresolved,
              'clarificationPrompts': <Object?>[
                <String, Object?>{
                  ...((unresolved['clarificationPrompts']! as List<Object?>)
                      .single! as Map<String, Object?>),
                  'options': <Object?>[],
                },
              ],
            },
          ],
        },
      ),
    ]) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(cards: <Object?>[card]),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
      );
    }
  });

  test('task preview decodes its complete governed approval reference', () {
    final response = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[_taskPreviewCard()]),
    );

    final card = response.cards.single;
    expect(card.kind, 'task_preview');
    expect(card.destination, AIAssistantDestination.tasks);
    expect(card.entityRef, isNull);
    expect(card.title, 'Llamar a Claudia');
    expect(card.subtitle, 'Mañana · Prioridad alta');
    expect(card.description, contains('PG-00484'));
    expect(card.chips, <String>['Mañana', 'Alta']);
    expect(card.approvalRef?.id, _approvalA);
    expect(
      card.approvalRef?.action,
      AIAssistantApprovalAction.createTask,
    );
    expect(card.approvalRef?.expiresAt.isUtc, isTrue);
    expect(card.approvalRef?.state, AIAssistantApprovalState.pending);
  });

  test('terminal task previews remain valid canonical replay history', () {
    for (final state in <String>['approved', 'discarded', 'expired']) {
      final response = AIAgentGatewayResponse.fromJson(
        _response(cards: <Object?>[
          _taskPreviewCard(
            approvalRef: <String, Object?>{
              'id': _approvalA,
              'action': 'create_task',
              'expiresAt': _approvalExpiryWire,
              'state': state,
            },
          ),
        ]),
      );

      expect(response.cards.single.approvalRef?.state.isTerminal, isTrue);
    }
  });

  test('workshop previews decode only their matching closed action', () {
    final diagnosis = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[_workshopPreviewCard()]),
    ).cards.single;
    final item = AIAgentGatewayResponse.fromJson(
      _response(
        cards: <Object?>[
          _workshopPreviewCard(
            kind: 'workshop_item_preview',
            action: 'add_workshop_item',
          ),
        ],
      ),
    ).cards.single;

    expect(diagnosis.destination, AIAssistantDestination.workshopJobs);
    expect(
      diagnosis.approvalRef?.action,
      AIAssistantApprovalAction.updateDiagnosis,
    );
    expect(
      item.approvalRef?.action,
      AIAssistantApprovalAction.addWorkshopItem,
    );

    for (final invalid in <Map<String, Object?>>[
      _workshopPreviewCard(action: 'add_workshop_item'),
      _workshopPreviewCard(
        kind: 'workshop_item_preview',
        action: 'update_diagnosis',
      ),
      <String, Object?>{
        ..._workshopPreviewCard(),
        'destination': 'tasks',
      },
    ]) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(cards: <Object?>[invalid]),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$invalid',
      );
    }
  });

  test('task preview rejects malformed, broadened or misplaced approvals', () {
    final invalidApprovalRefs = <Object?>[
      <String, Object?>{
        'id': '../../approval',
        'action': 'create_task',
        'expiresAt': _approvalExpiryWire,
        'state': 'pending',
      },
      <String, Object?>{
        'id': _approvalA,
        'action': 'delete_task',
        'expiresAt': _approvalExpiryWire,
        'state': 'pending',
      },
      <String, Object?>{
        'id': _approvalA,
        'action': 'create_task',
        'expiresAt': '2026-08-12T03:45:00-04:00',
        'state': 'pending',
      },
      <String, Object?>{
        'id': _approvalA,
        'action': 'create_task',
        'expiresAt': _approvalExpiryWire,
        'state': 'unknown',
      },
      <String, Object?>{
        'id': _approvalA,
        'action': 'create_task',
        'expiresAt': _approvalExpiryWire,
        'state': 'pending',
        'task': <String, Object?>{'title': 'Model-authored mutation'},
      },
    ];

    for (final approvalRef in invalidApprovalRefs) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(
            cards: <Object?>[
              _taskPreviewCard(approvalRef: approvalRef),
            ],
          ),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$approvalRef',
      );
    }

    for (final card in <Map<String, Object?>>[
      _taskPreviewCard(kind: 'task'),
      _taskPreviewCard(destination: 'customers'),
      <String, Object?>{
        ..._taskPreviewCard(),
        'entityRef': <String, Object?>{
          'kind': 'customer',
          'id': _customerA,
        },
      },
      <String, Object?>{
        ..._taskPreviewCard(),
        'approvalRef': null,
      },
    ]) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(cards: <Object?>[card]),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$card',
      );
    }
  });

  test('approval request carries only the exact direct-command envelope', () {
    final request = AIAgentGatewayApprovalRequest(
      approvalId: _approvalA,
      decision: AIAssistantApprovalDecision.approve,
      clientActionId: _actionA,
    ).toJson();

    expect(request, <String, Object?>{
      'version': 1,
      'operation': 'approval_action',
      'approvalId': _approvalA,
      'approvalAction': 'approve',
      'clientActionId': _actionA,
    });
    expect(request, isNot(contains('message')));
    expect(request, isNot(contains('modelRole')));
    expect(request, isNot(contains('task')));
    expect(request, isNot(contains('tenantId')));
    expect(request, isNot(contains('route')));
  });

  test('approval response is terminal and constrains its resulting cards', () {
    final approved = AIAgentGatewayApprovalResponse.fromJson(
      _approvalResponse(),
    );
    final discarded = AIAgentGatewayApprovalResponse.fromJson(
      _approvalResponse(state: 'discarded', cards: const <Object?>[]),
    );

    expect(approved.state, AIAssistantApprovalState.approved);
    expect(approved.cards.single.kind, 'task');
    expect(approved.cards.single.entityRef, isNull);
    expect(approved.cards.single.approvalRef, isNull);
    expect(discarded.state, AIAssistantApprovalState.discarded);
    expect(discarded.cards, isEmpty);

    final workshop = AIAgentGatewayApprovalResponse.fromJson(
      _approvalResponse(
        cards: <Object?>[
          <String, Object?>{
            'kind': 'job',
            'title': 'PG-00420',
            'destination': 'workshop_jobs',
            'chips': <String>[],
            'entityRef': <String, Object?>{
              'kind': 'workshopJob',
              'id': _jobA,
            },
          },
        ],
      ),
    );
    expect(workshop.cards.single.entityRef?.id, _jobA);

    for (final invalid in <Map<String, Object?>>[
      _approvalResponse(state: 'pending', cards: const <Object?>[]),
      _approvalResponse(state: 'discarded'),
      _approvalResponse(
        cards: <Object?>[
          _taskPreviewCard(),
        ],
      ),
      <String, Object?>{
        ..._approvalResponse(),
        'threadId': _threadA,
      },
    ]) {
      expect(
        () => AIAgentGatewayApprovalResponse.fromJson(invalid),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$invalid',
      );
    }
  });

  test('expense and conversation cards accept only their exact closed refs',
      () {
    final response = AIAgentGatewayResponse.fromJson(
      _response(cards: <Object?>[
        <String, Object?>{
          'kind': 'expense',
          'title': 'GA-00042',
          'destination': 'expenses',
          'chips': <String>['Pendiente'],
          'entityRef': <String, Object?>{
            'kind': 'expense',
            'id': _expenseA,
          },
        },
        <String, Object?>{
          'kind': 'conversation',
          'title': 'WhatsApp sin responder',
          'destination': 'conversations',
          'chips': <String>['1 sin leer'],
          'entityRef': <String, Object?>{
            'kind': 'conversation',
            'id': _conversationA,
          },
        },
      ]),
    );

    expect(response.cards, hasLength(2));
    expect(
      response.cards[0].entityRef?.detailWorkspaceRoute,
      '/accounting/expenses/$_expenseA',
    );
    expect(response.cards[0].ctaLabel, 'Abrir gasto');
    expect(
      response.cards[1].entityRef?.detailWorkspaceRoute,
      '/chat?conversation=$_conversationA',
    );
    expect(response.cards[1].ctaLabel, 'Abrir conversación');
  });

  test('unknown, invalid, extra and mismatched entity refs reject the response',
      () {
    Map<String, Object?> card(
      Object? entityRef, {
      String kind = 'customer',
      String destination = 'customers',
    }) =>
        <String, Object?>{
          'kind': kind,
          'title': 'Resultado',
          'destination': destination,
          'chips': <String>[],
          'entityRef': entityRef,
        };

    final invalidCards = <Map<String, Object?>>[
      card(<String, Object?>{'kind': 'administrator', 'id': _customerA}),
      card(<String, Object?>{'kind': 'customer', 'id': '../../admin'}),
      card(<String, Object?>{
        'kind': 'customer',
        'id': _customerA,
        'route': '/admin',
      }),
      card(<String, Object?>{'kind': 'workshopJob', 'id': _jobA}),
      card(
        <String, Object?>{'kind': 'customer', 'id': _customerA},
        kind: 'job',
        destination: 'workshop_jobs',
      ),
      card(
        <String, Object?>{'kind': 'conversation', 'id': _conversationA},
        kind: 'expense',
        destination: 'expenses',
      ),
      card(null),
    ];

    for (final invalidCard in invalidCards) {
      expect(
        () => AIAgentGatewayResponse.fromJson(
          _response(cards: <Object?>[invalidCard]),
        ),
        throwsA(isA<AIAgentGatewayContractException>()),
        reason: '$invalidCard',
      );
    }
  });

  test('card text limits still count UTF-8 bytes when entityRef is present',
      () {
    expect(
      () => AIAgentGatewayResponse.fromJson(
        _response(cards: <Object?>[
          <String, Object?>{
            'kind': 'customer',
            'title': '🚀' * 41,
            'destination': 'customers',
            'chips': <String>[],
            'entityRef': <String, Object?>{
              'kind': 'customer',
              'id': _customerA,
            },
          },
        ]),
      ),
      throwsA(isA<AIAgentGatewayContractException>()),
    );
  });

  test('engine chains only the opaque thread and reprojects trusted job ids',
      () async {
    final transport = _QueueTransport(<Object?>[
      _response(),
      _response(runId: _runB),
    ]);
    final ids = <String>[_requestA, _requestB].iterator;
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: transport),
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );
    final jobs = <MechanicJob>[
      MechanicJob(
        id: _jobA,
        tenantId: 'tenant-a',
        jobNumber: 'PG-00001',
        customerId: 'customer-a',
        status: JobStatus.pendiente,
        clientRequest: 'Revisar frenos',
        totalCost: 0,
      ),
    ];

    await engine.sendMessage(
      'primero',
      jobs: jobs,
      jobsAreCurrentView: true,
      authority: _authority,
    );
    await engine.sendMessage('segundo', authority: _authority);

    expect(transport.bodies, hasLength(2));
    expect(transport.bodies.first, isNot(contains('threadId')));
    expect(transport.bodies.last['threadId'], _threadA);
    expect(transport.bodies.last, isNot(contains('messages')));
    final firstContext = transport.bodies.first['viewContext']! as Map;
    expect(firstContext['kind'], 'workshop_jobs');
    expect(firstContext['jobIds'], <String>[_jobA]);
  });

  test('empty or identifierless views never emit an invalid workshop context',
      () async {
    final transport = _QueueTransport(<Object?>[
      _response(),
      _response(runId: _runB),
    ]);
    final ids = <String>[_requestA, _requestB].iterator;
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: transport),
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );

    await engine.sendMessage(
      'vista vacía',
      jobs: const <MechanicJob>[],
      jobsAreCurrentView: true,
      authority: _authority,
    );
    await engine.sendMessage(
      'fila legacy',
      jobs: <MechanicJob>[
        MechanicJob(
          tenantId: 'tenant-a',
          id: 'legacy-non-uuid-id',
          jobNumber: 'PG-LEGACY',
          customerId: 'customer-a',
          status: JobStatus.pendiente,
          clientRequest: 'Revisar',
          totalCost: 0,
        ),
      ],
      jobsAreCurrentView: true,
      authority: _authority,
    );

    expect(
      (transport.bodies.first['viewContext']! as Map)['kind'],
      'none',
    );
    expect(
      (transport.bodies.last['viewContext']! as Map)['kind'],
      'rejected',
    );
  });

  test('reset aborts the active gateway turn and drops its thread generation',
      () async {
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: _BlockingTransport()),
      idFactory: () => _requestA,
    );

    final pending = engine.sendMessage('espera', authority: _authority);
    await Future<void>.delayed(Duration.zero);
    engine.resetChat();

    await expectLater(
      pending,
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.code, 'code', 'request_aborted'),
      ),
    );
  });

  test('ambiguous transport retry reuses the exact client request id',
      () async {
    final transport = _AmbiguousOnceTransport();
    final ids = <String>[_requestA, _requestB].iterator;
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: transport),
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );

    await expectLater(
      engine.sendMessage('mismo turno', authority: _authority),
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.outcomeUnknown, 'ambiguous', isTrue),
      ),
    );
    await engine.sendMessage('mismo turno', authority: _authority);
    await engine.sendMessage('turno siguiente', authority: _authority);

    expect(
      transport.bodies.map((body) => body['clientRequestId']),
      <String>[_requestA, _requestA, _requestB],
    );
    expect(transport.bodies.last['threadId'], _threadA);
  });

  test('ambiguous approval retry reuses the exact client action id', () async {
    final transport = _AmbiguousApprovalOnceTransport();
    final ids = <String>[_actionA, _actionB].iterator;
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: transport),
      idFactory: () {
        ids.moveNext();
        return ids.current;
      },
    );

    await expectLater(
      engine.resolveApproval(
        _pendingTaskApproval,
        AIAssistantApprovalDecision.approve,
        authority: _authority,
      ),
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.outcomeUnknown, 'ambiguous', isTrue),
      ),
    );
    final result = await engine.resolveApproval(
      _pendingTaskApproval,
      AIAssistantApprovalDecision.approve,
      authority: _authority,
    );

    expect(result.state, AIAssistantApprovalState.approved);
    expect(
      transport.bodies.map((body) => body['clientActionId']),
      <String>[_actionA, _actionA],
    );
    expect(
      transport.bodies.map((body) => body['approvalAction']),
      everyElement('approve'),
    );
  });

  test('reset aborts a direct approval and clears its replay generation',
      () async {
    final engine = GatewayAIAssistantTurnEngine(
      client: AIAgentGatewayClient(transport: _BlockingTransport()),
      idFactory: () => _actionA,
    );

    final pending = engine.resolveApproval(
      _pendingTaskApproval,
      AIAssistantApprovalDecision.discard,
      authority: _authority,
    );
    await Future<void>.delayed(Duration.zero);
    engine.resetChat();

    await expectLater(
      pending,
      throwsA(
        isA<AIAgentGatewayException>()
            .having((error) => error.code, 'code', 'request_aborted'),
      ),
    );
  });

  test('runtime selection is once-per-engine and never falls back by turn', () {
    final gateway = _MarkerEngine();
    final legacy = _MarkerEngine();
    var gatewayBuilds = 0;
    var legacyBuilds = 0;

    final selected = AIAssistantSessionService.buildEngineForRuntime(
      gatewayEnabled: true,
      gatewayFactory: () {
        gatewayBuilds++;
        return gateway;
      },
      legacyFactory: () {
        legacyBuilds++;
        return legacy;
      },
    );

    expect(selected, same(gateway));
    expect(gatewayBuilds, 1);
    expect(legacyBuilds, 0);
  });
}
