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

/// Lo que «Configurar» confirmó para una bici y todavía no llega a su ficha,
/// con la llave del intento para que el reintento no se escriba dos veces.
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

/// Trabajo y ficha se guardan en dos llamadas. Lo que no alcanzó a llegar a
/// la ficha después de guardar el trabajo queda aquí, por id de trabajo, hasta
/// que un intento lo escriba o lo descarte; el formulario que abre ese trabajo
/// lo retoma. Vive en memoria: si la app se cierra antes, las respuestas siguen
/// en la línea y «Configurar» las vuelve a confirmar contra la ficha vigente.
/// Sólo [writePendingBikeFactPromotions] lo escribe.
final Map<String, Map<String, PendingBikeFactPromotion>>
    unsentBikeFactPromotionsByJob = {};

typedef BikeFactPatcher = Future<BikeProfile?> Function({
  required String operationKey,
  required String bikeId,
  required String jobId,
  required List<BikeTechnicalFact> facts,
});

/// Cómo terminó escribir en la ficha lo pendiente de un trabajo, por bici.
class BikeFactWriteOutcome {
  const BikeFactWriteOutcome({
    required this.written,
    required this.discarded,
    required this.failed,
  });

  /// Ficha al día, con la que devolvió el servidor (null si no había nada que
  /// escribir).
  final Map<String, BikeProfile?> written;

  /// Promociones que ya no valen: la ficha cambió desde que se cargó
  /// ([BikeTechnicalFactConflict]) o traen una clave fuera del contrato
  /// ([StateError]). El mecánico vuelve a confirmar en «Configurar».
  final Map<String, Object> discarded;

  /// Promociones que no llegaron por otra razón: siguen pendientes, con su
  /// llave, para el próximo intento.
  final Map<String, Object> failed;
}

/// Escribe, bici por bici, lo que confirmó «Configurar», y deja en
/// [unsentBikeFactPromotionsByJob] sólo lo que falló sin ser descartado: un
/// reintento que vuelve a fallar no lo pierde (Codex, 2026-09-27).
Future<BikeFactWriteOutcome> writePendingBikeFactPromotions({
  required String jobId,
  required Map<String, PendingBikeFactPromotion> pending,
  required BikeFactPatcher patch,
}) async {
  final written = <String, BikeProfile?>{};
  final discarded = <String, Object>{};
  final failed = <String, Object>{};
  final stillPending = <String, PendingBikeFactPromotion>{};

  for (final entry in pending.entries) {
    final bikeId = entry.key;
    final promotion = entry.value;
    final List<BikeTechnicalFact> facts;
    try {
      facts = bikeTechnicalFactsDiff(
        baseline: promotion.baseline,
        target: promotion.target,
      );
    } on StateError catch (error) {
      discarded[bikeId] = error;
      continue;
    }
    if (facts.isEmpty) {
      written[bikeId] = null;
      continue;
    }
    try {
      written[bikeId] = await patch(
        operationKey: promotion.operationKey,
        bikeId: bikeId,
        jobId: jobId,
        facts: facts,
      );
    } on BikeTechnicalFactConflict catch (conflict) {
      discarded[bikeId] = conflict;
    } catch (error) {
      failed[bikeId] = error;
      stillPending[bikeId] = promotion;
    }
  }

  if (stillPending.isEmpty) {
    unsentBikeFactPromotionsByJob.remove(jobId);
  } else {
    unsentBikeFactPromotionsByJob[jobId] = stillPending;
  }
  return BikeFactWriteOutcome(
    written: written,
    discarded: discarded,
    failed: failed,
  );
}

/// La llave con que una línea terminada escribe en la ficha lo que instaló:
/// `job_completion:<línea>:<n>:<datos>` (revisión de Codex del paso C–F,
/// 2026-09-27). El servidor exige que la línea sea de ese trabajo y de esa
/// bici.
///
/// `n` crece cada vez que la línea instala otra cosa. Con la llave anterior,
/// `<línea>:<datos>`, corregir una línea terminada de 28H a 32H y de vuelta a
/// 28H encontraba el primer recibo y dejaba la ficha en 32H. Devuelve null
/// cuando el último recibo de la línea ya dice lo mismo: es un reintento, o
/// alguien corrigió la ficha después y no se le pisa.
String? nextJobCompletionOperationKey({
  required String itemId,
  required Map<String, Object> installed,
  required Iterable<String> existingKeys,
}) {
  final factKeys = installed.keys.toList()..sort();
  final facts = factKeys.map((key) => '$key=${installed[key]}').join(',');
  final prefix = 'job_completion:$itemId:';
  var latest = 0;
  String? latestFacts;
  for (final key in existingKeys) {
    if (!key.startsWith(prefix)) continue;
    final rest = key.substring(prefix.length);
    final separator = rest.indexOf(':');
    final sequence =
        separator <= 0 ? null : int.tryParse(rest.substring(0, separator));
    if (sequence == null || sequence <= latest) continue;
    latest = sequence;
    latestFacts = rest.substring(separator + 1);
  }
  if (latestFacts == facts) return null;
  return '$prefix${latest + 1}:$facts';
}
