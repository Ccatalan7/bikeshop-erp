#!/usr/bin/env python3
"""Adjudicate physical ownership in the three unpublished service families."""
from copy import deepcopy
import hashlib
import json

from compile_existing_drivetrain_service_parts_catalog import (
    compile_catalog as proposal, _add, _claim_columns, _claim_conditions,
    EVIDENCE, DOCUMENTED_MODEL, DOCUMENTED_INTERFACE, ONEUP, ONEUP_FIT, SYNTHETIC)
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column
from compile_non_drivetrain_publication import RESEARCH, write_json
from compile_product_spec_catalog import validate_contract


def compile_catalog():
    catalog, fixtures = proposal()
    templates = {t['key']: t for t in catalog['templates']}
    definitions = catalog['definitions']
    pulley = templates['derailleur_pulley']
    c = pulley['form_contract']
    single = condition('pulley_package_kind', 'Roldana individual')
    pair = condition('pulley_package_kind', 'Par de roldanas en el mismo envase')
    # Claims for one occurrence must not become a Cartesian product shared by
    # both physical pulleys just because they occupy the same package.
    for key in ('pulley_declared_speeds', 'derailleur_cage_length',
                'compatible_derailleur_models'):
        c['allowed_when'][key] = deepcopy(single)
    key = 'pulley_unit_fitment_declarations'
    _add(definitions, pulley, key, 'Declaraciones por roldana del envase', 'json',
         role='declaration', semantic='declaration', allowed=pair,
         rules={'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
             'columns': [column('unit_reference', 'Roldana de esta declaración', required=True),
                 *_claim_columns('del cambio',
                     column('declared_speed', 'Velocidades de esta declaración', 'token',
                            options=definitions['pulley_declared_speeds']['allowed_values']),
                     column('cage_length_declaration', 'Jaula declarada', 'token',
                            options=definitions['derailleur_cage_length']['allowed_values']))]}},
         helper='Cada declaración pertenece a una roldana identificada. No '
         'extiende velocidades, modelos o jaulas a las otras piezas del envase.')
    c['row_conditions']['fields'][key] = _claim_conditions()
    c['row_coherence']['links'].append({'id': 'pulley_claim_owns_its_unit',
        'field': key, 'column': 'unit_reference', 'target_field': 'pulley_units',
        'label_columns': ['unit_identity']})
    for key in ('pulley_teeth', 'pulley_bearing_construction',
                'pulley_bearing_element_material', 'pulley_outer_diameter_mm',
                'pulley_width_mm', 'pulley_bore_diameter_mm'):
        c['prerequisites'][key] = [EVIDENCE]

    guide = templates['chain_guide']
    c = guide['form_contract']
    parts_key = 'chain_guide_included_parts'
    for col in definitions[parts_key]['validation_rules']['rows_schema']['columns']:
        if col['key'] == 'weight_g':
            col['label'] = 'Peso de esta pieza suelta'
    c['helpers'][parts_key] += (' El peso aquí corresponde a la pieza suelta; '
        'un peso del conjunto montado pertenece a su configuración completa.')
    c['helpers']['chainring_teeth_min'] = (
        'Capacidad publicada para esta variante y las configuraciones que '
        'documenta su fabricante. No se calcula uniendo rangos de piezas.')
    c['helpers']['chainring_teeth_max'] = c['helpers']['chainring_teeth_min']
    key = 'chain_guide_assembled_weights'
    _add(definitions, guide, key, 'Peso del conjunto por configuración', 'json',
         rules={'rows_schema': {'version': 1, 'unique_by': [['configuration_identity']],
             'columns': [
                 column('configuration_identity', 'Configuración del conjunto', required=True),
                 column('mounted_part_reference', 'Pieza montada de este envase', required=True),
                 column('weight_g', 'Peso del conjunto montado', 'decimal',
                        unit='g', positive=True, required=True),
                 column('source_document', 'Documento del peso y su alcance', required=True),
                 column('source_url', 'URL del documento, si existe', 'url')]}},
         helper='Peso publicado del conjunto completo con una pieza concreta '
         'montada. No es el peso de esa pieza ni del envase con sus repuestos.')
    c['row_coherence'] = {'version': 1, 'links': [{
        'id': 'assembled_weight_names_its_mounted_piece', 'field': key,
        'column': 'mounted_part_reference', 'target_field': parts_key,
        'label_columns': ['part_identity']}]}

    for fixture in fixtures['cases']:
        if fixture['id'] == 'cg_included_plates_keep_their_own_ranges':
            pieces = fixture['values'][parts_key]['rows']
            weights = []
            for piece in pieces:
                weight = piece['values'].pop('weight_g')
                weights.append({'configuration_identity': 'Conjunto con ' + piece['values']['part_identity'],
                    'mounted_part_reference': piece['id'], 'weight_g': weight,
                    'source_document': 'OneUp Bash Guide ISCG05 V2, peso por configuración',
                    'source_url': ONEUP})
            fixture['values']['chain_guide_assembled_weights'] = rows(*weights)
        if fixture['id'] == 'pu_two_identical_units_are_not_a_guide_and_a_tension':
            fixture['id'] = 'pu_equal_teeth_do_not_resolve_identity_or_position'
    fixtures['cases'] += root_cases()
    # SQL's existing draft validator uses these established aliases. Keep
    # the same owner, severity and verdict; only its transport names/order vary.
    for fixture in fixtures['cases']:
        if fixture['id'] == 'cg_the_same_mount_option_twice_blocks':
            fixture['expected_sql_blocking'] = [
                {'code': 'field_constraint', 'field': 'chain_guide_mount_options'}]
        if fixture['id'] == 'cg_an_inverted_declared_capacity_blocks':
            fixture['expected_sql_blocking'] = sorted(fixture['expected_blocking'],
                key=lambda issue: (issue['code'], issue['field']))
        if fixture['id'] in ('cg_a_chainline_without_its_datum_is_pending',
                              'pur_dimensions_need_their_document'):
            fixture['expected_sql_issue_subset'] = [
                {**issue, 'code': 'prerequisite_missing'}
                for issue in fixture['expected_sql_issue_subset']]
    for template in templates.values():
        validate_contract(template['key'], template['form_contract'], definitions,
                          {f['key'] for f in template['fields']})
    catalog['title'] = 'Service transmission parts: occurrence-scoped dimensions and claims'
    catalog['stats'].update(definitions=len(definitions),
        field_uses=sum(len(t['fields']) for t in templates.values()))
    catalog['root_adjudications'] = {
        'weights': 'OneUp assembly weights belong to mounted configurations, never loose plates.',
        'pulley_claims': 'Each packaged pulley owns its speed, cage and model declarations.',
        'identity': 'Equal tooth counts in a title do not prove identical pulleys or positions.',
        'capacity': 'A declared guide capacity is not computed as the union of loose-part ranges.',
    }
    return catalog, fixtures


def root_cases():
    units = rows({'unit_identity': 'A', 'teeth': '11', 'source_document': 'Synthetic'},
                 {'unit_identity': 'B', 'teeth': '11', 'source_document': 'Synthetic'})
    pair = {'pulley_package_kind': 'Par de roldanas en el mismo envase',
        'pulley_unit_count': '2', 'pulley_units': units, EVIDENCE: SYNTHETIC}
    claims_key = 'pulley_unit_fitment_declarations'
    def claim(unit_ref, identity, speed):
        return {'claim_identity': identity, 'unit_reference': unit_ref,
            'scope_kind': DOCUMENTED_INTERFACE, 'declared_interface': 'Synthetic interface',
            'declared_speed': speed, 'source_document': 'Synthetic'}
    claims = rows(claim(units['rows'][0]['id'], 'a', '11'),
                  claim(units['rows'][1]['id'], 'b', '12'))
    parts = rows({'part_identity': 'Plate A', 'part_role': 'Placa protectora',
        'installed_from_factory': True, 'source_document': 'Synthetic'})
    assembled_key = 'chain_guide_assembled_weights'
    weight = {'configuration_identity': 'Complete assembly A',
        'mounted_part_reference': parts['rows'][0]['id'], 'weight_g': '105',
        'source_document': 'Synthetic'}
    guide = {EVIDENCE: SYNTHETIC, 'chain_guide_included_parts': parts}
    def pu(name, values, **kwargs):
        return case('pur_' + name, 'derailleur_pulley', values, **kwargs)
    def cg(name, values, **kwargs):
        return case('cgr_' + name, 'chain_guide', values, **kwargs)
    return [
        pu('a_pair_does_not_share_scalar_speed_claims',
           {**pair, 'pulley_declared_speeds': ['11', '12']},
           blocking=[('field_applicability', 'pulley_declared_speeds')]),
        pu('a_pair_does_not_share_scalar_cage_claims',
           {**pair, 'derailleur_cage_length': 'GS / media'},
           blocking=[('field_applicability', 'derailleur_cage_length')]),
        pu('each_unit_owns_its_speed_declaration', {**pair, claims_key: claims}),
        pu('a_unit_claim_cannot_reference_a_foreign_piece', {**pair,
           claims_key: rows(claim('outside', 'a', '11'))},
           blocking=[('row_reference_unresolved', claims_key)]),
        pu('a_single_unit_cannot_use_package_claims', {
           'pulley_package_kind': 'Roldana individual', claims_key: claims},
           blocking=[('field_applicability', claims_key)]),
        pu('dimensions_need_their_document', {'pulley_package_kind': 'Roldana individual',
            'pulley_outer_diameter_mm': '32.4'},
           pending=[('prerequisite', 'pulley_outer_diameter_mm')]),
        cg('assembly_weight_keeps_its_component_reference',
           {**guide, assembled_key: rows(weight)}),
        cg('an_assembly_cannot_name_a_piece_outside_this_package',
           {**guide, assembled_key: rows({**weight, 'mounted_part_reference': 'outside'})},
           blocking=[('row_reference_unresolved', assembled_key)]),
        cg('a_loose_piece_can_have_its_own_documented_weight', {EVIDENCE: SYNTHETIC,
           'chain_guide_included_parts': rows({**parts['rows'][0]['values'], 'weight_g': '21'})}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-drivetrain-service-parts-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-drivetrain-service-parts-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']), 'production_writes': False}))
