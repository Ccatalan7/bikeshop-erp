import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/wheel_canonical_data.dart';

void main() {
  test('cada forma real de escribir el aro se lee igual', () {
    // Todas las escrituras de `bikes.wheel_size` vistas en producción el
    // 2026-09-27, con la etiqueta de la ficha que les corresponde.
    const seen = {
      '29"': '29"',
      "29''": '29"',
      '29': '29"',
      '26"': '26"',
      "26''": '26"',
      '26': '26"',
      '700': '700c',
      '700c': '700c',
      "700''": '700c',
      '27.5': '27.5"',
      '27.5"': '27.5"',
      "27.5''": '27.5"',
      "24''": '24"',
      '24"': '24"',
      '24': '24"',
      '20"': '20"',
      '20': '20"',
      '16': '16"',
      "16''": '16"',
      '12"': '12"',
    };
    for (final entry in seen.entries) {
      expect(canonicalBikeWheelSizeLabel(entry.key), entry.value,
          reason: entry.key);
    }
  });

  test('lo ambiguo queda sin leer, no se adivina', () {
    expect(canonicalBikeWheelSizeLabel('28'), isNull);
    expect(canonicalBikeWheelSizeLabel('27.5" - 26"'), isNull);
    expect(canonicalBikeWheelSizeLabel("14''"), isNull);
    expect(canonicalBikeWheelSizeLabel(''), isNull);
    expect(canonicalBikeWheelSizeLabel(null), isNull);
    expect(canonicalBikeWheelSizeLabel('29 pulgadas'), isNull);
  });

  test('la etiqueta de la ficha y el valor del wizard van y vuelven', () {
    for (final entry in kWheelSizeWizardValueByLabel.entries) {
      expect(wheelSizeWizardValueForLabel(entry.key), entry.value);
      expect(wheelSizeLabelForWizardValue(entry.value), entry.key);
      expect(canonicalBikeWheelSizeLabel(entry.key), entry.key);
    }
  });
}
