import 'package:flutter/material.dart';

import '../../modules/website/theme/website_resolved_theme.dart';
import '../models/customer_portal_presentation.dart';
import '../theme/public_store_surface_theme.dart';

/// Lenguaje visual del portal de clientes (`/cuenta`), dirección «Sendero».
///
/// El sitio público queda a criterio del agente
/// (`.github/GUI_DESIGN_PRINCIPLES.md` «El sitio público no pasa por Design»),
/// pero la marca es del editor: todo color, fuente y foto sale del tema del
/// sitio ([PublicStoreSurfaceTheme], [WebsiteResolvedTheme]), así el portal
/// sigue lo que el dueño elige y sirve igual a otra tienda.
///
/// Salió de revisar sitios de marcas de MTB (Commencal, Amflow, Saracen, Fox
/// Racing, RockShox, YT; 2026-09-26) y de lo que repiten: esquinas rectas,
/// títulos en la fuente de títulos y en mayúsculas, etiquetas chicas con
/// espacio entre letras, un solo color para actuar (el primario del sitio),
/// fotos a sangre con el texto abajo a la izquierda, el producto sobre un
/// fondo gris claro, y nada de sombras: líneas finas y bandas. El acento del
/// sitio marca sólo lo que espera al cliente.
@immutable
class PortalStyle {
  const PortalStyle._(this.surfaceTheme, this.site);

  factory PortalStyle.of(BuildContext context) => PortalStyle._(
        PublicStoreSurfaceTheme.of(context),
        WebsiteResolvedTheme.of(context),
      );

  final PublicStoreSurfaceTheme surfaceTheme;
  final WebsiteResolvedTheme site;

  /// Ancho del contenido; los márgenes van por fuera.
  static const double contentMaxWidth = 1120;

  /// Desde aquí las pestañas caben enteras y «Cerrar sesión» va a la derecha.
  static const double wideBreakpoint = 900;

  /// Bajo este ancho las filas se apilan y las fichas van de a una.
  static const double compactBreakpoint = 560;

  /// Alto de todo botón del portal.
  static const double buttonHeight = 48;

  /// Esquinas rectas en todo el portal.
  static const BorderRadius radius = BorderRadius.zero;
  static const OutlinedBorder shape = RoundedRectangleBorder();

  static double gutter(double width) => width < compactBreakpoint ? 16 : 32;

  // ---------------------------------------------------------------- colores

  /// Fondo de la página.
  Color get page => surfaceTheme.surface;

  /// Fondo gris claro donde se apoyan productos, bicis y avisos.
  Color get well => surfaceTheme.raisedSurface;
  Color get line => surfaceTheme.line;

  /// Texto principal, opaco: también se usa como fondo de las bandas y de
  /// las etiquetas oscuras.
  Color get ink => Color.alphaBlend(surfaceTheme.textPrimary, page);
  Color get inkSecondary => Color.alphaBlend(surfaceTheme.textSecondary, page);
  Color get inkMuted => Color.alphaBlend(surfaceTheme.textMuted, page);

  /// Banda oscura (el aviso de arriba, la franja sin foto).
  Color get band => ink;
  Color get onBand => page;

  /// El color de las acciones: el primario del sitio.
  Color get action => surfaceTheme.primary;
  Color get onAction => surfaceTheme.onPrimary;

  /// Lo que espera al cliente: el acento del sitio.
  Color get attention => surfaceTheme.colors.secondary;
  Color get onAttention => surfaceTheme.colors.onSecondary;

  Color get success => surfaceTheme.success;
  Color get onSuccess => surfaceTheme.onSuccess;
  Color get danger => surfaceTheme.error;
  Color get onDanger => surfaceTheme.onError;

  /// Compatibilidad: controles de formulario (casillas) usan el de acción.
  Color get accent => action;
  Color get onAccent => onAction;
  Color get panel => page;
  Color get canvas => page;

  // ------------------------------------------------------------ tipografía

  TextTheme get _text => surfaceTheme.text;

  /// Fuente de títulos del sitio, en mayúsculas desde quien la usa.
  TextStyle heading(
    double size, {
    FontWeight weight = FontWeight.w600,
    double spacing = 1,
    double height = 1.05,
    Color? color,
  }) =>
      (_text.titleLarge ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: spacing,
        height: height,
        color: color ?? ink,
      );

  TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.45,
    Color? color,
  }) =>
      (_text.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? ink,
      );

  /// «HOLA, ANDRÉS» en la banda del resumen.
  TextStyle display({required bool compact}) =>
      heading(compact ? 44 : 72, height: 0.95);

  /// Título de una página en su banda, o de una ficha.
  TextStyle pageTitle({required bool compact}) =>
      heading(compact ? 34 : 48, height: 0.95);

  TextStyle sectionTitle({required bool compact}) =>
      heading(compact ? 24 : 28, height: 1);

  /// El título de una ficha grande («TREK MARLIN 7»).
  TextStyle featureTitle({required bool compact}) =>
      heading(compact ? 28 : 34, spacing: 0.5);

  /// El nombre en una tarjeta de bici.
  TextStyle itemTitle({required bool compact}) =>
      heading(compact ? 20 : 24, spacing: 0.5, height: 1.1);

  /// Rótulo chico sobre un título: «MI CUENTA», «TALLER VIÑABIKE».
  TextStyle get eyebrow => heading(13, weight: FontWeight.w500, spacing: 2.6);

  /// Botones, pestañas y enlaces.
  TextStyle get label =>
      heading(14, weight: FontWeight.w500, spacing: 1.6, height: 1.2);

  TextStyle get tagText =>
      heading(12, weight: FontWeight.w500, spacing: 1.4, height: 1.1);

  /// Rótulos de datos y encabezados de tabla.
  TextStyle get micro => heading(
        11,
        weight: FontWeight.w500,
        spacing: 1.3,
        height: 1.25,
        color: inkSecondary,
      );

  /// Montos: cifras del mismo ancho, para leerse en columna.
  TextStyle get figure => heading(20, spacing: 0.5).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get figureSmall => figure.copyWith(fontSize: 17);

  TextStyle get pageSubtitle => body(16, color: inkSecondary);

  TextStyle get rowTitle => body(16, weight: FontWeight.w600, height: 1.3);

  TextStyle get rowMeta => body(14, color: inkSecondary, height: 1.4);

  TextStyle get sectionLabel => micro;

  TextStyle get link => label;

  /// El siguiente paso, cuando hay que decirlo en palabras.
  TextStyle get nextStep => rowMeta.copyWith(
        color: ink,
        fontWeight: FontWeight.w600,
      );

  /// Fondo y texto suaves de un estado, para avisos en línea.
  ({Color background, Color foreground}) tone(PortalTone tone) {
    final base = switch (tone) {
      PortalTone.success => success,
      PortalTone.warning => attention,
      PortalTone.danger => danger,
      PortalTone.info => ink,
      PortalTone.neutral => inkSecondary,
    };
    final background = tone == PortalTone.neutral
        ? well
        : Color.alphaBlend(base.withValues(alpha: 0.12), page);
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

  /// Campos de formulario rectos, con línea fina y el color de acción al
  /// escribir. Se aplica con `Theme(data: style.formTheme(Theme.of(c)))`.
  ThemeData formTheme(ThemeData base) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: page,
        border: border(line),
        enabledBorder: border(line),
        disabledBorder: border(line),
        focusedBorder: border(action, 2),
        errorBorder: border(danger),
        focusedErrorBorder: border(danger, 2),
        labelStyle: body(15, color: inkSecondary),
        floatingLabelStyle: body(15, color: ink),
        hintStyle: body(15, color: inkMuted),
      ),
      checkboxTheme: base.checkboxTheme.copyWith(
        shape: const RoundedRectangleBorder(),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? action : null,
        ),
        checkColor: WidgetStatePropertyAll(onAction),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          shape: shape,
          textStyle: label,
          minimumSize: const Size(0, buttonHeight),
        ),
      ),
    );
  }
}

// ================================================================== botones

enum PortalButtonKind { primary, secondary, onPhoto, ghost, danger }

/// Botón del portal: recto, 48 de alto, rótulo en mayúsculas espaciadas. Uno
/// relleno por ficha o pantalla, para lo que el cliente vino a hacer.
ButtonStyle portalButtonStyle(
  BuildContext context, [
  PortalButtonKind kind = PortalButtonKind.primary,
]) {
  final style = PortalStyle.of(context);
  final (background, foreground, border) = switch (kind) {
    PortalButtonKind.primary => (style.action, style.onAction, style.action),
    PortalButtonKind.secondary => (Colors.transparent, style.ink, style.ink),
    PortalButtonKind.onPhoto => (
        Colors.white,
        const Color(0xFF111111),
        Colors.white
      ),
    PortalButtonKind.ghost => (Colors.transparent, Colors.white, Colors.white),
    PortalButtonKind.danger => (style.danger, style.onDanger, style.danger),
  };
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? (background == Colors.transparent ? Colors.transparent : style.line)
          : background,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? style.inkMuted : foreground,
    ),
    overlayColor: WidgetStatePropertyAll(foreground.withValues(alpha: 0.1)),
    side: WidgetStateProperty.resolveWith(
      (states) => BorderSide(
        color: states.contains(WidgetState.disabled) ? style.line : border,
      ),
    ),
    shape: const WidgetStatePropertyAll(PortalStyle.shape),
    minimumSize: const WidgetStatePropertyAll(
      Size(0, PortalStyle.buttonHeight),
    ),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 24),
    ),
    elevation: const WidgetStatePropertyAll(0),
    textStyle: WidgetStatePropertyAll(style.label),
  );
}

/// El botón principal (relleno en el color de acción).
ButtonStyle portalPrimaryButton(BuildContext context) =>
    portalButtonStyle(context);

/// El secundario (contorno en el color de texto).
ButtonStyle portalSecondaryButton(BuildContext context) =>
    portalButtonStyle(context, PortalButtonKind.secondary);

class PortalButton extends StatelessWidget {
  const PortalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = PortalButtonKind.primary,
    this.arrow = false,
    this.icon,
    this.expand = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final PortalButtonKind kind;

  /// Flecha al final: el botón lleva a otra parte.
  final bool arrow;
  final IconData? icon;
  final bool expand;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      style: portalButtonStyle(context, kind),
      onPressed: busy ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ] else if (icon != null) ...[
            Icon(icon, size: 18),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              semanticsLabel: label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (arrow) ...[
            const SizedBox(width: 10),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ],
      ),
    );
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

/// Enlace de acción: rótulo en mayúsculas subrayado, con flecha.
class PortalLink extends StatelessWidget {
  const PortalLink({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.arrow = true,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final foreground = color ?? style.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: foreground)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      style: style.label.copyWith(
                        color: foreground,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (arrow) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward, size: 16, color: foreground),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================ etiquetas

/// Qué dice el color de una etiqueta: quién tiene que moverse.
enum PortalTagKind {
  /// Espera al cliente (el acento del sitio).
  attention,

  /// Lista, a favor del cliente (retirar).
  success,

  /// Algo salió mal y el cliente puede hacer algo.
  danger,

  /// En curso, del lado de la tienda; también el tipo de una bici.
  ink,

  /// Terminado.
  outline,

  /// Cancelado o archivado.
  quiet,
}

/// La etiqueta de un estado según quién tiene que moverse: si espera al
/// cliente, si sigue en curso o si ya terminó.
PortalTagKind portalStatusTagKind(
  PortalTone tone, {
  required bool needsCustomer,
  required bool active,
}) {
  if (needsCustomer) {
    return switch (tone) {
      PortalTone.success => PortalTagKind.success,
      PortalTone.danger => PortalTagKind.danger,
      _ => PortalTagKind.attention,
    };
  }
  if (active) return PortalTagKind.ink;
  return tone == PortalTone.neutral
      ? PortalTagKind.quiet
      : PortalTagKind.outline;
}

class PortalTag extends StatelessWidget {
  const PortalTag({
    super.key,
    required this.label,
    this.kind = PortalTagKind.ink,
  });

  final String label;
  final PortalTagKind kind;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final (background, foreground, border) = switch (kind) {
      PortalTagKind.attention => (
          style.attention,
          style.onAttention,
          style.attention
        ),
      PortalTagKind.success => (style.success, style.onSuccess, style.success),
      PortalTagKind.danger => (style.danger, style.onDanger, style.danger),
      PortalTagKind.ink => (style.ink, style.onBand, style.ink),
      PortalTagKind.outline => (Colors.transparent, style.ink, style.ink),
      PortalTagKind.quiet => (
          Colors.transparent,
          style.inkSecondary,
          style.line
        ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label.toUpperCase(),
          semanticsLabel: label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.tagText.copyWith(color: foreground),
        ),
      ),
    );
  }
}

/// El estado de un pedido, un trabajo o una conversación.
class PortalStatusTag extends StatelessWidget {
  const PortalStatusTag({
    super.key,
    required this.label,
    required this.tone,
    this.needsCustomer = false,
    this.active = true,
  });

  final String label;
  final PortalTone tone;
  final bool needsCustomer;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return PortalTag(
      label: label,
      kind: portalStatusTagKind(
        tone,
        needsCustomer: needsCustomer,
        active: active,
      ),
    );
  }
}

/// La cantidad junto al título de una sección: un cuadro en el acento.
class PortalCount extends StatelessWidget {
  const PortalCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      child: ColoredBox(
        color: style.attention,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '$count',
              style: style.heading(14, spacing: 0, color: style.onAttention),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ secciones

/// Título de sección: una raya corta en el color de acción, el título en
/// mayúsculas, la cantidad si importa y la acción a la derecha.
class PortalSection extends StatelessWidget {
  const PortalSection({
    super.key,
    required this.label,
    required this.child,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final Widget child;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PortalSectionHeader(
          label: label,
          count: count,
          actionLabel: actionLabel,
          onAction: onAction,
        ),
        const SizedBox(height: 24),
        child,
      ],
    );
  }
}

class PortalSectionHeader extends StatelessWidget {
  const PortalSectionHeader({
    super.key,
    required this.label,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < PortalStyle.compactBreakpoint;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 36, height: 3, color: style.action),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      label.toUpperCase(),
                      semanticsLabel: label,
                      style: style.sectionTitle(compact: compact),
                    ),
                  ),
                  if (count != null && count! > 0) PortalCount(count: count!),
                ],
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(width: 16),
          PortalLink(label: actionLabel!, onTap: onAction!),
        ],
      ],
    );
  }
}

/// Una lista de filas: una línea fuerte arriba y una fina entre filas, sin
/// caja alrededor.
class PortalPanel extends StatelessWidget {
  const PortalPanel({super.key, required this.children, this.header});

  final List<Widget> children;

  /// Encabezados de columna de una tabla, sobre la línea fuerte.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: header,
          ),
        Divider(height: 1, thickness: 1, color: style.ink),
        for (final child in children) ...[
          child,
          Divider(height: 1, thickness: 1, color: style.line),
        ],
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
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
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  footer!,
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
          if (onTap != null && showChevron) ...[
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward, size: 18, color: style.ink),
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

/// Miniatura cuadrada sobre el gris de producto: la foto entera (sin
/// recortar), o un dibujo o ícono tranquilo.
class PortalThumb extends StatelessWidget {
  const PortalThumb({
    super.key,
    required this.fallbackIcon,
    this.imageUrl,
    this.size = 64,
    this.child,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final double size;

  /// Lo que va en vez de la foto (el dibujo de una bici).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final fallback = Center(
      child: child ??
          Icon(fallbackIcon, size: size * 0.38, color: style.inkSecondary),
    );
    final url = imageUrl?.trim() ?? '';
    return SizedBox.square(
      dimension: size,
      child: ColoredBox(
        color: style.well,
        child: url.isEmpty
            ? fallback
            : Padding(
                padding: EdgeInsets.all(size * 0.08),
                child: PortalProductImage(url: url, fallback: fallback),
              ),
      ),
    );
  }
}

/// La foto de un producto apoyada en el gris: el blanco de la foto se funde
/// con el fondo (multiplicar), como en los catálogos.
class PortalProductImage extends StatelessWidget {
  const PortalProductImage({
    super.key,
    required this.url,
    required this.fallback,
  });

  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.contain,
      color: PortalStyle.of(context).well,
      colorBlendMode: BlendMode.multiply,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// El gris de producto con lo que se muestra encima (una foto recortada, el
/// dibujo de una bici) y rótulos en las esquinas.
class PortalWell extends StatelessWidget {
  const PortalWell({
    super.key,
    required this.height,
    required this.child,
    this.topLeft,
    this.topRight,
  });

  final double height;
  final Widget child;
  final Widget? topLeft;
  final String? topRight;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return SizedBox(
      height: height,
      child: ColoredBox(
        color: style.well,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 44, 24, 16),
                child: Center(child: child),
              ),
            ),
            if (topLeft != null) Positioned(left: 16, top: 16, child: topLeft!),
            if (topRight != null)
              Positioned(
                right: 16,
                top: 20,
                child: Text(
                  topRight!,
                  style: style.heading(
                    12,
                    weight: FontWeight.w500,
                    spacing: 2,
                    color: style.inkSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Aviso en línea: una frase y su acción, sobre el gris.
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
    return ColoredBox(
      color: style.well,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: style.ink),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        message,
                        style: style.rowMeta.copyWith(color: style.ink),
                      ),
                    ),
                  ),
                ],
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

/// Filtro recto con su cantidad: «TODOS 12», «EN CURSO 2». El elegido va
/// relleno en el color de texto.
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
    final foreground = selected ? style.onBand : style.ink;
    return Semantics(
      selected: selected,
      button: true,
      label: [label, if (count != null) '$count'].join(', '),
      excludeSemantics: true,
      child: Material(
        color: selected ? style.band : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? style.band : style.line),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.label.copyWith(
                        color: foreground,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style: style.label.copyWith(
                        fontSize: 13,
                        color: foreground.withValues(alpha: 0.7),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se ve cuando una sección no tiene nada: una frase, por qué, y
/// adónde ir, sobre el gris. Sin ilustraciones ni íconos gigantes.
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
    return ColoredBox(
      color: style.well,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: style.rowTitle.copyWith(fontSize: 17)),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(message!, style: style.rowMeta),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Datos de una ficha: el rótulo arriba, chico y en mayúsculas, y el valor
/// debajo. Los que vienen vacíos no se muestran.
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
          Text(
            visible[i].$1.toUpperCase(),
            semanticsLabel: visible[i].$1,
            style: style.micro,
          ),
          const SizedBox(height: 4),
          Text(
            visible[i].$2,
            style: style.body(16, weight: FontWeight.w500, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// Los datos cortos de un pedido o un trabajo en una fila de columnas, entre
/// dos líneas finas: «PEDIDO EL · PRODUCTOS · TOTAL».
class PortalFactStrip extends StatelessWidget {
  const PortalFactStrip({super.key, required this.facts});

  final List<(String label, String value)> facts;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: style.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            for (final (label, value) in facts)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      semanticsLabel: label,
                      style: style.micro,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.body(15, weight: FontWeight.w600).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Los pasos del taller en cinco tramos rectos: los hechos en el color de
/// acción, el actual en el acento si espera al cliente, lo que falta en gris.
class PortalWorkshopProgress extends StatelessWidget {
  const PortalWorkshopProgress({
    super.key,
    required this.step,
    required this.needsCustomer,
    this.showLabels = true,
  });

  final int step;
  final bool needsCustomer;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final last = customerWorkshopSteps.length - 1;
    Color bar(int index) {
      if (index < step) return style.action;
      if (index > step) return style.line;
      if (index == last) return style.success;
      return needsCustomer ? style.attention : style.ink;
    }

    final current = step.clamp(0, last);
    return Semantics(
      label: 'Paso ${current + 1} de ${last + 1}: '
          '${customerWorkshopSteps[current]}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i <= last; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 6, color: bar(i)),
                      if (showLabels) ...[
                        const SizedBox(height: 8),
                        Text(
                          customerWorkshopSteps[i].toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: style.micro.copyWith(
                            color: i == step ? style.ink : style.inkSecondary,
                            fontWeight:
                                i == step ? FontWeight.w700 : FontWeight.w500,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (!showLabels) ...[
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                text: 'PASO ${current + 1} DE ${last + 1} · ',
                children: [
                  TextSpan(
                    text: customerWorkshopSteps[current].toUpperCase(),
                    style: TextStyle(
                      color: style.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              style: style.micro.copyWith(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

/// Cómo va una ficha grande: apilada (teléfono), de a dos con el mismo alto
/// que su vecina, o sola y acostada (la foto a la izquierda, el texto a la
/// derecha) cuando es la única de su sección en ancho.
enum PortalTileLayout { stacked, equalHeight, horizontal }

typedef PortalTileBuilder = Widget Function(PortalTileLayout layout);

/// Fichas grandes de a dos en ancho, del mismo alto por fila; de a una en
/// teléfono; sola y acostada si es la única. Las fichas no llevan
/// `LayoutBuilder`: el alto se mide con `IntrinsicHeight`.
class PortalTileGrid extends StatelessWidget {
  const PortalTileGrid({super.key, required this.width, required this.tiles});

  final double width;
  final List<PortalTileBuilder> tiles;

  /// Desde este ancho las fichas van de a dos.
  static const double twoUpWidth = 760;

  @override
  Widget build(BuildContext context) {
    if (width < twoUpWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: 48),
            tiles[i](PortalTileLayout.stacked),
          ],
        ],
      );
    }
    if (tiles.length == 1) return tiles.first(PortalTileLayout.horizontal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 56),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i](PortalTileLayout.equalHeight)),
                const SizedBox(width: 40),
                Expanded(
                  child: i + 1 < tiles.length
                      ? tiles[i + 1](PortalTileLayout.equalHeight)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Junta la foto (o el dibujo) y el texto de una ficha grande según su
/// [PortalTileLayout].
Widget portalTileFrame({
  required Widget well,
  required Widget details,
  required PortalTileLayout layout,
  required bool compact,
}) {
  if (layout == PortalTileLayout.horizontal) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: well),
        const SizedBox(width: 48),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: details,
          ),
        ),
      ],
    );
  }
  final column = Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      well,
      SizedBox(height: compact ? 20 : 24),
      if (layout == PortalTileLayout.equalHeight)
        Expanded(child: details)
      else
        details,
    ],
  );
  return column;
}

// ================================================================== fichas

/// Abre la ficha de algo del portal (un trabajo, una bici): diálogo recto en
/// ancho, hoja desde abajo en teléfono. El título va en la fuente del sitio.
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
        Container(height: 4, color: style.action),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title.toUpperCase(),
                          semanticsLabel: title,
                          style: style.featureTitle(compact: true),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(subtitle, style: style.rowMeta),
                      ],
                      if (status != null) ...[
                        const SizedBox(height: 14),
                        status,
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: IconButton.styleFrom(shape: PortalStyle.shape),
                icon: Icon(Icons.close, color: style.ink),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Divider(height: 1, thickness: 1, color: style.ink),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: body,
          ),
        ),
        if (actions.isNotEmpty) ...[
          Divider(height: 1, thickness: 1, color: style.line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 12,
              runSpacing: 12,
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
      backgroundColor: style.page,
      shape: PortalStyle.shape,
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
      backgroundColor: style.page,
      surfaceTintColor: Colors.transparent,
      shape: PortalStyle.shape,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.84,
        ),
        child: content(dialogContext),
      ),
    ),
  );
}

/// Diálogo recto del portal (confirmar, formularios cortos), con el título en
/// la fuente del sitio y los campos del portal.
class PortalDialog extends StatelessWidget {
  const PortalDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.scrollable = false,
    this.width = 480,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final bool scrollable;
  final double width;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return Theme(
      data: style.formTheme(Theme.of(context)),
      child: AlertDialog(
        scrollable: scrollable,
        backgroundColor: style.page,
        surfaceTintColor: Colors.transparent,
        shape: PortalStyle.shape,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        titlePadding: EdgeInsets.zero,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: style.action),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Semantics(
                header: true,
                child: Text(
                  title.toUpperCase(),
                  semanticsLabel: title,
                  style: style.heading(24),
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(width: width, child: content),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: actions,
      ),
    );
  }
}

/// La franja de servicio al pie del resumen: tres cosas útiles, cada una con
/// su ícono, su título y adónde ir.
class PortalServiceBand extends StatelessWidget {
  const PortalServiceBand({super.key, required this.items});

  final List<PortalServiceItem> items;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return ColoredBox(
      color: style.well,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final gutter = PortalStyle.gutter(width);
          final columns = width >= 820;
          final tiles = [
            for (var i = 0; i < items.length; i++)
              _ServiceItem(item: items[i], stacked: !columns, first: i == 0),
          ];
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: PortalStyle.contentMaxWidth + gutter * 2,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  columns ? 52 : 12,
                  gutter,
                  columns ? 52 : 28,
                ),
                child: columns
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) const SizedBox(width: 56),
                            Expanded(child: tiles[i]),
                          ],
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: tiles,
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

@immutable
class PortalServiceItem {
  const PortalServiceItem({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onTap;
}

class _ServiceItem extends StatelessWidget {
  const _ServiceItem({
    required this.item,
    required this.stacked,
    required this.first,
  });

  final PortalServiceItem item;
  final bool stacked;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final title = Text(
      item.title.toUpperCase(),
      semanticsLabel: item.title,
      style: style.heading(stacked ? 16 : 18),
    );
    final icon = Icon(item.icon, size: stacked ? 24 : 28, color: style.ink);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stacked)
          Row(children: [
            icon,
            const SizedBox(width: 12),
            Expanded(child: title)
          ])
        else ...[
          icon,
          const SizedBox(height: 12),
          title,
        ],
        const SizedBox(height: 10),
        Text(item.message, style: style.body(15, color: style.inkSecondary)),
        const SizedBox(height: 4),
        PortalLink(label: item.actionLabel, onTap: item.onTap),
      ],
    );
    if (!stacked) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: style.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: content,
      ),
    );
  }
}
