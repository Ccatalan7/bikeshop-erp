import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// Semantic tone of a [VbStatusBadge], resolved only through
/// [VinabikeThemeRoles].
///
/// `E-01` binds meaning to tone: *"success hecho · warning te toca · danger roto
/// o anulado · neutral sin carga · accent necesita criterio humano"*. The accent
/// case maps to the `info` role, which is the tone family the resolver owns.
enum VbStatusTone { neutral, info, success, warning, danger }

/// `E-01 VbStatusBadge` — informa, no ejecuta.
///
/// The guide is explicit on both halves of this contract:
///
/// * anatomy — *"Píldora r999, padding 3/9, texto 9.5/600 (8.5 en denso), fondo
///   `tone.soft` + borde `tone.border` + texto `tone.fg`. Sin ícono, sin sombra,
///   sin mayúsculas."*
/// * meaning — *"El color no es el único canal: el texto siempre nombra el
///   estado."*
///
/// It is deliberately **not** interactive: *"El status badge no tiene
/// interacción ni alto de control"*, and the guide names "el chip es el botón"
/// as the anti-pattern. A badge that needs an action is a badge plus a separate
/// `A-01` button.
///
/// [icon] exists because callers asked for it, but `E-01`'s anatomy is
/// icon-less: it defaults to null, is purely decorative and is hidden from the
/// semantics tree so the label stays the only channel.
class VbStatusBadge extends StatelessWidget {
  const VbStatusBadge({
    super.key,
    required this.label,
    this.tone = VbStatusTone.neutral,
    this.dense = false,
    this.icon,
    this.semanticLabel,
  }) : assert(label.length > 0, 'E-01: el texto siempre nombra el estado.');

  /// Rejects a label made only of whitespace.
  ///
  /// The check lives in `build` rather than in the constructor because
  /// `String.trim()` is not const-evaluable and the constructor must stay
  /// `const` for callers that rebuild the badge often.
  static bool _namesTheState(String label) => label.trim().isNotEmpty;

  /// The visible text. `E-01` requires it: colour is never the only channel.
  final String label;
  final VbStatusTone tone;

  /// `E-01`: "8.5px — mismo texto" for a narrow column.
  final bool dense;

  /// Decorative only. Excluded from semantics.
  final IconData? icon;

  /// Overrides the announced text when the visible label needs context.
  final String? semanticLabel;

  /// `E-01` · píldora r999.
  static const double radius = 999;

  /// `E-01` · padding 3/9.
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 9,
    vertical: 3,
  );

  /// `E-01` · texto 9.5/600, 8.5 en denso.
  static const double fontSize = 9.5;
  static const double denseFontSize = 8.5;
  static const FontWeight fontWeight = FontWeight.w600;

  /// `F-04` trazo · hairline 1.
  static const double borderWidth = 1;

  VinabikeSemanticTone _tone(VinabikeThemeRoles roles) => switch (tone) {
        VbStatusTone.neutral => roles.neutral,
        VbStatusTone.info => roles.info,
        VbStatusTone.success => roles.success,
        VbStatusTone.warning => roles.warning,
        VbStatusTone.danger => roles.danger,
      };

  @override
  Widget build(BuildContext context) {
    assert(
      _namesTheState(label),
      'E-01: el texto siempre nombra el estado; un label en blanco no lo hace.',
    );
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final resolved = _tone(roles);

    final textStyle =
        (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: dense ? denseFontSize : fontSize,
      fontWeight: fontWeight,
      // `E-01`: fondo tone.soft + borde tone.border + texto tone.fg.
      //
      // The surface is `container`, so the ink of that pair is `onContainer`.
      // `accent`/`onAccent` are the other pair of the same tone and pairing
      // `container` with `accent` is not a contrast the role model guarantees.
      color: resolved.onContainer,
      height: 1.2,
    );

    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resolved.container,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: resolved.border, width: borderWidth),
          // No shadow: `E-01` says "sin sombra".
        ),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: dense ? denseFontSize : fontSize,
                    color: resolved.onContainer,
                  ),
                ),
                // `F-04` escala · 4.
                const SizedBox(width: 4),
              ],
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle,
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
