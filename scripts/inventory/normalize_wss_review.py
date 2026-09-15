#!/usr/bin/env python3
"""Reproduce root's source-adjudicated WSS proposal without publishing it."""
from copy import deepcopy as copy
import hashlib
import json
from pathlib import Path

from compile_product_spec_catalog import RESEARCH
from product_spec_field_patches import artifact_sha

PACKET = 'wheels-steering-suspension-implementation-packet-2026-09-07.json'
REVIEW = 'wheels-steering-suspension-packet-semantic-review-2026-09-07.json'
BASE = 'all-family-row-conditions-integrated-2026-09-07.json'
EXPECTED = {
    PACKET: 'c03ebe91fa7e56d32ffb44a0a6ba3b00a4ff917b296068773e2a95027444b3bd',
    REVIEW: 'd45728eefb34ce50598e1d89d272bcf9bd92ff3c0283e91573404cf290e14171',
    BASE: 'c12204e42f86423fc3bf3eba345a9f07568b4849d9c8d9b8ace4d44430ddcf9a',
}


def load(name):
    raw = (RESEARCH / name).read_bytes()
    if name in EXPECTED and hashlib.sha256(raw).hexdigest() != EXPECTED[name]:
        raise ValueError('Frozen WSS input changed: ' + name)
    return json.loads(raw)


def write(name, value):
    (RESEARCH / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def predicate(field, values, kind='token', operator=None):
    return {'field': field, 'operator': operator or ('in' if isinstance(values, list) else 'eq'),
            'value_type': kind, 'value': values}


def when(*conditions):
    return {'kind': 'when', 'rows': [list(conditions)]}


def normalize():
    original, semantic, base = load(PACKET), load(REVIEW), load(BASE)
    definitions = copy(original['new_definitions'])
    templates = {t['key']: t for t in base['templates']}
    patches = [{k: copy(p[k]) for k in ('id', 'op', 'template', 'key', 'before', 'after')}
               for p in original['patches']]
    decisions = {p['id']: {'patch_id': p['id'], 'decision': 'aceptar',
        'reason': 'Representación con alcance de un producto; no aprueba montaje ni publica datos.'} for p in patches}
    for p in original['patches']:
        if p.get('requires_before_extensions'):
            decisions[p['id']]['before_extensions'] = p['requires_before_extensions']

    def correction(patch_id, reason):
        decisions[patch_id].update(decision='corregir', reason=reason)

    def add_patch(patch, reason):
        patches.append(patch)
        decisions[patch['id']] = {'patch_id': patch['id'], 'decision': 'aceptar', 'reason': reason}

    def definition(key, label, kind, options=()):
        definitions[key] = {'key': key, 'origin': 'new', 'id': None, 'label': label,
            'data_type': kind, 'unit': None, 'allowed_values': list(options),
            'validation_rules': {}, 'used_by': []}

    def add_field(template, key, order, allowed=None):
        add_patch({'id': 'ROOT-WSS-' + template + '-' + key, 'op': 'add_field',
            'template': template, 'key': key, 'before': None, 'after': {
                'field_entry': {'key': key, 'section_key': 'measurement', 'sort_order': order,
                    'is_required': False, 'visibility_rules': [], 'option_rules': [], 'constraint_rules': []},
                'definition_used_by_append': template, 'roles': 'measurement',
                'semantic_roles': 'compatibility', 'allowed_when': allowed or {'kind': 'always'},
                'required_when': {'kind': 'never'}, 'evidence_requirements': 'oem_spec'}},
            'Eje separado que evita deducir una interfaz desde otra propiedad.')

    # Keep the historical token; broaden only the unpublished construction vocabulary.
    cartridges = ['Cartucho sellado', 'Cartucho abierto', 'Cartucho blindado', 'Cartucho (sellado sin confirmar)']
    old_options = base['definitions']['bearing_construction']['allowed_values']
    add_patch({'id': 'ROOT-WSS-cartridge-constructions', 'op': 'append_allowed_values',
        'template': None, 'key': 'bearing_construction', 'before': old_options,
        'after': old_options + cartridges[1:]}, 'Un cartucho no necesariamente está sellado; se conserva el token previo y sus IDs.')
    cartridge = when(predicate('bearing_construction', cartridges))
    old_cartridge = when(predicate('bearing_construction', 'Cartucho sellado'))
    for template in ('bearing', 'bottom_bracket_bearing'):
        contract = templates[template]['form_contract']
        for field in templates[template]['fields']:
            key = field['key']
            before = {bucket: contract[bucket][key] for bucket in ('allowed_when', 'required_when')
                      if contract[bucket].get(key) == old_cartridge}
            if before:
                add_patch({'id': 'ROOT-WSS-cartridge-domain-' + template + '-' + key,
                    'op': 'replace_field_contract', 'template': template, 'key': key,
                    'before': before, 'after': {bucket: cartridge for bucket in before}},
                    'Diámetros y referencia pertenecen también al cartucho abierto/blindado, sin alterar bolas sueltas.')

    # MAX retention and rolling contact geometry can coexist. Preserve the OEM wording.
    d = definitions['bearing_internal_construction']
    d.update(data_type='text', allowed_values=[], label='Diseño interno declarado por el fabricante (literal)')
    correction('WSS-W03-internal_construction', 'Enduro 7001 1ZS MAX es MAX y contacto angular; MAX sí tiene canal de llenado. No son alternativas exclusivas.')
    definitions['bearing_seal_kind'].update(data_type='text', allowed_values=[],
        label='Designación de sellado o blindaje del fabricante (literal)')
    correction('WSS-W03-seal_kind', 'Conservar LLU, LLB y designaciones por cara sin colapsarlas en un token común.')
    geometry = ['Biseles interior y exterior', 'Sólo bisel interior', 'Sólo bisel exterior',
                'Sin biseles de apoyo', 'Otro', 'Desconocido / sin confirmar']
    definition('bearing_seat_geometry', 'Geometría de apoyo del cartucho', 'single_select', geometry)
    definition('bearing_element_retention', 'Retención de elementos rodantes', 'single_select',
               ['Con jaula', 'Complemento completo / sin jaula', 'Otro', 'Desconocido / sin confirmar'])
    add_field('bearing', 'bearing_seat_geometry', 240, cartridge)
    add_field('bearing', 'bearing_element_retention', 250, cartridge)
    # The two new prerequisites must exist before the angle contracts are validated.
    for side in ('inner', 'outer'):
        key = 'bearing_' + side + '_contact_angle_deg'
        patch_id = 'WSS-W04-bearing-require-' + key
        p = next(p for p in patches if p['id'] == patch_id)
        condition = when(predicate('bearing_construction', cartridges), predicate('bearing_seat_geometry',
            ['Biseles interior y exterior', 'Sólo bisel ' + ('interior' if side == 'inner' else 'exterior')]))
        p['before'] = {bucket: copy(templates['bearing']['form_contract'][bucket][key])
                       for bucket in ('allowed_when', 'required_when')}
        p['after'] = {bucket: condition for bucket in p['before']}
        correction(patch_id, 'El par de biseles depende de la geometría de apoyo explícita y construcción de cartucho, no del destino ni del contacto entre bolas y pistas.')
        add_patch({'id': 'ROOT-WSS-bevel-label-' + side, 'op': 'replace_definition_label',
            'template': None, 'key': key, 'before': base['definitions'][key]['label'],
            'after': 'Ángulo del bisel de apoyo ' + ('interior' if side == 'inner' else 'exterior')},
            'El bisel de montaje descrito por Park no es el ángulo interno de contacto entre bola y pista.')
        add_patch({'id': 'ROOT-WSS-bevel-domain-' + side, 'op': 'replace_unpublished_numeric_rules',
            'template': None, 'key': key, 'before': base['definitions'][key]['validation_rules'],
            'after': {'positive': True, 'max': '90'}}, 'Ángulo de una superficie de apoyo: dominio geométrico, no lista de estándares homologados.')

    for p in patches:
        if p['op'] == 'add_field' and p['template'] == 'bearing' and p['after']['allowed_when'] == old_cartridge:
            p['after']['allowed_when'] = cartridge

    # A tyre fiche owns one physical variant. Pressure is one value + declared unit.
    schema = definitions['tire_rim_configurations']['validation_rules']['rows_schema']
    schema['columns'] = [c for c in schema['columns'] if c['key'] not in ('tire_variant', 'max_pressure_bar', 'max_pressure_psi')]
    schema['columns'][4:4] = [
        {'key': 'max_pressure', 'label': 'Presión máxima declarada', 'type': 'decimal', 'validation': {'positive': True}},
        {'key': 'pressure_unit', 'label': 'Unidad declarada', 'type': 'token', 'allowed_values': ['bar', 'psi']},
    ]
    schema['unique_by'] = [['rim_bead_profile', 'mounting_method']]
    definitions['tire_rim_configurations']['label'] = 'Límites generales de montaje de esta variante de neumático'
    correction('WSS-W01-tire-configurations', 'Un SKU por ficha; una presión y su unidad, sin dos máximos paralelos contradictorios. Límites específicos de otro producto requieren relación con ese producto.')

    # Shock ends are intrinsic to the component, not the bicycle mounting orientation.
    schema = definitions['shock_end_configurations']['validation_rules']['rows_schema']
    schema['columns'][0]['allowed_values'] = ['Cuerpo', 'Vástago']
    schema['columns'][0]['label'] = 'Extremo físico del amortiguador'
    schema['columns'][1]['allowed_values'] = ['Ojal estándar', 'Ojal con rodamiento', 'Trunnion', 'Yoke', 'Otro', 'Desconocido / sin confirmar']
    correction('WSS-W02-shock-ends', 'FOX y RockShox identifican body/shaft eyelet. Superior/inferior depende de cómo se instala en el cuadro.')
    add_patch({'id': 'ROOT-WSS-retire-shock-mount-scalar', 'op': 'replace_field_contract',
        'template': 'rear_shock', 'key': 'shock_mount_kind',
        'before': {'roles': templates['rear_shock']['form_contract']['roles']['shock_mount_kind']},
        'after': {'roles': 'legacy'}}, 'El montaje por extremo sustituye al selector sin extremo; el hecho legacy se conserva sin gobernar el editor.')

    # A frame housing is not EC or ZS: both headsets can use one cylindrical port.
    schema = definitions['headset_port_configurations']['validation_rules']['rows_schema']
    schema['columns'][1]['allowed_values'] = ['Alojamiento para cazoleta prensada', 'Asiento mecanizado para cartucho', 'Otro', 'Desconocido / sin confirmar']
    correction('WSS-W05-frame-ports', 'Separa geometría del alojamiento de la cazoleta seleccionada y de la rosca de la espiga.')
    schema = definitions['headset_bearing_configurations']['validation_rules']['rows_schema']
    schema['columns'][1:1] = [
        {'key': 'construction', 'label': 'Construcción', 'type': 'token', 'required': True,
         'allowed_values': ['Cartucho', 'Bolas sueltas', 'Canastillo con bolas', 'Otro', 'Desconocido / sin confirmar']},
        {'key': 'seat_geometry', 'label': 'Geometría de apoyo del cartucho', 'type': 'token', 'allowed_values': geometry},
    ]
    for col in schema['columns']:
        if col['key'] in ('inner_contact_angle_deg', 'outer_contact_angle_deg'):
            col['label'] = 'Ángulo del bisel ' + ('interior' if col['key'].startswith('inner') else 'exterior')
            col['validation']['max'] = '90'
        if col['key'] == 'seat_type':
            col['allowed_values'].remove('Roscado')
    correction('WSS-W04-headset-bearings', 'Bolas y canastillos no reciben ángulos de cartucho; rosca de espiga es independiente de IS/ZS/EC.')

    definition('fork_crown_layout', 'Construcción de coronas de la horquilla', 'single_select',
               ['Una corona', 'Doble corona', 'Otra', 'Desconocido / sin confirmar'])
    add_field('fork', 'fork_crown_layout', 200)
    for key in ('crown_stack_min_mm', 'crown_stack_max_mm'):
        p = next(p for p in patches if p['key'] == key and p['op'] == 'add_field')
        p['after']['allowed_when'] = when(predicate('fork_crown_layout', 'Doble corona'))
        correction(p['id'], 'Altura entre coronas depende de la doble corona y del modelo concreto, no del resorte aire/muelle.')
        definitions[key]['label'] = 'Altura total ' + ('mínima' if 'min' in key else 'máxima') + ' de montaje entre coronas'
    definitions['fork_tire_clearance_configurations']['validation_rules']['rows_schema']['unique_by'] = [['bead_seat_diameter_mm']]
    correction('WSS-W07-fork-clearance', 'El máximo no identifica la envolvente general; una sola envolvente por BSD del mismo SKU. Configuraciones adicionales exigen alcance declarado.')
    decisions['WSS-W10-spoke-thread-label'].update(decision='rechazar',
        reason='El rótulo original sí describe rosca. Sapim FG2.3 no es diámetro de alambre de 2.0 mm.')

    def row_rules(template, field, allowed, required):
        add_patch({'id': 'ROOT-WSS-conditions-' + template, 'op': 'replace_template_coherence',
            'template': template, 'key': 'row_conditions',
            'before': {'present': 'row_conditions' in templates[template]['form_contract'],
                       'value': templates[template]['form_contract'].get('row_conditions')},
            'after': {'version': 1, 'fields': {field: {'allowed_when': allowed,
                'required_when': required, 'allowed_options': {}}}}},
            'Los requisitos consumen sólo celdas de la misma configuración; falta de dato permanece pendiente.')
    pressure_condition = when(predicate('pressure_unit', ['bar', 'psi']))
    row_rules('tire', 'tire_rim_configurations', {'max_pressure': pressure_condition},
              {'max_pressure': pressure_condition})
    angle_allowed = {'seat_geometry': when(predicate('construction', 'Cartucho'))}
    angle_required = {}
    for side in ('inner', 'outer'):
        key = side + '_contact_angle_deg'
        condition = when(predicate('construction', 'Cartucho'), predicate('seat_geometry',
            ['Biseles interior y exterior', 'Sólo bisel ' + ('interior' if side == 'inner' else 'exterior')]))
        angle_allowed[key] = condition
        angle_required[key] = condition
    row_rules('headset', 'headset_bearing_configurations', angle_allowed, angle_required)

    # Store the normalized proposal, retaining source file hashes in the adjudication.
    # Correction replacements are concrete here; they are not permissions to mutate later.
    for decision in decisions.values():
        if decision['decision'] == 'corregir':
            p = next(p for p in patches if p['id'] == decision['patch_id'])
            decision['after_override'] = p['after']
    proposal = {'schema_version': 1, 'new_definitions': definitions, 'patches': patches,
                'source_hashes': EXPECTED, 'approval_scope': 'field_representation'}
    adjudication = {'schema_version': 1, 'approval_scope': 'field_representation',
        'base_sha256': artifact_sha(base), 'proposal_file': 'wss-normalized-patches-2026-09-07.json',
        'proposal_sha256': artifact_sha(proposal), 'source_hashes': EXPECTED,
        'patch_adjudications': list(decisions.values()), 'mechanical_coverage_complete': False,
        'automatic_fill_authorized': False, 'product_writes': 0}
    write(adjudication['proposal_file'], proposal)
    write('wss-root-decisions-2026-09-07.json', adjudication)
    cases = []
    urls = {k: v.get('url') for k, v in original['sources'].items()}
    for source in original['fixtures'] + semantic['regression_fixtures']:
        if source['id'] == 'tire_gp5000_two_variants_hookless':
            continue  # Replaced by separate, source-scoped physical variants below.
        case = {'id': 'wss_' + source['id'], 'template': source['template'],
            'kind': source['kind'], 'values': copy(source['values']),
            'source_urls': [urls[s] for s in source.get('source_ids', []) if urls.get(s)],
            'expected_blocking': [{k: i[k] for k in ('code', 'field')}
                for i in source.get('expected_issues', source.get('expected', [])) if i.get('blocking', True)],
            'note': source['note'], 'automatic_fill_authorized': False, 'facts_verified_for_product': False}
        values = case['values']
        if values.get('bearing_internal_construction') == 'MAX / sin canal de llenado':
            values['bearing_internal_construction'] = 'MAX'
            values['bearing_element_retention'] = 'Complemento completo / sin jaula'
            case['note'] = 'Diseño MAX conserva su literal; Enduro declara complemento completo y canal de llenado. La envolvente no aprueba el uso.'
        if source['id'] in ('SF1', 'SF2', 'bearing_headset_without_angles'):
            values['bearing_construction'] = 'Cartucho sellado'
            values['bearing_seat_geometry'] = 'Biseles interior y exterior'
        if source['id'] in ('SF2', 'bearing_headset_without_angles'):
            case['expected_issue_subset'] = [
                {'code': 'required_missing', 'field': 'bearing_inner_contact_angle_deg', 'blocking': False},
                {'code': 'required_missing', 'field': 'bearing_outer_contact_angle_deg', 'blocking': False}]
        if source['id'] in ('SF3', 'SF4'):
            case['forbidden_issue_fields'] = ['bearing_inner_contact_angle_deg', 'bearing_outer_contact_angle_deg']
        if 'crown_stack_min_mm' in values or 'crown_stack_max_mm' in values:
            values['fork_crown_layout'] = 'Doble corona'
        for row in values.get('headset_port_configurations', {}).get('rows', []):
            row['values']['seat_type'] = 'Alojamiento para cazoleta prensada'
        for row in values.get('headset_bearing_configurations', {}).get('rows', []):
            row['values']['construction'] = 'Cartucho'
            row['values']['seat_geometry'] = 'Biseles interior y exterior'
        for row in values.get('shock_end_configurations', {}).get('rows', []):
            row['values']['end_position'] = {'Superior': 'Cuerpo', 'Inferior': 'Vástago'}[row['values']['end_position']]
            row['values'].pop('hardware_width_mm', None)
            row['values'].pop('bolt_diameter_mm', None)
            case['note'] = 'Fixture de representación por extremo físico; no atribuye combinación ni medidas de hardware a un SKU OEM.'
        for row in values.get('tire_rim_configurations', {}).get('rows', []):
            v = row['values']
            variant = v.pop('tire_variant', None)
            if variant:
                values.setdefault('tire_width_mm', '28')
                values.setdefault('bead_seat_diameter_mm', '622')
            # The source gives a maximum, not a minimum or a singleton width.
            v.pop('rim_internal_width_min_mm', None)
            for unit in ('bar', 'psi'):
                key = 'max_pressure_' + unit
                if key in v:
                    if 'max_pressure' in v:
                        raise ValueError('Cannot collapse two pressure observations implicitly')
                    v['max_pressure'] = v.pop(key)
                    v['pressure_unit'] = unit
        for key, definition in definitions.items():
            if key not in values or definition['data_type'] != 'json':
                continue
            numeric = {c['key'] for c in definition['validation_rules']['rows_schema']['columns']
                       if c['type'] in ('decimal', 'integer')}
            for row in values[key]['rows']:
                for column in numeric:
                    if type(row['values'].get(column)) is int:
                        row['values'][column] = str(row['values'][column])
        if source['id'] == 'SF5':
            values.pop('tire_max_pressure_psi', None)  # 102 psi was not reverified for this exact edition.
            case['note'] = 'Continental GP5000 S TR 28-622: máximo 23 mm internos y 5.0 bar. No se inventa un mínimo.'
        if source['id'] == 'SF8':
            case['kind'] = 'synthetic_representation'
            case['note'] = 'Fixture sintética: dos BSD para una misma horquilla si OEM los declara; no identifica ni aprueba una horquilla real.'
        cases.append(case)
    tire30 = copy(next(c for c in cases if c['id'] == 'wss_SF5'))
    tire30['id'] = 'wss_gp5000_s_tr_30_622_separate_product'
    tire30['values'].update(tire_etrto='30-622', tire_width_mm='30')
    tire30['values']['tire_rim_configurations']['rows'][0]['values'].update(
        rim_internal_width_max_mm='25', max_pressure='4.5')
    tire30['note'] = 'Otro producto: GP5000 S TR 30-622, máximo 25 mm internos y 4.5 bar; no pertenece a la ficha de la 28-622.'
    cases.append(tire30)

    def case(name, template, values, blocking=(), **extra):
        cases.append({'id': 'wss_root_' + name, 'template': template, 'values': values,
            'kind': 'root_boundary', 'source_urls': [], 'expected_blocking': list(blocking),
            'automatic_fill_authorized': False, 'facts_verified_for_product': False, **extra})

    both = {'bearing_construction': 'Cartucho sellado', 'bearing_seat_geometry': 'Biseles interior y exterior'}
    case('rolling_angle_does_not_imply_mount_bevels', 'bearing', {
        'bearing_construction': 'Cartucho blindado', 'bearing_internal_construction': 'Angular Contact MAX',
        'bearing_seat_geometry': 'Sin biseles de apoyo',
        'bearing_element_retention': 'Complemento completo / sin jaula',
        'bearing_size_code': '7001 1ZS MAX'},
        forbidden_issue_fields=['bearing_inner_contact_angle_deg', 'bearing_outer_contact_angle_deg'])
    case('loose_ball_cannot_receive_a_bevel_angle', 'bearing', {
        'bearing_construction': 'Bolas sueltas (bolsa)', 'bearing_application': 'Dirección',
        'bearing_inner_contact_angle_deg': '36'}, [{'code': 'field_applicability', 'field': 'bearing_inner_contact_angle_deg'}])
    case('bevel_angle_outside_geometric_domain', 'bearing', {
        **both, 'bearing_inner_contact_angle_deg': '360', 'bearing_outer_contact_angle_deg': '45'},
        [{'code': 'range', 'field': 'bearing_inner_contact_angle_deg'}])
    case('open_cartridge_dimensions_are_applicable', 'bottom_bracket_bearing', {
        'bearing_construction': 'Cartucho abierto', 'bearing_size_code': '6902',
        'bearing_inner_diameter_mm': '15', 'bearing_outer_diameter_mm': '28', 'bb_bearing_width_mm': '7'})
    case('single_crown_cannot_receive_double_crown_stack', 'fork', {
        'fork_crown_layout': 'Una corona', 'crown_stack_min_mm': '105'},
        [{'code': 'field_applicability', 'field': 'crown_stack_min_mm'}])
    row = {'schema_version': 1, 'rows': [{'id': 'upper', 'values': {
        'position': 'Superior', 'construction': 'Bolas sueltas', 'inner_contact_angle_deg': '36'}, 'sources': []}]}
    case('headset_loose_balls_do_not_have_cartridge_bevels', 'headset',
        {'headset_part_scope': 'Superior', 'headset_bearing_configurations': row},
        [{'code': 'row_field_applicability', 'field': 'headset_bearing_configurations'}])
    case('pressure_unit_requires_its_value', 'tire', {'tire_rim_configurations': {
        'schema_version': 1, 'rows': [{'id': 'hookless', 'values': {
            'rim_bead_profile': 'Sin gancho (hookless)', 'mounting_method': 'Tubeless', 'pressure_unit': 'bar'}, 'sources': []}]}},
        expected_row_condition_issues=[{'code': 'row_required_missing', 'field': 'tire_rim_configurations',
            'row_id': 'hookless', 'column': 'max_pressure', 'blocking': False}])
    for c in cases:
        c['expected_blocking'].sort(key=lambda i: (i['code'], i['field']))
        # Existing SQL wraps unlinked row/numeric failures as field_constraint.
        # Retain both exact public diagnostics; never waive the blocking check.
        if c['id'] in ('wss_shock_two_rows_same_end', 'wss_SF7',
                       'wss_root_bevel_angle_outside_geometric_domain'):
            c['expected_sql_blocking'] = [{'code': 'field_constraint', 'field': i['field']}
                                         for i in c['expected_blocking']]
    case_document = {'schema_version': 1, 'cases': cases,
                     'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    adjudication['cases_sha256'] = artifact_sha(case_document)
    write('wss-representation-cases-2026-09-07.json', case_document)
    write('wss-root-decisions-2026-09-07.json', adjudication)
    return original, semantic, base, proposal, adjudication


if __name__ == '__main__':
    *_, proposal, decisions = normalize()
    print(json.dumps({'patches': len(proposal['patches']), 'new_definitions': len(proposal['new_definitions']),
                      'proposal_sha256': decisions['proposal_sha256']}))
