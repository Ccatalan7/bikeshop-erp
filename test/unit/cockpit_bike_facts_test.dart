import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/cockpit_canonical_data.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_spec_draft.dart';
import 'package:vinabike_erp/modules/bikeshop/services/cockpit_compatibility.dart';
import 'package:vinabike_erp/modules/bikeshop/services/part_bike_fact_change.dart';
import 'package:vinabike_erp/shared/models/product_compatibility.dart';

// Las filas sin rueda de `bike_fact_spec_links` como las entrega PostgREST
// (20261002170000).
final _links = [
  for (final row in const [
    {
      'spec_key': 'bar_clamp_diameter_mm',
      'position': 'none',
      'bike_fact_key': 'handlebarClampMm',
      'component_label': 'abrazadera del manubrio',
      'component_article': 'la',
      'unit': 'mm',
      'min_value': 20,
      'max_value': 40,
      'template_key': 'handlebar',
      'on_mismatch': 'change',
      'value_decimals': 1,
    },
    {
      'spec_key': 'grip_area_diameter_mm',
      'position': 'none',
      'bike_fact_key': 'controlsBarDiameterMm',
      'component_label': 'zona de mandos',
      'component_article': 'la',
      'unit': 'mm',
      'min_value': 20,
      'max_value': 30,
      'template_key': 'handlebar',
      'on_mismatch': 'change',
      'value_decimals': 1,
    },
    {
      'spec_key': 'handlebar_clamp_mm',
      'position': 'none',
      'bike_fact_key': 'controlsBarDiameterMm',
      'component_label': 'zona de mandos',
      'component_article': 'la',
      'unit': 'mm',
      'min_value': 20,
      'max_value': 30,
      'template_key': 'shifter',
      'on_mismatch': 'conflict',
      'value_decimals': 1,
    },
    {
      'spec_key': 'steerer_fit',
      'position': 'none',
      'bike_fact_key': 'steererFit',
      'component_label': 'tubo de horquilla',
      'min_value': 0,
      'max_value': 0,
      'template_key': 'fork',
      'on_mismatch': 'change',
      'value_map': {
        '1 1/8" (28.6 mm)': 'straight_1_1_8',
        'Tapered 1 1/8" – 1.5"': 'tapered_1_1_8_1_5',
      },
      'value_decimals': 0,
    },
    {
      'spec_key': 'seatpost_diameter_mm',
      'position': 'none',
      'bike_fact_key': 'seatpostDiameterMm',
      'component_label': 'tija',
      'component_article': 'la',
      'unit': 'mm',
      'min_value': 20,
      'max_value': 36,
      'template_key': 'seatpost',
      'on_mismatch': 'change',
      'product_condition': {
        'spec_key': 'seatpost_kind',
        'values': ['Rígida', 'Con suspensión', 'Telescópica (dropper)'],
        'missing_ok': true,
      },
      'value_decimals': 1,
    },
  ])
    BikeFactSpecLink.fromJson(row)!,
];

// Las fichas técnicas como las lee `get_product_spec_contexts_v1` en
// producción (2026-10-02).
const _handlebar = {
  '__template_key': 'handlebar',
  'bar_clamp_diameter_mm': 31.8,
  'grip_area_diameter_mm': 22.2,
};
const _shifter = {'__template_key': 'shifter', 'handlebar_clamp_mm': 22.2};
const _kalloy = {
  '__template_key': 'seatpost',
  'seatpost_diameter_mm': 27.2,
  'seatpost_kind': 'Rígida',
};
const _shim = {
  '__template_key': 'seatpost',
  'seatpost_diameter_mm': 30.9,
  'seatpost_kind': 'Suplemento (shim)',
};

void main() {
  group('a part of the whole bike', () {
    test('reads its row without a wheel and with tenths', () {
      final clamp = _links.first;
      expect(clamp.position, BikeMemoryLocation.none);
      expect(clamp.isBikeWide, isTrue);
      expect(clamp.valueDecimals, 1);
      expect(clamp.productValue(_handlebar), 31.8);
      expect(
          clamp.productValue({..._handlebar, 'bar_clamp_diameter_mm': 31.85}),
          isNull,
          reason: 'más décimas de las que acepta la fila no se redondean');
      expect(
          clamp.productValue({..._handlebar, 'bar_clamp_diameter_mm': '25,4'}),
          25.4,
          reason: 'con coma, como la lee el servidor');
      expect(clamp.measureLabel(31.8), '31,8 mm');
      expect(_links[3].measureLabel('tapered_1_1_8_1_5'), 'Cónico 1⅛″–1,5″');
    });

    test('marks itself: every datum it changes, a shim none', () {
      expect(
        bikeWidePartMarker(links: _links, productSpecValues: _handlebar),
        [
          {'key': 'controlsBarDiameterMm', 'value': 22.2},
          {'key': 'handlebarClampMm', 'value': 31.8},
        ],
      );
      expect(bikeWidePartMarker(links: _links, productSpecValues: _kalloy),
          {'key': 'seatpostDiameterMm', 'value': 27.2});
      expect(
          bikeWidePartMarker(links: _links, productSpecValues: _shim), isNull);
      expect(
        partWheelPositions(links: _links, productSpecValues: _handlebar),
        isEmpty,
        reason: 'no tiene rueda que elegir',
      );
    });

    test('a mark with tenths survives a save and a reload', () {
      expect(
        samePartChangeMarker(
          {'key': 'handlebarClampMm', 'value': 31.8},
          {'key': 'handlebarClampMm', 'value': '31.8'},
        ),
        isTrue,
      );
      expect(
        samePartChangeMarker(
          {'key': 'handlebarClampMm', 'value': 31.8},
          {'key': 'handlebarClampMm', 'value': 31.9},
        ),
        isFalse,
      );
    });

    test('says what the line changes, and what does not fit', () {
      final change = partBikeFactChanges(
        links: _links,
        productSpecValues: _handlebar,
        location: BikeMemoryLocation.none,
        confirmedMarker:
            bikeWidePartMarker(links: _links, productSpecValues: _handlebar),
        bikeValues: const {'handlebarClampMm': 25.4},
      );
      expect(change.map((c) => c.label), [
        'Cambia la ficha al terminar: zona de mandos 22,2 mm',
        'Cambia la ficha al terminar: abrazadera del manubrio 25,4 mm → '
            '31,8 mm',
      ]);

      final road = partBikeFactChanges(
        links: _links,
        productSpecValues: _shifter,
        location: BikeMemoryLocation.none,
        confirmedMarker:
            bikeWidePartMarker(links: _links, productSpecValues: _shifter),
        bikeValues: const {'controlsBarDiameterMm': 23.8},
        bikeConfirmed: const {'controlsBarDiameterMm': true},
      ).single;
      expect(road.status, PartBikeFactChangeStatus.incompatible);
      expect(
          road.label, 'No calza: en la ficha la zona de mandos es de 23,8 mm');
      expect(road.tooltip, startsWith('Manillas, mandos y puños calzan'));

      final unknown = partBikeFactChanges(
        links: _links,
        productSpecValues: _shifter,
        location: BikeMemoryLocation.none,
        confirmedMarker:
            bikeWidePartMarker(links: _links, productSpecValues: _shifter),
      ).single;
      expect(
          unknown.label,
          'La ficha lo anota al terminar: zona de mandos '
          '22,2 mm');
    });
  });

  group('the sheet', () {
    Bike bike({BikeType? type = BikeType.road}) => Bike(
          id: 'bike-1',
          tenantId: 'tenant-1',
          customerId: 'customer-1',
          bikeType: type,
          updatedAt: DateTime.utc(2026, 10, 2),
        );

    test('section 6 has the seven data, from what the job installed', () {
      final draft = BikeSpecDraft.fromRecord(
        bike: bike(),
        profile: BikeProfile(
          id: 'profile-1',
          tenantId: 'tenant-1',
          bikeId: 'bike-1',
          technicalProfile: const {
            'values': {
              'handlebarClampMm': 31.8,
              'seatpostDiameterMm': 27.2,
              'steererFit': 'tapered_1_1_8_1_5',
            },
            'sources': {
              'handlebarClampMm': 'job_completion',
              'seatpostDiameterMm': 'job_completion',
              'steererFit': 'job_completion',
            },
            'confirmed': {'steererFit': true},
          },
        ),
      );
      final section = BikeSpecDraft.sections.last;
      expect(section.number, 6);
      expect(section.fields.map((field) => field.label), [
        'Tubo de horquilla',
        'Dirección arriba (SHIS)',
        'Dirección abajo (SHIS)',
        'Manubrio (abrazadera)',
        'Zona de mandos',
        'Tija',
        'Tipo de tija',
      ]);
      expect(draft.value('handlebarClampMm'), '31.8');
      expect(draft.labelFor('handlebarClampMm', '31.8'), '31,8 mm');
      expect(draft.canReview('handlebarClampMm'), isTrue);
      expect(draft.canReview('steererFit'), isFalse);
    });

    test('the bike type suggests the control zone; using it saves a number',
        () {
      final draft = BikeSpecDraft.fromRecord(bike: bike());
      expect(draft.suggestion('controlsBarDiameterMm'), '23.8');
      draft.set(
          'controlsBarDiameterMm', draft.suggestion('controlsBarDiameterMm'));
      expect(draft.suggestion('controlsBarDiameterMm'), isNull);
      final built = draft.build(confirmedAt: DateTime.utc(2026, 10, 2));
      expect(built.profile?.technicalValues['controlsBarDiameterMm'], 23.8);
      expect(
          built.profile?.technicalSources['controlsBarDiameterMm'], 'mechanic');
      expect(built.profile?.technicalConfirmed['controlsBarDiameterMm'], true);

      final mtb =
          BikeSpecDraft.fromRecord(bike: bike(type: BikeType.mountainHardtail));
      expect(mtb.suggestion('controlsBarDiameterMm'), '22.2');
      expect(
          BikeSpecDraft.fromRecord(bike: bike(type: BikeType.electric))
              .suggestion('controlsBarDiameterMm'),
          isNull);
    });
  });

  group('the matrix when adding a part', () {
    ProductCompatibilityAssessment? assess(
      Map<String, dynamic> spec,
      Map<String, dynamic> bike, {
      BikeType? type,
    }) =>
        assessCockpitCompatibility(
          templateKey: spec['__template_key'] as String?,
          specValues: spec,
          technicalValues: bike,
          bikeType: type,
        );

    test('a seatpost: thinner with a sleeve, thicker never', () {
      expect(assess(_kalloy, {'seatpostDiameterMm': 27.2})?.level,
          ProductCompatibilityLevel.compatible);
      final thick = assess({
        ..._kalloy,
        'seatpost_diameter_mm': 30.9,
      }, {
        'seatpostDiameterMm': 27.2,
      });
      expect(thick?.level, ProductCompatibilityLevel.incompatible);
      expect(thick?.detail,
          'Esta tija es de 30,9 mm y la bici usa 27,2 mm: no entra.');
      expect(assess(_kalloy, {'seatpostDiameterMm': 30.9})?.level,
          ProductCompatibilityLevel.caution);
      expect(assess(_shim, {'seatpostDiameterMm': 27.2}), isNull);
    });

    test('controls go by the control zone, or the type while it is unknown',
        () {
      expect(assess(_shifter, {'controlsBarDiameterMm': 23.8})?.level,
          ProductCompatibilityLevel.incompatible);
      expect(assess(_shifter, const {}, type: BikeType.road)?.level,
          ProductCompatibilityLevel.caution);
      expect(
          assess(_shifter, const {}, type: BikeType.mountainHardtail), isNull);
    });

    test('a stem: a thinner bar with a shim, a thicker one never', () {
      const stem = {
        '__template_key': 'stem',
        'bar_clamp_diameter_mm': 31.8,
        'stem_steerer_clamp_diameter_mm': 28.6,
      };
      expect(assess(stem, {'handlebarClampMm': 31.8})?.level,
          ProductCompatibilityLevel.compatible);
      expect(assess(stem, {'handlebarClampMm': 25.4})?.level,
          ProductCompatibilityLevel.caution);
      expect(
        assess({...stem, 'bar_clamp_diameter_mm': 25.4},
            {'handlebarClampMm': 31.8})?.level,
        ProductCompatibilityLevel.incompatible,
      );
      expect(
        assess(stem, {'steererFit': 'tapered_1_1_8_1_5'})?.level,
        ProductCompatibilityLevel.compatible,
        reason: 'un tubo cónico es 1⅛″ arriba',
      );
      expect(assess(stem, {'steererFit': 'straight_1_1_4'})?.level,
          ProductCompatibilityLevel.incompatible);
    });

    test('a fork: tapered never in a straight head tube', () {
      const tapered = {
        '__template_key': 'fork',
        'steerer_fit': 'Tapered 1 1/8" – 1.5"',
      };
      const straight = {
        '__template_key': 'fork',
        'steerer_fit': '1 1/8" (28.6 mm)',
      };
      expect(assess(tapered, {'steererFit': 'straight_1_1_8'})?.level,
          ProductCompatibilityLevel.incompatible);
      expect(assess(straight, {'steererFit': 'tapered_1_1_8_1_5'})?.level,
          ProductCompatibilityLevel.caution);
      expect(assess(straight, {'steererFit': 'straight_1_1_8'})?.level,
          ProductCompatibilityLevel.compatible);
      expect(assess(straight, const {}), isNull);
      // «No sé» no es «no calza».
      for (final unknown in [
        'unknown',
        'desconocido',
        '',
        'straight_1_1_8_old'
      ]) {
        expect(assess(tapered, {'steererFit': unknown}), isNull,
            reason: unknown);
      }
    });

    test('there is something to compare with', () {
      expect(cockpitFactsKnown(const {}, bikeType: BikeType.road), isTrue);
      expect(cockpitFactsKnown(const {}), isFalse);
      expect(cockpitFactsKnown(const {'seatpostDiameterMm': 27.2}), isTrue);
      expect(cockpitFactsKnown(const {'steererFit': 'unknown'}), isFalse);
      expect(cockpitFactsKnown(const {'steererFit': 'straight_1_1_8'}), isTrue);
      expect(suggestedControlsBarDiameterForBikeType(BikeType.gravel), 23.8);
    });
  });
}
