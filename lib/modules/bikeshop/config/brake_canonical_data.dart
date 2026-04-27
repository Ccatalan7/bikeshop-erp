const Map<String, String> kBikeProfileBrakeTypeOptions = {
  'rim': 'Llanta (rim)',
  'mechanical_disc': 'Disco mecánico',
  'hydraulic_disc': 'Disco hidráulico',
  'roller_brake': 'Roller brake',
  'drum_brake': 'Tambor',
  'coaster_brake': 'Contrapedal',
  'band_brake': 'Banda',
};

const Map<String, String> kRimBrakeFamilyOptions = {
  'v_brake': 'V-Brake',
  'cantilever': 'Cantilever',
  'road_caliper_short_reach': 'Caliper ruta corto',
  'road_caliper_long_reach': 'Caliper ruta largo',
  'u_brake': 'U-Brake',
  'rod_brake': 'Freno de varilla',
  'other': 'Otro',
  'unknown': 'Desconocido',
};

const Set<String> kRimBrakeFamilyOptionValues = {
  'v_brake',
  'cantilever',
  'road_caliper_short_reach',
  'road_caliper_long_reach',
  'u_brake',
  'rod_brake',
};

const Map<String, String> kBrakeTypeDisplayLabels = {
  'rim': 'Llanta (rim)',
  'mechanical_disc': 'Disco mecánico',
  'hydraulic_disc': 'Hidráulico',
  'v_brake': 'V-Brake',
  'cantilever': 'Cantilever',
  'road_caliper_short_reach': 'Caliper corto / short reach',
  'road_caliper_long_reach': 'Caliper largo / long reach',
  'roller_brake': 'Roller brake',
  'drum_brake': 'Tambor',
  'coaster_brake': 'Contrapedal',
  'band_brake': 'Banda',
};

const Map<String, String> kBrakePadContaminationOptions = {
  'ok': 'Limpias',
  'dirty': 'Sucias',
  'contaminated': 'Contaminadas',
  'replace': 'Reemplazar',
};

const Map<String, String> kBrakeRotorTruenessOptions = {
  'ok': 'Recto',
  'attention': 'Leve desalineación',
  'misaligned': 'Desviado / roza',
  'replace': 'Reemplazar',
};

const Map<String, String> kBrakeRotorContaminationOptions = {
  'ok': 'Limpio',
  'dirty': 'Sucio',
  'contaminated': 'Contaminado',
  'replace': 'Reemplazar',
};

const Map<String, String> kBrakeSymptomLabels = {
  'noise': 'Ruido',
  'vibration': 'Vibración',
  'rubbing': 'Roce constante',
  'low_power': 'Poca potencia',
  'spongy_lever': 'Maneta esponjosa',
  'intermittent': 'Frenado intermitente',
};

const Map<String, String> kBrakeWheelOptions = {
  'front': 'Delantera',
  'rear': 'Trasera',
  'both': 'Ambas ruedas',
};

const Map<String, String> kBrakeFluidTypeOptions = {
  'mineral': 'Aceite Mineral (Shimano / Magura / Tektro)',
  'dot': 'DOT 4 / 5.1 (SRAM / Hayes / Hope)',
};

const Map<String, String> kBrakeDamageLevelOptions = {
  'minor': 'Leve - centrado posible',
  'moderate': 'Moderado',
  'severe': 'Severo - puede requerir reemplazo',
};

const Map<String, String> kBrakePistonCountOptions = {
  '2': '2 pistones',
  '4': '4 pistones',
};

const Map<String, String> kBrakeRotorSizeOptions = {
  '140': '140 mm',
  '160': '160 mm',
  '180': '180 mm',
  '203': '203 mm',
};

const Map<String, String> kBrakeQuestionKeyAliases = {
  'position': 'which_wheel',
  'num_pistons': 'piston_count',
  'rotor_diameter': 'rotor_size',
  'deviation_severity': 'damage_level',
};

const Set<String> kObsoleteBrakeWizardQuestionKeys = {
  'includes_cable_housing',
  'symptom_severity',
  'hose_condition',
};

const Set<String> kDiagnosisLinkedBrakeWizardQuestionKeys = {
  'pad_condition',
  'pad_contaminated',
  'rotor_condition',
  'damage_level',
  'contamination_level',
  'symptom',
};

bool isDiagnosisLinkedBrakeQuestionKey(String key) {
  return kDiagnosisLinkedBrakeWizardQuestionKeys.contains(key);
}

String canonicalBrakeQuestionKey(String rawKey) {
  return kBrakeQuestionKeyAliases[rawKey] ?? rawKey;
}

bool isObsoleteBrakeWizardQuestionKey(String rawKey) {
  return kObsoleteBrakeWizardQuestionKeys.contains(rawKey);
}

String? canonicalBrakeWheelValue(String? rawValue) {
  switch (rawValue) {
    case 'front':
    case 'delantero':
      return 'front';
    case 'rear':
    case 'trasero':
      return 'rear';
    case 'both':
    case 'ambos':
      return 'both';
    default:
      return _normalizeBrakeText(rawValue);
  }
}

String? canonicalBrakeWheelValueFromAnswers(Map<String, dynamic> answers) {
  return canonicalBrakeWheelValue(
    answers['which_wheel']?.toString() ?? answers['position']?.toString(),
  );
}

String? canonicalBrakeTypeValue(String? rawValue) {
  final normalized = _normalizeBrakeText(rawValue)?.toLowerCase();
  switch (normalized) {
    case 'rim':
    case 'llanta':
    case 'rim brake':
    case 'freno de llanta':
      return 'rim';
    case 'mechanical_disc':
    case 'disco_mec':
    case 'disco mecanico':
    case 'disco mecánico':
    case 'mecanico':
    case 'mecánico':
      return 'mechanical_disc';
    case 'hydraulic_disc':
    case 'hidraulico':
    case 'hidráulico':
      return 'hydraulic_disc';
    case 'v_brake':
    case 'v-brake':
    case 'v brake':
    case 'vbrake':
      return 'v_brake';
    case 'cantilever':
      return 'cantilever';
    case 'road_caliper_short_reach':
    case 'short reach':
    case 'caliper corto':
      return 'road_caliper_short_reach';
    case 'road_caliper_long_reach':
    case 'long reach':
    case 'caliper largo':
      return 'road_caliper_long_reach';
    case 'u_brake':
    case 'u-brake':
    case 'u brake':
    case 'ubrake':
      return 'u_brake';
    case 'rod_brake':
    case 'rod brake':
    case 'freno de varilla':
    case 'varilla':
      return 'rod_brake';
    case 'roller_brake':
    case 'roller brake':
      return 'roller_brake';
    case 'drum_brake':
    case 'drum brake':
    case 'tambor':
      return 'drum_brake';
    case 'coaster_brake':
    case 'coaster brake':
    case 'contrapedal':
      return 'coaster_brake';
    case 'band_brake':
    case 'band brake':
    case 'banda':
      return 'band_brake';
    default:
      return _normalizeBrakeText(rawValue);
  }
}

String? canonicalBrakeFluidTypeValue(String? rawValue) {
  switch (rawValue) {
    case 'mineral':
      return 'mineral';
    case 'dot':
    case 'dot3':
    case 'dot4':
    case 'dot51':
      return 'dot';
    default:
      return _normalizeBrakeText(rawValue);
  }
}

String? canonicalBrakeDamageLevelValue(String? rawValue) {
  switch (rawValue) {
    case 'minor':
    case 'leve':
      return 'minor';
    case 'moderate':
    case 'moderado':
      return 'moderate';
    case 'severe':
    case 'severo':
      return 'severe';
    default:
      return _normalizeBrakeText(rawValue);
  }
}

String? canonicalBrakePistonCountValue(String? rawValue) {
  switch (rawValue) {
    case '2':
    case '4':
      return rawValue;
    default:
      return _normalizeBrakeText(rawValue);
  }
}

String? canonicalBrakeRotorSizeValue(String? rawValue) {
  switch (rawValue) {
    case '140':
    case '160':
    case '180':
    case '203':
      return rawValue;
    default:
      return _normalizeBrakeText(rawValue);
  }
}

Map<String, dynamic> canonicalizeBrakeWizardAnswers(
  Map<String, dynamic> rawAnswers,
) {
  final normalized = <String, dynamic>{};

  void mergeEntry(
    String rawKey,
    dynamic rawValue, {
    required bool isCanonicalSource,
  }) {
    if (rawKey == '_notes') {
      if (_isMeaningfulBrakeAnswer(rawValue)) {
        normalized[rawKey] = rawValue;
      }
      return;
    }

    if (isObsoleteBrakeWizardQuestionKey(rawKey)) {
      return;
    }

    final normalizedKey = canonicalBrakeQuestionKey(rawKey);
    final normalizedValue =
        canonicalizeBrakeWizardAnswerValue(normalizedKey, rawValue);
    if (!_isMeaningfulBrakeAnswer(normalizedValue)) {
      return;
    }

    if (!normalized.containsKey(normalizedKey) || isCanonicalSource) {
      normalized[normalizedKey] = normalizedValue;
    }
  }

  for (final entry in rawAnswers.entries) {
    if (entry.key == '_notes' ||
        canonicalBrakeQuestionKey(entry.key) == entry.key) {
      mergeEntry(entry.key, entry.value, isCanonicalSource: true);
    }
  }

  for (final entry in rawAnswers.entries) {
    if (entry.key != '_notes' &&
        canonicalBrakeQuestionKey(entry.key) != entry.key) {
      mergeEntry(entry.key, entry.value, isCanonicalSource: false);
    }
  }

  return normalized;
}

dynamic canonicalizeBrakeWizardAnswerValue(String key, dynamic rawValue) {
  switch (key) {
    case 'brake_type':
    case 'brake_type_mech':
      return canonicalBrakeTypeValue(rawValue?.toString());
    case 'which_wheel':
      return canonicalBrakeWheelValue(rawValue?.toString());
    case 'fluid_type':
      return canonicalBrakeFluidTypeValue(rawValue?.toString());
    case 'damage_level':
      return canonicalBrakeDamageLevelValue(rawValue?.toString());
    case 'piston_count':
      return canonicalBrakePistonCountValue(rawValue?.toString());
    case 'rotor_size':
      return canonicalBrakeRotorSizeValue(rawValue?.toString());
    case 'symptom':
      if (rawValue is List) {
        final normalized = canonicalizeBrakeSymptomKeys(
          rawValue.map((value) => value.toString()),
        );
        return normalized.isEmpty ? null : normalized;
      }

      final normalized = canonicalBrakeSymptomKey(rawValue?.toString() ?? '');
      return normalized == null ? null : <String>[normalized];
    default:
      return rawValue;
  }
}

String? canonicalBrakeSymptomKey(String rawValue) {
  switch (rawValue) {
    case 'noise':
    case 'suena':
      return 'noise';
    case 'vibration':
      return 'vibration';
    case 'rubbing':
    case 'roza':
      return 'rubbing';
    case 'low_power':
    case 'frena_poco':
      return 'low_power';
    case 'spongy_lever':
    case 'maneta_blanda':
      return 'spongy_lever';
    case 'intermittent':
      return 'intermittent';
    default:
      return null;
  }
}

List<String> canonicalizeBrakeSymptomKeys(Iterable<String> rawValues) {
  final resolved = <String>{};
  for (final rawValue in rawValues) {
    final normalized = canonicalBrakeSymptomKey(rawValue);
    if (normalized != null) {
      resolved.add(normalized);
    }
  }

  return kBrakeSymptomLabels.keys
      .where(resolved.contains)
      .toList(growable: false);
}

String? resolveBrakeSymptomLabel(String rawValue) {
  final canonicalKey = canonicalBrakeSymptomKey(rawValue);
  if (canonicalKey != null) {
    return kBrakeSymptomLabels[canonicalKey];
  }
  if (rawValue == 'desalineado') {
    return 'Desalineado';
  }
  return null;
}

String? _normalizeBrakeText(String? rawValue) {
  if (rawValue == null) {
    return null;
  }

  final normalized = rawValue.trim();
  return normalized.isEmpty ? null : normalized;
}

bool _isMeaningfulBrakeAnswer(dynamic value) {
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
