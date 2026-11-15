import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../utils/desktop_input.dart';

/// Las flechas mueven lo que está bajo el cursor, como en un navegador.
///
/// El dueño, 2026-11-14: «no puedo mover filas con los arrows o moverme hacia
/// el lado con las flechas». En el escritorio Flutter usa las flechas para
/// pasar el foco de un control a otro, y desplazar pide Cmd/Ctrl + flecha con
/// el foco puesto dentro de la lista: para quien mira una tabla, las flechas no
/// hacían nada.
///
/// - ↑ ↓ desplazan la lista bajo el cursor; ← → la mueven hacia el lado, que es
///   lo que necesita una tabla más ancha que la ventana.
/// - Re Pág y Av Pág avanzan casi una pantalla; Inicio y Fin van a los extremos.
/// - Si lo de más adentro ya llegó a su tope, sigue lo que lo contiene.
///
/// No se mete donde las flechas ya tienen dueño: un campo de texto, un menú
/// abierto, o cualquier control que las atienda por su cuenta (esos reciben la
/// tecla antes que este manejador). Con Mayús, Ctrl, Alt o Cmd tampoco. Un
/// visor por páginas (pestañas, fotos) no cambia de página: tiene sus botones.
///
/// Los desplazables se encuentran por lo que hay bajo el cursor en el momento
/// de la tecla, con las marcas que deja [KeyboardScrollTarget]. No se guarda
/// ningún «último desplazable»: quedaría apuntando a una pantalla que ya no
/// está. Sólo existe con mouse y teclado ([usesDesktopPointerAndKeyboard]).
class KeyboardScrollScope extends StatefulWidget {
  const KeyboardScrollScope({super.key, required this.child});

  final Widget child;

  /// Cuánto avanza una flecha, en píxeles lógicos: unas dos filas de tabla.
  static const double lineStep = 72;

  /// Envuelve el contenido de un [Scrollable] con su marca.
  ///
  /// Se llama desde el [ScrollBehavior] de la app con el `context` que éste
  /// recibe, que es el del propio [Scrollable].
  static Widget markScrollable(BuildContext context, Widget child) {
    if (context is StatefulElement) {
      final state = context.state;
      if (state is ScrollableState) {
        return KeyboardScrollTarget(scrollable: state, child: child);
      }
    }
    return child;
  }

  @override
  State<KeyboardScrollScope> createState() => _KeyboardScrollScopeState();
}

class _KeyboardScrollScopeState extends State<KeyboardScrollScope> {
  Offset? _pointer;
  int? _pointerView;
  bool _tracking = false;

  /// Hacia dónde va lo que movió una flecha anterior. Dos toques rápidos
  /// suman dos pasos aunque el primero no haya terminado de moverse.
  final Expando<double> _heading = Expando<double>('keyboard-scroll-heading');

  @override
  void initState() {
    super.initState();
    if (usesDesktopPointerAndKeyboard) {
      GestureBinding.instance.pointerRouter.addGlobalRoute(_trackPointer);
      _tracking = true;
    }
  }

  @override
  void dispose() {
    if (_tracking) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_trackPointer);
    }
    super.dispose();
  }

  void _trackPointer(PointerEvent event) {
    if (event is PointerHoverEvent ||
        event is PointerMoveEvent ||
        event is PointerDownEvent) {
      _pointer = event.position;
      _pointerView = event.viewId;
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final move = _KeyMove.of(event.logicalKey);
    if (move == null) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (_focusOwnsTheKey()) return KeyEventResult.ignored;

    final pointer = _pointer;
    final view = _pointerView;
    if (pointer == null || view == null) return KeyEventResult.ignored;

    for (final scrollable in _scrollablesUnder(pointer, view)) {
      if (_scroll(scrollable, move, repeat: event is KeyRepeatEvent)) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// Un campo de texto mueve su cursor con las flechas, y un menú abierto pasa
  /// de un ítem a otro: ahí la tecla no es para desplazar.
  bool _focusOwnsTheKey() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null || !focused.mounted) return false;
    if (focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }
    final route = ModalRoute.of(focused);
    // Un diálogo o una hoja son contenido para leer; el resto de las rutas
    // emergentes son menús y listas de opciones.
    return route is PopupRoute &&
        route is! RawDialogRoute &&
        route is! ModalBottomSheetRoute;
  }

  /// De adentro hacia afuera, lo que hay bajo el cursor.
  List<ScrollableState> _scrollablesUnder(Offset position, int view) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, view);
    final found = <ScrollableState>[];
    for (final entry in result.path) {
      final target = entry.target;
      if (target is _RenderKeyboardScrollTarget &&
          target.scrollable.mounted &&
          !found.contains(target.scrollable)) {
        found.add(target.scrollable);
      }
    }
    return found;
  }

  bool _scroll(
    ScrollableState scrollable,
    _KeyMove move, {
    required bool repeat,
  }) {
    final position = scrollable.position;
    if (!position.hasPixels || !position.hasContentDimensions) return false;
    if (axisDirectionToAxis(position.axisDirection) != move.axis) return false;
    // Un visor por páginas —pestañas, fotos— cambia con sus propios botones:
    // una flecha no lo hace saltar a la pestaña vecina.
    if (position is PageMetrics) return false;
    // Una lista bloqueada a propósito tampoco se mueve con el teclado.
    if (!position.physics.shouldAcceptUserOffset(position)) return false;

    final forward = axisDirectionIsReversed(position.axisDirection)
        ? !move.forward
        : move.forward;
    final sign = forward ? 1.0 : -1.0;
    final from = _heading[position] ?? position.pixels;
    final double wanted;
    switch (move.amount) {
      case _KeyAmount.line:
        wanted = from + sign * KeyboardScrollScope.lineStep;
      case _KeyAmount.page:
        wanted = from + sign * position.viewportDimension * 0.85;
      case _KeyAmount.edge:
        wanted = forward ? position.maxScrollExtent : position.minScrollExtent;
    }
    final target = wanted
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - from).abs() < 0.5) return false;

    if (repeat) {
      // Con la tecla mantenida llega una repetición cada pocos milisegundos:
      // animar cada una las haría esperarse entre sí.
      _heading[position] = null;
      position.jumpTo(target);
    } else {
      _heading[position] = target;
      position
          .animateTo(
        target,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        if (_heading[position] == target) _heading[position] = null;
      });
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!usesDesktopPointerAndKeyboard) return widget.child;
    // Recibe la tecla después de lo que tiene el foco y antes que los atajos
    // generales de la app: quien la atiende más adentro la detiene ahí.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}

enum _KeyAmount { line, page, edge }

class _KeyMove {
  const _KeyMove(this.axis, this.amount, {required this.forward});

  final Axis axis;
  final _KeyAmount amount;

  /// Hacia abajo o hacia la derecha, tal como se ve.
  final bool forward;

  static _KeyMove? of(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowDown) {
      return const _KeyMove(Axis.vertical, _KeyAmount.line, forward: true);
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return const _KeyMove(Axis.vertical, _KeyAmount.line, forward: false);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return const _KeyMove(Axis.horizontal, _KeyAmount.line, forward: true);
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return const _KeyMove(Axis.horizontal, _KeyAmount.line, forward: false);
    }
    if (key == LogicalKeyboardKey.pageDown) {
      return const _KeyMove(Axis.vertical, _KeyAmount.page, forward: true);
    }
    if (key == LogicalKeyboardKey.pageUp) {
      return const _KeyMove(Axis.vertical, _KeyAmount.page, forward: false);
    }
    if (key == LogicalKeyboardKey.end) {
      return const _KeyMove(Axis.vertical, _KeyAmount.edge, forward: true);
    }
    if (key == LogicalKeyboardKey.home) {
      return const _KeyMove(Axis.vertical, _KeyAmount.edge, forward: false);
    }
    return null;
  }
}

/// Marca el área de un [Scrollable] para que [KeyboardScrollScope] sepa cuál
/// está bajo el cursor. No dibuja ni cambia medidas.
class KeyboardScrollTarget extends SingleChildRenderObjectWidget {
  const KeyboardScrollTarget({
    super.key,
    required this.scrollable,
    super.child,
  });

  final ScrollableState scrollable;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeyboardScrollTarget(scrollable);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderKeyboardScrollTarget).scrollable = scrollable;
  }
}

class _RenderKeyboardScrollTarget extends RenderProxyBox {
  _RenderKeyboardScrollTarget(this.scrollable);

  ScrollableState scrollable;
}
