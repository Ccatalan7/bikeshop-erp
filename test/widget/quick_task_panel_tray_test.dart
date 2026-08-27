import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_event.dart';
import 'package:vinabike_erp/modules/tasks/models/smart_task_job_item.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/shared/widgets/quick_task_panel.dart';

const _me = '11111111-1111-4111-8111-111111111111';

class _FakeTaskService extends ChangeNotifier implements TaskService {
  _FakeTaskService(this._tasks);

  final List<TaskModel> _tasks;

  @override
  List<TaskModel> get tasks => _tasks;

  @override
  String? get currentUserId => _me;

  @override
  ErpAuthorityScopeKey? get authorityScope => null;

  @override
  List<SmartTaskJobItem> jobItemsOf(String taskId) => const [];

  @override
  TaskLinkableJob? jobHeaderOf(TaskModel task) => task.linkedJobId == null
      ? null
      : TaskLinkableJob(
          id: task.linkedJobId!,
          jobNumber: 'PG-000777',
          status: 'PENDIENTE',
          customerName: 'Cliente Bandeja',
          clientRequest: 'Ajuste general',
        );

  @override
  Map<String, dynamic>? userStateOf(String taskId) => null;

  @override
  Future<List<TaskAssignmentPrincipal>> fetchAssignmentDirectory() async =>
      const [];

  @override
  Future<List<TaskLinkableJob>> fetchLinkableJobs({int limit = 120}) async =>
      const [];

  @override
  Future<List<SmartTaskEvent>> fetchEvents(String taskId,
          {int limit = 50}) async =>
      const [];

  @override
  Future<void> markSeen(TaskModel task) async {}

  @override
  Future<TaskModel> blockTask(String taskId, String reason,
      {int? expectedVersion}) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    final updated = _tasks[index].copyWith(
      status: TaskStatus.blocked,
      blockedAt: DateTime.now(),
      blockedReason: reason,
      version: _tasks[index].version + 1,
    );
    _tasks[index] = updated;
    notifyListeners();
    return updated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

TaskModel _task(int index,
    {DateTime? due,
    DateTime? acknowledged,
    TaskKind kind = TaskKind.task,
    String? linkedJobId}) {
  final now = DateTime.now();
  final isNote = kind == TaskKind.note;
  return TaskModel(
    id: '00000000-0000-4000-8000-0000000000$index$index',
    tenantId: 't',
    title: isNote ? 'N$index' : 'T$index',
    createdBy: _me,
    assignedTo: isNote ? null : _me,
    kind: kind,
    linkedJobId: linkedJobId,
    dueDate: due ?? DateTime(now.year, now.month, now.day, 12),
    acknowledgedAt: acknowledged,
  );
}

Widget _host(TaskService tasks, RightToolbarService toolbar,
    {Widget child = const QuickTaskPanel()}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<RightToolbarService>.value(value: toolbar),
      ChangeNotifierProvider<TaskService>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets(
      'contrato de cola compacta: al menos 8 filas ordinarias visibles en 384x824',
      (tester) async {
    tester.view.physicalSize = const Size(384, 824);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final acknowledged = DateTime.now();
    final tasks = _FakeTaskService([
      for (var i = 1; i <= 9; i++) _task(i, acknowledged: acknowledged),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    var visible = 0;
    for (var i = 1; i <= 9; i++) {
      final row =
          find.byKey(ValueKey('task-row-00000000-0000-4000-8000-0000000000$i$i'));
      if (row.evaluate().isEmpty) continue;
      final rect = tester.getRect(row);
      if (rect.bottom <= 824 && rect.top >= 0) visible++;
    }
    expect(visible, greaterThanOrEqualTo(8),
        reason: 'la cola compacta debe mostrar >= 8 filas ordinarias');
  });

  testWidgets('mi bandeja separa Por aceptar de Hoy', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(1), // sin acuse -> Por aceptar
      _task(2, acknowledged: DateTime.now()), // Hoy
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('POR ACEPTAR'), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);
  });

  testWidgets(
      'la sesión del panel preserva alcance y borrador al cerrar y reabrir',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final toolbar = RightToolbarService();
    final tasks = _FakeTaskService([_task(1, acknowledged: DateTime.now())]);

    await tester.pumpWidget(_host(tasks, toolbar));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Equipo'));
    await tester.pump();
    // El compositor abre en su host canónico (O-05 en este ancho compacto).
    await tester.tap(find.text('Nueva tarea'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
        find.widgetWithText(TextField, 'Título de la tarea…'),
        'Ajuste de cambios Trek');
    await tester.pump();

    // Cerrar la superficie (tap en la barrera) NO bota el borrador…
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // …y cerrar el panel desmonta el widget (comportamiento real del rail).
    await tester.pumpWidget(
        _host(tasks, toolbar, child: const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 100));

    // Reabrir: alcance restaurado y el borrador esperando en el compositor.
    await tester.pumpWidget(_host(tasks, toolbar));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Nueva tarea'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ajuste de cambios Trek'), findsOneWidget);
    expect(find.text('Crear tarea'), findsOneWidget);
  });

  testWidgets(
      'una Nota conserva la pega, oculta responsable y dice Guardar nota',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([_task(1, acknowledged: DateTime.now())]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Como Tarea: responsable visible.
    expect(find.text('Trabajador responsable'), findsOneWidget);

    await tester.ensureVisible(find.text('Nota'));
    await tester.pump();
    await tester.tap(find.text('Nota'));
    await tester.pump(const Duration(milliseconds: 200));

    // Como Nota: sin responsable ni servicios, la pega sigue disponible.
    expect(find.text('Trabajador responsable'), findsNothing);
    expect(find.text('Pega del taller'), findsOneWidget);
    expect(find.text('Guardar nota'), findsOneWidget);
    expect(find.text('Título de la nota…'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Abrir pega usa push y conserva el retorno', (tester) async {
    final router = GoRouter(
      initialLocation: '/origen',
      routes: [
        GoRoute(
          path: '/origen',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () => openWorkshopJobFromTray(
                    buttonContext, 'job con espacios'),
                child: const Text('Abrir pega'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/taller/pegas/:id',
          builder: (context, state) =>
              Scaffold(body: Text('Detalle ${state.pathParameters['id']}')),
        ),
      ],
    );
    final workspaces = WorkspaceManager(sessionIdentity: 'task-tray-test');
    workspaces.updateWorkspaceRouteById(
      workspaces.activeWorkspace!.id,
      '/origen',
    );
    workspaces.activeWorkspace!.router = router;
    await tester.pumpWidget(
      ChangeNotifierProvider<WorkspaceManager>.value(
        value: workspaces,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Abrir pega'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Detalle'), findsOneWidget);
    expect(workspaces.activeWorkspace!.currentRoute,
        '/taller/pegas/job%20con%20espacios');
    // push: el origen sigue en la pila y el retorno existe.
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Abrir pega'), findsOneWidget);
    expect(workspaces.activeWorkspace!.currentRoute, '/origen');
    expect(workspaces.activeWorkspace!.canGoForward, isTrue);
  });

  testWidgets(
      'una nota del equipo vive en su sección y solo ofrece Archivar nota',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(1, acknowledged: DateTime.now()),
      _task(2, kind: TaskKind.note),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Equipo'));
    await tester.pump();
    expect(find.text('NOTAS'), findsOneWidget);

    await tester.tap(find.text('N2'));
    await tester.pump(const Duration(milliseconds: 200));

    // Detalle en modo Nota: identidad y acciones propias, nada del ciclo.
    expect(find.text('Nota'), findsWidgets);
    expect(find.text('Archivar nota'), findsOneWidget);
    expect(find.text('Completar'), findsNothing);
    expect(find.text('Bloquear'), findsNothing);
    expect(find.text('Asignar'), findsNothing);
    expect(find.text('Cancelar tarea'), findsNothing);
    expect(find.byTooltip('Conversar'), findsNothing);
  });

  testWidgets(
      'una pega vinculada sin servicios es visible en fila y detalle',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(3, kind: TaskKind.note, linkedJobId: 'job-777'),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Equipo'));
    await tester.pump();

    // La fila muestra la identidad de la pega aunque no haya servicios.
    expect(find.textContaining('#PG-000777'), findsOneWidget);

    await tester.tap(find.text('N3'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('PEGA #PG-000777'), findsOneWidget);
    expect(find.text('Abrir pega'), findsOneWidget);
    expect(find.textContaining('Pega completa'), findsOneWidget);
  });

  testWidgets(
      'bloquear desde el popover espera su cierre antes de reconstruir el detalle',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(4, acknowledged: DateTime.now()),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('T4'));
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Bloquear'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Falta repuesto');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Bloquear'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bloqueada'), findsOneWidget);
    expect(find.text('Motivo: Falta repuesto'), findsOneWidget);
  });
}
