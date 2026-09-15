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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_money_text.dart';

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

  /// Separación entre un rótulo y la línea que lo desarrolla.
  ///
  /// **Leído de Design, no del código de al lado.** `GUÍA GENERAL Viñabike -
  /// Componentes` (proyecto `a0fa3196-6315-4b96-bde7-7cc801e7a74e`), bloque
  /// **F-04 · Espacio, radio y trazo**, publica la escala
  /// `2 · 4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 24` y acota los impares: «7/9/11/13
  /// sólo para óptica interna de un control ya definido». El par concreto lo
  /// fija el componente **T-01 · T-02 · T-03** (`VbTable · VbColumnSpec ·
  /// VbRow · VbRowDisclosure`), cuya celda de dos líneas separa rótulo y valor
  /// con `margin-top:4px`.
  ///
  /// **Corrección 2026-08-25:** este token se había propuesto en 3 px «porque
  /// es lo que el módulo ya usa en 29 bloques». Eso es procedencia local, no de
  /// Design, y 3 no está en la escala F-04 ni entre sus impares permitidos. El
  /// valor correcto es 4. Los 29 usos previos quedan como están —migrarlos toca
  /// código ajeno a este cambio— y su desviación se reporta en el handoff.
  static const double labelGap = 4;

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

/// Escala tipográfica del handoff.
///
/// Las familias son las de `typography.families`: Poppins para identidad de
/// superficie, IBM Plex Sans para lectura operativa e IBM Plex Mono para
/// números comparables.
///
/// **Se resuelven con las APIs específicas de `google_fonts`, no por nombre.**
/// Antes esto declaraba `fontFamily: 'Poppins'` a secas, y el proyecto sólo
/// registra Oswald y Barlow en `pubspec.yaml`: la familia resolvía únicamente
/// si otra superficie —`vb_short_select`, los tokens de nómina— ya la había
/// cargado en esa sesión. El módulo se veía distinto según por dónde hubiera
/// pasado el operador antes. Con `GoogleFonts.poppins()` y compañía el pedido
/// deja de ser **dependiente del orden**: cada estilo carga la familia que
/// nombra, haya pasado o no el operador por otra pantalla. Es el mismo patrón
/// que `PayrollTokens`.
///
/// **Eso no es disponibilidad garantizada.** El proyecto no empaqueta Poppins
/// ni IBM Plex en `assets/fonts`, así que `google_fonts` las descarga la
/// primera vez y las cachea en el dispositivo: sin red y sin caché el sistema
/// cae a la fuente por defecto. Lo que este cambio arregla es la dependencia
/// del recorrido previo, no el acceso a la red. Si en algún momento hace falta
/// que el módulo se vea igual sin conexión, el arreglo es empaquetar las
/// familias, no tocar este archivo.
///
/// Nunca `GoogleFonts.getFont(nombre)`: la variante dinámica impide que el
/// tree-shaking descarte lo que no se usa y esconde la familia real detrás de
/// una cadena.
///
/// Los tamaños, pesos, alturas y espaciados son exactamente los del t23; lo
/// único que cambia es cómo se resuelve la familia. Los estilos dejan de ser
/// `const` porque la fuente se resuelve en tiempo de ejecución.
abstract final class PurchaseType {
  /// `module_title` del spec: la identidad del módulo en la banda de proceso.
  ///
  /// Faltaba, y su ausencia empujó «Asistente de compras» a [surfaceTitle],
  /// que el spec reserva para **Stock interno**. Leído de
  /// `handoff-t23/spec.json` → `typography.scale`, no de la pantalla.
  static final TextStyle moduleTitle = GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: 16,
    height: 1.2,
  );

  static final TextStyle panelTitle = GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: 13.5,
  );

  static final TextStyle surfaceTitle = GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: 14,
  );

  static final TextStyle sectionTitle = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w600,
    fontSize: 12.5,
  );

  static final TextStyle rowTitle = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w600,
    fontSize: 12,
  );

  /// `card_title` del spec: cards de candidato y de stock **en teléfono**.
  ///
  /// El spec lo declara como un rango, `600 13–13.5px IBM Plex Sans`; se toma
  /// el extremo alto, que es el que usa el prototipo en la card de stock.
  /// Faltaba, y su ausencia mandó los nombres de producto de esas cards a
  /// [rowTitle], que es 12 y pertenece a las filas de tabla y de plan.
  static final TextStyle cardTitle = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w600,
    fontSize: 13.5,
  );

  static final TextStyle body = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w400,
    fontSize: 11.5,
    height: 1.55,
  );

  static final TextStyle meta = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w400,
    fontSize: 10.5,
    height: 1.45,
  );

  /// `meta` con la familia **numérica**: cantidades, edades de evidencia,
  /// conteos de compra.
  ///
  /// No es un tamaño nuevo — son las métricas exactas de [meta] con
  /// `typography.families.numeric`, que el spec reserva para «números
  /// comparables, códigos, metadatos de conteo». Existe porque esos textos se
  /// venían escribiendo como `meta.copyWith(fontFamily: 'IBM Plex Mono')`, y
  /// pedir la familia por nombre es justo lo que este archivo prohíbe: el
  /// proyecto sólo registra Oswald y Barlow, así que el nombre resuelve nada
  /// más si otra pantalla ya cargó esa familia en la sesión.
  static final TextStyle metaNumeric = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w400,
    fontSize: 10.5,
    height: 1.45,
  );

  /// Texto que se escribe: el campo del prototipo es 12,5, no el body de 11,5.
  static final TextStyle input = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w400,
    fontSize: 12.5,
    height: 1.55,
  );

  /// CTA textual dentro de un panel («Ejemplos» en el prototipo).
  static final TextStyle inlineAction = GoogleFonts.ibmPlexSans(
    fontWeight: FontWeight.w600,
    fontSize: 11,
  );

  /// Etiqueta de columna: mono 9, versalitas espaciadas.
  static final TextStyle label = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w600,
    fontSize: 9,
    letterSpacing: 0.7,
  );

  /// Pistas prescindibles, como el atajo de teclado.
  static final TextStyle hint = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w400,
    fontSize: 10,
  );

  /// Números comparables. Siempre mono, para que la columna alinee.
  static final TextStyle metricLarge = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w700,
    fontSize: 21,
  );

  static final TextStyle metricMedium = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w700,
    fontSize: 15,
  );

  static final TextStyle metricSmall = GoogleFonts.ibmPlexMono(
    fontWeight: FontWeight.w700,
    fontSize: 13,
  );

  /// Cifras que se comparan en columna llevan ancho fijo de dígito.
  static const List<FontFeature> tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
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
/// **Con flete o sin flete.**
///
/// Lo que se negocia con el proveedor es la mercadería: el flete es un costo
/// nuestro y meterlo en el precio que se le compara —y en el que se le propone
/// en un pedido— infla la cifra con algo que él no cobra. Por eso el estado
/// normal es `sinFlete`.
///
/// El aterrizado sigue a un toque, porque para decidir a quién comprarle el
/// costo real puesto en bodega sí es el que manda.
enum PurchaseCostBasis {
  sinFlete,
  conFlete;

  bool get includesFreight => this == PurchaseCostBasis.conFlete;

  /// Lo que va bajo el número, en la fila.
  String get rowCaption => includesFreight ? 'c/u con flete' : 'c/u neto';

  String get label => includesFreight ? 'Con flete' : 'Sin flete';

  /// La salvedad al pie del bloque. Cambia con el eje: publicar «costos con
  /// flete prorrateado» mientras se muestra el neto sería describir otra tabla.
  String get footnote => includesFreight
      ? 'Costos con flete prorrateado.'
      : 'Costos de mercadería, sin el flete que pagamos aparte.';
}

/// El interruptor del eje de costo.
///
/// Dos palabras y sin icono: con icono, `SegmentedButton` no se estrecha —ni
/// con densidad compacta ni reduciendo el padding— y se come el ancho que la
/// cabecera necesita para su recuento.
class PurchaseCostBasisToggle extends StatelessWidget {
  const PurchaseCostBasisToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PurchaseCostBasis value;
  final ValueChanged<PurchaseCostBasis> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'COSTO',
          style: PurchaseType.label.copyWith(color: tokens.inkFaint),
        ),
        const SizedBox(width: 7),
        Container(
          decoration: BoxDecoration(
            color: tokens.sunken,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tokens.hair),
          ),
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in PurchaseCostBasis.values)
                _Option(
                  key: ValueKey('cost-basis-${option.name}'),
                  label: option.label,
                  selected: option == value,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Mostrar el costo unitario ${label.toLowerCase()}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: selected ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? tokens.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected ? tokens.borderStrong : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: PurchaseType.meta.copyWith(
                color: selected ? tokens.ink : tokens.inkMuted,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// **Cuánto ocupa una orden rotulada se mide; no se declara.**
///
/// Depende de la familia tipográfica y de la escala de texto del sistema: un
/// ancho «medido a ojo» en un Mac desborda en otro, y en la fuente de las
/// pruebas de widget desbordaba siempre. Se pasan **todos** los rótulos que el
/// control puede llegar a mostrar —«Confirmando…», «Ocultar»— para que la
/// columna no se corra cuando una fila cambia de estado.
double purchaseInlineActionWidth(BuildContext context, List<String> labels) {
  // El control hereda del `DefaultTextStyle` del host: medir el estilo suelto
  // usa otra familia que la que se dibuja y se queda corto por unos píxeles,
  // que es exactamente un desborde.
  final style = DefaultTextStyle.of(context).style.merge(
        PurchaseType.inlineAction,
      );
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    widest = math.max(widest, painter.width.ceilToDouble());
  }
  // Los 4 px son el padding horizontal del propio control.
  return widest + 4;
}

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

/// Cómo escriben plata el inspector de candidato, el plan y su cierre.
///
/// **Por qué existe.** El plan mostraba `CLP 17450` donde el resto del ERP dice
/// `$17.450`: la misma cifra con dos caras, y la del plan además sin separador
/// de miles, que es justo la que hay que leer rápido para decidir. La forma
/// canónica de peso chileno la fija `VbMoneyText.formatClp`; acá se reutiliza
/// esa función en vez de reimplementarla, para que un cambio de formato no se
/// bifurque.
///
/// **Alcance real, hoy.** Lo usan el inspector de candidato, la línea y el pie
/// del plan, y el cierre del plan. La canasta y los escenarios siguen
/// formateando por su dueño anterior —`VbMoneyText` más una rama local para la
/// moneda extranjera—: hoy producen las mismas formas visibles, pero son un
/// segundo dueño que puede divergir. No se movieron porque ninguna razón de
/// producto lo pidió; cuando alguien las toque, este es el sitio al que deben
/// entrar.
///
/// **Ninguna moneda se convierte.** No hay tipo de cambio autorizado en este
/// sistema, así que un monto en USD se muestra con su código y dos decimales y
/// se queda ahí. Escribirlo con `$` lo haría pasar por pesos, y sumarlo a un
/// total en CLP sería inventar una tasa.
abstract final class PurchaseMoney {
  /// `$17.450` en CLP; `USD 129.90` en cualquier otra moneda.
  ///
  /// `null` es «no hay cifra», y se dice con la raya —nunca con un cero, que
  /// se leería como gratis.
  static String format(double? amount, String currency) {
    if (amount == null) return '—';
    if (isClp(currency)) return VbMoneyText.formatClp(amount);
    return '${currency.trim().toUpperCase()} ${amount.toStringAsFixed(2)}';
  }

  /// El precio de una unidad: la misma cifra con el sufijo `c/u`.
  static String perUnit(double? amount, String currency) =>
      '${format(amount, currency)} c/u';

  static bool isClp(String currency) => currency.trim().toUpperCase() == 'CLP';
}
