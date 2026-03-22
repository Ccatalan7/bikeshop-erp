import 'package:flutter/material.dart';

class SplitNewJobButton extends StatelessWidget {
  final VoidCallback onMainPressed;
  final Function(String) onTypeSelected;

  const SplitNewJobButton({
    super.key,
    required this.onMainPressed,
    required this.onTypeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Use primary color style matching a regular FilledButton
    final backgroundColor = colorScheme.primary;
    final foregroundColor = colorScheme.onPrimary;

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(100),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onMainPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 18, color: foregroundColor),
                  const SizedBox(width: 8),
                  Text(
                    'Nuevo Trabajo',
                    style: TextStyle(
                      color: foregroundColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: foregroundColor.withOpacity(0.3),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tipo de trabajo',
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: onTypeSelected,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'warranty',
                child: Row(children: [
                  Icon(Icons.verified_user_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Verificar Garantía'),
                ]),
              ),
              PopupMenuItem(
                value: 'quotation',
                child: Row(children: [
                  Icon(Icons.request_quote_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Presupuesto'),
                ]),
              ),
              PopupMenuItem(
                value: 'item_service',
                child: Row(children: [
                  Icon(Icons.build_circle_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('Componente / Ítem'),
                ]),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(Icons.arrow_drop_down, color: foregroundColor),
            ),
          ),
        ],
      ),
    );
  }
}
