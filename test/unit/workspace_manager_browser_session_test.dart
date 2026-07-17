import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('browser tabs restore their latest URL and active state per ERP user',
      () async {
    final manager = WorkspaceManager(sessionIdentity: 'staff-a');
    await manager.browserSessionReady;

    final browserId = manager.openBrowserWorkspace(
      'https://example.com',
      title: 'Example',
    );
    expect(browserId, isNotNull);

    manager.updateBrowserWorkspaceState(
      browserId!,
      url: 'https://example.com/account/preferences',
      title: 'Preferences',
    );
    await manager.flushBrowserSession();

    final restored = WorkspaceManager(sessionIdentity: 'staff-a');
    await restored.browserSessionReady;

    expect(restored.workspaces, hasLength(2));
    final browser = restored.workspaces.singleWhere(
      (workspace) => workspace.isBrowserWorkspace,
    );
    expect(browser.browserUrl, 'https://example.com/account/preferences');
    expect(browser.title, 'Preferences');
    expect(browser.isHydrated, isTrue);
    expect(restored.activeWorkspace?.id, browser.id);
    expect(
      Uri.parse(browser.shareRoute).queryParameters['url'],
      'https://example.com/account/preferences',
    );

    final otherUser = WorkspaceManager(sessionIdentity: 'staff-b');
    await otherUser.browserSessionReady;
    expect(otherUser.workspaces, hasLength(1));
    expect(otherUser.workspaces.single.currentRoute, '/dashboard');
  });

  test('background restored browser tabs stay dormant until selected',
      () async {
    final manager = WorkspaceManager(sessionIdentity: 'staff-lazy');
    await manager.browserSessionReady;
    manager.openBrowserWorkspace('https://example.org', title: 'Example');
    manager.switchToWorkspace(0);
    await manager.flushBrowserSession();

    final restored = WorkspaceManager(sessionIdentity: 'staff-lazy');
    await restored.browserSessionReady;

    final browserIndex = restored.workspaces.indexWhere(
      (workspace) => workspace.isBrowserWorkspace,
    );
    expect(browserIndex, greaterThanOrEqualTo(0));
    expect(restored.workspaces[browserIndex].isHydrated, isFalse);

    restored.switchToWorkspace(browserIndex);
    expect(restored.workspaces[browserIndex].isHydrated, isTrue);
  });

  test('pinned browser tabs restore first without stealing focus', () async {
    final manager = WorkspaceManager(sessionIdentity: 'staff-pinned');
    await manager.browserSessionReady;
    final browserId = manager.openBrowserWorkspace(
      'https://example.net',
      title: 'Pinned browser',
    );
    expect(browserId, isNotNull);

    final browserIndex = manager.workspaces.indexWhere(
      (workspace) => workspace.id == browserId,
    );
    manager.toggleWorkspacePinned(browserIndex);
    final dashboardIndex = manager.workspaces.indexWhere(
      (workspace) => workspace.currentRoute == '/dashboard',
    );
    manager.switchToWorkspace(dashboardIndex);
    await manager.flushBrowserSession();

    final restored = WorkspaceManager(sessionIdentity: 'staff-pinned');
    await restored.browserSessionReady;

    expect(restored.workspaces.first.isBrowserWorkspace, isTrue);
    expect(restored.workspaces.first.isPinned, isTrue);
    expect(restored.workspaces.first.isHydrated, isFalse);
    expect(restored.activeWorkspace?.currentRoute, '/dashboard');
  });

  test('rapid ERP user changes are applied in request order', () async {
    final manager = WorkspaceManager(sessionIdentity: 'staff-start');
    await manager.browserSessionReady;

    final transitions = <Future<void>>[
      manager.setSessionIdentity('staff-middle'),
      manager.setSessionIdentity('staff-final'),
    ];
    await Future.wait(transitions);

    manager.openBrowserWorkspace('https://final.example', title: 'Final');
    await manager.flushBrowserSession();

    final restoredFinal = WorkspaceManager(sessionIdentity: 'staff-final');
    await restoredFinal.browserSessionReady;
    expect(
      restoredFinal.workspaces.any(
        (workspace) => workspace.browserUrl == 'https://final.example',
      ),
      isTrue,
    );

    final restoredMiddle = WorkspaceManager(sessionIdentity: 'staff-middle');
    await restoredMiddle.browserSessionReady;
    expect(restoredMiddle.workspaces, hasLength(1));
  });

  test('an explicit non-browser route keeps focus during session restore',
      () async {
    final saved = WorkspaceManager(sessionIdentity: 'staff-direct-route');
    await saved.browserSessionReady;
    saved.openBrowserWorkspace('https://example.edu', title: 'Browser');
    await saved.flushBrowserSession();

    final restored = WorkspaceManager(sessionIdentity: 'staff-direct-route');
    final initialWorkspaceId = restored.activeWorkspace!.id;
    restored.updateWorkspaceRouteById(initialWorkspaceId, '/mail');
    await restored.browserSessionReady;

    expect(restored.activeWorkspace?.currentRoute, '/mail');
    final browser = restored.workspaces.singleWhere(
      (workspace) => workspace.isBrowserWorkspace,
    );
    expect(browser.isHydrated, isFalse);
  });
}
