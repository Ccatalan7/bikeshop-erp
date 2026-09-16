/// Cómo se le muestra al cliente una medida técnica de la ficha.
///
/// El motor guarda el diámetro de rueda como ISO 5775 (`bead_seat_diameter_mm`),
/// que es exacto pero no es lo que el cliente compra: él pide «aro 29»,
/// «700c», «aro 26». Estas funciones traducen sin perder el número.
library;

/// Rodado comercial de un diámetro ISO 5775 (tabla de Sheldon Brown), o null
/// cuando el texto no es un diámetro conocido.
String? wheelSizeLabelForBsd(String raw) {
  final bsd = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
  if (bsd == null) return null;
  const labels = <int, String>{
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
  final label = labels[bsd];
  return label == null ? null : '$label (ISO $bsd)';
}

/// Valor de un filtro o de una fila de ficha en palabras de tienda: el
/// diámetro ISO como rodado, un número con su unidad, lo demás tal cual.
String publicSpecValueLabel({
  required String specKey,
  required String value,
  String? dataType,
  String? unit,
}) {
  final raw = value.trim();
  if (raw.isEmpty) return raw;
  if (specKey == 'bead_seat_diameter_mm') {
    return wheelSizeLabelForBsd(raw) ?? raw;
  }
  if (specKey == 'tire_width_mm') {
    return tireWidthLabel(raw) ?? raw;
  }
  final cleanUnit = unit?.trim() ?? '';
  if (dataType == 'number' && cleanUnit.isNotEmpty) {
    final alreadyHasUnit = RegExp(
      '(^|\\s)${RegExp.escape(cleanUnit)}\\.?\$',
      caseSensitive: false,
    ).hasMatch(raw);
    return alreadyHasUnit ? raw : '$raw $cleanUnit';
  }
  return raw;
}

/// Ancho de neumático como lo pide el cliente: en pulgadas desde 1.5" (MTB,
/// urbana, niños: «2.1" · 53 mm»), en milímetros por debajo (ruta y gravel:
/// «25 mm»). El milímetro guardado no se pierde nunca.
String? tireWidthLabel(String raw) {
  final mm = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (mm == null || mm <= 0) return null;
  final mmText = _trimNumber(mm.round().toDouble());
  if (mm < 38) return '$mmText mm';
  final inches = mm / 25.4;
  // 2.125 y 2.375 son octavos comerciales; el resto se escribe con dos
  // decimales (1.95, 2.25) o uno (2.1, 2.4).
  final eighths = inches * 8;
  final inchText = (eighths - eighths.round()).abs() < 0.02 &&
          (eighths.round() % 2 == 1)
      ? (eighths.round() / 8).toStringAsFixed(3)
      : _trimNumber(double.parse(inches.toStringAsFixed(2)));
  // «2.0"», nunca «2"»: así lo escriben los flancos y las tiendas.
  final inchLabel = inchText.contains('.') ? inchText : '$inchText.0';
  return '$inchLabel" · $mmText mm';
}

String _trimNumber(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  var text = value.toStringAsFixed(2);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}
