import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_portal_navigation_queue.dart';

/// **Dos navegaciones del mismo portal no pueden solaparse.**
///
/// La consulta exacta por SKU y la enumeración por necesidad comparten cookie
/// y sesión contra un ASP que guarda estado por sesión. Si corren a la vez, la
/// segunda cambia la clasificación de la primera y las dos informan filas que
/// no son suyas: ninguna falla, las dos mienten. Por eso lo que se afirma acá
/// no es «terminó», es **que nunca hubo dos adentro a la vez**.

class _Overlap {
  int inside = 0;
  int maxInside = 0;
  final List<String> order = <String>[];

  Future<void> Function() body(String label, Completer<void> release) {
    return () async {
      inside++;
      if (inside > maxInside) maxInside = inside;
      order.add('$label:in');
      await release.future;
      order.add('$label:out');
      inside--;
    };
  }
}

void main() {
  test('las navegaciones del mismo proveedor no se solapan y salen en orden',
      () async {
    final queue = SupplierPortalNavigationQueue();
    final overlap = _Overlap();
    final first = Completer<void>();
    final second = Completer<void>();
    final third = Completer<void>();

    // Se encolan las tres antes de soltar ninguna: si la cola no serializara,
    // las tres entrarían de inmediato y `maxInside` sería 3.
    final futures = <Future<void>>[
      queue.run('rbx', overlap.body('exacta', first)),
      queue.run('rbx', overlap.body('necesidad', second)),
      queue.run('rbx', overlap.body('exacta-2', third)),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(overlap.maxInside, 1);
    expect(overlap.order, <String>['exacta:in']);

    first.complete();
    await Future<void>.delayed(Duration.zero);
    second.complete();
    await Future<void>.delayed(Duration.zero);
    third.complete();
    await Future.wait(futures);

    expect(overlap.maxInside, 1, reason: 'nunca hubo dos adentro a la vez');
    expect(overlap.order, <String>[
      'exacta:in',
      'exacta:out',
      'necesidad:in',
      'necesidad:out',
      'exacta-2:in',
      'exacta-2:out',
    ]);
  });

  test('dos proveedores distintos no se estorban', () async {
    final queue = SupplierPortalNavigationQueue();
    final started = <String>[];
    final rbx = Completer<void>();
    final mkr = Completer<void>();

    final futures = <Future<void>>[
      queue.run('rbx', () async {
        started.add('rbx');
        await rbx.future;
      }),
      queue.run('mkr', () async {
        started.add('mkr');
        await mkr.future;
      }),
    ];
    await Future<void>.delayed(Duration.zero);

    // Serializar por portal, no por app: la cola es de la sesión de UN
    // proveedor, y frenar a los demás sería inventarse un costo.
    expect(started, <String>['rbx', 'mkr']);

    rbx.complete();
    mkr.complete();
    await Future.wait(futures);
  });

  test('una navegación que falla no le quita el turno a la siguiente',
      () async {
    final queue = SupplierPortalNavigationQueue();
    final done = <String>[];

    final failing = queue.run<void>('rbx', () async {
      throw StateError('el portal cortó');
    });
    final next = queue.run<void>('rbx', () async {
      done.add('siguiente');
    });

    await expectLater(failing, throwsStateError);
    await next;
    expect(done, <String>['siguiente']);
    expect(queue.pendingSuppliers, 0,
        reason: 'la cola no deja turnos colgados');
  });

  test(
    'pedir el mismo proveedor desde adentro no se abraza a sí mismo',
    () async {
      final queue = SupplierPortalNavigationQueue();

      // Sin la guardia de reentrada esto espera su propio turno para siempre y
      // la prueba muere por timeout. Es el precio de «serializar TODO» hecho
      // ingenuamente.
      final value = await queue.run<int>('rbx', () async {
        final inner = await queue.run<int>('rbx', () async => 7);
        return inner + 1;
      });

      expect(value, 8);
      expect(queue.pendingSuppliers, 0);
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test('la reentrada no libera a OTRO proveedor de su turno', () async {
    final queue = SupplierPortalNavigationQueue();
    final overlap = _Overlap();
    final outer = Completer<void>();
    final blocker = Completer<void>();

    final held = queue.run('mkr', overlap.body('mkr-primero', blocker));
    await Future<void>.delayed(Duration.zero);

    final nested = queue.run<void>('rbx', () async {
      // Anidado, pero sobre otro proveedor: acá sí hay que esperar turno.
      await queue.run('mkr', overlap.body('mkr-anidado', outer));
    });
    await Future<void>.delayed(Duration.zero);

    expect(overlap.maxInside, 1);
    expect(overlap.order, <String>['mkr-primero:in']);

    blocker.complete();
    await Future<void>.delayed(Duration.zero);
    outer.complete();
    await Future.wait(<Future<void>>[held, nested]);

    expect(overlap.maxInside, 1);
  });
}
