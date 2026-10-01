import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/modules/tasks/services/task_upload_cleanup_journal.dart';

const _tenantA = '94000000-0000-4000-8000-000000000001';
const _tenantB = '94000000-0000-4000-8000-000000000002';
const _userA = '94000000-0000-4000-8000-000000000003';
const _userB = '94000000-0000-4000-8000-000000000004';
const _taskId = '94000000-0000-4000-8000-000000000005';
const _sessionId = '94000000-0000-4000-8000-000000000006';
const _otherSessionId = '94000000-0000-4000-8000-000000000009';
const _attachmentA = '94000000-0000-4000-8000-000000000007';
const _attachmentB = '94000000-0000-4000-8000-000000000008';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('one intent per file survives a new reader without names or bytes',
      () async {
    final first = TaskUploadCleanupJournal();
    final createdAt = DateTime.utc(2026, 9, 29, 12);
    final fileA = TaskUploadCleanupIntent(
      tenantId: _tenantA,
      userId: _userA,
      taskId: _taskId,
      attachmentId: _attachmentA,
      ownerSession: _sessionId,
      createdAt: createdAt,
    );
    final fileB = TaskUploadCleanupIntent(
      tenantId: _tenantA,
      userId: _userA,
      taskId: _taskId,
      attachmentId: _attachmentB,
      ownerSession: _sessionId,
      createdAt: createdAt.add(const Duration(minutes: 1)),
    );
    await first.remember(fileA);
    await first.remember(fileB);

    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getString(fileA.key)!;
    expect(stored, contains(_attachmentA));
    expect(stored, isNot(contains('prueba.txt')));
    expect(stored, isNot(contains('storage_path')));
    expect(stored, isNot(contains('bytes')));

    final second = TaskUploadCleanupJournal();
    expect((await second.pendingFor(_tenantA, _userA)).length, 2);
    expect(await second.pendingFor(_tenantA, _userB), isEmpty);
    expect(await second.pendingFor(_tenantB, _userA), isEmpty);

    await second
        .remember(fileA.abandon(createdAt.add(const Duration(hours: 1))));
    final abandoned = (await first.pendingFor(_tenantA, _userA)).first;
    expect(abandoned.attachmentId, _attachmentA);
    expect(abandoned.abandonedAt, isNotNull);

    await second.forget(fileA);
    expect(
      (await first.pendingFor(_tenantA, _userA))
          .map((intent) => intent.attachmentId),
      [_attachmentB],
    );
  });

  test('a swapped record is rejected before any cleanup can use it', () async {
    final intent = TaskUploadCleanupIntent(
      tenantId: _tenantA,
      userId: _userA,
      taskId: _taskId,
      attachmentId: _attachmentA,
      ownerSession: _sessionId,
      createdAt: DateTime.utc(2026, 9, 29),
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      '${TaskUploadCleanupIntent.scopePrefix(_tenantA, _userA)}$_attachmentB',
      intent.encode(),
    );
    final journal = TaskUploadCleanupJournal();
    await expectLater(
      journal.pendingFor(_tenantA, _userA),
      throwsA(isA<FormatException>()),
    );
  });

  test('another session cannot replace or remove a pending file intent',
      () async {
    final first = TaskUploadCleanupIntent(
      tenantId: _tenantA,
      userId: _userA,
      taskId: _taskId,
      attachmentId: _attachmentA,
      ownerSession: _sessionId,
      createdAt: DateTime.utc(2026, 9, 29),
    );
    final second = TaskUploadCleanupIntent(
      tenantId: _tenantA,
      userId: _userA,
      taskId: _taskId,
      attachmentId: _attachmentA,
      ownerSession: _otherSessionId,
      createdAt: DateTime.utc(2026, 9, 30),
    );
    final journal = TaskUploadCleanupJournal();
    await journal.remember(first);
    await expectLater(journal.remember(second), throwsStateError);
    await journal.forget(second);
    final pending = await journal.pendingFor(_tenantA, _userA);
    expect(pending, hasLength(1));
    expect(pending.single.ownerSession, _sessionId);
    await journal.forget(first);
    expect(await journal.pendingFor(_tenantA, _userA), isEmpty);
  });
}
