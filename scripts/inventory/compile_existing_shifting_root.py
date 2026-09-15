#!/usr/bin/env python3
"""Adjudicate shifter occurrence ownership and documented derailleur setups.

Preserves Claude's proposal as an input. No product, DB or runtime writes.
The tables describe evidence; matching a bicycle still requires a directed
model-scoped relation, not a successful shape/range validation.
"""
from copy import deepcopy
import hashlib
import json

from compile_existing_shifting_catalog import (
    compile_catalog as proposal, _add, _claim_columns, _claim_conditions,
    _retire, EVIDENCE, SYNTHETIC, LEFT, RIGHT, INDEXED, FRICTION,
    DOCUMENTED_INTERFACE)
from compile_mobility_accessories_catalog import (
    case, condition, rows, remove_unpublished_field)
from compile_wheel_small_parts_catalog import column, ALWAYS
from compile_non_drivetrain_publication import RESEARCH, write_json
from compile_product_spec_catalog import validate_contract

HANDBOOK = 'https://productinfo.shimano.com/pdfs/product/archive/2024-2025_Specifications_v032_en.pdf'
RD_U6000 = 'https://bike.shimano.com/en-NA/products/components/pdp.P-RD-U6000.html'
FD_PARTS = 'https://dassets.shimano.com/content/dam/global/cg1SHICCycling/final/ev/ev/EV-FD-R2000-4160.pdf'
SH_CLAIMS = 'shifter_unit_compatibility_claims'
RD_SETUPS = 'rear_derailleur_application_configurations'
FD_SETUPS = 'front_derailleur_application_configurations'
CLAMPS = 'front_derailleur_clamp_options'
DIRECT, REDUCED = 'Abrazadera directa', 'Abrazadera con casquillo reductor'
COMPATIBLE, EXCLUDED, CONDITIONAL = 'Compatible declarado', 'No compatible declarado', 'Condicional declarado'


def documented_columns():
    return [column('source_document', 'Documento de esta configuración', required=True),
            column('source_url', 'URL del documento, si existe', 'url'),
            column('conditions', 'Condiciones y límites documentados')]


def tooth(key, label, required=False, zero=False):
    col = column(key, label, 'integer', unit='T', positive=not zero, required=required)
    if zero:
        col['validation'] = {'min': '0'}
    return col


def configuration_columns():
    return [column('configuration_identity', 'Configuración identificada', required=True),
            column('front_chainring_count', 'Cantidad de platos de esta configuración',
                   'integer', positive=True, required=True),
            column('rear_sprocket_count', 'Velocidades traseras de esta configuración',
                   'integer', positive=True, required=True),
            column('chain_declaration', 'Cadena o clase de cadena documentada')]


def compile_catalog():
    catalog, fixtures = proposal()
    # Proposal helpers share some synthetic dictionaries between cases.
    # Each case owns its target scope when we complete the new columns.
    fixtures['cases'] = [deepcopy(f) for f in fixtures['cases']]
    templates = {t['key']: t for t in catalog['templates']}
    definitions = catalog['definitions']
    # Global ecosystem/actuation selectors recreate the original Cartesian
    # product problem. Preserve their observations, use the scoped claims.
    for t in templates.values():
        _retire(t, ['shift_actuation_family',
                    'drivetrain_declared_compatible_ecosystems', 'drivetrain_platform'])
    shifter(definitions, templates['shifter'])
    rear(definitions, templates['rear_derailleur'])
    front(definitions, templates['front_derailleur'])
    for t in templates.values():
        for field in t['fields']:
            if field['key'].endswith('compatibility_claims'):
                scope_claims(definitions, t, field['key'])

    adapt_proposal_cases(fixtures)
    fixtures['cases'] += root_cases()
    # Exact aliases measured against the existing SQL validator; preserve
    # owner and blocking verdict rather than treating differing names as parity.
    for fixture in fixtures['cases']:
        if fixture['id'] == 'rd_a_declared_ratio_without_evidence_is_pending':
            fixture['expected_sql_issue_subset'] = [{**i, 'code': 'prerequisite_missing'}
                for i in fixture['expected_issue_subset']]
        if fixture['id'] in ('shr_a_pair_cannot_declare_three_units',
                              'rdr_a_speed_array_cannot_merge_two_configurations',
                              'rdr_an_inverted_large_cog_range_blocks', 'rdr_a_fractional_tooth_blocks'):
            fixture['expected_sql_blocking'] = [{**i, 'code': 'field_constraint'}
                for i in fixture['expected_blocking']]
    fixtures['pending_cases'] = [p for p in fixtures['pending_cases']
        if p['id'] != 'oem_manuals_were_not_reachable_in_this_round']
    fixtures['pending_cases'].append({
        'id': 'documented_configurations_require_model_and_source_adjudication',
        'required_result': 'unknown_without_exact_reference',
        'reason': 'Range and ownership validation does not authenticate a document, '
                  'resolve a product identity or approve a complete assembly.'})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    for key in set(definitions) - owned:
        if definitions[key]['origin'] != 'new':
            raise ValueError('Published definition would be discarded: ' + key)
        del definitions[key]
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog['title'] = 'Shifting: occurrence-scoped controls and documented complete configurations'
    catalog['stats'].update(definitions=len(definitions),
        field_uses=sum(len(t['fields']) for t in templates.values()))
    catalog['source_urls'] += [HANDBOOK, RD_U6000, FD_PARTS]
    catalog['root_adjudications'] = {
        'pair': 'Each shifter owns its claims; a package cannot inherit them for both units.',
        'return': 'Rapid Rise reverses spring return; that alone is not an incompatibility rule.',
        'capacity': 'Front count, rear speeds and sprocket limits stay in one configuration.',
        'front': 'Top-gear minimum is the lower bound for the LARGE ring, not the small ring.',
        'clamp': 'Direct contact and reduction are distinct; reduction decreases nominal diameter.',
        'contents': 'A compatible/required adapter is not evidence that it is supplied.',
        'legacy': 'Published global selectors are retained as legacy, never reinterpreted.'}
    return catalog, fixtures


def shifter(definitions, t):
    c = t['form_contract']
    single = condition('shifter_position', [LEFT, RIGHT, 'Universal'])
    pair = condition('shifter_position', 'Par')
    c['allowed_when']['shifter_compatibility_claims'] = single
    definitions['shifter_unit_count']['validation_rules'] = {'integer': True, 'min': '2', 'max': '2'}
    c['helpers']['shifter_unit_count'] = 'Un par contiene exactamente dos mandos; cada uno conserva su identidad y su lado.'
    _add(definitions, t, SH_CLAIMS, 'Declaraciones por mando del par', 'json',
         role='declaration', semantic='declaration', allowed=pair,
         rules={'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
             'columns': [column('unit_reference', 'Mando de esta declaración', required=True),
                         *_claim_columns('del componente accionado')]}},
         helper='Cada declaración pertenece al mando indicado. No se transmite al otro mando del par.')
    c['row_conditions']['fields'][SH_CLAIMS] = _claim_conditions()
    c['row_coherence']['links'].append({'id': 'claim_owns_its_shifter',
        'field': SH_CLAIMS, 'column': 'unit_reference', 'target_field': 'shifter_units',
        'label_columns': ['unit_identity', 'unit_side']})
    c['prerequisites'][SH_CLAIMS] = [EVIDENCE]


def scope_claims(definitions, t, key):
    columns = definitions[key]['validation_rules']['rows_schema']['columns']
    targets = {
        'shifter': ['Cambio trasero', 'Desviador delantero', 'Buje con cambios internos', 'Interfaz de mando'],
        'rear_derailleur': ['Mando', 'Cassette o piñonería', 'Cadena', 'Interfaz de mando'],
        'front_derailleur': ['Mando', 'Conjunto de bielas y platos', 'Cadena', 'Interfaz de mando']}
    columns += [column('target_component', 'Componente al que se refiere', 'token',
                       options=targets[t['key']], required=True),
                column('declaration_result', 'Resultado que declara la fuente', 'token',
                       options=[COMPATIBLE, EXCLUDED, CONDITIONAL], required=True)]
    t['form_contract']['row_conditions']['fields'][key]['required_when']['conditions'] = condition(
        'declaration_result', CONDITIONAL)


def rear(definitions, t):
    c = t['form_contract']
    c['helpers']['rear_derailleur_spring_return'] = (
        'Hacia dónde vuelve el cambio cuando se suelta el cable. El retorno inverso '
        'cambia el sentido de actuación; no prueba por sí solo incompatibilidad con un mando.')
    remove_unpublished_field(t, 'compatible_rear_speeds')
    _retire(t, ['rear_derailleur_min_teeth', 'rear_derailleur_max_teeth',
                'rear_derailleur_total_capacity_teeth'])
    c.pop('scalar_ordered_pairs', None)
    _add(definitions, t, RD_SETUPS, 'Configuraciones de transmisión documentadas', 'json',
         role='declaration', semantic='compatibility', required=ALWAYS,
         rules={'rows_schema': {'version': 1, 'unique_by': [['configuration_identity']],
             'ordered_pairs': [['smallest_sprocket_min_teeth', 'smallest_sprocket_max_teeth'],
                               ['largest_sprocket_min_teeth', 'largest_sprocket_max_teeth'],
                               ['smallest_sprocket_max_teeth', 'largest_sprocket_min_teeth']],
             'columns': [*configuration_columns(),
                 tooth('smallest_sprocket_min_teeth', 'Piñón pequeño: mínimo admitido'),
                 tooth('smallest_sprocket_max_teeth', 'Piñón pequeño: máximo admitido'),
                 tooth('largest_sprocket_min_teeth', 'Piñón grande: mínimo admitido'),
                 tooth('largest_sprocket_max_teeth', 'Piñón grande: máximo admitido'),
                 tooth('total_capacity_teeth', 'Capacidad total documentada'),
                 tooth('max_front_difference_teeth', 'Diferencia máxima entre platos', zero=True),
                 *documented_columns()]}},
         helper='Una configuración por fila. Velocidades y límites permanecen juntos; '
                'no se unen los límites de configuraciones distintas ni se calcula compatibilidad por marca.')
    c['prerequisites'][RD_SETUPS] = [EVIDENCE]


def front(definitions, t):
    c = t['form_contract']
    for key in ('compatible_rear_speeds', 'compatible_chainring_counts',
                'front_derailleur_min_chainring_teeth'):
        remove_unpublished_field(t, key)
    _retire(t, ['max_chainring_teeth'])
    c.pop('scalar_ordered_pairs', None)
    _add(definitions, t, FD_SETUPS, 'Configuraciones de platos documentadas', 'json',
         role='declaration', semantic='compatibility', required=ALWAYS,
         rules={'rows_schema': {'version': 1, 'unique_by': [['configuration_identity']],
             'ordered_pairs': [['top_chainring_min_teeth', 'top_chainring_max_teeth'],
                               ['chainstay_angle_min_deg', 'chainstay_angle_max_deg']],
             'columns': [*configuration_columns(),
                 tooth('top_chainring_min_teeth', 'Plato grande: mínimo admitido'),
                 tooth('top_chainring_max_teeth', 'Plato grande: máximo admitido'),
                 tooth('total_capacity_teeth', 'Diferencia total de dientes admitida'),
                 tooth('top_middle_difference_teeth', 'Diferencia plato grande–medio documentada'),
                 column('chainline_mm', 'Línea de cadena nominal de esta configuración',
                        'decimal', unit='mm', positive=True),
                 column('chainline_datum', 'Referencia geométrica de esa línea de cadena'),
                 column('chainstay_angle_min_deg', 'Ángulo de vaina mínimo', 'decimal', unit='deg', positive=True),
                 column('chainstay_angle_max_deg', 'Ángulo de vaina máximo', 'decimal', unit='deg', positive=True),
                 *documented_columns()]}},
         helper='El mínimo y máximo de plato grande son dos límites del plato exterior. '
                'No son los dientes del plato pequeño y grande montados. Mantén cantidad de '
                'platos, velocidades, capacidad y geometría en su configuración documentada.')
    c['prerequisites'][FD_SETUPS] = [EVIDENCE]
    c['row_conditions']['fields'][FD_SETUPS] = {
        'allowed_when': {'top_middle_difference_teeth': condition('front_chainring_count', '3', 'decimal')},
        'required_when': {'chainline_datum': {'kind': 'when', 'rows': [[{
            'field': 'chainline_mm', 'operator': 'gt', 'value_type': 'decimal', 'value': '0'}]]}}}
    # Separate columns prevent a direct clamp inheriting reducer measurements.
    # The strict pair compares two nominal interfaces of the SAME reducer.
    definitions[CLAMPS]['label'] = 'Montajes de abrazadera documentados'
    definitions[CLAMPS]['validation_rules'] = {'rows_schema': {
        'version': 2, 'unique_by': [['option_identity']],
        'strict_ordered_pairs': [['reduced_tube_diameter_mm', 'unreduced_clamp_diameter_mm']],
        'columns': [column('option_identity', 'Configuración de abrazadera', required=True),
            column('attachment_method', 'Montaje de esta opción', 'token', required=True,
                   options=[DIRECT, REDUCED]),
            column('direct_tube_diameter_mm', 'Tubo nominal que abraza directamente',
                   'decimal', unit='mm', positive=True),
            column('reduced_tube_diameter_mm', 'Tubo nominal que recibe el reductor',
                   'decimal', unit='mm', positive=True),
            column('unreduced_clamp_diameter_mm', 'Abrazadera nominal que recibe el reductor',
                   'decimal', unit='mm', positive=True),
            column('adapter_reference', 'Referencia del casquillo requerido'),
            column('adapter_included', 'El envase incluye este casquillo', 'boolean'),
            *documented_columns()]}}
    direct, reduced = condition('attachment_method', DIRECT), condition('attachment_method', REDUCED)
    conditional = {'direct_tube_diameter_mm': direct,
                   'reduced_tube_diameter_mm': reduced, 'unreduced_clamp_diameter_mm': reduced,
                   'adapter_reference': reduced}
    c['row_conditions']['fields'][CLAMPS] = {
        'allowed_when': {**deepcopy(conditional), 'adapter_included': reduced},
        'required_when': deepcopy(conditional)}
    c['helpers'][CLAMPS] = (
        'Distingue contacto directo y reducción. El casquillo recibe un tubo menor '
        'que la abrazadera. Sus medidas son designaciones nominales de montaje, '
        'no cotas mecanizadas. Que un manual admita el casquillo no prueba que venga incluido.')


def clamp_rows(*values):
    return {**rows(*values), 'schema_version': 2}


def fd_clamps():
    source = {'source_document': 'Shimano FD-R2000-B, handbook p. 140 y EV-FD-R2000-4160',
              'source_url': HANDBOOK}
    return clamp_rows(
        {'option_identity': '34.9 directa', 'attachment_method': DIRECT,
         'direct_tube_diameter_mm': '34.9', **source},
        {'option_identity': '31.8 con M', 'attachment_method': REDUCED,
         'reduced_tube_diameter_mm': '31.8', 'unreduced_clamp_diameter_mm': '34.9',
         'adapter_reference': 'Y2B198020 / M', **source})


def adapt_proposal_cases(fixtures):
    replaced = {'rd_an_inverted_teeth_range_blocks', 'rd_the_largest_cog_must_be_a_whole_tooth_count',
                'fd_an_inverted_chainring_range_blocks', 'sh_the_platform_declaration_needs_its_evidence'}
    fixtures['cases'] = [f for f in fixtures['cases'] if f['id'] not in replaced]
    for f in fixtures['cases']:
        v = f['values']
        for key, value in v.items():
            if key.endswith('compatibility_claims') and isinstance(value, dict):
                target = {'shifter': 'Cambio trasero', 'rear_derailleur': 'Mando',
                          'front_derailleur': 'Conjunto de bielas y platos'}[f['template']]
                for row in value['rows']:
                    row['values'].setdefault('target_component', target)
                    row['values'].setdefault('declaration_result', COMPATIBLE)
        v.pop('compatible_rear_speeds', None)
        v.pop('compatible_chainring_counts', None)
        if CLAMPS in v:
            v[CLAMPS] = fd_clamps()
        if f['id'] == 'fd_the_same_clamp_diameter_twice_blocks':
            f['id'] = 'fd_the_same_clamp_configuration_identity_twice_blocks'
            v[CLAMPS]['rows'][1]['values']['option_identity'] = '34.9 directa'
        if f['id'] == 'fd_a_clamp_option_without_its_adapter_state_is_pending':
            f['id'] = 'fd_a_clamp_option_without_its_attachment_method_is_pending'
            v[CLAMPS] = clamp_rows({'option_identity': 'Unknown mounting', 'source_document': 'Synthetic'})
        if f['id'] == 'rd_a_rear_derailleur_without_its_mount_is_pending':
            for bucket in ('expected_issue_subset', 'expected_sql_issue_subset'):
                f[bucket] = [issue for issue in f.get(bucket, []) if issue['field'] != 'compatible_rear_speeds']


def root_cases():
    units = rows({'unit_identity': 'Left', 'unit_side': LEFT, 'actuation_mode': FRICTION,
                  'source_document': 'Synthetic'},
                 {'unit_identity': 'Right', 'unit_side': RIGHT, 'actuation_mode': INDEXED,
                  'indexed_positions': '8', 'source_document': 'Synthetic'})
    pair = {'shifter_position': 'Par', 'shifter_unit_count': '2', 'shifter_units': units, EVIDENCE: SYNTHETIC}
    claim = {'claim_identity': 'First', 'scope_kind': DOCUMENTED_INTERFACE,
             'declared_interface': 'Synthetic interface', 'source_document': 'Synthetic',
             'target_component': 'Cambio trasero', 'declaration_result': COMPATIBLE}
    rd = {EVIDENCE: RD_U6000, 'rear_derailleur_mount_type': 'Pata/postiza estándar'}
    configs = rows(*[{'configuration_identity': 'RD-U6000 1x' + n,
        'front_chainring_count': '1', 'rear_sprocket_count': n,
        'largest_sprocket_max_teeth': teeth, 'total_capacity_teeth': '39',
        'max_front_difference_teeth': '0', 'source_document': 'Shimano RD-U6000 official product page',
        'conditions': 'Una misma declaración OEM 11/10, separada según sus máximos por velocidad. '
                      'La tabla conjunta declara mínimo 48T y máximo 50T; no desglosa el mínimo por velocidad.',
        'source_url': RD_U6000} for n, teeth in [('10', '48'), ('11', '50')]])
    fd = {EVIDENCE: HANDBOOK, 'front_derailleur_mount_type': 'Abrazadera', CLAMPS: fd_clamps()}
    front_config = {'configuration_identity': 'FD-R2000-B 2x8', 'front_chainring_count': '2',
        'rear_sprocket_count': '8', 'top_chainring_min_teeth': '46', 'top_chainring_max_teeth': '52',
        'total_capacity_teeth': '16', 'chainstay_angle_min_deg': '61', 'chainstay_angle_max_deg': '66',
        'chain_declaration': 'HG 8/7/6-speed', 'chainline_mm': '43.5',
        'source_document': 'Shimano handbook v3.2 2024-2025 p. 140', 'source_url': HANDBOOK}
    def sh(name, values, **kwargs): return case('shr_' + name, 'shifter', values, **kwargs)
    def rear_case(name, values, **kwargs): return case('rdr_' + name, 'rear_derailleur', values, **kwargs)
    def front_case(name, values, **kwargs): return case('fdr_' + name, 'front_derailleur', values, **kwargs)
    reducer = fd_clamps()['rows'][1]['values']
    return [
        sh('a_pair_cannot_share_one_model_claim', {**pair, 'shifter_compatibility_claims': rows(claim)},
           blocking=[('field_applicability', 'shifter_compatibility_claims')]),
        sh('each_claim_owns_its_unit', {**pair, SH_CLAIMS: rows(
            {**claim, 'unit_reference': 'r1', 'target_component': 'Desviador delantero'},
            {**claim, 'claim_identity': 'Second', 'unit_reference': 'r2'})}),
        sh('a_claim_cannot_name_a_unit_outside_the_package',
           {**pair, SH_CLAIMS: rows({**claim, 'unit_reference': 'foreign'})},
           blocking=[('row_reference_unresolved', SH_CLAIMS)]),
        sh('a_single_cannot_use_pair_claims', {'shifter_position': RIGHT,
            SH_CLAIMS: rows({**claim, 'unit_reference': 'r1'})},
           blocking=[('field_applicability', SH_CLAIMS)]),
        sh('a_pair_cannot_declare_three_units', {**pair, 'shifter_unit_count': '3'},
           blocking=[('range', 'shifter_unit_count')]),
        sh('a_conditional_claim_without_conditions_is_pending', {**pair,
           SH_CLAIMS: rows({**claim, 'unit_reference': 'r1', 'declaration_result': CONDITIONAL})},
           pending=[('row_required_missing', SH_CLAIMS)]),
        rear_case('u6000_limits_stay_with_their_speed_count', {**rd, RD_SETUPS: configs}, sources=[RD_U6000]),
        rear_case('a_speed_array_cannot_merge_two_configurations', {**rd, RD_SETUPS: rows(
            {**configs['rows'][0]['values'], 'rear_sprocket_count': ['10', '11']})},
            blocking=[('row_shape', RD_SETUPS)]),
        rear_case('an_inverted_large_cog_range_blocks', {**rd, RD_SETUPS: rows(
            {**configs['rows'][0]['values'], 'largest_sprocket_min_teeth': '50'})},
            blocking=[('row_shape', RD_SETUPS)]),
        rear_case('a_fractional_tooth_blocks', {**rd, RD_SETUPS: rows(
            {**configs['rows'][0]['values'], 'largest_sprocket_max_teeth': '48.5'})},
            blocking=[('row_shape', RD_SETUPS)]),
        rear_case('a_configuration_needs_its_document', {**rd, RD_SETUPS: rows(
            {k: v for k, v in configs['rows'][0]['values'].items() if k != 'source_document'})},
            pending=[('row_incomplete', RD_SETUPS)]),
        front_case('top_gear_bounds_belong_to_the_large_ring', {**fd, FD_SETUPS: rows(front_config)},
                   pending=[('row_required_missing', FD_SETUPS)], sources=[HANDBOOK]),
        front_case('inverted_large_ring_bounds_block', {**fd, FD_SETUPS: rows(
            {**front_config, 'top_chainring_min_teeth': '53'})}, blocking=[('row_shape', FD_SETUPS)]),
        front_case('a_double_has_no_middle_ring_difference', {**fd, FD_SETUPS: rows(
            {**front_config, 'top_middle_difference_teeth': '11'})},
            blocking=[('row_field_applicability', FD_SETUPS)]),
        front_case('chainline_needs_its_geometric_datum', {**fd, FD_SETUPS: rows(
            {**front_config, 'chainline_mm': '43.5'})}, pending=[('row_required_missing', FD_SETUPS)]),
        front_case('a_reducer_cannot_enlarge_the_clamp', {**fd, CLAMPS: clamp_rows(
            {**reducer, 'reduced_tube_diameter_mm': '36'})}, blocking=[('row_shape', CLAMPS)]),
        front_case('a_reducer_cannot_have_equal_nominal_interfaces', {**fd, CLAMPS: clamp_rows(
            {**reducer, 'reduced_tube_diameter_mm': '34.9'})}, blocking=[('row_shape', CLAMPS)]),
        front_case('direct_contact_cannot_claim_an_included_reducer', {**fd, CLAMPS: clamp_rows(
            {**fd_clamps()['rows'][0]['values'], 'adapter_included': True})},
            blocking=[('row_field_applicability', CLAMPS)]),
        front_case('adapter_inclusion_can_remain_unknown', fd, sources=[HANDBOOK, FD_PARTS]),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-shifting-adjudicated-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-shifting-adjudicated-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']), 'production_writes': False}))
