import 'dart:async';

/// Una navegación headless por proveedor a la vez.
///
/// **Dos recorridos que comparten una cookie se pisan sin avisar.** El portal
/// de RBX es un ASP legacy que guarda estado por sesión: mientras una consulta
/// exacta por SKU navega, una enumeración por necesidad cambia la
/// clasificación bajo sus pies, y las dos informan filas que no son de su
/// nodo. Ninguna de las dos falla: las dos mienten.
///
/// Por eso la cola es UNA sola para todas las navegaciones de un proveedor —la
/// exacta y la de necesidad—, y vive fuera del runner para poder probarse sin
/// un navegador.
///
/// Dos propiedades que no son opcionales:
///
///  * **FIFO.** Cada llamada publica su turno antes de esperar el anterior, así
///    que el orden de llegada es el orden de ejecución.
///  * **Reentrante.** Si un cuerpo ya en turno vuelve a pedir el mismo
///    proveedor, se ejecuta en línea. Sin esto, «serializar todo» se convierte
///    en un abrazo mortal la primera vez que alguien componga dos operaciones.
class SupplierPortalNavigationQueue {
  SupplierPortalNavigationQueue();

  static final SupplierPortalNavigationQueue shared =
      SupplierPortalNavigationQueue();

  static const Object _zoneKey = #vinabikeSupplierPortalNavigation;

  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  /// Cuántos proveedores tienen turno vivo. Sólo para pruebas y diagnóstico.
  int get pendingSuppliers => _tails.length;

  /// Corre [body] cuando le toque el turno de [supplierId].
  Future<T> run<T>(String supplierId, Future<T> Function() body) async {
    final key = supplierId.trim();
    if (key.isEmpty) return body();

    final held = Zone.current[_zoneKey];
    final owned = held is Set<String> ? held : const <String>{};
    if (owned.contains(key)) {
      // Ya tenemos el turno de este proveedor: volver a pedirlo se esperaría a
      // sí mismo para siempre.
      return body();
    }

    final previous = _tails[key];
    final gate = Completer<void>();
    _tails[key] = gate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // Que la navegación anterior fallara no le quita el turno a ésta.
      }
    }
    try {
      return await runZoned<Future<T>>(
        body,
        zoneValues: <Object, Object>{
          _zoneKey: <String>{...owned, key},
        },
      );
    } finally {
      gate.complete();
      if (identical(_tails[key], gate.future)) {
        _tails.remove(key);
      }
    }
  }
}
