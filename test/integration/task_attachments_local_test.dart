// C1 (PLANS.md, 2026-09-30): el recorrido de un adjunto privado de tarea
// contra Auth, PostgREST y Storage locales reales, con el TaskService de la
// app. Lo lanza scripts/e2e/run_task_attachments_local.sh, que crea antes los
// empleados sintéticos y los talleres; sin ese script la prueba se salta.
//
// Aquí sólo actúan los empleados con su contraseña y la llave anónima: no hay
// llave de servicio ni dobles de Auth/Storage/REST. Lo único local es el
// almacenamiento del dispositivo (preferencias y el diario de subidas).
//
// No sustituye el recorrido en la app ni en el teléfono.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/modules/tasks/services/task_upload_cleanup_journal.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

final Map<String, String> _env = Platform.environment;
final bool _enabled = _env['TASK_E2E_ENABLED'] == '1';

String _required(String name) {
  final value = _env[name];
  if (value == null || value.isEmpty) {
    throw StateError(
        'Falta $name: correr scripts/e2e/run_task_attachments_local.sh');
  }
  return value;
}

/// El diario de subidas vive en el dispositivo; aquí en memoria.
class _DeviceUploadStore implements TaskUploadCleanupStore {
  final Map<String, String> _values = {};

  @override
  Future<Map<String, String>> readAll(String prefix) async => {
        for (final entry in _values.entries)
          if (entry.key.startsWith(prefix)) entry.key: entry.value,
      };

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

Future<({int status, List<int> bytes})> _open(String url) async {
  final http = HttpClient();
  try {
    final request = await http.getUrl(Uri.parse(url));
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (previous, chunk) => previous..addAll(chunk),
    );
    return (status: response.statusCode, bytes: body);
  } finally {
    http.close(force: true);
  }
}

void main() {
  late SupabaseClient client;
  TaskService? tasks;

  setUpAll(() async {
    if (!_enabled) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test responde 400 a toda petición HTTP; este recorrido usa la red
    // local de verdad.
    HttpOverrides.global = null;
    final apiUrl = _required('TASK_E2E_API_URL');
    final host = Uri.parse(apiUrl).host;
    if (host != '127.0.0.1' && host != 'localhost') {
      throw StateError('Sólo contra el stack local');
    }
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: apiUrl,
      anonKey: _required('TASK_E2E_ANON_KEY'),
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      debug: false,
    );
    client = Supabase.instance.client;
  });

  tearDownAll(() async {
    if (!_enabled) return;
    tasks?.dispose();
    await client.removeAllChannels();
    if (client.auth.currentSession != null) await client.auth.signOut();
    await Supabase.instance.dispose();
  });

  test(
    'un empleado sube, abre y retira un adjunto privado; otro taller no lo abre',
    () async {
      final emailA = _required('TASK_E2E_EMAIL_A');
      final emailB = _required('TASK_E2E_EMAIL_B');
      final password = _required('TASK_E2E_PASSWORD');
      final tenantA = _required('TASK_E2E_TENANT_A');
      final runId = _required('TASK_E2E_RUN_ID');
      final evidence = <String>[];

      // Empleado A entra con su contraseña y crea su tarea por la RPC real.
      final sessionA = await client.auth
          .signInWithPassword(email: emailA, password: password);
      expect(sessionA.user, isNotNull);
      tasks = TaskService(
        client,
        TenantService(),
        uploadCleanupJournal:
            TaskUploadCleanupJournal(store: _DeviceUploadStore()),
      );
      final service = tasks!;
      final task = await service.createTrayTask(
        title: 'C1 adjunto privado',
        description: 'Recorrido local sintético',
        idempotencyKey: 'c1-task-$runId',
      );
      final taskId = task.id!;

      // Sube el archivo: Storage privado y vínculo por RPC con recibo.
      final attachmentId = const Uuid().v4();
      final bytes =
          Uint8List.fromList(utf8.encode('Diagnóstico C1 $runId: cadena gastada.'));
      await service.addAttachment(
        taskId: taskId,
        fileName: 'diagnostico C1.txt',
        bytes: bytes,
        mimeType: 'text/plain',
        attachmentId: attachmentId,
      );
      await service.fetchTasks();
      final linked = service.tasks
          .firstWhere((candidate) => candidate.id == taskId)
          .attachments
          .firstWhere((attachment) => attachment['id'] == attachmentId);
      expect(linked['storage_bucket'], 'task-attachments');
      final path = linked['storage_path'] as String;
      expect(path, startsWith('$tenantA/$taskId/$attachmentId/'));
      evidence.add('subida=vinculada ruta=<taller A>/<tarea>/<adjunto>/'
          '${path.split('/').last}');

      // Lo abre por una URL firmada de cinco minutos: mismos bytes.
      final signedUrl = await service.createSignedAttachmentUrl(path);
      final opened = await _open(signedUrl);
      expect(opened.status, 200);
      expect(opened.bytes, bytes);
      evidence.add('apertura=200 bytes_iguales=${bytes.length}');

      // Otro taller: ni URL firmada, ni descarga, ni el vínculo.
      await client.auth.signOut();
      await client.auth.signInWithPassword(email: emailB, password: password);
      await expectLater(
        client.storage.from('task-attachments').createSignedUrl(path, 60),
        throwsA(isA<StorageException>()),
      );
      await expectLater(
        client.storage.from('task-attachments').download(path),
        throwsA(isA<StorageException>()),
      );
      final seenByOtherTenant = await client
          .from('smart_task_attachments')
          .select('id')
          .eq('id', attachmentId);
      expect(seenByOtherTenant, isEmpty);
      evidence.add('otro_taller=sin_url_sin_descarga_sin_vinculo');

      // Empleado A lo retira: baja por RPC, bytes por Storage y acuse.
      await client.auth.signOut();
      await client.auth.signInWithPassword(email: emailA, password: password);
      final completed = await service.removeAttachment(
        taskId: taskId,
        attachmentId: attachmentId,
      );
      expect(completed, isTrue);
      await expectLater(
        client.storage.from('task-attachments').download(path),
        throwsA(isA<StorageException>()),
      );
      final reopened = await _open(signedUrl);
      expect(reopened.status, isNot(200));
      await service.fetchTasks();
      expect(
        service.tasks
            .firstWhere((candidate) => candidate.id == taskId)
            .attachments
            .where((attachment) => attachment['id'] == attachmentId),
        isEmpty,
      );
      evidence.add('retiro=completo url_firmada_previa=${reopened.status}');

      stdout.writeln('C1 evidencia: ${evidence.join(' | ')}');
    },
    skip: _enabled
        ? false
        : 'Sólo con scripts/e2e/run_task_attachments_local.sh (stack local)',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
