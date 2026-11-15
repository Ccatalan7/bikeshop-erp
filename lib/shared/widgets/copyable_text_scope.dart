import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../utils/desktop_input.dart';

/// Una superficie cuyo texto se puede marcar con el mouse y copiar.
///
/// El dueño, 2026-11-14: «no puedo hacer highlight de texto para copiar y
/// pegar». El ERP no tenía ninguna zona de selección —sólo el acceso y la
/// tienda—, y además el arrastre del mouse estaba configurado para desplazar,
/// que le gana a la selección: el desplazamiento se decide con 1 px de
/// movimiento y la selección necesita 2.
///
/// Va **una por superficie** —cada página, cada panel del riel, cada diálogo—
/// y nunca una sola arriba de todo. La selección de Flutter se resuelve por
/// geometría, no por lo que se ve: con una zona común, marcar texto en un
/// diálogo o en un espacio de trabajo también marcaría el texto tapado de la
/// página de abajo o del espacio inactivo, y eso es lo que se copiaría.
///
/// Dentro de la zona el arrastre del mouse marca texto y deja de desplazar.
/// Para moverse quedan la rueda, Mayús + rueda hacia el lado, el trackpad y las
/// flechas (`KeyboardScrollScope`). El dedo sigue desplazando igual. Sólo
/// existe con mouse y teclado ([usesDesktopPointerAndKeyboard]).
class CopyableTextScope extends StatefulWidget {
  const CopyableTextScope({super.key, required this.child}) : _selects = true;

  /// No marca nada por sí misma: hace que los diálogos, hojas y menús que se
  /// abran desde aquí abajo nazcan con su propia zona.
  ///
  /// Va en la raíz del ERP, para lo que se abre desde fuera de una página.
  const CopyableTextScope.host({super.key, required this.child})
      : _selects = false;

  final Widget child;
  final bool _selects;

  /// Los mismos dispositivos que desplazan por defecto en Flutter: todos menos
  /// el mouse.
  static const Set<PointerDeviceKind> _scrollDragDevices = <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  State<CopyableTextScope> createState() => _CopyableTextScopeState();
}

class _CopyableTextScopeState extends State<CopyableTextScope> {
  // La zona tiene el foco sólo mientras hay algo marcado, que es lo que
  // necesita Cmd/Ctrl+C. Por defecto Flutter se lo da con cualquier clic, y un
  // clic en una foto o en una fila le quitaba las teclas a lo que las escucha
  // más adentro: las flechas del visor de fotos de un producto, el Esc de un
  // panel. Al desmarcar, el foco vuelve a quien lo tenía.
  //
  // Tampoco es una parada de Tab: si lo fuera, un menú recién abierto le daría
  // el foco a ella antes que a su primer ítem.
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'CopyableTextScope',
    skipTraversal: true,
    canRequestFocus: false,
  );

  void _selectionChanged(SelectedContent? content) {
    final marked = content != null && content.plainText.isNotEmpty;
    _focusNode.canRequestFocus = marked;
    if (marked && !_focusNode.hasFocus) _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!usesDesktopPointerAndKeyboard) return widget.child;

    // Ya hay una zona arriba en esta misma superficie: una sola basta, y dos
    // anidadas se pelean el mismo arrastre.
    final alreadySelectable = SelectionContainer.maybeOf(context) != null;
    // El menú y las asas de la selección se dibujan en el Overlay.
    final selects = widget._selects &&
        !alreadySelectable &&
        Overlay.maybeOf(context) != null;
    if (!selects) return _CopyableTextRoutes(child: widget.child);

    return _CopyableTextRoutes(
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: CopyableTextScope._scrollDragDevices,
        ),
        child: SelectionArea(
          focusNode: _focusNode,
          onSelectionChanged: _selectionChanged,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Lleva la zona a las rutas que se abren desde aquí.
///
/// `showDialog`, `showModalBottomSheet` y los menús capturan los
/// [InheritedTheme] que hay entre quien los abre y el navegador, y envuelven
/// con ellos su contenido. Es el único punto por el que pasan los 377 diálogos
/// del ERP sin tocarlos uno por uno.
class _CopyableTextRoutes extends InheritedTheme {
  const _CopyableTextRoutes({required super.child});

  @override
  Widget wrap(BuildContext context, Widget child) =>
      CopyableTextScope(child: child);

  @override
  bool updateShouldNotify(_CopyableTextRoutes oldWidget) => false;
}
