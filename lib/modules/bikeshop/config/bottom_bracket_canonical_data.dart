const Map<String, String> kBottomBracketFamilyOptions = {
  'bsa_threaded': 'BSA roscado',
  'pressfit': 'Pressfit',
  'bb30_pf30': 'BB30 / PF30',
  'mid': 'Mid / BMX',
  'one_piece': 'One-piece',
  'other': 'Otro',
  'unknown': 'Desconocido',
};

const Map<String, String> kBottomBracketSpindleInterfaceOptions = {
  'square_jis': 'Cuadrado JIS',
  'square_iso': 'Cuadrado ISO',
  'square_taper': 'Cuadrado (sin confirmar JIS/ISO)',
  'hollowtech_24': 'Hollowtech / 24 mm',
  'sram_dub': 'SRAM DUB',
  'isis': 'ISIS',
  'octalink': 'Octalink',
  'bmx_19': 'BMX 19 mm',
  'bmx_22': 'BMX 22 mm',
  'bmx_24': 'BMX 24 mm',
  'one_piece': 'One-piece / americano',
  'unknown': 'Desconocido / sin confirmar',
};

const List<String> _kBottomBracketShellWidthThreadedOptions = [
  '68',
  '70',
  '73',
  '83',
  '100',
];

const List<String> _kBottomBracketShellWidthPressfitOptions = [
  '86.5',
  '89.5',
  '92',
  '107',
  '121',
];

const List<String> _kBottomBracketShellWidthBb30Pf30Options = [
  '68',
  '73',
  '83',
  '86.5',
];

const List<String> _kBottomBracketShellWidthMidOptions = [
  '68',
  '73',
];

const List<String> _kBottomBracketShellWidthOnePieceOptions = [
  '68',
  '73',
];

const List<String> _kBottomBracketShellDiameterPressfitOptions = [
  '41',
];

const List<String> _kBottomBracketShellDiameterBb30Pf30Options = [
  '42',
  '46',
];

const List<String> _kBottomBracketShellDiameterMidOptions = [
  '41.2',
];

const List<String> _kBottomBracketShellDiameterOnePieceOptions = [
  '51.5',
];

String _normalizeBottomBracketText(String rawValue) {
  return rawValue
      .trim()
      .toLowerCase()
      .replaceAll('-', '_')
      .replaceAll(' ', '_');
}

String? canonicalBottomBracketFamilyValue(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }

  final normalized = _normalizeBottomBracketText(rawValue);
  if (normalized == 'unknown' || normalized.contains('desconoc')) {
    return 'unknown';
  }
  if (normalized.contains('bb30') || normalized.contains('pf30')) {
    return 'bb30_pf30';
  }
  if (normalized.contains('pressfit') || normalized.contains('press_fit')) {
    return 'pressfit';
  }
  if (normalized.contains('mid')) {
    return 'mid';
  }
  if (normalized.contains('american') ||
      normalized.contains('americano') ||
      normalized.contains('one_piece')) {
    return 'one_piece';
  }
  if (normalized.contains('bsa') ||
      normalized.contains('threaded') ||
      normalized.contains('ingles') ||
      normalized.contains('english')) {
    return 'bsa_threaded';
  }
  if (normalized.contains('other') || normalized.contains('otro')) {
    return 'other';
  }

  return normalized;
}

String? canonicalBottomBracketSpindleInterfaceValue(String? rawValue) {
  if (rawValue == null || rawValue.trim().isEmpty) {
    return null;
  }

  final normalized = _normalizeBottomBracketText(rawValue);
  if (normalized == 'unknown' || normalized.contains('desconoc')) {
    return 'unknown';
  }
  if (normalized.contains('jis')) {
    return 'square_jis';
  }
  if (normalized.contains('iso')) {
    return 'square_iso';
  }
  if (normalized.contains('dub')) {
    return 'sram_dub';
  }
  if (normalized.contains('isis')) {
    return 'isis';
  }
  if (normalized.contains('octalink')) {
    return 'octalink';
  }
  if (normalized.contains('bmx') &&
      (normalized.contains('19mm') || normalized.contains('19_mm'))) {
    return 'bmx_19';
  }
  if (normalized.contains('bmx') &&
      (normalized.contains('22mm') || normalized.contains('22_mm'))) {
    return 'bmx_22';
  }
  if (normalized.contains('bmx') &&
      (normalized.contains('24mm') || normalized.contains('24_mm'))) {
    return 'bmx_24';
  }
  if (normalized.contains('one_piece') || normalized.contains('americano')) {
    return 'one_piece';
  }
  if (normalized.contains('hollowtech') ||
      normalized.contains('24mm') ||
      normalized.contains('24_mm') ||
      normalized.contains('integrado')) {
    return 'hollowtech_24';
  }
  if (normalized.contains('square') || normalized.contains('cuadrado')) {
    return 'square_taper';
  }

  return normalized;
}

Map<String, String> _measurementOptions(List<String> values) {
  return {
    for (final value in values) value: '$value mm',
  };
}

String? bottomBracketFamilyLabel(String? rawValue) {
  final canonicalValue = canonicalBottomBracketFamilyValue(rawValue);
  if (canonicalValue == null || canonicalValue.isEmpty) {
    return null;
  }

  return kBottomBracketFamilyOptions[canonicalValue] ?? canonicalValue;
}

bool isKnownBottomBracketFamily(String? rawValue) {
  final canonicalValue = canonicalBottomBracketFamilyValue(rawValue);
  return canonicalValue != null &&
      canonicalValue.isNotEmpty &&
      canonicalValue != 'unknown';
}

bool bottomBracketFamilyUsesShellDiameter(String? rawValue) {
  switch (canonicalBottomBracketFamilyValue(rawValue)) {
    case 'pressfit':
    case 'bb30_pf30':
    case 'mid':
    case 'one_piece':
      return true;
    default:
      return false;
  }
}

Map<String, String> bottomBracketShellWidthOptionsForFamily(String? rawValue) {
  switch (canonicalBottomBracketFamilyValue(rawValue)) {
    case 'bsa_threaded':
      return _measurementOptions(_kBottomBracketShellWidthThreadedOptions);
    case 'pressfit':
      return _measurementOptions(_kBottomBracketShellWidthPressfitOptions);
    case 'bb30_pf30':
      return _measurementOptions(_kBottomBracketShellWidthBb30Pf30Options);
    case 'mid':
      return _measurementOptions(_kBottomBracketShellWidthMidOptions);
    case 'one_piece':
      return _measurementOptions(_kBottomBracketShellWidthOnePieceOptions);
    case 'other':
      return _measurementOptions({
        ..._kBottomBracketShellWidthThreadedOptions,
        ..._kBottomBracketShellWidthPressfitOptions,
        ..._kBottomBracketShellWidthBb30Pf30Options,
      }.toList()
        ..sort());
    default:
      return const <String, String>{};
  }
}

Map<String, String> bottomBracketShellDiameterOptionsForFamily(
  String? rawValue,
) {
  switch (canonicalBottomBracketFamilyValue(rawValue)) {
    case 'pressfit':
      return _measurementOptions(_kBottomBracketShellDiameterPressfitOptions);
    case 'bb30_pf30':
      return _measurementOptions(_kBottomBracketShellDiameterBb30Pf30Options);
    case 'mid':
      return _measurementOptions(_kBottomBracketShellDiameterMidOptions);
    case 'one_piece':
      return _measurementOptions(_kBottomBracketShellDiameterOnePieceOptions);
    default:
      return const <String, String>{};
  }
}

Map<String, String> bottomBracketSpindleInterfaceOptionsForFamily(
  String? rawValue,
) {
  switch (canonicalBottomBracketFamilyValue(rawValue)) {
    case 'mid':
      return const {
        'bmx_19': 'BMX 19 mm',
        'bmx_22': 'BMX 22 mm',
        'bmx_24': 'BMX 24 mm',
        'unknown': 'Desconocido / sin confirmar',
      };
    case 'one_piece':
      return const {
        'one_piece': 'One-piece / americano',
        'unknown': 'Desconocido / sin confirmar',
      };
    case 'bsa_threaded':
    case 'pressfit':
    case 'bb30_pf30':
    case 'other':
      return const {
        'square_jis': 'Cuadrado JIS',
        'square_iso': 'Cuadrado ISO',
        'square_taper': 'Cuadrado (sin confirmar JIS/ISO)',
        'hollowtech_24': 'Hollowtech / 24 mm',
        'sram_dub': 'SRAM DUB',
        'isis': 'ISIS',
        'octalink': 'Octalink',
        'unknown': 'Desconocido / sin confirmar',
      };
    default:
      return const <String, String>{};
  }
}

String? bottomBracketSpindleInterfaceLabel(String? rawValue) {
  final canonicalValue = canonicalBottomBracketSpindleInterfaceValue(rawValue);
  if (canonicalValue == null || canonicalValue.isEmpty) {
    return null;
  }

  return kBottomBracketSpindleInterfaceOptions[canonicalValue] ??
      canonicalValue;
}

String? bottomBracketMeasurementLabel(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }

  final parsedValue = rawValue is num
      ? rawValue.toDouble()
      : double.tryParse(rawValue.toString().trim());
  if (parsedValue == null) {
    return null;
  }

  if (parsedValue == parsedValue.roundToDouble()) {
    return '${parsedValue.toInt()} mm';
  }

  return '${parsedValue.toStringAsFixed(1)} mm';
}
