import 'package:flutter/material.dart';

Future<bool> showEmployeeRetirementDialog(
  BuildContext context, {
  required String workerName,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => EmployeeRetirementDialog(
          workerName: workerName,
        ),
      ) ??
      false;
}

class EmployeeRetirementDialog extends StatelessWidget {
  const EmployeeRetirementDialog({
    super.key,
    required this.workerName,
  });

  final String workerName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Desvincular trabajador'),
      content: Text(
        '¿Desvincular a $workerName? El registro laboral y su historial se '
        'conservarán, mientras que sus accesos ERP y Worker Space quedarán '
        'cerrados.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          child: const Text('Desvincular'),
        ),
      ],
    );
  }
}
