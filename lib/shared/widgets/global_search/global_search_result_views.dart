import 'package:flutter/material.dart';

import '../../services/global_search/global_search_entry.dart';
import '../../themes/vinabike_theme_roles.dart';

/// Las piezas que dibujan un resultado, compartidas por las dos formas en que
/// el buscador se presenta: el panel centrado de `⌘K` y la lista bajo el campo
/// del inicio.
///
/// Existen separadas por una razón medida, no por estética: mientras el inicio
/// abría el panel centrado, cada tecla escrita durante la transición de 200 ms
/// se perdía, porque el foco viajaba de un campo a otro. La lista del inicio
/// dejó de ser otra superficie y pasó a ser la **misma fila** bajo el campo que
/// ya tiene el foco, así que no hay traspaso que perder.
///
/// Valores: alto de fila `F-06` 48, radio de fila `S-05` 6, movimiento `F-05`
/// `fast 120` con `cubic-bezier(.22,1,.36,1)`. Ningún hex entra acá.

/// `F-06` · objetivo táctil.
const double kGlobalSearchRowHeight = 48;

/// `S-05` · radio de la opción.
const double kGlobalSearchRowRadius = 6;

/// `F-05` · `fast 120`.
const Duration kGlobalSearchFast = Duration(milliseconds: 120);

/// `F-05` · la única curva del ERP.
const Cubic kGlobalSearchCurve = Cubic(0.22, 1, 0.36, 1);

class GlobalSearchGroupHeader extends StatelessWidget {
  const GlobalSearchGroupHeader({super.key, required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color:
                  roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: roles?.faintForeground ??
                    theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class GlobalSearchResultRow extends StatefulWidget {
  const GlobalSearchResultRow({
    super.key,
    required this.entry,
    required this.height,
    required this.radius,
    required this.transition,
    required this.isHighlighted,
    required this.onTap,
  });

  final GlobalSearchEntry entry;
  final double height;
  final double radius;
  final Duration transition;
  final bool isHighlighted;
  final VoidCallback onTap;

  @override
  State<GlobalSearchResultRow> createState() => GlobalSearchResultRowState();
}

class GlobalSearchResultRowState extends State<GlobalSearchResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final entry = widget.entry;
    final selected = widget.isHighlighted;

    // `S-05`, opción elegida: contenedor de selección + borde teñido de la
    // misma familia. El hover es el mismo contenedor a media presencia, que es
    // lo que distingue «el teclado está acá» de «el mouse pasa por encima».
    final background = selected
        ? roles?.selectionContainer ?? theme.colorScheme.primaryContainer
        : _hovered
            ? (roles?.selectionContainer ?? theme.colorScheme.primaryContainer)
                .withValues(alpha: 0.5)
            : Colors.transparent;

    final subtitle = entry.subtitle;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: widget.transition,
            curve: const Cubic(0.22, 1, 0.36, 1),
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: selected
                    ? roles?.accentBorder ?? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  entry.resolvedIcon,
                  size: 18,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: widget.transition,
                  opacity: selected ? 1 : 0,
                  child: Icon(
                    Icons.keyboard_return_rounded,
                    size: 15,
                    color: roles?.faintForeground ??
                        theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlobalSearchMoreRow extends StatelessWidget {
  const GlobalSearchMoreRow({
    super.key,
    required this.label,
    required this.height,
    required this.radius,
    required this.onTap,
  });

  final String label;
  final double height;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height - 10,
          child: Row(
            children: [
              const SizedBox(width: 36),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlobalSearchKeyCap extends StatelessWidget {
  const GlobalSearchKeyCap({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: roles?.hairline ?? theme.dividerColor),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class GlobalSearchMessage extends StatelessWidget {
  const GlobalSearchMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 26,
            color: roles?.faintForeground ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action!],
        ],
      ),
    );
  }
}
