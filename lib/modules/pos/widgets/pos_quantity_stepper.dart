import 'package:flutter/material.dart';

class PosQuantityStepper extends StatelessWidget {
  const PosQuantityStepper({
    super.key,
    required this.itemName,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String itemName;
  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 144,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            _StepperButton(
              semanticLabel: 'Disminuir cantidad de $itemName',
              icon: Icons.remove_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              onTap: onDecrement,
            ),
            Expanded(
              child: Semantics(
                label: 'Cantidad $quantity',
                excludeSemantics: true,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _StepperButton(
              semanticLabel: 'Aumentar cantidad de $itemName',
              icon: Icons.add_rounded,
              color: theme.colorScheme.primary,
              onTap: onIncrement,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.semanticLabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String semanticLabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
