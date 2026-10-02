import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';

/// Letra del módulo de bicicletas (rediseño aprobado por el dueño el
/// 2026-10-02): Oswald para el nombre de la bici y los títulos, Barlow para
/// leer. Las dos están empaquetadas en `assets/fonts`, así que se ven igual
/// sin red. Los colores salen siempre del tema.
abstract final class BikeModuleText {
  static const String display = 'Oswald';
  static const String body = 'Barlow';

  /// «Bicicletas», «X200».
  static TextStyle title(BuildContext context, {double size = 34}) => TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 1.08,
        letterSpacing: 0.2,
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// La marca sobre el modelo: «UPLAND».
  static TextStyle eyebrow(BuildContext context, {double size = 15}) =>
      TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w500,
        fontSize: size,
        letterSpacing: size * 0.14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  /// Montos grandes y el día de una visita.
  static TextStyle figure(BuildContext context, {double size = 22}) =>
      TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w500,
        fontSize: size,
        height: 1,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurface,
      );

  /// Etiquetas de columna y de dato: lo que se lee último.
  static TextStyle label(BuildContext context) => TextStyle(
        fontFamily: body,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.7,
        color: VinabikeThemeRoles.of(context).faintForeground,
      );

  /// N° de trabajo: cifras alineadas.
  static TextStyle code(BuildContext context, {Color? color}) => TextStyle(
        fontFamily: body,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      );
}

const _monthAbbr = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// «27 mar», o «27 mar 2025» si no es de este año.
String bikeShortDate(DateTime date, {required DateTime today}) {
  final local = date.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _monthAbbr[local.month - 1];
  return local.year == today.year ? '$day $month' : '$day $month ${local.year}';
}

/// «27 mar 2026».
String bikeFullDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')} '
      '${_monthAbbr[local.month - 1]} ${local.year}';
}

/// «mar 2026»: la cabecera de una visita.
/// Lo que pidió el cliente como una frase: el taller lo escribe en líneas,
/// a veces con «+» o «-» al inicio y con puntos repetidos.
String bikeRequestAsSentence(String raw) {
  final lines = raw
      .split(RegExp(r'\n+'))
      .map((line) => line.trim().replaceFirst(RegExp(r'^[+\-•*·]+\s*'), ''))
      .map((line) => line.replaceAll(RegExp(r'\.{2,}'), '.').trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final buffer = StringBuffer();
  for (final line in lines) {
    if (buffer.isNotEmpty) {
      final text = buffer.toString();
      buffer.write(RegExp(r'[.:;!?]$').hasMatch(text) ? ' ' : '. ');
    }
    buffer.write(line);
  }
  return buffer.toString();
}

String bikeMonthYear(DateTime date) {
  final local = date.toLocal();
  return '${_monthAbbr[local.month - 1]} ${local.year}';
}

/// Barlow para todo el subárbol, botones y campos incluidos.
class BikeModuleTheme extends StatelessWidget {
  const BikeModuleTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: BikeModuleText.body),
        primaryTextTheme:
            theme.primaryTextTheme.apply(fontFamily: BikeModuleText.body),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: BikeModuleText.body),
        child: child,
      ),
    );
  }
}

/// El color del estado del trabajo y su nombre: punto y texto.
class BikeJobStatusDot extends StatelessWidget {
  const BikeJobStatusDot({
    super.key,
    required this.label,
    required this.color,
    this.muted = false,
    this.fontSize = 13,
  });

  final String label;
  final Color color;

  /// Entregado o cancelado: ya no pide nada, se lee más bajo.
  final bool muted;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
              color: muted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
