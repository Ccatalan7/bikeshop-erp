import 'dart:convert';

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

  test('discarded AliExpress media tab is removed without stealing focus',
      () async {
    const storageKey = 'vinabike_browser_workspace_session_v1::staff-sanitize';
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode({
        'version': 1,
        'activeWasBrowser': true,
        'activeBrowserIndex': 0,
        'tabs': [
          {
            'url':
                'https://ae-pic-a1.aliexpress-media.com/kf/example-image.jpg',
            'title': 'Imagen',
            'isPinned': false,
          },
          {
            'url': 'https://www.aliexpress.com/account',
            'title': 'AliExpress',
            'isPinned': false,
          },
        ],
      }),
    });

    final restored = WorkspaceManager(sessionIdentity: 'staff-sanitize');
    await restored.browserSessionReady;

    expect(restored.activeWorkspace?.currentRoute, '/dashboard');
    expect(
      restored.workspaces.any(
        (workspace) =>
            workspace.browserUrl?.contains('aliexpress-media.com') == true,
      ),
      isFalse,
    );
    final retained = restored.workspaces.singleWhere(
      (workspace) =>
          workspace.browserUrl == 'https://www.aliexpress.com/account',
    );
    expect(retained.isHydrated, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final sanitized = jsonDecode(prefs.getString(storageKey)!) as Map;
    expect(sanitized['activeWasBrowser'], isFalse);
    expect((sanitized['tabs'] as List), hasLength(1));
    expect(
      ((sanitized['tabs'] as List).single as Map)['url'],
      'https://www.aliexpress.com/account',
    );
  });

  test('restore keeps the original active index after sanitizing earlier tabs',
      () async {
    const storageKey = 'vinabike_browser_workspace_session_v1::staff-index-map';
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode({
        'version': 1,
        'activeWasBrowser': true,
        'activeBrowserIndex': 1,
        'tabs': [
          {
            'url': 'https://ae-pic-a1.aliexpress-media.com/kf/stale.jpg',
            'title': 'Stale',
            'isPinned': false,
          },
          {
            'url': 'https://first.example',
            'title': 'First',
            'isPinned': false,
          },
          {
            'url': 'https://second.example',
            'title': 'Second',
            'isPinned': false,
          },
        ],
      }),
    });

    final restored = WorkspaceManager(sessionIdentity: 'staff-index-map');
    await restored.browserSessionReady;

    expect(restored.activeWorkspace?.browserUrl, 'https://first.example');
    expect(restored.activeWorkspace?.isHydrated, isTrue);
  });

  test('restore exclusion is narrow to the AliExpress media CDN', () {
    expect(
      isRestorableBrowserWorkspaceUri(
        Uri.parse('https://ae-pic-a1.aliexpress-media.com/kf/image.jpg'),
      ),
      isFalse,
    );
    expect(
      isRestorableBrowserWorkspaceUri(
        Uri.parse('https://images.example.com/product.jpg'),
      ),
      isTrue,
    );
    expect(
      isRestorableBrowserWorkspaceUri(Uri.parse('file:///tmp/image.jpg')),
      isFalse,
    );
  });
}
