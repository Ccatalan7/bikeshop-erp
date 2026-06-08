import 'package:flutter/material.dart';

/// Canonical floating action bar for a selected website block.
class BlockActionBar extends StatelessWidget {
  const BlockActionBar({
    super.key,
    required this.blockId,
    required this.blockType,
    this.isFirst = false,
    this.isLast = false,
    this.isVisible = true,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicate,
    this.onDelete,
    this.onToggleVisibility,
  });

  final String blockId;
  final String blockType;
  final bool isFirst;
  final bool isLast;
  final bool isVisible;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _blockTypeLabel(blockType),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!isFirst)
            _ActionButton(
              icon: Icons.arrow_upward,
              tooltip: 'Mover arriba',
              onPressed: onMoveUp,
            ),
          if (!isLast)
            _ActionButton(
              icon: Icons.arrow_downward,
              tooltip: 'Mover abajo',
              onPressed: onMoveDown,
            ),
          _ActionButton(
            icon: isVisible ? Icons.visibility : Icons.visibility_off,
            tooltip: isVisible ? 'Ocultar' : 'Mostrar',
            onPressed: onToggleVisibility,
          ),
          _ActionButton(
            icon: Icons.copy,
            tooltip: 'Duplicar',
            onPressed: onDuplicate,
          ),
          _ActionButton(
            icon: Icons.delete,
            tooltip: 'Eliminar',
            onPressed: onDelete,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  String _blockTypeLabel(String type) {
    return switch (type) {
      'hero' => 'HERO',
      'products' => 'PRODUCTOS',
      'about' => 'NOSOTROS',
      'services' => 'SERVICIOS',
      'testimonials' => 'TESTIMONIOS',
      'contact' => 'CONTACTO',
      'cta' => 'CTA',
      'gallery' => 'GALERÍA',
      'banner' => 'BANNER',
      _ => type.toUpperCase(),
    };
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade200 : Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}
