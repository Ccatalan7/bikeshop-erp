import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/modules/tasks/services/task_upload_cleanup_journal.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '92000000-0000-4000-8000-000000000001';
const _taskId = '92000000-0000-4000-8000-000000000002';
const _attachmentId = '92000000-0000-4000-8000-000000000003';
const _userId = '92000000-0000-4000-8000-000000000004';
const _path = '$_tenantId/$_taskId/$_attachmentId/proof.txt';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a retry reuses identical private bytes but rejects a changed file',
      () async {
    final gateway = _AttachmentGateway();
    final journal = TaskUploadCleanupJournal();
    gateway.beforeUpload = () async {
      final pending = await journal.pendingFor(_tenantId, _userId);
      expect(pending.single.attachmentId, _attachmentId,
          reason: 'cleanup identity must survive before Storage sees bytes');
    };
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);
    final bytes = Uint8List.fromList([1, 2, 3]);

    await service.addAttachment(
      taskId: _taskId,
      attachmentId: _attachmentId,
      fileName: 'proof.txt',
      mimeType: 'text/plain',
      bytes: bytes,
    );
    await service.addAttachment(
      taskId: _taskId,
      attachmentId: _attachmentId,
      fileName: 'proof.txt',
      mimeType: 'text/plain',
      bytes: bytes,
    );

    expect(gateway.uploads, 1);
    expect(gateway.downloads, 1);
    expect(gateway.linkCommands, 2);
    expect(gateway.objectBytes, orderedEquals(bytes));
    expect(await journal.pendingFor(_tenantId, _userId), isEmpty,
        reason: 'a confirmed live link must retire its cleanup intent');

    await expectLater(
      service.addAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
        fileName: 'proof.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList([3, 2, 1]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(gateway.uploads, 1);
    expect(gateway.linkCommands, 2,
        reason: 'changed bytes must never acquire an attachment receipt');
    expect((await journal.pendingFor(_tenantId, _userId)).single.attachmentId,
        _attachmentId,
        reason: 'a rejected ambiguous retry must retain the cleanup intent');
  });

  test('an occupied orphan path is linked only when its bytes match', () async {
    final gateway = _AttachmentGateway()
      ..objectBytes = Uint8List.fromList([4, 5, 6]);
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    await expectLater(
      service.addAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
        fileName: 'proof.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList([6, 5, 4]),
      ),
      throwsA(isA<StateError>()),
    );
    expect(gateway.linkCommands, 0);
    await service.abandonPendingAttachmentUploads(
      taskId: _taskId,
      attachmentIds: [_attachmentId],
    );
    final abandoned =
        await TaskUploadCleanupJournal().pendingFor(_tenantId, _userId);
    expect(abandoned.single.attachmentId, _attachmentId);
    expect(abandoned.single.abandonedAt, isNotNull,
        reason: 'explicit close must persist an attempted orphan identity');

    await service.addAttachment(
      taskId: _taskId,
      attachmentId: _attachmentId,
      fileName: 'proof.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList([4, 5, 6]),
    );
    expect(gateway.linkCommands, 1);
    expect(gateway.objectBytes, orderedEquals([4, 5, 6]));
    expect(await TaskUploadCleanupJournal().pendingFor(_tenantId, _userId),
        isEmpty);
  });

  test('a scope switch during Storage does not link the old task', () async {
    final gateway = _AttachmentGateway();
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);
    gateway.beforeUpload = () async {
      service.bindAuthorityScope(
        userId: _userId,
        tenantId: '93000000-0000-4000-8000-000000000001',
      );
    };

    await expectLater(
      service.addAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
        fileName: 'proof.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      throwsA(isA<AuthorityScopeChangedException>()),
    );
    expect(gateway.uploads, 1);
    expect(gateway.linkCommands, 0,
        reason: 'the prior tenant cannot be linked after losing its lease');
    expect(
        (await TaskUploadCleanupJournal().pendingFor(_tenantId, _userId))
            .single
            .attachmentId,
        _attachmentId,
        reason: 'the private object must remain recoverable by its ID');
  });

  test('a rejected link retains private bytes for a concurrent producer',
      () async {
    final gateway = _AttachmentGateway()..rejectLink = true;
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    await expectLater(
      service.addAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
        fileName: 'proof.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList([4, 5, 6]),
      ),
      throwsA(isA<PostgrestException>()),
    );
    expect(gateway.linkCommands, 1);
    expect(gateway.objectBytes, orderedEquals([4, 5, 6]));
    expect(gateway.deleteRequests, 0);
    expect(
        (await TaskUploadCleanupJournal().pendingFor(_tenantId, _userId))
            .single
            .attachmentId,
        _attachmentId);
  });

  test('resume clears only intents with an authorized link or tombstone',
      () async {
    final gateway = _AttachmentGateway();
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);
    final journal = TaskUploadCleanupJournal();
    final intent = TaskUploadCleanupIntent(
      tenantId: _tenantId,
      userId: _userId,
      taskId: _taskId,
      attachmentId: _attachmentId,
      ownerSession: '92000000-0000-4000-8000-000000000005',
      createdAt: DateTime.utc(2026, 9, 29),
    );

    await journal.remember(intent);
    await service.reconcileLinkedUploadIntents();
    expect(await journal.pendingFor(_tenantId, _userId), hasLength(1),
        reason: 'an attempt without a visible link must not be discarded');

    await journal.remember(intent.abandon(DateTime.utc(2026, 9, 29, 1)));
    await service.reconcileLinkedUploadIntents();
    expect(await journal.pendingFor(_tenantId, _userId), hasLength(1),
        reason: 'absence does not prove a concurrent upload has stopped');

    gateway.seedLinkedObject();
    gateway.link!['uploaded_by'] = '92000000-0000-4000-8000-000000000099';
    await service.reconcileLinkedUploadIntents();
    expect(await journal.pendingFor(_tenantId, _userId), hasLength(1),
        reason: 'a link uploaded by another actor cannot clear this intent');
    gateway.link!['uploaded_by'] = _userId;
    gateway.tombstoned = true;
    await service.reconcileLinkedUploadIntents();
    expect(await journal.pendingFor(_tenantId, _userId), isEmpty,
        reason: 'a removed link belongs to the server cleanup queue');
    await journal.remember(intent);
    gateway.tombstoned = false;
    await service.reconcileLinkedUploadIntents();
    expect(await journal.pendingFor(_tenantId, _userId), isEmpty,
        reason: 'a confirmed link also resolves an unmarked lost response');
    expect(gateway.recoveryStatusQueries, 5);
    expect(gateway.deleteRequests, 0,
        reason: 'link reconciliation is read-only for Storage');
  });

  test('removal acknowledges cleanup only after private bytes are gone',
      () async {
    final gateway = _AttachmentGateway()..seedLinkedObject();
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    expect(
      await service.removeAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
      ),
      isTrue,
    );
    expect(gateway.tombstoned, isTrue);
    expect(gateway.objectBytes, isNull);
    expect(gateway.deleteRequests, 1);
    expect(gateway.ackCommands, 1);
  });

  test('a failed Storage deletion leaves the link hidden and cleanup pending',
      () async {
    final gateway = _AttachmentGateway()
      ..seedLinkedObject()
      ..failDelete = true;
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    expect(
      await service.removeAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
      ),
      isFalse,
    );
    expect(gateway.tombstoned, isTrue);
    expect(gateway.objectBytes, orderedEquals([7, 8, 9]));
    expect(gateway.deleteRequests, 1);
    expect(gateway.ackCommands, 0,
        reason: 'bytes still present must never be acknowledged as deleted');
  });

  test('a scope switch after tombstone leaves private cleanup to its queue',
      () async {
    final gateway = _AttachmentGateway()..seedLinkedObject();
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);
    gateway.afterRemove = () async {
      service.bindAuthorityScope(
        userId: _userId,
        tenantId: '93000000-0000-4000-8000-000000000001',
      );
    };

    expect(
      await service.removeAttachment(
        taskId: _taskId,
        attachmentId: _attachmentId,
      ),
      isFalse,
    );
    expect(gateway.tombstoned, isTrue);
    expect(gateway.objectBytes, orderedEquals([7, 8, 9]));
    expect(gateway.deleteRequests, 0);
    expect(gateway.ackCommands, 0);
  });

  test('pending cleanup drains a second page after 25 acknowledged files',
      () async {
    final gateway = _CleanupGateway();
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    await service.resumePendingAttachmentCleanup();

    expect(gateway.pendingQueries, 2);
    expect(gateway.deletedIds.length, 26);
    expect(gateway.ackedIds.length, 26);
  });

  test('a failed cleanup page stops and a later retry resumes it', () async {
    final gateway = _CleanupGateway()..failFirstDelete = true;
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    await service.resumePendingAttachmentCleanup();
    expect(gateway.pendingQueries, 1,
        reason: 'the same failed row must not be fetched in a tight loop');
    expect(gateway.ackedIds.length, 24);

    gateway.failFirstDelete = false;
    await service.resumePendingAttachmentCleanup();
    expect(gateway.pendingQueries, 2);
    expect(gateway.ackedIds.length, 26);
  });

  test('a foreign cleanup row does not block local rows in the same page',
      () async {
    final gateway = _CleanupGateway();
    final local = gateway.rows.first;
    const foreignId = '93000000-0000-4000-8000-000000000003';
    gateway.rows
      ..clear()
      ..add({
        'id': foreignId,
        'task_id': '93000000-0000-4000-8000-000000000002',
        'storage_path': '93000000-0000-4000-8000-000000000001/'
            '93000000-0000-4000-8000-000000000002/$foreignId/proof.txt',
      })
      ..add(local);
    final client = await gateway.client();
    final service = _IsolatedTaskService(client, _tenantService());
    addTearDown(service.dispose);
    addTearDown(client.dispose);

    await service.resumePendingAttachmentCleanup();

    expect(gateway.pendingQueries, 1,
        reason: 'a foreign oldest row must not cause a tight paging loop');
    expect(gateway.deletedIds, {local['id']});
    expect(gateway.ackedIds, {local['id']});
    expect(gateway.deletedIds, isNot(contains(foreignId)));
  });
}

TenantService _tenantService() => TenantService.testing(
      currentUserId: () => _userId,
      profileLookup: (_) async => [
        {
          'tenant_id': _tenantId,
          'role': 'admin',
          'permissions': <String, dynamic>{}
        }
      ],
    );

class _IsolatedTaskService extends TaskService {
  _IsolatedTaskService(super.client, super.tenantService);

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<void> fetchTasks() async {}
}

class _AttachmentGateway {
  Future<void> Function()? beforeUpload;
  Future<void> Function()? afterRemove;
  Uint8List? objectBytes;
  Map<String, dynamic>? link;
  int uploads = 0;
  int downloads = 0;
  int linkCommands = 0;
  int deleteRequests = 0;
  int ackCommands = 0;
  int recoveryStatusQueries = 0;
  bool tombstoned = false;
  bool failDelete = false;
  bool rejectLink = false;

  void seedLinkedObject() {
    objectBytes = Uint8List.fromList([7, 8, 9]);
    link = {
      'id': _attachmentId,
      'tenant_id': _tenantId,
      'task_id': _taskId,
      'uploaded_by': _userId,
      'storage_path': _path,
      'file_name': 'proof.txt',
      'mime_type': 'text/plain',
      'size_bytes': 3,
    };
  }

  Future<SupabaseClient> client() async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_handle),
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
    await client.auth.recoverSession(jsonEncode({
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
    return client;
  }

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/rest/v1/rpc/smart_task_attachment_recovery_status_v1') {
      recoveryStatusQueries++;
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      if (params['p_tenant_id'] != _tenantId ||
          params['p_task_id'] != _taskId ||
          params['p_attachment_id'] != _attachmentId) {
        throw StateError('Recovery queried outside the upload intent scope');
      }
      if (link?['uploaded_by'] != null && link!['uploaded_by'] != _userId) {
        return _json(
            '{"code":"42501","message":"identity mismatch"}', request, 403);
      }
      return _json(
        jsonEncode(link == null
            ? 'absent'
            : tombstoned
                ? 'removed'
                : 'active'),
        request,
      );
    }
    if (path == '/rest/v1/smart_task_attachments') {
      return _json(link == null ? 'null' : jsonEncode(link), request);
    }
    if (path == '/rest/v1/rpc/smart_task_attachment_add_v1') {
      linkCommands++;
      if (rejectLink) {
        return _json(
            '{"code":"23514","message":"link rejected"}', request, 400);
      }
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      link = {
        'id': params['p_attachment_id'],
        'tenant_id': _tenantId,
        'task_id': params['p_task_id'],
        'uploaded_by': _userId,
        'storage_path': params['p_storage_path'],
        'file_name': params['p_file_name'],
        'mime_type': params['p_mime_type'],
        'size_bytes': params['p_size_bytes'],
      };
      return _json(jsonEncode(link), request);
    }
    if (path == '/rest/v1/rpc/smart_task_attachment_remove_v1') {
      tombstoned = true;
      if (afterRemove != null) await afterRemove!();
      return _json(
          jsonEncode({
            'id': _attachmentId,
            'task_id': _taskId,
            'storage_bucket': 'task-attachments',
            'storage_path': _path,
          }),
          request);
    }
    if (path == '/rest/v1/rpc/smart_task_attachment_ack_cleanup_v1') {
      ackCommands++;
      if (objectBytes != null) {
        return _json('{"message":"bytes still exist"}', request, 409);
      }
      return _json(
          jsonEncode({
            'id': _attachmentId,
            'task_id': _taskId,
            'storage_deleted_at': '2026-09-29T23:00:00Z',
          }),
          request);
    }
    if (path == '/storage/v1/object/task-attachments' &&
        request.method == 'DELETE') {
      deleteRequests++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['prefixes'] is! List ||
          !(body['prefixes'] as List).contains(_path)) {
        throw StateError('Private deletion must name the exact object');
      }
      if (failDelete) {
        return _json('{"error":"Unavailable"}', request, 503);
      }
      objectBytes = null;
      return _json('[]', request);
    }
    if (path == '/storage/v1/object/task-attachments/$_path') {
      if (request.method == 'POST') {
        await beforeUpload?.call();
        uploads++;
        if (request.headers['x-upsert'] != 'false') {
          throw StateError('A retry must never overwrite private bytes');
        }
        if (objectBytes != null) {
          return _json(
              '{"error":"Duplicate","message":"exists"}', request, 409);
        }
        objectBytes = _multipartFileBytes(request);
        return _json(jsonEncode({'Key': 'task-attachments/$_path'}), request);
      }
      if (request.method == 'GET') {
        downloads++;
        final bytes = objectBytes;
        if (bytes == null) {
          return _json('{"error":"Not found"}', request, 404);
        }
        return http.Response.bytes(bytes, 200, request: request);
      }
    }
    throw StateError('Unexpected HTTP ${request.method} $path');
  }
}

class _CleanupGateway extends _AttachmentGateway {
  _CleanupGateway() {
    for (var i = 0; i < 26; i++) {
      final id = '92000000-0000-4000-8000-'
          '${(i + 100).toString().padLeft(12, '0')}';
      rows.add({
        'id': id,
        'task_id': _taskId,
        'storage_path': '$_tenantId/$_taskId/$id/proof.txt',
      });
    }
  }

  final rows = <Map<String, String>>[];
  final deletedIds = <String>{};
  final ackedIds = <String>{};
  int pendingQueries = 0;
  bool failFirstDelete = false;

  @override
  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path;
    if (path == '/rest/v1/rpc/smart_task_attachment_pending_cleanup_v2') {
      pendingQueries++;
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      if (params['p_limit'] != 25 || params['p_tenant_id'] != _tenantId) {
        throw StateError('Unexpected private cleanup scope or page size');
      }
      return _json(
        jsonEncode(rows
            .where((row) => !ackedIds.contains(row['id']))
            .take(25)
            .toList()),
        request,
      );
    }
    if (path == '/storage/v1/object/task-attachments' &&
        request.method == 'DELETE') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final prefixes = body['prefixes'] as List<dynamic>;
      if (prefixes.length != 1) throw StateError('Expected one private file');
      final storagePath = prefixes.single.toString();
      final row =
          rows.singleWhere((item) => item['storage_path'] == storagePath);
      final id = row['id']!;
      if (failFirstDelete && id == rows.first['id']) {
        return _json('{"error":"Unavailable"}', request, 503);
      }
      deletedIds.add(id);
      return _json('[]', request);
    }
    if (path == '/rest/v1/rpc/smart_task_attachment_ack_cleanup_v1') {
      final params = jsonDecode(request.body) as Map<String, dynamic>;
      final id = params['p_attachment_id']?.toString();
      if (id == null || !deletedIds.contains(id)) {
        return _json('{"error":"bytes still exist"}', request, 409);
      }
      ackedIds.add(id);
      return _json(
        jsonEncode({
          'id': id,
          'task_id': _taskId,
          'storage_deleted_at': '2026-09-29T23:00:00Z',
        }),
        request,
      );
    }
    throw StateError('Unexpected cleanup HTTP ${request.method} $path');
  }
}

http.Response _json(String body, http.Request request, [int status = 200]) =>
    http.Response(
      body,
      status,
      headers: const {'content-type': 'application/json'},
      request: request,
    );

Uint8List _multipartFileBytes(http.Request request) {
  final contentType = request.headers['content-type'] ?? '';
  final boundary =
      RegExp(r'boundary=([^;]+)').firstMatch(contentType)?.group(1);
  if (boundary == null) throw StateError('Expected multipart upload');
  final body = latin1.decode(request.bodyBytes);
  final fileHeader = body.indexOf('filename=""');
  final start = body.indexOf('\r\n\r\n', fileHeader) + 4;
  final end = body.indexOf('\r\n--$boundary', start);
  if (fileHeader < 0 || start < 4 || end < start) {
    throw StateError('Expected one multipart file');
  }
  return Uint8List.fromList(latin1.encode(body.substring(start, end)));
}
