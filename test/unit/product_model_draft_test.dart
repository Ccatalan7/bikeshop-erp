import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_model_draft.dart';
import 'package:vinabike_public_core/public_store/models/public_product_model.dart';

/// Modelos con tallas y colores en el ERP (20261120230000). Los nombres son
/// los del catálogo real (productos de MKR publicados el 2026-11-20): la
/// sugerencia tiene que acertar con ellos, no con nombres de laboratorio.
ProductModelMember _p(String id, String name) =>
    ProductModelMember(productId: id, name: name, options: const {});

void main() {
  group('suggest', () {
    test('the knee pad: shared name, two colors, three sizes', () {
      final draft = ProductModelDraft.suggest([
        _p('a', 'Rodillera Leatt 3DF 5.0 Blanco/Negro L/XL'),
        _p('b', 'Rodillera Leatt 3DF 5.0 Blanco/Negro S/M'),
        _p('c', 'Rodillera Leatt 3DF 5.0 Blanco/Negro XXL'),
        _p('d', 'Rodillera Leatt 3DF 5.0 Negra XXL'),
      ]);
      expect(draft.name, 'Rodillera Leatt 3DF 5.0');
      expect([for (final axis in draft.axes) axis.name], ['Color', 'Talla']);
      expect(draft.axes[0].values, ['Blanco/Negro', 'Negra']);
      expect(draft.axes[1].values, ['S/M', 'L/XL', 'XXL']);
      expect([for (final m in draft.members) m.productId], ['b', 'a', 'c', 'd'],
          reason: 'color first, then size, as the store shows them');
      expect(draft.members.last.options, {'Color': 'Negra', 'Talla': 'XXL'});
      expect(draft.problems, isEmpty);
    });

    test('the gloves: color names of two words and sizes with US/EU', () {
      final draft = ProductModelDraft.suggest([
        _p('a', 'Guantes Leatt MTB GripR 1.0 Amarillo Lager L 10US 9EU'),
        _p('b', 'Guantes Leatt MTB GripR 1.0 Azul Galaxia M 9US 8EU'),
        _p('c', 'Guantes Leatt MTB GripR 1.0 Blanco Trails M 9US 8EU'),
      ]);
      expect(draft.name, 'Guantes Leatt MTB GripR 1.0');
      expect(draft.axes[0].values,
          ['Amarillo Lager', 'Azul Galaxia', 'Blanco Trails']);
      expect(draft.axes[1].values, ['M', 'L']);
      expect(
        {for (final m in draft.members) m.productId: m.options['Talla']},
        {'a': 'L', 'b': 'M', 'c': 'M'},
      );
    });

    test('a shared color stays in the name: only the size varies', () {
      final draft = ProductModelDraft.suggest([
        _p('s', 'Casco Smith Forefront 2 MIPS Negro Mate S'),
        _p('m', 'Casco Smith Forefront 2 MIPS Negro Mate M'),
        _p('l', 'Casco Smith Forefront 2 MIPS Negro Mate L'),
      ]);
      expect(draft.name, 'Casco Smith Forefront 2 MIPS Negro Mate');
      expect([for (final axis in draft.axes) axis.name], ['Talla']);
      expect(draft.axes.single.values, ['S', 'M', 'L']);
    });

    test('a measure and a color: the seat clamp', () {
      final draft = ProductModelDraft.suggest([
        _p('a', 'Abrazadera Radical Mountain Collarín Bloqueo 34.9mm Rojo'),
        _p('b', 'Abrazadera Radical Mountain Collarín Bloqueo 34.9mm Azul'),
        _p('c', 'Abrazadera Radical Mountain Collarín Bloqueo 31.8mm Rojo'),
      ]);
      expect(draft.name, 'Abrazadera Radical Mountain Collarín Bloqueo');
      expect([for (final axis in draft.axes) axis.name], ['Color', 'Medida']);
      expect(draft.axes[1].values, ['31.8mm', '34.9mm']);
      expect(draft.problems, isEmpty);
    });

    test('a shared ending stays in the name: the valves come in pairs', () {
      final draft = ProductModelDraft.suggest([
        _p('a',
            'Válvulas Radical Mountain Presta F/V Tubeless Aluminio 36mm Azul 2U'),
        _p('b',
            'Válvulas Radical Mountain Presta F/V Tubeless Aluminio 36mm Roja 2U'),
      ]);
      expect(draft.name,
          'Válvulas Radical Mountain Presta F/V Tubeless Aluminio 36mm 2U');
      expect(draft.axes.single.name, 'Color');
      expect(draft.axes.single.values, ['Azul', 'Roja']);
    });

    test('nothing recognizable: what changes is the variant', () {
      final draft = ProductModelDraft.suggest([
        _p('a', 'Bombin Radical Mountain Mini Mtb J50010'),
        _p('b', 'Bombin Radical Mountain Mini Mtb J50013'),
      ]);
      expect(draft.axes.single.name, 'Variante');
      expect(draft.axes.single.values, ['J50010', 'J50013']);
      expect(draft.problems, isEmpty);
    });
  });

  group('editing', () {
    final base = ProductModelDraft.suggest([
      _p('a', 'Rodillera Leatt 3DF 5.0 Blanco/Negro S/M'),
      _p('b', 'Rodillera Leatt 3DF 5.0 Negra XXL'),
    ]);

    test('an added product takes the values its name says', () {
      final draft = base
          .withAxisValue('Talla', 'L/XL')
          .withMember(_p('c', 'Rodillera Leatt 3DF 5.0 Blanco/Negro L/XL'));
      expect(draft.members.last.options,
          {'Color': 'Blanco/Negro', 'Talla': 'L/XL'});
    });

    test('the longest value wins: «Negra» is not «Blanco/Negro»', () {
      expect(
        ProductModelDraft.inferValue(
          'Rodillera Leatt 3DF 5.0 Blanco/Negro XXL',
          const ProductModelAxis(
              name: 'Color', values: ['Negra', 'Blanco/Negro']),
        ),
        'Blanco/Negro',
      );
      expect(
        ProductModelDraft.inferValue(
          'Rodillera Leatt 3DF 5.0 Negra XXL',
          const ProductModelAxis(
              name: 'Color', values: ['Negro', 'Blanco/Negro']),
        ),
        isNull,
        reason: 'a word inside another is not a match',
      );
    });

    test('what is missing and what repeats is said in shop words', () {
      final draft = base
          .withMember(_p('c', 'Rodillera Leatt 3DF 5.0 Gris'))
          .withOption('b', 'Color', 'Blanco/Negro')
          .withOption('b', 'Talla', 'S/M');
      expect(draft.problems,
          contains('Falta color de «Rodillera Leatt 3DF 5.0 Gris».'));
      expect(
        draft.problems.where((p) => p.contains('misma combinación')),
        hasLength(1),
      );
      expect(draft.canSave, isFalse);
    });

    test('removing a value empties it on the variants that had it', () {
      final draft = base.withoutAxisValue('Color', 'Negra');
      expect(
          draft.members.firstWhere((m) => m.productId == 'b').options['Color'],
          '');
      expect(draft.axes.first.values, ['Blanco/Negro']);
    });

    test('the save carries every axis on every variant', () {
      final json = base.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json['name'], 'Rodillera Leatt 3DF 5.0');
      expect((json['members'] as List).first, {
        'product_id': 'a',
        'options': {'Color': 'Blanco/Negro', 'Talla': 'S/M'},
      });
    });

    test('a saved model reads back with its updated_at for the next save', () {
      final model = ProductModel.fromJson({
        'id': 'm1',
        'name': 'Rodillera Leatt 3DF 5.0',
        'updated_at': '2026-11-20T23:10:00.123456+00:00',
        'axes': [
          {
            'name': 'Talla',
            'values': ['S/M', 'XXL']
          },
        ],
        'members': [
          {
            'product_id': 'a',
            'name': 'A',
            'options': {'Talla': 'S/M'},
            'price': 65990,
            'stock': 2,
            'on_website': true
          },
          {
            'product_id': 'b',
            'name': 'B',
            'options': {'Talla': 'XXL'},
            'price': '65990.00',
            'stock': 0
          },
        ],
      })!;
      final json = ProductModelDraft.fromModel(model).toJson();
      expect(json['id'], 'm1');
      expect(json['updated_at'], '2026-11-20T23:10:00.123456+00:00');
      expect(model.members.first.onWebsite, isTrue);
      expect(model.members.last.price, 65990);
    });
  });

  group('store words', () {
    test('«2 colores · 3 tallas», and an axis that does not vary is not said',
        () {
      expect(
        productModelAxesLabel(const [
          (name: 'Color', count: 2),
          (name: 'Talla', count: 3),
        ]),
        '2 colores · 3 tallas',
      );
      expect(
        productModelAxesLabel(const [
          (name: 'Color', count: 1),
          (name: 'Medida', count: 2),
        ]),
        '2 medidas',
      );
      expect(productModelAxisWord('Largo', 4), 'largos');
    });

    test('a size that does not come in the current color is not a link', () {
      final model = PublicProductModel.fromJson({
        'id': 'm',
        'name': 'Rodillera Leatt 3DF 5.0',
        'axes': [
          {
            'name': 'Color',
            'values': ['Blanco/Negro', 'Negra']
          },
          {
            'name': 'Talla',
            'values': ['S/M', 'L/XL', 'XXL']
          },
        ],
        'variants': [
          {
            'id': 'b',
            'options': {'Color': 'Blanco/Negro', 'Talla': 'S/M'}
          },
          {
            'id': 'a',
            'options': {'Color': 'Blanco/Negro', 'Talla': 'L/XL'}
          },
          {
            'id': 'c',
            'options': {'Color': 'Blanco/Negro', 'Talla': 'XXL'}
          },
          {
            'id': 'd',
            'options': {'Color': 'Negra', 'Talla': 'XXL'}
          },
        ],
      })!;
      const current = {'Color': 'Negra', 'Talla': 'XXL'};
      expect(model.exactVariant(current, 'Talla', 'S/M'), isNull);
      expect(model.exactVariant(current, 'Talla', 'XXL')?['id'], 'd');
      expect(
        model.variantFor(const {'Color': 'Blanco/Negro', 'Talla': 'XXL'},
            'Color', 'Negra')?['id'],
        'd',
        reason: 'another color keeps the size when it exists',
      );
      expect(
        model.variantFor(const {'Color': 'Negra', 'Talla': 'XXL'}, 'Color',
            'Blanco/Negro')?['id'],
        'c',
      );
      expect(
        model.variantFor(
          const {'Color': 'Negra', 'Talla': 'XXL'},
          'Color',
          'Blanco/Negro',
          available: (v) => v['id'] == 'b',
        )?['id'],
        'c',
        reason: 'keeping the size weighs more than being in stock',
      );
      expect([for (final a in model.choosableAxes) a.name], ['Color', 'Talla']);
    });

    test('a listing row without a grouped model has no summary', () {
      expect(
        PublicProductModelSummary.fromRow(const {'model_id': null}),
        isNull,
      );
      final summary = PublicProductModelSummary.fromRow(const {
        'model_id': 'm',
        'model_name': 'Rodillera Leatt 3DF 5.0',
        'model_summary': {
          'variants': 4,
          'axes': [
            {'name': 'Color', 'count': 2},
            {'name': 'Talla', 'count': 3},
          ],
          'priceMin': 65990,
          'priceMax': 67990,
        },
      })!;
      expect(summary.label, '2 colores · 3 tallas');
      expect(summary.pricesVary, isTrue);
    });
  });
}
