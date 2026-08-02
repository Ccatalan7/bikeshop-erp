import 'package:flutter/material.dart';

import 'workspace_shell_scope.dart';

/// **`A-02 · Icon button`, variante SOBRE SHELL** — dueño único.
///
/// Owner de puntero para el chrome desktop. Su host (`WorkspaceTabBar`) no se
/// monta bajo el breakpoint compacto de 900 px; por eso este widget no promete
/// el target táctil invisible de 48 px. Si otro host táctil necesita `A-02`,
/// debe usar el owner adaptativo correspondiente en vez de reutilizar éste.
///
/// Leído de `GUÍA GENERAL Viñabike - Componentes` (proyecto
/// `ERP Bikeshop UI Mockups`): «SOBRE SURFACE — 28 / r6, glifo 16» y
/// **«SOBRE SHELL — 32 / r7»**. Regla dura de la ficha: **«Siempre tooltip +
/// semanticLabel; un icon button sin label accesible no pasa el test»**.
///
/// Existe porque las acciones del chrome venían cada una con su propia caja
/// (32 / 28 / 26) y su propio glifo (16 / 18 / 20). Mezcladas en 200 px, eso es
/// lo que el dueño vio como un grupo comprimido y superpuesto. Los literales
/// viven **acá y en ningún otro lugar**.
class VbShellIconButton extends StatelessWidget {
  const VbShellIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  /// `A-02` sobre shell.
  static const double box = 32;
  static const double radius = 7;
  static const double glyph = 16;

  final IconData icon;

  /// Se usa como tooltip **y** como etiqueta accesible: la ficha exige las dos
  /// y una sola fuente evita que se separen.
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          key: buttonKey,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            mouseCursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            child: SizedBox(
              width: box,
              height: box,
              child: Icon(
                icon,
                size: glyph,
                color: enabled
                    ? chrome.foreground
                    : chrome.mutedForeground.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
