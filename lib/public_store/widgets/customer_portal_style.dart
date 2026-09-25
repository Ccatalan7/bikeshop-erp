import 'package:flutter/material.dart';

import '../models/customer_portal_presentation.dart';
import '../theme/public_store_surface_theme.dart';

/// Lenguaje visual del portal de clientes (`/cuenta`).
///
/// El sitio público queda a criterio del agente
/// (`.github/GUI_DESIGN_PRINCIPLES.md` «El sitio público no pasa por Design»),
/// pero la marca es del editor: todo color sale de [PublicStoreSurfaceTheme],
/// así el portal sigue los colores y fuentes que el dueño elige y sirve igual a
/// otra tienda. El acento es el de comercio (el del botón de compra), no el
/// primario del sitio.
///
/// Criterio: una columna tranquila sobre el fondo del sitio, paneles blancos
/// con una línea fina sólo donde agrupan filas, estados en palabras con un
/// tono suave, cifras tabulares y el título de página en la fuente de títulos
/// del sitio, como la portada. Nada de baldosas de métricas ni saludos de
/// relleno.
@immutable
class PortalStyle {
  const PortalStyle._(this.surfaceTheme);

  factory PortalStyle.of(BuildContext context) =>
      PortalStyle._(PublicStoreSurfaceTheme.of(context));

  final PublicStoreSurfaceTheme surfaceTheme;

  static const double panelRadius = 14;
  static const double thumbRadius = 10;
  static const double navWidth = 232;
  static const double contentMaxWidth = 760;
  static const double wideBreakpoint = 900;

  Color get canvas => surfaceTheme.softSurface;
  Color get panel => surfaceTheme.surface;
  Color get line => surfaceTheme.line;
  Color get ink => surfaceTheme.textPrimary;
  Color get inkSecondary => surfaceTheme.textSecondary;
  Color get inkMuted => surfaceTheme.textMuted;
  Color get accent => surfaceTheme.commerceAccent;
  Color get onAccent => surfaceTheme.onCommerceAccent;
  Color get accentSoft =>
      Color.alphaBlend(accent.withValues(alpha: 0.08), panel);

  TextTheme get _text => surfaceTheme.text;

  /// Título de página, en la fuente de títulos del sitio.
  TextStyle pageTitle({required bool compact}) =>
      (_text.headlineSmall ?? const TextStyle()).copyWith(
        color: ink,
        fontSize: compact ? 26 : 32,
        height: 1.1,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      );

  TextStyle get pageSubtitle =>
      (_text.bodyMedium ?? const TextStyle()).copyWith(
        color: inkSecondary,
        height: 1.4,
      );

  /// Rótulo de sección: versalitas chicas, como un índice.
  TextStyle get sectionLabel =>
      (_text.labelMedium ?? const TextStyle()).copyWith(
        color: inkSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      );

  TextStyle get rowTitle => (_text.bodyMedium ?? const TextStyle()).copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
        height: 1.25,
      );

  TextStyle get rowMeta => (_text.bodySmall ?? const TextStyle()).copyWith(
        color: inkSecondary,
        height: 1.35,
      );

  /// Montos y números de pedido: cifras del mismo ancho, para que se lean en
  /// columna.
  TextStyle get figure => (_text.bodyMedium ?? const TextStyle()).copyWith(
        color: ink,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get link => (_text.labelLarge ?? const TextStyle()).copyWith(
        color: accent,
        fontWeight: FontWeight.w700,
      );

  /// El siguiente paso de un pedido o una bici, en el color de acción.
  TextStyle get nextStep => rowMeta.copyWith(
        color: accent,
        fontWeight: FontWeight.w600,
      );

  /// Botón secundario del portal (la acción del título de una página).
  ButtonStyle get secondaryButton => OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: line),
        backgroundColor: panel,
        textStyle: link,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  /// Fondo y texto de un estado. El texto se oscurece hasta leerse sobre su
  /// fondo (4,5:1).
  ({Color background, Color foreground}) tone(PortalTone tone) {
    final base = switch (tone) {
      PortalTone.success => surfaceTheme.success,
      PortalTone.warning => surfaceTheme.warning,
      PortalTone.danger => surfaceTheme.error,
      PortalTone.info => accent,
      PortalTone.neutral => inkSecondary,
    };
    final background = tone == PortalTone.neutral
        ? canvas
        : Color.alphaBlend(base.withValues(alpha: 0.11), panel);
    return (
      background: background,
      foreground: _readable(base, background),
    );
  }

  Color _readable(Color color, Color background) {
    if (_contrast(color, background) >= 4.5) return color;
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(color, ink, step / 20) ?? color;
      if (_contrast(candidate, background) >= 4.5) return candidate;
    }
    return ink;
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// Título de la página del portal, con su acción a la derecha.
class PortalPageHeader extends StatelessWidget {
  const PortalPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title.toUpperCase(),
            style: style.pageTitle(compact: compact),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: style.pageSubtitle),
        ],
      ],
    );
    if (action == null) return heading;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: 12,
      spacing: 16,
      children: [heading, action!],
    );
  }
}

/// Sección del portal: rótulo, acción opcional y contenido.
class PortalSection extends StatelessWidget {
  const PortalSection({
    super.key,
    required this.label,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: style.sectionLabel),
              ),
              if (actionLabel != null && onAction != null)
                PortalLink(label: actionLabel!, onTap: onAction!),
            ],
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// Grupo de filas: panel blanco con una línea fina entre filas.
class PortalPanel extends StatelessWidget {
  const PortalPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.panel,
        borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
        border: Border.all(color: style.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: style.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Fila del portal: imagen o ícono, título, detalle y lo que va a la derecha.
/// Toda la fila es el objetivo del toque cuando lleva a algún lado.
class PortalRow extends StatelessWidget {
  const PortalRow({
    super.key,
    required this.title,
    this.leading,
    this.meta,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
    this.footer,
    this.showChevron = true,
  });

  final Widget? leading;
  final String title;
  final String? meta;

  /// Debajo del detalle: el estado en teléfono, o el siguiente paso.
  final Widget? footer;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  /// Sin flecha cuando la fila ya lleva su propio menú a la derecha.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: style.rowTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta != null && meta!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta!,
                    style: style.rowMeta,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 8),
                  footer!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (onTap != null && showChevron) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 20, color: style.inkMuted),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// Estado en palabras sobre un fondo suave de su tono.
class PortalStatusPill extends StatelessWidget {
  const PortalStatusPill({super.key, required this.label, required this.tone});

  final String label;
  final PortalTone tone;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final colors = style.tone(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.rowMeta.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Miniatura cuadrada: la foto del producto o, sin foto, un ícono tranquilo.
class PortalThumb extends StatelessWidget {
  const PortalThumb({
    super.key,
    required this.fallbackIcon,
    this.imageUrl,
    this.size = 48,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final fallback = Center(
      child: Icon(fallbackIcon, size: size * 0.42, color: style.inkSecondary),
    );
    final url = imageUrl?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(PortalStyle.thumbRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: style.canvas,
          child: url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}

/// Enlace de acción en el color de comercio.
class PortalLink extends StatelessWidget {
  const PortalLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: style.accent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, 32),
        textStyle: style.link,
      ),
      child: Text(label),
    );
  }
}

/// Aviso en línea: una frase y su acción, sin caja pesada.
class PortalNotice extends StatelessWidget {
  const PortalNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = Icons.info_outline,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.accentSoft,
        borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: style.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: style.rowMeta.copyWith(color: style.ink),
              ),
            ),
            if (actionLabel != null && onAction != null)
              PortalLink(label: actionLabel!, onTap: onAction!),
          ],
        ),
      ),
    );
  }
}

/// En teléfono, el estado va bajo el detalle, con el siguiente paso al lado:
/// a la derecha no cabe sin cortar el nombre del producto.
class PortalStatusLine extends StatelessWidget {
  const PortalStatusLine({super.key, required this.pill, this.nextStep});

  final Widget pill;
  final String? nextStep;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        pill,
        if (nextStep != null) Text(nextStep!, style: style.nextStep),
      ],
    );
  }
}

/// En ancho, el estado y el monto en columnas fijas, para que las filas de
/// pedidos y de taller se lean alineadas aunque el taller no tenga monto.
class PortalTrailingColumns extends StatelessWidget {
  const PortalTrailingColumns({super.key, required this.pill, this.figure});

  final Widget pill;
  final String? figure;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 190),
          child: pill,
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 92,
          child: figure == null
              ? null
              : Text(figure!, textAlign: TextAlign.right, style: style.figure),
        ),
      ],
    );
  }
}

/// Filtro en forma de píldora, con su cantidad: «Todos 12», «En curso 2».
class PortalFilterChip extends StatelessWidget {
  const PortalFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final foreground = selected ? style.onAccent : style.ink;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? style.accent : style.panel,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? style.accent : style.line),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.rowMeta.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: style.rowMeta.copyWith(
                      color: foreground.withValues(alpha: 0.72),
                      fontFeatures: style.figure.fontFeatures,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se ve cuando una sección no tiene nada: una frase, por qué, y
/// adónde ir. Sin ilustraciones ni íconos gigantes.
class PortalEmptyState extends StatelessWidget {
  const PortalEmptyState({
    super.key,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return PortalPanel(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 8, actions.isEmpty ? 16 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: style.rowTitle),
              if (message != null) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(message!, style: style.rowMeta),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 4, runSpacing: 4, children: actions),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Datos de una ficha: el rótulo arriba, chico, y el valor debajo. Los que
/// vienen vacíos no se muestran.
class PortalFacts extends StatelessWidget {
  const PortalFacts({super.key, required this.facts});

  final List<(String label, String? value)> facts;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final visible = [
      for (final (label, value) in facts)
        if (value != null && value.trim().isNotEmpty) (label, value.trim()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) Divider(height: 25, thickness: 1, color: style.line),
          Text(visible[i].$1.toUpperCase(), style: style.sectionLabel),
          const SizedBox(height: 4),
          Text(visible[i].$2, style: style.rowTitle.copyWith(height: 1.4)),
        ],
      ],
    );
  }
}

/// Abre la ficha de algo del portal (un trabajo, una bici): diálogo en ancho,
/// hoja desde abajo en teléfono. El título va en la fuente del sitio, como el
/// de la página.
Future<void> showPortalDetail(
  BuildContext context, {
  required String title,
  String? subtitle,
  Widget? status,
  required Widget body,
  List<Widget> actions = const [],
}) {
  final style = PortalStyle.of(context);
  final compact = MediaQuery.sizeOf(context).width < 600;

  Widget content(BuildContext sheetContext) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title.toUpperCase(),
                          style: style
                              .pageTitle(compact: true)
                              .copyWith(fontSize: 22),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: style.rowMeta),
                      ],
                      if (status != null) ...[
                        const SizedBox(height: 12),
                        status,
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: Icon(Icons.close, color: style.inkSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Divider(height: 1, thickness: 1, color: style.line),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: body,
          ),
        ),
        if (actions.isNotEmpty) ...[
          Divider(height: 1, thickness: 1, color: style.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }

  if (compact) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: style.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PortalStyle.panelRadius),
        ),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (sheetContext) =>
          SafeArea(top: false, child: content(sheetContext)),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: style.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PortalStyle.panelRadius),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.84,
        ),
        child: content(dialogContext),
      ),
    ),
  );
}

/// Botón principal del portal: relleno en el color de comercio. Uno por
/// pantalla o por ficha, para lo que el cliente vino a hacer.
ButtonStyle portalPrimaryButton(BuildContext context) {
  final style = PortalStyle.of(context);
  return FilledButton.styleFrom(
    backgroundColor: style.accent,
    foregroundColor: style.onAccent,
    textStyle: style.link,
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );
}
