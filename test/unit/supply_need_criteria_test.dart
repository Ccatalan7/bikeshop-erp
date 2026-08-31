import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';

/// Cómo se lee `constraints` para la barra de necesidad.
///
/// **El hueco que cierra.** El contrato pide en esa barra el resumen de
/// criterios («rodado 27,5 · ancho > 2,0 · gama económica · buen margen · +1»),
/// y la ranura recibía el **origen** —«Solicitud directa»—, así que una
/// necesidad interpretada se veía igual que una escrita a mano.
///
/// **Por qué estas afirmaciones.** `constraints` mezcla tres cosas en un mismo
/// arreglo y confundirlas es el error fácil: los predicados técnicos vienen
/// **sin** `kind`, la preferencia comercial es texto libre que no rankea, y
/// `ranking_profile` ya tiene su propio control en pantalla. Las formas de
/// abajo están copiadas de producción, no inventadas.

void main() {
  test('los predicados técnicos son las entradas sin «kind»', () {
    final criteria = SupplyNeedCriteria.fromConstraints(const <Object?>[
      {
        'field': 'chain_speeds',
        'values': ['9'],
        'operator': 'eq'
      },
      {
        'field': 'tire_width',
        'values': ['2.0'],
        'operator': 'gt'
      },
    ]);

    expect(criteria.predicates.length, 2);
    expect(criteria.predicates.first.field, 'chain_speeds');
    expect(criteria.predicates.last.operator, 'gt');
    expect(criteria.commercialPreference, isNull);
  });

  test('el perfil de ranking no es un criterio: ya tiene su control', () {
    final criteria = SupplyNeedCriteria.fromConstraints(const <Object?>[
      {'kind': 'ranking_profile', 'value': 'balanced'},
    ]);

    // Ésta es la forma exacta que tiene «motores de menos de 130mm» en
    // producción: si contara, la barra mostraría «balanced» como si fuera una
    // medida del producto.
    expect(criteria.isEmpty, isTrue);
    expect(criteria.length, 0);
  });

  test('la preferencia comercial viaja aparte, nunca como predicado', () {
    final criteria = SupplyNeedCriteria.fromConstraints(const <Object?>[
      {'kind': 'ranking_profile', 'value': 'profitability'},
      {
        'kind': 'commercial_preference',
        'value': 'Económicos pero con buen margen',
      },
    ]);

    expect(criteria.predicates, isEmpty);
    expect(criteria.commercialPreference, 'Económicos pero con buen margen');
    expect(criteria.isNotEmpty, isTrue);
    expect(criteria.length, 1);
  });

  test('una entrada sin campo no se convierte en un criterio mudo', () {
    final criteria = SupplyNeedCriteria.fromConstraints(const <Object?>[
      {
        'values': ['9'],
        'operator': 'eq'
      },
      {
        'field': '   ',
        'values': ['9'],
        'operator': 'eq'
      },
      'basura',
    ]);

    // Sin campo, el rótulo sería «: igual a 9». Callar es mejor.
    expect(criteria.predicates, isEmpty);
    expect(criteria.isEmpty, isTrue);
  });

  test('un constraints ausente o roto no revienta la barra', () {
    expect(SupplyNeedCriteria.fromConstraints(null).isEmpty, isTrue);
    expect(
        SupplyNeedCriteria.fromConstraints('no soy una lista').isEmpty, isTrue);
  });

  test('la categoría viaja con los criterios cuando la interpretación la fijó',
      () {
    final criteria = SupplyNeedCriteria.fromConstraints(
      const <Object?>[
        {
          'field': 'chain_speeds',
          'values': ['9'],
          'operator': 'eq'
        },
      ],
      categoryId: 'category-chain',
      categoryPath: 'Transmisión / Cadenas',
    );

    expect(criteria.categoryId, 'category-chain');
    expect(criteria.categoryPath, 'Transmisión / Cadenas');
  });

  test('la cuenta incluye la preferencia, que es lo que decide el «+N»', () {
    final criteria = SupplyNeedCriteria.fromConstraints(const <Object?>[
      {
        'field': 'a',
        'values': ['1'],
        'operator': 'eq'
      },
      {
        'field': 'b',
        'values': ['2'],
        'operator': 'eq'
      },
      {
        'field': 'c',
        'values': ['3'],
        'operator': 'eq'
      },
      {
        'field': 'd',
        'values': ['4'],
        'operator': 'eq'
      },
      {'kind': 'commercial_preference', 'value': 'buen margen'},
    ]);

    expect(criteria.predicates.length, 4);
    expect(criteria.length, 5);
  });
}
