import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/services/workspace_manager.dart';

class GlobalAIFloatingButton extends StatelessWidget {
  const GlobalAIFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      icon: const Icon(Icons.auto_awesome),
      color: theme.colorScheme.primary,
      tooltip: 'Asistente IA Global',
      onPressed: () {
        context.read<WorkspaceManager>().toggleAIPanel();
      },
    );
  }
}
