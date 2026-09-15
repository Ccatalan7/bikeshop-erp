"""Final scope corrections for combined controls; no DB or product writes."""
from copy import deepcopy

from compile_mobility_accessories_catalog import case, rows
from compile_wheel_small_parts_catalog import column

FAMILY = 'brake_shift_combined_control'
UNITS = 'combined_control_units'
SHIFT = 'combined_control_shift_configurations'
COUNT = 'combined_control_declared_units'
BRAKE = 'combined_control_brake_configurations'
OLD_HYBRID = 'Híbrido (cable a hidráulico)'
CABLE_CONVERTER = 'Mecánico (cable) hacia conversor hidráulico externo'


def integrate_root(definitions, templates, fixtures):
    # Model/side/edition identify a type of object, not a physical occurrence.
    # Counting rows as units requires one row per occurrence even when two
    # pieces share all those properties. Do not invent a quantity sum operator.
    schema = definitions[UNITS]['validation_rules']['rows_schema']
    schema['columns'].insert(0, column(
        'member', 'Pieza física del conjunto', required=True))
    schema['unique_by'] = [['member']]
    template = templates[FAMILY]
    contract = template['form_contract']
    contract['helpers'][UNITS] = (
        'Identifica cada pieza física, por ejemplo A y B, aunque compartan '
        'modelo, lado y edición. Una fila representa una pieza; sus circuitos '
        'se enlazan a esa fila. La cantidad total declarada se compara con '
        'las piezas, no con el número de modelos distintos.')
    for link in contract['row_coherence']['links']:
        link['label_columns'] = ['member', 'unit', 'control_model']
    # TRP HY/RD's hydraulic reservoir belongs to the caliper. Describing the
    # system as hybrid must not give its cable lever a fluid circuit. This
    # template describes the control; the converter has its own component.
    brake_schema = definitions[BRAKE]['validation_rules']['rows_schema']
    actuation = next(c for c in brake_schema['columns'] if c['key'] == 'brake_actuation')
    actuation['label'] = 'Salida de freno de este mando'
    actuation['allowed_values'] = [CABLE_CONVERTER if v == OLD_HYBRID else v
                                  for v in actuation['allowed_values']]
    brake_conditions = contract['row_conditions']['fields'][BRAKE]
    for group in ('allowed_when', 'required_when'):
        for col, expression in brake_conditions[group].items():
            for clause in expression.get('rows', []):
                for predicate in clause:
                    value = predicate.get('value')
                    if predicate['field'] != 'brake_actuation' or not isinstance(value, list):
                        continue
                    if col == 'lever_cable_pull':
                        predicate['value'] = [CABLE_CONVERTER if v == OLD_HYBRID else v
                                              for v in value]
                    else:
                        predicate['value'] = [v for v in value if v != OLD_HYBRID]
    contract['helpers'][BRAKE] += (
        ' Si el cable termina en un conversor hidráulico externo, el mando '
        'sigue siendo de cable. El líquido y el conector hidráulico pertenecen '
        'al conversor o cáliper y se documentan en la ficha de esa pieza.')
    for fixture in fixtures['cases']:
        units = fixture['values'].get(UNITS, {}).get('rows', [])
        for index, unit in enumerate(units, 1):
            unit['values']['member'] = 'Pieza sintética ' + str(index)
        if fixture['id'] == 'cbc_same_unit_and_edition_twice_blocks':
            for unit in units:
                unit['values']['member'] = 'La misma pieza física'
            fixture['successor_translation'] = (
                'La duplicación prohibida es la misma pieza física. Lado, '
                'modelo y edición pueden repetirse en dos piezas distintas; '
                'se explicita la identidad de ocurrencia sin cambiar el '
                'bloqueo esperado ni convertir un modelo en cantidad.')
        for row in fixture['values'].get(BRAKE, {}).get('rows', []):
            if row['values'].get('brake_actuation') == OLD_HYBRID:
                row['values']['brake_actuation'] = CABLE_CONVERTER
        if fixture['id'] == 'cbc_hybrid_configuration_keeps_pull_and_fluid':
            fixture['expected_blocking'] = [
                {'code': 'row_field_applicability', 'field': BRAKE}]
            fixture['successor_translation'] = (
                'Se rechaza la premisa anterior: un sistema cable/hidráulico '
                'con conversor externo no traslada el líquido al mando. '
                'El ejemplo TRP HY/RD ubica la hidráulica en el cáliper; '
                'se conservan los valores sintéticos contradictorios para '
                'probar que ahora se rechazan.')
        multiplicities = {
            'cbc_cable_configuration_cannot_declare_a_fluid': 2,
            'cbc_shiftless_configuration_cannot_name_a_target': 4,
            'cbc_hybrid_configuration_keeps_pull_and_fluid': 6,
        }
        if fixture['id'] in multiplicities:
            fixture['expected_sql_blocking'] = (
                fixture['expected_blocking'] * multiplicities[fixture['id']])
    unit = {
        'member': 'A', 'unit': 'Derecho', 'control_model': 'Modelo sintético',
        'edition': 'Edición sintética', 'source_url': 'https://example.invalid/synthetic'}
    fixtures['cases'].append(case(
        'ccr_two_identical_controls_are_two_physical_occurrences', FAMILY,
        {COUNT: '2', UNITS: rows(unit, {**unit, 'member': 'B'})}))
    fixtures['cases'].append(case(
        'ccr_same_occurrence_cannot_be_two_models', FAMILY,
        {COUNT: '2', UNITS: rows(unit, {**unit, 'control_model': 'Otro modelo'})},
        blocking=[('row_shape', UNITS)]))
    fixtures['cases'].append(case(
        'ccr_cable_to_external_converter_keeps_only_control_properties', FAMILY,
        {UNITS: rows(unit), BRAKE: rows({
            'unit_row_id': 'r1', 'configuration': 'Montaje sintético',
            'brake_function': 'Con freno', 'brake_actuation': CABLE_CONVERTER,
            'lever_cable_pull': 'Tiro corto (ruta / cantilever / caliper)',
            'source_scope': 'Apartado sintético',
            'source_url': 'https://example.invalid/synthetic'})}))
    # Requiredness of status is already driven by shift_mode. A named target
    # without status needs no presence operator: isolate that one missing cell.
    missing = deepcopy(next(c for c in fixtures['cases']
                            if c['id'] == 'cbc_documented_exclusion_is_recordable'))
    missing['id'] = 'ccr_target_without_status_is_pending'
    missing['values'][SHIFT]['rows'][0]['values'].pop('status')
    missing['expected_issue_subset'] = [
        {'code': 'row_required_missing', 'field': SHIFT, 'blocking': False}]
    missing['expected_row_condition_issues'] = [{
        'code': 'row_required_missing', 'field': SHIFT,
        'row_id': 'r1', 'column': 'status', 'blocking': False}, {
        'code': 'row_prerequisite', 'field': SHIFT,
        'row_id': 'r1', 'column': 'conditions', 'blocking': False}]
    fixtures['cases'].append(missing)
    # Make the prerequisite order explicit without changing any shared control.
    active_order = [UNITS, COUNT, 'combined_control_brake_configurations',
                    SHIFT, 'spec_evidence_source']
    template['fields'].sort(key=lambda f: (
        active_order.index(f['key']) if f['key'] in active_order else 1000,
        f['sort_order']))
    for index, field in enumerate(template['fields']):
        field['sort_order'] = index * 10
