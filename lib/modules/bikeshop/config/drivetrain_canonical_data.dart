const Map<String, String> kDrivetrainChainWearOptions = {
  'ok': 'OK (< 0.5%)',
  'worn': 'Desgastada (0.5-0.75%) - reemplazar pronto',
  'replace': 'Muy desgastada (> 0.75%) - cambiar ahora',
};

const Map<String, String> kDrivetrainCableConditionOptions = {
  'ok': 'Funcionamiento suave / sin resistencia anormal',
  'high_friction': 'Alta friccion / recorrido duro',
  'frayed': 'Deshilachado',
  'corroded': 'Corrosion visible',
  'housing_damaged': 'Funda danada / colapsada',
  'replace': 'Danio severo / recambio necesario',
};

const Map<String, String> kDrivetrainFrontChainringCountOptions = {
  '1': '1 plato',
  '2': '2 platos',
  '3': '3 platos',
};

const Map<String, String> kDrivetrainRearCogCountOptions = {
  '1': '1 pinon',
  '3': '3 pinones',
  '5': '5 pinones',
  '6': '6 pinones',
  '7': '7 pinones',
  '8': '8 pinones',
  '9': '9 pinones',
  '10': '10 pinones',
  '11': '11 pinones',
  '12': '12 pinones',
  '13': '13 pinones',
  '14': '14 pinones',
};

const Map<String, String> kDrivetrainFreehubTypeOptions = {
  'shimano_hg': 'Shimano HG',
  'microspline': 'Micro Spline',
  'sram_xd': 'SRAM XD',
  'campagnolo': 'Campagnolo',
  'threaded_freewheel': 'Rueda libre roscada',
  'bmx_driver': 'Driver BMX',
  'fixed_threaded': 'Rosca fija / contratuerca',
  'coaster_hub': 'Maza contrapedal',
  'unknown': 'Desconocido / sin confirmar',
};

const Set<String> kDiagnosisLinkedDrivetrainWizardQuestionKeys = {
  'chain_wear',
  'cable_condition',
};

bool isDiagnosisLinkedDrivetrainQuestionKey(String key) {
  return kDiagnosisLinkedDrivetrainWizardQuestionKeys.contains(key);
}

String? canonicalDrivetrainChainWearValue(String? rawValue) {
  switch (rawValue) {
    case 'ok':
    case 'worn':
    case 'replace':
      return rawValue;
    default:
      return _normalizeDrivetrainText(rawValue);
  }
}

String? canonicalDrivetrainCableConditionValue(String? rawValue) {
  switch (rawValue) {
    case 'ok':
    case 'high_friction':
    case 'frayed':
    case 'corroded':
    case 'housing_damaged':
    case 'replace':
      return rawValue;
    case 'sticky':
    case 'hard':
    case 'tight':
    case 'dragging':
      return 'high_friction';
    case 'rusted':
      return 'corroded';
    case 'damaged_housing':
    case 'collapsed_housing':
      return 'housing_damaged';
    default:
      return _normalizeDrivetrainText(rawValue);
  }
}

String? canonicalDrivetrainFrontChainringCountValue(String? rawValue) {
  final numericValue = _extractCanonicalDrivetrainCount(
    rawValue,
    allowedValues: kDrivetrainFrontChainringCountOptions.keys,
  );
  return numericValue;
}

String? canonicalDrivetrainRearCogCountValue(String? rawValue) {
  final numericValue = _extractCanonicalDrivetrainCount(
    rawValue,
    allowedValues: kDrivetrainRearCogCountOptions.keys,
  );
  return numericValue;
}

String? canonicalDrivetrainFreehubTypeValue(String? rawValue) {
  switch (_normalizeDrivetrainText(rawValue)?.toLowerCase()) {
    case 'shimano_hg':
    case 'hg':
      return 'shimano_hg';
    case 'microspline':
    case 'micro_spline':
    case 'micro spline':
      return 'microspline';
    case 'sram_xd':
    case 'xd':
    case 'sram xd':
      return 'sram_xd';
    case 'campagnolo':
      return 'campagnolo';
    case 'threaded_freewheel':
    case 'freewheel':
    case 'rueda libre':
      return 'threaded_freewheel';
    case 'bmx_driver':
    case 'bmx driver':
    case 'driver bmx':
      return 'bmx_driver';
    case 'fixed_threaded':
    case 'fixed':
    case 'fixed hub':
    case 'rosca fija':
      return 'fixed_threaded';
    case 'coaster_hub':
    case 'coaster':
    case 'contrapedal':
      return 'coaster_hub';
    case 'unknown':
    case 'desconocido':
      return 'unknown';
    default:
      return null;
  }
}

String? drivetrainConfigFromCounts(
  dynamic rawFrontChainringCount,
  dynamic rawRearCogCount,
) {
  final frontCount = int.tryParse(
    canonicalDrivetrainFrontChainringCountValue(
          rawFrontChainringCount?.toString(),
        ) ??
        '',
  );
  final rearCount = int.tryParse(
    canonicalDrivetrainRearCogCountValue(rawRearCogCount?.toString()) ?? '',
  );
  if (frontCount == null ||
      rearCount == null ||
      frontCount <= 0 ||
      rearCount <= 0) {
    return null;
  }
  if (frontCount == 1 && rearCount == 1) {
    return 'singlespeed';
  }
  return '${frontCount}x$rearCount';
}

int? drivetrainSpeedsFromCounts(
  dynamic rawFrontChainringCount,
  dynamic rawRearCogCount,
) {
  final frontCount = int.tryParse(
    canonicalDrivetrainFrontChainringCountValue(
          rawFrontChainringCount?.toString(),
        ) ??
        '',
  );
  final rearCount = int.tryParse(
    canonicalDrivetrainRearCogCountValue(rawRearCogCount?.toString()) ?? '',
  );
  if (frontCount == null ||
      rearCount == null ||
      frontCount <= 0 ||
      rearCount <= 0) {
    return null;
  }
  return frontCount * rearCount;
}

String? drivetrainFrontChainringCountFromConfig(String? drivetrainConfig) {
  final normalized = _normalizeDrivetrainText(drivetrainConfig)?.toLowerCase();
  if (normalized == null) {
    return null;
  }
  if (normalized == 'singlespeed') {
    return '1';
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(normalized);
  if (match == null) {
    return null;
  }
  return canonicalDrivetrainFrontChainringCountValue(match.group(1));
}

String? drivetrainRearCogCountFromConfig(String? drivetrainConfig) {
  final normalized = _normalizeDrivetrainText(drivetrainConfig)?.toLowerCase();
  if (normalized == null) {
    return null;
  }
  if (normalized == 'singlespeed') {
    return '1';
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(normalized);
  if (match == null) {
    return null;
  }
  return canonicalDrivetrainRearCogCountValue(match.group(2));
}

bool isKnownDrivetrainFreehubType(String? rawValue) {
  final canonicalValue = canonicalDrivetrainFreehubTypeValue(rawValue);
  return canonicalValue != null && canonicalValue != 'unknown';
}

String? drivetrainFreehubTypeLabel(String? rawValue) {
  final canonicalValue = canonicalDrivetrainFreehubTypeValue(rawValue);
  if (canonicalValue == null) {
    return null;
  }
  return kDrivetrainFreehubTypeOptions[canonicalValue];
}

String? resolveDrivetrainQuestionLabel(String key) {
  switch (key) {
    case 'chain_wear':
      return 'Desgaste de la cadena';
    case 'cable_condition':
      return 'Estado cables y fundas';
    case 'front_chainring_count':
      return 'Platos delanteros';
    case 'rear_cog_count':
      return 'Pinones traseros';
    case 'freehub_type':
      return 'Driver / freehub';
    default:
      return null;
  }
}

Map<String, dynamic> canonicalizeDrivetrainWizardAnswers(
  Map<String, dynamic> rawAnswers,
) {
  final normalized = <String, dynamic>{};

  for (final entry in rawAnswers.entries) {
    final normalizedValue = canonicalizeDrivetrainWizardAnswerValue(
      entry.key,
      entry.value,
    );

    if (_isMeaningfulDrivetrainAnswer(normalizedValue)) {
      normalized[entry.key] = normalizedValue;
    }
  }

  return normalized;
}

dynamic canonicalizeDrivetrainWizardAnswerValue(String key, dynamic rawValue) {
  switch (key) {
    case 'chain_wear':
      return canonicalDrivetrainChainWearValue(rawValue?.toString());
    case 'cable_condition':
      return canonicalDrivetrainCableConditionValue(rawValue?.toString());
    case 'front_chainring_count':
      return canonicalDrivetrainFrontChainringCountValue(rawValue?.toString());
    case 'rear_cog_count':
      return canonicalDrivetrainRearCogCountValue(rawValue?.toString());
    case 'freehub_type':
      return canonicalDrivetrainFreehubTypeValue(rawValue?.toString());
    case 'derailleurs':
      if (rawValue is! List) {
        return rawValue;
      }

      final normalized = rawValue
          .map((value) => value.toString())
          .where((value) => value == 'front' || value == 'rear')
          .toList(growable: false);
      return normalized.isEmpty ? null : normalized;
    default:
      return rawValue;
  }
}

String? resolveDrivetrainAnswerLabel(String key, String rawValue) {
  switch (key) {
    case 'chain_wear':
      return kDrivetrainChainWearOptions[rawValue];
    case 'cable_condition':
      return kDrivetrainCableConditionOptions[rawValue];
    case 'front_chainring_count':
      return kDrivetrainFrontChainringCountOptions[rawValue];
    case 'rear_cog_count':
      return kDrivetrainRearCogCountOptions[rawValue];
    case 'freehub_type':
      return kDrivetrainFreehubTypeOptions[rawValue];
    default:
      return null;
  }
}

bool _isMeaningfulDrivetrainAnswer(dynamic value) {
  if (value == null) {
    return false;
  }
  if (value is String) {
    return value.trim().isNotEmpty;
  }
  if (value is List) {
    return value.isNotEmpty;
  }
  return true;
}

String? _normalizeDrivetrainText(String? rawValue) {
  final normalized = rawValue?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String? _extractCanonicalDrivetrainCount(
  String? rawValue, {
  required Iterable<String> allowedValues,
}) {
  final normalized = _normalizeDrivetrainText(rawValue);
  if (normalized == null) {
    return null;
  }

  if (allowedValues.contains(normalized)) {
    return normalized;
  }

  final digitMatch = RegExp(r'(\d+)').firstMatch(normalized);
  final digitValue = digitMatch?.group(1);
  if (digitValue != null && allowedValues.contains(digitValue)) {
    return digitValue;
  }

  return null;
}
