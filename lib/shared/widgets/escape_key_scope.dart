import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/desktop_input.dart';

/// Esc saca el cursor de un campo de texto cuando nada más usa la tecla.
///
/// El dueño, 2026-11-14: «ESC doesn't unfocus a search bar». En Flutter, Esc
/// es «cancelar» (`DismissIntent`) y sube desde el campo hasta la primera
/// acción de cancelar que encuentra: las opciones de un Autocomplete, un menú
/// abierto, una edición que se cancela, el cajón o el diálogo que lo contiene.
/// **Se detiene en esa primera acción aunque esté apagada**, y cada `Scaffold`
/// trae una (cerrar su cajón lateral) que sin cajón abierto no hace nada: en
/// una página la tecla moría ahí y el cursor se quedaba en el buscador.
///
/// Va una vez, en el `builder` del `MaterialApp` autenticado: recibe la tecla
/// después de todo lo que la atiende más adentro (un popover, el desmarcar de
/// `CopyableTextScope`) y antes de que siga a cancelar. Hace el mismo camino
/// que hará cancelar y, si nadie la va a usar, quita el foco del campo; si no,
/// la deja pasar. Lo escrito queda; mientras se compone una letra (´ + e) la
/// tecla es del sistema.
///
/// Sólo con mouse y teclado ([usesDesktopPointerAndKeyboard]).
class EscapeKeyScope extends StatelessWidget {
  const EscapeKeyScope({super.key, required this.child});

  final Widget child;

  static KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus;
    final field =
        focused?.context?.findAncestorStateOfType<EditableTextState>();
    if (focused == null || field == null || field.widget.focusNode != focused) {
      return KeyEventResult.ignored;
    }
    final composing = field.textEditingValue.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (_escapeIsUsedAround(field.context)) return KeyEventResult.ignored;
    focused.unfocus();
    return KeyEventResult.handled;
  }

  /// Si cancelar, subiendo desde el campo, va a hacer algo.
  static bool _escapeIsUsedAround(BuildContext field) {
    // Un Autocomplete con sus opciones a la vista las cierra; con ellas
    // cerradas pasa la tecla hacia arriba, igual que el menú del campo.
    Element? autocomplete;
    field.visitAncestorElements((element) {
      if (element.widget is! RawAutocomplete) return true;
      autocomplete = element;
      return false;
    });
    final options = autocomplete;
    if (options != null && _showsOptions(options)) return true;

    // La primera acción de cancelar más arriba, sin contar la del campo ni la
    // del Autocomplete (quedan debajo de `from`). Como cancelar, se detiene en
    // ella esté o no encendida.
    final from = options ?? field;
    Action<Intent>? action;
    from.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Actions) action = widget.actions[DismissIntent];
      return action == null;
    });
    final found = action;
    if (found == null) return false;
    const intent = DismissIntent();
    return found is ContextAction<Intent>
        ? found.isEnabled(intent, from)
        : found.isEnabled(intent);
  }

  /// Las opciones se dibujan bajo `AutocompleteHighlightedOption` sólo
  /// mientras están a la vista.
  static bool _showsOptions(Element autocomplete) {
    var shown = false;
    void visit(Element element) {
      if (shown) return;
      if (element.widget is AutocompleteHighlightedOption) {
        shown = true;
        return;
      }
      element.visitChildren(visit);
    }

    autocomplete.visitChildren(visit);
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    if (!usesDesktopPointerAndKeyboard) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: child,
    );
  }
}
