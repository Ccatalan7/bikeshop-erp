import 'dart:io';

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

  test(
      'ISO 5775: sólo un rótulo de un solo diámetro refuta, igual que el servidor',
      () {
    // Los mismos rótulos que `supabase/tests/part_change_tire_bsd.sql` pasa
    // por `iso_bsd_candidates_for_wheel_size`: los 25 de producción
    // (2026-09-28) y cinco de la gramática.
    const candidates = {
      '29"': {622},
      '26"': <int>{},
      "29''": {622},
      '700': {622},
      "26''": <int>{},
      '700c': {622},
      '29': {622},
      '27.5': {584},
      '27.5"': {584},
      '26': <int>{},
      "27.5''": {584},
      "24''": <int>{},
      '20"': <int>{},
      '24"': <int>{},
      '20': <int>{},
      '16': <int>{},
      '24': <int>{},
      "700''": {622},
      "16''": <int>{},
      '27.5" - 26"': <int>{},
      '28': <int>{},
      '12"': <int>{},
      "14''": <int>{},
      '650b': {584},
      '': <int>{},
      '29"\t': {622},
      ' 27,5 " ': {584},
      '700 c': {622},
      '2 9': <int>{},
      '29er': <int>{},
    };
    for (final entry in candidates.entries) {
      expect(isoBsdCandidatesForBikeWheelSize(entry.key), entry.value,
          reason: entry.key);
    }
    expect(isoBsdCandidatesForBikeWheelSize(null), isEmpty);
    expect(isoWheelBsdLabel(622), '622 (29″/700c)');
    expect(isoWheelBsdLabel(584), '584 (27,5″/650b)');
    expect(isoWheelBsdLabel(559), '559 (26″)');
    expect(isoWheelBsdLabel(599), '599 (26″ 599)');
    expect(isoWheelBsdLabel(600), '600');
    expect(kIsoWheelBsdOptions.take(4), [622, 584, 559, 686]);
    expect(kIsoWheelBsdOptions.toSet().length, kIsoWheelBsdOptions.length);
    // Cada BSD que ofrece la ficha tiene su nombre de taller.
    for (final bsd in kIsoWheelBsdOptions) {
      expect(isoWheelBsdLabel(bsd), isNot('$bsd'), reason: '$bsd');
    }
    expect(kIsoWheelBsdOptions.length, 46);
    expect(kIsoWheelBsdOptions,
        containsAll(<int>[642, 599, 583, 541, 428, 340, 152]));
  });

  test('se ofrecen las llantas del taller, no la tabla ISO entera', () {
    // 2026-11-25: las 46 a la vista eran «todas las medidas habidas y por
    // haber». Se ofrece la llanta de cada aro que llega al taller.
    expect(kWorkshopWheelBsdOptions,
        [622, 584, 559, 507, 406, 355, 305, 254, 203]);
    expect(kIsoWheelBsdOptions, containsAll(kWorkshopWheelBsdOptions));
    // Cada aro de la ficha que es un solo diámetro tiene su llanta a la vista.
    for (final bsds in kIsoBsdCandidatesByWheelLabel.values) {
      expect(kWorkshopWheelBsdOptions, containsAll(bsds));
    }
    // Las raras no se ofrecen de entrada.
    for (final rare in const [686, 630, 609, 597, 590, 571, 534, 428]) {
      expect(kWorkshopWheelBsdOptions, isNot(contains(rare)), reason: '$rare');
    }

    expect(wheelBsdChoices(), kWorkshopWheelBsdOptions);
    expect(wheelBsdChoices(current: 584), kWorkshopWheelBsdOptions);
    // Lo que la bici ya tiene no desaparece de la lista.
    expect(wheelBsdChoices(current: 630), [...kWorkshopWheelBsdOptions, 630]);
    expect(wheelBsdChoices(current: 600), [...kWorkshopWheelBsdOptions, 600]);
    // «Otra medida…» abre la tabla entera.
    expect(wheelBsdChoices(all: true), kIsoWheelBsdOptions);
    expect(wheelBsdChoices(current: 630, all: true), kIsoWheelBsdOptions);
  });

  test('las tablas del servidor y de la app son las mismas', () {
    // `iso_bsd_candidates_for_wheel_size` e `iso_bsd_wheel_label` viven en
    // la migración; si otra migración las redefine, esta prueba lee esa.
    final sql = File(
      'supabase/migrations/20260928110000_part_change_tire_bsd.sql',
    ).readAsStringSync();
    String body(String name) {
      final start = sql.indexOf('create or replace function public.$name(');
      final end = sql.indexOf(r'$function$;', start);
      return sql.substring(start, end);
    }

    final names = {
      for (final m in RegExp(r"when (\d+) then '([^']+)'")
          .allMatches(body('iso_bsd_wheel_label')))
        int.parse(m.group(1)!): m.group(2)!,
    };
    expect(names.keys.toSet(), kIsoWheelBsdOptions.toSet());
    for (final entry in names.entries) {
      expect(isoWheelBsdLabel(entry.key), '${entry.key} (${entry.value})');
    }

    final candidates = {
      for (final m in RegExp(r"when '([^']+)' then '\{([0-9,]*)\}'")
          .allMatches(body('iso_bsd_candidates_for_wheel_size')))
        m.group(1)!: m.group(2)!.split(',').map(int.parse).toSet(),
    };
    expect(candidates, kIsoBsdCandidatesByWheelLabel);
  });

  test('la gramática no junta dígitos ni acepta otra unidad', () {
    expect(canonicalBikeWheelSizeLabel('2 9'), isNull);
    expect(canonicalBikeWheelSizeLabel('29er'), isNull);
    expect(canonicalBikeWheelSizeLabel(' 29 " '), '29"');
    expect(canonicalBikeWheelSizeLabel('29"\t'), '29"');
    expect(canonicalBikeWheelSizeLabel('650 B'), '650b');
    expect(canonicalBikeWheelSizeLabel('700 c'), '700c');
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
