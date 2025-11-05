import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';
import '../services/auth_service.dart';
import '../routes/app_router.dart';
import 'workspace_tab_bar.dart';

/// App-level workspace container - EXACT same pattern as demo
class AppWorkspaceContainer extends StatelessWidget {
  const AppWorkspaceContainer({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    
    // If not authenticated, show login
    if (!authService.isAuthenticated) {
      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: AppRouter.createRouter(authService),
        theme: Theme.of(context),
      );
    }
    
    // Authenticated = workspace system (EXACT same as demo)
    return const _WorkspaceContent();
  }
}

class _WorkspaceContent extends StatelessWidget {
  const _WorkspaceContent();

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    
    return Column(
      children: [
        const WorkspaceTabBar(),
        Expanded(
          child: IndexedStack(
            index: workspaceManager.activeIndex,
            sizing: StackFit.expand,
            children: workspaceManager.workspaces.map((workspace) {
              return _WorkspaceInstance(
                key: ValueKey(workspace.id),
                workspace: workspace,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

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
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
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
    super.build(context);
    
    // EXACT same as demo - MaterialApp.router per workspace
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: Theme.of(context),
    );
  }
}
