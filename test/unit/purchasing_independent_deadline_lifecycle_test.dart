import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

void main() {
  setUp(resetSupplyNeedRequirementDiscoveryCache);

  test('cancelar una lectura también resuelve a quien la esperaba', () {
    fakeAsync((clock) {
      List<SupplyNeedUnmodelledRequirement>? received;
      final remote = Completer<Object?>();
      unawaited(readSupplyNeedRequirementsWithModel(
        requestText: 'Puños de gel, sin tapones',
        fields: const <SupplierNeedSearchField>[],
        askedValues: const <String, List<Object>>{},
        extractor: (_) => remote.future,
      ).then((value) => received = value));
      clock.flushMicrotasks();
      expect(clock.pendingTimers, hasLength(1));

      cancelSupplierModelReadDeadlines();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
      expect(received, isNotNull,
          reason: 'cancelar el plazo sin completar la espera la deja colgada '
              'para siempre cuando el proveedor nunca responde');
      expect(received, isEmpty,
          reason: 'la cancelación degrada sin inventar requisitos');
    });
  });

  test('una preparación tardía no inicia IA después de cerrar su pantalla', () {
    fakeAsync((clock) {
      final owner = SupplierModelReadOwner();
      final templateReady = Completer<void>();
      final remote = Completer<Object?>();
      var modelCalls = 0;
      List<SupplyNeedUnmodelledRequirement>? received;

      // La página espera la plantilla antes de comenzar sus dos lecturas.
      unawaited(() async {
        await templateReady.future;
        received = await readSupplyNeedRequirementsWithModel(
          requestText: 'Puños de goma y doble abrazadera',
          fields: const <SupplierNeedSearchField>[],
          askedValues: const <String, List<Object>>{},
          owner: owner,
          extractor: (_) {
            modelCalls += 1;
            return remote.future;
          },
        );
      }());
      clock.flushMicrotasks();
      cancelSupplierModelReadDeadlines(owner: owner);
      templateReady.complete();
      clock.flushMicrotasks();
      try {
        expect(modelCalls, 0,
            reason: 'la plantilla llegó después del dispose; el dueño '
                'cerrado no puede iniciar una llamada ni otro plazo');
        expect(clock.pendingTimers, isEmpty);
        expect(received, isEmpty);
      } finally {
        cancelSupplierModelReadDeadlines(owner: owner);
        clock.flushMicrotasks();
      }
    });
  });
}
