import 'package:flutter/material.dart';

/// Compact presentation for the canonical workshop status-filter mode.
///
/// The caller remains the owner of the selected statuses and include/exclude
/// mode. The exclusion toggle appears only when there is a selection to invert.
class WorkshopStatusFilterHeader extends StatelessWidget {
  const WorkshopStatusFilterHeader({
    super.key,
    required this.excludeMode,
    required this.canClear,
    required this.onExcludeModeChanged,
    required this.onClear,
  });

  static const operatorKey =
      ValueKey<String>('workshop-mobile-status-filter-operator');
  static const clearKey =
      ValueKey<String>('workshop-mobile-status-filter-clear');

  final bool excludeMode;
  final bool canClear;
  final ValueChanged<bool> onExcludeModeChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'ESTADO OPERATIVO',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
            TextButton(
              key: clearKey,
              onPressed: canClear ? onClear : null,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: const Text('Todos'),
            ),
          ],
        ),
        if (canClear)
          SwitchListTile(
            key: operatorKey,
            contentPadding: EdgeInsets.zero,
            title: const Text('Excluir los estados elegidos'),
            subtitle: Text(
              excludeMode
                  ? 'Mostrando todos excepto los seleccionados'
                  : 'Mostrando solamente los seleccionados',
            ),
            value: excludeMode,
            onChanged: onExcludeModeChanged,
            dense: true,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}
