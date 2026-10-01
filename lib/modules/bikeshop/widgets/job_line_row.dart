import 'package:flutter/material.dart';

/// Una línea de Productos y Servicios del trabajo (paso G del backbone,
/// 2026-09-27).
///
/// La fila anterior apilaba una insignia «Servicio», un botón «Configurar», el
/// «Lado» en la cabecera, una caja de descripción de tres líneas siempre
/// abierta y cinco controles de orden y borrado: cada línea medía ~200 px y la
/// jerarquía se perdía. Ésta dice lo mismo en menos: qué es (miniatura, nombre
/// y una línea de datos), qué le falta o cómo quedó (chips), cuánto cuesta
/// (cantidad, precio y total alineados) y un solo menú para lo secundario.
/// El contenido lo arma el formulario; esta clase sólo decide la anatomía en
/// escritorio y en teléfono.
class JobLineRow extends StatefulWidget {
  const JobLineRow({
    super.key,
    required this.thumb,
    required this.body,
    required this.quantity,
    required this.price,
    required this.total,
    required this.actions,
    required this.semanticLabel,
    this.mobileLayout = false,
    this.highlighted = false,
    this.onTap,
    this.menuKey,
    this.cardKey,
    this.expandedChild,
  });

  /// Miniatura de 40 px (foto del producto o el ícono del servicio).
  final Widget thumb;

  /// Nombre, datos, descripción y chips; o el buscador si no hay producto.
  final Widget body;
  final Widget quantity;
  final Widget price;
  final Widget total;
  final List<JobLineAction> actions;
  final String semanticLabel;
  final bool mobileLayout;

  /// La línea está abierta o elegida.
  final bool highlighted;
  final VoidCallback? onTap;
  final Key? menuKey;
  final Key? cardKey;

  /// Lo que se abre debajo de la línea (configuración, taller).
  final Widget? expandedChild;

  static const double quantityWidth = 72;
  static const double priceWidth = 112;
  static const double totalWidth = 104;
  static const double menuWidth = 44;

  /// Lo que ocupan las columnas fijas y los márgenes de la fila: el resto es
  /// del nombre. La tabla cae a desplazamiento horizontal bajo
  /// [fixedWidth] + 200.
  static const double fixedWidth = 16 +
      thumbSize +
      14 +
      12 +
      quantityWidth +
      8 +
      priceWidth +
      totalWidth +
      menuWidth +
      8;
  static const double thumbSize = 40;

  /// Lo que tardan la fila y sus campos en encenderse o apagarse al pasar
  /// el mouse.
  static const Duration hoverFade = Duration(milliseconds: 160);

  @override
  State<JobLineRow> createState() => _JobLineRowState();
}

/// Una acción del menú «⋯» de la línea.
class JobLineAction {
  const JobLineAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.key,
    this.danger = false,
    this.startsGroup = false,
  });

  final Key? key;
  final IconData icon;
  final String label;

  /// Null deja la acción visible pero deshabilitada (subir la primera línea).
  final VoidCallback? onSelected;
  final bool danger;

  /// Separa esta acción de las anteriores con una línea.
  final bool startsGroup;
}

enum JobLineChipTone { neutral, info, success, warning }

/// Un dato corto de la línea: la rueda, qué le falta, cómo quedó configurada.
class JobLineChip extends StatelessWidget {
  const JobLineChip({
    super.key,
    required this.label,
    this.icon,
    this.tone = JobLineChipTone.neutral,
    this.onTap,
    this.trailingIcon,
    this.maxLines = 1,
    this.tooltip,
    this.minHeight = 26,
  });

  final String label;
  final IconData? icon;
  final JobLineChipTone tone;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final int maxLines;
  final String? tooltip;

  /// 26 en escritorio; en teléfono el chip crece hacia su área de toque de
  /// 48 para que dos chips apilados no queden separados por aire vacío.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg) = switch (tone) {
      JobLineChipTone.neutral => (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerHighest,
        ),
      JobLineChipTone.info => (scheme.primary, scheme.primaryContainer),
      JobLineChipTone.success => (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
      JobLineChipTone.warning => (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
    };
    final text = Text(
      label,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
    );
    Widget chip = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(child: text),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 16, color: fg),
          ],
        ],
      ),
    );
    if (onTap != null) {
      chip = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: chip,
        ),
      );
    }
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class _JobLineRowState extends State<JobLineRow> {
  final _menuButton = GlobalKey<PopupMenuButtonState<int>>();
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return widget.mobileLayout ? _buildCard(context) : _buildRow(context);
  }

  Widget _menu(BuildContext context, {required double size}) {
    // Sin acciones (una línea protegida) no hay menú, pero la columna queda.
    if (widget.actions.isEmpty) return SizedBox.square(dimension: size);
    final scheme = Theme.of(context).colorScheme;
    // El tooltip de PopupMenuButton no llega al lector de pantalla como nombre:
    // el menú se anunciaba como «botón» a secas. Mismo patrón que
    // VbShellIconButton, con la acción de abrir el menú.
    return Semantics(
      container: true,
      button: true,
      label: 'Acciones de ${widget.semanticLabel}',
      onTap: () => _menuButton.currentState?.showButtonMenu(),
      excludeSemantics: true,
      child: KeyedSubtree(
        key: widget.menuKey,
        child: PopupMenuButton<int>(
          key: _menuButton,
          tooltip: 'Acciones de la línea',
          icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
          style: IconButton.styleFrom(minimumSize: Size(size, size)),
          onSelected: (index) => widget.actions[index].onSelected?.call(),
          itemBuilder: (context) => [
            for (var i = 0; i < widget.actions.length; i++) ...[
              if (widget.actions[i].startsGroup) const PopupMenuDivider(),
              PopupMenuItem<int>(
                key: widget.actions[i].key,
                value: i,
                enabled: widget.actions[i].onSelected != null,
                height: widget.mobileLayout ? 48 : 40,
                child: Row(
                  children: [
                    Icon(
                      widget.actions[i].icon,
                      size: 18,
                      color: widget.actions[i].danger
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    // Con texto grande la opción se parte en dos líneas.
                    Flexible(
                      child: Text(
                        widget.actions[i].label,
                        style: widget.actions[i].danger
                            ? TextStyle(color: scheme.error)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Elegir la línea se hace con el mouse, el dedo o el teclado (Tab y
  /// Enter): era un GestureDetector sin foco (revisión de Codex, 2026-09-27).
  /// El hover lo pinta la fila; aquí sólo queda el foco.
  Widget _tapTarget(Widget child) {
    if (widget.onTap == null) return child;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        hoverColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: child,
      ),
    );
  }

  Widget _buildRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Fila y campos se encienden y se apagan juntos (mismo tiempo y curva) y
    // cada color se desvanece hacia sí mismo transparente: hacia
    // `Colors.transparent`, que es negro, la mitad del camino era gris y el
    // barrido dejaba cajas grises en las filas que el mouse iba soltando
    // (dueño, 2026-10-01).
    final hoverFill = scheme.surfaceContainerLow;
    final background = widget.highlighted
        ? scheme.primaryContainer.withValues(alpha: 0.22)
        : (_hovered ? hoverFill : hoverFill.withValues(alpha: 0));
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: JobLineRow.thumbSize, child: widget.thumb),
          const SizedBox(width: 14),
          Expanded(child: widget.body),
          const SizedBox(width: 12),
          SizedBox(
            width: JobLineRow.quantityWidth,
            child: _FieldShell(boxed: _hovered, child: widget.quantity),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: JobLineRow.priceWidth,
            child: _FieldShell(boxed: _hovered, child: widget.price),
          ),
          SizedBox(
            width: JobLineRow.totalWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.topRight,
                child: widget.total,
              ),
            ),
          ),
          SizedBox(
            width: JobLineRow.menuWidth,
            child: Align(
              alignment: Alignment.topRight,
              child: _menu(context, size: 36),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: JobLineRow.hoverFade,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: background,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tapTarget(row),
              // Alineado con el nombre de la línea, no con la miniatura.
              if (widget.expandedChild != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    16 + JobLineRow.thumbSize + 14,
                    0,
                    16,
                    16,
                  ),
                  child: widget.expandedChild,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: Container(
        key: widget.cardKey,
        decoration: BoxDecoration(
          color: widget.highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.18)
              : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tapTarget(
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox.square(
                      dimension: JobLineRow.thumbSize,
                      child: widget.thumb,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: widget.body),
                    _menu(context, size: 48),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 2, child: widget.quantity),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: widget.price),
                  const SizedBox(width: 12),
                  widget.total,
                ],
              ),
            ),
            if (widget.expandedChild != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: widget.expandedChild,
              ),
          ],
        ),
      ),
    );
  }
}

/// Cantidad y precio se leen como números; el recuadro aparece al pasar el
/// mouse o al escribir, para que la fila no parezca un formulario.
class _FieldShell extends StatefulWidget {
  const _FieldShell({required this.boxed, required this.child});

  final bool boxed;
  final Widget child;

  @override
  State<_FieldShell> createState() => _FieldShellState();
}

class _FieldShellState extends State<_FieldShell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = widget.boxed || _focused;
    // Apagado es el mismo color con alfa 0, nunca `Colors.transparent`: así
    // el recuadro aparece y se va sin pasar por gris.
    final fill = scheme.surface;
    final edge = _focused ? scheme.primary : scheme.outlineVariant;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedContainer(
        duration: JobLineRow.hoverFade,
        curve: Curves.easeOutCubic,
        height: 40,
        decoration: BoxDecoration(
          color: visible ? fill : fill.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: visible ? edge : edge.withValues(alpha: 0),
          ),
        ),
        alignment: Alignment.centerRight,
        child: widget.child,
      ),
    );
  }
}

/// El encabezado de un grupo de líneas del mismo sistema (paso G1,
/// 2026-09-27): «Rueda trasera · 2» con su subtotal en la columna del total.
/// En escritorio es una franja de la tabla alineada con los nombres; en
/// teléfono, un rótulo sobre las tarjetas del grupo.
class JobLineGroupHeader extends StatelessWidget {
  const JobLineGroupHeader({
    super.key,
    required this.label,
    required this.lineCount,
    required this.subtotal,
    this.mobileLayout = false,
  });

  final String label;
  final int lineCount;

  /// Ya formateado, como el total de cada línea.
  final String subtotal;
  final bool mobileLayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          TextSpan(
            text: '  ·  $lineCount',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final amount = Text(
      subtotal,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final content = mobileLayout
        ? Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                amount,
              ],
            ),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  const SizedBox(width: JobLineRow.thumbSize + 14),
                  Expanded(child: title),
                  SizedBox(
                    width: JobLineRow.totalWidth,
                    child:
                        Align(alignment: Alignment.centerRight, child: amount),
                  ),
                  const SizedBox(width: JobLineRow.menuWidth),
                ],
              ),
            ),
          );
    return Semantics(
      header: true,
      container: true,
      excludeSemantics: true,
      label: '$label, $lineCount ${lineCount == 1 ? 'línea' : 'líneas'}, '
          'subtotal $subtotal',
      child: content,
    );
  }
}
