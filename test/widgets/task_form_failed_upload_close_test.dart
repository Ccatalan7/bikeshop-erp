import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/bikeshop/widgets/task_form_dialog.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/services/user_management_service.dart';

const _tenantId = '93000000-0000-4000-8000-000000000001';
const _taskId = '93000000-0000-4000-8000-000000000002';
const _userId = '93000000-0000-4000-8000-000000000003';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test-anon-key',
    );
    final header = base64Url
        .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
        .replaceAll('=', '');
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'exp': 4102444800,
          'sub': _userId,
          'role': 'authenticated',
        })))
        .replaceAll('=', '');
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': '$header.$payload.signature',
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'user': {
        'id': _userId,
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-09-29T00:00:00.000Z',
      },
    }));
  });

  testWidgets('failed upload cannot silently discard its pending retry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    FilePicker.platform = _OneFilePicker();

    final tenantService = _FixedTenantService();
    final taskService = _FailingAttachmentTaskService(tenantService);
    addTearDown(taskService.dispose);
    addTearDown(tenantService.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TenantService>.value(value: tenantService),
          ChangeNotifierProvider<TaskService>.value(value: taskService),
          Provider<UserManagementService>.value(
            value: _EmptyUserManagementService(tenantService),
          ),
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
        find.byType(TextFormField).first, 'Llamar al cliente');

    final addFile = find.text('Agregar archivo');
    await tester.ensureVisible(addFile);
    await tester.tap(addFile);
    await tester.pumpAndSettle();

    final save = find.text('Guardar');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    await tester.pump();
    expect(find.text('Subiendo archivos...'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TaskFormDialog), findsOneWidget);
    expect(find.text('La tarea ya quedó guardada'), findsNothing);

    taskService.upload.completeError(StateError('Storage unavailable'));
    await tester.pumpAndSettle();
    expect(taskService.createCalls, 1);
    expect(taskService.uploadCalls, 1);

    final cancel = find.text('Cancelar');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('La tarea ya quedó guardada'), findsOneWidget);
    await tester.tap(find.text('Seguir aquí'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormDialog), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('La tarea ya quedó guardada'), findsOneWidget);
    taskService.failAbandon = true;
    await tester.tap(find.text('Cerrar sin adjuntar'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormDialog), findsOneWidget,
        reason: 'the dialog must retain bytes when the intent cannot persist');

    taskService.failAbandon = false;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('La tarea ya quedó guardada'), findsOneWidget);
    await tester.tap(find.text('Cerrar sin adjuntar'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskFormDialog), findsNothing);
    expect(taskService.createCalls, 1);
    expect(taskService.abandonedTaskId, _taskId);
    expect(taskService.abandonedAttachmentIds, hasLength(1));
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

class _EmptyUserManagementService extends UserManagementService {
  _EmptyUserManagementService(super.tenantService);

  @override
  Future<List<Map<String, dynamic>>> getTenantUsers() async => [];
}

class _FailingAttachmentTaskService extends TaskService {
  _FailingAttachmentTaskService(_FixedTenantService tenantService)
      : super(Supabase.instance.client, tenantService);

  final Completer<void> upload = Completer<void>();
  int createCalls = 0;
  int uploadCalls = 0;
  String? abandonedTaskId;
  List<String> abandonedAttachmentIds = [];
  bool failAbandon = false;

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<void> fetchTasks() async {}

  @override
  Future<TaskModel> createTask(TaskModel task, {String? idempotencyKey}) async {
    createCalls++;
    return task.copyWith(id: _taskId);
  }

  @override
  Future<void> addAttachment({
    required String taskId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? attachmentId,
  }) {
    uploadCalls++;
    return upload.future;
  }

  @override
  Future<void> abandonPendingAttachmentUploads({
    required String taskId,
    required Iterable<String> attachmentIds,
  }) async {
    if (failAbandon) throw StateError('Local intent write failed');
    abandonedTaskId = taskId;
    abandonedAttachmentIds = attachmentIds.toList();
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
          name: 'prueba.txt',
          size: 3,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ]);
}
