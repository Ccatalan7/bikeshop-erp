import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_technical_fact_patch.dart';
import 'package:vinabike_erp/modules/bikeshop/services/wheel_service_facts.dart';

BikeProfile _profile(
  Map<String, dynamic> values, {
  Map<String, dynamic> confirmed = const {},
}) {
  return BikeProfile(
    tenantId: 'tenant',
    bikeId: 'bike',
    technicalProfile: {
      'values': values,
      'sources': const <String, dynamic>{},
      'confirmed': confirmed,
    },
  );
}

void main() {
  test('sólo viaja lo que la promoción cambió, con el valor que se vio', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: _profile({
        'brakeType': 'rim',
        'frontSpokeHoles': 32,
        'suspensionLayout': 'rigid',
      }),
      target: _profile({
        'brakeType': 'rim',
        'rimBrakeFamily': 'v_brake',
        'frontSpokeHoles': 32,
        'suspensionLayout': 'rigid',
      }),
    );

    expect(facts.map((fact) => fact.toJson()), [
      {
        'key': 'rimBrakeFamily',
        'op': 'set',
        'value': 'v_brake',
        'expected': null,
        'expected_confirmed': false,
      },
    ]);
  });

  test('un valor distinto lleva el anterior como esperado', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: _profile({'bottomBracketFamily': 'pressfit'}),
      target: _profile({'bottomBracketFamily': 'bsa_threaded'}),
    );

    expect(facts.single.toJson(), {
      'key': 'bottomBracketFamily',
      'op': 'set',
      'value': 'bsa_threaded',
      'expected': 'pressfit',
      'expected_confirmed': false,
    });
  });

  test('una clave que desaparece se borra diciendo qué valor tenía', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: _profile({'bbShellDiameterMm': 41}),
      target: _profile({}),
    );

    expect(facts.single.toJson(), {
      'key': 'bbShellDiameterMm',
      'op': 'remove',
      'expected': 41,
      'expected_confirmed': false,
    });
  });

  test('confirmar el mismo valor viaja como confirmación', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: _profile({'drivetrainSpeeds': 11}),
      target: _profile(
        {'drivetrainSpeeds': 11},
        confirmed: {'drivetrainSpeeds': true},
      ),
    );

    expect(facts.single.toJson(), {
      'key': 'drivetrainSpeeds',
      'op': 'set',
      'value': 11,
      'expected': 11,
      'expected_confirmed': false,
    });
  });

  test('lo que ya estaba confirmado e igual no viaja', () {
    expect(
      bikeTechnicalFactsDiff(
        baseline: _profile(
          {'drivetrainSpeeds': 11},
          confirmed: {'drivetrainSpeeds': true},
        ),
        target: _profile(
          {'drivetrainSpeeds': 11.0},
          confirmed: {'drivetrainSpeeds': true},
        ),
      ),
      isEmpty,
    );
  });

  test('sin ficha cargada, todo viaja como nuevo', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: null,
      target: _profile({'freehubType': 'shimano_hg', 'drivetrainSpeeds': '9'}),
    );

    expect(facts.map((fact) => fact.toJson()), [
      {
        'key': 'drivetrainSpeeds',
        'op': 'set',
        'value': 9,
        'expected': null,
        'expected_confirmed': false,
      },
      {
        'key': 'freehubType',
        'op': 'set',
        'value': 'shimano_hg',
        'expected': null,
        'expected_confirmed': false,
      },
    ]);
  });

  test('lleva si el dato estaba confirmado cuando se cargó', () {
    final facts = bikeTechnicalFactsDiff(
      baseline: _profile(
        {'valveType': 'schrader'},
        confirmed: {'valveType': true},
      ),
      target: _profile({}),
    );

    expect(facts.single.toJson(), {
      'key': 'valveType',
      'op': 'remove',
      'expected': 'schrader',
      'expected_confirmed': true,
    });
  });

  test('una clave fuera del contrato no se pierde en silencio', () {
    expect(
      () => bikeTechnicalFactsDiff(
        baseline: _profile({'suspensionLayout': 'rigid'}),
        target: _profile({'suspensionLayout': 'front_suspension'}),
      ),
      throwsStateError,
    );
  });

  test('lo visto en una sola rueda viaja como sugerencia, nunca como reemplazo',
      () {
    BikeProfile suggested(Map<String, dynamic> values) => BikeProfile(
          tenantId: 'tenant',
          bikeId: 'bike',
          technicalProfile: {
            'values': values,
            'sources': const {'valveType': kServiceSuggestionSource},
            'confirmed': const <String, dynamic>{},
          },
        );

    expect(
      bikeTechnicalFactsDiff(
        baseline: _profile({'valveType': 'unknown'}),
        target: suggested({'valveType': 'presta'}),
      ).single.toJson(),
      {
        'key': 'valveType',
        'op': 'suggest',
        'value': 'presta',
        'expected': 'unknown',
        'expected_confirmed': false,
      },
    );
    expect(
      () => bikeTechnicalFactsDiff(
        baseline: _profile({'valveType': 'schrader'}),
        target: suggested({'valveType': 'presta'}),
      ),
      throwsStateError,
    );
  });

  test('una ficha nacida sólo de sugerencias no dice «Confirmado»', () {
    final bike = Bike(
      tenantId: 'tenant',
      customerId: 'customer',
      brand: 'Oxford',
      model: 'Sin ficha',
    );
    final suggestedOnly = BikeProfile(
      tenantId: 'tenant',
      bikeId: 'bike',
      technicalProfile: const {
        'values': {'valveType': 'presta'},
        'sources': {'valveType': kServiceSuggestionSource},
        'confirmed': <String, dynamic>{},
      },
    );

    expect(
      BikeProfileSummaryBuilder.buildSummarySnapshot(
        bike: bike,
        intakeProfile: const {},
        technicalValues: suggestedOnly.technicalValues,
      ),
      isNot(contains('lastConfirmedAt')),
    );
    expect(
      BikeRecordSnapshot.fromBikeAndProfile(bike: bike, profile: suggestedOnly)
          .lastConfirmedAt,
      isNull,
    );
  });

  test('el conflicto nombra las claves que cambiaron', () {
    expect(
      const BikeTechnicalFactConflict(['brakeType']).toString(),
      contains('brakeType'),
    );
  });

  // La llave `job_completion:<línea>:<n>:<datos>` y el 28H → 32H → 28H los
  // cuida ahora el servidor (supabase/tests/job_installed_bike_facts.sql):
  // la app sólo cuenta lo que no entró (ítem 4, 2026-09-28).
  test('lo instalado que la ficha no tomó se dice en el taller', () {
    final messages = installedBikeFactProblemMessages({
      'applied': [
        {'key': 'rearSpokeHoles', 'value': 28},
      ],
      'problems': [
        {
          'item_name': 'Enrayado sin bici',
          'key': 'frontSpokeHoles',
          'value': 28,
          'reason': 'line_without_bike',
        },
        {
          'item_name': 'Enrayado mal tipeado',
          'key': 'frontSpokeHoles',
          'value': 99,
          'reason': 'out_of_range',
        },
        {
          'item_name': 'Enrayado',
          'key': 'rearSpokeHoles',
          'value': 32,
          'reason': 'rejected',
          'message': 'Bicycle not found for current tenant',
        },
        {
          'item_name': 'Enrayado sin rueda',
          'value': '28',
          'reason': 'no_wheel'
        },
        {
          'item_name': 'Enrayado raro',
          'value': '28.5',
          'reason': 'invalid_value',
        },
        {
          'item_name': 'Enrayado Oxford',
          'bike_label': 'Oxford Dos',
          'key': 'frontSpokeHoles',
          'value': 36,
          'previous': 32,
          'reason': 'no_longer_installed',
        },
      ],
    });

    expect(messages, hasLength(6));
    expect(
      messages[5],
      'La ficha de Oxford Dos sigue diciendo 36H en la rueda delantera por '
      '«Enrayado Oxford», que ya no dice haberlo instalado ahí (antes: 32H en '
      'la rueda delantera). Si esa rueda no se armó, corrige su ficha; si sí, '
      'vuelve a elegir el dato en su campo de la ficha para confirmarlo.',
    );
    expect(messages[3], contains('no dice qué rueda armó'));
    expect(messages[4], contains('no dice un número de perforaciones'));
    expect(messages[0], contains('«Enrayado sin bici» no dice de qué bici es'));
    expect(messages[0], contains('28H en la rueda delantera'));
    expect(messages[1], contains('fuera de 12 a 48'));
    expect(messages[2], contains('se reintenta'));
    expect(installedBikeFactProblemMessages(null), isEmpty);
    expect(
      installedBikeFactProblemMessages({'applied': [], 'problems': []}),
      isEmpty,
    );
  });
}
