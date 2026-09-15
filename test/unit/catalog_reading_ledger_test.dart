import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/services/catalog_reading_ledger.dart';
import 'package:vinabike_erp/shared/services/catalog_name_reading.dart';

CatalogNameReadingOutcome _resultado({
  int recorded = 0,
  int keptExisting = 0,
  List<String> rejectedByServer = const <String>[],
  List<String> failures = const <String>[],
  bool cutShort = false,
  bool abandoned = false,
  bool modelUnavailable = false,
}) =>
    CatalogNameReadingOutcome(
      recorded: recorded,
      keptExisting: keptExisting,
      rejectedByServer: rejectedByServer,
      failures: failures,
      cutShort: cutShort,
      abandoned: abandoned,
      modelUnavailable: modelUnavailable,
      rowsRead: 1,
    );

void main() {
  const necesidad = 'need-1';
  const huecos = <String>['p1|compound_type', 'p2|compound_type'];

  test('la misma pregunta no se repite dentro de la misma visita', () {
    final ledger = CatalogReadingLedger();
    expect(ledger.claim(necesidad, huecos), isNotNull);
    expect(ledger.claim(necesidad, huecos), isNull,
        reason: 'preguntarle dos veces lo mismo al modelo es pagar dos veces '
            'por la misma respuesta');
  });

  test('volver a la necesidad tras una lectura abandonada la desbloquea', () {
    // **El borde real.** El operador abre la necesidad, el modelo se demora, el
    // operador cambia de necesidad, la lectura llega tarde y se suelta sin
    // escribir. Al volver, los huecos son los mismos y la llave también: con
    // la llave retenida esa necesidad quedaba muda el resto de la visita,
    // aunque el presupuesto se hubiera repuesto al reabrirla.
    final ledger = CatalogReadingLedger();
    final llave = ledger.claim(necesidad, huecos);
    expect(llave, isNotNull);

    ledger.settle(
        necesidad, llave!, _resultado(abandoned: true, cutShort: true));

    // El operador vuelve: reabrir repone el presupuesto…
    ledger.enter(necesidad);
    expect(ledger.budgetFor(necesidad), kCatalogNameReadingRecordCap);
    // …y la misma pregunta se puede volver a hacer, porque nunca se hizo.
    expect(ledger.claim(necesidad, huecos), isNotNull,
        reason: 'no se preguntó nada: la llave no se consumió');
  });

  test('lo que sí obtuvo veredicto no se vuelve a ofrecer', () {
    // Soltar la llave no puede reabrir la puerta a lo ya juzgado: ésa es otra
    // memoria, y no se suelta.
    final ledger = CatalogReadingLedger();
    ledger.offeredFor(necesidad).add('p1|compound_type');
    final llave = ledger.claim(necesidad, huecos);
    ledger.settle(necesidad, llave!, _resultado(abandoned: true));
    expect(ledger.offeredFor(necesidad), contains('p1|compound_type'));
  });

  test('un rechazo del servidor sí consume la llave', () {
    // La misma cita y el mismo valor dan el mismo veredicto: repetir la
    // pregunta sólo gasta la llamada al modelo.
    final ledger = CatalogReadingLedger();
    final llave = ledger.claim(necesidad, huecos);
    ledger.settle(
      necesidad,
      llave!,
      _resultado(rejectedByServer: const <String>['p1/compound_type: no']),
    );
    expect(ledger.claim(necesidad, huecos), isNull);
  });

  test('el presupuesto es de la cadena y sólo lo gasta un veredicto', () {
    final ledger = CatalogReadingLedger();
    final primera = ledger.claim(necesidad, huecos)!;
    ledger.settle(necesidad, primera, _resultado(recorded: 3, keptExisting: 1));
    expect(ledger.budgetFor(necesidad), kCatalogNameReadingRecordCap - 4);

    final segunda = ledger.claim(necesidad, const <String>['p3|x'])!;
    ledger.settle(
      necesidad,
      segunda,
      _resultado(failures: const <String>['p3/x: la red se cayó']),
    );
    expect(ledger.budgetFor(necesidad), kCatalogNameReadingRecordCap - 4,
        reason: 'una caída no quema capacidad útil');
  });

  test('agotado el presupuesto, la visita deja de leer', () {
    final ledger = CatalogReadingLedger();
    final llave = ledger.claim(necesidad, huecos)!;
    ledger.settle(
      necesidad,
      llave,
      _resultado(recorded: kCatalogNameReadingRecordCap),
    );
    expect(ledger.claim(necesidad, const <String>['p9|otro']), isNull);
    // Y volver a entrar lo repone: es una visita nueva.
    ledger.enter(necesidad);
    expect(ledger.claim(necesidad, const <String>['p9|otro']), isNotNull);
  });

  test('la cadena sigue sólo si quedó trabajo y nadie falló', () {
    final ledger = CatalogReadingLedger();
    expect(
      ledger.canContinue(necesidad, _resultado(cutShort: true)),
      isTrue,
    );
    expect(
      ledger.canContinue(
          necesidad, _resultado(cutShort: true, modelUnavailable: true)),
      isFalse,
      reason: 'sin modelo, insistir en el acto no cambia nada',
    );
    expect(
      ledger.canContinue(
          necesidad, _resultado(cutShort: true, abandoned: true)),
      isFalse,
      reason: 'la pregunta cambió: seguir sería leer para nadie',
    );
  });

  test('cada necesidad lleva su propia cuenta', () {
    final ledger = CatalogReadingLedger();
    final llave = ledger.claim(necesidad, huecos)!;
    ledger.settle(necesidad, llave, _resultado(recorded: 10));
    expect(ledger.budgetFor('otra'), kCatalogNameReadingRecordCap);
    expect(ledger.claim('otra', huecos), isNotNull);
  });
}
