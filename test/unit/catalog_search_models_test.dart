import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_search_models.dart';

/// «Búsquedas» of the store catalog (2026-10-24, 20261024070000).
void main() {
  test('a text is folded as the search compares it', () {
    expect(foldCatalogSearchText('  Cámara  ÑANDÚ, 29"  '), 'camara nandu 29');
    expect(foldCatalogSearchText('Pedalier/Motor'), 'pedalier motor');
  });

  test('a group answers to its name and to any of its words', () {
    final maza = CatalogSearchConcept.fromRow(const {
      'concept': 'maza',
      'kind': 'part',
      'terms': ['maza', 'buje'],
      'own_terms': ['cubo'],
      'broader': <String>[],
      'phrases': <String>[],
      'own_phrases': ['maza trasera'],
      'shared': true,
    });
    expect(maza.label, 'Maza');
    expect(maza.matches('Bují'), isFalse);
    expect(maza.matches('BUJE'), isTrue);
    expect(maza.matches('cub'), isTrue);
    expect(maza.ownWords, ['cubo', 'maza trasera']);
    expect(maza.matches(''), isTrue);
  });

  test('what a word added did, in the operator\'s words', () {
    CatalogSearchWordsResult result({int? finds, int? listed}) =>
        CatalogSearchWordsResult(
          concept: 'maza',
          added: const ['bujes delanteros'],
          already: const [],
          created: false,
          finds: finds,
          listed: listed,
        );
    expect(
      result(finds: 12, listed: 12).describe(search: 'bujes delanteros'),
      'Palabra agregada: «bujes delanteros». «bujes delanteros» ahora '
      'encuentra 12 productos.',
    );
    expect(
      result(finds: 3, listed: 0).describe(search: 'x'),
      endsWith('«x» ahora encuentra 3 productos, todos agotados.'),
    );
    expect(
      result(finds: 5, listed: 2).describe(search: 'x'),
      endsWith('«x» ahora encuentra 5 productos: 2 a la venta.'),
    );
    expect(
      result(finds: 0, listed: 0).describe(search: 'x'),
      endsWith('«x» todavía no encuentra productos.'),
    );
    expect(
      const CatalogSearchWordsResult(
        concept: 'maza',
        added: [],
        already: ['buje'],
        created: false,
      ).describe(),
      'Esas palabras ya estaban en el buscador.',
    );
  });

  test('a search out of stock is told apart from one nobody understands', () {
    final miss = CatalogSearchMiss.fromRow(const {
      'term': 'camara 650b',
      'typed': 'cámara 650b',
      'searches': 2,
      'out_of_stock': 3,
      'first_seen_at': '2026-10-22T12:00:00Z',
      'last_seen_at': '2026-10-23T12:00:00Z',
      'state': 'word',
      'concept': 'camara',
    });
    expect(miss.onlyOutOfStock, isTrue);
    expect(miss.state, CatalogSearchMissState.word);
    expect(miss.concept, 'camara');
    expect(
      CatalogSearchMiss.fromRow(const {'term': 'x', 'state': 'open'}).concept,
      isNull,
    );
  });
}
