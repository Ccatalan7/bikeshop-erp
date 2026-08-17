/// Gramática visual del Asistente de compras.
///
/// Todo valor de este archivo está **leído** de la página fuente del prototipo
/// —`Compras · Asistente inteligente navegable.dc.html` del proyecto Design
/// `ERP Bikeshop UI Mockups`— o de `handoff-t23/spec.json`. Ninguno se estimó
/// mirando un PNG, que es exactamente lo que produjo la versión anterior del
/// módulo: las tablas de medidas coincidían y la pantalla no se parecía.
///
/// La división que gobierna este archivo, y que el dueño fijó el 2026-08-17:
/// **el aspecto se copia exacto; el contenido, las palabras y los controles son
/// nuestros.** Por eso acá vive el continente —panel, columna, escala— y nunca
/// un texto de la interfaz.
library;

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';

/// Los nombres del prototipo, resueltos contra los roles montados del tema.
///
/// El prototipo habla en `--surface`/`--border`/`--ink`; el ERP habla en
/// `ColorScheme` y `VinabikeThemeRoles`. Esta clase es el único lugar donde se
/// traducen: un widget del módulo nunca vuelve a nombrar un rol del tema, y
/// nunca escribe un hex —el contrato de paletas lo trata como defecto.
@immutable
class PurchaseTokens {
  const PurchaseTokens._({
    required this.canvas,
    required this.surface,
    required this.sunken,
    required this.selected,
    required this.hair,
    required this.border,
    required this.borderStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.inkDisabled,
    required this.act,
    required this.actSoft,
    required this.actBorder,
    required this.onAct,
    required this.focusBorder,
    required this.shadow,
  });

  factory PurchaseTokens.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    return PurchaseTokens._(
      // El contrato de paletas es explícito: `scaffoldBackgroundColor` **es**
      // el rol canvas.
      canvas: theme.scaffoldBackgroundColor,
      surface: scheme.surface,
      // «La divulgación usa la capa hundida» — regla 5 del contrato.
      sunken: scheme.surfaceContainerLow,
      selected: roles.selectionContainer,
      hair: roles.hairline,
      border: scheme.outlineVariant,
      borderStrong: scheme.outline,
      ink: scheme.onSurface,
      inkMuted: scheme.onSurfaceVariant,
      inkFaint: roles.faintForeground,
      inkDisabled: roles.disabledForeground,
      // `primary` es el acento de acción del preset, no un azul fijo.
      act: scheme.primary,
      actSoft: roles.selectionContainer,
      actBorder: roles.accentBorder,
      onAct: scheme.onPrimary,
      focusBorder: roles.focusRing,
      shadow: roles.shadow,
    );
  }

  final Color canvas;
  final Color surface;
  final Color sunken;
  final Color selected;

  /// Separador **dentro** de un panel. No dibuja el contorno de otra caja.
  final Color hair;

  /// Contorno de un panel.
  final Color border;

  /// Contorno de un control editable dentro de un panel: el prototipo usa un
  /// borde más fuerte adentro que afuera, y esa caja-dentro-de-caja es la mitad
  /// de lo que hace que el bloque se lea como un objeto.
  final Color borderStrong;

  final Color ink;

  /// Obligatorio para todo caveat que cambie la decisión (`spec.json`).
  final Color inkMuted;

  /// Prescindible: etiquetas de columna, unidades, atajos.
  final Color inkFaint;

  final Color inkDisabled;
  final Color act;
  final Color actSoft;
  final Color actBorder;
  final Color onAct;
  final Color focusBorder;
  final Color shadow;
}

/// Geometría congelada del prototipo. Referencia de diseño, no decisión local.
abstract final class PurchaseMetrics {
  /// Escenario: `padding:14px` y columna `max-width:780px; margin:0 auto`.
  ///
  /// El `margin:0 auto` es la mitad olvidada: sin él la columna queda pegada a
  /// la izquierda y la pantalla completa cambia de carácter.
  static const double stagePadding = 14;
  static const double columnMax = 780;

  /// Columna ancha de Stock interno (`frames[single-stock].geometry`).
  static const double wideColumnMax = 840;

  /// `gap:11px` entre bloques del escenario.
  static const double stageGap = 11;

  /// Panel: `border-radius:10px`, `padding:12px 13px`.
  static const double panelRadius = 10;
  static const EdgeInsets panelPadding = EdgeInsets.fromLTRB(13, 12, 13, 12);

  /// Control editable dentro del panel: radio 8, `padding:10px 11px`,
  /// `min-height:60px`.
  static const double fieldRadius = 8;
  static const EdgeInsets fieldPadding = EdgeInsets.fromLTRB(11, 10, 11, 10);
  static const double fieldMinHeight = 60;

  /// Fila de acciones dentro del panel: `margin-top:9px; gap:12px`.
  static const double actionsGap = 12;
  static const double actionsTopGap = 9;

  /// Radio del tile de imagen (`image_contract`).
  static const double mediaRadius = 8;

  /// Alturas de imagen por superficie (`image_contract.geometry`).
  static const double mediaTableRow = 38;
  static const double mediaPhoneCard = 46;
  static const double mediaStockPhoneCard = 64;
  static const double mediaInspector = 76;

  /// Banda de proceso (`geometry_shell.process_band`).
  static const double stepBadge = 20;
  static const double stepActiveUnderline = 2;

  /// Objetivo táctil mínimo en teléfono (`navigation_contract.focus`).
  static const double touchTarget = 44;

  /// Duración de `vbRise`, la entrada de los paneles anclados.
  static const Duration riseDuration = Duration(milliseconds: 140);
}

/// Escala tipográfica del handoff. Las familias vienen de `typography.families`.
abstract final class PurchaseType {
  static const String _display = 'Poppins';
  static const String _text = 'IBM Plex Sans';
  static const String _numeric = 'IBM Plex Mono';

  static const TextStyle panelTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 13.5,
  );

  static const TextStyle surfaceTitle = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  static const TextStyle sectionTitle = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
  );

  static const TextStyle rowTitle = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w600,
    fontSize: 12,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w400,
    fontSize: 11.5,
    height: 1.55,
  );

  static const TextStyle meta = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w400,
    fontSize: 10.5,
    height: 1.45,
  );

  /// Texto que se escribe: el campo del prototipo es 12,5, no el body de 11,5.
  static const TextStyle input = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    height: 1.55,
  );

  /// CTA textual dentro de un panel («Ejemplos» en el prototipo).
  static const TextStyle inlineAction = TextStyle(
    fontFamily: _text,
    fontWeight: FontWeight.w600,
    fontSize: 11,
  );

  /// Etiqueta de columna: mono 9, versalitas espaciadas.
  static const TextStyle label = TextStyle(
    fontFamily: _numeric,
    fontWeight: FontWeight.w600,
    fontSize: 9,
    letterSpacing: 0.7,
  );

  /// Pistas prescindibles, como el atajo de teclado.
  static const TextStyle hint = TextStyle(
    fontFamily: _numeric,
    fontWeight: FontWeight.w400,
    fontSize: 10,
  );

  /// Números comparables. Siempre mono, para que la columna alinee.
  static const TextStyle metricLarge = TextStyle(
    fontFamily: _numeric,
    fontWeight: FontWeight.w700,
    fontSize: 21,
  );

  static const TextStyle metricMedium = TextStyle(
    fontFamily: _numeric,
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static const TextStyle metricSmall = TextStyle(
    fontFamily: _numeric,
    fontWeight: FontWeight.w700,
    fontSize: 13,
  );
}

/// Por qué un panel se destaca. Cambia el borde, nunca el relleno.
enum PurchasePanelAccent {
  /// Contorno normal.
  plain,

  /// Elegido por el operador, o dicho por él.
  selected,

  /// Advierte sin bloquear.
  warning,
}

/// El panel del módulo: superficie, borde de 1 px y radio 10.
///
/// Es el objeto que faltaba. La versión anterior dejaba título, subtítulo,
/// campo y botones sueltos sobre el fondo, y por eso se leía como un formulario
/// tirado encima en vez de un bloque.
///
/// `padded` es para contenido libre y aplica `padding:12px 13px`; en `false` el
/// panel recorta a su radio y el contenido pone su propio espaciado — la
/// variante `overflow:hidden` que el prototipo usa para listas y tablas.
class PurchasePanel extends StatelessWidget {
  const PurchasePanel({
    super.key,
    required this.child,
    this.padded = true,
    this.accent = PurchasePanelAccent.plain,
    this.raised = false,
  });

  final Widget child;
  final bool padded;
  final PurchasePanelAccent accent;

  /// Anclado sobre el contenido (popover, menú). Nunca lleva velo detrás: el
  /// módulo prohíbe el scrim.
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final borderColor = switch (accent) {
      PurchasePanelAccent.plain => tokens.border,
      PurchasePanelAccent.selected => tokens.actBorder,
      PurchasePanelAccent.warning => roles.warning.border,
    };
    final radius = BorderRadius.circular(PurchaseMetrics.panelRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: borderColor),
        borderRadius: radius,
        boxShadow: raised
            ? [
                BoxShadow(
                  color: tokens.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: padded
          ? Padding(padding: PurchaseMetrics.panelPadding, child: child)
          : ClipRRect(
              // El radio se recorta sólo acá: una lista a sangre dentro del
              // panel se saldría de la esquina redondeada.
              borderRadius: radius,
              child: child,
            ),
    );
  }
}

/// Acción principal de una superficie. Una por pantalla.
///
/// `height:34px; padding:0 15px; border-radius:8px; font:600 12px`, y
/// deshabilitado toma el contenedor neutro con tinta deshabilitada — el
/// prototipo apaga «Analizar» mientras el campo está vacío en vez de dejarlo
/// encendido sobre nada.
class PurchasePrimaryButton extends StatelessWidget {
  const PurchasePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.minimumWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? minimumWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final enabled = onPressed != null;
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: enabled ? tokens.act : roles.neutral.container,
          foregroundColor: enabled ? tokens.onAct : tokens.inkDisabled,
          disabledBackgroundColor: roles.neutral.container,
          disabledForegroundColor: tokens.inkDisabled,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          minimumSize: Size(minimumWidth ?? 0, 34),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PurchaseMetrics.fieldRadius),
          ),
          textStyle: PurchaseType.inlineAction.copyWith(fontSize: 12),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Acción secundaria dentro de un panel: **texto**, no un botón con caja.
///
/// En el prototipo «Ejemplos» es `font:600 11px` del color de acción y nada
/// más. Envolverlo en un `TextButton` con su relleno y su altura de 40 lo
/// convierte en otro objeto y desequilibra la fila.
class PurchaseInlineAction extends StatelessWidget {
  const PurchaseInlineAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        // Área táctil sin engordar la fila: el texto conserva su tamaño.
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: PurchaseType.inlineAction.copyWith(
            color: onPressed == null ? tokens.inkDisabled : tokens.act,
          ),
        ),
      ),
    );
  }
}

/// El escenario: columna centrada con el ancho del diseño y su separación.
///
/// `wide` cambia a la columna de 840 que usa Stock interno.
class PurchaseStage extends StatelessWidget {
  const PurchaseStage({
    super.key,
    required this.children,
    this.wide = false,
  });

  final List<Widget> children;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PurchaseMetrics.stagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide
                ? PurchaseMetrics.wideColumnMax
                : PurchaseMetrics.columnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: PurchaseMetrics.stageGap),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
