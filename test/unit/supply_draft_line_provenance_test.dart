import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_assistant_turn_contracts.dart';

/// Qué sobrevive a editar una línea del borrador, y qué no.
///
/// Producto, categoría, familia y predicados salieron de interpretar **una
/// frase concreta**. Si el operador la reescribe, arrastrarlos afirmaría algo
/// que nadie dijo, y el ranking posterior heredaría una familia equivocada sin
/// que nada lo delate. Cambiar cuánto o en qué unidad no cambia qué es la cosa,
/// así que ahí la procedencia se conserva entera.
AIAssistantSupplyNeedDraftLine _line() => const AIAssistantSupplyNeedDraftLine(
      lineRef: 'line-1',
      description: 'Cadena de 10 velocidades',
      productId: '41414141-4141-4141-8141-414141414141',
      productName: 'Cadena KMC X10 116L',
      productSku: 'KMC-X10-116',
      identityState: 'confirmed',
      categoryId: '31313131-3131-4131-8131-313131313131',
      categoryPath: 'Transmisión / Cadenas',
      technicalFamily: 'chain',
      quantity: 2,
      unit: 'unit',
      technicalPredicates: [
        AIAssistantSupplyNeedTechnicalPredicate(
          field: 'chain_speeds',
          operator: 'eq',
          values: [10],
        ),
      ],
      preference: 'gama económica',
      clarification: null,
      clarificationRequired: false,
    );

void main() {
  group('reescribir la descripción limpia la procedencia', () {
    final rewritten = _line().withRewrittenDescription(
      description: 'Cassette de 9 velocidades',
      quantity: 1,
      unit: 'unit',
      clarification:
          'Confirma el producto exacto antes de comparar proveedores.',
    );

    test('el producto no sobrevive a una frase distinta', () {
      expect(rewritten.productId, isNull);
      expect(rewritten.productName, isNull);
      expect(rewritten.productSku, isNull);
      expect(rewritten.identityState, 'unresolved');
    });

    test('la categoría y su familia tampoco', () {
      expect(rewritten.categoryId, isNull);
      expect(rewritten.categoryPath, isNull);
      expect(rewritten.technicalFamily, isNull);
    });

    test('los criterios técnicos se van con la frase que los produjo', () {
      expect(rewritten.technicalPredicates, isEmpty);
      expect(rewritten.preference, isNull);
    });

    test('la línea queda pidiendo confirmación, no dándola por hecha', () {
      expect(rewritten.description, 'Cassette de 9 velocidades');
      expect(rewritten.clarificationRequired, isTrue);
      expect(rewritten.clarification, isNotNull);
      expect(rewritten.hasConfirmedProduct, isFalse);
    });

    test('y el comando no manda una categoría que ya no existe', () {
      expect(rewritten.toCommandJson()['categoryId'], isNull);
      expect(rewritten.toCommandJson()['productId'], isNull);
    });
  });

  group('cambiar cantidad o unidad conserva la procedencia', () {
    final adjusted = _line().copyWith(quantity: 5, unit: 'par');

    test('el producto sigue siendo el mismo', () {
      expect(adjusted.productId, _line().productId);
      expect(adjusted.productName, _line().productName);
      expect(adjusted.identityState, 'confirmed');
      expect(adjusted.hasConfirmedProduct, isTrue);
    });

    test('la categoría, la familia y los criterios se mantienen', () {
      expect(adjusted.categoryId, _line().categoryId);
      expect(adjusted.categoryPath, _line().categoryPath);
      expect(adjusted.technicalFamily, _line().technicalFamily);
      expect(adjusted.technicalPredicates, _line().technicalPredicates);
      expect(adjusted.preference, 'gama económica');
    });

    test('y sólo cambia lo que se pidió cambiar', () {
      expect(adjusted.quantity, 5);
      expect(adjusted.unit, 'par');
      expect(adjusted.description, 'Cadena de 10 velocidades');
    });
  });

  group('el comando durable manda identidades, no glosas', () {
    test('viaja la categoría y no sus etiquetas derivadas', () {
      final command = _line().toCommandJson();

      expect(command['categoryId'], '31313131-3131-4131-8131-313131313131');
      // `categoryPath` y `technicalFamily` se derivan de sus dueños en cada
      // lectura; mandarlas las congelaría en el ledger al lado de una fuente
      // que sigue cambiando.
      expect(command.containsKey('categoryPath'), isFalse);
      expect(command.containsKey('technicalFamily'), isFalse);
    });

    test('una línea sin categoría manda null, no la omite', () {
      final withoutCategory = _line().withRewrittenDescription(
        description: 'Algo que todavía no sé nombrar',
        quantity: 1,
        unit: 'unit',
        clarification: 'Confirma de qué pieza se trata.',
      );

      expect(withoutCategory.toCommandJson().containsKey('categoryId'), isTrue);
      expect(withoutCategory.toCommandJson()['categoryId'], isNull);
    });
  });
}
