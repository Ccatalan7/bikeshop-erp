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
}
