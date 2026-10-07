import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import 'website_editor_host_theme.dart';

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
    this.onCopy,
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

  /// Copies the block to paste on this page or another one.
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    // The operator's chrome wears the ERP's selection pair, never the site's
    // brand (same rule as the selection ring around it).
    final host = WebsiteEditorHostTheme.maybeOf(context);
    final theme = host?.theme ?? Theme.of(context);
    final roles = host?.roles ?? VinabikeThemeRoles.maybeOf(context);
    final fill =
        roles?.selectionContainer ?? theme.colorScheme.primaryContainer;
    final onFill =
        roles?.onSelectionContainer ?? theme.colorScheme.onPrimaryContainer;
    final danger = roles?.danger.accent ?? theme.colorScheme.error;
    return Material(
      color: fill,
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              blockActionBarLabel(blockType),
              style: theme.textTheme.labelMedium?.copyWith(
                color: onFill,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            if (!isFirst)
              _ActionButton(
                icon: Icons.arrow_upward_rounded,
                tooltip: 'Subir',
                color: onFill,
                onPressed: onMoveUp,
              ),
            if (!isLast)
              _ActionButton(
                icon: Icons.arrow_downward_rounded,
                tooltip: 'Bajar',
                color: onFill,
                onPressed: onMoveDown,
              ),
            _ActionButton(
              icon: isVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: isVisible ? 'Ocultar' : 'Mostrar',
              color: onFill,
              onPressed: onToggleVisibility,
            ),
            _ActionButton(
              icon: Icons.copy_all_outlined,
              tooltip: 'Duplicar',
              color: onFill,
              onPressed: onDuplicate,
            ),
            if (onCopy != null)
              _ActionButton(
                icon: Icons.content_copy_rounded,
                tooltip: 'Copiar para otra página',
                color: onFill,
                onPressed: onCopy,
              ),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Eliminar',
              color: danger,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// The block's name in the editor's words, the same the «Secciones» list
/// uses («Portada», «Productos destacados»), never its storage type.
String blockActionBarLabel(String blockType) {
  final normalised = blockType.trim().toLowerCase();
  for (final type in WebsiteBlockType.values) {
    if (type.name.toLowerCase() == normalised) {
      return WebsiteBlockRegistry.definitionFor(type).title;
    }
  }
  return blockType.isEmpty ? 'Bloque' : blockType;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 18,
      color: color,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
      icon: Icon(icon),
    );
  }
}
