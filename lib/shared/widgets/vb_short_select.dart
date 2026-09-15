import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../themes/vinabike_theme_roles.dart';
import '../utils/responsive_breakpoints.dart';
import 'vb_anchored_popover.dart';

/// **S-05 · `VbShortSelect<T>`** — el select corto del kit compartido
/// (`GUÍA GENERAL Viñabike · Componentes`, proyecto `ERP Bikeshop UI Mockups`).
///
/// Es el **dueño canónico** de «elegir uno de pocos valores conocidos». Existe
/// porque `universal-ui-component-system.md` prohíbe la variante local de una
/// feature y la guía cierra la deuda con nombre: *«Los 99 archivos con
/// `DropdownButton`/`DropdownMenu` se reparten entre S-05 y S-06 según la
/// matriz. Ninguno sobrevive con estilo propio.»*
///
/// ### Cuándo NO es este componente
///
/// La guía pone el techo y lo hace verificable: *«Hasta ~7 opciones, conjunto
/// estable y conocido, etiquetas cortas… El menú **no** es scrollable: si
/// necesita scroll, era el otro componente.»* Una lista paginada, que crece con
/// el uso o que trae nombres de persona es **S-06**, y forzarla acá produce un
/// popover recortado. El [assert] de [build] hace visible esa violación en
/// desarrollo en vez de dejarla clipear en silencio.
///
/// ### Geometría — leída de `DesignSync`, no estimada
///
/// Campo cerrado: `height 34 · padding 0 9 0 11 · radius 8 · border 1px
/// borderStrong · gap 8`, valor `400 12`, chevron `400 9`. Abierto y con foco:
/// borde `accent` más un anillo `0 0 0 3px accent @ .12`. Popover: `padding 5 ·
/// radius 10`, opción `height 30 · padding 0 9 · radius 6 · 400 11.5`, y la
/// elegida `surfaceSelected + borde tintado + 600` con su check en `accent`.
/// Vacío usa el gris de apoyo y deshabilitado, `surfaceSunken` con texto
/// deshabilitado.
///
/// **El estado `read-only` de la guía NO está implementado, y es a propósito.**
/// Se dibuja como texto con `border-bottom:1px dashed`, y el ritmo del
/// punteado **no es un valor legible**: en CSS `dashed` lo resuelve el motor,
/// así que no hay número que leer en el archivo. Se registra como *unreadable*
/// en vez de inventar un patrón plausible, y se implementará cuando tenga un
/// consumidor real y un valor que citar.
///
/// **Ningún hex entra a este archivo.** La primera regla de la guía es
/// `PROHIBIDO EL HEX LITERAL EN CUALQUIER WIDGET`, así que cada valor va atado
/// al rol que lo resuelve: `#CDD5DE → scheme.outline`, `#E2E7ED →
/// outlineVariant`, `#F7F8FA → surfaceContainerLow`, `#10243A → onSurface`,
/// `#4A5B6B → onSurfaceVariant` (el mapeo que ya publica `app_theme.dart`),
/// `#F7FBFF → roles.selectionContainer`, `#1668BD → roles.focusRing`,
/// `#B3BCC4 → roles.disabledForeground`. El borde de la opción elegida usa
/// `roles.info.border` porque en este ERP `info.container` **es**
/// `selectionContainer` —los dos resuelven a `scheme.primaryContainer`—, así
/// que ése es el borde publicado de ese mismo contenedor teñido.
///
/// ### Táctil: bottom sheet, no popover — y el umbral es 900
///
/// La guía es explícita —*«la lista es un bottom sheet, no un popover de 200
/// px»*— y **O-05** publica su anatomía: `r14 arriba, handle 34×4, título 14
/// Poppins, filas de 48 con separador… Máx. 60% de alto; con más, es una
/// página.` Además: *«Nunca aparece en desktop pointer: ahí es popover o side
/// sheet»*, y *«Arrastrar hacia abajo cierra; el backdrop también»*.
///
/// **Dónde empieza «táctil» lo fija `F-06`, textualmente:** *«Bajo 900 px de
/// ancho lógico la densidad se fuerza a touch: 48 px de target sin importar la
/// preferencia.»* Es el mismo 900 que publica
/// [ResponsiveBreakpoints.desktopMin], así que **la tablet de 834 es un host
/// táctil**: bottom sheet y objetivo de 48, no popover de escritorio.
@immutable
class VbShortSelectOption<T> {
  const VbShortSelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;

  /// Etiqueta corta. La guía pide etiquetas cortas justamente porque el menú no
  /// hace scroll ni envuelve.
  final String label;

  /// Deshabilitada dentro de una lista habilitada — el `Anulada` gris del
  /// dibujo de la guía.
  final bool enabled;
}

class VbShortSelect<T> extends StatefulWidget {
  const VbShortSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.sheetTitle,
    this.label,
    this.placeholder,
    this.semanticLabel,
  });

  final T value;

  final List<VbShortSelectOption<T>> options;

  /// `null` deshabilita el control, igual que en cualquier control de Material.
  final ValueChanged<T>? onChanged;

  /// Título del bottom sheet táctil («Elegir persona» en el dibujo de la guía).
  /// Se exige siempre porque el mismo widget cambia de presentación con el
  /// ancho: un título que sólo se escribe «cuando toque» aparece vacío en el
  /// primer teléfono que abra la pantalla.
  final String sheetTitle;

  /// Rótulo sobre el campo, tal como lo dibuja S-05 (`500 11`, 5 px de aire).
  /// Es parte del componente, no del llamador: dejarlo afuera es exactamente
  /// cómo cada pantalla termina con su propio rótulo.
  final String? label;

  /// Texto cuando el valor actual no está en la lista — el estado `vacío`.
  final String? placeholder;

  final String? semanticLabel;

  /// El techo que publica la guía. Por encima, el componente es S-06.
  static const int maxOptions = 7;

  /// Alto **visual** del campo cerrado. No es el objetivo táctil: ver
  /// [touchTargetHeight].
  static const double fieldHeight = 34;

  /// El rótulo de S-05 sobre cualquier campo, no sólo sobre este control.
  ///
  /// **Se expone porque el rótulo es del componente, no del llamador.** En un
  /// mismo bloque conviven este control y un campo de texto libre, y con dos
  /// dueños del rótulo el texto libre terminaba mostrando el suyo dentro de la
  /// caja mientras el de al lado lo llevaba encima: dos formas de nombrar lo
  /// mismo, una al lado de la otra. Un `label` nulo devuelve el campo tal cual.
  static Widget labelled(BuildContext context, String? label, Widget field) {
    if (label == null) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 5),
        field,
      ],
    );
  }

  /// Objetivo táctil bajo [ResponsiveBreakpoints.desktopMin].
  ///
  /// **`F-06` lo publica textualmente:** *«Bajo 900 px de ancho lógico la
  /// densidad se fuerza a touch: 48 px de target sin importar la preferencia.»*
  /// Y la guía enseña el patrón exacto —caja visual chica dentro de un área
  /// grande— en dos sitios más: el campo de búsqueda dice `Alto 34 (48 touch)`
  /// y la casilla dice `toda la fila es el hit target (34, 48 en touch)`, con
  /// un recuadro rotulado **«TOUCH — 48 con área invisible»**. Así que la caja
  /// de 34 **no cambia**: crece el objetivo alrededor de ella.
  static const double touchTargetHeight = 48;

  /// Alto de cada opción del popover de escritorio.
  static const double optionHeight = 30;

  /// Alto de cada fila del bottom sheet táctil (O-05).
  static const double sheetRowHeight = 48;

  @override
  State<VbShortSelect<T>> createState() => _VbShortSelectState<T>();
}

class _VbShortSelectState<T> extends State<VbShortSelect<T>> {
  final GlobalKey _anchor = GlobalKey();
  bool _open = false;

  VbShortSelectOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  bool get _enabled => widget.onChanged != null;

  /// **El umbral es 900, no 600 — y lo fija `F-06`, no una preferencia mía.**
  ///
  /// La guía: *«Bajo 900 px de ancho lógico la densidad se fuerza a touch»*.
  /// Coincide con el contrato del repositorio, donde
  /// [ResponsiveBreakpoints.desktopMin] es 900 y el shell es compacto por
  /// debajo: la tablet de 834 **es** un host táctil, no un escritorio angosto.
  ///
  /// Una versión anterior usó `phoneMaxExclusive` (600) y por eso la tablet
  /// abría un popover donde correspondía un bottom sheet — visible en las
  /// capturas de 834 antes de esta corrección.
  ///
  /// El mismo umbral decide las dos cosas que dependen de «esto es táctil»: la
  /// presentación de la lista y el tamaño del objetivo.
  bool _isTouchHost(BuildContext context) =>
      MediaQuery.sizeOf(context).width < ResponsiveBreakpoints.desktopMin;

  Future<void> _openMenu() async {
    if (!_enabled || widget.options.isEmpty) return;
    // La presentación se decide **antes** de abrir nada: después del `await` el
    // contexto ya no es el mismo y elegir ahí sería leerlo cruzando el hueco.
    final useSheet = _isTouchHost(context);
    final pending = useSheet ? _showSheet() : _showPopover();
    setState(() => _open = true);
    final result = await pending;
    if (!mounted) return;
    setState(() => _open = false);
    // Escape y el backdrop cierran **sin cambiar el valor**: por eso el
    // resultado viaja envuelto. Devolver `T?` haría indistinguible «cancelé»
    // de «elegí el valor nulo», que es exactamente el caso de este ERP —
    // `Sin especificar` es una opción legítima.
    if (result != null) widget.onChanged?.call(result.value);
  }

  Future<_VbShortSelectChoice<T>?> _showPopover() {
    return showVbAnchoredPopover<_VbShortSelectChoice<T>>(
      anchorContext: _anchor.currentContext ?? context,
      builder: (_) => _VbShortSelectMenu<T>(
        options: widget.options,
        value: widget.value,
      ),
    );
  }

  Future<_VbShortSelectChoice<T>?> _showSheet() {
    final media = MediaQuery.of(context);
    return showModalBottomSheet<_VbShortSelectChoice<T>>(
      context: context,
      // La superficie la pinta O-05, no el tema del sheet: así el radio de 14
      // y la sombra de overlay quedan donde se pueden leer.
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      constraints: BoxConstraints(
        // «Máx. 60% de alto; con más, es una página.»
        maxHeight: media.size.height * 0.6,
      ),
      builder: (_) => _VbShortSelectSheet<T>(
        title: widget.sheetTitle,
        options: widget.options,
        value: widget.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.options.length <= VbShortSelect.maxOptions,
      'S-05 admite hasta ${VbShortSelect.maxOptions} opciones y su menú no '
      'hace scroll. Con ${widget.options.length} el componente correcto es '
      'S-06 (searchable), no un S-05 más alto.',
    );

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final selected = _selected;
    final label = selected?.label ?? widget.placeholder ?? '';

    final Color background =
        _enabled ? scheme.surface : scheme.surfaceContainerLow;
    final Color border = _open
        ? roles.focusRing
        : (_enabled ? scheme.outline : scheme.outlineVariant);
    final Color foreground = !_enabled
        ? roles.disabledForeground
        : (selected == null ? scheme.onSurfaceVariant : scheme.onSurface);

    // **El objetivo táctil crece; la caja NO.** `F-06`: bajo 900 px el target
    // es de 48 px, y la guía dibuja ese patrón como «48 con área invisible».
    // El `InkWell` —que es a la vez el ancla del popover y el nodo semántico—
    // ocupa el objetivo completo; la caja de 34 queda centrada dentro.
    final double target = _isTouchHost(context)
        ? VbShortSelect.touchTargetHeight
        : VbShortSelect.fieldHeight;

    return _withLabel(
      context,
      Semantics(
        button: true,
        enabled: _enabled,
        expanded: _open,
        label: widget.semanticLabel,
        value: label,
        excludeSemantics: true,
        child: _VbShortSelectFieldShortcuts(
          enabled: _enabled,
          onOpen: _openMenu,
          child: InkWell(
            key: _anchor,
            onTap: _enabled ? _openMenu : null,
            borderRadius: BorderRadius.circular(_fieldRadius),
            child: Container(
              height: target,
              alignment: Alignment.center,
              child: Container(
                height: VbShortSelect.fieldHeight,
                padding: const EdgeInsets.only(left: 11, right: 9),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(_fieldRadius),
                  border: Border.all(color: border),
                  boxShadow: _open
                      ? <BoxShadow>[
                          // «0 0 0 3px rgba(22,104,189,.12)» — anillo sin blur ni
                          // desplazamiento, sólo extensión.
                          BoxShadow(
                            color: roles.focusRing.withValues(alpha: 0.12),
                            spreadRadius: 3,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _valueStyle(foreground),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _open ? '▴' : '▾',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                        color: !_enabled
                            ? roles.disabledForeground
                            : (_open
                                ? roles.focusRing
                                : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// El rótulo de S-05: `font:500 11px`, `margin-bottom:5px`.
  Widget _withLabel(BuildContext context, Widget field) =>
      VbShortSelect.labelled(context, widget.label, field);

  TextStyle _valueStyle(Color color) => GoogleFonts.ibmPlexSans(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: color,
      );
}

/// `radius.field` de la guía.
const double _fieldRadius = 8;

/// `radius` de la opción dentro del popover.
const double _optionRadius = 6;

/// `radius.pill`, el último peldaño de la escalera de radios de la guía
/// (`4 · 6 · 8 · 10 · 14 · 999`, el 999 rotulado `pill`). No es un número
/// plausible: es el token publicado, y el handle del bottom sheet lo escribe
/// literal — `width:34px;height:4px;border-radius:999px`.
const double _pillRadius = 999;

/// Elección envuelta, para que «cerré sin cambiar» no se confunda con «elegí
/// null».
@immutable
class _VbShortSelectChoice<T> {
  const _VbShortSelectChoice(this.value);
  final T value;
}

/// Teclado del campo cerrado, tal como lo publica la guía: *«Enter/Espacio/↓
/// abre»*.
class _VbShortSelectFieldShortcuts extends StatelessWidget {
  const _VbShortSelectFieldShortcuts({
    required this.enabled,
    required this.onOpen,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space) {
          onOpen();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// El menú de escritorio: contenido del popover anclado (S-05 + O-02).
class _VbShortSelectMenu<T> extends StatefulWidget {
  const _VbShortSelectMenu({required this.options, required this.value});

  final List<VbShortSelectOption<T>> options;
  final T value;

  @override
  State<_VbShortSelectMenu<T>> createState() => _VbShortSelectMenuState<T>();
}

class _VbShortSelectMenuState<T> extends State<_VbShortSelectMenu<T>> {
  late int _highlight = _initialHighlight();

  int _initialHighlight() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].value == widget.value) return i;
    }
    return _firstEnabled();
  }

  int _firstEnabled() {
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].enabled) return i;
    }
    return -1;
  }

  void _move(int delta) {
    if (widget.options.isEmpty) return;
    var index = _highlight;
    for (var step = 0; step < widget.options.length; step++) {
      index = (index + delta) % widget.options.length;
      if (index < 0) index += widget.options.length;
      if (widget.options[index].enabled) {
        setState(() => _highlight = index);
        return;
      }
    }
  }

  void _commit() {
    if (_highlight < 0 || _highlight >= widget.options.length) return;
    final option = widget.options[_highlight];
    if (!option.enabled) return;
    Navigator.of(context).pop(_VbShortSelectChoice<T>(option.value));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown) {
          _move(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp) {
          _move(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) {
          _commit();
          return KeyEventResult.handled;
        }
        // «Tab cierra confirmando el resaltado.»
        if (key == LogicalKeyboardKey.tab) {
          _commit();
          return KeyEventResult.handled;
        }
        // Escape lo maneja el owner del popover, que ya cierra sin cambiar.
        return KeyEventResult.ignored;
      },
      child: VbPopoverSurface(
        child: Padding(
          padding: const EdgeInsets.all(5),
          // **No es scrollable por diseño** (la guía lo dice con esas
          // palabras). Este `SingleChildScrollView` sólo evita que una ventana
          // más baja que el menú desborde: con las ≤7 opciones que el
          // componente admite, nunca hay nada que desplazar.
          child: SingleChildScrollView(
            // **`IntrinsicWidth` o el menú se come el viewport.** Cada opción
            // es un `Row` con `Expanded`, así que sin esto la columna adopta el
            // ancho MÁXIMO que el popover admite: medido en la app viva, un
            // menú de 1.672 px colgando de un campo de 206. La guía pide
            // «mismo ancho o más», y ese «más» es el de la opción más larga,
            // no el de la pantalla. El piso lo sigue poniendo
            // `showVbAnchoredPopover`, que arranca en el ancho del campo.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.options.length; i++)
                    _MenuOption<T>(
                      option: widget.options[i],
                      selected: widget.options[i].value == widget.value,
                      highlighted: i == _highlight,
                      onTap: () => Navigator.of(context).pop(
                        _VbShortSelectChoice<T>(widget.options[i].value),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuOption<T> extends StatelessWidget {
  const _MenuOption({
    required this.option,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  final VbShortSelectOption<T> option;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final marked = selected || highlighted;

    return Semantics(
      button: true,
      selected: selected,
      enabled: option.enabled,
      label: option.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: option.enabled ? onTap : null,
        borderRadius: BorderRadius.circular(_optionRadius),
        child: Container(
          height: VbShortSelect.optionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: marked ? roles.selectionContainer : null,
            borderRadius: BorderRadius.circular(_optionRadius),
            border: Border.all(
              color: marked ? roles.info.border : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11.5,
                    fontWeight: marked ? FontWeight.w600 : FontWeight.w400,
                    color: !option.enabled
                        ? roles.disabledForeground
                        : (marked
                            ? roles.onSelectionContainer
                            : scheme.onSurface),
                  ),
                ),
              ),
              if (selected)
                Text(
                  '✓',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: roles.focusRing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// **O-05 · el mismo select en táctil.**
///
/// `r14 arriba · handle 34×4 · título 14 Poppins · filas de 48 con separador`.
/// El alto máximo lo acota quien lo abre (60% de la pantalla).
///
/// La sombra: la guía publica `0 12px 40px rgba(12,37,55,.22)` para el nivel
/// `overlay`. El **desplazamiento y el blur se copian literales**; el color va
/// atado a `roles.shadow` en vez de al navy literal al .22 porque la sección
/// «16 Dark mode» de la guía cae **más allá del tope de 256 KiB** del API de
/// archivos y no se puede leer. En claro `roles.shadow` resuelve a ese mismo
/// navy al .2 —dos centésimas de diferencia con el .22 del archivo, anotadas
/// acá— y eso es preferible a inventar un segundo valor oscuro sin fuente.
class _VbShortSelectSheet<T> extends StatelessWidget {
  const _VbShortSelectSheet({
    required this.title,
    required this.options,
    required this.value,
  });

  final String title;
  final List<VbShortSelectOption<T>> options;
  final T value;

  static const double _sheetRadius = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    const radius = BorderRadius.vertical(top: Radius.circular(_sheetRadius));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: roles.shadow, blurRadius: 40, offset: const Offset(0, 12)),
        ],
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle 34×4. Es decorativo: lo que se anuncia es el título.
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(top: 9, bottom: 7),
                  child: Center(
                    child: Container(
                      width: 34,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outline,
                        // `radius.pill`. La escalera de radios de la guía es
                        // `4 · 6 · 8 · 10 · 14 · 999`, y el último está
                        // rotulado **`pill`**; el handle lo usa literalmente:
                        // `width:34px;height:4px;border-radius:999px`.
                        borderRadius: BorderRadius.circular(_pillRadius),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
                // «Foco al título al abrir»: el encabezado es lo primero que
                // el lector de pantalla anuncia.
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i == 0)
                          Divider(height: 1, color: scheme.outlineVariant),
                        _SheetRow<T>(
                          option: options[i],
                          selected: options[i].value == value,
                          onTap: () => Navigator.of(context).pop(
                            _VbShortSelectChoice<T>(options[i].value),
                          ),
                        ),
                        if (i != options.length - 1)
                          Divider(height: 1, color: scheme.outlineVariant),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetRow<T> extends StatelessWidget {
  const _SheetRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final VbShortSelectOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);

    return Semantics(
      button: true,
      selected: selected,
      enabled: option.enabled,
      label: option.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: option.enabled ? onTap : null,
        child: Container(
          height: VbShortSelect.sheetRowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          color: selected ? roles.selectionContainer : null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: !option.enabled
                        ? roles.disabledForeground
                        : (selected
                            ? roles.onSelectionContainer
                            : scheme.onSurface),
                  ),
                ),
              ),
              if (selected)
                Text(
                  '✓',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: roles.focusRing,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
