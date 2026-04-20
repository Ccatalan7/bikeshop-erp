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

String? resolveDrivetrainQuestionLabel(String key) {
  switch (key) {
    case 'chain_wear':
      return 'Desgaste de la cadena';
    case 'cable_condition':
      return 'Estado cables y fundas';
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
