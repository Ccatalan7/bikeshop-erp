import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';

/// **El contrato anterior llamaba `eligible` a todo lo revisado.**
///
/// Un cliente que hable con un servidor que todavía no publica `reviewed` tiene
/// que traducir, no sumar: sumarle los no verificados los contaría dos veces, y
/// dejar ese número como «comprobadas» reproduciría exactamente la cifra que
/// engañaba —«49 alternativas» sobre 47 filas sin un solo criterio establecido—.
void main() {
  test('un payload del contrato anterior se traduce, no se suma', () {
    // Lo que publicaba el servidor de ayer para la necesidad real de pastillas.
    final counts = SupplyStockCounts.fromJson(const <String, dynamic>{
      'eligible': 49,
      'full': 3,
      'partial': 18,
      'none': 28,
      'unverified': 47,
    });
    expect(counts.reviewed, 49,
        reason:
            'lo que ese contrato llamaba elegible era el universo revisado');
    expect(counts.eligible, 2,
        reason:
            'y lo comprobado es lo que queda al descontar lo no verificado');
    expect(counts.unverified, 47);
    expect(counts.reviewed, counts.eligible + counts.unverified,
        reason: 'las dos cifras cierran sin contar nada dos veces');
  });

  test('el contrato nuevo se lee tal cual', () {
    final counts = SupplyStockCounts.fromJson(const <String, dynamic>{
      'eligible': 2,
      'reviewed': 49,
      'unverified': 47,
    });
    expect(counts.eligible, 2);
    expect(counts.reviewed, 49);
  });

  test('un payload anterior sin nada comprobado no inventa alternativas', () {
    final counts = SupplyStockCounts.fromJson(const <String, dynamic>{
      'eligible': 12,
      'unverified': 12,
    });
    expect(counts.eligible, 0);
    expect(counts.reviewed, 12);
  });

  test('un payload incoherente no produce un negativo', () {
    final counts = SupplyStockCounts.fromJson(const <String, dynamic>{
      'eligible': 3,
      'unverified': 9,
    });
    expect(counts.eligible, 0, reason: 'nunca menos que ninguna');
    expect(counts.reviewed, 3);
  });

  SupplyStockOption option(String state, {bool? complete}) =>
      SupplyStockOption.fromJson(<String, dynamic>{
        'productId': 'p',
        'name': 'P',
        'atp': 1,
        'coverage': 'full',
        'matchState': state,
        if (complete != null) 'evidenceComplete': complete,
      });

  test('comprobado lo decide la completitud que publica el servidor', () {
    // **`weak` no es cumplimiento.** «Algo se estableció y nada contradijo»
    // dejaba pasar una pastilla METALICA CON DISIPADOR para una necesidad de
    // compuesto orgánico y sin aletas: sólo el sistema de freno estaba
    // establecido, y los otros dos criterios seguían sin resolver.
    expect(option('weak', complete: false).isChecked, isFalse);
    expect(option('weak', complete: true).isChecked, isTrue,
        reason: 'un weak con TODOS los criterios establecidos sí completa');
    expect(option('strong', complete: true).isChecked, isTrue);
    expect(option('no_criteria', complete: false).isChecked, isFalse,
        reason: 'sin criterios, sólo una categoría cerrada lo sostiene, y eso '
            'lo decide el servidor');
  });

  test('sin el dato del servidor, sólo strong se da por comprobado', () {
    expect(option('strong').isChecked, isTrue);
    for (final state in <String>[
      'weak',
      'no_criteria',
      'unverified',
      'lo_que_venga',
    ]) {
      expect(option(state).isChecked, isFalse,
          reason: 'sin la completitud publicada, lo dudoso cae del lado '
              'seguro: \$state');
    }
  });
}
