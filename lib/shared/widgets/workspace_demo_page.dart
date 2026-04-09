import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';
import 'workspace_tab_bar.dart';
import 'workspace_container.dart';

/// Demo page to test the workspace tab system
/// This demonstrates the TradingView-style workspace functionality
class WorkspaceDemoPage extends StatelessWidget {
  const WorkspaceDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WorkspaceManager(),
      child: const _WorkspaceDemoContent(),
    );
  }
}

class _WorkspaceDemoContent extends StatelessWidget {
  const _WorkspaceDemoContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workspace Demo'),
        backgroundColor: theme.colorScheme.surface,
      ),
      body: const Column(
        children: [
          // Tab bar at the top (includes dropdown menu)
          WorkspaceTabBar(),
          
          // Workspace container (IndexedStack with all workspaces)
          Expanded(
            child: WorkspaceContainer(),
          ),
        ],
      ),
    );
  }
}


