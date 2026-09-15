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
  _FakeTaskService(
    this._tasks, {
    List<TaskAssignmentPrincipal> directory = const [],
    List<TaskLinkableJob> linkableJobs = const [],
    Map<String, List<TaskJobWorkItem>> jobItemsByJob = const {},
    Map<String, List<SmartTaskJobItem>> jobLinksByTask = const {},
    Map<TaskContextKind, List<TaskContextTarget>> contextTargetsByKind =
        const {},
  })  : _directory = directory,
        _linkableJobs = linkableJobs,
        _jobItemsByJob = jobItemsByJob,
        _jobLinksByTask = jobLinksByTask,
        _contextTargetsByKind = contextTargetsByKind;

  final List<TaskModel> _tasks;
  final List<TaskAssignmentPrincipal> _directory;
  final List<TaskLinkableJob> _linkableJobs;
  final Map<String, List<TaskJobWorkItem>> _jobItemsByJob;
  final Map<String, List<SmartTaskJobItem>> _jobLinksByTask;
  final Map<TaskContextKind, List<TaskContextTarget>> _contextTargetsByKind;

  String? createdLinkedJobId;
  List<String>? createdJobItemIds;
  String? createdLinkedCustomerId;
  String? createdLinkedSupplierId;
  String? createdLinkedPurchaseInvoiceId;
  String? createdLinkedSalesInvoiceId;
  int fetchLinkableJobsCalls = 0;

  @override
  List<TaskModel> get tasks => _tasks;

  @override
  String? get currentUserId => _me;

  @override
  ErpAuthorityScopeKey? get authorityScope => null;

  @override
  List<SmartTaskJobItem> jobItemsOf(String taskId) =>
      _jobLinksByTask[taskId] ?? const [];

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
      _directory;

  @override
  Future<List<TaskLinkableJob>> fetchLinkableJobs({int limit = 120}) async {
    fetchLinkableJobsCalls++;
    return _linkableJobs;
  }

  @override
  Future<List<TaskContextTarget>> fetchLinkTargets(
          TaskContextKind kind) async =>
      _contextTargetsByKind[kind] ?? const [];

  @override
  Future<List<TaskJobWorkItem>> fetchJobWorkItems(String jobId) async =>
      _jobItemsByJob[jobId] ?? const [];

  @override
  Future<TaskModel> createTrayTask({
    required String title,
    String? description,
    TaskKind kind = TaskKind.task,
    TaskVisibility visibility = TaskVisibility.team,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
    String? assignedTo,
    String? linkedJobId,
    List<String>? jobItemIds,
    String? overlapDecision,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? idempotencyKey,
  }) async {
    createdLinkedJobId = linkedJobId;
    createdJobItemIds = jobItemIds == null ? null : [...jobItemIds];
    createdLinkedCustomerId = linkedCustomerId;
    createdLinkedSupplierId = linkedSupplierId;
    createdLinkedPurchaseInvoiceId = linkedPurchaseInvoiceId;
    createdLinkedSalesInvoiceId = linkedSalesInvoiceId;
    return TaskModel(
      id: '99999999-9999-4999-8999-999999999999',
      tenantId: 't',
      title: title,
      createdBy: _me,
      assignedTo: assignedTo,
      kind: kind,
      visibility: visibility,
      priority: priority,
      dueDate: dueDate,
      linkedJobId: linkedJobId,
      linkedCustomerId: linkedCustomerId,
      linkedSupplierId: linkedSupplierId,
      linkedPurchaseInvoiceId: linkedPurchaseInvoiceId,
      linkedSalesInvoiceId: linkedSalesInvoiceId,
    );
  }

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TaskModel _task(int index,
    {DateTime? due,
    DateTime? acknowledged,
    TaskKind kind = TaskKind.task,
    String? linkedJobId,
    String? linkedCustomerId,
    String? linkedCustomerName}) {
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
    linkedCustomerId: linkedCustomerId,
    linkedCustomerName: linkedCustomerName,
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

Future<void> _chooseComposerContext(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(find.text('Sin vínculo'));
  await tester.tap(find.text('Sin vínculo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
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
      final row = find
          .byKey(ValueKey('task-row-00000000-0000-4000-8000-0000000000$i$i'));
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

  testWidgets('el selector explica el acceso sin filtrar roles internos',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService(
      [_task(1, acknowledged: DateTime.now())],
      directory: const [
        TaskAssignmentPrincipal(
          tenantId: 't',
          userId: 'owner',
          employeeId: null,
          displayName: 'Viñabike',
          role: 'admin',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        TaskAssignmentPrincipal(
          tenantId: 't',
          userId: 'portal',
          employeeId: 'employee',
          displayName: 'Fernando José Tapia Carrillo',
          role: 'worker',
          photoUrl: null,
          access: TaskPrincipalAccess.portal,
        ),
      ],
    );
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    final assigneeField = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Trabajador responsable',
    );
    expect(assigneeField, findsOneWidget);
    await tester.tap(assigneeField);
    await tester.pumpAndSettle();

    expect(find.text('Administración'), findsOneWidget);
    expect(find.text('Recibe tareas en su portal'), findsOneWidget);
    expect(find.textContaining('Portal ·'), findsNothing);
    expect(find.text('worker'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'el compositor nace neutral y ofrece contextos sin mostrar sus controles',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(1, acknowledged: DateTime.now()),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();

    expect(find.text('Vincular a (opcional)'), findsOneWidget);
    expect(find.text('Sin vínculo'), findsOneWidget);
    expect(find.text('1 · Trabajo'), findsNothing);
    expect(find.text('2 · Alcance de la tarea'), findsNothing);

    await tester.tap(find.text('Sin vínculo'));
    await tester.pumpAndSettle();
    expect(find.text('Trabajo del taller'), findsOneWidget);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('Proveedor'), findsOneWidget);
    expect(find.text('Venta / factura'), findsOneWidget);
    expect(find.text('Compra / documento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'el compositor elige primero un trabajo y después su alcance de servicios',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService(
      [_task(1, acknowledged: DateTime.now())],
      linkableJobs: const [
        TaskLinkableJob(
          id: 'job-528',
          jobNumber: 'PG-00528',
          status: 'EN_PROCESO',
          customerName: 'Vicente Hernandez',
          clientRequest: 'Cambio de cadena, regulación de cambios y frenos.',
        ),
        TaskLinkableJob(
          id: 'job-527',
          jobNumber: 'PG-00527',
          status: 'EN_PROCESO',
          customerName: 'Exequiel Araya',
          clientRequest: 'Revisión de cambio trasero',
        ),
      ],
      jobItemsByJob: const {
        'job-528': [
          TaskJobWorkItem(
            id: 'service-chain',
            name: 'Cambio de cadena',
            itemType: 'service',
            jobBikeId: 'bike-1',
            bikeLabel: 'Trek Marlin 7',
            instructions: 'CAMBIAR CADENA Y AJUSTAR TENSIÓN.',
          ),
          TaskJobWorkItem(
            id: 'service-gears',
            name: 'Regulación de cambios y frenos',
            itemType: 'service',
            jobBikeId: 'bike-1',
            bikeLabel: 'Trek Marlin 7',
          ),
        ],
      },
    );
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Título de la tarea…'),
      'Realizar trabajo de Vicente',
    );
    await _chooseComposerContext(tester, 'Trabajo del taller');

    final jobField = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == '1 · Trabajo',
    );
    expect(jobField, findsOneWidget);
    await tester.tap(jobField);
    await tester.pumpAndSettle();

    // El primer nivel contiene sólo trabajos. La solicitud sigue indexada para
    // buscar, pero no se imprime como si fuera otra opción de servicio.
    expect(find.text('#PG-00528 · Vicente Hernandez'), findsOneWidget);
    expect(find.text('#PG-00527 · Exequiel Araya'), findsOneWidget);
    expect(find.text('Sin trabajo seleccionado'), findsWidgets);
    expect(find.text('Sin especificar'), findsNothing);
    expect(
      find.text('Cambio de cadena, regulación de cambios y frenos.'),
      findsNothing,
    );
    expect(find.text('Revisión de cambio trasero'), findsNothing);

    await tester.tap(find.text('#PG-00528 · Vicente Hernandez'));
    await tester.pumpAndSettle();

    expect(find.text('2 · Alcance de la tarea'), findsOneWidget);
    expect(find.text('Trabajo completo'), findsOneWidget);
    expect(find.text('Por servicios'), findsOneWidget);
    expect(find.text('Se incluirán los 2 servicios de este trabajo.'),
        findsOneWidget);
    expect(find.text('Cambio de cadena'), findsNothing);

    await tester.tap(find.text('Por servicios'));
    await tester.pump();

    expect(find.text('Cambio de cadena'), findsOneWidget);
    expect(find.text('CAMBIAR CADENA Y AJUSTAR TENSIÓN.'), findsOneWidget);
    expect(find.text('Regulación de cambios y frenos'), findsOneWidget);
    expect(find.text('Selecciona al menos un servicio.'), findsOneWidget);
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((checkbox) => checkbox.value == false),
      isTrue,
    );

    await tester.tap(find.text('Cambio de cadena'));
    await tester.pump();
    expect(find.text('Selecciona al menos un servicio.'), findsNothing);

    await tester.ensureVisible(find.text('Crear tarea'));
    await tester.tap(find.text('Crear tarea'));
    await tester.pumpAndSettle();

    expect(tasks.createdLinkedJobId, 'job-528');
    expect(tasks.createdJobItemIds, ['service-chain']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trabajo completo envía todos sus servicios reales',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService(
      [_task(1, acknowledged: DateTime.now())],
      linkableJobs: const [
        TaskLinkableJob(
          id: 'job-1',
          jobNumber: 'PG-00001',
          status: 'EN_PROCESO',
          customerName: 'Cliente Uno',
          clientRequest: 'Solicitud',
        ),
      ],
      jobItemsByJob: const {
        'job-1': [
          TaskJobWorkItem(
            id: 'service-a',
            name: 'Servicio A',
            itemType: 'service',
            jobBikeId: null,
            bikeLabel: null,
          ),
          TaskJobWorkItem(
            id: 'service-b',
            name: 'Servicio B',
            itemType: 'adhoc',
            jobBikeId: null,
            bikeLabel: null,
          ),
        ],
      },
    );
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Título de la tarea…'),
      'Resolver trabajo completo',
    );
    await _chooseComposerContext(tester, 'Trabajo del taller');
    await tester.tap(find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == '1 · Trabajo',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#PG-00001 · Cliente Uno'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Crear tarea'));
    await tester.tap(find.text('Crear tarea'));
    await tester.pumpAndSettle();

    expect(tasks.createdLinkedJobId, 'job-1');
    expect(
        tasks.createdJobItemIds, unorderedEquals(['service-a', 'service-b']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('un vínculo a cliente se carga bajo demanda y viaja solo',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService(
      [_task(1, acknowledged: DateTime.now())],
      contextTargetsByKind: const {
        TaskContextKind.customer: [
          TaskContextTarget(
            kind: TaskContextKind.customer,
            id: 'customer-1',
            label: 'María González',
            context: '+56 9 1234 5678',
            route: '/clientes/customer-1',
          ),
        ],
      },
    );
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Nueva tarea'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Título de la tarea…'),
      'Llamar por retiro',
    );
    await _chooseComposerContext(tester, 'Cliente');

    final customerField = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == 'Cliente',
    );
    expect(customerField, findsOneWidget);
    await tester.tap(customerField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('María González'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Crear tarea'));
    await tester.pumpAndSettle();

    expect(tasks.createdLinkedCustomerId, 'customer-1');
    expect(tasks.createdLinkedJobId, isNull);
    expect(tasks.createdLinkedSupplierId, isNull);
    expect(tasks.createdLinkedPurchaseInvoiceId, isNull);
    expect(tasks.createdLinkedSalesInvoiceId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'la sesión del panel preserva alcance y borrador al cerrar y reabrir',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final toolbar = RightToolbarService();
    final tasks = _FakeTaskService(
      [_task(1, acknowledged: DateTime.now())],
      linkableJobs: const [
        TaskLinkableJob(
          id: 'job-active',
          jobNumber: 'PG-00042',
          status: 'EN_CURSO',
          customerName: 'Cliente Activo',
          clientRequest: 'Ajuste general',
        ),
      ],
    );

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
    await _chooseComposerContext(tester, 'Trabajo del taller');
    expect(tasks.fetchLinkableJobsCalls, 1);

    // Cerrar la superficie (tap en la barrera) NO bota el borrador…
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // …y cerrar el panel desmonta el widget (comportamiento real del rail).
    await tester
        .pumpWidget(_host(tasks, toolbar, child: const SizedBox.shrink()));
    await tester.pump(const Duration(milliseconds: 100));

    // Reabrir: alcance restaurado y el borrador esperando en el compositor.
    await tester.pumpWidget(_host(tasks, toolbar));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Nueva tarea'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ajuste de cambios Trek'), findsOneWidget);
    expect(find.text('Crear tarea'), findsOneWidget);
    expect(tasks.fetchLinkableJobsCalls, 2);
    expect(find.text('No hay trabajos activos disponibles para vincular.'),
        findsNothing);
  });

  testWidgets(
      'una Nota neutral oculta responsable y conserva contextos opcionales',
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

    // Como Nota: sin responsable ni flujo del Taller impuesto de antemano.
    expect(find.text('Trabajador responsable'), findsNothing);
    expect(find.text('Vincular a (opcional)'), findsOneWidget);
    expect(find.text('Sin vínculo'), findsOneWidget);
    expect(find.text('1 · Trabajo'), findsNothing);
    expect(find.text('Guardar nota'), findsOneWidget);
    expect(find.text('Título de la nota…'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Abrir trabajo usa push y conserva el retorno', (tester) async {
    final router = GoRouter(
      initialLocation: '/origen',
      routes: [
        GoRoute(
          path: '/origen',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (buttonContext) => TextButton(
                onPressed: () =>
                    openWorkshopJobFromTray(buttonContext, 'job con espacios'),
                child: const Text('Abrir trabajo'),
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

    await tester.tap(find.text('Abrir trabajo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Detalle'), findsOneWidget);
    expect(workspaces.activeWorkspace!.currentRoute,
        '/taller/pegas/job%20con%20espacios');
    // push: el origen sigue en la pila y el retorno existe.
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Abrir trabajo'), findsOneWidget);
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

  testWidgets('un trabajo vinculado sin servicios es visible en fila y detalle',
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

    // La fila muestra la identidad del trabajo aunque no haya servicios.
    expect(find.textContaining('#PG-000777'), findsOneWidget);

    await tester.tap(find.text('N3'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('TRABAJO #PG-000777'), findsOneWidget);
    expect(find.text('Abrir trabajo'), findsOneWidget);
    expect(find.textContaining('Trabajo completo'), findsOneWidget);
  });

  testWidgets(
      'el detalle conserva el nombre y las instrucciones completas del servicio',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const taskId = '00000000-0000-4000-8000-000000000066';
    final tasks = _FakeTaskService(
      [_task(6, acknowledged: DateTime.now(), linkedJobId: 'job-527')],
      jobLinksByTask: {
        taskId: [
          SmartTaskJobItem(
            id: 'link-1',
            taskId: taskId,
            jobItemId: 'service-1',
            jobId: 'job-527',
            jobBikeId: 'bike-1',
            itemName: 'Mecánica Media',
            itemType: 'service',
            jobNumber: 'PG-00527',
            bikeLabel: 'Totem 4423',
            itemInstructions:
                'REVISIÓN DE HORQUILLA/DIRECCIÓN + MANTENCIÓN SI ES NECESARIO AL REINSTALAR',
            linkedAt: DateTime(2026, 8, 27),
            invalidatedAt: null,
            contextChangedAt: null,
          ),
        ],
      },
    );
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Equipo'));
    await tester.pump();
    await tester.tap(find.text('T6'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('TRABAJO #PG-00527'), findsOneWidget);
    expect(find.textContaining('Mecánica Media'), findsOneWidget);
    expect(
      find.text(
          'REVISIÓN DE HORQUILLA/DIRECCIÓN + MANTENCIÓN SI ES NECESARIO AL REINSTALAR'),
      findsOneWidget,
    );
    expect(find.text('Abrir trabajo'), findsOneWidget);
  });

  testWidgets('un cliente vinculado queda visible en fila y detalle',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tasks = _FakeTaskService([
      _task(
        5,
        acknowledged: DateTime.now(),
        linkedCustomerId: 'customer-5',
        linkedCustomerName: 'María González',
      ),
    ]);
    await tester.pumpWidget(_host(tasks, RightToolbarService()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Cliente · María González'), findsOneWidget);
    await tester.tap(find.text('T5'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('CLIENTE'), findsOneWidget);
    expect(find.text('María González'), findsOneWidget);
    expect(find.text('Abrir'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
