import '../utils/drivetrain_compatibility_projection.dart';

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
  'shimano_hg_road_11': 'Shimano HG Road 11',
  'microspline': 'Micro Spline',
  'sram_xd': 'SRAM XD',
  'sram_xdr': 'SRAM XDR',
  'campagnolo': 'Campagnolo',
  'campagnolo_n3w': 'Campagnolo N3W',
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
    case 'shimano_hg_road_11':
    case 'shimano hg road 11':
    case 'shimano hg 11 road':
    case 'hg road 11':
    case 'road_11_hg':
      return 'shimano_hg_road_11';
    case 'microspline':
    case 'micro_spline':
    case 'micro spline':
      return 'microspline';
    case 'sram_xd':
    case 'xd':
    case 'sram xd':
      return 'sram_xd';
    case 'sram_xdr':
    case 'xdr':
    case 'sram xdr':
      return 'sram_xdr';
    case 'campagnolo':
      return 'campagnolo';
    case 'campagnolo_n3w':
    case 'n3w':
    case 'campagnolo n3w':
      return 'campagnolo_n3w';
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

String? canonicalDrivetrainWheelPositionValue(String? rawValue) {
  switch (_normalizeDrivetrainText(rawValue)?.toLowerCase()) {
    case 'front':
    case 'front_hub':
    case 'front_wheel':
    case 'delantera':
      return 'front';
    case 'rear':
    case 'rear_hub':
    case 'rear_wheel':
    case 'trasera':
      return 'rear';
    default:
      return null;
  }
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

class DrivetrainProductSpecInferenceResult {
  const DrivetrainProductSpecInferenceResult({
    this.derivedValues = const <String, dynamic>{},
    this.guidanceByField = const <String, String>{},
  });

  final Map<String, dynamic> derivedValues;
  final Map<String, String> guidanceByField;
}

class DrivetrainProductSpecFieldBehavior {
  const DrivetrainProductSpecFieldBehavior({
    this.hidden = false,
    this.enabled = true,
    this.allowedOptions,
    this.helperText,
  });

  final bool hidden;
  final bool enabled;
  final List<String>? allowedOptions;
  final String? helperText;
}

const String kDrivetrainCompatibilityFamilyShimano = 'Ecosistema Shimano';
const String kDrivetrainCompatibilityFamilySram = 'Ecosistema SRAM';
const String kDrivetrainCompatibilityFamilyCampagnolo = 'Ecosistema Campagnolo';
const String kDrivetrainCompatibilityFamilyMicroshift = 'Ecosistema Microshift';
const String kDrivetrainCompatibilityFamilyKmc = 'KMC multicompatible';
const String kDrivetrainCompatibilityFamilyUniversal = 'Universal / generico';
const String kDrivetrainCompatibilityFamilySingleSpeed = 'Single speed / BMX';
const String kDrivetrainCompatibilityFamilyOther = 'Otro';
const String kDrivetrainCompatibilityFamilyUnknown =
    'Desconocido / sin confirmar';
const String kDrivetrainModeDerailleur = 'Derailleur';
const String kDrivetrainModeSingleSpeedBmxIgh = 'Single speed / BMX / IGH';

const Set<String> _kSupportedDrivetrainProductFamilies = {
  'chain',
  'missing_link',
  'chain_link',
  'cassette',
  'freewheel',
  'fixed_cog',
  'rear_derailleur',
  'front_derailleur',
  'shifter',
  'chainring',
  'crankset',
  'drivetrain_kit',
  'chain_guide',
};

DrivetrainProductSpecFieldBehavior resolveDrivetrainProductSpecFieldBehavior({
  required String technicalFamily,
  required String fieldKey,
  required Map<String, dynamic> currentValues,
}) {
  if (fieldKey == 'drivetrain_compatibility_family') {
    return const DrivetrainProductSpecFieldBehavior(
      hidden: true,
      helperText:
          'Campo legado/interino. Usa ecosistema principal y ecosistemas compatibles declarados en lugar de esta mezcla antigua.',
    );
  }

  final normalizedFamily = _normalizeDrivetrainText(technicalFamily)
      ?.toLowerCase()
      .replaceAll(' ', '_');
  final isChainFamily = normalizedFamily == 'chain' ||
      normalizedFamily == 'chain_link' ||
      normalizedFamily == 'missing_link';
  final isRearCogFamily = normalizedFamily == 'cassette' ||
      normalizedFamily == 'freewheel' ||
      normalizedFamily == 'fixed_cog';
  final isCassetteSpacerFamily = normalizedFamily == 'cassette_spacer';
  final isChainringFamily = normalizedFamily == 'chainring';
  final isCranksetFamily = normalizedFamily == 'crankset';
  final isChainGuideFamily = normalizedFamily == 'chain_guide';
  final isShifterFamily = normalizedFamily == 'shifter';
  final isFrontDerailleurFamily = normalizedFamily == 'front_derailleur';
  final isBottomBracketFamily = normalizedFamily == 'bottom_bracket';
  final isHubFamily = normalizedFamily == 'hub' ||
      normalizedFamily == 'hub_generic' ||
      normalizedFamily == 'front_hub' ||
      normalizedFamily == 'rear_hub';
  final normalizedBottomBracketFamily =
      _normalizeDrivetrainText(currentValues['bottom_bracket_family'])
          ?.toLowerCase();
  final isPressfitBottomBracketFamily =
      normalizedBottomBracketFamily?.contains('pressfit') == true ||
          normalizedBottomBracketFamily?.contains('bb30') == true ||
          normalizedBottomBracketFamily?.contains('pf30') == true;
  final isMidBmxBottomBracketFamily =
      normalizedBottomBracketFamily?.contains('mid') == true &&
          normalizedBottomBracketFamily?.contains('bmx') == true;
  final isOnePieceBottomBracketFamily =
      normalizedBottomBracketFamily?.contains('americano') == true ||
          normalizedBottomBracketFamily?.contains('one-piece') == true ||
          normalizedBottomBracketFamily?.contains('one piece') == true;
  final isSquareCartridgeBottomBracketFamily =
      normalizedBottomBracketFamily?.contains('cuadrado') == true ||
          normalizedBottomBracketFamily?.contains('square') == true ||
          normalizedBottomBracketFamily?.contains('cartucho') == true;
  final isExternal24BottomBracketFamily =
      normalizedBottomBracketFamily?.contains('hollowtech') == true ||
          normalizedBottomBracketFamily?.contains('24mm externo') == true ||
          normalizedBottomBracketFamily?.contains('24 mm externo') == true;
  final isThreadedCupBottomBracketFamily =
      normalizedBottomBracketFamily?.contains('bsa') == true ||
          normalizedBottomBracketFamily?.contains('roscado') == true ||
          isSquareCartridgeBottomBracketFamily ||
          isExternal24BottomBracketFamily;
  final hubWheelPosition = canonicalDrivetrainWheelPositionValue(
    currentValues['wheel_position']?.toString(),
  );
  const cassetteBodyFamilyOptions = {
    'Shimano HG',
    'Shimano HG Road 11',
    'Micro Spline',
    'SRAM XD',
    'SRAM XDR',
    'Campagnolo',
    'Campagnolo N3W',
  };
  if (isRearCogFamily) {
    if (fieldKey == 'drivetrain_primary_ecosystem' ||
        fieldKey == 'drivetrain_declared_compatible_ecosystems' ||
        fieldKey == 'drivetrain_platform' ||
        fieldKey == 'drivetrain_compatibility_family') {
      return const DrivetrainProductSpecFieldBehavior(hidden: true);
    }

    if (fieldKey == 'drivetrain_speeds') {
      if (normalizedFamily == 'fixed_cog') {
        return const DrivetrainProductSpecFieldBehavior(
          enabled: false,
          allowedOptions: ['1'],
          helperText:
              'Un pinon fijo trabaja como 1v. No lo mezcles con coberturas multi-velocidad.',
        );
      }

      return DrivetrainProductSpecFieldBehavior(
        helperText: normalizedFamily == 'cassette'
            ? 'La velocidad trasera es obligatoria, pero no basta sin el driver/freehub exacto y el rango real del conjunto.'
            : 'Confirma la cantidad real de velocidades de la rueda libre; no la dejes implicita aunque el montaje sea roscado.',
      );
    }

    if (fieldKey == 'freehub_type') {
      if (normalizedFamily == 'cassette') {
        return DrivetrainProductSpecFieldBehavior(
          allowedOptions:
              _sortDrivetrainOptionLabels(cassetteBodyFamilyOptions),
          helperText:
              'Confirma el driver exacto del cassette. Velocidad sola no resuelve cuerpos, generaciones, largos ni separadores (por ejemplo HG vs HG Road 11, o XD vs XDR).',
        );
      }

      if (normalizedFamily == 'freewheel') {
        return const DrivetrainProductSpecFieldBehavior(
          enabled: true,
          allowedOptions: ['Rueda libre roscada'],
          helperText:
              'Confirma explicitamente el montaje roscado en la ficha. La categoria comercial no reemplaza este dato tecnico.',
        );
      }

      return DrivetrainProductSpecFieldBehavior(
        allowedOptions: _sortDrivetrainOptionLabels(const {
          'Rosca fija / contratuerca',
          'Driver BMX',
          'Maza contrapedal',
        }),
        helperText:
            'No mezcles rosca fija, driver BMX y contrapedal como si fueran el mismo soporte de pinon simple.',
      );
    }

    if (fieldKey == 'largest_cog_teeth') {
      if (normalizedFamily == 'fixed_cog') {
        return const DrivetrainProductSpecFieldBehavior(hidden: true);
      }

      return DrivetrainProductSpecFieldBehavior(
        helperText: normalizedFamily == 'cassette'
            ? 'Captura el pinon mayor real. Aunque velocidad y driver coincidan, el rango debe cruzarse con capacidad del cambio y excepciones del cuerpo.'
            : 'Captura el pinon mayor real. Aunque la rueda libre sea roscada, el rango sigue afectando la compatibilidad funcional del cambio.',
      );
    }
  }

  if (isCassetteSpacerFamily) {
    if (fieldKey == 'freehub_type') {
      return DrivetrainProductSpecFieldBehavior(
        allowedOptions: _sortDrivetrainOptionLabels(cassetteBodyFamilyOptions),
        helperText:
            'Confirma la familia real del cuerpo del cassette. Un espaciador no es universal solo por decir “Shimano-compatible”: siguen existiendo diferencias de largo, generacion y montaje.',
      );
    }

    if (fieldKey == 'spacer_thickness_mm') {
      return const DrivetrainProductSpecFieldBehavior(
        helperText:
            'Registra el espesor real en mm. Los espaciadores de cassette resuelven casos concretos de cuerpo/generacion y no deben tratarse como una pieza universal.',
      );
    }
  }

  if (isHubFamily) {
    if (fieldKey == 'wheel_position') {
      if (normalizedFamily == 'front_hub') {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          enabled: false,
          allowedOptions: ['front'],
          helperText:
              'La maza ya queda fijada como delantera por la plantilla.',
        );
      }
      if (normalizedFamily == 'rear_hub') {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          enabled: false,
          allowedOptions: ['rear'],
          helperText: 'La maza ya queda fijada como trasera por la plantilla.',
        );
      }

      return const DrivetrainProductSpecFieldBehavior(
        helperText:
            'Confirma primero si la maza es delantera o trasera. Esa decision define el OLD valido y si corresponde o no un driver/freehub trasero.',
      );
    }

    if (fieldKey == 'hub_spacing_mm') {
      if (normalizedFamily == 'front_hub' || hubWheelPosition == 'front') {
        return const DrivetrainProductSpecFieldBehavior(
          allowedOptions: ['100', '110'],
          helperText:
              'Usa medidas delanteras estandarizadas. En este backbone la maza delantera debe declararse como 100 o 110 mm.',
        );
      }

      if (normalizedFamily == 'rear_hub' || hubWheelPosition == 'rear') {
        return const DrivetrainProductSpecFieldBehavior(
          allowedOptions: ['130', '135', '142', '148'],
          helperText:
              'Usa medidas traseras estandarizadas. En este backbone la maza trasera debe declararse como 130, 135, 142 o 148 mm.',
        );
      }

      return const DrivetrainProductSpecFieldBehavior(
        allowedOptions: ['100', '110', '130', '135', '142', '148'],
        helperText:
            'Confirma la posicion primero. Mezclar OLD delantero y trasero en un mismo campo abierto degrada la compatibilidad upstream.',
      );
    }

    if (fieldKey == 'freehub_type') {
      if (normalizedFamily == 'front_hub' || hubWheelPosition == 'front') {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          helperText: 'Una maza delantera no usa driver/freehub trasero.',
        );
      }

      if (hubWheelPosition == null && normalizedFamily != 'rear_hub') {
        return DrivetrainProductSpecFieldBehavior(
          enabled: false,
          allowedOptions: _sortDrivetrainOptionLabels(const {
            ...cassetteBodyFamilyOptions,
            'Rueda libre roscada',
            'Driver BMX',
            'Rosca fija / contratuerca',
            'Maza contrapedal',
          }),
          helperText:
              'Primero confirma si la maza es trasera. Solo entonces tiene sentido filtrar la familia real del cuerpo.',
        );
      }

      return DrivetrainProductSpecFieldBehavior(
        allowedOptions: _sortDrivetrainOptionLabels(const {
          ...cassetteBodyFamilyOptions,
          'Rueda libre roscada',
          'Driver BMX',
          'Rosca fija / contratuerca',
          'Maza contrapedal',
        }),
        helperText:
            'Confirma la familia real del cuerpo trasero. Shimano HG, HG Road 11, XD/XDR y Campagnolo/N3W no deben colapsarse en una sola opcion gruesa.',
      );
    }
  }

  if (isBottomBracketFamily) {
    if (fieldKey == 'bb_thread_standard') {
      if (isPressfitBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          helperText:
              'Las familias Pressfit y BB30/PF30 se distinguen por el diámetro del bore/caja, no por una rosca de copas.',
        );
      }

      if (isMidBmxBottomBracketFamily || isOnePieceBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          helperText:
              'Mid/BMX y one-piece/americano no deben mezclar un estándar de rosca de copas como si fueran cajas roscadas BSA o italianas.',
        );
      }
    }

    if (fieldKey == 'spindle_interface') {
      if (isExternal24BottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          enabled: false,
          allowedOptions: ['Hollowtech / 24mm'],
          helperText:
              'La familia Hollowtech / 24mm externo ya fija la interfaz del eje. No la abras de nuevo a BMX, ISIS u otras familias incompatibles.',
        );
      }

      if (isSquareCartridgeBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          allowedOptions: ['Cuadrado JIS', 'Cuadrado ISO'],
          helperText:
              'Un cartucho cuadrado debe declararse como JIS o ISO; no mezcles esta familia con Hollowtech, ISIS o BMX.',
        );
      }

      if (isMidBmxBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          allowedOptions: ['BMX 19mm', 'BMX 22mm', 'BMX 24mm'],
          helperText:
              'Mid / BMX debe quedarse dentro de interfaces BMX reales. No abras esta familia a estándares de ruta/MTB ajenos.',
        );
      }

      if (isOnePieceBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          enabled: false,
          allowedOptions: ['One-piece / americano'],
          helperText:
              'La familia americano / one-piece ya fija la interfaz del eje.',
        );
      }
    }

    if (fieldKey == 'bb_shell_diameter_mm') {
      if (isPressfitBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          helperText:
              'En familias Pressfit y BB30/PF30 confirma el diámetro real del bore/caja. Ese diámetro sí es parte del estándar, no un dato decorativo.',
        );
      }

      if (isThreadedCupBottomBracketFamily) {
        return const DrivetrainProductSpecFieldBehavior(
          hidden: true,
          helperText:
              'En familias roscadas o de copas externas manda el estándar de rosca y el ancho de caja; no dejes un diámetro de bore como si fuera la seam principal.',
        );
      }
    }

    if ((fieldKey == 'spindle_length_mm' ||
            fieldKey == 'spindle_diameter_mm') &&
        isExternal24BottomBracketFamily) {
      return const DrivetrainProductSpecFieldBehavior(
        hidden: true,
        helperText:
            'En sistemas Hollowtech / 24mm externos la compatibilidad gira primero sobre familia de shell/copa, no sobre un largo o diámetro suelto del spindle.',
      );
    }
  }

  if (isChainringFamily || isCranksetFamily) {
    if (fieldKey == 'drivetrain_primary_ecosystem' ||
        fieldKey == 'drivetrain_declared_compatible_ecosystems' ||
        fieldKey == 'drivetrain_compatibility_family') {
      return const DrivetrainProductSpecFieldBehavior(hidden: true);
    }
  }

  if (isChainGuideFamily) {
    if (fieldKey == 'drivetrain_primary_ecosystem' ||
        fieldKey == 'drivetrain_declared_compatible_ecosystems' ||
        fieldKey == 'drivetrain_platform' ||
        fieldKey == 'drivetrain_compatibility_family') {
      return const DrivetrainProductSpecFieldBehavior(hidden: true);
    }
  }

  if (isShifterFamily) {
    final shifterPosition = canonicalDrivetrainShifterPositionLabel(
        currentValues['shifter_position']);

    const rearSideShifterFieldKeys = {
      'drivetrain_speeds',
      'rear_cog_count',
      'shift_actuation_family',
      'drivetrain_platform',
    };

    if (shifterPosition == 'Izquierdo / delantero' &&
        rearSideShifterFieldKeys.contains(fieldKey)) {
      return const DrivetrainProductSpecFieldBehavior(
        hidden: true,
        helperText:
            'Un shifter delantero usa cantidad de platos y no debe reutilizar las costuras exactas del indexado/plataforma trasera.',
      );
    }

    if (fieldKey == 'front_chainring_count' &&
        shifterPosition == 'Derecho / trasero') {
      return const DrivetrainProductSpecFieldBehavior(
        hidden: true,
        helperText:
            'Un shifter trasero usa velocidades traseras, no cantidad de platos.',
      );
    }
  }

  if (isFrontDerailleurFamily && fieldKey == 'front_derailleur_clamp_mm') {
    final mountType = canonicalFrontDerailleurMountTypeLabel(
      currentValues['front_derailleur_mount_type'],
    );

    if (mountType == 'Braze-on' ||
        mountType == 'Direct mount' ||
        mountType == 'E-type') {
      return DrivetrainProductSpecFieldBehavior(
        hidden: true,
        helperText:
            'El diametro de abrazadera no aplica cuando el desviador delantero usa montaje $mountType.',
      );
    }

    if (mountType == 'Abrazadera') {
      return const DrivetrainProductSpecFieldBehavior(
        helperText:
            'Confirma el diametro real de la abrazadera solo cuando el desviador es de montaje con abrazadera.',
      );
    }
  }

  if (isFrontDerailleurFamily && fieldKey == 'front_chainring_count') {
    return const DrivetrainProductSpecFieldBehavior(
      allowedOptions: ['2', '3'],
      helperText:
          'Un desviador delantero solo tiene sentido en transmisiones 2x o 3x; en 1x esta costura no aplica.',
    );
  }

  if (isFrontDerailleurFamily &&
      (fieldKey == 'drivetrain_primary_ecosystem' ||
          fieldKey == 'drivetrain_compatibility_family' ||
          fieldKey == 'drivetrain_declared_compatible_ecosystems')) {
    return DrivetrainProductSpecFieldBehavior(
      allowedOptions: _sortDrivetrainOptionLabels(const {
        'Ecosistema Shimano',
        'Ecosistema SRAM',
        'Ecosistema Campagnolo',
        'Ecosistema Microshift',
        'Universal / generico',
        'Otro',
        'Desconocido / sin confirmar',
      }),
      helperText:
          'Un desviador delantero solo aplica a transmisiones de varios platos; Single speed / BMX no pertenece a esta ficha.',
    );
  }

  if (isFrontDerailleurFamily && fieldKey == 'drivetrain_platform') {
    return DrivetrainProductSpecFieldBehavior(
      allowedOptions: _sortDrivetrainOptionLabels(const {
        'Shimano HG / SIS',
        'Shimano Hyperglide+',
        'Shimano Linkglide / CUES',
        'SRAM FlatTop / AXS road',
        'Campagnolo',
        'Microshift Advent / Acolyte',
        'Friccion / universal',
        'Generico compatible',
        'Desconocido / sin confirmar',
      }),
      helperText:
          'Un desviador delantero no debe declararse contra plataformas 1x-only como Single speed / BMX, SRAM Eagle o SRAM T-Type.',
    );
  }

  if (!isChainFamily) {
    return const DrivetrainProductSpecFieldBehavior();
  }

  final widthFamily = canonicalDrivetrainChainWidthFamilyLabel(
    currentValues['chain_width_family'],
  );
  final outerWidthMm = canonicalDrivetrainChainOuterWidthMm(
    currentValues['chain_outer_width_mm'],
  );
  final explicitMode = canonicalDrivetrainModeLabel(
    currentValues['drivetrain_mode'],
  );
  final speedLabels = _extractDrivetrainProductSpeedLabels(
    currentValues['chain_speeds'] ??
        currentValues['chain_speed'] ??
        currentValues['drivetrain_speeds'],
  );
  final explicitProfiles = _extractDrivetrainProductProfileLabels(
    currentValues['chain_profile_family'],
  );
  final explicitPlatform = canonicalDrivetrainProductPlatformLabel(
    currentValues['drivetrain_platform'],
  );
  final explicitPrimaryEcosystem = canonicalDrivetrainCompatibilityFamilyLabel(
    currentValues['drivetrain_primary_ecosystem'],
  );
  final explicitDeclaredCompatibleEcosystems =
      _extractDrivetrainCompatibilityFamilyLabels(
    currentValues['drivetrain_declared_compatible_ecosystems'],
  );
  final legacyCompatibilityFamilies =
      _extractDrivetrainCompatibilityFamilyLabels(
    currentValues['drivetrain_compatibility_family'],
  );
  final explicitCompatibilityFamilies = <String>{
    if (explicitPrimaryEcosystem != null) explicitPrimaryEcosystem,
    ...explicitDeclaredCompatibleEcosystems,
    if (explicitPrimaryEcosystem == null &&
        explicitDeclaredCompatibleEcosystems.isEmpty)
      ...legacyCompatibilityFamilies,
  };
  final derivedCompatibilityFamilies =
      _deriveStructuredDrivetrainCompatibilityFamilies(
    widthFamily: widthFamily,
    speedLabels: speedLabels,
    explicitProfiles: explicitProfiles,
    explicitPlatform: explicitPlatform,
    shiftActuationValue: currentValues['shift_actuation_family'],
  );
  final effectiveCompatibilityFamilies =
      explicitCompatibilityFamilies.isNotEmpty
          ? explicitCompatibilityFamilies
          : derivedCompatibilityFamilies;
  final derivedMode = _deriveDrivetrainModeLabel(
    widthFamily: widthFamily,
    speedLabels: speedLabels,
    explicitProfiles: explicitProfiles,
    explicitPlatform: explicitPlatform,
    compatibilityFamilies: effectiveCompatibilityFamilies,
    shiftActuationValue: currentValues['shift_actuation_family'],
  );
  final effectiveMode = explicitMode ?? derivedMode;

  if (fieldKey == 'drivetrain_mode') {
    if (derivedMode == null) {
      return const DrivetrainProductSpecFieldBehavior();
    }
    return DrivetrainProductSpecFieldBehavior(
      hidden: true,
      enabled: false,
      allowedOptions: [derivedMode],
      helperText: derivedMode == kDrivetrainModeSingleSpeedBmxIgh
          ? 'El modo queda fijado por señales single speed / BMX / IGH ya declaradas en la ficha.'
          : 'El modo queda fijado por velocidades, plataforma, indexado o ecosistema ya declarados.',
    );
  }

  if (fieldKey == 'drivetrain_primary_ecosystem' ||
      fieldKey == 'drivetrain_compatibility_family') {
    if (effectiveMode == kDrivetrainModeSingleSpeedBmxIgh) {
      return const DrivetrainProductSpecFieldBehavior(
        enabled: false,
        allowedOptions: [kDrivetrainCompatibilityFamilySingleSpeed],
        helperText:
            'En modo single speed / BMX / IGH, el ecosistema principal queda fijado como Single speed / BMX.',
      );
    }

    final suggestedPrimaryEcosystems = derivedCompatibilityFamilies
        .where((label) => label != kDrivetrainCompatibilityFamilyKmc)
        .toSet();
    if (suggestedPrimaryEcosystems.isNotEmpty) {
      return DrivetrainProductSpecFieldBehavior(
        helperText: suggestedPrimaryEcosystems.length > 1
            ? 'Senales estructuradas del producto sugieren ${_sortDrivetrainOptionLabels(suggestedPrimaryEcosystems).join(' / ')}, pero el ecosistema principal sigue siendo una confirmacion manual upstream.'
            : 'Senales estructuradas del producto sugieren ${suggestedPrimaryEcosystems.first}, pero el ecosistema principal sigue siendo una confirmacion manual upstream.',
      );
    }
    return const DrivetrainProductSpecFieldBehavior();
  }

  if (fieldKey == 'drivetrain_declared_compatible_ecosystems') {
    return DrivetrainProductSpecFieldBehavior(
      helperText: effectiveMode == kDrivetrainModeSingleSpeedBmxIgh
          ? 'Usa este campo solo si la caja realmente declara compatibilidad cruzada. En single speed / BMX / IGH normalmente no aplica.'
          : 'Usa este campo solo para claims explícitos como “Compatible Shimano”; no dupliques aquí el ecosistema principal.',
    );
  }

  if (fieldKey == 'chain_speeds' || fieldKey == 'chain_speed') {
    final allowedSpeeds = _buildAllowedChainSpeedOptions(
      widthFamily: widthFamily,
      outerWidthMm: outerWidthMm,
      speedLabels: speedLabels,
      explicitPlatform: explicitPlatform,
      drivetrainMode: effectiveMode,
    );
    if (allowedSpeeds.isEmpty) {
      return const DrivetrainProductSpecFieldBehavior();
    }

    return DrivetrainProductSpecFieldBehavior(
      enabled: allowedSpeeds.length > 1,
      allowedOptions: _sortDrivetrainOptionLabels(allowedSpeeds),
      helperText: allowedSpeeds.length > 1
          ? 'Velocidades filtradas desde ancho y plataforma para evitar mezclar coberturas incompatibles.'
          : 'La cobertura de velocidades queda fijada por el ancho y la compatibilidad upstream declarada.',
    );
  }

  if (fieldKey == 'drivetrain_platform') {
    if (_shouldHideChainPlatformField(
      widthFamily: widthFamily,
      speedLabels: speedLabels,
      explicitPlatform: explicitPlatform,
      drivetrainMode: effectiveMode,
    )) {
      return const DrivetrainProductSpecFieldBehavior(hidden: true);
    }

    final allowedPlatforms = _buildAllowedChainPlatformOptions(
      widthFamily: widthFamily,
      speedLabels: speedLabels,
      explicitPlatform: explicitPlatform,
      drivetrainMode: effectiveMode,
      compatibilityFamilies: effectiveCompatibilityFamilies,
    );
    if (allowedPlatforms.isEmpty) {
      return const DrivetrainProductSpecFieldBehavior();
    }

    return DrivetrainProductSpecFieldBehavior(
      enabled: allowedPlatforms.length > 1,
      allowedOptions: _sortDrivetrainOptionLabels(allowedPlatforms),
      helperText: allowedPlatforms.length > 1
          ? 'Opciones filtradas desde ancho, velocidades, familia y perfil para no mezclar ecosistemas incompatibles.'
          : 'La plataforma queda fijada por la compatibilidad ya declarada en este producto.',
    );
  }

  if (fieldKey == 'chain_outer_width_mm') {
    if (effectiveMode == kDrivetrainModeSingleSpeedBmxIgh ||
        widthFamily == '1/8' ||
        explicitPlatform == 'Single speed / BMX') {
      return const DrivetrainProductSpecFieldBehavior(hidden: true);
    }

    final allowedOuterWidths = _buildAllowedChainOuterWidthOptions(
      widthFamily: widthFamily,
      speedLabels: speedLabels,
      explicitPlatform: explicitPlatform,
      drivetrainMode: effectiveMode,
    );
    if (allowedOuterWidths.isEmpty) {
      return const DrivetrainProductSpecFieldBehavior();
    }

    return DrivetrainProductSpecFieldBehavior(
      enabled: allowedOuterWidths.length > 1,
      allowedOptions: _sortDrivetrainOptionLabels(allowedOuterWidths),
      helperText: widthFamily == '11/128'
          ? '11/128 solo fija el ancho interno. Usa el ancho externo nominal para distinguir 9/10/11/12v y evitar perfiles universales falsos.'
          : 'Ayuda a distinguir coberturas reales dentro de la misma familia 3/32 sin mezclar cadenas demasiado anchas o demasiado angostas.',
    );
  }

  if (fieldKey == 'chain_profile_family') {
    final allowedProfiles = _buildAllowedChainProfileOptions(
      widthFamily: widthFamily,
      outerWidthMm: outerWidthMm,
      speedLabels: speedLabels,
      explicitProfiles: explicitProfiles,
      explicitPlatform: explicitPlatform,
      drivetrainMode: effectiveMode,
      compatibilityFamilies: effectiveCompatibilityFamilies,
    );
    if (allowedProfiles.isEmpty) {
      return const DrivetrainProductSpecFieldBehavior();
    }

    return DrivetrainProductSpecFieldBehavior(
      enabled: allowedProfiles.length > 1,
      allowedOptions: _sortDrivetrainOptionLabels(allowedProfiles),
      helperText: allowedProfiles.length > 1
          ? 'Perfiles filtrados desde ancho, velocidades, familia y plataforma para evitar combinaciones tecnicamente debiles.'
          : 'El perfil queda fijado por la compatibilidad upstream ya confirmada.',
    );
  }

  return const DrivetrainProductSpecFieldBehavior();
}

DrivetrainProductSpecInferenceResult inferDrivetrainProductSpecValues({
  required String technicalFamily,
  required Map<String, dynamic> currentValues,
}) {
  final normalizedFamily = _normalizeDrivetrainText(technicalFamily)
      ?.toLowerCase()
      .replaceAll(' ', '_');
  if (normalizedFamily == null ||
      !_kSupportedDrivetrainProductFamilies.contains(normalizedFamily)) {
    return const DrivetrainProductSpecInferenceResult();
  }

  final isChainFamily = normalizedFamily == 'chain' ||
      normalizedFamily == 'missing_link' ||
      normalizedFamily == 'chain_link';

  final derivedValues = <String, dynamic>{};
  final guidanceByField = <String, String>{};

  final widthFamily = canonicalDrivetrainChainWidthFamilyLabel(
    currentValues['chain_width_family'],
  );
  final outerWidthMm = canonicalDrivetrainChainOuterWidthMm(
    currentValues['chain_outer_width_mm'],
  );
  final explicitMode = canonicalDrivetrainModeLabel(
    currentValues['drivetrain_mode'],
  );
  final explicitSpeeds = _extractDrivetrainProductSpeedLabels(
    currentValues['chain_speeds'] ?? currentValues['chain_speed'],
  );
  final explicitProfiles = _extractDrivetrainProductProfileLabels(
    currentValues['chain_profile_family'],
  );
  final explicitPlatform = canonicalDrivetrainProductPlatformLabel(
    currentValues['drivetrain_platform'],
  );
  final explicitPrimaryEcosystem = canonicalDrivetrainCompatibilityFamilyLabel(
    currentValues['drivetrain_primary_ecosystem'],
  );
  final explicitDeclaredCompatibleEcosystems =
      _extractDrivetrainCompatibilityFamilyLabels(
    currentValues['drivetrain_declared_compatible_ecosystems'],
  );
  final legacyCompatibilityFamilies =
      _extractDrivetrainCompatibilityFamilyLabels(
    currentValues['drivetrain_compatibility_family'],
  );
  final explicitCompatibilityFamilies = <String>{
    if (explicitPrimaryEcosystem != null) explicitPrimaryEcosystem,
    ...explicitDeclaredCompatibleEcosystems,
    if (explicitPrimaryEcosystem == null &&
        explicitDeclaredCompatibleEcosystems.isEmpty)
      ...legacyCompatibilityFamilies,
  };
  final derivedCompatibilityFamilies =
      _deriveStructuredDrivetrainCompatibilityFamilies(
    widthFamily: widthFamily,
    speedLabels: explicitSpeeds,
    explicitProfiles: explicitProfiles,
    explicitPlatform: explicitPlatform,
    shiftActuationValue: currentValues['shift_actuation_family'],
  );
  final derivedMode = _deriveDrivetrainModeLabel(
    widthFamily: widthFamily,
    speedLabels: explicitSpeeds,
    explicitProfiles: explicitProfiles,
    explicitPlatform: explicitPlatform,
    compatibilityFamilies: explicitCompatibilityFamilies.isNotEmpty
        ? explicitCompatibilityFamilies
        : derivedCompatibilityFamilies,
    shiftActuationValue: currentValues['shift_actuation_family'],
  );
  final effectiveMode = explicitMode ?? derivedMode;

  if (!_isMeaningfulDrivetrainProductSpecValue(
        currentValues['drivetrain_mode'],
      ) &&
      derivedMode != null) {
    derivedValues['drivetrain_mode'] = derivedMode;
    guidanceByField['drivetrain_mode'] = derivedMode ==
            kDrivetrainModeSingleSpeedBmxIgh
        ? 'Autocompletado desde señales single speed / BMX / IGH ya confirmadas en la ficha.'
        : 'Autocompletado desde velocidades, plataforma, indexado o ecosistema ya confirmados.';
  }

  final suggestedPrimaryEcosystems = derivedCompatibilityFamilies
      .where((label) => label != kDrivetrainCompatibilityFamilyKmc)
      .toSet();
  if (!_isMeaningfulDrivetrainProductSpecValue(
    currentValues['drivetrain_primary_ecosystem'],
  )) {
    if (effectiveMode == kDrivetrainModeSingleSpeedBmxIgh) {
      derivedValues['drivetrain_primary_ecosystem'] =
          kDrivetrainCompatibilityFamilySingleSpeed;
      guidanceByField['drivetrain_primary_ecosystem'] =
          'Autocompletado desde el modo single speed / BMX / IGH.';
    } else if (suggestedPrimaryEcosystems.isNotEmpty) {
      guidanceByField['drivetrain_primary_ecosystem'] =
          'Sugerido desde ${_compatibilityFamilyInferenceReasons(
        explicitPlatform: explicitPlatform,
        explicitProfiles: explicitProfiles,
        shiftActuationValue: currentValues['shift_actuation_family'],
        widthFamily: widthFamily,
        speedLabels: explicitSpeeds,
      ).join(' + ')}: ${_sortDrivetrainOptionLabels(suggestedPrimaryEcosystems).join(' / ')}.';
    }
  }

  if (!_isMeaningfulDrivetrainProductSpecValue(
        currentValues['drivetrain_declared_compatible_ecosystems'],
      ) &&
      legacyCompatibilityFamilies.length > 1) {
    final migratedClaims = legacyCompatibilityFamilies
        .where((label) => label != kDrivetrainCompatibilityFamilyKmc)
        .toList(growable: false);
    if (migratedClaims.length > 1) {
      guidanceByField['drivetrain_declared_compatible_ecosystems'] =
          'El valor legado mezclaba varios ecosistemas. Revisa aquí solo los claims explícitos que el empaque realmente declara.';
    }
  }

  if (!isChainFamily) {
    return DrivetrainProductSpecInferenceResult(
      derivedValues: derivedValues,
      guidanceByField: guidanceByField,
    );
  }

  List<String>? inferredSpeeds;
  String? speedReason;
  final outerWidthDerivedSpeeds = _deriveChainSpeedOptionsFromOuterWidthMm(
    outerWidthMm,
  );
  if (explicitSpeeds.isEmpty) {
    if (effectiveMode == kDrivetrainModeSingleSpeedBmxIgh) {
      inferredSpeeds = const ['1'];
      speedReason = 'modo single speed / BMX / IGH';
    } else {
      switch (widthFamily) {
        case '1/8':
          inferredSpeeds = const ['1'];
          speedReason = 'ancho 1/8';
          break;
        case '3/32':
          final constrainedOuterWidthSpeeds = outerWidthDerivedSpeeds
              .where((label) => const {'5', '6', '7', '8'}.contains(label))
              .toList(growable: false);
          if (constrainedOuterWidthSpeeds.isNotEmpty) {
            inferredSpeeds = constrainedOuterWidthSpeeds;
            speedReason =
                'ancho externo nominal ${_formatDrivetrainChainOuterWidthMm(outerWidthMm!)} mm dentro de familia 3/32';
            break;
          }
          inferredSpeeds = const ['5', '6', '7', '8'];
          speedReason = 'ancho 3/32';
          break;
        case '11/128':
          if (outerWidthDerivedSpeeds.isNotEmpty) {
            inferredSpeeds =
                _sortDrivetrainOptionLabels(outerWidthDerivedSpeeds);
            speedReason =
                'ancho externo nominal ${_formatDrivetrainChainOuterWidthMm(outerWidthMm!)} mm';
          }
          break;
      }
    }
  }

  if (inferredSpeeds != null) {
    derivedValues['chain_speeds'] = inferredSpeeds;
    guidanceByField['chain_speeds'] =
        'Autocompletado desde $speedReason: ${inferredSpeeds.join('/')}v. Corrigelo si el fabricante declara otra cobertura.';
  }

  final effectiveSpeeds =
      explicitSpeeds.isNotEmpty ? explicitSpeeds : <String>{...?inferredSpeeds};

  final inferredProfiles = <String>[];
  final profileReasons = <String>[];

  void addProfile(String label, String reason) {
    if (!inferredProfiles.contains(label)) {
      inferredProfiles.add(label);
      profileReasons.add(reason);
    }
  }

  switch (explicitPlatform) {
    case 'Shimano Hyperglide+':
      addProfile('Shimano HG+', 'plataforma Shimano Hyperglide+');
      break;
    case 'Shimano Linkglide / CUES':
      addProfile(
        'Shimano Linkglide / CUES',
        'plataforma Shimano Linkglide / CUES',
      );
      break;
    case 'SRAM Eagle':
      addProfile('SRAM Eagle', 'plataforma SRAM Eagle');
      break;
    case 'SRAM FlatTop / AXS road':
      addProfile('SRAM FlatTop', 'plataforma SRAM FlatTop / AXS road');
      break;
    case 'SRAM T-Type Transmission':
      addProfile('SRAM T-Type', 'plataforma SRAM T-Type Transmission');
      break;
    case 'Campagnolo':
      addProfile('Campagnolo', 'plataforma Campagnolo');
      break;
    case 'Single speed / BMX':
      addProfile('Single speed / BMX', 'plataforma Single speed / BMX');
      break;
  }

  if (widthFamily == '1/8') {
    addProfile('Single speed / BMX', 'ancho 1/8');
  } else if (widthFamily == '3/32') {
    if (outerWidthMm == null &&
        (effectiveSpeeds.isEmpty ||
            _drivetrainSpeedLabelsWithin(
              effectiveSpeeds,
              const {'5', '6', '7', '8'},
            ))) {
      addProfile(
        'Universal 5-8v',
        effectiveSpeeds.isEmpty ? 'ancho 3/32' : 'ancho 3/32 + 5/6/7/8v',
      );
    }
  } else if (widthFamily == '11/128') {
    if (outerWidthMm == null &&
        effectiveSpeeds.isEmpty &&
        explicitPlatform == null) {
      guidanceByField['chain_outer_width_mm'] =
          '11/128 solo fija el ancho interno. Confirma el ancho externo nominal para resolver si la cadena es 9v, 10v, 11v o una cadena mas estrecha de 12v.';
    }
  }

  final hasLegacyKmcCompatibility = legacyCompatibilityFamilies.contains(
    kDrivetrainCompatibilityFamilyKmc,
  );
  if (hasLegacyKmcCompatibility &&
      inferredProfiles.isNotEmpty &&
      !inferredProfiles.contains('Single speed / BMX') &&
      !_drivetrainSpeedLabelsContainAny(effectiveSpeeds, const {'12', '13'})) {
    addProfile('KMC compatible', 'compatibilidad KMC legada');
  }

  if (!_isMeaningfulDrivetrainProductSpecValue(
        currentValues['chain_profile_family'],
      ) &&
      inferredProfiles.isNotEmpty) {
    derivedValues['chain_profile_family'] = inferredProfiles;
    guidanceByField['chain_profile_family'] =
        'Sugerido desde ${profileReasons.join(' + ')}: ${inferredProfiles.join(' / ')}. Corrigelo si la caja declara HG+, Linkglide, Eagle, FlatTop, T-Type u otra familia especifica.';
  } else if (widthFamily == '11/128' &&
      outerWidthMm != null &&
      explicitPlatform == null &&
      !_isMeaningfulDrivetrainProductSpecValue(
        currentValues['chain_profile_family'],
      )) {
    guidanceByField['chain_profile_family'] =
        'El ancho externo ${_formatDrivetrainChainOuterWidthMm(outerWidthMm)} mm ayuda a fijar la velocidad real, pero no basta para asumir un perfil universal. Confirma si la caja declara HG+, Linkglide / CUES, Eagle, FlatTop, T-Type, Campagnolo u otra plataforma especifica.';
  } else if (widthFamily == '11/128' &&
      _drivetrainSpeedLabelsContainAny(effectiveSpeeds, const {'12', '13'}) &&
      explicitPlatform == null) {
    guidanceByField['chain_profile_family'] =
        'No se autocompleta con 12/13v angosta sin una plataforma explicita. Confirma si la caja declara HG+, Linkglide / CUES, Eagle, FlatTop, T-Type o Campagnolo.';
  }

  if (widthFamily == '11/128' &&
      explicitSpeeds.isEmpty &&
      outerWidthMm == null &&
      !guidanceByField.containsKey('chain_speeds')) {
    guidanceByField['chain_speeds'] =
        '11/128 no basta por si solo: confirma ancho externo nominal o velocidad declarada por fabricante antes de asumir 9/10/11/12v.';
  }

  if (!_isMeaningfulDrivetrainProductSpecValue(
        currentValues['drivetrain_mode'],
      ) &&
      !derivedValues.containsKey('drivetrain_mode')) {
    final resolvedProfilesForMode = explicitProfiles.isNotEmpty
        ? explicitProfiles
        : inferredProfiles.toSet();
    final resolvedCompatibilityFamiliesForMode =
        explicitCompatibilityFamilies.isNotEmpty
            ? explicitCompatibilityFamilies
            : _deriveStructuredDrivetrainCompatibilityFamilies(
                widthFamily: widthFamily,
                speedLabels: effectiveSpeeds,
                explicitProfiles: resolvedProfilesForMode,
                explicitPlatform: explicitPlatform,
                shiftActuationValue: currentValues['shift_actuation_family'],
              );
    final inferredModeFromResolvedSignals = _deriveDrivetrainModeLabel(
      widthFamily: widthFamily,
      speedLabels: effectiveSpeeds,
      explicitProfiles: resolvedProfilesForMode,
      explicitPlatform: explicitPlatform,
      compatibilityFamilies: resolvedCompatibilityFamiliesForMode,
      shiftActuationValue: currentValues['shift_actuation_family'],
    );
    if (inferredModeFromResolvedSignals != null) {
      derivedValues['drivetrain_mode'] = inferredModeFromResolvedSignals;
      guidanceByField['drivetrain_mode'] = inferredModeFromResolvedSignals ==
              kDrivetrainModeSingleSpeedBmxIgh
          ? 'Autocompletado desde señales single speed / BMX / IGH confirmadas tras resolver ancho, perfil y velocidades.'
          : 'Autocompletado desde el conjunto resuelto de ancho, perfil y velocidades de cadena.';
    }
  }

  if (!guidanceByField.containsKey('chain_width_family') &&
      widthFamily != null) {
    switch (widthFamily) {
      case '1/8':
        guidanceByField['chain_width_family'] =
            '1/8 suele corresponder a single speed / BMX. 3/32 tambien existe en algunas configuraciones simples, pero no es la opcion base aqui.';
        break;
      case '3/32':
        guidanceByField['chain_width_family'] =
            '3/32 suele cubrir cadenas 5-8v. Si el fabricante declara una familia mas precisa, confirmala en perfil de cadena.';
        break;
      case '11/128':
        guidanceByField['chain_width_family'] =
            '11/128 solo fija la familia angosta moderna. El ancho externo nominal sigue siendo necesario para distinguir 9/10/11/12v y decidir si existe una compatibilidad realmente universal.';
        break;
    }
  }

  if (!guidanceByField.containsKey('chain_outer_width_mm') &&
      outerWidthMm != null) {
    guidanceByField['chain_outer_width_mm'] = widthFamily == '11/128'
        ? 'Ancho externo nominal ${_formatDrivetrainChainOuterWidthMm(outerWidthMm)} mm: ayuda a separar cadenas 9/10/11/12v dentro de la misma familia interna 11/128.'
        : 'Ancho externo nominal ${_formatDrivetrainChainOuterWidthMm(outerWidthMm)} mm: ayuda a precisar la cobertura real dentro de la familia 3/32.';
  }

  return DrivetrainProductSpecInferenceResult(
    derivedValues: derivedValues,
    guidanceByField: guidanceByField,
  );
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

String? canonicalDrivetrainChainWidthFamilyLabel(dynamic rawValue) {
  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll(' ', '');
  if (normalized == null ||
      normalized.isEmpty ||
      normalized == 'otro' ||
      normalized == 'other' ||
      normalized.contains('desconoc')) {
    return null;
  }
  if (normalized.contains('1/8') || normalized.contains('1-8')) {
    return '1/8';
  }
  if (normalized.contains('3/32') || normalized.contains('3-32')) {
    return '3/32';
  }
  if (normalized.contains('11/128') || normalized.contains('11-128')) {
    return '11/128';
  }
  return null;
}

String? canonicalDrivetrainShifterPositionLabel(dynamic rawValue) {
  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll(' ', '');
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.contains('desconoc')) {
    return null;
  }

  if (normalized.contains('izquierdo') ||
      normalized.contains('delantero') ||
      normalized.contains('front')) {
    return 'Izquierdo / delantero';
  }
  if (normalized.contains('derecho') ||
      normalized.contains('trasero') ||
      normalized.contains('rear')) {
    return 'Derecho / trasero';
  }
  if (normalized.contains('par') || normalized.contains('pair')) {
    return 'Par';
  }
  if (normalized.contains('universal')) {
    return 'Universal';
  }

  return null;
}

String? canonicalFrontDerailleurMountTypeLabel(dynamic rawValue) {
  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll(' ', '');
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.contains('desconoc')) {
    return null;
  }

  if (normalized.contains('abraz') || normalized.contains('clamp')) {
    return 'Abrazadera';
  }
  if (normalized.contains('braze')) {
    return 'Braze-on';
  }
  if (normalized.contains('etype') || normalized.contains('e-type')) {
    return 'E-type';
  }
  if (normalized.contains('direct')) {
    return 'Direct mount';
  }

  return null;
}

double? canonicalDrivetrainChainOuterWidthMm(dynamic rawValue) {
  if (rawValue == null) {
    return null;
  }
  if (rawValue is num) {
    final numericValue = rawValue.toDouble();
    if (numericValue < 5 || numericValue > 8) {
      return null;
    }
    return double.parse(numericValue.toStringAsFixed(2));
  }

  final normalized = rawValue.toString().trim().replaceAll(',', '.');
  if (normalized.isEmpty || normalized.toLowerCase().contains('desconoc')) {
    return null;
  }

  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(normalized);
  final parsed = match == null ? null : double.tryParse(match.group(0)!);
  if (parsed == null || parsed < 5 || parsed > 8) {
    return null;
  }

  return double.parse(parsed.toStringAsFixed(2));
}

String _formatDrivetrainChainOuterWidthMm(double value) {
  final formatted = value.toStringAsFixed(2);
  return formatted.endsWith('0')
      ? formatted.substring(0, formatted.length - 1)
      : formatted;
}

String? canonicalDrivetrainProductPlatformLabel(dynamic rawValue) {
  switch (drivetrainCompatibilityPlatformToken(rawValue)) {
    case 'shimano_hg_sis':
      return 'Shimano HG / SIS';
    case 'shimano_hg_plus':
      return 'Shimano Hyperglide+';
    case 'shimano_linkglide':
      return 'Shimano Linkglide / CUES';
    case 'sram_eagle':
      return 'SRAM Eagle';
    case 'sram_flattop':
      return 'SRAM FlatTop / AXS road';
    case 'sram_t_type':
      return 'SRAM T-Type Transmission';
    case 'campagnolo':
      return 'Campagnolo';
    case 'microshift_advent':
      return 'Microshift Advent / Acolyte';
    case 'single_speed_bmx':
      return 'Single speed / BMX';
    case 'friction_universal':
      return 'Friccion / universal';
    case 'generic':
      return 'Generico compatible';
    default:
      return null;
  }
}

Set<String> _extractDrivetrainProductSpeedLabels(dynamic rawValue) {
  final labels = <String>{};

  void parse(dynamic value) {
    if (value == null) {
      return;
    }
    if (value is List) {
      for (final item in value) {
        parse(item);
      }
      return;
    }
    final text = value.toString();
    for (final match in RegExp(r'\d{1,2}').allMatches(text)) {
      labels.add(match.group(0)!);
    }
  }

  parse(rawValue);
  return labels;
}

Set<String> _extractDrivetrainProductProfileLabels(dynamic rawValue) {
  final labels = <String>{};

  void parse(dynamic value) {
    if (value == null) {
      return;
    }
    if (value is List) {
      for (final item in value) {
        parse(item);
      }
      return;
    }
    final label = _normalizeDrivetrainText(value.toString());
    if (label != null &&
        label.isNotEmpty &&
        !label.toLowerCase().contains('desconoc') &&
        label.toLowerCase() != 'otro') {
      labels.add(label);
    }
  }

  parse(rawValue);
  return labels;
}

bool _shouldHideChainPlatformField({
  required String? widthFamily,
  required Set<String> speedLabels,
  required String? explicitPlatform,
  required String? drivetrainMode,
}) {
  if (drivetrainMode == kDrivetrainModeSingleSpeedBmxIgh &&
      explicitPlatform == null) {
    return true;
  }
  final hasUpstreamSignal =
      widthFamily != null || speedLabels.isNotEmpty || explicitPlatform != null;
  if (!hasUpstreamSignal) {
    return false;
  }
  if (explicitPlatform != null) {
    return false;
  }
  if (widthFamily == '1/8' || speedLabels.contains('1')) {
    return false;
  }
  if (_drivetrainSpeedLabelsContainAny(speedLabels, const {'12', '13'})) {
    return false;
  }
  if (widthFamily == '3/32' || widthFamily == '11/128') {
    return true;
  }
  if (speedLabels.isNotEmpty) {
    return true;
  }
  return false;
}

Set<String> _buildAllowedChainPlatformOptions({
  required String? widthFamily,
  required Set<String> speedLabels,
  required String? explicitPlatform,
  required String? drivetrainMode,
  required Set<String> compatibilityFamilies,
}) {
  if (drivetrainMode == kDrivetrainModeSingleSpeedBmxIgh ||
      widthFamily == '1/8' ||
      speedLabels.contains('1') ||
      explicitPlatform == 'Single speed / BMX') {
    return const {'Single speed / BMX'};
  }

  final allowed = <String>{};
  if (explicitPlatform != null) {
    allowed.add(explicitPlatform);
  }

  if (_drivetrainSpeedLabelsContainAny(speedLabels, const {'12', '13'})) {
    final familyPlatforms =
        compatibilityFamilies.expand(_platformsForCompatibilityFamily).toSet();
    if (familyPlatforms.isNotEmpty) {
      allowed.addAll(familyPlatforms);
    } else {
      allowed.addAll(const {
        'Shimano Hyperglide+',
        'Shimano Linkglide / CUES',
        'SRAM Eagle',
        'SRAM FlatTop / AXS road',
        'SRAM T-Type Transmission',
        'Campagnolo',
      });
    }
  }

  return allowed;
}

Set<String> _buildAllowedChainProfileOptions({
  required String? widthFamily,
  required double? outerWidthMm,
  required Set<String> speedLabels,
  required Set<String> explicitProfiles,
  required String? explicitPlatform,
  required String? drivetrainMode,
  required Set<String> compatibilityFamilies,
}) {
  final allowed = <String>{};

  if (drivetrainMode == kDrivetrainModeSingleSpeedBmxIgh ||
      widthFamily == '1/8' ||
      speedLabels.contains('1')) {
    allowed.add('Single speed / BMX');
  }

  if (widthFamily == '3/32') {
    if (outerWidthMm == null &&
        (speedLabels.isEmpty ||
            _drivetrainSpeedLabelsWithin(
              speedLabels,
              const {'1', '5', '6', '7', '8'},
            ))) {
      allowed.add('Universal 5-8v');
    }
    if (speedLabels.contains('1') || explicitPlatform == 'Single speed / BMX') {
      allowed.add('Single speed / BMX');
    }
  }

  if (widthFamily == '11/128' &&
      outerWidthMm == null &&
      (speedLabels.isEmpty ||
          _drivetrainSpeedLabelsWithin(speedLabels, const {'9', '10', '11'}))) {
    allowed.add('Universal 9-11v');
  }

  if (explicitPlatform != null) {
    allowed.addAll(_profilesForPlatform(explicitPlatform));
  }
  allowed.addAll(explicitProfiles);

  if (_drivetrainSpeedLabelsContainAny(speedLabels, const {'12', '13'})) {
    final familyProfiles =
        compatibilityFamilies.expand(_profilesForCompatibilityFamily).toSet();
    if (familyProfiles.isNotEmpty) {
      allowed.addAll(familyProfiles);
    } else {
      allowed.addAll(const {
        'Shimano HG+',
        'Shimano Linkglide / CUES',
        'SRAM Eagle',
        'SRAM FlatTop',
        'SRAM T-Type',
        'Campagnolo',
      });
    }
  }

  if (compatibilityFamilies.contains(kDrivetrainCompatibilityFamilyKmc) &&
      allowed.isNotEmpty) {
    allowed.add('KMC compatible');
  }

  return allowed;
}

Set<String> _profilesForPlatform(String platform) {
  switch (platform) {
    case 'Shimano Hyperglide+':
      return const {'Shimano HG+'};
    case 'Shimano Linkglide / CUES':
      return const {'Shimano Linkglide / CUES'};
    case 'SRAM Eagle':
      return const {'SRAM Eagle'};
    case 'SRAM FlatTop / AXS road':
      return const {'SRAM FlatTop'};
    case 'SRAM T-Type Transmission':
      return const {'SRAM T-Type'};
    case 'Campagnolo':
      return const {'Campagnolo'};
    case 'Single speed / BMX':
      return const {'Single speed / BMX'};
    default:
      return const <String>{};
  }
}

Set<String> _profilesForCompatibilityFamily(String compatibilityFamily) {
  switch (compatibilityFamily) {
    case kDrivetrainCompatibilityFamilyShimano:
      return const {'Shimano HG+', 'Shimano Linkglide / CUES'};
    case kDrivetrainCompatibilityFamilySram:
      return const {'SRAM Eagle', 'SRAM FlatTop', 'SRAM T-Type'};
    case kDrivetrainCompatibilityFamilyCampagnolo:
      return const {'Campagnolo'};
    case kDrivetrainCompatibilityFamilyKmc:
      return const {'KMC compatible'};
    case kDrivetrainCompatibilityFamilySingleSpeed:
      return const {'Single speed / BMX'};
    default:
      return const <String>{};
  }
}

Set<String> _platformsForCompatibilityFamily(String compatibilityFamily) {
  switch (compatibilityFamily) {
    case kDrivetrainCompatibilityFamilyShimano:
      return const {
        'Shimano Hyperglide+',
        'Shimano Linkglide / CUES',
      };
    case kDrivetrainCompatibilityFamilySram:
      return const {
        'SRAM Eagle',
        'SRAM FlatTop / AXS road',
        'SRAM T-Type Transmission',
      };
    case kDrivetrainCompatibilityFamilyCampagnolo:
      return const {'Campagnolo'};
    case kDrivetrainCompatibilityFamilyMicroshift:
      return const {'Microshift Advent / Acolyte'};
    case kDrivetrainCompatibilityFamilySingleSpeed:
      return const {'Single speed / BMX'};
    default:
      return const <String>{};
  }
}

List<String> _sortDrivetrainOptionLabels(Iterable<String> values) {
  final sorted = values.toList(growable: false)..sort();
  return sorted;
}

Set<String> _extractDrivetrainCompatibilityFamilyLabels(dynamic rawValue) {
  final labels = <String>{};

  void parse(dynamic value) {
    if (value == null) {
      return;
    }
    if (value is List) {
      for (final item in value) {
        parse(item);
      }
      return;
    }
    final label = canonicalDrivetrainCompatibilityFamilyLabel(value);
    if (label != null &&
        label != kDrivetrainCompatibilityFamilyUnknown &&
        label != kDrivetrainCompatibilityFamilyOther) {
      labels.add(label);
    }
  }

  parse(rawValue);
  return labels;
}

String? canonicalDrivetrainCompatibilityFamilyLabel(dynamic rawValue) {
  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll('_', ' ');
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  if (normalized.contains('shimano')) {
    return kDrivetrainCompatibilityFamilyShimano;
  }
  if (normalized.contains('sram')) {
    return kDrivetrainCompatibilityFamilySram;
  }
  if (normalized.contains('campagnolo')) {
    return kDrivetrainCompatibilityFamilyCampagnolo;
  }
  if (normalized.contains('microshift') ||
      normalized.contains('advent') ||
      normalized.contains('acolyte')) {
    return kDrivetrainCompatibilityFamilyMicroshift;
  }
  if (normalized.contains('kmc')) {
    return kDrivetrainCompatibilityFamilyKmc;
  }
  if ((normalized.contains('single') && normalized.contains('speed')) ||
      normalized.contains('bmx')) {
    return kDrivetrainCompatibilityFamilySingleSpeed;
  }
  if (normalized.contains('universal') ||
      normalized.contains('generico') ||
      normalized.contains('generic')) {
    return kDrivetrainCompatibilityFamilyUniversal;
  }
  if (normalized == 'otro' || normalized == 'other') {
    return kDrivetrainCompatibilityFamilyOther;
  }
  if (normalized.contains('desconoc') || normalized == 'unknown') {
    return kDrivetrainCompatibilityFamilyUnknown;
  }
  return null;
}

String? canonicalDrivetrainModeLabel(dynamic rawValue) {
  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll('_', ' ');
  if (normalized == null ||
      normalized.isEmpty ||
      normalized.contains('desconoc') ||
      normalized == 'unknown') {
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
    return kDrivetrainModeSingleSpeedBmxIgh;
  }

  if (normalized.contains('derailleur') ||
      normalized.contains('desviador') ||
      normalized.contains('cambio')) {
    return kDrivetrainModeDerailleur;
  }

  return null;
}

String? _deriveDrivetrainModeLabel({
  required String? widthFamily,
  required Set<String> speedLabels,
  required Set<String> explicitProfiles,
  required String? explicitPlatform,
  required Set<String> compatibilityFamilies,
  required dynamic shiftActuationValue,
}) {
  if (widthFamily == '1/8' ||
      speedLabels.contains('1') ||
      explicitPlatform == 'Single speed / BMX' ||
      explicitProfiles.contains('Single speed / BMX') ||
      compatibilityFamilies
          .contains(kDrivetrainCompatibilityFamilySingleSpeed)) {
    return kDrivetrainModeSingleSpeedBmxIgh;
  }

  if (_drivetrainSpeedLabelsContainAny(
        speedLabels,
        const {'5', '6', '7', '8', '9', '10', '11', '12', '13'},
      ) ||
      explicitPlatform != null ||
      explicitProfiles.any((profile) => profile != 'Single speed / BMX') ||
      compatibilityFamilies.any(
        (family) => family != kDrivetrainCompatibilityFamilySingleSpeed,
      ) ||
      _compatibilityFamiliesFromShiftActuation(shiftActuationValue).any(
        (family) => family != kDrivetrainCompatibilityFamilySingleSpeed,
      )) {
    return kDrivetrainModeDerailleur;
  }

  return null;
}

Set<String> _deriveStructuredDrivetrainCompatibilityFamilies({
  required String? widthFamily,
  required Set<String> speedLabels,
  required Set<String> explicitProfiles,
  required String? explicitPlatform,
  required dynamic shiftActuationValue,
}) {
  final families = <String>{};

  final platformFamily = _compatibilityFamilyForPlatform(explicitPlatform);
  if (platformFamily != null) {
    families.add(platformFamily);
  }

  families.addAll(_compatibilityFamiliesFromProfiles(explicitProfiles));
  families
      .addAll(_compatibilityFamiliesFromShiftActuation(shiftActuationValue));

  if (widthFamily == '1/8' || speedLabels.contains('1')) {
    families.add(kDrivetrainCompatibilityFamilySingleSpeed);
  }

  return families;
}

Set<String> _deriveChainSpeedOptionsFromOuterWidthMm(double? outerWidthMm) {
  if (outerWidthMm == null) {
    return const <String>{};
  }
  if (outerWidthMm >= 7.75) {
    return const {'6'};
  }
  if (outerWidthMm >= 7.0) {
    return const {'6', '7', '8'};
  }
  if (outerWidthMm >= 6.55 && outerWidthMm <= 6.75) {
    return const {'9'};
  }
  if (outerWidthMm >= 5.84 && outerWidthMm <= 6.02) {
    return const {'10'};
  }
  if (outerWidthMm >= 5.55 && outerWidthMm <= 5.69) {
    return const {'11'};
  }
  if (outerWidthMm >= 5.20 && outerWidthMm <= 5.35) {
    return const {'12'};
  }
  return const <String>{};
}

Set<String> _buildAllowedChainSpeedOptions({
  required String? widthFamily,
  required double? outerWidthMm,
  required Set<String> speedLabels,
  required String? explicitPlatform,
  required String? drivetrainMode,
}) {
  final normalizedCurrent = _normalizedDrivetrainSpeedLabels(speedLabels);
  final outerWidthDerivedSpeeds = _deriveChainSpeedOptionsFromOuterWidthMm(
    outerWidthMm,
  );

  if (drivetrainMode == kDrivetrainModeSingleSpeedBmxIgh ||
      widthFamily == '1/8' ||
      explicitPlatform == 'Single speed / BMX') {
    return const {'1'};
  }

  if (widthFamily == '3/32') {
    if (normalizedCurrent.contains('1')) {
      return const {'1'};
    }
    final constrainedOuterWidthSpeeds = outerWidthDerivedSpeeds
        .where((label) => const {'5', '6', '7', '8'}.contains(label))
        .toSet();
    if (constrainedOuterWidthSpeeds.isNotEmpty) {
      return constrainedOuterWidthSpeeds;
    }
    return const {'5', '6', '7', '8'};
  }

  if (widthFamily == '11/128') {
    if (outerWidthDerivedSpeeds.isNotEmpty) {
      return outerWidthDerivedSpeeds;
    }
    if (_drivetrainSpeedLabelsContainAny(
        normalizedCurrent, const {'12', '13'})) {
      return const {'12', '13'};
    }
    return const {'9', '10', '11', '12', '13'};
  }

  if (explicitPlatform == 'Shimano Hyperglide+' ||
      explicitPlatform == 'Shimano Linkglide / CUES' ||
      explicitPlatform == 'SRAM Eagle' ||
      explicitPlatform == 'SRAM FlatTop / AXS road' ||
      explicitPlatform == 'SRAM T-Type Transmission' ||
      explicitPlatform == 'Campagnolo') {
    return const {'12', '13'};
  }

  return const <String>{};
}

Set<String> _buildAllowedChainOuterWidthOptions({
  required String? widthFamily,
  required Set<String> speedLabels,
  required String? explicitPlatform,
  required String? drivetrainMode,
}) {
  if (drivetrainMode == kDrivetrainModeSingleSpeedBmxIgh ||
      widthFamily == '1/8' ||
      explicitPlatform == 'Single speed / BMX') {
    return const <String>{};
  }

  if (widthFamily == '3/32') {
    return const {'7.1', '7.3', '7.8'};
  }

  if (widthFamily == '11/128') {
    if (speedLabels.contains('9')) {
      return const {'6.6', '6.7'};
    }
    if (speedLabels.contains('10')) {
      return const {'5.88', '5.95'};
    }
    if (speedLabels.contains('11')) {
      return const {'5.62'};
    }
    if (_drivetrainSpeedLabelsContainAny(speedLabels, const {'12', '13'}) ||
        explicitPlatform == 'Shimano Hyperglide+' ||
        explicitPlatform == 'Shimano Linkglide / CUES' ||
        explicitPlatform == 'SRAM Eagle' ||
        explicitPlatform == 'SRAM FlatTop / AXS road' ||
        explicitPlatform == 'SRAM T-Type Transmission') {
      return const {'5.25', '5.3'};
    }
    return const {'6.6', '6.7', '5.88', '5.95', '5.62', '5.25', '5.3'};
  }

  if (_drivetrainSpeedLabelsContainAny(
      speedLabels, const {'5', '6', '7', '8'})) {
    return const {'7.1', '7.3', '7.8'};
  }
  if (_drivetrainSpeedLabelsContainAny(
        speedLabels,
        const {'9', '10', '11', '12', '13'},
      ) ||
      explicitPlatform != null) {
    return const {'6.6', '6.7', '5.88', '5.95', '5.62', '5.25', '5.3'};
  }

  return const {
    '7.1',
    '7.3',
    '7.8',
    '6.6',
    '6.7',
    '5.88',
    '5.95',
    '5.62',
    '5.25',
    '5.3'
  };
}

Set<String> _normalizedDrivetrainSpeedLabels(Set<String> speedLabels) {
  return speedLabels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toSet();
}

List<String> _compatibilityFamilyInferenceReasons({
  required String? explicitPlatform,
  required Set<String> explicitProfiles,
  required dynamic shiftActuationValue,
  required String? widthFamily,
  required Set<String> speedLabels,
}) {
  final reasons = <String>{};

  if (_compatibilityFamilyForPlatform(explicitPlatform) != null) {
    reasons.add('plataforma declarada');
  }
  if (_compatibilityFamiliesFromProfiles(explicitProfiles).isNotEmpty) {
    reasons.add('perfil declarado');
  }
  if (_compatibilityFamiliesFromShiftActuation(shiftActuationValue)
      .isNotEmpty) {
    reasons.add('familia de indexado declarada');
  }
  if (widthFamily == '1/8' || speedLabels.contains('1')) {
    reasons.add('single speed / BMX confirmado');
  }

  if (reasons.isEmpty) {
    reasons.add('senales estructuradas');
  }

  return reasons.toList(growable: false);
}

String? _compatibilityFamilyForPlatform(String? platform) {
  switch (platform) {
    case 'Shimano HG / SIS':
    case 'Shimano Hyperglide+':
    case 'Shimano Linkglide / CUES':
      return kDrivetrainCompatibilityFamilyShimano;
    case 'SRAM Eagle':
    case 'SRAM FlatTop / AXS road':
    case 'SRAM T-Type Transmission':
      return kDrivetrainCompatibilityFamilySram;
    case 'Campagnolo':
      return kDrivetrainCompatibilityFamilyCampagnolo;
    case 'Microshift Advent / Acolyte':
      return kDrivetrainCompatibilityFamilyMicroshift;
    case 'Single speed / BMX':
      return kDrivetrainCompatibilityFamilySingleSpeed;
    case 'Friccion / universal':
    case 'Generico compatible':
      return kDrivetrainCompatibilityFamilyUniversal;
    default:
      return null;
  }
}

Set<String> _compatibilityFamiliesFromProfiles(Set<String> profiles) {
  final families = <String>{};
  for (final profile in profiles) {
    switch (profile) {
      case 'Shimano HG+':
      case 'Shimano Linkglide / CUES':
        families.add(kDrivetrainCompatibilityFamilyShimano);
        break;
      case 'SRAM Eagle':
      case 'SRAM FlatTop':
      case 'SRAM T-Type':
        families.add(kDrivetrainCompatibilityFamilySram);
        break;
      case 'Campagnolo':
        families.add(kDrivetrainCompatibilityFamilyCampagnolo);
        break;
      case 'KMC compatible':
        families.add(kDrivetrainCompatibilityFamilyKmc);
        break;
      case 'Single speed / BMX':
        families.add(kDrivetrainCompatibilityFamilySingleSpeed);
        break;
    }
  }
  return families;
}

Set<String> _compatibilityFamiliesFromShiftActuation(dynamic rawValue) {
  final families = <String>{};
  final platformFamily = _compatibilityFamilyForPlatform(
      canonicalDrivetrainProductPlatformLabel(rawValue));
  if (platformFamily != null) {
    families.add(platformFamily);
  }

  final normalized = _normalizeDrivetrainText(rawValue?.toString())
      ?.toLowerCase()
      .replaceAll('_', ' ');
  if (normalized == null || normalized.isEmpty) {
    return families;
  }

  if (normalized.contains('campagnolo')) {
    families.add(kDrivetrainCompatibilityFamilyCampagnolo);
  }
  if (normalized.contains('advent') || normalized.contains('acolyte')) {
    families.add(kDrivetrainCompatibilityFamilyMicroshift);
  }
  if (normalized.contains('exact actuation') ||
      normalized.contains('x actuation') ||
      normalized.contains('axs') ||
      normalized.contains('t type')) {
    families.add(kDrivetrainCompatibilityFamilySram);
  }
  if (normalized.contains('sis') ||
      normalized.contains('dynasys') ||
      normalized.contains('linkglide') ||
      normalized.contains('cues') ||
      normalized.contains('shimano road') ||
      normalized.contains('shimano ruta') ||
      normalized.contains('ruta')) {
    families.add(kDrivetrainCompatibilityFamilyShimano);
  }
  if (normalized.contains('friccion') ||
      normalized.contains('friction') ||
      normalized.contains('universal')) {
    families.add(kDrivetrainCompatibilityFamilyUniversal);
  }

  return families;
}

bool _drivetrainSpeedLabelsWithin(Set<String> actual, Set<String> allowed) {
  if (actual.isEmpty) {
    return false;
  }
  return actual.every(allowed.contains);
}

bool _drivetrainSpeedLabelsContainAny(
  Set<String> actual,
  Set<String> expected,
) {
  return actual.any(expected.contains);
}

bool _isMeaningfulDrivetrainProductSpecValue(dynamic value) {
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
