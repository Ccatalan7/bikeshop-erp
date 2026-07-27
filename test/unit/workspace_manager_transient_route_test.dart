import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('openRequest is excluded from the durable workspace route identity', () {
    final route = workspaceRouteIdentity(
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-a',
    );
    final uri = Uri.parse(route);

    expect(uri.path, '/mail');
    expect(uri.queryParameters['providerId'], 'gmail');
    expect(uri.queryParameters['messageId'], 'message-42');
    expect(uri.queryParameters, isNot(contains('openRequest')));
  });

  test('an openRequest-only route collapses to its canonical path', () {
    expect(
      workspaceRouteIdentity('/settings/users?openRequest=request-a'),
      '/settings/users',
    );
  });

  test('repeated notification requests reuse one workspace identity', () {
    final manager = WorkspaceManager();

    manager.openRouteInWorkspace(
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-a',
    );
    manager.openRouteInWorkspace(
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-b',
    );

    expect(manager.workspaces, hasLength(2));
    final mailWorkspace = manager.activeWorkspace!;
    expect(mailWorkspace.initialRoute, contains('messageId=message-42'));
    expect(mailWorkspace.initialRoute, isNot(contains('openRequest')));
    expect(
      mailWorkspace.routeHistory.every(
        (route) => !route.contains('openRequest'),
      ),
      isTrue,
    );
  });

  test('transient requests do not add synthetic Back destinations', () {
    final manager = WorkspaceManager();
    final workspaceId = manager.activeWorkspace!.id;

    manager.updateWorkspaceRouteById(
      workspaceId,
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-a',
    );
    manager.updateWorkspaceRouteById(
      workspaceId,
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-b',
    );

    expect(
      manager.activeWorkspace!.routeHistory,
      [
        '/dashboard',
        '/mail?providerId=gmail&messageId=message-42',
      ],
    );

    manager.navigateActiveWorkspaceBack();

    expect(manager.activeWorkspace!.currentRoute, '/dashboard');
  });

  test('pinned shared-link reuse keeps return milestones durable', () {
    final manager = WorkspaceManager();
    final chatWorkspaceId = manager.activeWorkspace!.id;
    manager.updateWorkspaceRouteById(chatWorkspaceId, '/chat');
    manager.toggleWorkspacePinned(0);

    manager.navigateActiveWorkspaceFromSharedLink(
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-a',
    );
    manager.switchToWorkspaceById(chatWorkspaceId);
    manager.navigateActiveWorkspaceFromSharedLink(
      '/mail?providerId=gmail&messageId=message-42&openRequest=request-b',
    );

    expect(manager.workspaces, hasLength(2));
    expect(
      manager.activeWorkspace!.routeHistory.every(
        (route) => !route.contains('openRequest'),
      ),
      isTrue,
    );

    manager.navigateActiveWorkspaceBack();

    expect(manager.activeWorkspace!.currentRoute, '/chat');
  });
}
