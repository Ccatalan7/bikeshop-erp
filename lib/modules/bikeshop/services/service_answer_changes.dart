/// Las respuestas del asistente que dicen algo distinto de su precarga
/// (revisión de Codex del paso C–F, 2026-09-27).
///
/// Una respuesta igual a lo que el diagnóstico ya decía es esa misma lectura
/// devuelta, no un hallazgo nuevo. Reescribirla pierde lo que la pregunta no
/// distingue: un rotor contaminado se precarga como contaminación «moderada»
/// y volvía como pastillas contaminadas; un aro fisurado se precarga como daño
/// «mayor» y volvía golpeado; un crujido de pedalier se precarga como «ruido»
/// y volvía como «requiere revisión».
library;

Map<String, dynamic> answersChangedFromPrefill(
  Map<String, dynamic> answers,
  Map<String, Object?> prefill,
) =>
    {
      for (final entry in answers.entries)
        if (!_sameAnswer(entry.value, prefill[entry.key]))
          entry.key: entry.value,
    };

bool _sameAnswer(Object? answer, Object? prefill) {
  if (answer == null || prefill == null) return answer == prefill;
  if (answer is List && prefill is List) {
    final left = answer.map((value) => value.toString()).toList()..sort();
    final right = prefill.map((value) => value.toString()).toList()..sort();
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
  return answer.toString() == prefill.toString();
}

/// Las respuestas con las que se abre «Configurar»: lo guardado en la línea,
/// pero lo que el diagnóstico dice hoy manda en sus preguntas. La capa del
/// diagnóstico es el mismo registro de la pestaña, no una copia: si se la
/// precargara con la respuesta vieja de la línea, guardar sin tocarla la
/// compararía con el diagnóstico actual y lo reescribiría (un aro que pasó a
/// fisurado volvía «menor»; revisión del paso F.2, 2026-09-27).
Map<String, dynamic> answersWithDiagnosisPrefill(
  Map<String, dynamic> saved,
  Map<String, Object?> fromDiagnosis,
) =>
    {
      ...saved,
      for (final entry in fromDiagnosis.entries)
        if (entry.value != null) entry.key: entry.value,
    };
