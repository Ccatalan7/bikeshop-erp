import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../themes/vinabike_theme_roles.dart';

/// **F-03 · `VbMoneyText`** — cifras y dinero del kit compartido
/// (`GUÍA GENERAL Viñabike · Componentes`).
///
/// Dueño canónico de **cómo se escribe una cifra de dinero** en este ERP:
///
/// - **CLP sin decimales, punto de miles, símbolo pegado** — `$1.204.900`.
/// - **Negativos con el menos matemático `−`**, nunca paréntesis: `−$40.000`.
/// - **`$0` en `inkFaint` cuando es un cero real**; `—` cuando *no aplica*.
///   **Jamás vacío ni `null`** — una celda de dinero en blanco no dice «cero»,
///   dice «no sé», y en una nómina eso es otra cosa.
/// - **Mono tabular, alineado a la derecha**: las columnas de dinero sólo se
///   comparan de un vistazo si los dígitos ocupan lo mismo.
/// - **Hasta 9 dígitos sin romper la columna, y prohibido truncar dinero con
///   «…»**: media cifra es peor que ninguna.
///
/// **Sin overrides visuales, a propósito.** `universal-ui-component-system.md`
/// define los componentes canónicos como implementaciones «with stable behavior
/// and **controlled variants**», y prohíbe que acepten «arbitrary visual
/// overrides». Una versión anterior de esta clase aceptaba `size`, `weight`,
/// `textAlign` y `color`: con eso cada llamador podía inventar su propia manera
/// de escribir dinero, que es justo lo que F-03 viene a cerrar. El único tamaño
/// que la guía publica para dinero es **`700 14px`**, y es el que se usa.
///
/// **`inkFaint` es `VinabikeThemeRoles.neutral.accent`.** No es
/// `onSurfaceVariant`: `PayrollVisualTokens.inkFaint` resuelve
/// `roles?.neutral.accent ?? onSurfaceVariant.withValues(alpha: .78)`, y con el
/// tema de la app siempre hay roles. Llamarlo `onSurfaceVariant` habría
/// congelado una atribución falsa en el contrato.
class VbMoneyText extends StatelessWidget {
  const VbMoneyText(this.amount, {super.key});

  /// `null` significa **no aplica** y se dibuja `—`. Un cero real es `0` y se
  /// dibuja `$0`: son estados distintos y la guía los separa a propósito.
  final num? amount;

  /// CLP sin decimales, punto de miles, símbolo pegado, menos matemático.
  ///
  /// Expuesto porque el formato tiene que ser el mismo en un `Text`, en una
  /// etiqueta de semántica y en una prueba: tres implementaciones del mismo
  /// formato es como se cuelan dos maneras de escribir el mismo peso.
  static String formatClp(num amount) {
    final rounded = amount.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${rounded < 0 ? '−' : ''}\$$buffer';
  }

  bool get _isFaint => amount == null || amount!.round() == 0;

  String get _text => amount == null ? '—' : formatClp(amount!);

  @override
  Widget build(BuildContext context) {
    // El cero real y el «no aplica» van apagados: presentes, legibles, y sin
    // competir con las cifras que sí mueven dinero.
    final color = _isFaint
        ? VinabikeThemeRoles.of(context).neutral.accent
        : Theme.of(context).colorScheme.onSurface;

    return Text(
      _text,
      textAlign: TextAlign.right,
      // Prohibido truncar dinero: ni `…`, ni fuente encogida.
      softWrap: false,
      overflow: TextOverflow.visible,
      maxLines: 1,
      style: GoogleFonts.ibmPlexMono(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: color,
      ).copyWith(
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
