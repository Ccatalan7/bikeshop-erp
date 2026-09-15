#!/usr/bin/env python3
"""Prepare the original headset family by physical end; never publish or fill."""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, new_definition, case, condition, rows as v1_rows)
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column, retire
from compile_product_spec_catalog import validate_contract

PREIMAGE = RESEARCH / 'existing-headset-preimage-2026-09-08.json'
PREIMAGE_SHA = '52fe18575bedfc30afa71b99c026c66fc622355e660fe6760a79b50babc232f5'
FAMILY = 'headset'
SCOPE = 'headset_part_scope'
EVIDENCE = 'spec_evidence_source'
UNKNOWN = 'Desconocido / sin confirmar'
PARK = 'https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system'
SHELDON = 'https://www.sheldonbrown.com/headsets.html'
CANE = 'https://www.canecreek.com/products/fifty'
SYNTHETIC = 'https://example.invalid/synthetic'
ENDS = [('upper', 'Superior'), ('lower', 'Inferior')]


def rows(*values):
    result = v1_rows(*values)
    result['schema_version'] = 2
    return result


def compile_catalog():
    for path, expected in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                           (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Pinned input changed: ' + path.name)
    base = json.loads(CATALOG.read_text())
    before = json.loads(PREIMAGE.read_text())
    actual_template = before['templates'][0]
    template = deepcopy(next(t for t in base['templates'] if t['key'] == FAMILY))
    template['name'] = actual_template['name']
    definitions = {f['key']: deepcopy(base['definitions'][f['key']])
                   for f in template['fields']}
    for actual in before['existing_definitions']:
        key = actual['key']
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values', 'validation_rules')}
        definitions[key].update(origin='existing', used_by=[FAMILY])
    live_ids = {f['spec_definition_id'] for f in before['fields']}
    original_schema = deepcopy(definitions['headset_bearing_configurations'][
        'validation_rules']['rows_schema'])
    original_conditions = deepcopy(template['form_contract']['row_conditions'][
        'fields']['headset_bearing_configurations'])

    def drop_unused(key):
        if definitions[key]['id'] in live_ids:
            raise ValueError('Never remove a published field observation: ' + key)
        template['fields'] = [f for f in template['fields'] if f['key'] != key]
        for section in ('roles', 'semantic_roles', 'labels', 'allowed_when',
                        'required_when', 'allowed_options', 'prerequisites',
                        'helpers', 'evidence_requirements'):
            template['form_contract'].get(section, {}).pop(key, None)
        del definitions[key]

    # SHIS upper/lower already carry the declared interface. A second global
    # threaded/standard/steerer selector can contradict those declarations and
    # erase mixed upper/lower designs. Existing readings stay legacy.
    retire(template, ['headset_standard', 'steerer_type', 'bearing_system'])
    c = template['form_contract']
    for key in ('headset_standard', 'steerer_type', 'bearing_system'):
        c['semantic_roles'][key] = 'legacy'
    for key in ('headset_bearing_configurations', 'threaded', 'stack_height_mm'):
        drop_unused(key)
    c.pop('row_conditions', None)
    definitions[SCOPE]['allowed_values'] += [UNKNOWN]
    c['required_when'][EVIDENCE] = deepcopy(ALWAYS)
    c['helpers'][SCOPE] = ('Extremos de dirección que contiene esta variante. '
        'Los códigos y rodamientos superiores e inferiores conservan su dueño.')

    for end, label in ENDS:
        applies = condition(SCOPE, [label, 'Completa'])
        shis = 'headset_' + end + '_shis'
        c['prerequisites'][shis] = [EVIDENCE]
        c['helpers'][shis] = (
            'Código SHIS publicado para este extremo. Sus números son códigos '
            'nominales, no dimensiones medidas ni una tolerancia universal. '
            'No se infiere el código desde una medida aislada del nombre.')
        key = 'headset_' + end + '_bearing_configuration'
        schema = deepcopy(original_schema)
        schema['version'] = 2
        schema['strict_ordered_pairs'] = [
            ['bearing_inner_diameter_mm', 'bearing_outer_diameter_mm']]
        # A bearing's shape does not independently choose EC/ZS/IS; that is
        # the declared headset/frame interface, already owned by this end's SHIS.
        schema['columns'] = [col for col in schema['columns'] if col['key'] != 'seat_type']
        for col in schema['columns']:
            if col['key'] == 'position':
                col['allowed_values'] = [label]
            if col['key'] == 'source_url':
                col.pop('required', None)
        schema['columns'] += [
            column('ball_count', 'Bolas de este conjunto', 'integer', positive=True),
            column('ball_diameter_mm', 'Diámetro de bola', 'decimal', unit='mm', positive=True),
            column('source_document', 'Documento, envase o referencia del conjunto', required=True),
        ]
        definitions[key] = new_definition(key, 'Rodamiento ' + label.lower(),
            'json', [FAMILY], rules={'rows_schema': schema})
        add_field(template, key, 'measurement', 'compatibility',
                  allowed=applies, required=applies,
                  helper='Datos del conjunto de este extremo; no son una lista '
                  'de otros modelos posibles. La falta de fuente queda pendiente.')
        conditions = deepcopy(original_conditions)
        cartridge_or_cage = condition('construction', ['Cartucho', 'Canastillo con bolas'])
        balls = condition('construction', ['Bolas sueltas', 'Canastillo con bolas'])
        for dimension in ('bearing_inner_diameter_mm', 'bearing_outer_diameter_mm', 'bearing_height_mm'):
            conditions.setdefault('allowed_when', {})[dimension] = deepcopy(cartridge_or_cage)
        for dimension in ('ball_count', 'ball_diameter_mm'):
            conditions.setdefault('allowed_when', {})[dimension] = deepcopy(balls)
            conditions.setdefault('required_when', {})[dimension] = deepcopy(balls)
        conditions.setdefault('required_when', {})['seat_geometry'] = condition('construction', 'Cartucho')
        c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][key] = conditions
        stack = 'headset_' + end + '_stack_height_mm'
        definitions[stack] = new_definition(stack, 'Altura instalada ' + label.lower(),
            'number', [FAMILY], unit='mm', rules={'min': '0'})
        add_field(template, stack, 'measurement', 'compatibility', allowed=applies,
            helper='Altura instalada de este extremo, según el datum OEM. '
            'No sumar piezas sueltas ni copiar la altura total del juego.')
        c['prerequisites'][stack] = [EVIDENCE]

    # Included crown race is contents, not a declaration about the fork. A
    # complete headset may omit a separate race; a source must identify it.
    c['required_when']['crown_race_included'] = deepcopy(ALWAYS)
    race = 'headset_supplied_crown_race_reference'
    definitions[race] = new_definition(race, 'Pista de corona incluida', 'text', [FAMILY])
    included = condition('crown_race_included', True, 'boolean')
    add_field(template, race, 'contents', 'contents', allowed=included, required=included,
        helper='Identidad declarada de la pieza incluida. El asiento de la '
        'horquilla es otra propiedad; no se rellena a partir de esta referencia.')
    c['prerequisites'][race] = [EVIDENCE]

    keys = {f['key'] for f in template['fields']}
    if set(definitions) != keys or not live_ids <= {d['id'] for d in definitions.values()}:
        raise ValueError('Published observations or field ownership lost')
    validate_contract(FAMILY, c, definitions, keys)
    catalog = {**base, 'title': 'Headset original: separately owned upper and lower ends',
        'templates': [template], 'definitions': definitions,
        'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA, 'preimage': PREIMAGE_SHA},
        'automatic_fill_authorized': False, 'mechanical_coverage_complete': False,
        'source_urls': [PARK, SHELDON, CANE],
        'stats': {'templates': 1, 'definitions': len(definitions), 'field_uses': len(template['fields'])}}
    return catalog, {'cases': fixtures(), 'pending_cases': [
        {'id': 'headset_shis_source_and_model_scope',
         'required_result': 'Model-scoped source required before a fitment verdict.',
         'reason': 'SHIS names are codes, not measured bore/race dimensions. Do not infer from a product-title number.'},
    ]}


def fixtures():
    upper = 'headset_upper_bearing_configuration'
    lower = 'headset_lower_bearing_configuration'
    race = 'headset_supplied_crown_race_reference'
    def bearing(position='Superior', construction='Cartucho', **extra):
        return {'position': position, 'construction': construction,
                'source_document': 'Synthetic document', **extra}
    def sample(name, values, **kwargs):
        return case('hs_' + name, FAMILY, values, **kwargs)
    return [
        sample('mixed_ends_preserve_two_shis_codes', {SCOPE: 'Completa',
            'headset_upper_shis': 'ZS44/28.6', 'headset_lower_shis': 'EC44/40',
            EVIDENCE: CANE}, sources=[PARK, CANE]),
        sample('upper_only_cannot_claim_lower_code', {SCOPE: 'Superior',
            'headset_lower_shis': 'EC44/40', EVIDENCE: SYNTHETIC},
            blocking=[('field_applicability', 'headset_lower_shis')]),
        sample('lower_only_cannot_claim_upper_bearing', {SCOPE: 'Inferior',
            upper: rows(bearing())}, blocking=[('field_applicability', upper)]),
        sample('upper_only_cannot_claim_lower_bearing', {SCOPE: 'Superior',
            lower: rows(bearing('Inferior'))}, blocking=[('field_applicability', lower)]),
        sample('upper_table_rejects_lower_position', {SCOPE: 'Superior',
            upper: rows(bearing('Inferior'))}, blocking=[('row_shape', upper)]),
        sample('lower_table_rejects_upper_position', {SCOPE: 'Inferior',
            lower: rows(bearing())}, blocking=[('row_shape', lower)]),
        sample('duplicate_upper_position_blocks', {SCOPE: 'Superior',
            upper: rows(bearing(), bearing())}, blocking=[('row_shape', upper)]),
        sample('upper_body_inner_cannot_exceed_outer', {SCOPE: 'Superior',
            upper: rows(bearing(bearing_inner_diameter_mm='41',
                                bearing_outer_diameter_mm='30'))},
            blocking=[('row_shape', upper)]),
        sample('lower_body_inner_cannot_exceed_outer', {SCOPE: 'Inferior',
            lower: rows(bearing('Inferior', bearing_inner_diameter_mm='52',
                                bearing_outer_diameter_mm='40'))},
            blocking=[('row_shape', lower)]),
        sample('upper_body_requires_positive_wall_thickness', {SCOPE: 'Superior',
            upper: rows(bearing(bearing_inner_diameter_mm='41',
                                bearing_outer_diameter_mm='41.00'))},
            blocking=[('row_shape', upper)]),
        sample('lower_body_requires_positive_wall_thickness', {SCOPE: 'Inferior',
            lower: rows(bearing('Inferior', bearing_inner_diameter_mm='40',
                                bearing_outer_diameter_mm='4e1'))},
            blocking=[('row_shape', lower)]),
        sample('body_without_an_outer_measure_is_incomplete', {SCOPE: 'Superior',
            upper: rows(bearing(bearing_inner_diameter_mm='30'))}),
        sample('loose_balls_do_not_have_cartridge_body', {SCOPE: 'Superior',
            upper: rows(bearing(construction='Bolas sueltas', bearing_outer_diameter_mm='41'))},
            blocking=[('row_field_applicability', upper)]),
        sample('loose_balls_record_diameter_and_count', {SCOPE: 'Superior',
            upper: rows(bearing(construction='Bolas sueltas', ball_count='22', ball_diameter_mm='4'))}),
        sample('cartridge_does_not_have_a_loose_ball_count', {SCOPE: 'Superior',
            upper: rows(bearing(ball_count='22'))}, blocking=[('row_field_applicability', upper)]),
        sample('inner_and_outer_bevels_are_separate', {SCOPE: 'Inferior',
            lower: rows(bearing('Inferior', seat_geometry='Biseles interior y exterior',
                inner_contact_angle_deg='36', outer_contact_angle_deg='45'))}, sources=[SHELDON]),
        sample('no_bevel_does_not_accept_a_bevel_angle', {SCOPE: 'Inferior',
            lower: rows(bearing('Inferior', seat_geometry='Sin biseles de apoyo',
                inner_contact_angle_deg='36'))}, blocking=[('row_field_applicability', lower)]),
        sample('incomplete_scope_is_pending', {SCOPE: UNKNOWN, lower: rows(bearing('Inferior'))},
            pending=[('field_applicability_pending', lower)]),
        sample('crown_race_absent_disallows_its_reference', {'crown_race_included': False,
            race: 'Synthetic crown race', EVIDENCE: SYNTHETIC},
            blocking=[('field_applicability', race)]),
        sample('complete_does_not_force_a_separate_crown_race', {SCOPE: 'Completa',
            'crown_race_included': False}),
        sample('lower_only_disallows_upper_stack', {SCOPE: 'Inferior',
            'headset_upper_stack_height_mm': '8', EVIDENCE: SYNTHETIC},
            blocking=[('field_applicability', 'headset_upper_stack_height_mm')]),
        sample('legacy_classification_does_not_overrule_the_ends', {SCOPE: 'Completa',
            'headset_standard': 'Tapered', 'steerer_type': '1"',
            'bearing_system': 'Mixto'}),
    ]


if __name__ == '__main__':
    catalog, cases = compile_catalog()
    path = RESEARCH / 'existing-headset-catalog-2026-09-08.json'
    write_json(path, catalog)
    cases['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-headset-cases-2026-09-08.json', cases)
    print(json.dumps({**catalog['stats'], 'cases': len(cases['cases']), 'production_writes': False}))
