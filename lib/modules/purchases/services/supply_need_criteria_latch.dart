import '../models/intelligent_purchasing_models.dart';

/// La ficha vigente de una necesidad, para quien tenga que juzgar **después**.
///
/// Abrir una necesidad lanza la lectura de sus criterios **sin esperarla**: el
/// stock, los candidatos y el plan no se cuelgan de una glosa. Pero el feed ya
/// guardado del proveedor se vuelve a juzgar en ese mismo tramo, y si lee el
/// último valor pintado en pantalla puede estar leyendo la ficha ANTERIOR:
/// entre precisar y repintar, ese valor todavía es el viejo, y encima el
/// atajo «si no está vacío no lo pidas» hacía que nunca se corrigiera hasta
/// otra recarga. El resultado era una lista rotulada con la ficha de antes.
///
/// El pestillo guarda la lectura **en vuelo** —no su resultado— para que quien
/// necesite la ficha vigente la espere sin volver a pedirla, y sin que nadie
/// más se bloquee.
class SupplyNeedCriteriaLatch {
  String? _needId;
  Future<SupplyNeedCriteria>? _pending;

  /// Se llama al **lanzar** la lectura, no al terminarla: quien pregunta un
  /// instante después tiene que encontrarla ya publicada.
  void publish(String needId, Future<SupplyNeedCriteria> load) {
    _needId = needId;
    _pending = load;
    // Un fallo acá lo reporta quien espera; sin esto Dart lo trataría como
    // error asíncrono no observado y tumbaría la zona.
    load.then((_) {}, onError: (Object _) {});
  }

  void forget() {
    _needId = null;
    _pending = null;
  }

  /// La ficha con la que hay que juzgar ahora.
  ///
  /// [painted] es lo que la pantalla tiene puesto, y sólo se usa cuando no hay
  /// nada en vuelo. [fetch] es el último recurso: una necesidad recién abierta
  /// cuya glosa aún no se pidió.
  Future<SupplyNeedCriteria> resolve({
    required String needId,
    required SupplyNeedCriteria painted,
    required Future<SupplyNeedCriteria> Function() fetch,
  }) async {
    final pending = _needId == needId ? _pending : null;
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        // La lectura falló; se sigue con lo que haya, no se inventa una ficha.
      }
    }
    if (painted.categoryId == null && painted.predicates.isEmpty) {
      return fetch();
    }
    return painted;
  }
}
