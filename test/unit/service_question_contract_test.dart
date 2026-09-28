import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/service_question_contract.dart';

/// Las preguntas vivas de «Configurar» contra su contrato.
///
/// Una pregunta sin contrato es una respuesta que nadie decidió dónde vive: la
/// deriva que `BIKE_WORKSHOP_MASTER_SCHEMA.md` prohíbe.
///
/// El fixture es una foto fechada: una pregunta nueva en producción no hace
/// fallar esta prueba hasta refrescarlo. Se refresca antes de tocar el wizard
/// o un perfil, con
/// `scripts/db/query.sh production --file
/// supabase/manual_checks/service_question_contract_live.sql --format csv`,
/// y en la app una pregunta sin contrato se trata como propia del servicio:
/// nunca se promueve a la ficha ni se proyecta al diagnóstico.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/bike_workshop/live_service_questions_2026-09-27.json')
        .readAsStringSync(),
  ) as List<dynamic>;
  final live = fixture.cast<Map<String, dynamic>>();
  final livePairs = {
    for (final row in live) '${row['family']}/${row['key']}',
  };

  test('cada pregunta viva tiene un solo contrato', () {
    final missing = [
      for (final pair in livePairs)
        if (serviceQuestionContractFor(
              family: pair.split('/').first,
              key: pair.split('/').last,
            ) ==
            null)
          pair,
    ];
    expect(missing, isEmpty, reason: 'preguntas vivas sin destino decidido');

    final declared = [
      for (final contract in kServiceQuestionContracts)
        '${contract.family}/${contract.key}',
    ];
    expect(declared.toSet().length, declared.length,
        reason: 'un par familia/clave con dos contratos');
    expect(declared.toSet(), livePairs,
        reason: 'un contrato para una pregunta que ya no existe en producción');
  });

  test('cada destino trae lo que necesita para cumplirse', () {
    for (final contract in kServiceQuestionContracts) {
      final id = '${contract.family}/${contract.key}';
      switch (contract.destination) {
        case ServiceQuestionDestination.lineTarget:
          expect(contract.key, 'which_wheel', reason: id);
        case ServiceQuestionDestination.bikeProfile:
          expect(
            contract.profileKey != null ||
                contract.profileKeyByLocation != null,
            isTrue,
            reason: '$id va a la ficha sin clave',
          );
        case ServiceQuestionDestination.diagnosis:
          expect(contract.diagnosisSystem, isNotNull, reason: id);
          expect(contract.diagnosisField, isNotNull, reason: id);
        case ServiceQuestionDestination.serviceExecution:
          expect(contract.profileKey, isNull, reason: id);
          expect(contract.diagnosisField, isNull, reason: id);
      }
      expect(
        contract.upstreamCandidate == null,
        contract.upstreamDecision == null,
        reason: '$id: un candidato de la ficha lleva la decisión del paso F',
      );
      if (contract.appliesOnCompletion) {
        expect(contract.destination, ServiceQuestionDestination.bikeProfile,
            reason: '$id: sólo la ficha cambia al terminar el trabajo');
      }
      expect(
        contract.honored || (contract.gap?.isNotEmpty ?? false),
        isTrue,
        reason: '$id no se cumple y no dice qué falta',
      );
    }
  });

  test('las preguntas de la rueda de la línea son siempre la misma', () {
    final targets = [
      for (final row in live)
        if (row['key'] == 'which_wheel') row,
    ];
    for (final row in targets) {
      final options = (row['options'] as List).cast<String>().toSet();
      expect(options.difference({'front', 'rear', 'both'}), isEmpty,
          reason: '${row['profile']} usa otro vocabulario de rueda');
    }
  });

  test('la familia heredada «brakes» resuelve al contrato de «brake»', () {
    expect(
      serviceQuestionContractFor(family: 'brakes', key: 'brake_type'),
      same(serviceQuestionContractFor(family: 'brake', key: 'brake_type')),
    );
  });
}
