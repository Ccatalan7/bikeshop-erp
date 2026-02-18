import 'package:flutter/material.dart';
import 'ai_chat_bubble.dart';

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
        showDialog(
          context: context,
          builder: (context) => const AIChatDialog(
              jobs: []), // Passing empty jobs for now, will refactor later
        );
      },
    );
  }
}
