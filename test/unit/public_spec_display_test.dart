import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/utils/public_spec_display.dart';

void main() {
  group('wheelSizeLabelForBsd', () {
    test('translates the ISO diameter into the wheel size the customer buys',
        () {
      expect(wheelSizeLabelForBsd('622'), '29" / 700c (ISO 622)');
      expect(wheelSizeLabelForBsd('559 mm'), '26" (ISO 559)');
      expect(wheelSizeLabelForBsd('406'), '20" (ISO 406)');
    });

    test('leaves an unknown diameter alone', () {
      expect(wheelSizeLabelForBsd('600'), isNull);
      expect(wheelSizeLabelForBsd('aro'), isNull);
    });
  });

  group('tireWidthLabel', () {
    test('MTB widths in inches with the millimetre kept', () {
      expect(tireWidthLabel('53.3'), '2.1" · 53 mm');
      expect(tireWidthLabel('54'), '2.125" · 54 mm');
      expect(tireWidthLabel('49.5'), '1.95" · 50 mm');
      expect(tireWidthLabel('57.1'), '2.25" · 57 mm');
      expect(tireWidthLabel('50.8'), '2.0" · 51 mm');
      expect(tireWidthLabel('61'), '2.4" · 61 mm');
      expect(tireWidthLabel('38.1'), '1.5" · 38 mm');
    });

    test('road and gravel widths stay in millimetres', () {
      expect(tireWidthLabel('25'), '25 mm');
      expect(tireWidthLabel('32'), '32 mm');
      expect(tireWidthLabel('34,9'), '35 mm');
    });

    test('rejects what is not a width', () {
      expect(tireWidthLabel(''), isNull);
      expect(tireWidthLabel('ancho'), isNull);
      expect(tireWidthLabel('0'), isNull);
    });
  });

  group('publicSpecValueLabel', () {
    test('routes the wheel diameter and the tyre width to their shop words',
        () {
      expect(
        publicSpecValueLabel(
          specKey: 'bead_seat_diameter_mm',
          value: '584',
          dataType: 'number',
          unit: 'mm',
        ),
        '27.5" / 650b (ISO 584)',
      );
      expect(
        publicSpecValueLabel(
          specKey: 'tire_width_mm',
          value: '53.3',
          dataType: 'number',
          unit: 'mm',
        ),
        '2.1" · 53 mm',
      );
    });

    test('appends the unit to a number once', () {
      expect(
        publicSpecValueLabel(
          specKey: 'valve_length_mm_value',
          value: '48',
          dataType: 'number',
          unit: 'mm',
        ),
        '48 mm',
      );
      expect(
        publicSpecValueLabel(
          specKey: 'valve_length_mm_value',
          value: '48 mm',
          dataType: 'number',
          unit: 'mm',
        ),
        '48 mm',
      );
      expect(
        publicSpecValueLabel(
          specKey: 'sprocket_count',
          value: '11',
          dataType: 'number',
          unit: null,
        ),
        '11',
      );
    });

    test('leaves option labels and booleans as the shop wrote them', () {
      expect(
        publicSpecValueLabel(
          specKey: 'valve_standard',
          value: 'Francesa (Presta)',
          dataType: 'single_select',
        ),
        'Francesa (Presta)',
      );
      expect(
        publicSpecValueLabel(
          specKey: 'includes_spindle',
          value: 'Sí',
          dataType: 'boolean',
        ),
        'Sí',
      );
    });
  });

  group('chileanNumber', () {
    test('decimal comma, thousands point, no trailing zeros', () {
      expect(chileanNumber('57.1'), '57,1');
      expect(chileanNumber('24.0'), '24');
      expect(chileanNumber('563.55'), '563,55');
      expect(chileanNumber('1000'), '1.000');
      expect(chileanNumber('10000'), '10.000');
      expect(chileanNumber('12.7'), '12,7');
      expect(chileanNumber('2,3'), '2,3');
    });

    test('leaves what is not a number alone', () {
      expect(chileanNumber('58-584'), '58-584');
      expect(chileanNumber('14G'), '14G');
    });
  });

  group('publicSpecSheetValue', () {
    test('the wheel size reads as the shop sells it, the ISO as a detail', () {
      expect(
        publicSpecSheetValue(
          specKey: 'bead_seat_diameter_mm',
          value: '584',
          dataType: 'number',
          unit: 'mm',
        ),
        const PublicSpecDisplayValue('27.5" / 650b', detail: 'ISO 584'),
      );
    });

    test('numbers in Chilean, units in words', () {
      String text(String key, String value, String? unit,
              [String type = 'number']) =>
          publicSpecSheetValue(
            specKey: key,
            value: value,
            dataType: type,
            unit: unit,
          ).text;
      expect(text('rim_internal_width_mm', '27.4', 'mm'), '27,4 mm');
      expect(text('rim_external_width_mm', '32.0', 'mm'), '32 mm');
      expect(text('largest_cog_teeth', '34', 'T'), '34 dientes');
      expect(text('pack_quantity', '1', 'unidades'), '1 unidad');
      expect(text('lumens_claimed', '1000', 'lm'), '1.000 lúmenes');
      expect(text('stem_angle_deg', '22', '°'), '22°');
      expect(text('ball_diameter_in', '1/4', 'in', 'single_select'), '1/4"');
      expect(text('tire_etrto', '58-584', null, 'text'), '58-584',
          reason: 'Until 2026-10-01 the store title-cased text and the '
              'ETRTO «58-584» was printed «58 584».');
    });

    test('a list reads as Spanish', () {
      expect(
        publicSpecSheetValue(
          specKey: 'chain_speeds',
          value: '6, 7, 8',
          dataType: 'multi_select',
        ).text,
        '6, 7 y 8',
      );
      expect(naturalSpanishList(['9']), '9');
    });

    test('a tube says which tyres it fits, in the units they are sold in', () {
      expect(
        tubeFitLabel('Diámetro de asiento (BSD): 622 mm · Ancho mínimo: '
            '44.4 mm · Ancho máximo: 59.7 mm'),
        '29" / 700c · 1.75" a 2.35"',
      );
      expect(
        tubeFitLabel('Diámetro de asiento (BSD): 622 mm · Ancho mínimo: '
            '18 mm · Ancho máximo: 25 mm | Diámetro de asiento (BSD): 559 mm '
            '· Ancho mínimo: 49.5 mm · Ancho máximo: 54 mm'),
        '700c · 18 a 25 mm\n26" · 1.95" a 2.125"',
      );
      expect(tubeFitLabel('sin diámetro'), isNull);
    });
  });

  group('publicSpecValueLabel with option names', () {
    test('a filter keeps the label and shows the visible name', () {
      expect(
        publicSpecValueLabel(
          specKey: 'chain_connector_type',
          value: 'Missing link',
          dataType: 'single_select',
          optionDisplay: const {
            'Missing link': 'Eslabón rápido (missing link)'
          },
        ),
        'Eslabón rápido (missing link)',
      );
      expect(
        publicSpecValueLabel(
          specKey: 'rotor_diameter_mm_value',
          value: '203',
          dataType: 'number',
          unit: 'mm',
        ),
        '203 mm',
      );
    });
  });
}
