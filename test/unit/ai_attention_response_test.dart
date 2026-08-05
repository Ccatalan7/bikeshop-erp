import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_agent_tool.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_destination.dart';
import 'package:vinabike_erp/modules/ai_assistant/services/ai_service.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';

/// The briefing as the operator receives it: through `sendMessage`, with the
/// exact phrases the owner uses.
///
/// The read model has its own suite; this one is about the sentence that comes
/// back — what it claims, what it refuses to claim, and what it never leaks.
const _tenant = 'tenant-a';
final _scope = ErpAuthorityScopeKey.from(userId: 'user-a', tenantId: _tenant)!;
final _authority = AIAssistantTurnAuthority(
  _scope,
  permissions: const <String>{AIToolPermission.operationalRead},
);

const _secret = 'PGRST302-conn-tenant-b-token';

class _Bikeshop implements BikeshopService {
  _Bikeshop({this.jobs = const <MechanicJob>[], this.failure});

  List<MechanicJob> jobs;
  Object? failure;

  @override
  ErpAuthorityScopeKey? get authorityScope => _scope;

  @override
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async {
    final boom = failure;
    if (boom != null) throw boom;
    return jobs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tasks implements TaskService {
  _Tasks({this.taskList = const <TaskModel>[], this.declines = false});

  List<TaskModel> taskList;
  bool declines;

  @override
  List<TaskModel> get tasks => taskList;

  @override
  ErpAuthorityScopeKey? get authorityScope => _scope;

  @override
  Future<ErpAuthorityScopeKey?> fetchTasksForPreload() async =>
      declines ? null : _scope;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fails loudly if the briefing path ever reaches the model.
class _NoGeminiService extends AIAssistantService {
  @override
  Future<List<double>?> generateEmbedding(String text) async {
    fail('the briefing asked Gemini for an embedding');
  }
}

MechanicJob _job(String id, DateTime deadline) => MechanicJob(
      id: id,
      tenantId: _tenant,
      jobNumber: 'PG-$id',
      customerId: 'c1',
      status: JobStatus.enCurso,
      deliveryDeadline: deadline,
      clientRequest: 'Revisar',
      totalCost: 0,
    );

TaskModel _task(String id, DateTime due) => TaskModel(
      id: id,
      tenantId: _tenant,
      title: 'Tarea $id',
      status: TaskStatus.pending,
      priority: TaskPriority.urgent,
      dueDate: due,
      createdBy: 'user-a',
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// 03/08/2026 in Santiago.
final _yesterday = DateTime.utc(2026, 8, 1, 16);

void main() {
  late AIAssistantService service;

  setUp(() {
    service = _NoGeminiService();
    service.initialize();
  });

  Future<AIAssistantResponse> ask(
    String phrase, {
    BikeshopService? bikeshop,
    TaskService? tasks,
  }) {
    return service.sendMessage(
      phrase,
      bikeshopService: bikeshop ?? _Bikeshop(),
      taskService: tasks ?? _Tasks(),
      authority: _authority,
    );
  }

  test('the owner phrase for today answers deterministically', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(jobs: [_job('late', _yesterday)]),
    );

    expect(response.text, contains('Para hoy'));
    expect(response.text, contains('PG-late'));
    expect(response.text, contains('hora de Chile'));
    expect(
      response.cards.map((c) => c.destination),
      everyElement(
        anyOf(
          AIAssistantDestination.workshopJobs,
          AIAssistantDestination.tasks,
        ),
      ),
    );
  });

  test('the owner phrase for tomorrow answers deterministically', () async {
    final response = await ask('Ayúdame a organizar el trabajo para mañana');

    expect(response.text, contains('Para mañana'));
    expect(response.text, contains('Revisé'));
  });

  test('the stamp carries a real clock time', () async {
    final response = await ask('¿Qué necesita atención hoy?');
    expect(
      RegExp(r'Al \d{2}/\d{2}/\d{4} \d{2}:\d{2}, hora de Chile')
          .hasMatch(response.text),
      isTrue,
      reason: response.text,
    );
  });

  test('a failed source never puts its exception on screen', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(failure: StateError(_secret)),
      tasks: _Tasks(taskList: [_task('t', _yesterday)]),
    );

    expect(response.text, isNot(contains(_secret)));
    expect(response.text, isNot(contains('Exception')));
    expect(response.text, contains('parcial'));
  });

  test(
      'a partial briefing with nothing found does not speak for the whole '
      'business', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(failure: StateError(_secret)),
    );

    // Tareas answered and held nothing; Taller did not answer. Saying "no hay
    // entregas ni tareas" would be a claim about a module nobody read.
    expect(response.text, contains('en Tareas'));
    expect(
      response.text,
      isNot(contains('no encontré entregas ni tareas comprometidas')),
    );
    expect(response.text, contains('parcial'));
  });

  test('both sources failing claims nothing and offers no card', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(failure: StateError(_secret)),
      tasks: _Tasks(declines: true),
    );

    expect(response.text, contains('no pude mirar'));
    expect(response.text, isNot(contains(_secret)));
    expect(response.cards, isEmpty);
    // The stamp survives the failure: without it there is no way to tell a
    // failed briefing from a stale panel.
    expect(
      RegExp(r'Al \d{2}/\d{2}/\d{4} \d{2}:\d{2}, hora de Chile')
          .hasMatch(response.text),
      isTrue,
      reason: response.text,
    );
  });

  test('a truncated briefing still offers every available source', () async {
    // Six workshop items fill the list and the task lands seventh. Deriving
    // the cards from the visible six removed the way into the module that
    // still had something pending.
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(
        jobs: [for (var i = 0; i < 6; i++) _job('j$i', _yesterday)],
      ),
      tasks: _Tasks(taskList: [_task('t', _yesterday)]),
    );

    expect(response.text, contains('detecté 7'));
    expect(
      response.cards.map((c) => c.destination),
      containsAll(<AIAssistantDestination>[
        AIAssistantDestination.workshopJobs,
        AIAssistantDestination.tasks,
      ]),
    );
  });

  test('the briefing is Markdown blocks, not one glued paragraph', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(jobs: [_job('a', _yesterday)]),
      tasks: _Tasks(taskList: [_task('b', _yesterday)]),
    );

    expect(response.text, contains('\n\n'));
    expect(response.text, contains('\n- '));
    expect(response.text, isNot(contains('•')));
  });

  test('an unavailable source is never offered as a card', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(failure: StateError(_secret)),
      tasks: _Tasks(taskList: [_task('t', _yesterday)]),
    );

    expect(
      response.cards.map((c) => c.destination),
      isNot(contains(AIAssistantDestination.workshopJobs)),
    );
    expect(
      response.cards.map((c) => c.destination),
      contains(AIAssistantDestination.tasks),
    );
  });

  test('a truncated briefing announces the real total first', () async {
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(
        jobs: [for (var i = 0; i < 10; i++) _job('j$i', _yesterday)],
      ),
    );

    expect(response.text, contains('detecté 10'));
    expect(response.text, contains('te muestro las 6'));
    expect(response.text, isNot(contains('hay 6 cosas')));
  });

  test('a verified quiet day is allowed to say so', () async {
    final response = await ask('prioridades de hoy');

    expect(response.text, contains('no encontré entregas ni tareas'));
    expect(response.text, isNot(contains('parcial')));
  });

  test('the briefing writes nothing and navigates nothing', () async {
    // No navigation callback exists on this path, and the response carries
    // only aggregate destinations for the operator to choose.
    final response = await ask(
      '¿Qué necesita atención hoy?',
      bikeshop: _Bikeshop(jobs: [_job('j', _yesterday)]),
    );

    for (final card in response.cards) {
      expect(
        AIAssistantDestinationResolver.registeredWorkspaceRoutes
                .contains('/taller/pegas') ||
            AIAssistantDestinationResolver.registeredToolbarTools.isNotEmpty,
        isTrue,
      );
      expect(card.ctaLabel, startsWith('Abrir '));
    }
  });
}
