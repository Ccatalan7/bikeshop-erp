import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

/// **Un plazo es un temporizador, y un temporizador sobrevive al widget.**
///
/// `Future.timeout` crea el suyo y no lo presta: con la llamada al modelo sin
/// volver —lo normal al cerrar la pantalla o sin red— seguía vivo veinte
/// segundos después de que ya nadie esperaba. En la app era una fuga silenciosa
/// y en las pruebas un fallo al desmontar, con las aserciones sin evaluarse.
void main() {
  setUp(() {
    resetSupplyNeedCriteriaSpansCache();
    resetSupplyNeedRequirementDiscoveryCache();
  });

  const fields = <SupplierNeedSearchField>[
    SupplierNeedSearchField(
      key: 'compound_type',
      label: 'Compuesto',
      dataType: 'single_select',
      allowedValues: <Object>['Orgánico'],
    ),
  ];
  const asked = <String, List<Object>>{
    'compound_type': <Object>['Orgánico'],
  };

  test('el plazo sigue venciendo y degradando', () {
    fakeAsync((async) {
      Object? resultado;
      unawaited(readSupplyNeedCriteriaSpansWithModel(
        requestText: 'Pastillas de resina',
        fields: fields,
        askedValues: asked,
        // Nunca responde: es el caso que el plazo existe para cerrar.
        extractor: (_) => Completer<Object?>().future,
        deadline: const Duration(seconds: 20),
      ).then((value) => resultado = value));

      async.elapse(const Duration(seconds: 19));
      expect(resultado, isNull, reason: 'todavía dentro del plazo');
      async.elapse(const Duration(seconds: 2));
      expect(resultado, isA<SupplyNeedCriteriaSpans>());
      expect((resultado! as SupplyNeedCriteriaSpans).spans, isEmpty,
          reason: 'vencer degrada a cero tramos, no a una excepción');
    });
  });

  test('soltarlo no deja el temporizador vivo', () {
    fakeAsync((async) {
      unawaited(readSupplyNeedRequirementsWithModel(
        requestText: 'Puños de gel',
        fields: fields,
        askedValues: asked,
        extractor: (_) => Completer<Object?>().future,
        deadline: const Duration(seconds: 20),
      ));
      expect(async.pendingTimers, isNotEmpty);

      cancelSupplierModelReadDeadlines();
      expect(async.pendingTimers, isEmpty,
          reason: 'quien deja de esperar suelta su plazo; si no, el '
              'temporizador sobrevive a la pantalla que lo pidió');
    });
  });

  test('cerrar una pantalla no le suelta el plazo a la otra', () {
    fakeAsync((async) {
      final unaPantalla = SupplierModelReadOwner();
      final otraPantalla = SupplierModelReadOwner();
      Object? deLaCerrada;
      Object? deLaViva;
      unawaited(readSupplyNeedCriteriaSpansWithModel(
        requestText: 'Pastillas de resina',
        fields: fields,
        askedValues: asked,
        extractor: (_) => Completer<Object?>().future,
        owner: unaPantalla,
      ).then((value) => deLaCerrada = value));
      unawaited(readSupplyNeedRequirementsWithModel(
        requestText: 'Puños de gel',
        fields: fields,
        askedValues: asked,
        extractor: (_) => Completer<Object?>().future,
        owner: otraPantalla,
      ).then((value) => deLaViva = value));
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(2));

      cancelSupplierModelReadDeadlines(owner: unaPantalla);
      async.flushMicrotasks();
      expect(deLaCerrada, isNotNull, reason: 'la cerrada resuelve y degrada');
      expect(deLaViva, isNull,
          reason: 'la que sigue abierta conserva su plazo: soltárselo la '
              'dejaría esperando una respuesta que nadie va a cerrar');
      expect(async.pendingTimers, hasLength(1));

      // Y su plazo sigue venciendo por su cuenta.
      async.elapse(const Duration(seconds: 21));
      expect(deLaViva, isNotNull);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('la llamada sin dueño no toca las lecturas de una pantalla', () {
    fakeAsync((async) {
      final pantalla = SupplierModelReadOwner();
      Object? suya;
      unawaited(readSupplyNeedRequirementsWithModel(
        requestText: 'Puños de gel',
        fields: fields,
        askedValues: asked,
        extractor: (_) => Completer<Object?>().future,
        owner: pantalla,
      ).then((value) => suya = value));
      async.flushMicrotasks();

      cancelSupplierModelReadDeadlines();
      async.flushMicrotasks();
      expect(suya, isNull,
          reason: 'una lectura con dueño sólo la suelta su dueño');
      expect(async.pendingTimers, hasLength(1));
      cancelSupplierModelReadDeadlines(owner: pantalla);
      async.flushMicrotasks();
      expect(suya, isNotNull);
    });
  });

  test('un dueño cerrado no vuelve a abrir nada', () {
    fakeAsync((async) {
      final pantalla = SupplierModelReadOwner();
      cancelSupplierModelReadDeadlines(owner: pantalla);
      expect(pantalla.isClosed, isTrue);

      var llamadas = 0;
      Object? tramos;
      unawaited(readSupplyNeedCriteriaSpansWithModel(
        requestText: 'Pastillas de resina',
        fields: fields,
        askedValues: asked,
        owner: pantalla,
        extractor: (_) {
          llamadas += 1;
          return Completer<Object?>().future;
        },
      ).then((value) => tramos = value));
      async.flushMicrotasks();

      expect(llamadas, 0,
          reason: 'una preparación que termina después del cierre no puede '
              'arrancar una llamada para una pantalla que ya no existe');
      expect(async.pendingTimers, isEmpty, reason: 'ni un plazo nuevo');
      expect((tramos! as SupplyNeedCriteriaSpans).spans, isEmpty);
    });
  });
}
