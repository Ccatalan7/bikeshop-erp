import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// Aviso corto con forma de píldora: un estado que la persona tiene que ver
/// sin que le tape el trabajo (conexión, cambios sin guardar, borrador
/// recuperado).
///
/// Dos formas de tocarlo:
/// - [onTap]: la píldora entera es un botón, y [actionLabel] dice qué hace;
/// - [trailing]: botones propios («Deshacer», cerrar). Entonces la píldora no
///   es un botón y cada acción se toca por separado, para que un toque
///   distraído no deshaga nada.
class VbStatusPill extends StatelessWidget {
  const VbStatusPill({
    super.key,
    required this.tone,
    required this.title,
    this.icon,
    this.detail,
    this.actionLabel,
    this.onTap,
    this.busy = false,
    this.maxLines = 1,
    this.trailing = const [],
  });

  final VinabikeSemanticTone tone;
  final IconData? icon;
  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onTap;
  final bool busy;
  final int maxLines;
  final List<Widget> trailing;

  /// Lo que oye el lector de pantalla: las partes separadas por punto, sin
  /// duplicarlo cuando una ya termina en «…».
  static String spokenLabel(Iterable<String> parts) =>
      parts.fold<String>('', (said, part) {
        if (said.isEmpty) return part;
        final closed = said.endsWith('…') || said.endsWith('.');
        return '$said${closed ? ' ' : '. '}$part';
      });

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final text = Theme.of(context).textTheme;
    final wholePill = onTap != null && trailing.isEmpty;
    final label = spokenLabel([
      title,
      if (detail != null) detail!,
      if (wholePill && actionLabel != null) actionLabel!,
    ]);
    final message = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (detail != null)
            // El punto va pegado a la última palabra del título y a la
            // primera del detalle: si no cabe todo en una línea, baja junto
            // con ellas y nunca queda colgando al final ni abre la siguiente.
            TextSpan(
              text: '  ·  $detail',
              style: TextStyle(
                color: tone.onContainer.withValues(alpha: 0.78),
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: text.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.25,
        color: tone.onContainer,
      ),
    );
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 18,
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tone.accent,
                  ),
                )
              : Icon(icon, size: 18, color: tone.accent),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: wholePill
              ? message
              : Semantics(
                  liveRegion: true,
                  label: label,
                  child: ExcludeSemantics(child: message)),
        ),
        if (wholePill && actionLabel != null) ...[
          const SizedBox(width: 14),
          Text(
            actionLabel!,
            style: text.labelLarge?.copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: tone.accent,
              decoration: TextDecoration.underline,
              decorationColor: tone.accent.withValues(alpha: 0.5),
            ),
          ),
        ],
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: 8),
          ...trailing,
        ],
      ],
    );

    final surface = Material(
      color: tone.container,
      elevation: 0,
      shape: StadiumBorder(side: BorderSide(color: tone.border)),
      shadowColor: roles.shadow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: wholePill ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: roles.shadow.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                trailing.isEmpty ? 10 : 4,
                trailing.isEmpty ? 16 : 6,
                trailing.isEmpty ? 10 : 4,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );

    if (!wholePill) return surface;
    return Semantics(
      container: true,
      liveRegion: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: surface,
    );
  }
}

/// Botón de texto dentro de un [VbStatusPill], con el tono de la píldora y un
/// área de toque de 44.
class VbStatusPillButton extends StatelessWidget {
  const VbStatusPillButton({
    super.key,
    required this.tone,
    required this.label,
    required this.onPressed,
  });

  final VinabikeSemanticTone tone;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: tone.accent,
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      child: Text(label),
    );
  }
}

/// Cerrar un [VbStatusPill] sin hacer nada más.
class VbStatusPillClose extends StatelessWidget {
  const VbStatusPillClose({
    super.key,
    required this.tone,
    required this.onPressed,
    this.tooltip = 'Cerrar aviso',
  });

  final VinabikeSemanticTone tone;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 18,
      color: tone.onContainer.withValues(alpha: 0.8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: const Icon(Icons.close_rounded),
    );
  }
}
