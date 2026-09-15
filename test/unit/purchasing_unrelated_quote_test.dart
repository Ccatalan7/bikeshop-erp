import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

void main() {
  test('an unrelated quote cannot prove an enum subtype either', () {
    final result = verifySupplierSpecExtraction(
      fields: const [SupplierNeedSearchField(
        key: 'brake_type', label: 'Tipo de Freno', dataType: 'single_select',
        allowedValues: ['Disco Hidráulico', 'Disco Mecánico', 'V-Brake'],
      )],
      rows: const [SupplierSpecExtractionRow(
        id: 'row', text: 'PASTILLA FRENO DISCO BP-10/SP-10',
      )],
      response: {'rows': [{'id': 'row', 'facts': [{
        'field': 'brake_type', 'value': 'Disco Hidráulico', 'quote': 'PASTILLA',
      }]}]},
    );
    expect(result.readings['row']?['brake_type'], isNull,
      reason: 'que la cita no comparta palabras no demuestra una traducción');
  });
}
