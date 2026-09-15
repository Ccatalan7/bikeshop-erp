import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// **`A-02 · Icon button`, variante SOBRE SURFACE** — dueño único.
///
/// Leído de `GUÍA GENERAL Viñabike - Componentes` (proyecto
/// `ERP Bikeshop UI Mockups`, ficha `A-02`): **«SOBRE SURFACE — 28 / r6,
/// glifo 16»**, con sus cinco muestras «default · hover · focus · pressed ·
/// disabled». La variante sobre shell (32 / r7) vive en [VbShellIconButton];
/// ésta es la que va dentro de un panel, una hoja o un visor.
///
/// Las muestras de la ficha se atan a roles en vez de pegar el hex:
///
/// | estado   | ficha                                   | rol                                   |
/// |----------|-----------------------------------------|---------------------------------------|
/// | default  | glifo inkMuted                          | `onSurfaceVariant`                    |
/// | hover    | fondo surfaceSunken + borde hairline    | `surfaceContainerLow` + `hairline`    |
/// | focus    | borde accent + anillo 3 px al 12 %      | `primary` + `focusRing` (F-05)        |
/// | pressed  | fondo accent.soft, glifo accent oscuro  | `info.container` + `info.onContainer` |
/// | disabled | glifo apagado                           | `disabledForeground`                  |
///
/// Regla dura de la ficha: **«Siempre tooltip + semanticLabel; un icon button
/// sin label accesible no pasa el test»**, y **«Solo para acciones cuyo ícono
/// es universal (cerrar, más opciones, expandir, buscar). Todo lo demás lleva
/// texto.»** El movimiento entre estados es `F-05 · fast 120`.
class VbSurfaceIconButton extends StatefulWidget {
  const VbSurfaceIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });

  /// `A-02` sobre surface.
  static const double box = 28;
  static const double radius = 6;
  static const double glyph = 16;

  /// `F-05` · anillo de foco 3 px.
  static const double focusRingWidth = 3;

  /// `F-05` · «Con foco Campo rgba(22,104,189,.12)».
  static const double focusRingAlpha = 0.12;

  /// `F-05` · «fast 120 (hover, check)».
  static const Duration motionFast = Duration(milliseconds: 120);

  final IconData icon;

  /// Se usa como tooltip **y** como etiqueta accesible: la ficha exige las dos
  /// y una sola fuente evita que se separen.
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  State<VbSurfaceIconButton> createState() => _VbSurfaceIconButtonState();
}

class _VbSurfaceIconButtonState extends State<VbSurfaceIconButton> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final enabled = widget.onPressed != null;

    final Color glyphColor;
    Color? background;
    Color? border;
    if (!enabled) {
      glyphColor = roles.disabledForeground;
    } else if (_pressed) {
      glyphColor = roles.info.onContainer;
      background = roles.info.container;
    } else if (_hovered) {
      glyphColor = scheme.onSurface;
      background = scheme.surfaceContainerLow;
      border = roles.hairline;
    } else {
      glyphColor = scheme.onSurfaceVariant;
    }
    if (_focused && enabled) {
      border = scheme.primary;
    }

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        excludeSemantics: true,
        child: Material(
          key: widget.buttonKey,
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(VbSurfaceIconButton.radius),
            // Los estados los pinta el contenedor de abajo; el ink de Material
            // pondría un segundo relleno que la ficha no dibuja.
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            mouseCursor:
                enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: AnimatedContainer(
              duration: VbSurfaceIconButton.motionFast,
              width: VbSurfaceIconButton.box,
              height: VbSurfaceIconButton.box,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(VbSurfaceIconButton.radius),
                border: border == null ? null : Border.all(color: border),
                boxShadow: _focused && enabled
                    ? [
                        BoxShadow(
                          color: roles.focusRing.withValues(
                            alpha: VbSurfaceIconButton.focusRingAlpha,
                          ),
                          spreadRadius: VbSurfaceIconButton.focusRingWidth,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                size: VbSurfaceIconButton.glyph,
                color: glyphColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
