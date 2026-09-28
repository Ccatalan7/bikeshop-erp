/// Lo que un servicio de rueda (familia `wheels`) lee de la ficha y lo que le
/// devuelve (paso C del backbone, 2026-09-27).
///
/// La ficha guarda dos clases de datos de rueda, y la respuesta de un servicio
/// vale distinto para cada una:
///
/// - **Por posición** (`frontSpokeHoles`, `rearSpokeHoles`): las pregunta el
///   Enrayado y describen la rueda que se arma, no la que llegó. Son estado
///   instalado: la ficha cambia **al terminar el trabajo**
///   ([wheelInstalledFacts], aplicado por la sincronización de la memoria),
///   nunca al configurar. Una sola respuesta para «ambas» no se escribe: 3 de
///   44 bicis tienen perforaciones distintas adelante y atrás.
/// - **De una rueda, como llegó** (`front/rearRotorSizeMm`,
///   `front/rearAxleInterface`, `front/rearBrakeFluidType`): se confirman con
///   esa rueda o ese freno. Un solo rotor o eje para «ambas» no se escribe;
///   un sangrado de ambos frenos sí deja su fluido en cada uno.
/// - **De la bici completa** (`valveType`, `brakeType` con `rimBrakeFamily`):
///   sólo una respuesta que cubre ambas ruedas los confirma. Una sola rueda los
///   deja sugeridos, sin confirmar, y sólo si la ficha no los sabía: en
///   producción 8 de 27 bicis tienen rotores distintos adelante y atrás, y el
///   aro llegó a escribirse «27.5" - 26"».
///
/// Lo observado nunca pisa un dato confirmado distinto: eso es cambiar la
/// bici, no confirmarla. Cambiar sólo lo hace lo instalado, al terminar.
/// El aro (`bikes.wheel_size`) sólo se lee, y como dato **registrado**: se
/// precarga a la vista, nunca se oculta ni sirve de prueba física para la
/// matriz. La columna no tiene marca de confirmación, así que llenarla desde
/// una rueda no se distinguiría de confirmarla.
library;

import '../config/brake_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bikeshop_models.dart';

/// Las ruedas que toca un servicio: la ubicación de la línea si la tiene; si
/// no, la respuesta «¿qué rueda?», donde «ambas» son las dos. Freno y ruedas
/// usan este mismo resolvedor.
Set<BikeMemoryLocation> serviceWheelPositions(
  BikeMemoryLocation location,
  Map<String, dynamic> answers,
) {
  if (location == BikeMemoryLocation.front) return {BikeMemoryLocation.front};
  if (location == BikeMemoryLocation.rear) return {BikeMemoryLocation.rear};
  switch (canonicalBrakeWheelValueFromAnswers(answers)) {
    case 'front':
      return {BikeMemoryLocation.front};
    case 'rear':
      return {BikeMemoryLocation.rear};
    case 'both':
      return {BikeMemoryLocation.front, BikeMemoryLocation.rear};
    default:
      return {};
  }
}

const Map<BikeMemoryLocation, String> _spokeHolesKeyByPosition = {
  BikeMemoryLocation.front: 'frontSpokeHoles',
  BikeMemoryLocation.rear: 'rearSpokeHoles',
};

const Map<BikeMemoryLocation, String> _positionLabel = {
  BikeMemoryLocation.front: 'delantera',
  BikeMemoryLocation.rear: 'trasera',
};

/// Respuesta `brake_type` de un servicio de rueda → datos de la ficha.
const Map<String, Map<String, String>> _brakeFactsByWheelAnswer = {
  'hydraulic_disc': {'brakeType': 'hydraulic_disc'},
  'mechanical_disc': {'brakeType': 'mechanical_disc'},
  'v_brake': {'brakeType': 'rim', 'rimBrakeFamily': 'v_brake'},
  'cantilever': {'brakeType': 'rim', 'rimBrakeFamily': 'cantilever'},
};

const Map<String, String> _valveLabel = {
  'presta': 'presta',
  'schrader': 'schrader (auto)',
  'dunlop': 'dunlop',
  'other': 'otra',
};

const Map<String, String> _brakeLabel = {
  'hydraulic_disc': 'disco hidráulico',
  'mechanical_disc': 'disco mecánico',
  'v_brake': 'V-brake',
  'cantilever': 'cantilever',
};

const Map<BikeMemoryLocation, String> _brakeFluidKeyByPosition = {
  BikeMemoryLocation.front: 'frontBrakeFluidType',
  BikeMemoryLocation.rear: 'rearBrakeFluidType',
};

const Map<BikeMemoryLocation, String> _brakePositionLabel = {
  BikeMemoryLocation.front: 'delantero',
  BikeMemoryLocation.rear: 'trasero',
};

const Map<BikeMemoryLocation, String> _axleKeyByPosition = {
  BikeMemoryLocation.front: 'frontAxleInterface',
  BikeMemoryLocation.rear: 'rearAxleInterface',
};

bool _isUnknown(Object? value) {
  if (value == null) return true;
  final text = value.toString().trim().toLowerCase();
  return text.isEmpty ||
      text == 'unknown' ||
      text == 'desconocido' ||
      text == kRegistryUnknownCode;
}

/// Un dato de la ficha como lo dice el taller, para avisos y resúmenes.
String bikeFactValueLabel(String key, Object? value) => switch (key) {
      'frontBrakeFluidType' || 'rearBrakeFluidType' => brakeFluidLabel(value),
      'frontAxleInterface' ||
      'rearAxleInterface' =>
        axleInterfaceLabel(value) ?? '$value',
      _ => '$value',
    };

String? _wheelAnswerForBrake(Map<String, dynamic> values) {
  final brakeType = values['brakeType']?.toString();
  if (brakeType == 'rim') {
    final family = values['rimBrakeFamily']?.toString();
    return _brakeFactsByWheelAnswer.containsKey(family) ? family : null;
  }
  return _brakeFactsByWheelAnswer.containsKey(brakeType) ? brakeType : null;
}

/// Lo que el asistente ya sabe antes de preguntar.
class WheelServicePrefill {
  const WheelServicePrefill({
    required this.answers,
    required this.hiddenKeys,
    required this.knownFacts,
  });

  /// Respuestas precargadas desde la ficha.
  final Map<String, String> answers;

  /// Preguntas que no se hacen porque la ficha ya lo confirma.
  final Set<String> hiddenKeys;

  /// Lo que se muestra arriba del asistente como «desde la ficha».
  final List<String> knownFacts;
}

/// Precarga desde la ficha. Se oculta sólo lo confirmado y lo que la pregunta
/// puede expresar con sus opciones; lo no confirmado queda precargado y a la
/// vista, para que el mecánico lo mire. El aro es texto registrado sin marca
/// de confirmación: se precarga cuando se lee sin adivinar, y queda a la vista.
WheelServicePrefill wheelServicePrefill({
  required Set<BikeMemoryLocation> positions,
  required String? bikeWheelSize,
  required Map<String, dynamic> values,
  required Map<String, dynamic> confirmed,
  required Map<String, Set<String>> optionsByKey,
}) {
  final answers = <String, String>{};
  final hidden = <String>{};
  final known = <String>[];

  void offer(String key, String? answer, {required bool isConfirmed}) {
    final options = optionsByKey[key];
    if (answer == null || options == null || !options.contains(answer)) return;
    answers[key] = answer;
    if (isConfirmed) hidden.add(key);
  }

  final wheelLabel = canonicalBikeWheelSizeLabel(bikeWheelSize);
  if (wheelLabel != null) {
    offer('wheel_size', wheelSizeWizardValueForLabel(wheelLabel),
        isConfirmed: false);
    known.add('Aro registrado $wheelLabel');
  }

  // Las perforaciones son de una rueda: se precargan sólo con una definida.
  final holeKey =
      positions.length == 1 ? _spokeHolesKeyByPosition[positions.single] : null;
  if (holeKey != null && values[holeKey] != null) {
    final holes = num.tryParse(values[holeKey].toString())?.toInt().toString();
    // Es la rueda que se arma: se precarga la actual, siempre a la vista.
    offer('hole_count', holes, isConfirmed: false);
    if (holes != null) {
      known.add('${holes}H ${_positionLabel[positions.single]}');
    }
  }

  final valve = values['valveType']?.toString();
  if (!_isUnknown(valve)) {
    offer('valve_type', valve, isConfirmed: confirmed['valveType'] == true);
    known.add('Válvula ${_valveLabel[valve] ?? valve}');
  }

  final brakeAnswer = _wheelAnswerForBrake(values);
  if (brakeAnswer != null) {
    final brakeConfirmed = confirmed['brakeType'] == true &&
        (values['brakeType'] != 'rim' || confirmed['rimBrakeFamily'] == true);
    offer('brake_type', brakeAnswer, isConfirmed: brakeConfirmed);
    known.add('Freno ${_brakeLabel[brakeAnswer]}');
  }

  // El eje es de una rueda: se lee sólo con una definida (paso F.2).
  final axleKey =
      positions.length == 1 ? _axleKeyByPosition[positions.single] : null;
  final axle = axleKey == null ? null : values[axleKey]?.toString();
  if (axleKey != null && !_isUnknown(axle)) {
    offer('axle_type', axle, isConfirmed: confirmed[axleKey] == true);
    final label = axleInterfaceLabel(axle);
    if (label != null) known.add(label);
  }

  return WheelServicePrefill(
    answers: answers,
    hiddenKeys: hidden,
    knownFacts: known,
  );
}

/// Lo que las respuestas de un servicio de rueda le devuelven a la ficha.
class WheelServiceFacts {
  const WheelServiceFacts({
    required this.confirm,
    required this.suggest,
    required this.differences,
    this.onCompletion = const {},
    this.currentValues = const {},
  });

  /// Datos que el mecánico vio y quedan confirmados.
  final Map<String, Object> confirm;

  /// Datos de la bici completa vistos en una sola rueda, que la ficha no
  /// sabía: quedan sugeridos, sin confirmar.
  final Map<String, Object> suggest;

  /// Lo que no coincide con la ficha y no se escribe, en palabras de taller.
  final List<String> differences;

  /// Estado que el servicio deja instalado: la ficha lo toma al terminar el
  /// trabajo, no al guardarlo.
  final Map<String, Object> onCompletion;

  /// Lo que la ficha dice hoy de las claves de [onCompletion].
  final Map<String, Object?> currentValues;

  /// Nada que escribir al guardar el trabajo.
  bool get isEmpty => confirm.isEmpty && suggest.isEmpty;
}

/// Reglas comunes de lo observado: un dato de la bici completa se confirma
/// con ambas ruedas y se sugiere con una; un dato de una rueda se confirma con
/// esa rueda. Ninguno pisa un dato confirmado distinto.
class _ObservedFacts {
  _ObservedFacts({
    required this.positions,
    required this.values,
    required this.confirmed,
  });

  final Set<BikeMemoryLocation> positions;
  final Map<String, dynamic> values;
  final Map<String, dynamic> confirmed;
  final confirm = <String, Object>{};
  final suggest = <String, Object>{};
  final differences = <String>[];

  bool get coversBike =>
      positions.contains(BikeMemoryLocation.front) &&
      positions.contains(BikeMemoryLocation.rear);

  static bool _same(Object? current, Object value) =>
      current != null &&
      (current is num || value is num
          ? num.tryParse(current.toString()) == num.tryParse(value.toString())
          : current.toString() == value.toString());

  void _differs(String key, String label, Object? current, Object value) {
    differences.add(
      '$label: la ficha dice ${bikeFactValueLabel(key, current)} y el '
      'servicio ${bikeFactValueLabel(key, value)}. No se cambia desde aquí.',
    );
  }

  /// Dato de la bici completa. Devuelve si quedó compatible con la respuesta.
  bool aggregate(String key, Object value, String label) {
    final current = values[key];
    final isConfirmed = confirmed[key] == true;
    if (_same(current, value)) {
      if (!isConfirmed && coversBike) confirm[key] = value;
      return true;
    }
    if (isConfirmed || (!coversBike && !_isUnknown(current))) {
      _differs(key, label, current, value);
      return false;
    }
    if (coversBike) {
      confirm[key] = value;
    } else {
      suggest[key] = value;
    }
    return true;
  }

  /// Dato de una rueda, visto en la bici tal como llegó. Con [bothNotice],
  /// una sola respuesta para las dos ruedas no se escribe (no dice cuál tiene
  /// cada una); sin él, la respuesta vale para cada rueda que el servicio tocó.
  void perPosition(
    Map<BikeMemoryLocation, String> keyByPosition,
    Object value,
    String Function(BikeMemoryLocation position) labelOf, {
    String? bothNotice,
  }) {
    if (positions.length > 1 && bothNotice != null) {
      differences.add(bothNotice);
      return;
    }
    for (final position in positions) {
      final key = keyByPosition[position];
      if (key == null) continue;
      final current = values[key];
      final isConfirmed = confirmed[key] == true;
      if (isConfirmed && _same(current, value)) continue;
      if (isConfirmed) {
        _differs(key, labelOf(position), current, value);
        continue;
      }
      confirm[key] = value;
    }
  }

  void brakeAnswer(Object? answer) {
    final brakeFacts = _brakeFactsByWheelAnswer[answer];
    if (brakeFacts != null &&
        aggregate('brakeType', brakeFacts['brakeType']!, 'Freno')) {
      final family = brakeFacts['rimBrakeFamily'];
      if (family != null) {
        aggregate('rimBrakeFamily', family, 'Freno de llanta');
      }
    }
  }
}

WheelServiceFacts wheelServiceFacts({
  required Set<BikeMemoryLocation> positions,
  required Map<String, dynamic> answers,
  required Map<String, dynamic> values,
  required Map<String, dynamic> confirmed,
}) {
  final observed = _ObservedFacts(
    positions: positions,
    values: values,
    confirmed: confirmed,
  );

  // Por posición: es la rueda que se arma, así que no se confirma nada al
  // guardar; queda como cambio para cuando el trabajo termine.
  final onCompletion =
      wheelInstalledFacts(positions: positions, answers: answers);
  if (answers['hole_count'] != null && positions.length > 1) {
    observed.differences.add(
      'Una sola respuesta de perforaciones no dice cuántas tiene cada rueda: '
      'queda en la línea y la ficha no cambia.',
    );
  }

  final valve = answers['valve_type']?.toString();
  if (valve != null && _valveLabel.containsKey(valve)) {
    observed.aggregate('valveType', valve, 'Válvula');
  }
  observed.brakeAnswer(answers['brake_type']);

  // El eje es el de la puntera: el servicio de maza lo ve, no lo cambia, y
  // se confirma con esa rueda (paso F.2). «Desconocido» no se escribe.
  final axle = answers['axle_type']?.toString();
  if (axle != null && kAxleInterfaceLabels.containsKey(axle)) {
    observed.perPosition(
      _axleKeyByPosition,
      axle,
      (position) => 'Eje de la rueda ${_positionLabel[position]}',
      bothNotice: 'Un solo eje para ambas ruedas no dice cuál tiene cada '
          'una: queda en la línea y la ficha no cambia.',
    );
  }

  return WheelServiceFacts(
    confirm: observed.confirm,
    suggest: observed.suggest,
    differences: observed.differences,
    onCompletion: onCompletion,
    currentValues: {for (final key in onCompletion.keys) key: values[key]},
  );
}

const Map<BikeMemoryLocation, String> _rotorKeyByPosition = {
  BikeMemoryLocation.front: 'frontRotorSizeMm',
  BikeMemoryLocation.rear: 'rearRotorSizeMm',
};

/// Lo que un servicio de freno le devuelve a la ficha (paso D). El tipo de
/// freno es de la bici completa: una rueda sugiere y ambas confirman. El
/// rotor es de cada rueda y es el que ya está puesto (el Centrado de Rotor lo
/// ajusta, no lo cambia): se confirma con esa rueda. Un solo tamaño para
/// «ambas» no se escribe: 8 de 27 bicis tienen rotores distintos.
WheelServiceFacts brakeServiceFacts({
  required Set<BikeMemoryLocation> positions,
  required Map<String, dynamic> answers,
  required Map<String, dynamic> values,
  required Map<String, dynamic> confirmed,
}) {
  final observed = _ObservedFacts(
    positions: positions,
    values: values,
    confirmed: confirmed,
  );
  observed.brakeAnswer(answers['brake_type']);
  // El fluido es de cada freno: manilla, manguera y caliper son un sistema
  // cerrado, y Park Tool y SRAM prohíben mezclar dentro de él, no usar otro
  // en el otro freno (paso F.2, corregido el 2026-09-27). Sangrar un freno
  // confirma el suyo; sangrar los dos con un fluido pone ese fluido en cada
  // uno. No dice el tipo de freno: también hay frenos de llanta hidráulicos.
  final fluid = canonicalBrakeFluidTypeValue(answers['fluid_type']?.toString());
  if (fluid != null && kBrakeFluidTypeOptions.containsKey(fluid)) {
    observed.perPosition(
      _brakeFluidKeyByPosition,
      fluid,
      (position) => 'Fluido del freno ${_brakePositionLabel[position]}',
    );
  }
  final rotor = int.tryParse(answers['rotor_size']?.toString() ?? '');
  if (rotor != null) {
    observed.perPosition(
      _rotorKeyByPosition,
      rotor,
      (position) => 'Rotor de la rueda ${_positionLabel[position]}',
      bothNotice: 'Un solo tamaño de rotor no dice cuál tiene cada rueda: '
          'queda en la línea y la ficha no cambia.',
    );
  }
  return WheelServiceFacts(
    confirm: observed.confirm,
    suggest: observed.suggest,
    differences: observed.differences,
  );
}

/// El estado que un servicio de rueda deja instalado en la ficha: las
/// perforaciones de la rueda que se armó, de una sola rueda.
Map<String, Object> wheelInstalledFacts({
  required Set<BikeMemoryLocation> positions,
  required Map<String, dynamic> answers,
}) {
  final holes = int.tryParse(answers['hole_count']?.toString() ?? '');
  final key =
      positions.length == 1 ? _spokeHolesKeyByPosition[positions.single] : null;
  if (holes == null || key == null) return const {};
  return {key: holes};
}

/// Cómo se dice en el taller un dato instalado: «28H en la rueda trasera».
String wheelInstalledFactLabel(String key, Object? value) => switch (key) {
      'frontSpokeHoles' => '${value}H en la rueda delantera',
      'rearSpokeHoles' => '${value}H en la rueda trasera',
      _ => '${_factLabel[key] ?? key} $value',
    };

const Map<String, String> _factLabel = {
  'frontSpokeHoles': 'perforaciones delanteras',
  'rearSpokeHoles': 'perforaciones traseras',
  'valveType': 'válvula',
  'brakeType': 'tipo de freno',
  'rimBrakeFamily': 'familia de freno de llanta',
  'frontRotorSizeMm': 'rotor delantero',
  'rearRotorSizeMm': 'rotor trasero',
  'frontBrakeFluidType': 'fluido del freno delantero',
  'rearBrakeFluidType': 'fluido del freno trasero',
  'frontAxleInterface': 'eje delantero',
  'rearAxleInterface': 'eje trasero',
};

/// Lo que el mecánico lee al cerrar el asistente de un servicio de rueda o de
/// freno.
String? wheelServiceFactsSummary(WheelServiceFacts facts) {
  String labels(Iterable<String> keys) =>
      keys.map((key) => _factLabel[key] ?? key).join(', ');
  final parts = [
    if (facts.confirm.isNotEmpty)
      'Al guardar el trabajo, la ficha confirma: ${labels(facts.confirm.keys)}.',
    if (facts.suggest.isNotEmpty)
      'Queda sugerido, sin confirmar, porque se vio en una sola rueda: '
          '${labels(facts.suggest.keys)}.',
    for (final entry in facts.onCompletion.entries)
      if ('${facts.currentValues[entry.key]}' != '${entry.value}')
        'Al terminar el trabajo, la ficha pasa a ${entry.value}H en la rueda '
            '${entry.key == 'frontSpokeHoles' ? 'delantera' : 'trasera'}'
            '${facts.currentValues[entry.key] == null ? '' : ' (hoy ${facts.currentValues[entry.key]}H)'}.',
    ...facts.differences,
  ];
  return parts.isEmpty ? null : parts.join(' ');
}

/// Lo que un servicio de rueda observó en la visita, en el vocabulario del
/// diagnóstico de `front_wheel` / `rear_wheel` (`WheelDiagnosisSheet`).
///
/// Sólo se traduce lo que la respuesta dice: «mayor» es un aro golpeado, no
/// fisurado; «ruido» o «preventivo» en la maza no son un estado del rodamiento
/// y quedan sólo en la nota.
class WheelDiagnosisFindings {
  const WheelDiagnosisFindings({
    this.tireCondition,
    this.rimCondition,
    this.hubBearingCondition,
    this.status,
  });

  final String? tireCondition;
  final String? rimCondition;
  final String? hubBearingCondition;

  /// El estado de la rueda que la respuesta justifica, o null si no dice
  /// nada del estado (`ok`, `attention` o `critical`).
  final String? status;

  bool get isEmpty =>
      tireCondition == null &&
      rimCondition == null &&
      hubBearingCondition == null &&
      status == null;
}

const Map<String, String> _tireConditionByAnswer = {
  'ok': 'ok',
  'worn': 'worn',
  'damaged': 'damaged',
};

const Map<String, String> _rimConditionByDamage = {
  'none': 'ok',
  'minor': 'attention',
  'major': 'bent',
};

const Map<String, String> _hubConditionBySymptom = {
  'play': 'play',
  'roughness': 'rough',
};

const Map<String, String> _statusByAnswer = {
  'tire_condition:ok': 'ok',
  'tire_condition:worn': 'attention',
  'tire_condition:damaged': 'critical',
  'rim_damage:none': 'ok',
  'rim_damage:minor': 'attention',
  'rim_damage:major': 'critical',
  'symptom:play': 'attention',
  'symptom:roughness': 'attention',
  'symptom:noise': 'attention',
};

const List<String> _statusRank = ['ok', 'attention', 'critical'];

WheelDiagnosisFindings wheelDiagnosisFindings(Map<String, dynamic> answers) {
  String? status;
  for (final key in const ['tire_condition', 'rim_damage', 'symptom']) {
    final candidate = _statusByAnswer['$key:${answers[key]}'];
    if (candidate != null &&
        (status == null ||
            _statusRank.indexOf(candidate) > _statusRank.indexOf(status))) {
      status = candidate;
    }
  }
  return WheelDiagnosisFindings(
    tireCondition: _tireConditionByAnswer[answers['tire_condition']],
    rimCondition: _rimConditionByDamage[answers['rim_damage']],
    hubBearingCondition: _hubConditionBySymptom[answers['symptom']],
    status: status,
  );
}

/// La respuesta del asistente que corresponde a lo que el diagnóstico de esa
/// rueda ya dice, para precargarla.
Map<String, String> wheelAnswersFromDiagnosis({
  String? tireCondition,
  String? rimCondition,
  String? hubBearingCondition,
}) {
  String? reverse(Map<String, String> map, String? value) {
    for (final entry in map.entries) {
      if (entry.value == value) return entry.key;
    }
    return null;
  }

  final tire = reverse(_tireConditionByAnswer, tireCondition);
  final rim = reverse(_rimConditionByDamage, rimCondition) ??
      (rimCondition == 'cracked' ? 'major' : null);
  final hub = reverse(_hubConditionBySymptom, hubBearingCondition);
  return {
    if (tire != null) 'tire_condition': tire,
    if (rim != null) 'rim_damage': rim,
    if (hub != null) 'symptom': hub,
  };
}
