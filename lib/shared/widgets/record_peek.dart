import 'dart:math' as math;

import 'package:flutter/material.dart';

/// «Ver sin salir»: un registro que otra superficie nombra se lee encima de
/// ella, sin navegar. En un teléfono es una hoja que sube; en una ventana más
/// ancha, un panel que entra desde la derecha. Lo de abajo queda donde estaba
/// (el chat, la ficha del proveedor), y sólo el «Abrir …» de la vista sale a
/// la página del registro, cerrando esto primero.
///
/// El dueño, 2026-10-14, sobre la compra nombrada en el encabezado de un chat:
/// «should be accessible somewhere appropriate to access the preview of that
/// invoice without having to navigate away». Y el 2026-11-03, sobre los
/// movimientos de la ficha de un proveedor: «que uno pueda abrir esos
/// movimientos, sin navegar afuera».
///
/// [builder] recibe el contexto del host y la función que lo cierra.
Future<void> showRecordPeek(
  BuildContext context, {
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double panelWidth = 420,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  if (MediaQuery.sizeOf(context).width < 600) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        void close() => Navigator.of(sheetContext).pop();
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: builder(sheetContext, close),
        );
      },
    );
  }
  // `showGeneralDialog`, a diferencia de la hoja, no lleva los temas de quien
  // la abre: sin esto, un módulo con paleta propia leería la del raíz.
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context).context,
  );
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.12),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      void close() => Navigator.of(dialogContext).pop();
      final width = math.min(
        panelWidth,
        MediaQuery.sizeOf(dialogContext).width - 48,
      );
      return themes.wrap(
        Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: Material(
              elevation: 4,
              color: colorScheme.surface,
              child: SafeArea(
                left: false,
                child: Builder(
                  builder: (hostContext) => builder(hostContext, close),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, __, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: child,
    ),
  );
}
