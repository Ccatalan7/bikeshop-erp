import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/ai_assistant/models/ai_inventory_reply.dart';

double _stockOf(Map<String, dynamic> row) =>
    (row['stock'] as num?)?.toDouble() ?? 0;

Map<String, dynamic> _row({
  required String name,
  double stock = 0,
  bool? isActive,
}) {
  return <String, dynamic>{
    'name': name,
    'stock': stock,
    if (isActive != null) 'is_active': isActive,
  };
}

void main() {
  group('sellable catalog', () {
    test('drops products proven inactive', () {
      // The inventory screen showed 26 products for a search where the
      // assistant announced 27, because the assistant counted a discontinued
      // product the screen excludes.
      final rows = [
        _row(name: 'activa', isActive: true),
        _row(name: 'de baja', isActive: false),
      ];

      final sellable = filterSellableCatalog(rows);

      expect(sellable, hasLength(1));
      expect(sellable.single['name'], 'activa');
    });

    test('drops a row whose status could not be verified', () {
      // Every real row carries the flag by this point, so a missing one is an
      // unverifiable match — a stale vector hit whose product is gone. Keeping
      // it is what let a discontinued product back into the count.
      final sellable = filterSellableCatalog([_row(name: 'sin bandera')]);

      expect(sellable, isEmpty);
    });
  });

  group('in-stock counting', () {
    test('counts only positive stock', () {
      final rows = [
        _row(name: 'con', stock: 7, isActive: true),
        _row(name: 'sin', stock: 0, isActive: true),
        _row(name: 'negativa', stock: -1, isActive: true),
      ];

      expect(countRowsInStock(rows, _stockOf), 1);
    });
  });

  group('search sentence', () {
    test('states the ratio over one single set', () {
      final sentence = buildInventorySearchSentence(
        count: 26,
        inStockCount: 5,
        sampleNames: const ['Cámara A', 'Cámara B'],
        searchTerm: 'camara 29',
      );

      expect(sentence, contains('Encontré 26 resultados para "camara 29"'));
      expect(sentence, contains('5 de 26 aparecen con stock ahora'));
    });

    test('a truncated sample can no longer shrink the numerator', () {
      // The regression: the numerator used to come from the 15 rows the
      // payload carried while the denominator was the full count, so the
      // sentence under-reported stock on every broad search. The signature now
      // makes the two numbers come from one place, and a numerator that could
      // not belong to that set is refused at runtime — not with an assert,
      // which vanishes in release, the only build where a wrong stock figure
      // actually reaches the counter.
      expect(
        () => buildInventorySearchSentence(
          count: 27,
          inStockCount: 40,
          sampleNames: const ['A'],
          searchTerm: 'camara 29',
        ),
        throwsArgumentError,
      );
      expect(
        () => buildInventorySearchSentence(
          count: 27,
          inStockCount: -1,
          sampleNames: const ['A'],
          searchTerm: 'camara 29',
        ),
        throwsArgumentError,
      );
      expect(
        () => buildInventorySearchSentence(
          count: -1,
          inStockCount: null,
          sampleNames: const ['A'],
          searchTerm: 'camara 29',
        ),
        throwsArgumentError,
      );
    });

    test('says nothing about stock when the ratio is unknown', () {
      final sentence = buildInventorySearchSentence(
        count: 3,
        inStockCount: null,
        sampleNames: const ['A', 'B'],
        searchTerm: 'freno',
      );

      expect(sentence, isNot(contains('stock')));
      expect(sentence, contains('Encontré 3 resultados'));
    });

    test('reads naturally at both ends of the range', () {
      expect(
        buildInventorySearchSentence(
          count: 5,
          inStockCount: 0,
          sampleNames: const ['A'],
          searchTerm: 'casco best',
        ),
        contains('Ahora mismo todos aparecen sin stock.'),
      );
      expect(
        buildInventorySearchSentence(
          count: 5,
          inStockCount: 5,
          sampleNames: const ['A'],
          searchTerm: 'casco best',
        ),
        contains('Todos aparecen con stock.'),
      );
    });

    test('falls back to a neutral label without a search term', () {
      final sentence = buildInventorySearchSentence(
        count: 1,
        inStockCount: 1,
        sampleNames: const [],
        searchTerm: '  ',
      );

      expect(sentence, contains('para tu búsqueda'));
      expect(sentence, contains('Te dejé algunas coincidencias abajo.'));
    });

    test('ignores blank names when picking the samples', () {
      final sentence = buildInventorySearchSentence(
        count: 4,
        inStockCount: 1,
        sampleNames: const ['', '   ', 'Cadena KMC', 'Cadena Shimano', 'Otra'],
        searchTerm: 'cadena',
      );

      expect(sentence, contains('Cadena KMC'));
      expect(sentence, contains('Cadena Shimano'));
      expect(sentence, isNot(contains('Otra')));
    });
  });

  group('product location', () {
    test('is omitted when the catalog has no location', () {
      // warehouse_location is null for the whole catalog, and every card used
      // to print the literal English word "Unknown" as if it were a fact.
      expect(buildProductLocationFragment(null), isNull);
      expect(buildProductLocationFragment(''), isNull);
      expect(buildProductLocationFragment('   '), isNull);
    });

    test('is shown when a real location exists', () {
      expect(buildProductLocationFragment(' Bodega 2 '), 'Ubicación Bodega 2');
    });
  });
}
