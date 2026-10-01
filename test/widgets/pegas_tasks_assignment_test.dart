// C1 (2026-09-30): «Asignado» de la lista de tareas del taller. Leía
// `get_tenant_users`, que es de administración (a un mecánico el menú le
// quedaba en «Cargando usuarios...») y cuyas filas traen `id`, no `user_id`:
// ninguna opción asignaba. Ahora usa el directorio de la bandeja, igual que
// «Reasignar» del rail: un trabajador se asigna como trabajador y, sobre un
// trabajo del taller, sólo quien tiene ficha.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/bikeshop/widgets/pegas_tasks_widget.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

const _tenant = 'tenant-test';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<_DirectoryTaskService> pumpList(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DirectoryTaskService([
      TaskModel(
        id: 'task-free',
        tenantId: _tenant,
        title: 'Llamar al cliente',
        status: TaskStatus.pending,
        createdBy: 'user-shop',
      ),
      TaskModel(
        id: 'task-on-job',
        tenantId: _tenant,
        title: 'Cambiar pastillas',
        status: TaskStatus.pending,
        linkedJobId: 'job-1',
        linkedJobNumber: 'PG-00482',
        createdBy: 'user-shop',
      ),
    ]);
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskService>.value(value: service),
          ChangeNotifierProvider<TenantService>.value(value: TenantService()),
        ],
        child: MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: Brightness.light,
          ),
          home: const Scaffold(body: PegasTasksWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('assigns a worker without an account from the directory',
      (tester) async {
    final service = await pumpList(tester);

    await tester
        .tap(find.byKey(const ValueKey('workshop-task-assignee-task-free')));
    await tester.pumpAndSettle();
    expect(find.text('Javiera Soto'), findsOneWidget);
    expect(find.text('Cuenta de la tienda'), findsOneWidget);
    expect(find.text('Sin cuenta: la verá cuando tenga una'), findsOneWidget);
    await tester.tap(find.text('Pedro Díaz'));
    await tester.pumpAndSettle();

    expect(service.assigned, hasLength(1));
    expect(service.assigned.single.taskId, 'task-free');
    expect(service.assigned.single.principal?.employeeId, 'employee-pedro');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a task on a workshop job offers only people with a worker file',
      (tester) async {
    final service = await pumpList(tester);

    await tester
        .tap(find.byKey(const ValueKey('workshop-task-assignee-task-on-job')));
    await tester.pumpAndSettle();
    expect(find.text('Javiera Soto'), findsOneWidget);
    expect(find.text('Pedro Díaz'), findsOneWidget);
    expect(find.text('Cuenta de la tienda'), findsNothing,
        reason: 'the server refuses it: assignee_not_worker_linked');
    await tester.tap(find.text('Javiera Soto'));
    await tester.pumpAndSettle();

    expect(service.assigned.single.principal?.employeeId, 'employee-javiera');
    expect(tester.takeException(), isNull);
  });
}

class _DirectoryTaskService extends TaskService {
  _DirectoryTaskService(this.seededTasks)
      : super(Supabase.instance.client, TenantService());

  final List<TaskModel> seededTasks;
  final List<({String taskId, TaskAssignmentPrincipal? principal})> assigned =
      [];

  @override
  List<TaskModel> get tasks => seededTasks;

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<void> fetchTasks() async {}

  @override
  Future<List<TaskAssignmentPrincipal>> fetchAssignmentDirectory() async => [
        const TaskAssignmentPrincipal(
          tenantId: _tenant,
          userId: 'user-javiera',
          employeeId: 'employee-javiera',
          displayName: 'Javiera Soto',
          role: 'mechanic',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        const TaskAssignmentPrincipal(
          tenantId: _tenant,
          userId: 'user-shop',
          employeeId: null,
          displayName: 'Cuenta de la tienda',
          role: 'admin',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        const TaskAssignmentPrincipal(
          tenantId: _tenant,
          userId: null,
          employeeId: 'employee-pedro',
          displayName: 'Pedro Díaz',
          role: 'worker',
          photoUrl: null,
          access: TaskPrincipalAccess.none,
        ),
      ];

  @override
  Future<TaskModel> assignTaskToPrincipal(
    String taskId,
    TaskAssignmentPrincipal? assignee, {
    int? expectedVersion,
  }) async {
    assigned.add((taskId: taskId, principal: assignee));
    return seededTasks.firstWhere((task) => task.id == taskId);
  }
}
