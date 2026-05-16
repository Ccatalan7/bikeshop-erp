import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  test('shared links from pinned workspaces create a return milestone', () {
    final manager = WorkspaceManager();
    final chatWorkspaceId = manager.activeWorkspace!.id;

    manager.updateWorkspaceRouteById(chatWorkspaceId, '/chat');
    manager.toggleWorkspacePinned(0);

    manager.navigateActiveWorkspaceFromSharedLink('/sales/invoices');

    expect(manager.workspaces.length, 2);
    expect(manager.activeWorkspace!.currentRoute, '/sales/invoices');
    expect(manager.activeWorkspace!.canGoBack, isTrue);

    manager.navigateActiveWorkspaceBack();

    expect(manager.activeWorkspace!.currentRoute, '/chat');
  });
}
