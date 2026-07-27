import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/bikeshop/widgets/pegas_tasks_widget.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  for (final width in <double>[384, 599, 600, 899]) {
    testWidgets(
      'keeps the grouped task list usable without overflow at ${width.toInt()} px',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 824));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final taskService = _SeededTaskService(_sampleTasks());
        addTearDown(taskService.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TaskService>.value(value: taskService),
              ChangeNotifierProvider<TenantService>.value(
                value: TenantService(),
              ),
              Provider<UserManagementService>.value(
                value: _EmptyUserManagementService(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: PegasTasksWidget()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('workshop-tasks-compact-controls')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('workshop-tasks-compact-list')),
          findsOneWidget,
        );
        expect(find.text('3 pendientes'), findsOneWidget);
        expect(find.text('1 en curso'), findsOneWidget);
        expect(find.text('1 completadas'), findsOneWidget);
        expect(find.text('1 vencidas'), findsOneWidget);
        expect(find.text('Revisar freno trasero'), findsOneWidget);
        expect(find.text('Confirmar repuesto'), findsNothing);
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-tasks-search'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-tasks-compact-new'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-tasks-compact-status-filter'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-tasks-compact-priority-filter'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-toggle-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-disclosure-task-overdue'),
        );
        expect(
          find.byKey(
            const ValueKey('workshop-task-compact-details-task-overdue'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(
            const ValueKey('workshop-task-compact-disclosure-task-overdue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(
            const ValueKey('workshop-task-compact-details-task-overdue'),
          ),
          findsOneWidget,
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-more-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-linked-job-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-status-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-priority-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-date-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-assignee-task-overdue'),
        );
        _expectMinimumTouchTarget(
          tester,
          const ValueKey('workshop-task-compact-attachments-task-overdue'),
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(
            const ValueKey('workshop-task-compact-status-task-overdue'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancelada'), findsOneWidget);
        await tester.tap(find.text('En Curso').last);
        await tester.pumpAndSettle();

        expect(
          taskService.tasks
              .firstWhere((task) => task.id == 'task-overdue')
              .status,
          TaskStatus.inProgress,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(
            const ValueKey('workshop-tasks-compact-status-filter'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Todos los estados'));
        await tester.pumpAndSettle();

        expect(find.text('5 visibles'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Confirmar repuesto'),
          180,
          scrollable: find.descendant(
            of: find.byKey(const ValueKey('workshop-tasks-compact-list')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text('Confirmar repuesto'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.byKey(
            const ValueKey('workshop-tasks-compact-priority-filter'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Urgente').last);
        await tester.pumpAndSettle();

        expect(find.text('Revisar freno trasero'), findsOneWidget);
        expect(find.text('Confirmar repuesto'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('shows at least eight collapsed tasks in the 384x824 canary',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final taskService = _SeededTaskService(_denseTasks(12));
    addTearDown(taskService.dispose);

    await tester.pumpWidget(
      _taskProviders(
        taskService: taskService,
        child: const MaterialApp(
          home: Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final viewport = tester.getRect(
      find.byKey(const ValueKey('workshop-tasks-compact-list')),
    );
    for (var index = 0; index < 8; index++) {
      final task = find.byKey(ValueKey('workshop-task-compact-dense-$index'));
      expect(task, findsOneWidget);
      expect(
        tester.getRect(task).bottom,
        lessThanOrEqualTo(viewport.bottom + 0.5),
        reason: 'dense task $index was not fully visible',
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[900, 1440]) {
    testWidgets(
      'preserves the dense task table at ${width.toInt()} px',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 824));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final taskService = _SeededTaskService(_sampleTasks());
        addTearDown(taskService.dispose);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<TaskService>.value(value: taskService),
              ChangeNotifierProvider<TenantService>.value(
                value: TenantService(),
              ),
              Provider<UserManagementService>.value(
                value: _EmptyUserManagementService(),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(body: PegasTasksWidget()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('workshop-tasks-compact-controls')),
          findsNothing,
        );
        expect(find.text('Nueva Tarea'), findsOneWidget);
        expect(find.text('Tarea'), findsOneWidget);
        expect(find.text('Estado'), findsOneWidget);
        expect(find.text('Prioridad'), findsWidgets);
        expect(find.text('Adjuntos'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('opens the task form without overflow at the narrow mobile width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(336, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final taskService = _SeededTaskService(_sampleTasks());
    addTearDown(taskService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskService>.value(value: taskService),
          ChangeNotifierProvider<TenantService>.value(value: TenantService()),
          Provider<UserManagementService>.value(
            value: _EmptyUserManagementService(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('workshop-tasks-compact-new')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nueva Tarea'), findsOneWidget);
    expect(find.text('Título de la tarea'), findsOneWidget);
    expect(find.text('Guardar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps compact controls readable with increased text scale',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final taskService = _SeededTaskService(_sampleTasks());
    addTearDown(taskService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskService>.value(value: taskService),
          ChangeNotifierProvider<TenantService>.value(value: TenantService()),
          Provider<UserManagementService>.value(
            value: _EmptyUserManagementService(),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
              ),
              child: child!,
            );
          },
          home: const Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-tasks-compact-controls')),
      findsOneWidget,
    );
    expect(find.text('Revisar freno trasero'), findsOneWidget);
    _expectMinimumTouchTarget(
      tester,
      const ValueKey('workshop-tasks-search'),
    );
    await tester.tap(
      find.byKey(
        const ValueKey('workshop-task-compact-disclosure-task-overdue'),
      ),
    );
    await tester.pumpAndSettle();
    _expectMinimumTouchTarget(
      tester,
      const ValueKey('workshop-task-linked-job-task-overdue'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('distinguishes a true empty list from filtered-out tasks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final emptyService = _SeededTaskService(<TaskModel>[]);
    addTearDown(emptyService.dispose);
    await tester.pumpWidget(
      _taskProviders(
        taskService: emptyService,
        child: const MaterialApp(
          home: Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-tasks-empty')),
      findsOneWidget,
    );
    expect(find.text('Aún no hay tareas'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('workshop-tasks-filtered-empty')),
      findsNothing,
    );

    final filteredService = _SeededTaskService(_sampleTasks());
    addTearDown(filteredService.dispose);
    await tester.pumpWidget(
      _taskProviders(
        taskService: filteredService,
        child: const MaterialApp(
          home: Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('workshop-tasks-search')),
      'sin coincidencias',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-tasks-filtered-empty')),
      findsOneWidget,
    );
    expect(find.text('Sin resultados para estos filtros'), findsOneWidget);
    _expectMinimumTouchTarget(
      tester,
      const ValueKey('workshop-tasks-clear-filters'),
    );

    await tester.tap(
      find.byKey(const ValueKey('workshop-tasks-clear-filters')),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('workshop-tasks-compact-list')),
      findsOneWidget,
    );
    expect(find.text('5 visibles'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inherits the root compact layout and restores filters after remount',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 824));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final taskService = _SeededTaskService(_sampleTasks());
      addTearDown(taskService.dispose);
      final session = PegasTasksSession(statusFilter: null);

      Widget buildSurface() => _taskProviders(
            taskService: taskService,
            child: MaterialApp(
              home: Scaffold(
                body: PegasTasksWidget(
                  useCompactLayout: true,
                  session: session,
                ),
              ),
            ),
          );

      await tester.pumpWidget(buildSurface());
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('workshop-tasks-compact-controls')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(
          const ValueKey('workshop-tasks-compact-priority-filter'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alta').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workshop-tasks-search')),
        'Confirmar',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(
          const ValueKey('workshop-task-compact-disclosure-task-progress'),
        ),
      );
      await tester.pumpAndSettle();

      expect(session.priorityFilter, TaskPriority.high);
      expect(session.searchQuery, 'Confirmar');
      expect(session.expandedTaskKeys, contains('task-progress'));
      expect(
        find.byKey(
          const ValueKey('workshop-task-compact-details-task-progress'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildSurface());
      await tester.pump();
      await tester.pump();

      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey('workshop-tasks-search')),
      );
      expect(searchField.controller?.text, 'Confirmar');
      expect(find.text('Confirmar repuesto'), findsOneWidget);
      expect(find.text('Preparar presupuesto'), findsNothing);
      expect(
        find.byKey(
          const ValueKey('workshop-task-compact-details-task-progress'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restores the compact task scroll position after remount',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final taskService = _SeededTaskService(_denseTasks(18));
    addTearDown(taskService.dispose);
    final session = PegasTasksSession(statusFilter: null);

    Widget buildSurface() => _taskProviders(
          taskService: taskService,
          child: MaterialApp(
            home: Scaffold(
              body: PegasTasksWidget(
                useCompactLayout: true,
                session: session,
              ),
            ),
          ),
        );

    await tester.pumpWidget(buildSurface());
    await tester.pump();
    await tester.pump();
    final list = find.byKey(const ValueKey('workshop-tasks-compact-list'));
    await tester.drag(list, const Offset(0, -260));
    await tester.pump();

    final savedOffset = session.scrollOffset;
    expect(savedOffset, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildSurface());
    await tester.pump();
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    expect(scrollable.position.pixels, closeTo(savedOffset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens the exact linked job and preserves task list context',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(384, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final taskService = _SeededTaskService(_sampleTasks());
    addTearDown(taskService.dispose);
    final router = GoRouter(
      initialLocation: '/tasks',
      routes: [
        GoRoute(
          path: '/tasks',
          builder: (context, state) => const Scaffold(body: PegasTasksWidget()),
        ),
        GoRoute(
          path: '/taller/pegas/:id',
          builder: (context, state) => Scaffold(
            body: Column(
              children: [
                Text('Destino ${state.pathParameters['id']}'),
                TextButton(
                  key: const ValueKey('linked-job-back'),
                  onPressed: context.pop,
                  child: const Text('Volver a tareas'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _taskProviders(
        taskService: taskService,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('workshop-tasks-search')),
      'Revisar',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const ValueKey('workshop-task-compact-disclosure-task-overdue'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('workshop-task-linked-job-task-overdue')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Destino job-1'), findsOneWidget);
    expect(find.text('Volver a tareas'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('linked-job-back')));
    await tester.pumpAndSettle();

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey('workshop-tasks-search')),
    );
    expect(searchField.controller?.text, 'Revisar');
    expect(find.text('Revisar freno trasero'), findsOneWidget);
    expect(find.text('Preparar presupuesto'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _taskProviders({
  required TaskService taskService,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<TaskService>.value(value: taskService),
      ChangeNotifierProvider<TenantService>.value(value: TenantService()),
      Provider<UserManagementService>.value(
        value: _EmptyUserManagementService(),
      ),
    ],
    child: child,
  );
}

void _expectMinimumTouchTarget(
  WidgetTester tester,
  Key key,
) {
  final size = tester.getSize(find.byKey(key));
  expect(size.width, greaterThanOrEqualTo(48), reason: '$key width was $size');
  expect(size.height, greaterThanOrEqualTo(48),
      reason: '$key height was $size');
}

List<TaskModel> _sampleTasks() {
  final now = DateTime.now();
  return [
    TaskModel(
      id: 'task-overdue',
      tenantId: 'tenant-test',
      title: 'Revisar freno trasero',
      description: 'Validar roce antes de llamar al cliente.',
      status: TaskStatus.pending,
      priority: TaskPriority.urgent,
      dueDate: now.subtract(const Duration(days: 1)),
      assignedTo: 'worker-1',
      assigneeName: 'Catalina Mecánica',
      linkedJobId: 'job-1',
      linkedJobNumber: 'PG-00482',
      createdBy: 'worker-1',
    ),
    TaskModel(
      id: 'task-pending-2',
      tenantId: 'tenant-test',
      title: 'Preparar presupuesto',
      status: TaskStatus.pending,
      priority: TaskPriority.normal,
      dueDate: now.add(const Duration(days: 2)),
      createdBy: 'worker-1',
    ),
    TaskModel(
      id: 'task-pending-3',
      tenantId: 'tenant-test',
      title: 'Llamar al cliente',
      status: TaskStatus.pending,
      priority: TaskPriority.high,
      createdBy: 'worker-1',
    ),
    TaskModel(
      id: 'task-progress',
      tenantId: 'tenant-test',
      title: 'Confirmar repuesto',
      status: TaskStatus.inProgress,
      priority: TaskPriority.high,
      createdBy: 'worker-1',
    ),
    TaskModel(
      id: 'task-completed',
      tenantId: 'tenant-test',
      title: 'Entregar bicicleta',
      status: TaskStatus.completed,
      priority: TaskPriority.low,
      createdBy: 'worker-1',
    ),
  ];
}

List<TaskModel> _denseTasks(int count) {
  return List<TaskModel>.generate(
    count,
    (index) => TaskModel(
      id: 'dense-$index',
      tenantId: 'tenant-test',
      title: 'Tarea compacta ${index + 1}',
      status: TaskStatus.pending,
      priority: TaskPriority.normal,
      createdBy: 'worker-1',
    ),
  );
}

class _SeededTaskService extends TaskService {
  _SeededTaskService(this.seededTasks)
      : super(Supabase.instance.client, TenantService());

  final List<TaskModel> seededTasks;

  @override
  List<TaskModel> get tasks => seededTasks;

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<void> fetchTasks() async {}

  @override
  Future<void> updateTask(TaskModel task) async {
    final index = seededTasks.indexWhere((item) => item.id == task.id);
    if (index != -1) seededTasks[index] = task;
    notifyListeners();
  }
}

class _EmptyUserManagementService extends UserManagementService {
  _EmptyUserManagementService() : super(TenantService());

  @override
  Future<List<Map<String, dynamic>>> getTenantUsers() async => [];
}
