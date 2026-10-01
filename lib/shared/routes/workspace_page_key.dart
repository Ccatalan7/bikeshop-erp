import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// La identidad de una página del ERP es su ruta **concreta**.
///
/// go_router arma `state.pageKey` con el patrón (`/taller/pegas/:id`), no con
/// el id: ir con `go` de una ficha a otra del mismo tipo —el buscador global,
/// un enlace, Atrás/Adelante del espacio— reutilizaba la página y su `State`
/// seguía mostrando la primera (dueño, 2026-10-01: con PG-00596 abierto,
/// elegir PG-00594 en el buscador no cambiaba la pantalla). La misma ficha
/// conserva su llave, así que reconstruirla no reinicia su estado; una página
/// apilada con `push` ya trae una llave única y la sigue teniendo.
LocalKey workspacePageKey(GoRouterState state) =>
    ValueKey<String>('${state.pageKey.value}@${state.matchedLocation}');
