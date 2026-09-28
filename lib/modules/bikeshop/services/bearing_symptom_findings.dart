/// El síntoma de un servicio de pedalier o de dirección, en el vocabulario de
/// su diagnóstico (paso E del backbone, 2026-09-27).
///
/// `Ajuste/Mantención de Motor` y `Mantención de Dirección` preguntan un solo
/// síntoma que mezcla rodamiento y ruido. El diagnóstico los separa:
/// `bearingCondition`/`noiseStatus` en el pedalier y
/// `headsetBearingCondition`/`headsetNoiseStatus` en la dirección. Sólo se
/// traduce lo que la respuesta dice: «ruido» no dice si es crujido, click o
/// golpe, así que queda «requiere revisión»; «preventivo» no es un hallazgo.
library;

class BearingSymptomFindings {
  const BearingSymptomFindings({
    this.bearingCondition,
    this.noiseStatus,
    this.status,
  });

  /// Código de `_kBearingConditionOptions`.
  final String? bearingCondition;

  /// Código de `_kMechanicalNoiseStatusOptions`.
  final String? noiseStatus;

  /// `attention` cuando la respuesta es un síntoma; null si no dice nada.
  final String? status;

  bool get isEmpty =>
      bearingCondition == null && noiseStatus == null && status == null;
}

const Map<String, String> _bearingBySymptom = {
  'play': 'play',
  'roughness': 'rough',
  // Rodamiento apretado: hay que regularlo; no existe un código más exacto.
  'tightness': 'service',
};

BearingSymptomFindings bearingSymptomFindings(Object? symptom) {
  final bearing = _bearingBySymptom[symptom];
  if (bearing != null) {
    return BearingSymptomFindings(
      bearingCondition: bearing,
      status: 'attention',
    );
  }
  if (symptom == 'noise') {
    return const BearingSymptomFindings(
      noiseStatus: 'service',
      status: 'attention',
    );
  }
  return const BearingSymptomFindings();
}

/// El síntoma que corresponde a lo que el diagnóstico ya dice, para
/// precargarlo. Rodamiento antes que ruido, como el orden de la pregunta.
String? bearingSymptomFromDiagnosis({
  String? bearingCondition,
  String? noiseStatus,
}) {
  switch (bearingCondition) {
    case 'play':
      return 'play';
    case 'rough':
      return 'roughness';
  }
  if (noiseStatus != null && noiseStatus != 'ok') return 'noise';
  return null;
}
