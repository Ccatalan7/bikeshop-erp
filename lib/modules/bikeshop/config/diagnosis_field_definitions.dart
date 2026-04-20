import 'package:flutter/foundation.dart';

import 'brake_canonical_data.dart';
import 'drivetrain_canonical_data.dart';

class DiagnosisFieldDefinition {
  const DiagnosisFieldDefinition({
    required this.key,
    required this.label,
    required this.questionType,
    this.options = const <String, String>{},
  });

  final String key;
  final String label;
  final String questionType;
  final Map<String, String> options;
}

const Map<String, String> kBrakePadConditionOptions = {
  'ok': 'Buen estado',
  'worn': 'Desgastadas - reemplazar',
  'critical': 'Critico - cambio urgente',
};

const Map<String, String> kBrakeRotorConditionOptions = {
  'ok': 'Buen estado',
  'glazed': 'Sucio / contaminado',
  'warped': 'Desviado / roza',
  'replace': 'Reemplazar',
};

const Map<String, String> kBrakeContaminationLevelDiagnosisOptions = {
  'none': 'Sin contaminacion',
  'light': 'Leve',
  'moderate': 'Moderada',
  'severe': 'Severa',
};

const Map<String, DiagnosisFieldDefinition> kDiagnosisFieldDefinitions = {
  'pad_condition': DiagnosisFieldDefinition(
    key: 'pad_condition',
    label: 'Estado de las pastillas',
    questionType: 'single_select',
    options: kBrakePadConditionOptions,
  ),
  'pad_contaminated': DiagnosisFieldDefinition(
    key: 'pad_contaminated',
    label: '¿Pastillas contaminadas con fluido?',
    questionType: 'boolean',
  ),
  'rotor_condition': DiagnosisFieldDefinition(
    key: 'rotor_condition',
    label: 'Condicion del rotor',
    questionType: 'single_select',
    options: kBrakeRotorConditionOptions,
  ),
  'damage_level': DiagnosisFieldDefinition(
    key: 'damage_level',
    label: 'Nivel de danio del rotor',
    questionType: 'single_select',
    options: kBrakeDamageLevelOptions,
  ),
  'contamination_level': DiagnosisFieldDefinition(
    key: 'contamination_level',
    label: 'Nivel de contaminacion',
    questionType: 'single_select',
    options: kBrakeContaminationLevelDiagnosisOptions,
  ),
  'symptom': DiagnosisFieldDefinition(
    key: 'symptom',
    label: 'Sintomas observados',
    questionType: 'multi_select',
    options: kBrakeSymptomLabels,
  ),
  'chain_wear': DiagnosisFieldDefinition(
    key: 'chain_wear',
    label: 'Desgaste de la cadena',
    questionType: 'single_select',
    options: kDrivetrainChainWearOptions,
  ),
  'cable_condition': DiagnosisFieldDefinition(
    key: 'cable_condition',
    label: 'Estado cables y fundas',
    questionType: 'single_select',
    options: kDrivetrainCableConditionOptions,
  ),
};

DiagnosisFieldDefinition? diagnosisFieldDefinitionForKey(String key) {
  return kDiagnosisFieldDefinitions[key];
}

bool isDiagnosisSemanticFieldKey(String key) {
  return kDiagnosisFieldDefinitions.containsKey(key);
}

bool isDiagnosisSemanticQuestionCompatible({
  required String key,
  required String questionType,
  Iterable<String> optionValues = const <String>[],
}) {
  final definition = diagnosisFieldDefinitionForKey(key);
  if (definition == null) {
    return false;
  }

  if (definition.questionType != questionType) {
    return false;
  }

  if (definition.questionType == 'boolean') {
    return true;
  }

  return setEquals(
    definition.options.keys.toSet(),
    optionValues.toSet(),
  );
}
