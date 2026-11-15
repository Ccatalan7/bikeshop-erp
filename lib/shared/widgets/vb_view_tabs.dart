import 'package:flutter/material.dart';

/// Una vista de una lista, con su conteo.
@immutable
class VbViewTab<T> {
  const VbViewTab({required this.value, required this.label, this.count});

  final T value;
  final String label;

  /// Cuántas cosas hay en la vista. Nulo, o cero, no se muestra.
  final int? count;
}

/// Las vistas de una lista en la línea del encabezado: texto con su conteo y
/// la elegida subrayada, sin cápsulas ni fondos.
///
/// Nació en el encabezado de Correo (2026-11-06, «Para hoy 7 · Esperando 4»)
/// y pasó acá cuando Marcas lo necesitó (2026-11-15): un conteo vive junto a su
/// pestaña, no en un bloque de cifras sobre la lista
/// (`.github/GUI_DESIGN_PRINCIPLES.md`, «Una propuesta parte del ERP vivo»).
class VbViewTabs<T> extends StatelessWidget {
  const VbViewTabs({
    super.key,
    required this.tabs,
    required this.value,
    required this.onChanged,
    this.spacing = 22,
  });

  final List<VbViewTab<T>> tabs;
  final T value;
  final ValueChanged<T> onChanged;
  final double spacing;

  @visibleForTesting
  static Key tabKey(Object? value) => Key('vb-view-tab-$value');

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          if (index > 0) SizedBox(width: spacing),
          _VbViewTab<T>(
            tab: tabs[index],
            selected: tabs[index].value == value,
            onTap: () => onChanged(tabs[index].value),
          ),
        ],
      ],
    );
  }
}

class _VbViewTab<T> extends StatelessWidget {
  const _VbViewTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final VbViewTab<T> tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final count = tab.count;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        key: VbViewTabs.tabKey(tab.value),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 15, 2, 13),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? scheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
              if (count != null && count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
