import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_technical_fact_patch.dart';

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

  test('lo que no llegó a la ficha espera hasta llegar o descartarse',
      () async {
    unsentBikeFactPromotionsByJob.clear();
    PendingBikeFactPromotion promotion(String key) => PendingBikeFactPromotion(
          operationKey: key,
          baseline: _profile({}),
          target: _profile({'valveType': 'presta'}),
        );
    final pending = {
      'sin-red': promotion('op-a'),
      'cambiada': promotion('op-b'),
      'escrita': promotion('op-c'),
    };
    final networkUp = <String>{};
    Future<BikeProfile?> patch({
      required String operationKey,
      required String bikeId,
      required String jobId,
      required List<BikeTechnicalFact> facts,
    }) async {
      if (bikeId == 'cambiada') {
        throw const BikeTechnicalFactConflict(['valveType']);
      }
      if (bikeId == 'sin-red' && !networkUp.contains(bikeId)) {
        throw Exception('sin red');
      }
      return _profile({'valveType': 'presta'});
    }

    // Primer intento y un reintento al abrir que vuelve a fallar: el
    // pendiente sigue ahí, con su llave; el conflicto y lo escrito no.
    for (var attempt = 0; attempt < 2; attempt++) {
      final outcome = await writePendingBikeFactPromotions(
        jobId: 'job',
        pending: attempt == 0
            ? pending
            : Map.of(unsentBikeFactPromotionsByJob['job']!),
        patch: patch,
      );
      expect(outcome.failed.keys, ['sin-red']);
      expect(unsentBikeFactPromotionsByJob['job']!.keys, ['sin-red']);
      expect(unsentBikeFactPromotionsByJob['job']!['sin-red']!.operationKey,
          'op-a');
      if (attempt == 0) {
        expect(outcome.discarded.keys, ['cambiada']);
        expect(outcome.written.keys, ['escrita']);
      }
    }

    networkUp.add('sin-red');
    await writePendingBikeFactPromotions(
      jobId: 'job',
      pending: Map.of(unsentBikeFactPromotionsByJob['job']!),
      patch: patch,
    );
    expect(unsentBikeFactPromotionsByJob.containsKey('job'), isFalse);
  });

  test('el conflicto nombra las claves que cambiaron', () {
    expect(
      const BikeTechnicalFactConflict(['brakeType']).toString(),
      contains('brakeType'),
    );
  });

  test('una línea terminada que se corrige vuelve a escribir lo que instala',
      () {
    const line = 'e2790000-0000-4000-8000-000000000061';
    final keys = <String>[];
    String? next(int holes) {
      final key = nextJobCompletionOperationKey(
        itemId: line,
        installed: {'rearSpokeHoles': holes},
        existingKeys: keys,
      );
      if (key != null) keys.add(key);
      return key;
    }

    expect(next(28), 'job_completion:$line:1:rearSpokeHoles=28');
    expect(next(28), isNull, reason: 'un reintento no reescribe');
    expect(next(32), 'job_completion:$line:2:rearSpokeHoles=32');
    expect(next(28), 'job_completion:$line:3:rearSpokeHoles=28',
        reason: 'con la llave <línea>:<datos> este 28H encontraba el primer '
            'recibo y la ficha quedaba en 32H');
    expect(
      nextJobCompletionOperationKey(
        itemId: line,
        installed: {'rearSpokeHoles': 28},
        existingKeys: [
          ...keys,
          'job_completion:otra-linea:9:rearSpokeHoles=36',
          'job_completion:$line:rearSpokeHoles=36',
        ],
      ),
      isNull,
      reason: 'sólo cuentan los recibos numerados de esta línea',
    );
  });
}
