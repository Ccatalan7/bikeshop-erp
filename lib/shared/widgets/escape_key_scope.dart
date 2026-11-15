import 'package:flutter/material.dart';

import '../utils/desktop_input.dart';

/// Esc saca el cursor de un campo de texto cuando nada más usa la tecla.
///
/// El dueño, 2026-11-14: «ESC doesn't unfocus a search bar». En Flutter, Esc
/// es «cancelar» (`DismissIntent`) y sube desde el campo hasta el primero que
/// lo usa: el menú del campo, las opciones de un Autocomplete, un popover, una
/// edición que se cancela, el diálogo o la hoja que lo contiene. En una página
/// nadie lo usaba —la página misma no hace nada— y el cursor se quedaba en el
/// buscador.
///
/// Va una por superficie, al final de su cadena: la monta `CopyableTextScope`
/// en cada página, panel del riel y diálogo. Le llega Esc sólo si nada más
/// adentro lo usó; si lo usa lo que contiene la superficie (el diálogo que se
/// cierra), se lo pasa, y si no, saca el cursor del campo. Lo escrito queda.
///
/// Es una acción y no un manejador de teclas porque en el Mac, con un campo
/// enfocado, la tecla da la vuelta por el sistema y vuelve como «cancelar»
/// (`cancelOperation:`); en Windows llega por los atajos de la app. Como
/// acción le toca después de todo lo que ya usa Esc, sin tener que adivinarlo.
///
/// Sólo con mouse y teclado ([usesDesktopPointerAndKeyboard]).
class EscapeKeyScope extends StatefulWidget {
  const EscapeKeyScope({super.key, required this.child});

  final Widget child;

  @override
  State<EscapeKeyScope> createState() => _EscapeKeyScopeState();
}

class _EscapeKeyScopeState extends State<EscapeKeyScope> {
  late final _LeaveTheField _action = _LeaveTheField(this);

  @override
  Widget build(BuildContext context) {
    if (!usesDesktopPointerAndKeyboard) return widget.child;
    return Actions(
      actions: <Type, Action<Intent>>{DismissIntent: _action},
      child: widget.child,
    );
  }
}

class _LeaveTheField extends Action<DismissIntent> {
  _LeaveTheField(this._scope);

  final _EscapeKeyScopeState _scope;

  /// Lo que contiene la superficie —el diálogo, la hoja, el menú— usa Esc.
  ///
  /// Se busca desde la superficie, que está encima de esta acción: es lo que
  /// hace el campo mismo con su menú cerrado.
  bool _usedOutside(DismissIntent intent) {
    if (!_scope.mounted) return false;
    final context = _scope.context;
    final action = Actions.maybeFind<DismissIntent>(context, intent: intent);
    if (action == null) return false;
    return action is ContextAction<DismissIntent>
        ? action.isEnabled(intent, context)
        : action.isEnabled(intent);
  }

  /// El campo de esta superficie que tiene el cursor, si lo hay.
  FocusNode? _focusedField() {
    final focused = FocusManager.instance.primaryFocus;
    final field =
        focused?.context?.findAncestorStateOfType<EditableTextState>();
    if (field == null || field.widget.focusNode != focused) return null;
    final surface =
        field.context.findAncestorStateOfType<_EscapeKeyScopeState>();
    return identical(surface, _scope) ? focused : null;
  }

  @override
  bool isEnabled(DismissIntent intent) =>
      _usedOutside(intent) || _focusedField() != null;

  @override
  Object? invoke(DismissIntent intent) {
    if (_usedOutside(intent)) {
      return Actions.maybeInvoke(_scope.context, intent);
    }
    _focusedField()?.unfocus();
    return null;
  }
}
