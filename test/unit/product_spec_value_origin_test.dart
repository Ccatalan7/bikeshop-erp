import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/models/product_spec_value_origin.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

void main() {
  test('each stored value says where it came from', () {
    // The KMC HV408 chain on 2026-10-01: speeds, width and links from the
    // supplier's text; the drivetrain type read from a name that no longer
    // matches the vocabulary it was judged with.
    final origins = ProductSpecValueOrigin.fromSnapshot({
      'value_sources': {
        'chain_speeds': {'source': 'supplier_text', 'reading_current': null},
        'drivetrain_mode': {'source': 'name_reading', 'reading_current': false},
        'link_count': {'source': 'name_reading', 'reading_current': true},
      }
    });
    expect(origins['chain_speeds']!.note, 'Del texto del proveedor');
    expect(origins['link_count']!.note, 'Leído del nombre del producto');
    expect(origins['drivetrain_mode']!.note,
        'Leído del nombre del producto; ya no calza con el nombre actual');
  });

  test('an older server sends no origins and nothing is invented', () {
    expect(ProductSpecValueOrigin.fromSnapshot({'values': {}}), isEmpty);
  });

  test('the origin describes the stored value only while it is still there',
      () {
    const origin = ProductSpecValueOrigin(source: 'supplier_text');
    expect(ProductSpecValueOrigin.noteFor(origin, ['6'], ['6']),
        'Del texto del proveedor');
    // The operator changed it: the supplier did not say 7.
    expect(ProductSpecValueOrigin.noteFor(origin, ['7'], ['6']), isNull);
    // Cleared: nothing to describe.
    expect(ProductSpecValueOrigin.noteFor(origin, null, ['6']), isNull);
    expect(ProductSpecValueOrigin.noteFor(null, ['6'], ['6']), isNull);
  });

  test('an option shows its display name and keeps its identity', () {
    // «Derailleur» is what rules, workshop code and name readings compare;
    // the operator reads «Con cambio trasero» (20261002100000).
    final definition = SpecDefinition.fromJson({
      'id': 'mode',
      'key': 'drivetrain_mode',
      'label': 'Tipo de transmisión',
      'data_type': 'single_select',
      'allowed_values': ['Derailleur', 'Desconocido / sin confirmar'],
      'validation_rules': {},
      'spec_definition_values': [
        {
          'id': 'v1',
          'label': 'Derailleur',
          'display_label': 'Con cambio trasero'
        },
        {
          'id': 'v2',
          'label': 'Desconocido / sin confirmar',
          'display_label': null
        },
      ],
    });
    expect(definition.optionDisplay('Derailleur'), 'Con cambio trasero');
    expect(definition.optionDisplay('Desconocido / sin confirmar'),
        'Desconocido / sin confirmar');
    expect(definition.optionIds['Derailleur'], 'v1');
    expect(definition.options, contains('Derailleur'));
  });
}
