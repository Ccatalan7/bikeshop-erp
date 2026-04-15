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

const Set<String> kDiagnosisLinkedBrakeWizardQuestionKeys = {
  'pad_condition',
  'pad_contaminated',
  'rotor_condition',
  'damage_level',
  'deviation_severity',
  'contamination_level',
  'symptom',
};

bool isDiagnosisLinkedBrakeQuestionKey(String key) {
  return kDiagnosisLinkedBrakeWizardQuestionKeys.contains(key);
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
