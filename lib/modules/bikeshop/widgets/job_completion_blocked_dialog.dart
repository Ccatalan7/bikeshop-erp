import 'package:flutter/material.dart';

import '../services/job_completion_blocked.dart';

/// One actionable explanation for every workshop surface that can close a job.
Future<void> showJobCompletionBlocked(
  BuildContext context,
  JobCompletionBlockedException error, {
  String? jobLabel,
  String? intro,
  VoidCallback? onReviewLines,
  String reviewActionLabel = 'Revisar líneas',
}) async {
  if (!context.mounted) return;
  final reviewLines = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(
          jobLabel == null ? 'Trabajo sin cerrar' : '$jobLabel sin cerrar'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intro ??
                'El estado y la ficha no cambiaron. Corrige estas '
                    'líneas en el trabajo y vuelve a Finalizar o Entregar:'),
            const SizedBox(height: 16),
            for (var i = 0; i < error.problems.length; i++) ...[
              if (i > 0) const Divider(height: 24),
              Text(error.problems[i]),
            ],
          ],
        ),
      ),
      actions: [
        if (onReviewLines != null)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cerrar'),
          ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(onReviewLines != null),
          child: Text(onReviewLines == null ? 'Entendido' : reviewActionLabel),
        ),
      ],
    ),
  );
  if (reviewLines == true && context.mounted) onReviewLines?.call();
}
