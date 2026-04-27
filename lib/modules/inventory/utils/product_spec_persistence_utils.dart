dynamic sanitizeProductSpecValueForPersistence({
  required String specKey,
  required dynamic value,
}) {
  if (value == null) {
    return null;
  }

  switch (specKey) {
    case 'drivetrain_platform':
      return _sanitizeSingleSelectValue(
        rawValue: value,
        exactAllowedValues: const {
          'Shimano HG / SIS',
          'Shimano Hyperglide+',
          'Shimano Linkglide / CUES',
          'SRAM Eagle',
          'SRAM FlatTop / AXS road',
          'SRAM T-Type Transmission',
          'Campagnolo',
          'Microshift Advent / Acolyte',
          'Friccion / universal',
          'Single speed / BMX',
          'Generico compatible',
          'Desconocido / sin confirmar',
        },
      );
    case 'shift_actuation_family':
      return _sanitizeSingleSelectValue(
        rawValue: value,
        exactAllowedValues: const {
          'Shimano SIS 6-9v',
          'Shimano Dynasys 10v',
          'Shimano Dynasys 11/12v',
          'Shimano CUES / Linkglide',
          'Shimano ruta',
          'SRAM Exact Actuation',
          'SRAM X-Actuation / Eagle',
          'SRAM AXS road / FlatTop',
          'SRAM T-Type Transmission',
          'Campagnolo',
          'Microshift Advent / Acolyte',
          'Friccion / universal',
          'Otro',
          'Desconocido / sin confirmar',
        },
      );
    default:
      return value;
  }
}

String? _sanitizeSingleSelectValue({
  required dynamic rawValue,
  required Set<String> exactAllowedValues,
}) {
  final text = rawValue.toString().trim();
  if (text.isEmpty) {
    return null;
  }
  if (exactAllowedValues.contains(text)) {
    return text;
  }

  final normalized = _normalizeProductSpecPersistenceText(text);
  if (_looksLikeBroadDrivetrainEcosystemClaim(normalized)) {
    return null;
  }

  return text;
}

bool _looksLikeBroadDrivetrainEcosystemClaim(String normalized) {
  if (normalized.contains('ecosistema')) {
    return true;
  }
  if (normalized.contains('compatible') &&
      !normalized.contains('genericocompatible')) {
    return true;
  }

  final hasBrandFamily = normalized.contains('shimano') ||
      normalized.contains('sram') ||
      normalized.contains('campagnolo') ||
      normalized.contains('microshift');
  if (!hasBrandFamily) {
    return false;
  }

  final hasExactSemantics = normalized.contains('hg') ||
      normalized.contains('sis') ||
      normalized.contains('dynasys') ||
      normalized.contains('linkglide') ||
      normalized.contains('cues') ||
      normalized.contains('exactactuation') ||
      normalized.contains('xactuation') ||
      normalized.contains('eagle') ||
      normalized.contains('axs') ||
      normalized.contains('flattop') ||
      normalized.contains('ttype') ||
      normalized.contains('transmission') ||
      normalized.contains('advent') ||
      normalized.contains('acolyte') ||
      normalized.contains('friccion') ||
      normalized.contains('universal') ||
      normalized.contains('single') ||
      normalized.contains('bmx') ||
      normalized.contains('ruta');

  if (hasExactSemantics) {
    return false;
  }

  return true;
}

String _normalizeProductSpecPersistenceText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
