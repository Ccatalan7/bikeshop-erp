/// Cómo se le muestra al cliente una medida técnica de la ficha.
///
/// El motor guarda el diámetro de rueda como ISO 5775 (`bead_seat_diameter_mm`),
/// que es exacto pero no es lo que el cliente compra: él pide «aro 29»,
/// «700c», «aro 26». Estas funciones traducen sin perder el número.
///
/// Los nombres de cada dato y de cada opción son de la base
/// (`store_label`, `display_label`); aquí sólo se escribe el número a la
/// chilena (coma decimal, punto de miles), la unidad en palabras y las medidas
/// de rueda en pulgadas. Una talla comercial en pulgadas conserva su punto
/// («27.5"», «2.10"»): así viene impresa en el neumático y así se pide.
library;

import 'package:intl/intl.dart';

const Map<int, String> _wheelSizeByBsd = <int, String>{
  622: '29" / 700c',
  584: '27.5" / 650b',
  559: '26"',
  590: '26" x 1 3/8 (650A)',
  571: '26" (650C)',
  507: '24"',
  540: '24" x 1 3/8',
  520: '24" x 1 3/8 (S-5)',
  451: '20" x 1 3/8',
  406: '20"',
  355: '18"',
  349: '16" x 1 3/8',
  305: '16"',
  203: '12 1/2"',
  630: '27"',
  635: '28" x 1 1/2',
};

int? _bsd(String raw) =>
    int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '').trim());

/// Rodado comercial de un diámetro ISO 5775 (tabla de Sheldon Brown), sin el
/// número ISO, o null cuando el texto no es un diámetro conocido.
String? wheelSizeNameForBsd(String raw) {
  final bsd = _bsd(raw);
  return bsd == null ? null : _wheelSizeByBsd[bsd];
}

/// Rodado comercial con su ISO entre paréntesis, para un filtro donde el
/// valor va en una sola línea.
String? wheelSizeLabelForBsd(String raw) {
  final name = wheelSizeNameForBsd(raw);
  return name == null ? null : '$name (ISO ${_bsd(raw)})';
}

/// Un valor de la ficha pública: lo que se lee y, si hace falta, una precisión
/// para quien la busca («ISO 584» bajo «27.5" / 650b»).
class PublicSpecDisplayValue {
  const PublicSpecDisplayValue(this.text, {this.detail});

  final String text;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is PublicSpecDisplayValue &&
      other.text == text &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(text, detail);

  @override
  String toString() => detail == null ? text : '$text ($detail)';
}

/// Valor de una fila de la ficha técnica en palabras de tienda.
PublicSpecDisplayValue publicSpecSheetValue({
  required String specKey,
  required String value,
  String? dataType,
  String? unit,
}) {
  final raw = value.trim();
  if (raw.isEmpty) return const PublicSpecDisplayValue('');
  if (specKey == 'bead_seat_diameter_mm') {
    final name = wheelSizeNameForBsd(raw);
    if (name != null) {
      return PublicSpecDisplayValue(name, detail: 'ISO ${_bsd(raw)}');
    }
  }
  if (specKey == 'tire_width_mm') {
    final width = tireWidthLabel(raw);
    if (width != null) return PublicSpecDisplayValue(width);
  }
  if (specKey == 'tube_fit_rows') {
    final fit = tubeFitLabel(raw);
    if (fit != null) return PublicSpecDisplayValue(fit);
  }
  return PublicSpecDisplayValue(
    _valueWithUnit(raw, dataType: dataType, unit: unit),
  );
}

/// Valor de un filtro del catálogo en palabras de tienda: el diámetro ISO
/// como rodado, un número a la chilena con su unidad, una opción por su
/// nombre visible (`optionDisplay`, de `get_public_spec_option_labels_v1`).
String publicSpecValueLabel({
  required String specKey,
  required String value,
  String? dataType,
  String? unit,
  Map<String, String>? optionDisplay,
}) {
  final raw = value.trim();
  if (raw.isEmpty) return raw;
  if (specKey == 'bead_seat_diameter_mm') {
    return wheelSizeLabelForBsd(raw) ?? raw;
  }
  if (specKey == 'tire_width_mm') {
    return tireWidthLabel(raw) ?? raw;
  }
  final display = optionDisplay?[raw];
  if (display != null && display.trim().isNotEmpty) return display.trim();
  return _valueWithUnit(raw, dataType: dataType, unit: unit);
}

String _valueWithUnit(String raw, {String? dataType, String? unit}) {
  if (dataType == 'boolean') return raw;
  if (dataType == 'multi_select') {
    return naturalSpanishList(
      raw
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .map((part) => _withUnit(part, unit))
          .toList(),
    );
  }
  if (dataType == 'number') {
    return _withUnit(chileanNumber(raw), unit, count: _number(raw));
  }
  // Una opción con unidad (una bolita de «1/4» pulgada) la lleva escrita.
  if (dataType == 'single_select') return _withUnit(raw, unit);
  return raw;
}

num? _number(String raw) => num.tryParse(raw.trim().replaceAll(',', '.'));

/// «57.1» → «57,1»; «24.0» → «24»; «1000» → «1.000». Lo que no es un número
/// queda como vino.
String chileanNumber(String raw) {
  final text = raw.trim();
  if (!RegExp(r'^-?[0-9]+([.,][0-9]+)?$').hasMatch(text)) return text;
  final number = _number(text)!;
  final decimals = text.contains(RegExp('[.,]'))
      ? text.split(RegExp('[.,]')).last.replaceFirst(RegExp(r'0+$'), '').length
      : 0;
  final format = NumberFormat.decimalPatternDigits(
    locale: 'es_CL',
    decimalDigits: decimals,
  );
  // es_CL escribe 1.000 sólo desde 10.000; en la tienda «1.000 lúmenes» se
  // lee mejor que «1000».
  final grouped = format.format(number);
  if (number.abs() >= 1000 && number.abs() < 10000 && !grouped.contains('.')) {
    final integer = number.abs().truncate().toString();
    final rest = grouped.contains(',') ? ',${grouped.split(',').last}' : '';
    return '${number < 0 ? '-' : ''}${integer[0]}.${integer.substring(1)}$rest';
  }
  return grouped;
}

/// Unidades como se dicen en la tienda; «T» es la unidad del motor para
/// dientes y nadie la lee así.
const Map<String, String> _unitWords = <String, String>{
  'T': 'dientes',
  'in': '"',
  'lm': 'lúmenes',
};

const Map<String, String> _singularUnits = <String, String>{
  'dientes': 'diente',
  'unidades': 'unidad',
  'lúmenes': 'lumen',
  'eslabones': 'eslabón',
};

String _withUnit(String value, String? unit, {num? count}) {
  final rawUnit = unit?.trim() ?? '';
  if (rawUnit.isEmpty) return value;
  var word = _unitWords[rawUnit] ?? rawUnit;
  if (RegExp('(^|\\s)${RegExp.escape(word)}\\.?\$', caseSensitive: false)
          .hasMatch(value) ||
      RegExp('(^|\\s)${RegExp.escape(rawUnit)}\\.?\$', caseSensitive: false)
          .hasMatch(value)) {
    return value;
  }
  if (count == 1) word = _singularUnits[word] ?? word;
  // Pulgadas y grados van pegados al número: 1/4", 22°.
  if (word == '"' || word == '°') return '$value$word';
  return '$value $word';
}

/// «6, 7 y 8».
String naturalSpanishList(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.single;
  return '${items.sublist(0, items.length - 1).join(', ')} y ${items.last}';
}

/// Ancho de neumático como lo pide el cliente: en pulgadas desde 1.5" (MTB,
/// urbana, niños: «2.1" · 53 mm»), en milímetros por debajo (ruta y gravel:
/// «25 mm»). El milímetro guardado no se pierde nunca.
String? tireWidthLabel(String raw) {
  final mm = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (mm == null || mm <= 0) return null;
  final mmText = _trimNumber(mm.round().toDouble());
  if (mm < 38) return '$mmText mm';
  return '${_inchWidth(mm)}" · $mmText mm';
}

/// Pulgadas comerciales de un ancho: 2.125 y 2.375 son octavos y se escriben
/// así; el resto con dos decimales (1.95, 2.25) o uno (2.1, 2.4); nunca «2"»
/// sino «2.0"», como en los flancos y las tiendas.
String _inchWidth(double mm) {
  final inches = mm / 25.4;
  final eighths = inches * 8;
  final inchText =
      (eighths - eighths.round()).abs() < 0.02 && (eighths.round() % 2 == 1)
          ? (eighths.round() / 8).toStringAsFixed(3)
          : _trimNumber(double.parse(inches.toStringAsFixed(2)));
  return inchText.contains('.') ? inchText : '$inchText.0';
}

/// Para qué neumáticos sirve una cámara, a partir del texto que el servidor
/// redacta para cada fila de ajuste («Diámetro de asiento (BSD): 559 mm ·
/// Ancho mínimo: 49.5 mm · Ancho máximo: 54 mm»): «26" · 1.95" a 2.125"».
/// Anchos de ruta en milímetros: «700c · 18 a 25 mm». Una fila por línea.
/// Null si el texto no trae el diámetro.
String? tubeFitLabel(String raw) {
  final rows = <String>[];
  for (final row in raw.split(RegExp(r'\s*\|\s*|\n'))) {
    final bsdMatch = RegExp(r'BSD\)?\s*:\s*([0-9]+)').firstMatch(row);
    if (bsdMatch == null) continue;
    final bsd = int.parse(bsdMatch.group(1)!);
    double? width(String word) {
      final match =
          RegExp('$word\\s*:\\s*([0-9]+(?:[.,][0-9]+)?)', caseSensitive: false)
              .firstMatch(row);
      return match == null
          ? null
          : double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }

    final min = width('m[ií]nimo');
    final max = width('m[aá]ximo');
    final inMillimetres = (min ?? max ?? 38) < 38;
    final wheel = inMillimetres && bsd == 622
        ? '700c'
        : inMillimetres && bsd == 584
            ? '650b'
            : _wheelSizeByBsd[bsd] ?? 'ISO $bsd';
    String text(double mm) => inMillimetres
        ? _trimNumber(mm.round().toDouble())
        : '${_inchWidth(mm)}"';
    final unit = inMillimetres ? ' mm' : '';
    final widths = min != null && max != null
        ? '${text(min)} a ${text(max)}$unit'
        : min != null
            ? 'desde ${text(min)}$unit'
            : max != null
                ? 'hasta ${text(max)}$unit'
                : '';
    rows.add(widths.isEmpty ? wheel : '$wheel · $widths');
  }
  return rows.isEmpty ? null : rows.join('\n');
}

String _trimNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
