import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/barcode_scanner_service.dart';
import '../../services/global_search/global_search_index.dart';
import 'global_search_overlay.dart';

/// Escribir abre el buscador, en cualquier pantalla del ERP.
///
/// **La entrada es teclear, no un campo.** No hay una caja de búsqueda en el
/// inicio ni en ninguna pantalla: se está donde se está —una lista de facturas,
/// una pega abierta, el POS— se empieza a escribir y el buscador aparece
/// flotando con lo tecleado adentro. `⌘K` / `Ctrl+K` hace lo mismo
/// explícitamente, para quien prefiere un atajo.
///
/// **Por qué el buffer vive acá y no en el buscador.** El panel tarda 200 ms en
/// entrar. Si el texto naciera dentro de él, las teclas escritas durante esa
/// transición no tendrían dónde caer: medido en la app el 2026-09-17, escribir
/// «felipe» de corrido llegaba como «feli». Este widget está montado siempre,
/// así que la tecla entra al mismo buffer viva donde viva el foco — primero acá,
/// y desde que el campo del panel toma el foco, en el campo.
///
/// **Por qué no le roba las teclas al lector de códigos de barras.** El lector
/// de teclado escribe con el mismo patrón —sin campo enfocado— y por eso
/// `ScannerBridgeScope` ya escucha ahí. La diferencia no se adivina por
/// velocidad: `BarcodeScannerService` **sólo escucha cuando una pantalla lo
/// armó** (hoy, la de Configuración › Lector de teclado; está escrito en
/// `scanner_bridge_scope.dart`). Mientras esté armado, este atajo se calla.
class GlobalSearchShortcut extends StatefulWidget {
  const GlobalSearchShortcut({super.key, required this.child});

  final Widget child;

  @override
  State<GlobalSearchShortcut> createState() => _GlobalSearchShortcutState();
}

class _GlobalSearchShortcutState extends State<GlobalSearchShortcut> {
  /// El texto vive fuera del panel: ver la nota de la clase.
  final TextEditingController _buffer = TextEditingController();
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _registered = true;
    // El índice se calienta al entrar al ERP, no al primer tecleo: la primera
    // búsqueda del día tiene que encontrar registros y no sólo menús.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GlobalSearchIndex>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    if (_registered) HardwareKeyboard.instance.removeHandler(_onKey);
    _buffer.dispose();
    super.dispose();
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;

    if (_isDesktop && _isSearchShortcut(event)) {
      _open();
      return true;
    }
    if (!_shouldCapture(event)) return false;

    _buffer.text = '${_buffer.text}${event.character}';
    _buffer.selection = TextSelection.collapsed(offset: _buffer.text.length);
    // Abrir sólo la primera vez. Con el panel ya arriba, `open` significaría
    // «cerrar», y cada tecla lo haría parpadear.
    if (!GlobalSearchOverlay.isOpen) _open();
    return true;
  }

  bool _isSearchShortcut(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    return defaultTargetPlatform == TargetPlatform.macOS
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
  }

  /// Sólo un carácter que alguien quiso escribir, y sólo cuando no hay dónde
  /// escribirlo.
  /// Se sigue capturando **aunque el panel ya esté abierto**, mientras el foco
  /// no haya llegado a su campo.
  ///
  /// **Causa medida (2026-09-17, sesión real):** cortar acá por «ya está
  /// abierto» reabría el mismo hueco que este widget existe para tapar. El
  /// panel tarda 200 ms en entrar y su campo toma el foco recién al montarse;
  /// entre una cosa y la otra escribir «felipe» dejaba «f». La condición
  /// correcta no es si el panel está abierto, es si **hay dónde escribir**.
  bool _shouldCapture(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    // Un acorde es un comando de otro, no el principio de una búsqueda.
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return false;
    }

    final character = event.character;
    if (character == null || character.runes.length != 1) return false;
    final code = character.runes.first;
    // Control, tabulador, retorno y borrar traen `character` en algunos
    // teclados; nada por debajo de 0x20 es texto.
    if (code < 0x20 || code == 0x7F) return false;
    // El espacio es la tecla de desplazar y de alternar en media pantalla del
    // ERP: no puede ser el principio de nada.
    if (character == ' ') return false;

    if (_isEditing()) return false;
    if (_isScannerArmed()) return false;
    return true;
  }

  /// `true` cuando el foco está dentro de un campo de texto.
  ///
  /// Mismo recorrido que hace `ScannerBridgeScope` por la misma razón: el nodo
  /// con el foco es el `Focus` que `EditableText` monta, así que hay que mirar
  /// también hacia arriba, y el contexto puede estar desactivado en medio de un
  /// rebuild.
  bool _isEditing() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null || !context.mounted) return false;
    try {
      if (context.widget is EditableText) return true;
      return context.findAncestorWidgetOfExactType<EditableText>() != null;
    } catch (_) {
      // Contexto desactivado: no se puede afirmar que no se está escribiendo.
      return true;
    }
  }

  bool _isScannerArmed() {
    try {
      return context.read<BarcodeScannerService>().isListening;
    } catch (_) {
      return false;
    }
  }

  void _open() {
    GlobalSearchOverlay.open(context, sharedText: _buffer);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
