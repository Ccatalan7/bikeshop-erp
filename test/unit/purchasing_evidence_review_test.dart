import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

import 'purchasing_independent_review_test.dart' as qa;

void main() {
  test('a negation after the model cannot prove compatibility', () {
    final match = qa.judge('Pastillas para Shimano MT200',
        'PASTILLA SHIMANO MT200 NO ES COMPATIBLE',
        head: 'PASTILLA');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
  });

  test('a spaced model cannot evade a negative compatibility statement', () {
    final match = qa.judge('Pastillas para Shimano MT200',
        'PASTILLA SHIMANO NO COMPATIBLE CON MT 200',
        head: 'PASTILLA');
    expect(match.state, isNot(SupplierNeedMatchState.exact));
  });

  test('the absence of fins does not negate compatibility with the model', () {
    final match = qa.judge('Pastillas para Shimano MT200',
        'PASTILLA SHIMANO SIN ALETAS PARA MT200',
        head: 'PASTILLA');
    expect(match.state, isNot(SupplierNeedMatchState.conflict));
    expect(match.provenFields, contains(kCompatibilityRequirementField));
  });

  SupplierSpecExtractionResult verifyOne({
    required SupplierNeedSearchField field,
    required String row,
    required Object value,
    required String quote,
  }) =>
      verifySupplierSpecExtraction(
        fields: [field],
        rows: [SupplierSpecExtractionRow(id: 'source-row', text: row)],
        response: {
          'rows': [
            {
              'id': 'source-row',
              'facts': [
                {'field': field.key, 'value': value, 'quote': quote},
              ],
            },
          ],
        },
      );

  test('a literal quote does not prove an unsupported enum subtype', () {
    final result = verifyOne(
      field: const SupplierNeedSearchField(
        key: 'brake_type',
        label: 'Tipo de Freno',
        dataType: 'single_select',
        allowedValues: ['Disco Hidráulico', 'Disco Mecánico', 'V-Brake'],
      ),
      row: 'PASTILLA FRENO DISCO BP-10/SP-10',
      value: 'Disco Hidráulico',
      quote: 'FRENO DISCO',
    );
    expect(result.readings['source-row']?['brake_type'], isNull);
  });

  test('a numeric fact must agree with the quoted measurement', () {
    final result = verifyOne(
      field: const SupplierNeedSearchField(
        key: 'valve_length_mm',
        label: 'Largo de válvula',
        dataType: 'number',
        unit: 'mm',
      ),
      row: 'CAMARA CON VALVULA DE 48 MM',
      value: 80,
      quote: '48 MM',
    );
    expect(result.readings['source-row']?['valve_length_mm'], isNull);
  });

  test('a positive boolean cannot use an explicit absence as proof', () {
    final result = verifyOne(
      field: const SupplierNeedSearchField(
        key: 'pad_finned',
        label: 'Con Aletas de Calor',
        dataType: 'boolean',
      ),
      row: 'PASTILLA SIN ALETAS DE CALOR',
      value: true,
      quote: 'SIN ALETAS DE CALOR',
    );
    expect(result.readings['source-row']?['pad_finned'], isNull);
  });
}
