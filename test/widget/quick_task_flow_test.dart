import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/global_search/quick_task_flow.dart';

/// `/tarea` de punta a punta: a quién, sobre qué trabajo, qué hay que hacer,
/// revisar y crear — con teclado y con clics.
const _me = 'u-me';

class _FakeTaskService extends ChangeNotifier implements TaskService {
  final List<Map<String, Object?>> created = [];

  @override
  String? get currentUserId => _me;

  @override
  Future<List<TaskAssignmentPrincipal>> fetchAssignmentDirectory() async => [
        const TaskAssignmentPrincipal(
          tenantId: 't',
          userId: _me,
          employeeId: 'e1',
          displayName: 'Claudio Catalán',
          role: 'admin',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        const TaskAssignmentPrincipal(
          tenantId: 't',
          userId: 'u2',
          employeeId: 'e2',
          displayName: 'Vicente Díaz',
          role: 'mechanic',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        const TaskAssignmentPrincipal(
          tenantId: 't',
          userId: null,
          employeeId: 'e3',
          displayName: 'Braulio Muñoz',
          role: 'worker',
          photoUrl: null,
          access: TaskPrincipalAccess.none,
        ),
        // La cuenta de la tienda: usuario del ERP sin ficha de trabajador.
        const TaskAssignmentPrincipal(
          tenantId: 't',
          userId: 'u9',
          employeeId: null,
          displayName: 'Cuenta Tienda',
          role: 'admin',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
      ];

  @override
  Future<List<TaskLinkableJob>> fetchLinkableJobs({int limit = 120}) async =>
      const [
        TaskLinkableJob(
          id: 'j1',
          jobNumber: 'PG-00575',
          status: 'ESPERANDO_APROBACION',
          customerName: 'Juan Pérez',
          clientRequest: 'Cambio de maneta',
          statusLabel: 'Esperando aprobación',
          bikeLabel: 'Trek Marlin 7',
          quotationStatus: 'pending',
        ),
        TaskLinkableJob(
          id: 'j2',
          jobNumber: 'PG-00574',
          status: 'EN_CURSO',
          customerName: 'Ana Soto',
          clientRequest: 'Purga',
          statusLabel: 'En curso',
          bikeLabel: 'Giant Talon',
          hasInvoice: true,
        ),
      ];

  @override
  Future<Map<String, int>> fetchJobServiceCounts(List<String> jobIds) async =>
      const {'j1': 2};

  @override
  Future<List<TaskJobWorkItem>> fetchJobWorkItems(String jobId) async =>
      jobId == 'j1'
          ? const [
              TaskJobWorkItem(
                id: 'i1',
                name: 'Cambio de maneta izquierda',
                itemType: 'service',
                jobBikeId: 'b1',
                bikeLabel: 'Trek Marlin 7',
              ),
              TaskJobWorkItem(
                id: 'i2',
                name: 'Diagnóstico',
                itemType: 'service',
                jobBikeId: 'b1',
                bikeLabel: 'Trek Marlin 7',
              ),
            ]
          : const [];

  @override
  Future<List<TaskContextTarget>> fetchLinkTargets(
          TaskContextKind kind) async =>
      const [];

  @override
  Future<TaskModel> createTrayTask({
    required String title,
    String? description,
    TaskKind kind = TaskKind.task,
    TaskVisibility visibility = TaskVisibility.team,
    TaskPriority priority = TaskPriority.normal,
    DateTime? dueDate,
    String? assignedTo,
    String? assignedEmployeeId,
    String? linkedJobId,
    List<String>? jobItemIds,
    String? overlapDecision,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? idempotencyKey,
  }) async {
    created.add({
      'title': title,
      'description': description,
      'priority': priority,
      'dueDate': dueDate,
      'assignedTo': assignedTo,
      'assignedEmployeeId': assignedEmployeeId,
      'linkedJobId': linkedJobId,
      'jobItemIds': jobItemIds,
      'linkedCustomerId': linkedCustomerId,
    });
    return TaskModel(
      id: 'task-new',
      tenantId: 't',
      title: title,
      createdBy: _me,
      assignedTo: assignedTo,
      assignedEmployeeId: assignedEmployeeId,
      linkedJobId: linkedJobId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<({_FakeTaskService service, List<String> calls})> _pump(
  WidgetTester tester, {
  String initialQuery = '',
}) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final service = _FakeTaskService();
  addTearDown(service.dispose);
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 640,
            height: 760,
            child: Material(
              child: QuickTaskFlow(
                taskService: service,
                initialQuery: initialQuery,
                now: () => DateTime(2026, 9, 24, 10),
                onExit: () => calls.add('exit'),
                onClose: () => calls.add('close'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (service: service, calls: calls);
}

void main() {
  testWidgets('con teclado: Vicente, la Trek, hacer el trabajo, crear',
      (tester) async {
    final harness = await _pump(tester);

    // 1 · ¿Para quién? — quien escribe va primero.
    expect(find.text('Para mí'), findsOneWidget);
    expect(find.text('Braulio Muñoz'), findsOneWidget);
    expect(find.text('Sin cuenta: la verá cuando tenga una'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('quick-task-query')), 'vic');
    await tester.pumpAndSettle();
    expect(find.text('Braulio Muñoz'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 2 · ¿Sobre qué trabajo? — con sus señales.
    expect(find.text('Vicente Díaz'), findsOneWidget); // la miga
    expect(find.text('#PG-00575 · Trek Marlin 7'), findsOneWidget);
    expect(find.text('Juan Pérez · Esperando aprobación'), findsOneWidget);
    expect(find.text('Presupuesto por aprobar'), findsOneWidget);
    expect(find.text('2 servicios'), findsOneWidget);
    expect(find.text('Facturado'), findsOneWidget);
    expect(find.text('Otra cosa'), findsOneWidget);
    await tester.tap(find.text('#PG-00575 · Trek Marlin 7'));
    await tester.pumpAndSettle();

    // 3 · ¿Qué hay que hacer?
    expect(
        find.text('2 servicios, como lista para ir marcando'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // 4 · Revisa y crea: título propuesto y los dos servicios marcados.
    final title = tester
        .widget<TextField>(find.byKey(const ValueKey('quick-task-title')));
    expect(title.controller!.text, 'Hacer el trabajo de la Trek Marlin 7');
    expect(find.text('LISTA PARA IR MARCANDO · 2 DE 2'), findsOneWidget);
    await tester.tap(find.text('Diagnóstico'));
    await tester.pumpAndSettle();
    expect(find.text('LISTA PARA IR MARCANDO · 1 DE 2'), findsOneWidget);
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();
    expect(find.text('Le llega a Vicente en su bandeja de tareas.'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-task-create')));
    await tester.pumpAndSettle();

    final created = harness.service.created.single;
    expect(created['assignedEmployeeId'], 'e2');
    expect(created['assignedTo'], isNull);
    expect(created['linkedJobId'], 'j1');
    expect(created['jobItemIds'], ['i1']);
    expect(created['title'], 'Hacer el trabajo de la Trek Marlin 7');
    expect(created['dueDate'], DateTime(2026, 9, 24));
    expect(find.text('Tarea creada para Vicente Díaz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a alguien sin cuenta y sin trabajo: se escribe y se crea',
      (tester) async {
    final harness = await _pump(tester, initialQuery: 'braulio');

    await tester.tap(find.text('Braulio Muñoz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otra cosa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nada en particular'));
    await tester.pumpAndSettle();

    final create = find.byKey(const ValueKey('quick-task-create'));
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(harness.service.created, isEmpty,
        reason: 'sin título no se crea nada');

    await tester.enterText(
        find.byKey(const ValueKey('quick-task-title')), 'Ordenar el banco');
    await tester.pumpAndSettle();
    expect(find.textContaining('le llega sola el día que tenga una'),
        findsOneWidget);
    await tester.tap(create);
    await tester.pumpAndSettle();

    final created = harness.service.created.single;
    expect(created['assignedEmployeeId'], 'e3');
    expect(created['assignedTo'], isNull);
    expect(created['linkedJobId'], isNull);
    expect(created['title'], 'Ordenar el banco');
    expect(find.text('Tarea creada para Braulio Muñoz'), findsOneWidget);
  });

  testWidgets('a una cuenta sin ficha de trabajador no se le ofrecen trabajos',
      (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.text('Vicente Díaz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#PG-00575 · Trek Marlin 7'));
    await tester.pumpAndSettle();

    // Cambia de persona por la miga: el trabajo elegido se suelta.
    await tester.tap(find.byKey(const ValueKey('quick-task-crumb-person')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta Tienda'));
    await tester.pumpAndSettle();

    expect(find.text('#PG-00575 · Trek Marlin 7'), findsNothing);
    expect(find.text('#PG-00574 · Giant Talon'), findsNothing);
    expect(find.textContaining('Cuenta Tienda no tiene ficha de trabajador'),
        findsOneWidget);
    await tester.tap(find.text('Otra cosa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nada en particular'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('quick-task-title')), 'Pedir boletas');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quick-task-create')));
    await tester.pumpAndSettle();

    final created = harness.service.created.single;
    expect(created['assignedTo'], 'u9');
    expect(created['assignedEmployeeId'], isNull);
    expect(created['linkedJobId'], isNull);
  });

  testWidgets('escribir la tarea y Enter en «¿qué hay que hacer?» la titula',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Vicente Díaz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#PG-00574 · Giant Talon'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('quick-task-query')),
        'Cambiar la cámara trasera');
    await tester.pumpAndSettle();
    expect(find.text('«Cambiar la cámara trasera»'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final title = tester
        .widget<TextField>(find.byKey(const ValueKey('quick-task-title')));
    expect(title.controller!.text, 'Cambiar la cámara trasera');
    expect(
        find.text('Este trabajo todavía no tiene servicios cargados: la tarea '
            'queda anexada al trabajo completo.'),
        findsOneWidget);
  });

  testWidgets('con el título propuesto, el foco queda en él: Esc vuelve',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Vicente Díaz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#PG-00575 · Trek Marlin 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hacer el trabajo'));
    await tester.pumpAndSettle();

    final title = tester
        .widget<TextField>(find.byKey(const ValueKey('quick-task-title')));
    expect(title.focusNode!.hasFocus, isTrue,
        reason: 'si nadie toma el foco, Esc y ⌘↵ no llegan al flujo');
    expect(
        title.controller!.selection.baseOffset, title.controller!.text.length);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Armar el presupuesto'), findsOneWidget);
  });

  testWidgets('atrás: una pregunta por vez, y de la primera a las acciones',
      (tester) async {
    final harness = await _pump(tester);
    await tester.tap(find.text('Vicente Díaz'));
    await tester.pumpAndSettle();
    expect(find.text('#PG-00575 · Trek Marlin 7'), findsOneWidget);

    // Retroceso con el campo vacío vuelve a «¿Para quién?».
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(find.text('Para mí'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.calls, ['exit']);
  });

  testWidgets('una miga vuelve a su pregunta sin perder lo demás',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Vicente Díaz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#PG-00575 · Trek Marlin 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Armar el presupuesto'));
    await tester.pumpAndSettle();
    // En el detalle, un presupuesto parte sin servicios marcados.
    expect(find.text('SERVICIOS (NINGUNO: LA TAREA ES SOBRE EL TRABAJO)'),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quick-task-crumb-person')));
    await tester.pumpAndSettle();
    expect(find.text('Para mí'), findsOneWidget);
    // El trabajo elegido sigue en las migas.
    expect(find.text('#PG-00575 · Trek Marlin 7'), findsOneWidget);
  });
}
