const Set<String> kSpecificDrivetrainCompatibilityFamilies = {
  'shimano_ecosystem',
  'sram_ecosystem',
  'campagnolo_ecosystem',
  'microshift_ecosystem',
  'single_speed_bmx',
};

String? drivetrainCompatibilityPlatformToken(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }

  final normalized = _normalizeDrivetrainCompatibilityText(rawValue.toString());
  if (normalized.isEmpty ||
      normalized == 'unknown' ||
      normalized.contains('desconoc')) {
    return null;
  }

  switch (normalized) {
    case 'shimano_hg_sis':
    case 'shimano_hg_plus':
    case 'shimano_linkglide':
    case 'sram_eagle':
    case 'sram_flattop':
    case 'sram_t_type':
    case 'campagnolo':
    case 'microshift_advent':
    case 'kmc_compatible':
    case 'universal_5_8':
    case 'universal_9_11':
    case 'friction_universal':
    case 'single_speed_bmx':
    case 'generic':
      return normalized;
  }

  if (normalized.contains('hyperglide') ||
      normalized.contains('hg+') ||
      normalized.contains('hg_plus')) {
    return 'shimano_hg_plus';
  }
  if (normalized.contains('linkglide') || normalized.contains('cues')) {
    return 'shimano_linkglide';
  }
  // Bare ecosystem claims like "Shimano" or "SRAM" are not exact platform
  // truth, even if they were saved into the wrong field in legacy data.
  if (normalized == 'shimano_hg_sis' ||
      normalized == 'hg' ||
      normalized.contains('hg/sis') ||
      normalized.contains('hg sis') ||
      (normalized.contains('shimano') &&
          (normalized.contains('hg') || normalized.contains('sis')))) {
    return 'shimano_hg_sis';
  }
  if (normalized.contains('t-type') ||
      normalized.contains('t type') ||
      normalized.contains('t_type') ||
      normalized.contains('transmission')) {
    return 'sram_t_type';
  }
  if (normalized.contains('flattop') ||
      normalized.contains('flat top') ||
      normalized.contains('flat_top')) {
    return 'sram_flattop';
  }
  if (normalized == 'sram_eagle' || normalized.contains('eagle')) {
    return 'sram_eagle';
  }
  if (normalized == 'campagnolo' ||
      (normalized.contains('campagnolo') &&
          !normalized.contains('ecosistema') &&
          !normalized.contains('ecosystem') &&
          !normalized.contains('compatible'))) {
    return 'campagnolo';
  }
  if (normalized == 'microshift_advent' ||
      normalized.contains('advent') ||
      normalized.contains('acolyte')) {
    return 'microshift_advent';
  }
  if (normalized.contains('kmc')) {
    return 'kmc_compatible';
  }
  if (normalized.contains('5-8') || normalized.contains('5 a 8')) {
    return 'universal_5_8';
  }
  if (normalized.contains('9-11') || normalized.contains('9 a 11')) {
    return 'universal_9_11';
  }
  if (normalized.contains('friccion') ||
      normalized.contains('friction') ||
      normalized.contains('universal')) {
    return 'friction_universal';
  }
  if (normalized.contains('single') || normalized.contains('bmx')) {
    return 'single_speed_bmx';
  }
  if (normalized.contains('generico') ||
      normalized == 'generic' ||
      (normalized == 'compatible') ||
      ((normalized.contains('generic') || normalized.contains('compatible')) &&
          !normalized.contains('shimano') &&
          !normalized.contains('sram') &&
          !normalized.contains('campagnolo') &&
          !normalized.contains('microshift'))) {
    return 'generic';
  }

  return null;
}

String? drivetrainCompatibilityFamilyToken(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }

  final normalized = _normalizeDrivetrainCompatibilityText(rawValue.toString());
  if (normalized.isEmpty ||
      normalized == 'unknown' ||
      normalized.contains('desconoc')) {
    return null;
  }

  if (normalized.contains('shimano')) {
    return 'shimano_ecosystem';
  }
  if (normalized.contains('sram')) {
    return 'sram_ecosystem';
  }
  if (normalized.contains('campagnolo')) {
    return 'campagnolo_ecosystem';
  }
  if (normalized.contains('microshift') ||
      normalized.contains('advent') ||
      normalized.contains('acolyte')) {
    return 'microshift_ecosystem';
  }
  if (normalized.contains('kmc')) {
    return 'kmc_multi_compatible';
  }
  if (normalized.contains('single') || normalized.contains('bmx')) {
    return 'single_speed_bmx';
  }
  if (normalized.contains('universal') ||
      normalized.contains('generico') ||
      normalized.contains('generic')) {
    return 'universal_generic';
  }

  return _normalizeDrivetrainCompatibilityToken(rawValue.toString());
}

String? drivetrainCompatibilityModeToken(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }

  final normalized = _normalizeDrivetrainCompatibilityText(rawValue.toString());
  if (normalized.isEmpty ||
      normalized == 'unknown' ||
      normalized.contains('desconoc')) {
    return null;
  }

  if (normalized.contains('single') ||
      normalized.contains('bmx') ||
      normalized.contains('igh') ||
      normalized.contains('interna') ||
      normalized.contains('internal') ||
      normalized.contains('fijo') ||
      normalized.contains('fixie') ||
      normalized.contains('contrapedal') ||
      normalized.contains('coaster')) {
    return 'single_speed_bmx_igh';
  }

  if (normalized.contains('derailleur') ||
      normalized.contains('desviador') ||
      normalized.contains('cambio')) {
    return 'derailleur';
  }

  return _normalizeDrivetrainCompatibilityToken(rawValue.toString());
}

Set<String> drivetrainPlatformsFromCompatibilitySpecs(
  Map<String, dynamic> specValues,
) {
  final platforms = <String>{};

  void parse(dynamic value) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        parse(item);
      }
      return;
    }
    if (value is Map) {
      for (final item in value.values) {
        parse(item);
      }
      return;
    }

    final canonical = drivetrainCompatibilityPlatformToken(value);
    if (canonical != null) {
      platforms.add(canonical);
    }
  }

  parse(specValues['drivetrain_platform']);
  parse(specValues['chain_profile_family']);

  if (drivetrainCompatibilityModeToken(specValues['drivetrain_mode']) ==
      'single_speed_bmx_igh') {
    platforms.add('single_speed_bmx');
  }

  return platforms;
}

Set<String> drivetrainCompatibilityFamiliesFromCompatibilitySpecs(
  Map<String, dynamic> specValues,
) {
  final families = <String>{};

  void parse(dynamic value) {
    if (value == null) return;
    if (value is List) {
      for (final item in value) {
        parse(item);
      }
      return;
    }
    if (value is Map) {
      for (final item in value.values) {
        parse(item);
      }
      return;
    }

    final canonical = drivetrainCompatibilityFamilyToken(value);
    if (canonical != null) {
      families.add(canonical);
    }
  }

  parse(specValues['drivetrain_primary_ecosystem']);
  parse(specValues['drivetrain_declared_compatible_ecosystems']);
  if (families.isEmpty) {
    parse(specValues['drivetrain_compatibility_family']);
  }
  if (drivetrainCompatibilityModeToken(specValues['drivetrain_mode']) ==
      'single_speed_bmx_igh') {
    families.add('single_speed_bmx');
  }

  return families;
}

String? drivetrainCompatibilityFamilyForPlatformToken(String? platform) {
  switch (platform) {
    case 'shimano_hg_sis':
    case 'shimano_hg_plus':
    case 'shimano_linkglide':
      return 'shimano_ecosystem';
    case 'sram_eagle':
    case 'sram_flattop':
    case 'sram_t_type':
      return 'sram_ecosystem';
    case 'campagnolo':
      return 'campagnolo_ecosystem';
    case 'microshift_advent':
      return 'microshift_ecosystem';
    case 'single_speed_bmx':
      return 'single_speed_bmx';
    case 'generic':
    case 'friction_universal':
    case 'universal_5_8':
    case 'universal_9_11':
    case 'kmc_compatible':
      return 'universal_generic';
    default:
      return null;
  }
}

bool hasExplicitDrivetrainFamilyConflict({
  required String bikePlatform,
  required Set<String> productFamilies,
}) {
  final bikeFamily =
      drivetrainCompatibilityFamilyForPlatformToken(bikePlatform);
  if (bikeFamily == null || productFamilies.isEmpty) {
    return false;
  }

  if (productFamilies.contains(bikeFamily)) {
    return false;
  }

  if (productFamilies.any(
    (family) => _isBroadCompatibleDrivetrainFamilyForBike(
      bikeFamily: bikeFamily,
      productFamily: family,
    ),
  )) {
    return false;
  }

  final specificFamilies = productFamilies
      .where(kSpecificDrivetrainCompatibilityFamilies.contains)
      .toSet();
  if (specificFamilies.isEmpty) {
    return false;
  }

  return !specificFamilies.contains(bikeFamily);
}

bool _isBroadCompatibleDrivetrainFamilyForBike({
  required String bikeFamily,
  required String productFamily,
}) {
  if (productFamily == 'universal_generic') {
    return true;
  }

  return bikeFamily != 'single_speed_bmx' &&
      productFamily == 'kmc_multi_compatible';
}

String _normalizeDrivetrainCompatibilityText(String value) {
  return value.trim().toLowerCase();
}

String? _normalizeDrivetrainCompatibilityToken(String? rawValue) {
  final normalized = rawValue?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  return normalized
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
