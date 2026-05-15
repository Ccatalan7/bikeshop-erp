import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';
import '../services/auth_service.dart';
import '../routes/app_router.dart';
import 'app_selection_scope.dart';

/// Container that manages multiple workspace instances using IndexedStack
/// Each workspace has its own GoRouter instance and maintains its state
class WorkspaceContainer extends StatelessWidget {
  const WorkspaceContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();

    return IndexedStack(
      index: workspaceManager.activeStackIndex,
      sizing: StackFit.expand,
      children: workspaceManager.workspaceStackOrder.map((workspace) {
        return _WorkspaceInstance(
          key: ValueKey(workspace.id),
          workspace: workspace,
        );
      }).toList(),
    );
  }
}

/// Individual workspace instance with its own router
class _WorkspaceInstance extends StatefulWidget {
  final Workspace workspace;

  const _WorkspaceInstance({
    required super.key,
    required this.workspace,
  });

  @override
  State<_WorkspaceInstance> createState() => _WorkspaceInstanceState();
}

class _WorkspaceInstanceState extends State<_WorkspaceInstance>
    with AutomaticKeepAliveClientMixin {
  late final GoRouter _router;

  @override
  bool get wantKeepAlive => true; // Keep this workspace alive when not visible

  @override
  void initState() {
    super.initState();

    // Create a dedicated router for this workspace
    final authService = context.read<AuthService>();
    _router = AppRouter.createRouter(
      authService,
      initialLocationOverride: widget.workspace.initialRoute,
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: Theme.of(context), // Inherit theme from parent app
      builder: (context, child) => AppSelectionScope(
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
