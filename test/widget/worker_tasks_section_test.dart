import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/worker_portal/services/worker_tasks_service.dart';
import 'package:vinabike_erp/modules/worker_portal/widgets/worker_tasks_section.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

class _FakeWorkerTasksService implements WorkerTasksService {
  _FakeWorkerTasksService(this._tasks);

  List<WorkerTaskView> _tasks;
  int fetchCalls = 0;
  final List<String> commands = [];
  final List<Map<String, dynamic>> payloads = [];

  @override
  Future<List<WorkerTaskView>> fetchMyTasks() async {
    fetchCalls++;
    return _tasks;
  }

  @override
  Future<WorkerTaskView> sendCommand(
    String taskId, {
    required String command,
    int? expectedVersion,
    Map<String, dynamic> payload = const {},
  }) async {
    commands.add(command);
    payloads.add(payload);
    final task = _tasks.single;
    final jobItems = command == 'set_job_item_done'
        ? [
            for (final item in task.jobItems)
              item['job_item_id'] == payload['job_item_id']
                  ? {
                      ...item,
                      'done_at': payload['done'] == true
                          ? '2026-09-26T18:10:00Z'
                          : null,
                      'done_by_name':
                          payload['done'] == true ? 'Braulio Muñoz' : null,
                    }
                  : item,
          ]
        : task.jobItems;
    _tasks = [
      WorkerTaskView(
        id: task.id,
        title: task.title,
        description: task.description,
        status: command == 'complete' ? 'completed' : task.status,
        priority: task.priority,
        dueDate: task.dueDate,
        version: task.version + 1,
        acknowledgedAt:
            command == 'acknowledge' ? DateTime.now() : task.acknowledgedAt,
        startedAt: task.startedAt,
        completedAt: command == 'complete' ? DateTime.now() : null,
        blockedReason: task.blockedReason,
        createdAt: task.createdAt,
        creatorName: task.creatorName,
        assignerName: task.assignerName,
        jobId: task.jobId,
        jobNumber: task.jobNumber,
        bikeLabels: task.bikeLabels,
        jobItems: jobItems,
        handoffNote: command == 'set_handoff_note'
            ? (payload['note'] as String).isEmpty
                ? null
                : payload['note'] as String
            : task.handoffNote,
        handoffNoteAt: task.handoffNoteAt,
        handoffNoteByName: task.handoffNoteByName,
      ),
    ];
    return _tasks.single;
  }

  @override
  Future<WorkerTaskView> setJobItemDone(String taskId, String jobItemId,
          {required bool done}) =>
      sendCommand(taskId,
          command: 'set_job_item_done',
          payload: {'job_item_id': jobItemId, 'done': done});
  @override
  Future<WorkerTaskView> setHandoffNote(String taskId, String? note) =>
      sendCommand(taskId,
          command: 'set_handoff_note', payload: {'note': note?.trim() ?? ''});

  // `implements` no hereda los wrappers concretos: se delegan explícitos.
  @override
  Future<WorkerTaskView> acknowledge(String taskId) =>
      sendCommand(taskId, command: 'acknowledge');
  @override
  Future<WorkerTaskView> start(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'start', expectedVersion: expectedVersion);
  @override
  Future<WorkerTaskView> block(String taskId, String reason,
          {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'block',
          expectedVersion: expectedVersion,
          payload: {'reason': reason});
  @override
  Future<WorkerTaskView> unblock(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId, command: 'unblock', expectedVersion: expectedVersion);
  @override
  Future<WorkerTaskView> complete(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'complete', expectedVersion: expectedVersion);
  @override
  Future<WorkerTaskView> returnTask(String taskId, String reason) =>
      sendCommand(taskId, command: 'return', payload: {'reason': reason});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WorkerTaskView _task() => WorkerTaskView(
      id: '11111111-1111-4111-8111-111111111111',
      title: 'Mantención de motor',
      description: 'Cliente reporta ruido',
      status: 'pending',
      priority: 'normal',
      dueDate: null,
      version: 1,
      acknowledgedAt: null,
      startedAt: null,
      completedAt: null,
      blockedReason: null,
      createdAt: DateTime(2026, 8, 26),
      creatorName: 'La Jefa',
      // Reasignada por alguien distinto del creador: ese es el nombre que
      // el trabajador debe ver.
      assignerName: 'La Manager',
      jobId: 'j',
      jobNumber: 'PG-000123',
      bikeLabels: const ['Trek 820', 'Giant Talon'],
      jobItems: const [
        {
          'item_name': 'Mantención de motor',
          'item_instructions':
              'REVISIÓN DE HORQUILLA/DIRECCIÓN ANTES DE REINSTALAR',
          'item_type': 'service',
        },
      ],
    );

WorkerTaskView _acceptedWithServices({String? note}) => WorkerTaskView(
      id: '22222222-2222-4222-8222-222222222222',
      title: 'Hacer el trabajo de la Trek',
      description: null,
      status: 'in_progress',
      priority: 'normal',
      dueDate: null,
      version: 3,
      acknowledgedAt: DateTime(2026, 9, 26, 9),
      startedAt: DateTime(2026, 9, 26, 9, 5),
      completedAt: null,
      blockedReason: null,
      createdAt: DateTime(2026, 9, 26, 8),
      creatorName: 'La Manager',
      assignerName: 'La Manager',
      jobId: 'j',
      jobNumber: 'PG-000124',
      bikeLabels: const ['Trek Marlin 7'],
      jobItems: const [
        {
          'job_item_id': 'item-cadena',
          'item_name': 'Cambio de cadena',
          'item_type': 'service',
          'done_at': '2026-09-26T15:10:00Z',
          'done_by_name': 'Braulio Muñoz',
        },
        {
          'job_item_id': 'item-frenos',
          'item_name': 'Purga de frenos',
          'item_type': 'service',
        },
      ],
      handoffNote: note,
      handoffNoteAt: note == null ? null : DateTime.utc(2026, 9, 26, 21, 40),
      handoffNoteByName: note == null ? null : 'Braulio Muñoz',
    );

Future<void> _pumpSection(
    WidgetTester tester, _FakeWorkerTasksService fake) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: WorkerTasksSection(service: fake, enableRealtime: false),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('el trabajador marca cada servicio y ve quién hizo cada uno',
      (tester) async {
    final fake = _FakeWorkerTasksService([_acceptedWithServices()]);
    await _pumpSection(tester, fake);

    expect(find.text('1 de 2 servicios hechos'), findsOneWidget);
    expect(find.textContaining('Hecho · Braulio Muñoz'), findsOneWidget);

    await tester
        .tap(find.byKey(const ValueKey('worker-task-service-item-frenos')));
    await tester.pump();
    // La casilla responde antes de que vuelva la red.
    expect(find.text('Todos los servicios hechos'), findsOneWidget);
    await tester.pump();
    await tester.pump();

    expect(fake.commands, ['set_job_item_done']);
    expect(fake.payloads.single, {'job_item_id': 'item-frenos', 'done': true});
    expect(find.text('Todos los servicios hechos'), findsOneWidget);
    // Con todo hecho, Completar pasa a ser la acción principal.
    expect(
        find.ancestor(
            of: find.text('Completar'), matching: find.byType(FilledButton)),
        findsOneWidget);
  });

  testWidgets('la nota del turno se ve con quién la dejó', (tester) async {
    final fake = _FakeWorkerTasksService(
        [_acceptedWithServices(note: 'Falta la piola; llega mañana')]);
    await _pumpSection(tester, fake);

    expect(
        find.byKey(const ValueKey('worker-task-handoff-note')), findsOneWidget);
    expect(find.text('Falta la piola; llega mañana'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('worker-task-handoff-note')),
            matching: find.textContaining('Braulio Muñoz ·')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('worker-task-handoff-add')), findsNothing);

    await tester.tap(find.text('Borrar'));
    await tester.pump();
    await tester.pump();
    expect(fake.commands, ['set_handoff_note']);
    expect(fake.payloads.single, {'note': ''});
    expect(
        find.byKey(const ValueKey('worker-task-handoff-add')), findsOneWidget);
  });

  testWidgets(
      'el portal muestra trabajo, bicicletas y creador, y Aceptar/Completar '
      'recargan la proyección', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fake = _FakeWorkerTasksService([_task()]);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WorkerTasksSection(service: fake, enableRealtime: false),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Mantención de motor'), findsWidgets);
    expect(find.textContaining('PG-000123'), findsOneWidget);
    expect(find.textContaining('Trek 820'), findsOneWidget);
    expect(
      find.text('REVISIÓN DE HORQUILLA/DIRECCIÓN ANTES DE REINSTALAR'),
      findsOneWidget,
    );
    expect(find.textContaining('Asignada por La Manager'), findsOneWidget);
    expect(find.textContaining('La Jefa'), findsNothing,
        reason:
            'con assigned_by presente, el creador no es el nombre mostrado');
    expect(fake.fetchCalls, 1);

    await tester.ensureVisible(find.text('Aceptar'));
    await tester.tap(find.text('Aceptar'));
    await tester.pump();
    await tester.pump();
    expect(fake.commands, ['acknowledge']);
    expect(fake.fetchCalls, 2, reason: 'la acción recarga la proyección');

    await tester.ensureVisible(find.text('Completar').first);
    await tester.tap(find.text('Completar').first);
    await tester.pump();
    await tester.pump();
    expect(fake.commands, ['acknowledge', 'complete']);
    expect(find.textContaining('COMPLETADAS'), findsOneWidget);
  });
}
