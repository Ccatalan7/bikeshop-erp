import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bearing_symptom_findings.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_answer_changes.dart';

void main() {
  test('el síntoma se separa en rodamiento o ruido, sin inventar el tipo', () {
    final play = bearingSymptomFindings('play');
    expect(play.bearingCondition, 'play');
    expect(play.noiseStatus, isNull);

    final noise = bearingSymptomFindings('noise');
    expect(noise.bearingCondition, isNull);
    expect(noise.noiseStatus, 'service',
        reason: 'no dice si es crujido, click o golpe');

    expect(bearingSymptomFindings('tightness').bearingCondition, 'service');
    expect(bearingSymptomFindings('preventive').isEmpty, isTrue);

    expect(
      bearingSymptomFromDiagnosis(bearingCondition: 'rough', noiseStatus: 'ok'),
      'roughness',
    );
    expect(bearingSymptomFromDiagnosis(noiseStatus: 'creaking'), 'noise');
  });

  test('un crujido precargado como «ruido» no baja a «requiere revisión»', () {
    final prefill = bearingSymptomFromDiagnosis(noiseStatus: 'creaking');
    final findings = bearingSymptomFindings(
      answersChangedFromPrefill(
          {'symptom': 'noise'}, {'symptom': prefill})['symptom'],
    );
    expect(findings.isEmpty, isTrue);
    expect(
      answersChangedFromPrefill(
        {
          'symptom': ['a', 'b']
        },
        {
          'symptom': ['b', 'a']
        },
      ),
      isEmpty,
      reason: 'una lista es la misma respuesta en otro orden',
    );
  });
}
