import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Las rutas diferidas no pueden reiniciar su `State` al reconstruirse.**
///
/// El 2026-08-01, en la app viva y contra producción, cruzar los 900 px borraba
/// el borrador entero de la conciliación de cartolas: la extracción OCR y las
/// 20+ decisiones ya tomadas desaparecían y la pantalla volvía al paso 1. Mismo
/// PID, cero reinicios.
///
/// La causa **no** era el `MainLayout` —ése ya reubica su hijo con un
/// `GlobalKey`— sino `_buildDeferredPageWithNoTransition` en el router:
/// envolvía cada página en un `FutureBuilder(future: erp.loadLibrary())`, y
/// `loadLibrary()` devuelve un `Future` **nuevo en cada llamada** aunque la
/// biblioteca ya esté cargada. Cada reconstrucción de la página devolvía el
/// builder a `ConnectionState.waiting`, que dibuja un esqueleto de **otro
/// tipo** que el árbol real, y Flutter destruía el subárbol entero.
///
/// Alcanzaba a **toda ruta diferida con estado en memoria**, no sólo a la
/// conciliación.
void main() {
  final source = File('lib/shared/routes/app_router.dart').readAsStringSync();

  group('router · la biblioteca diferida se memoiza', () {
    test('el FutureBuilder de la página usa el Future estable', () {
      expect(
        source,
        contains('static final Future<dynamic> _erpLibraryOnce'),
        reason: 'sin un Future memoizado, cada build reinicia el FutureBuilder',
      );
      expect(
        source,
        contains('future: _erpLibraryOnce'),
        reason: 'el builder de la página tiene que consumir ese Future, no uno '
            'recién creado',
      );
    });

    test('ninguna página se construye con un `loadLibrary()` recién llamado',
        () {
      final freshInPageBuilder = RegExp(
        r'^\s+erp\.loadLibrary\(\),\s*$',
        multiLine: true,
      ).allMatches(source).length;
      expect(
        freshInPageBuilder,
        0,
        reason: 'pasar `erp.loadLibrary()` como argumento devuelve un Future '
            'distinto en cada build y reinicia el estado de la ruta; hubo 130 '
            'llamadas así, y cada una era una ruta que perdía su State',
      );
      expect(
        source,
        isNot(contains('future: libraryFuture')),
        reason: 'el parámetro por-llamada era justamente el problema',
      );
    });
  });

  group('el mecanismo, para que la razón no se pierda', () {
    testWidgets(
      'un FutureBuilder con Future NUEVO en cada build destruye el State; '
      'memoizado, no',
      (tester) async {
        for (final memoized in <bool>[false, true]) {
          final stable = Future<void>.value();
          var initialized = 0;
          var disposed = 0;

          Widget host(int generation) => MaterialApp(
                home: FutureBuilder<void>(
                  // Reproduce las dos formas: el `Future` recién creado —lo que
                  // hacía `erp.loadLibrary()` en cada build— y el memoizado.
                  future: memoized ? stable : Future<void>.value(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      // El esqueleto es de OTRO tipo que el árbol real: por eso
                      // volver a `waiting` no re-renderiza, destruye.
                      return const Center(child: Text('cargando'));
                    }
                    return _Probe(
                      generation: generation,
                      onInit: () => initialized += 1,
                      onDispose: () => disposed += 1,
                    );
                  },
                ),
              );

          await tester.pumpWidget(host(0));
          await tester.pumpAndSettle();
          expect(initialized, 1);

          // Una reconstrucción cualquiera de la página, como la que provoca
          // cruzar el breakpoint.
          await tester.pumpWidget(host(1));
          await tester.pumpAndSettle();

          if (memoized) {
            expect(
              disposed,
              0,
              reason: 'con el Future memoizado el subárbol se conserva',
            );
            expect(initialized, 1);
          } else {
            expect(
              disposed,
              greaterThan(0),
              reason: 'un Future nuevo por build devuelve el builder a '
                  '`waiting` y destruye el State de la ruta',
            );
          }
        }
      },
    );
  });
}

class _Probe extends StatefulWidget {
  const _Probe({
    required this.generation,
    required this.onInit,
    required this.onDispose,
  });

  final int generation;
  final VoidCallback onInit;
  final VoidCallback onDispose;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('gen ${widget.generation}');
}
