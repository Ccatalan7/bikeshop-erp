import 'package:flutter/foundation.dart';

/// Si la app se está usando con mouse y teclado: macOS, Windows y Linux.
///
/// Decide dónde se puede marcar texto con el mouse (`CopyableTextScope`) y
/// dónde las flechas desplazan lo que está bajo el cursor
/// (`KeyboardScrollScope`).
///
/// - El teléfono y la tableta quedan fuera: ahí marcar texto empieza con una
///   pulsación larga, que compite con reordenar y con los menús de las filas.
/// - La web también, por ahora: ahí cada zona de selección monta un elemento
///   HTML para el menú del navegador (`PlatformSelectableRegionContextMenu`), y
///   no se ha medido cuánto pesa con una zona por página y por diálogo.
bool get usesDesktopPointerAndKeyboard {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux =>
      true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia =>
      false,
  };
}
