import 'package:flutter/material.dart';

import '../theme/public_store_surface_theme.dart';

/// Honest, dismissible notice for saved cart lines that could not be restored.
class CartRestoreNotice extends StatelessWidget {
  const CartRestoreNotice({
    super.key,
    required this.dropped,
    required this.onAcknowledged,
  }) : assert(dropped > 0);

  final int dropped;
  final VoidCallback onAcknowledged;

  @override
  Widget build(BuildContext context) {
    final storeTheme = PublicStoreSurfaceTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: storeTheme.warningSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: storeTheme.warning),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: storeTheme.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dropped == 1
                  ? 'Ajustamos 1 producto de tu carrito guardado porque cambió su '
                      'disponibilidad.'
                  : 'Ajustamos $dropped productos de tu carrito guardado porque '
                      'cambió su disponibilidad.',
              style: storeTheme.text.bodyMedium?.copyWith(
                fontSize: 13,
                height: 1.45,
                color: storeTheme.onWarningSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAcknowledged,
            style: TextButton.styleFrom(
              foregroundColor: storeTheme.onWarningSurface,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
