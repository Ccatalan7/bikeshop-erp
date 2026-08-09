import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(WorkspaceManager, String)> managerWithClosableWorkspace(
    String identity,
  ) async {
    final manager = WorkspaceManager(sessionIdentity: identity);
    await manager.browserSessionReady;
    final workspaceId = manager.addWorkspace(
      title: 'Borrador',
      initialRoute: '/profile',
    );
    return (manager, workspaceId);
  }

  test('a workspace without a guard closes normally', () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-no-guard');
    addTearDown(manager.dispose);

    final closed = await manager.requestCloseWorkspaceById(workspaceId);

    expect(closed, isTrue);
    expect(manager.workspaceById(workspaceId), isNull);
    expect(manager.workspaces, hasLength(1));
  });

  test('a denying guard preserves the workspace and its draft', () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-denied');
    addTearDown(manager.dispose);
    final owner = Object();
    var guardCalls = 0;
    expect(
      manager.registerWorkspaceCloseGuard(
        workspaceId: workspaceId,
        owner: owner,
        guard: () async {
          guardCalls += 1;
          return false;
        },
      ),
      isTrue,
    );

    final closed = await manager.requestCloseWorkspaceById(workspaceId);

    expect(closed, isFalse);
    expect(guardCalls, 1);
    expect(manager.workspaceById(workspaceId), isNotNull);
  });

  test('an allowing guard closes and releases its registration', () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-allowed');
    addTearDown(manager.dispose);
    final owner = Object();
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: owner,
      guard: () async => true,
    );

    final closed = await manager.requestCloseWorkspaceById(workspaceId);

    expect(closed, isTrue);
    expect(manager.workspaceById(workspaceId), isNull);
    expect(
      manager.unregisterWorkspaceCloseGuard(
        workspaceId: workspaceId,
        owner: owner,
      ),
      isFalse,
    );
  });

  test('concurrent close requests share one guard decision and one close',
      () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-concurrent');
    addTearDown(manager.dispose);
    final decision = Completer<bool>();
    var guardCalls = 0;
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: Object(),
      guard: () {
        guardCalls += 1;
        return decision.future;
      },
    );

    final first = manager.requestCloseWorkspaceById(workspaceId);
    final second = manager.requestCloseWorkspaceById(workspaceId);

    expect(identical(first, second), isTrue);
    expect(guardCalls, 1);
    decision.complete(true);
    expect(await Future.wait([first, second]), [true, true]);
    expect(manager.workspaceById(workspaceId), isNull);
  });

  test('a guard cannot recursively request the same workspace close', () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-reentrant');
    addTearDown(manager.dispose);
    bool? nestedResult;
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: Object(),
      guard: () async {
        nestedResult = await manager.requestCloseWorkspaceById(workspaceId);
        return true;
      },
    );

    final closed = await manager.requestCloseWorkspaceById(workspaceId);

    expect(nestedResult, isFalse);
    expect(closed, isTrue);
    expect(manager.workspaceById(workspaceId), isNull);
  });

  test('stale disposal cannot remove a replacement guard', () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-owner-replacement');
    addTearDown(manager.dispose);
    final staleOwner = Object();
    final currentOwner = Object();
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: staleOwner,
      guard: () async => true,
    );
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: currentOwner,
      guard: () async => false,
    );

    expect(
      manager.unregisterWorkspaceCloseGuard(
        workspaceId: workspaceId,
        owner: staleOwner,
      ),
      isFalse,
    );
    expect(await manager.requestCloseWorkspaceById(workspaceId), isFalse);
    expect(manager.workspaceById(workspaceId), isNotNull);
  });

  test('a guard replaced during an in-flight decision is re-evaluated',
      () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-in-flight-replacement');
    addTearDown(manager.dispose);
    final firstDecision = Completer<bool>();
    var replacementCalls = 0;
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: Object(),
      guard: () => firstDecision.future,
    );

    final closeRequest = manager.requestCloseWorkspaceById(workspaceId);
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: Object(),
      guard: () async {
        replacementCalls += 1;
        return false;
      },
    );
    firstDecision.complete(true);

    expect(await closeRequest, isFalse);
    expect(replacementCalls, 1);
    expect(manager.workspaceById(workspaceId), isNotNull);
  });

  test('guard exceptions fail closed while forced lifecycle close still works',
      () async {
    final (manager, workspaceId) =
        await managerWithClosableWorkspace('close-error');
    addTearDown(manager.dispose);
    manager.registerWorkspaceCloseGuard(
      workspaceId: workspaceId,
      owner: Object(),
      guard: () async => throw StateError('guard failed'),
    );

    expect(await manager.requestCloseWorkspaceById(workspaceId), isFalse);
    expect(manager.workspaceById(workspaceId), isNotNull);

    manager.closeWorkspaceById(workspaceId);
    expect(manager.workspaceById(workspaceId), isNull);
  });

  test('desktop and compact close controls use the protected request API', () {
    final desktopSource =
        File('lib/shared/widgets/workspace_tab_bar.dart').readAsStringSync();
    final compactSource =
        File('lib/shared/widgets/main_layout.dart').readAsStringSync();

    expect(desktopSource, contains('.requestCloseWorkspaceById('));
    final compactProtectedCalls = RegExp(
      r'\.requestCloseWorkspaceById\s*\(\s*workspace\.id\s*\)',
    ).allMatches(compactSource);
    expect(
      compactProtectedCalls.length,
      greaterThanOrEqualTo(2),
      reason: 'both compact close controls must use the guarded request API',
    );
    expect(
      compactSource,
      isNot(contains('manager.closeWorkspaceById(workspace.id)')),
    );
  });
}
