/// Lo que un servicio de rueda (familia `wheels`) lee de la ficha y lo que le
/// devuelve (paso C del backbone, 2026-09-27).
///
/// La ficha guarda dos clases de datos de rueda, y la respuesta de un servicio
/// vale distinto para cada una:
///
/// - **Por posición** (`frontSpokeHoles`, `rearSpokeHoles`): las pregunta el
///   Enrayado y describen la rueda que se arma, no la que llegó. Son estado
///   instalado: la ficha cambia **al terminar el trabajo**, nunca al
///   configurar. La escribe el servidor en la misma transacción que termina
///   el trabajo (`apply_job_installed_bike_facts_internal`, ítem 4);
///   [wheelInstalledFacts] es la misma regla para anunciarla en el asistente. Una sola respuesta para «ambas» no se escribe: 3 de
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
import '../config/drivetrain_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bikeshop_models.dart';
import 'bike_technical_fact_patch.dart' show kBikeWheelSizeFactKey;
import 'part_bike_fact_change.dart' show bikeRequirementLabel, kWheelSizeAdvice;

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
      'frontRotorMount' || 'rearRotorMount' => rotorMountLabel(value),
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

/// Lo que el servidor no pudo escribir en la ficha al terminar un trabajo
/// (`installed_bike_facts.problems` de la transición o de
/// `sync_job_installed_bike_facts_v1`), dicho en el taller y con qué hacer.
List<String> installedBikeFactProblemMessages(Object? installed) {
  if (installed is! Map) return const [];
  final problems = installed['problems'];
  if (problems is! List) return const [];
  return [
    for (final problem in problems.whereType<Map>())
      _installedProblemMessage(
        item: problem['item_name']?.toString().trim(),
        fact: wheelInstalledFactLabel(
          problem['key']?.toString() ?? '',
          problem['value'],
        ),
        reason: problem['reason']?.toString(),
        message: problem['message']?.toString(),
        bike: problem['bike_label']?.toString().trim(),
        wheel: _spokeHoleKeys.contains(problem['key']?.toString()) ||
            problem['key'] == null,
        requiresKey: problem['requires_key']?.toString(),
        requires: problem['requires_value']?.toString(),
        requiresSource: problem['requires_source']?.toString(),
        pending: problem['pending']?.toString(),
        previous: problem['previous'] == null
            ? null
            : wheelInstalledFactLabel(
                problem['key']?.toString() ?? '',
                problem['previous'],
              ),
      ),
  ];
}

const Set<String> _spokeHoleKeys = {'frontSpokeHoles', 'rearSpokeHoles'};

String _installedProblemMessage({
  required String? item,
  required String fact,
  required String? reason,
  required String? message,
  String? bike,
  String? previous,
  bool wheel = true,
  String? requiresKey,
  String? requires,
  String? requiresSource,
  String? pending,
}) {
  final line = item == null || item.isEmpty ? 'Una línea' : '«$item»';
  // Con qué no calza: la ficha, o lo que instala el mismo trabajo en esa
  // rueda (`requires_source`, 20260928130000, 20260928140000).
  final against = switch (requiresSource) {
    'job_hub' => 'la maza que instala el trabajo',
    'job_build' => 'la rueda que arma el trabajo',
    'job_rim' => 'la llanta que instala el trabajo',
    'job_tire' => 'el neumático que instala el trabajo',
    _ => 'la ficha de la bici',
  };
  final side = requiresKey != null && requiresKey.startsWith('front')
      ? 'delanter'
      : 'traser';
  final bikeName = bike == null || bike.isEmpty ? 'otra bici' : bike;
  return switch (reason) {
    // La línea pasó a otra bici o rueda, o se borró: lo que escribió no se
    // deshace solo, porque no se sabe cuál asignación era la equivocada.
    'no_longer_installed' => 'La ficha de $bikeName sigue diciendo $fact por '
        '${item == null || item.isEmpty ? 'una línea que ya no está' : line}, '
        'que ya no dice haberlo instalado ahí'
        '${previous == null ? ' (antes no tenía el dato)' : ' (antes: $previous)'}. '
        '${wheel ? 'Si esa rueda no se armó' : 'Si esa pieza no se instaló'}, '
        'corrige su ficha; si sí, vuelve a elegir el dato en su campo de la '
        'ficha para confirmarlo.',
    'line_without_bike' => '$line no dice de qué bici es: la ficha no tomó '
        '$fact. Asígnala a su bici («Asignar a…» en el menú de la línea) y '
        'guarda el trabajo.',
    'out_of_range' => wheel
        ? '$line dice $fact, fuera de 12 a 48 perforaciones: la ficha no lo '
            'tomó. Corrige la línea y guarda el trabajo.'
        : '$line dice $fact, fuera de lo que acepta la ficha: no lo tomó. '
            'Revisa la ficha técnica del repuesto.',
    // Un repuesto que no calza con la bici: un rotor en una bici con freno
    // de llanta confirmado; un neumático cuyo BSD no es el de su rueda, o
    // que el aro escrito de la bici no admite (el mismo texto que
    // `bike_fact_requirement_text` y `bike_fact_requirement_advice`).
    'incompatible' => switch (requiresKey) {
        kBikeWheelSizeFactKey => '$line dice $fact, pero la ficha de '
            'la bici dice aro $requires: la ficha no cambió. $kWheelSizeAdvice',
        // Una llanta que no calza con su maza, su Enrayado o su neumático, o
        // un neumático con la llanta del trabajo (20260928140000).
        'frontHubSpokeHoles' || 'rearHubSpokeHoles' => '$line dice $fact, '
            'pero $against dice que la maza ${side}a tiene $requires '
            'perforaciones: la ficha no cambió. $_rimHubAdvice',
        'frontBuildSpokeHoles' || 'rearBuildSpokeHoles' => '$line dice $fact, '
            'pero $against dice que la rueda ${side}a lleva $requires rayos: '
            'la ficha no cambió. $_rimBuildAdvice',
        'frontTireBsdMm' || 'rearTireBsdMm' => '$line dice $fact, pero '
            '$against dice que el neumático ${side}o es '
            '${_bsdRequirement(requires)}: la ficha no cambió. $_rimTireAdvice',
        'frontRimBsdMm' || 'rearRimBsdMm' => '$line dice $fact, pero '
            '$against dice que la llanta ${side}a es '
            '${_bsdRequirement(requires)}: la ficha no cambió. $_tireRimAdvice',
        final key? when kWheelBsdFactKeyByPosition.containsValue(key) =>
          '$line dice $fact, pero la ficha de la bici dice que '
              '${key == 'frontWheelBsdMm' ? 'la rueda delantera' : 'la rueda trasera'} '
              'es ${isoWheelBsdLabel(int.tryParse(requires ?? '') ?? 0)}: la '
              'ficha no cambió. $_tireAdvice',
        // Un cassette o piñón de rosca que no entra en el driver de la maza,
        // o con otros piñones que la transmisión (20260928120000).
        'freehubType' => '$line dice $fact, pero $against dice que '
            'el driver trasero es «${_freehubLabel(requires)}»: la ficha no '
            'cambió. $_freehubAdvice',
        // Una maza que no se raya en la rueda que queda, o un rotor que no
        // entra en el anclaje de su maza (20260928130000).
        'frontSpokeHoles' || 'rearSpokeHoles' => '$line dice $fact, pero '
            '$against dice que la rueda '
            '${requiresKey == 'frontSpokeHoles' ? 'delantera' : 'trasera'} '
            'lleva $requires rayos: la ficha no cambió. $_spokeHolesAdvice',
        'frontRotorMount' || 'rearRotorMount' => '$line dice $fact, pero '
            '$against dice que el anclaje del rotor '
            '${requiresKey == 'frontRotorMount' ? 'delantero' : 'trasero'} '
            'es «${rotorMountLabel(requires)}»: la ficha no cambió. '
            '$_rotorMountAdvice',
        'drivetrainConfig' => '$line dice $fact, pero la transmisión de la '
            'ficha es $requires: la ficha no cambió. $_drivetrainAdvice',
        _ => '$line dice $fact, pero en la ficha el tipo de freno '
            'es «${bikeRequirementLabel(requires)}»: la ficha no cambió. Si la '
            'bici lleva freno de disco, corrige el tipo de freno en su ficha; '
            'si no, quita la línea.',
      },
    // No calza con la ficha, pero el mismo trabajo cambia la pieza que lo
    // decide: nada se escribe y el mecánico lo decide en la ficha
    // (`bike_fact_pending_text`).
    'pending' => '$line dice $fact y la ficha de la bici dice '
        '${requiresKey == 'drivetrainConfig' ? 'que la transmisión es $requires' : 'que el driver trasero es «${_freehubLabel(requires)}»'}, '
        'pero ${pending == 'hub_change' ? 'el trabajo también cambia la maza trasera: el driver lo dice la maza nueva. Elígelo en la ficha de la bici' : 'el trabajo también cambia el mando trasero: si la transmisión cambió, corrígela en la ficha de la bici'} '
        'y guarda el trabajo. La ficha no cambió.',
    // Dos Enrayados de la misma rueda que no dicen lo mismo (20260928130000).
    'conflicting_build' => '$line dice $fact, pero otro Enrayado del mismo '
        'trabajo arma esa rueda a $requires rayos: la ficha no cambió. Una '
        'rueda se arma una vez: deja una sola línea con la cantidad real y '
        'guarda el trabajo.',
    // Una línea instala una sola cosa.
    'mixed_change' => '$line dice perforaciones y un cambio de repuesto a la '
        'vez: la ficha no tomó ninguno. Deja en la línea sólo lo que instaló '
        'y guarda el trabajo.',
    // Lo que el mecánico vio al elegir la rueda ya no es el repuesto o la
    // rueda de la línea.
    'stale_change' => '$line: el cambio de ficha que guardó ($fact) ya no '
        'calza con su repuesto o con la rueda elegida, y la ficha no cambió. '
        'Ábrela, vuelve a elegir la rueda y guarda el trabajo.',
    'no_wheel' => '$line tiene perforaciones pero no dice qué rueda armó: '
        'la ficha no cambió. Elige la rueda en Configurar y guarda el trabajo.',
    'invalid_value' => '$line no dice un número de perforaciones que la '
        'ficha entienda: no cambió. Corrige la línea y guarda el trabajo.',
    _ => 'La ficha no tomó $fact de $line'
        '${message == null || message.isEmpty ? '' : ' ($message)'}; se '
        'reintenta al guardar el trabajo o volver a cambiar su estado.',
  };
}

const String _tireAdvice = 'Revisa la medida del neumático y la de esa '
    'rueda: si el neumático sí va ahí, corrige la ficha de la bici y guarda '
    'el trabajo; si no, cambia la línea.';

const String _rimHubAdvice = 'Una llanta se raya en una maza con sus mismas '
    'perforaciones (o con más, en los patrones de Sheldon Brown), nunca con '
    'menos: si también cambiaste la maza, agrega su línea en esa rueda; si la '
    'maza tiene otra cantidad, corrige la ficha; si no, cambia la línea.';

const String _rimBuildAdvice = 'La rueda queda con las perforaciones de su '
    'llanta: si el Enrayado u otra llanta de esa rueda dice otra cantidad, '
    'corrige esa línea; si no, cambia ésta.';

const String _rimTireAdvice = 'Una llanta y su neumático tienen el mismo '
    'BSD: si también cambiaste el neumático, agrega su línea en esa rueda; si '
    'la rueda es otra, corrige la ficha; si no, cambia la línea.';

const String _tireRimAdvice = 'Un neumático calza sólo en una llanta de su '
    'mismo BSD: si la llanta del trabajo es la que va, cambia esta línea; si '
    'no, corrige la de la llanta.';

/// «584 (27,5″/650b)», o tal cual si son dos («584 o 622»).
String _bsdRequirement(String? value) {
  final whole = int.tryParse(value ?? '');
  return whole == null ? value ?? '?' : isoWheelBsdLabel(whole);
}

const String _freehubAdvice = 'Revisa el núcleo de la maza trasera: si es '
    'otro, corrige el driver en la ficha de la bici y guarda el trabajo; si '
    'no, cambia la línea.';

const String _spokeHolesAdvice = 'Una maza con menos perforaciones que la '
    'llanta no se puede rayar: si también cambiaste la llanta, agrega su '
    'línea en esa rueda; si la rueda lleva otra cantidad, corrige la ficha; '
    'si no, cambia la línea.';

const String _rotorMountAdvice = 'Un rotor Center Lock no va en una maza de '
    '6 pernos, y uno de 6 pernos va en una Center Lock sólo con el adaptador '
    'SM-RTAD05, que no sirve con araña de aluminio (flotantes, SM-RT86 y '
    'SM-RT76): si la maza es otra, corrige la ficha; si no, cambia la línea.';

const String _drivetrainAdvice = 'Un cassette o piñón de otra velocidad '
    'necesita el mando de esa velocidad: si también lo cambiaste, agrega su '
    'línea o corrige la transmisión en la ficha; si no, cambia la línea.';

String _freehubLabel(Object? code) =>
    kDrivetrainFreehubTypeOptions['$code'] ?? '$code';

/// Cómo se dice en el taller un dato instalado: «28H en la rueda trasera»,
/// «180 mm en el rotor trasero», «622 (29″/700c) en la rueda trasera» (el
/// mismo texto que `installed_bike_fact_label` en el servidor).
String wheelInstalledFactLabel(String key, Object? value) => switch (key) {
      'frontSpokeHoles' => '${value}H en la rueda delantera',
      'rearSpokeHoles' => '${value}H en la rueda trasera',
      'frontRotorSizeMm' => '$value mm en el rotor delantero',
      'rearRotorSizeMm' => '$value mm en el rotor trasero',
      'frontWheelBsdMm' => '${_bsd(value)} en la rueda delantera',
      'rearWheelBsdMm' => '${_bsd(value)} en la rueda trasera',
      'freehubType' => '${_freehubLabel(value)} en el driver trasero',
      'frontRotorMount' =>
        '${rotorMountLabel(value)} en el anclaje del rotor delantero',
      'rearRotorMount' =>
        '${rotorMountLabel(value)} en el anclaje del rotor trasero',
      _ => '${_factLabel[key] ?? key} $value',
    };

String _bsd(Object? value) {
  final bsd = value is num ? value.toInt() : int.tryParse('$value');
  return bsd == null ? '$value' : isoWheelBsdLabel(bsd);
}

const Map<String, String> _factLabel = {
  'frontSpokeHoles': 'perforaciones delanteras',
  'rearSpokeHoles': 'perforaciones traseras',
  'valveType': 'válvula',
  'brakeType': 'tipo de freno',
  'rimBrakeFamily': 'familia de freno de llanta',
  'frontRotorSizeMm': 'rotor delantero',
  'rearRotorSizeMm': 'rotor trasero',
  'frontWheelBsdMm': 'diámetro de la rueda delantera (BSD)',
  'rearWheelBsdMm': 'diámetro de la rueda trasera (BSD)',
  'frontBrakeFluidType': 'fluido del freno delantero',
  'rearBrakeFluidType': 'fluido del freno trasero',
  'frontAxleInterface': 'eje delantero',
  'rearAxleInterface': 'eje trasero',
  'freehubType': 'driver trasero',
  'drivetrainConfig': 'transmisión',
  'frontRotorMount': 'anclaje del rotor delantero',
  'rearRotorMount': 'anclaje del rotor trasero',
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
