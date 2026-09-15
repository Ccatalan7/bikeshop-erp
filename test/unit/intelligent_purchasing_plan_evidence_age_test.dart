import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';

/// La edad de la evidencia que el plan muestra en cada línea.
///
/// **Qué defiende.** `handoff-t23` pide en `07 · Plan con líneas` la meta
/// «evidencia 18 días · completa»: la antigüedad va primero porque es la que
/// decide si el costo aterrizado todavía sirve. El dato no viajaba —la línea
/// sólo decía «evidencia completa»— aunque el servidor ya lo escribe en
/// `evidence_snapshot`.
///
/// **Por qué estas afirmaciones y no otras.** La edad se deriva restando dos
/// fechas del snapshot, así que las trampas están en los bordes: un snapshot
/// incompleto no puede convertirse en «0 días» (se leería como «de hoy»), un
/// cruce de huso no puede mover el resultado un día, y una compra posterior a
/// la captura no puede producir una edad negativa. Cada prueba muerde una de
/// esas: quitar el `?? null`, cambiar el `toUtc()` o borrar el piso en cero
/// pone una en rojo.

PurchasePlanLine lineWithSnapshot(Map<String, Object?>? snapshot) {
  return PurchasePlanLine.fromJson(<String, dynamic>{
    'id': 'line-1',
    'source_need_id': 'need-1',
    'candidate_id': 'cand-1',
    'product_id': 'prod-1',
    'supplier_name': 'TeknoBike',
    'quantity': 4,
    'unit': 'unit',
    'currency_code': 'CLP',
    'landed_unit_cost_net': 3181.45,
    'supplier_availability': 'unverified',
    if (snapshot != null) 'evidence_snapshot': snapshot,
  });
}

void main() {
  test('la edad sale de las dos fechas que el servidor escribió', () {
    final line = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-08-19T16:08:49.168853+00:00',
      'latest_purchase_at': '2026-06-01T04:00:00+00:00',
    });

    // 1 de junio → 19 de agosto: 30 (jun) + 31 (jul) + 18 = 79 días.
    expect(line.evidenceAgeDays, 79);
  });

  test('sin snapshot no hay edad, y eso no es cero', () {
    expect(lineWithSnapshot(null).evidenceAgeDays, isNull);
  });

  test('un snapshot al que le falta una fecha tampoco inventa un cero', () {
    final sinCompra = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-08-19T16:08:49.168853+00:00',
    });
    final sinCaptura = lineWithSnapshot(<String, Object?>{
      'latest_purchase_at': '2026-06-01T04:00:00+00:00',
    });

    expect(sinCompra.evidenceAgeDays, isNull);
    expect(sinCaptura.evidenceAgeDays, isNull);
  });

  test('el huso no mueve el resultado: se compara la fecha civil UTC', () {
    // Las dos son el mismo instante; sólo cambia cómo viene escrito.
    final enUtc = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-08-19T02:00:00+00:00',
      'latest_purchase_at': '2026-08-17T02:00:00+00:00',
    });
    final enSantiago = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-08-18T22:00:00-04:00',
      'latest_purchase_at': '2026-08-16T22:00:00-04:00',
    });

    expect(enUtc.evidenceAgeDays, 2);
    expect(enSantiago.evidenceAgeDays, enUtc.evidenceAgeDays);
  });

  test('una compra posterior a la captura no produce una edad negativa', () {
    final line = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-06-01T04:00:00+00:00',
      'latest_purchase_at': '2026-08-19T16:08:49.168853+00:00',
    });

    expect(line.evidenceAgeDays, 0);
  });

  test('withProduct conserva la edad al resolver nombre y foto', () {
    final line = lineWithSnapshot(<String, Object?>{
      'captured_at': '2026-08-19T16:08:49.168853+00:00',
      'latest_purchase_at': '2026-06-01T04:00:00+00:00',
    });

    // `fetchPlan` reconstruye la línea tras leer `products`: si esa
    // reconstrucción olvida el campo, la pantalla vuelve a perder la edad sin
    // que nada más falle.
    final resuelta = line.withProduct(name: 'Cámara Maxxis 29');

    expect(resuelta.evidenceAgeDays, 79);
    expect(resuelta.productName, 'Cámara Maxxis 29');
  });
}
