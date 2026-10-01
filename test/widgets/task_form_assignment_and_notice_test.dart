// C1 por la app (2026-09-30): dos defectos que mostró el recorrido real del
// TaskFormDialog contra el stack local (scripts/e2e/run_task_form_local.sh).
//
// 1. Un mecánico veía sólo «Sin asignar»: el campo leía `get_tenant_users`,
//    que es de administración. Ahora lee el directorio de asignación de la
//    bandeja y, como la tarea rápida, manda al trabajador como trabajador.
// 2. «No se pudo subir un archivo» era un SnackBar detrás de la barrera del
//    diálogo (atenuado, fuera de la semántica) con la excepción cruda. Ahora
//    es un aviso dentro del diálogo, anunciado y con el botón que corresponde.
// 3. En el teléfono (C1 nativo, Android) «Guardar» y «Cancelar» iban al final
//    del desplazamiento, bajo los adjuntos: con el teclado arriba no se veían.
//    Ahora quedan fijos y sólo los campos se desplazan.
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/bikeshop/widgets/task_form_dialog.dart';
import 'package:vinabike_erp/modules/tasks/models/task_assignment_principal.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '93000000-0000-4000-8000-000000000011';
const _taskId = '93000000-0000-4000-8000-000000000012';
const _userId = '93000000-0000-4000-8000-000000000013';
const _coworkerUserId = '93000000-0000-4000-8000-000000000014';
const _coworkerEmployeeId = '93000000-0000-4000-8000-000000000015';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': '${part({'alg': 'none', 'typ': 'JWT'})}.'
          '${part({
            'exp': 4102444800,
            'sub': _userId,
            'role': 'authenticated'
          })}'
          '.signature',
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'user': {
        'id': _userId,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-09-30T00:00:00.000Z',
      },
    }));
  });

  Future<_DirectoryTaskService> openForm(
    WidgetTester tester, {
    bool phoneWithKeyboard = false,
  }) async {
    if (phoneWithKeyboard) {
      // Medium_Phone_API_36.1 con el teclado del sistema (≈320 dp).
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.viewInsets = const FakeViewPadding(bottom: 840);
      addTearDown(tester.view.reset);
    } else {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    final tenantService = _FixedTenantService();
    final taskService = _DirectoryTaskService(tenantService);
    addTearDown(taskService.dispose);
    addTearDown(tenantService.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantService>.value(value: tenantService),
          ChangeNotifierProvider<TaskService>.value(value: taskService),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const TaskFormDialog(),
                ),
                child: const Text('Abrir formulario'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir formulario'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'Cambiar pastillas traseras');
    return taskService;
  }

  Future<void> tapSave(WidgetTester tester) async {
    final save = find.text('Guardar');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  testWidgets('a mechanic assigns a coworker from the task directory',
      (tester) async {
    final taskService = await openForm(tester);

    final field = find.text('Sin asignar');
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Tomás Rivas'), findsWidgets);
    await tester.tap(find.text('Javiera Soto').last);
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(find.byType(TaskFormDialog), findsNothing);
    expect(taskService.createdAssignedEmployeeId, _coworkerEmployeeId);
    expect(taskService.createdAssignedTo, isNull,
        reason: 'a worker goes only as worker; the server derives the account');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed upload is announced inside the dialog, in words',
      (tester) async {
    FilePicker.platform = _OneFilePicker();
    final taskService = await openForm(tester)
      ..failUploads = true;

    final addFile = find.text('Agregar archivo');
    await tester.ensureVisible(addFile);
    await tester.tap(addFile);
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(find.byType(TaskFormDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    const message = 'La tarea quedó guardada, pero 1 archivo no se subió. '
        'Pulsa Guardar para reintentar.';
    expect(find.text(message), findsOneWidget);
    expect(find.textContaining('StorageException'), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('task-form-notice'))),
      containsSemantics(isLiveRegion: true, label: message),
    );
    expect(taskService.createCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone with the keyboard up, Guardar and Cancelar stay',
      (tester) async {
    await openForm(tester, phoneWithKeyboard: true);
    // El título recién escrito termina de mostrar su cursor antes de
    // desplazar; si no, lo hace después y devuelve la vista arriba.
    await tester.pumpAndSettle();

    for (final label in ['Guardar', 'Cancelar']) {
      expect(find.text(label).hitTestable(), findsOneWidget,
          reason: '«$label» is reachable above the keyboard');
    }
    final addFile = find.text('Agregar archivo');
    await tester.ensureVisible(addFile);
    await tester.pumpAndSettle();
    expect(addFile.hitTestable(), findsOneWidget);
    for (final label in ['Guardar', 'Cancelar']) {
      expect(find.text(label).hitTestable(), findsOneWidget,
          reason: '«$label» stays while the attachments scroll');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('on desktop Cancelar and Guardar stay side by side at the end',
      (tester) async {
    await openForm(tester);

    final cancel = tester.getCenter(find.text('Cancelar'));
    final save = tester.getCenter(find.text('Guardar'));
    expect(cancel.dy, save.dy);
    expect(cancel.dx, lessThan(save.dx));
    expect(tester.takeException(), isNull);
  });
}

class _FixedTenantService extends TenantService {
  _FixedTenantService()
      : super.testing(
            currentUserId: () => _userId, profileLookup: (_) async => []);

  @override
  Future<String?> getTenantId() async => _tenantId;
}

class _DirectoryTaskService extends TaskService {
  _DirectoryTaskService(_FixedTenantService tenantService)
      : super(Supabase.instance.client, tenantService);

  bool failUploads = false;
  int createCalls = 0;
  String? createdAssignedTo;
  String? createdAssignedEmployeeId;

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<void> fetchTasks() async {}

  @override
  Future<List<TaskAssignmentPrincipal>> fetchAssignmentDirectory() async => [
        const TaskAssignmentPrincipal(
          tenantId: _tenantId,
          userId: _coworkerUserId,
          employeeId: _coworkerEmployeeId,
          displayName: 'Javiera Soto',
          role: 'mechanic',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
        const TaskAssignmentPrincipal(
          tenantId: _tenantId,
          userId: _userId,
          employeeId: null,
          displayName: 'Tomás Rivas',
          role: 'mechanic',
          photoUrl: null,
          access: TaskPrincipalAccess.erp,
        ),
      ];

  // The real createTask maps the form model; only the RPC is replaced.
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
    Map<String, String>? jobItemNotes,
    String? overlapDecision,
    String? linkedCustomerId,
    String? linkedSupplierId,
    String? linkedPurchaseInvoiceId,
    String? linkedSalesInvoiceId,
    String? idempotencyKey,
  }) async {
    createCalls++;
    createdAssignedTo = assignedTo;
    createdAssignedEmployeeId = assignedEmployeeId;
    return TaskModel(
      id: _taskId,
      tenantId: _tenantId,
      title: title,
      createdBy: _userId,
      assignedTo: assignedTo,
      assignedEmployeeId: assignedEmployeeId,
    );
  }

  @override
  Future<void> addAttachment({
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? attachmentId,
  }) async {
    if (failUploads) {
      throw Exception('StorageException(message: name resolution failed, '
          'statusCode: 503, error: null)');
    }
  }
}

class _OneFilePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
          name: 'pastilla-trasera.png',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
}
