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
    final task = _tasks.single;
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
        jobItems: task.jobItems,
      ),
    ];
    return _tasks.single;
  }

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
      sendCommand(taskId,
          command: 'unblock', expectedVersion: expectedVersion);
  @override
  Future<WorkerTaskView> complete(String taskId, {int? expectedVersion}) =>
      sendCommand(taskId,
          command: 'complete', expectedVersion: expectedVersion);
  @override
  Future<WorkerTaskView> returnTask(String taskId, String reason) =>
      sendCommand(taskId, command: 'return', payload: {'reason': reason});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
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
        {'item_name': 'Mantención de motor', 'item_type': 'service'},
      ],
    );

void main() {
  testWidgets(
      'el portal muestra pega, bicicletas y creador, y Aceptar/Completar '
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
    expect(find.textContaining('Asignada por La Manager'), findsOneWidget);
    expect(find.textContaining('La Jefa'), findsNothing,
        reason: 'con assigned_by presente, el creador no es el nombre mostrado');
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
