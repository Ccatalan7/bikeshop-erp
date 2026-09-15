import '../../../shared/services/catalog_name_reading.dart';

/// La contabilidad de la lectura del catálogo, por necesidad.
///
/// Vive fuera de la pantalla porque su parte difícil no es dibujar nada: es
/// decidir **qué se puede volver a preguntar y qué no**, y esa decisión sólo se
/// prueba de verdad simulando idas y vueltas del operador. Dentro del `State`
/// de un workspace de siete mil líneas eso obliga a montar el módulo entero
/// para ejercitar tres `Set`.
///
/// Tres memorias, con tres razones distintas:
///
///  - `_leidas` evita repetir la misma pregunta al modelo dentro de la misma
///    visita. La llave es el conjunto de huecos, no la necesidad: si una pasada
///    llenó algo, quedan menos huecos y la llave cambia sola.
///  - `_ofrecidas` evita repetirle al servidor un hecho que ya juzgó. Un
///    rechazo es una respuesta y da lo mismo siempre; volver a mandarlo gasta
///    presupuesto que necesita lo que viene detrás.
///  - `_presupuesto` acota la cadena automática de una visita completa, no de
///    cada vuelta.
class CatalogReadingLedger {
  final Map<String, Set<String>> _leidas = <String, Set<String>>{};
  final Map<String, Set<String>> _ofrecidas = <String, Set<String>>{};
  final Map<String, int> _presupuesto = <String, int>{};

  /// Lo que ya se le ofreció al servidor para esta necesidad. Se le pasa al
  /// lector, que lo lee y lo escribe.
  Set<String> offeredFor(String needId) =>
      _ofrecidas.putIfAbsent(needId, () => <String>{});

  /// Cuánto presupuesto de escritura le queda a esta necesidad en esta visita.
  int budgetFor(String needId) =>
      _presupuesto[needId] ?? kCatalogNameReadingRecordCap;

  /// **Entrar de verdad repone el presupuesto.** Abrir la necesidad o
  /// reabrirla es una visita nueva; la continuación automática no lo es, o el
  /// tope dejaría de serlo.
  void enter(String needId) =>
      _presupuesto[needId] = kCatalogNameReadingRecordCap;

  /// Si vale la pena leer este conjunto de huecos, y lo reserva si sí.
  ///
  /// Devuelve la llave reservada, o `null` si ya se leyó o no queda
  /// presupuesto. Quien la recibe **tiene que** devolverla con [settle].
  String? claim(String needId, Iterable<String> holes) {
    if (budgetFor(needId) <= 0) return null;
    final ordenados = holes.toList()..sort();
    if (ordenados.isEmpty) return null;
    final llave = '$needId >> ${ordenados.join(',')}';
    return _leidas.putIfAbsent(needId, () => <String>{}).add(llave)
        ? llave
        : null;
  }

  /// Cierra una pasada: descuenta lo gastado y decide si la llave se suelta.
  ///
  /// **Una pasada que no llegó a preguntar no consume su llave.** El caso que
  /// lo obliga: el operador cambia de necesidad mientras el modelo responde,
  /// la lectura se suelta sin escribir, y al volver a esa misma necesidad los
  /// huecos son los mismos y la llave también. Con la llave retenida, esa
  /// necesidad quedaba muda el resto de la visita aunque el presupuesto se
  /// hubiera repuesto. Lo que sí obtuvo veredicto no vuelve a ofrecerse: de eso
  /// se ocupa `_ofrecidas`, que es otra memoria y no se suelta.
  void settle(String needId, String key, CatalogNameReadingOutcome outcome) {
    _presupuesto[needId] = budgetFor(needId) - outcome.attemptsSpent;
    if (outcome.retryable) _leidas[needId]?.remove(key);
  }

  /// Si la cadena automática puede dar otra vuelta con lo que queda.
  bool canContinue(String needId, CatalogNameReadingOutcome outcome) =>
      outcome.hasMoreToOffer && !outcome.retryable && budgetFor(needId) > 0;
}
