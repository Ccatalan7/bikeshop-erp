import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_answer_changes.dart';
import 'package:vinabike_erp/modules/bikeshop/services/wheel_service_facts.dart';

const _front = {BikeMemoryLocation.front};
const _both = {BikeMemoryLocation.front, BikeMemoryLocation.rear};

void main() {
  test('«ambas» es un solo resolvedor para freno y ruedas', () {
    expect(
      serviceWheelPositions(BikeMemoryLocation.none, {'which_wheel': 'both'}),
      _both,
    );
    expect(
      serviceWheelPositions(BikeMemoryLocation.rear, {'which_wheel': 'both'}),
      {BikeMemoryLocation.rear},
      reason: 'la ubicación de la línea manda sobre la respuesta',
    );
  });

  test('una rueda sugiere lo de toda la bici; lo que arma espera al término',
      () {
    const answers = {
      'hole_count': '32',
      'valve_type': 'presta',
      'brake_type': 'v_brake',
    };

    final oneWheel = wheelServiceFacts(
      positions: _front,
      answers: answers,
      values: const {},
      confirmed: const {},
    );
    expect(oneWheel.confirm, isEmpty,
        reason: 'configurar un Enrayado no cambia la rueda de la bici');
    expect(oneWheel.onCompletion, {'frontSpokeHoles': 32});
    expect(oneWheel.suggest, {
      'valveType': 'presta',
      'brakeType': 'rim',
      'rimBrakeFamily': 'v_brake',
    });

    final bothWheels = wheelServiceFacts(
      positions: _both,
      answers: answers,
      values: const {},
      confirmed: const {},
    );
    expect(bothWheels.confirm, {
      'valveType': 'presta',
      'brakeType': 'rim',
      'rimBrakeFamily': 'v_brake',
    });
    expect(bothWheels.suggest, isEmpty);
    expect(bothWheels.differences.single, contains('cada rueda'),
        reason: 'un número para las dos ruedas no afirma que sean iguales');
  });

  test('lo observado no pisa lo confirmado; lo armado lo cambia al terminar',
      () {
    final facts = wheelServiceFacts(
      positions: _front,
      answers: const {
        'hole_count': '28',
        'valve_type': 'presta',
        'brake_type': 'hydraulic_disc',
      },
      values: const {
        'frontSpokeHoles': 32,
        'valveType': 'schrader',
        'brakeType': 'rim',
      },
      confirmed: const {
        'frontSpokeHoles': true,
        'valveType': true,
        'brakeType': true,
      },
    );
    expect(facts.isEmpty, isTrue);
    expect(facts.differences, hasLength(2));
    expect(facts.onCompletion, {'frontSpokeHoles': 28});
    expect(wheelServiceFactsSummary(facts), contains('(hoy 32H)'));

    final suggestedAlready = wheelServiceFacts(
      positions: _front,
      answers: const {'valve_type': 'schrader'},
      values: const {'valveType': 'presta'},
      confirmed: const {},
    );
    expect(suggestedAlready.isEmpty, isTrue,
        reason: 'una rueda no reemplaza lo que otra sugirió');
    expect(suggestedAlready.differences, hasLength(1));
  });

  test('lo confirmado no se pregunta; lo sugerido se precarga a la vista', () {
    final prefill = wheelServicePrefill(
      positions: _front,
      bikeWheelSize: "29''",
      values: const {'frontSpokeHoles': 32, 'valveType': 'presta'},
      confirmed: const {'frontSpokeHoles': true},
      optionsByKey: const {
        'wheel_size': {'v_26', 'v_29'},
        'hole_count': {'28', '32'},
        'valve_type': {'presta', 'schrader'},
      },
    );
    expect(prefill.answers, {
      'wheel_size': 'v_29',
      'hole_count': '32',
      'valve_type': 'presta',
    });
    expect(prefill.hiddenKeys, isEmpty,
        reason: 'el aro es texto registrado y las perforaciones son de la '
            'rueda que se arma: ambos se precargan a la vista');

    final ambiguous = wheelServicePrefill(
      positions: _front,
      bikeWheelSize: '27.5" - 26"',
      values: const {},
      confirmed: const {},
      optionsByKey: const {
        'wheel_size': {'v_26', 'v_27_5'},
      },
    );
    expect(ambiguous.answers, isEmpty,
        reason: 'un aro que no se lee sin adivinar se pregunta sin precarga');
  });

  test('el diagnóstico recibe sólo lo que la respuesta dice', () {
    final major = wheelDiagnosisFindings(const {'rim_damage': 'major'});
    expect(major.rimCondition, 'bent', reason: 'golpeado, no fisurado');
    expect(major.status, 'critical');

    final noise = wheelDiagnosisFindings(const {'symptom': 'noise'});
    expect(noise.hubBearingCondition, isNull);
    expect(noise.status, 'attention');

    expect(wheelDiagnosisFindings(const {'symptom': 'preventive'}).isEmpty,
        isTrue);
    expect(
      wheelAnswersFromDiagnosis(tireCondition: 'worn', rimCondition: 'cracked'),
      {'tire_condition': 'worn', 'rim_damage': 'major'},
    );
  });

  test('freno: el tipo es de la bici, el rotor de cada rueda', () {
    final rear = brakeServiceFacts(
      positions: const {BikeMemoryLocation.rear},
      answers: const {'brake_type': 'hydraulic_disc', 'rotor_size': '160'},
      values: const {'frontRotorSizeMm': 180},
      confirmed: const {'frontRotorSizeMm': true},
    );
    expect(rear.suggest, {'brakeType': 'hydraulic_disc'});
    expect(rear.confirm, {'rearRotorSizeMm': 160});

    final both = brakeServiceFacts(
      positions: _both,
      answers: const {'brake_type': 'hydraulic_disc', 'rotor_size': '180'},
      values: const {},
      confirmed: const {},
    );
    expect(both.confirm, {'brakeType': 'hydraulic_disc'},
        reason: 'un tamaño para dos rotores no afirma que sean iguales');
    expect(both.differences.single, contains('cada rueda'));
  });

  group('paso F.2: fluido y eje con los códigos del registro', () {
    const pasante15 = 'catalog_d2128659275dc69ee5e50dc9500992fa';
    const cierre9 = 'catalog_70d7fea9eaec337320d0814e6a8e7836';

    test('el fluido es de cada freno: mineral adelante no dice nada atrás', () {
      // Delantero mineral confirmado; se sangra el trasero con DOT 5.1.
      final rear = brakeServiceFacts(
        positions: const {BikeMemoryLocation.rear},
        answers: const {'fluid_type': 'dot_5_1'},
        values: const {'frontBrakeFluidType': 'aceite_mineral'},
        confirmed: const {'frontBrakeFluidType': true},
      );
      expect(rear.confirm, {'rearBrakeFluidType': 'dot_5_1'});
      expect(rear.differences, isEmpty,
          reason: 'cada freno es su propio sistema');

      final both = brakeServiceFacts(
        positions: _both,
        answers: const {'fluid_type': 'mineral'},
        values: const {},
        confirmed: const {},
      );
      expect(
          both.confirm,
          {
            'frontBrakeFluidType': 'aceite_mineral',
            'rearBrakeFluidType': 'aceite_mineral',
          },
          reason: 'sangrar los dos con un fluido lo pone en cada uno');

      final conflict = brakeServiceFacts(
        positions: _front,
        answers: const {'fluid_type': 'dot_5_1'},
        values: const {'frontBrakeFluidType': 'aceite_mineral'},
        confirmed: const {'frontBrakeFluidType': true},
      );
      expect(conflict.confirm, isEmpty);
      expect(
        conflict.differences.single,
        'Fluido del freno delantero: la ficha dice Aceite mineral y el '
        'servicio DOT 5.1. No se cambia desde aquí.',
      );
      expect(
        brakeServiceFacts(
          positions: _both,
          answers: const {'fluid_type': 'dot'},
          values: const {},
          confirmed: const {},
        ).isEmpty,
        isTrue,
        reason: '«dot» a secas no dice si es DOT 4 o DOT 5.1',
      );
    });

    test('el eje se confirma con su rueda y en palabras de taller', () {
      final front = wheelServiceFacts(
        positions: _front,
        answers: const {'axle_type': pasante15},
        values: const {},
        confirmed: const {},
      );
      expect(front.confirm, {'frontAxleInterface': pasante15});

      final unknown = wheelServiceFacts(
        positions: _front,
        answers: const {
          'axle_type': 'catalog_de6e897b1c6ced32e6762f3ceaebffd6'
        },
        values: const {},
        confirmed: const {},
      );
      expect(unknown.isEmpty, isTrue,
          reason: '«Desconocido / sin confirmar» no es un eje');

      final conflict = wheelServiceFacts(
        positions: _front,
        answers: const {'axle_type': cierre9},
        values: const {'frontAxleInterface': pasante15},
        confirmed: const {'frontAxleInterface': true},
      );
      expect(conflict.confirm, isEmpty);
      expect(
        conflict.differences.single,
        'Eje de la rueda delantera: la ficha dice Eje pasante 15 mm y el '
        'servicio Cierre rápido 9 mm (delantero). No se cambia desde aquí.',
      );
    });

    test('el eje confirmado no se pregunta; el desconocido no se precarga', () {
      final options = {
        'axle_type': {
          pasante15,
          cierre9,
          'catalog_de6e897b1c6ced32e6762f3ceaebffd6'
        },
      };
      final confirmed = wheelServicePrefill(
        positions: _front,
        bikeWheelSize: null,
        values: const {'frontAxleInterface': pasante15},
        confirmed: const {'frontAxleInterface': true},
        optionsByKey: options,
      );
      expect(confirmed.answers['axle_type'], pasante15);
      expect(confirmed.hiddenKeys, contains('axle_type'));
      expect(confirmed.knownFacts, contains('Eje pasante 15 mm'));

      final rearOnly = wheelServicePrefill(
        positions: _front,
        bikeWheelSize: null,
        values: const {'rearAxleInterface': pasante15},
        confirmed: const {'rearAxleInterface': true},
        optionsByKey: options,
      );
      expect(rearOnly.answers, isNot(contains('axle_type')),
          reason: 'el eje trasero no dice nada de la rueda delantera');

      final unknown = wheelServicePrefill(
        positions: _front,
        bikeWheelSize: null,
        values: const {
          'frontAxleInterface': 'catalog_de6e897b1c6ced32e6762f3ceaebffd6',
        },
        confirmed: const {},
        optionsByKey: options,
      );
      expect(unknown.answers, isNot(contains('axle_type')));
    });
  });

  test('la precarga devuelta igual no reescribe el diagnóstico', () {
    final prefill = wheelAnswersFromDiagnosis(
      tireCondition: 'worn',
      rimCondition: 'cracked',
    );
    final unchanged = wheelDiagnosisFindings(
      answersChangedFromPrefill(Map.of(prefill), prefill),
    );
    expect(unchanged.isEmpty, isTrue,
        reason: 'un aro fisurado precargado como «mayor» volvía golpeado');

    final changed = wheelDiagnosisFindings(answersChangedFromPrefill(
      {...prefill, 'tire_condition': 'damaged'},
      prefill,
    ));
    expect(changed.tireCondition, 'damaged');
    expect(changed.rimCondition, isNull);
  });

  test('reabrir sin tocar no rebaja un diagnóstico que cambió después', () {
    // La línea guardó «menor»; después el diagnóstico pasó a fisurado.
    final fromDiagnosis = wheelAnswersFromDiagnosis(rimCondition: 'cracked');
    final opened = answersWithDiagnosisPrefill(
      const {'rim_damage': 'minor', 'which_wheel': 'rear'},
      fromDiagnosis,
    );
    expect(opened['rim_damage'], 'major',
        reason: 'la capa del diagnóstico es el mismo registro, no una copia');
    expect(
      wheelDiagnosisFindings(answersChangedFromPrefill(opened, fromDiagnosis))
          .rimCondition,
      isNull,
      reason: 'guardar sin tocar no escribe nada sobre «fisurado»',
    );
  });
}
