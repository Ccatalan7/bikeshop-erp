import 'package:flutter/material.dart';

// Piezas de las hojas compactas del teléfono: el marco con título y las
// pestañas segmentadas (Mensajes, Tareas y herramientas, Notificaciones).
// Viven aparte de `MainLayout` porque la pantalla de mensajes del teléfono
// también las usa y un control compartido tiene un solo dueño.
class CompactTabBar<T> extends StatelessWidget {
  const CompactTabBar({
    required this.selected,
    required this.values,
    required this.counts,
    required this.labelOf,
    required this.iconOf,
    required this.nameOf,
    required this.keyPrefix,
    required this.onChanged,
  });

  final T selected;
  final List<T> values;
  final Map<T, int> counts;
  final String Function(T) labelOf;
  final IconData Function(T) iconOf;
  final String Function(T) nameOf;
  final String keyPrefix;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: _CompactTab(
                tabKey: ValueKey('$keyPrefix-${nameOf(value)}'),
                label: labelOf(value),
                icon: iconOf(value),
                count: counts[value] ?? 0,
                isSelected: value == selected,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactTab extends StatelessWidget {
  const _CompactTab({
    required this.tabKey,
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final Key tabKey;
  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isSelected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: isSelected,
      label: count > 0 ? '$label, $count sin leer' : label,
      excludeSemantics: true,
      child: InkWell(
        key: tabKey,
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          // 48px reales: en compacto no hay escala 0.8 que los encoja.
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            // Explícito: sin esto el contador se estiraba a lo alto de la
            // pestaña y se leía como una barra, no como un número.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 5),
                SizedBox(
                  height: 16,
                  child: CompactCountBadge(count: count),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CompactCountBadge extends StatelessWidget {
  const CompactCountBadge({
    required this.count,
    this.background,
    this.foreground,
  });

  final int count;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: foreground ?? theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

/// Marco común de las hojas compactas: título arriba y contenido debajo.
class CompactSheetFrame extends StatelessWidget {
  const CompactSheetFrame({
    required this.title,
    required this.child,
    this.showHeader = true,
    this.onClose,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;

  /// La cabecera se ESCONDE, no se desmonta el marco. Devolver un árbol de
  /// otra forma cuando hay chat abierto hacía que Flutter recreara el panel, y
  /// el `initState` nuevo corría antes de que el `dispose` viejo guardara la
  /// sesión: el chat se abría y se cerraba solo en el mismo instante.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `Visibility` y no `if`: quitar el hijo cambia el ÍNDICE de lo que
        // viene después, y Flutter, sin llaves, recrea esos elementos. El
        // panel de abajo se remontaba —y con él, el chat abierto se cerraba
        // solo. `Visibility` conserva la posición en la lista.
        Visibility(
          visible: showHeader,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Cerrar mensajes',
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
