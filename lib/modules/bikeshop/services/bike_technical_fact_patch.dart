import '../models/bikeshop_models.dart';

/// Claves de la ficha que un servicio del trabajo puede escribir. Son las
/// mismas que acepta `patch_bike_technical_facts_v1`; una clave fuera de esta
/// lista no se manda, se rechaza antes (ver [bikeTechnicalFactsDiff]).
const Set<String> kServiceWritableNumericProfileKeys = {
  'frontRotorSizeMm',
  'rearRotorSizeMm',
  'drivetrainSpeeds',
  'bbShellWidthMm',
  'bbShellDiameterMm',
  'frontSpokeHoles',
  'rearSpokeHoles',
  // El BSD de cada rueda (ISO 5775), de 150 a 700 mm (20260928110000).
  'frontWheelBsdMm',
  'rearWheelBsdMm',
};

const Set<String> kServiceWritableTextProfileKeys = {
  'brakeType',
  'rimBrakeFamily',
  'drivetrainConfig',
  'freehubType',
  'bottomBracketFamily',
  'spindleInterface',
  'valveType',
  // Paso F.2: códigos del registro (`fluid_type`, `axle_type`). El fluido es
  // de cada freno (20260928040000).
  'frontBrakeFluidType',
  'rearBrakeFluidType',
  'frontAxleInterface',
  'rearAxleInterface',
  // El anclaje del rotor de cada rueda: lo escribe la maza instalada al
  // terminar el trabajo (20260928130000).
  'frontRotorMount',
  'rearRotorMount',
};

/// La columna `bikes.wheel_size`, que el comando escribe con las etiquetas de
/// la ficha.
const String kBikeWheelSizeFactKey = 'bikes.wheel_size';

/// Fuente de un dato de la bici completa que un servicio vio en una sola
/// rueda: queda sugerido, sin confirmar (ver `wheel_service_facts.dart`).
const String kServiceSuggestionSource = 'service_wizard';

bool isServiceWritableProfileKey(String key) =>
    kServiceWritableNumericProfileKeys.contains(key) ||
    kServiceWritableTextProfileKeys.contains(key);

/// Un dato de la ficha que un servicio confirma, cambia o borra. [expected]
/// y [expectedConfirmed] son lo que la app vio: si la ficha ya no dice eso
/// —otro valor, o el mismo confirmado por alguien más—, el servidor rechaza el
/// comando entero en vez de pisar un cambio ajeno.
class BikeTechnicalFact {
  const BikeTechnicalFact.set({
    required this.key,
    required Object this.value,
    required this.expected,
    required this.expectedConfirmed,
  })  : remove = false,
        suggest = false;

  const BikeTechnicalFact.remove({
    required this.key,
    required this.expected,
    required this.expectedConfirmed,
  })  : remove = true,
        suggest = false,
        value = null;

  /// Llena un dato que la ficha no sabía, sin confirmarlo. El servidor no lo
  /// escribe si la ficha ya tiene un valor.
  const BikeTechnicalFact.suggest({
    required this.key,
    required Object this.value,
    required this.expected,
  })  : remove = false,
        suggest = true,
        expectedConfirmed = false;

  final String key;
  final Object? value;
  final Object? expected;
  final bool expectedConfirmed;
  final bool remove;
  final bool suggest;

  Map<String, dynamic> toJson() => {
        'key': key,
        'op': remove ? 'remove' : (suggest ? 'suggest' : 'set'),
        if (!remove) 'value': value,
        'expected': expected,
        'expected_confirmed': expectedConfirmed,
      };

  @override
  String toString() => remove
      ? 'remove $key (era $expected)'
      : 'set $key = $value (era $expected)';
}

/// Lo que la promoción cambió respecto de la ficha cargada, clave por clave.
///
/// - una clave que aparece o cambia de valor se manda con `set`;
/// - una clave que desaparece se manda con `remove`;
/// - una clave con el mismo valor que pasa a confirmada se manda con `set`
///   del mismo valor, que el servidor registra como confirmación;
/// - una clave nueva con fuente [kServiceSuggestionSource] y sin confirmar se
///   manda con `suggest`: sólo llena lo que la ficha no sabía.
///
/// Si la promoción tocó una clave fuera del contrato, lanza [StateError]:
/// perderla en silencio es justo la deriva que el backbone prohíbe.
List<BikeTechnicalFact> bikeTechnicalFactsDiff({
  required BikeProfile? baseline,
  required BikeProfile target,
}) {
  final baselineValues = baseline?.technicalValues ?? const <String, dynamic>{};
  final baselineConfirmed =
      baseline?.technicalConfirmed ?? const <String, dynamic>{};
  final targetValues = target.technicalValues;
  final targetConfirmed = target.technicalConfirmed;
  final targetSources = target.technicalSources;

  final keys = {...baselineValues.keys, ...targetValues.keys}.toList()..sort();
  final facts = <BikeTechnicalFact>[];
  for (final key in keys) {
    final before = baselineValues[key];
    final after = targetValues[key];
    final sameValue = _sameFactValue(before, after);
    final newlyConfirmed =
        targetConfirmed[key] == true && baselineConfirmed[key] != true;

    if (sameValue && !newlyConfirmed) continue;

    if (!isServiceWritableProfileKey(key)) {
      throw StateError(
        'La promoción desde un servicio cambió «$key», que no está en el '
        'contrato de claves escribibles.',
      );
    }

    final expectedConfirmed = baselineConfirmed[key] == true;
    if (after == null) {
      if (before != null) {
        facts.add(BikeTechnicalFact.remove(
          key: key,
          expected: before,
          expectedConfirmed: expectedConfirmed,
        ));
      }
      continue;
    }

    if (targetSources[key] == kServiceSuggestionSource &&
        targetConfirmed[key] != true) {
      if (before != null && !_isUnknownFactValue(before)) {
        throw StateError(
          'Una sugerencia no reemplaza «$key», que la ficha ya tenía '
          '(«$before»).',
        );
      }
      facts.add(BikeTechnicalFact.suggest(
        key: key,
        value: _canonicalFactValue(key, after),
        expected: before,
      ));
      continue;
    }

    facts.add(BikeTechnicalFact.set(
      key: key,
      value: _canonicalFactValue(key, after),
      expected: before,
      expectedConfirmed: expectedConfirmed,
    ));
  }
  return facts;
}

bool _isUnknownFactValue(Object value) {
  final text = value.toString().trim().toLowerCase();
  return text == 'unknown' || text == 'desconocido';
}

bool _sameFactValue(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  return a == b;
}

Object _canonicalFactValue(String key, Object value) {
  if (!kServiceWritableNumericProfileKeys.contains(key)) return value;
  if (value is num) return value;
  final parsed = num.tryParse(value.toString().replaceAll(',', '.'));
  if (parsed == null) {
    throw StateError('«$key» debe ser un número y vino «$value».');
  }
  return parsed;
}

/// La ficha cambió desde que se abrió el trabajo: el servidor no pisó nada.
class BikeTechnicalFactConflict implements Exception {
  const BikeTechnicalFactConflict(this.keys);

  final List<String> keys;

  @override
  String toString() => keys.isEmpty
      ? 'La ficha de la bicicleta cambió mientras editabas el trabajo. '
          'Recarga el trabajo antes de guardar.'
      : 'La ficha de la bicicleta cambió mientras editabas el trabajo '
          '(${keys.join(', ')}). Recarga el trabajo antes de guardar.';
}

/// El servidor rechazó el dato y no aplicó nada: no se reintenta.
class BikeTechnicalFactRejected implements Exception {
  const BikeTechnicalFactRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Lo que «Configurar» confirmó para una bici y todavía no llega a su ficha.
/// Viaja con las líneas del trabajo en `save_mechanic_job_lines_v1`; la llave
/// cambia cada vez que «Configurar» vuelve a promover esa bici, y así el
/// guardado sabe si lo que escribió sigue siendo lo pendiente.
class PendingBikeFactPromotion {
  const PendingBikeFactPromotion({
    required this.operationKey,
    required this.baseline,
    required this.target,
  });

  final String operationKey;
  final BikeProfile? baseline;
  final BikeProfile target;
}
