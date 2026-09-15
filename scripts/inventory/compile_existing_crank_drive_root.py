#!/usr/bin/env python3
"""Close package-owner leaks in crank parts without editing Claude's proposal.

Adjudication plus the five closures of the independent review: an applicable
requirement matches its applicability, every arm of a pair owns its length and
its system construction, the global cross-producing selectors are retired with
their observations, and the crank/axle junction is one typed representation
shared by the assembly and the single arm, with a linked per-member variant for
a pair. No product, DB, publisher or runtime writes.
"""
from copy import deepcopy
import hashlib
import json

from compile_existing_crank_drive_catalog import (
    compile_catalog as proposal, _add, _source_columns, EVIDENCE, SYNTHETIC,
    LEFT, RIGHT, PAIR, SINGLE_RING, RING_SET)
from compile_mobility_accessories_catalog import (
    condition, rows, case, new_definition, add_field)
from compile_wheel_small_parts_catalog import column, ALWAYS, NEVER
from compile_existing_shifting_catalog import _retire
from compile_non_drivetrain_publication import RESEARCH, write_json
from compile_product_spec_catalog import validate_contract

AXLE = 'crank_axle_interface_declarations'
AXLE_MEMBER = 'crank_axle_interface_by_member'
SPLIT_AXLE = 'Dos brazos con semiejes solidarios y unión central'
OFFERED = 'Eje ofrecido por esta pieza'
RECEIVER = 'Asiento que recibe el eje'
OWNERS = ['Pedalier con eje independiente', 'Conjunto de bielas con eje integrado',
          'Motor central', 'Otro sistema documentado']
GEOMETRIES = ['Cuadradillo', 'Estriado', 'Unión de semiejes',
              'Otra geometría documentada']
CROSS_LISTS = ('drivetrain_platform', 'compatible_rear_speeds')


def owned_copy(definitions, template, source, target, label, owner, label_columns,
               individual, grouped):
    """Existing structured shape, separate package use with an actual row link."""
    c = template['form_contract']
    c['allowed_when'][source] = deepcopy(individual)
    copied = deepcopy(definitions[source]['validation_rules'])
    copied['rows_schema']['columns'].insert(0,
        column('member_reference', 'Pieza dueña de esta declaración', required=True))
    _add(definitions, template, target, label, 'json', role='declaration',
         semantic='declaration', rules=copied, allowed=grouped,
         helper='La declaración pertenece a la pieza indicada; no se hereda al resto del envase.')
    conditions = c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields']
    if source in conditions:
        conditions[target] = deepcopy(conditions[source])
    c['row_coherence']['links'].append({'id': target + '_owner', 'field': target,
        'column': 'member_reference', 'target_field': owner, 'label_columns': label_columns})
    c['prerequisites'][target] = [EVIDENCE]


def axle_columns():
    """One junction, described once: role, owning system, geometry and source."""
    return [
        column('interface_identity', 'Interfaz identificada', required=True),
        column('junction_role', 'Qué papel cumple esta pieza en la unión', 'token',
               required=True, options=[OFFERED, RECEIVER]),
        column('axle_owner', 'Sistema dueño del eje', 'token', options=OWNERS),
        column('designation', 'Interfaz y variante exactas según la fuente', required=True),
        column('interface_geometry', 'Geometría de la unión documentada', 'token',
               required=True, options=GEOMETRIES),
        column('taper_standard', 'Estándar de cuadradillo si la fuente lo declara'),
        column('conditions', 'Condiciones y límites de la fuente'), *_source_columns()]


def axle_conditions():
    square = condition('interface_geometry', 'Cuadradillo')
    receives = condition('junction_role', RECEIVER)
    return {'allowed_when': {'taper_standard': deepcopy(square),
                             'axle_owner': deepcopy(receives)},
            'required_when': {'taper_standard': deepcopy(square),
                              'axle_owner': deepcopy(receives)}}


AXLE_HELPER = (
    'La unión entre biela y eje, descrita una sola vez: si esta pieza ofrece el '
    'eje o recibe su asiento, qué sistema es dueño del eje cuando lo recibe, la '
    'geometría documentada y la designación exacta de la fuente. Un motor '
    'central puede usar distintas interfaces: su función no permite deducir '
    'cuadradillo ni estriado, y dos designaciones iguales de texto no son una '
    'compatibilidad.')


def shared_axle(definitions, templates):
    """One neutral definition for the assembly and the individual arm."""
    definitions[AXLE] = new_definition(
        AXLE, 'Interfaz documentada entre biela y eje', 'json',
        ('crankset', 'crank_arm'),
        rules={'rows_schema': {'version': 1, 'unique_by': [['interface_identity']],
                               'columns': axle_columns()}})
    for key, allowed, required in (('crankset', ALWAYS, ALWAYS), ('crank_arm', None, None)):
        template = templates[key]
        add_field(template, AXLE, 'primary', 'compatibility',
                  allowed=allowed, required=required, helper=AXLE_HELPER)
        c = template['form_contract']
        c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][AXLE] = (
            axle_conditions())
        c['prerequisites'][AXLE] = [EVIDENCE]


def compile_catalog():
    catalog, fixtures = proposal()
    definitions = catalog['definitions']
    templates = {t['key']: t for t in catalog['templates']}
    for key in ('crankset_construction', 'crank_arm_system_construction'):
        definitions[key]['allowed_values'].append(SPLIT_AXLE)
    constructions = list(definitions['crank_arm_system_construction']['allowed_values'])
    crankset = templates['crankset']
    crankset['form_contract']['helpers']['crankset_construction'] = (
        'Distingue eje independiente, eje solidario a un brazo, semiejes unidos '
        'en el centro y construcción de una pieza. No es el número de platos ni '
        'una aprobación de compatibilidad por número de piezas.')
    arm = templates['crank_arm']
    c = arm['form_contract']
    individual, pair = condition('crank_side', [LEFT, RIGHT]), condition('crank_side', PAIR)
    definitions['crank_arm_unit_count']['validation_rules'] = {'integer': True, 'min': '2', 'max': '2'}
    c['helpers']['crank_arm_system_construction'] = (
        'Construcción documentada del sistema de esta pieza. Para decidir compatibilidad '
        'se necesita la interfaz y el modelo concretos; la cantidad de piezas no basta.')
    c['allowed_when']['crank_arm_system_construction'] = deepcopy(individual)
    c['allowed_when']['crank_arm_spindle_designation'] = deepcopy(individual)
    # H2/H3: what one arm must answer, each arm of a pair answers too. The
    # length stops being optional and the system construction gets the same
    # taxonomy per occurrence, instead of one declaration for both arms.
    unit_columns = definitions['crank_arm_units']['validation_rules']['rows_schema']['columns']
    next(x for x in unit_columns if x['key'] == 'length_mm')['required'] = True
    unit_columns.insert(-2, column('system_construction',
                                   'Construcción documentada del sistema de este brazo',
                                   'token', options=constructions))
    c['helpers']['crank_arm_units'] = (
        'Un brazo por fila, con su lado, su largo y la construcción documentada '
        'de su sistema. Lo que un brazo suelto debe declarar, cada brazo del par '
        'lo declara también; el envase no responde por los dos.')
    # H5: a required historical selector with no matching term is an impossible
    # prerequisite for a motor crank. Preserve it as legacy in both families and
    # describe the junction with one shared typed representation.
    _retire(arm, ['spindle_interface', 'spindle_taper_standard'])
    _retire(crankset, ['spindle_interface', 'spindle_taper_standard'])
    shared_axle(definitions, templates)
    c['allowed_when'][AXLE] = deepcopy(individual)
    c['required_when'][AXLE] = deepcopy(individual)
    owned_copy(definitions, arm, AXLE, AXLE_MEMBER, 'Interfaz de eje por brazo del par',
               'crank_arm_units', ['unit_identity', 'unit_side'], individual, pair)
    c['required_when'][AXLE_MEMBER] = deepcopy(pair)
    definitions[AXLE_MEMBER]['label'] = 'Interfaz de eje por brazo del par'
    owned_copy(definitions, arm, 'crank_arm_compatibility_claims', 'crank_arm_unit_compatibility_claims',
        'Declaraciones por brazo del par', 'crank_arm_units', ['unit_identity', 'unit_side'], individual, pair)
    # These tables already describe separate physical rings, but their offset,
    # pairing and fitment tables previously had no link to a ring occurrence.
    ring = templates['chainring']
    single, group = condition('chainring_package_kind', SINGLE_RING), condition('chainring_package_kind', RING_SET)
    for source, target, label in [
        ('chainring_offset_declarations', 'chainring_member_offsets', 'Desplazamiento por plato del juego'),
        ('chainring_oem_pairing_declarations', 'chainring_member_oem_pairings', 'Emparejado por plato del juego'),
        ('chainring_compatibility_claims', 'chainring_member_compatibility_claims', 'Declaraciones por plato del juego')]:
        owned_copy(definitions, ring, source, target, label, 'chainring_set_members',
                   ['member_identity', 'position'], single, group)
    for key in ('chain_width_family', 'chainring_mount_type'):
        ring['form_contract']['allowed_when'][key] = deepcopy(single)
    # H1: a field that only applies to one package kind is only required there.
    # The engine stays silent on an inapplicable requirement, so the contract
    # must not assert two different things and rely on that.
    ring['form_contract']['required_when']['chainring_mount_type'] = deepcopy(single)
    # H4: the global platform and speed lists rebuild the Cartesian product the
    # scoped declarations exist to avoid. They keep their observations as
    # legacy; per destination, per configuration and per piece survive.
    for template in (crankset, ring):
        _retire(template, [k for k in CROSS_LISTS if k in template['form_contract']['roles']])
        template['form_contract']['helpers']['spec_evidence_source'] = (
            'Fuente de la ficha. Una lista descriptiva de plataformas o de '
            'velocidades no aprueba un montaje: lo que autoriza una decisión es '
            'la declaración por destino, configuración o pieza, con su documento.')
    # Direct mount is also per occurrence, never a property inherited by all
    # rings in a package. Add the missing row fields to the unpublished table.
    member_columns = definitions['chainring_set_members']['validation_rules']['rows_schema']['columns']
    member_columns += [column('mount_designation', 'Montaje y generación de este plato'),
                       column('chain_declaration', 'Cadena documentada para este plato')]
    ring['form_contract']['allowed_when']['chainring_direct_mount_generation'] = {
        'kind': 'when', 'rows': [[
            {'field': 'chainring_package_kind', 'operator': 'eq', 'value_type': 'token', 'value': SINGLE_RING},
            {'field': 'chainring_mount_type', 'operator': 'in', 'value_type': 'token',
             'value': ['Direct mount Shimano', 'Direct mount SRAM', 'Direct mount Cinch']}]]}
    ring['form_contract']['required_when']['chainring_direct_mount_generation'] = deepcopy(
        ring['form_contract']['allowed_when']['chainring_direct_mount_generation'])
    adapt_cases(fixtures)
    fixtures['cases'] += root_cases()
    for fixture in fixtures['cases']:
        if fixture['id'] in ('ck_the_same_combination_twice_blocks', 'car_pair_count_is_exactly_two'):
            fixture['expected_sql_blocking'] = [{**i, 'code': 'field_constraint'}
                for i in fixture['expected_blocking']]
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions, {f['key'] for f in t['fields']})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definitions after the closures')
    catalog['title'] = 'Crank parts with one typed axle junction and occurrence-owned declarations'
    catalog['stats'].update(definitions=len(definitions), field_uses=sum(len(t['fields']) for t in templates.values()))
    catalog['root_adjudications'] = {
        'motor': 'A motor crank requires a documented interface, never a guessed legacy selector value.',
        'arms': 'Every arm in a pair owns its length, construction, axle interface and declarations.',
        'rings': 'Every packaged ring owns its offset, OEM pairing, fitments and mounting designation.',
        'construction': 'Central joining half-spindles are represented; piece count is not a fitment rule.',
        'junction': 'One shared typed representation states the role, the owning system, the geometry '
                    'and the exact designation; the published selector stays legacy and is not widened.',
        'lists': 'Global platform and speed lists are legacy; a descriptive list is not a mechanical approval.',
        'limits': 'Representation, exact OEM reference verification and assembly assessment remain distinct.'}
    # The motor-spindle pending said the required selector could not be
    # answered; H5 answers it with the typed junction, so it does not survive.
    fixtures['pending_cases'] = [p for p in fixtures['pending_cases']
        if p['id'] != 'an_integrated_motor_spindle_has_no_published_token']
    fixtures['pending_cases'] += pending_cases()
    return catalog, fixtures


def axle_row(identity, role, geometry, **extra):
    row = {'interface_identity': identity, 'junction_role': role,
           'designation': 'Designación exacta documentada',
           'interface_geometry': geometry, 'source_document': 'Documento identificado',
           **extra}
    if role == RECEIVER:
        row.setdefault('axle_owner', 'Pedalier con eje independiente')
    return row


def adapt_cases(fixtures):
    """Keep the inherited cases valid after the retirements, and complete the
    positives instead of letting them carry a silent pending."""
    for f in fixtures['cases']:
        values = f['template'], f['values']
        if f['template'] == 'crank_arm' and f['expected_blocking'] == [
                {'code': 'field_applicability', 'field': 'spindle_taper_standard'}]:
            f['id'] = 'car_the_retired_taper_selector_no_longer_answers'
            f['expected_blocking'] = []
            f['forbidden_issue_fields'] = ['spindle_taper_standard', 'spindle_interface']
            f['values']['spindle_interface'] = 'Interfaz que el dominio publicado no tiene'
            f['values']['spindle_taper_standard'] = 'Estándar inexistente'
        if f['template'] == 'chainring' and f['values'].get('chainring_package_kind') == RING_SET:
            f['values'].pop('chainring_mount_type', None)
        if f['expected_blocking']:
            continue
        v = f['values']
        if f['template'] == 'crankset' and AXLE not in v:
            offered = v.get('spindle_included') is True
            v[AXLE] = rows(axle_row(
                'Unión documentada', OFFERED if offered else RECEIVER,
                'Estriado' if offered else 'Cuadradillo',
                **({} if offered else {'taper_standard': 'JIS'})))
        if f['template'] == 'crank_arm':
            if v.get('crank_side') == PAIR and AXLE_MEMBER not in v and 'crank_arm_units' in v:
                v[AXLE_MEMBER] = rows(*[
                    {**axle_row('Unión ' + r['id'], RECEIVER, 'Cuadradillo',
                                taper_standard='JIS'), 'member_reference': r['id']}
                    for r in v['crank_arm_units']['rows']])
            elif v.get('crank_side') in (LEFT, RIGHT) and AXLE not in v:
                v[AXLE] = rows(axle_row('Unión documentada', RECEIVER, 'Cuadradillo',
                                        taper_standard='JIS'))


def root_cases():
    spline = axle_row('A', RECEIVER, 'Estriado', axle_owner='Motor central',
                      designation='Interfaz estriada exacta documentada')
    square = axle_row('Cuadradillo documentado', RECEIVER, 'Cuadradillo', taper_standard='JIS')
    def unit(identity, side):
        return {'unit_identity': identity, 'unit_side': side, 'length_mm': '170',
                'source_document': 'Envase identificado'}
    arms = rows(unit('Left', LEFT), unit('Right', RIGHT))
    pair = {EVIDENCE: SYNTHETIC, 'crank_side': PAIR, 'crank_arm_unit_count': '2',
            'crank_arm_units': arms, AXLE_MEMBER: rows(
                {**square, 'interface_identity': 'A', 'member_reference': 'r1'},
                {**square, 'interface_identity': 'B', 'member_reference': 'r2'})}
    rings = rows({'member_identity': 'A', 'position': 'Exterior', 'teeth': '36', 'source_document': 'Synthetic'},
                 {'member_identity': 'B', 'position': 'Interior', 'teeth': '26', 'source_document': 'Synthetic'})
    ring_set = {EVIDENCE: SYNTHETIC, 'chainring_package_kind': RING_SET,
                'chainring_set_member_count': '2', 'chainring_set_members': rings}
    offset = {'measurement_identity': 'A', 'offset_mm': '3', 'datum': 'Documented surface', 'source_document': 'Synthetic'}
    crank = {EVIDENCE: SYNTHETIC, 'crankset_construction': 'Tres piezas (eje independiente)',
             'spindle_included': False, 'bottom_bracket_included': False,
             'included_chainring_count': '0', AXLE: rows(square)}
    def build(prefix, family, name, values, forbidden=(), **kwargs):
        result = case(prefix + name, family, values, **kwargs)
        if forbidden:
            result['forbidden_issue_fields'] = list(forbidden)
        return result

    def arm(name, values, **kw): return build('car_', 'crank_arm', name, values, **kw)
    def ring(name, values, **kw): return build('crr_', 'chainring', name, values, **kw)
    def crankset(name, values, **kw): return build('ckr_', 'crankset', name, values, **kw)
    return [
        # H5 · one junction, two families, the same typed answer.
        arm('a_motor_interface_needs_no_unavailable_legacy_token', {
            EVIDENCE: SYNTHETIC, 'crank_side': LEFT, 'crank_arm_length_mm': '170',
            AXLE: rows(spline)}),
        arm('a_splined_arm_cannot_declare_a_square_taper_standard', {
            EVIDENCE: SYNTHETIC, 'crank_side': LEFT, 'crank_arm_length_mm': '170',
            AXLE: rows({**spline, 'taper_standard': 'JIS'})},
            blocking=[('row_field_applicability', AXLE)]),
        arm('a_square_arm_declares_which_standard', {
            EVIDENCE: SYNTHETIC, 'crank_side': LEFT, 'crank_arm_length_mm': '170',
            AXLE: rows(square)}),
        arm('a_square_arm_without_its_standard_is_incomplete', {
            EVIDENCE: SYNTHETIC, 'crank_side': LEFT, 'crank_arm_length_mm': '170',
            AXLE: rows({k: v for k, v in square.items() if k != 'taper_standard'})},
            pending=[('row_required_missing', AXLE)]),
        arm('pair_interfaces_own_different_arms', pair),
        arm('a_foreign_arm_interface_blocks', {**pair, AXLE_MEMBER: rows(
            {**square, 'member_reference': 'foreign'})},
            blocking=[('row_reference_unresolved', AXLE_MEMBER)]),
        arm('a_pair_cannot_inherit_one_axle_interface', {**pair, AXLE: rows(square)},
            blocking=[('field_applicability', AXLE)]),
        arm('a_splined_unit_interface_also_rejects_a_square_taper', {**pair, AXLE_MEMBER: rows(
            {**spline, 'member_reference': 'r1', 'taper_standard': 'JIS'})},
            blocking=[('row_field_applicability', AXLE_MEMBER)]),
        arm('pair_count_is_exactly_two', {**pair, 'crank_arm_unit_count': '3'},
            blocking=[('range', 'crank_arm_unit_count')]),
        # H2 · the length a single arm must answer, each arm answers too.
        arm('a_pair_without_an_arm_length_is_pending', {**pair, 'crank_arm_units': rows(
            {k: v for k, v in unit('Left', LEFT).items() if k != 'length_mm'},
            unit('Right', RIGHT))},
            pending=[('row_incomplete', 'crank_arm_units')]),
        # H3 · the construction of each arm, never one declaration for both.
        arm('each_arm_declares_its_own_system_construction', {**pair,
            'crank_arm_units': rows(
                {**unit('Left', LEFT), 'system_construction': SPLIT_AXLE},
                {**unit('Right', RIGHT), 'system_construction': SPLIT_AXLE})}),
        arm('a_pair_cannot_declare_one_system_construction',
            {**pair, 'crank_arm_system_construction': SPLIT_AXLE},
            blocking=[('field_applicability', 'crank_arm_system_construction')]),
        # H5 · the assembly answers with the same representation.
        crankset('a_crankset_names_its_axle_junction', crank),
        crankset('an_offered_axle_names_no_owning_system', {**crank,
            'spindle_included': True, AXLE: rows(axle_row(
                'Eje propio', OFFERED, 'Estriado', axle_owner='Motor central'))},
            blocking=[('row_field_applicability', AXLE)]),
        crankset('a_received_axle_without_its_owning_system_is_incomplete', {**crank,
            AXLE: rows({k: v for k, v in square.items() if k != 'axle_owner'})},
            pending=[('row_required_missing', AXLE)]),
        crankset('a_splined_crankset_cannot_declare_a_square_taper', {**crank,
            AXLE: rows({**spline, 'taper_standard': 'JIS'})},
            blocking=[('row_field_applicability', AXLE)]),
        # An out-of-domain value proves the retired field is stripped, not
        # merely quiet: an active selector would reject it.
        crankset('the_retired_axle_selector_no_longer_answers', {**crank,
            'spindle_interface': 'Interfaz que el dominio publicado no tiene',
            'spindle_taper_standard': 'Estándar inexistente'},
            forbidden=['spindle_interface', 'spindle_taper_standard']),
        # H4 · the retired cross lists answer nothing and block nothing.
        crankset('the_retired_cross_lists_no_longer_answer', {**crank,
            'drivetrain_platform': 'Plataforma inexistente',
            'compatible_rear_speeds': ['99']},
            forbidden=['drivetrain_platform', 'compatible_rear_speeds']),
        ring('the_retired_cross_lists_no_longer_answer', {**ring_set,
            'drivetrain_platform': 'Plataforma inexistente',
            'compatible_rear_speeds': ['99']},
            forbidden=['drivetrain_platform', 'compatible_rear_speeds']),
        # H1 · an inapplicable field is not demanded either.
        ring('a_set_is_not_asked_for_a_package_mount_type', ring_set,
             forbidden=['chainring_mount_type']),
        ring('a_single_ring_is_still_asked_for_its_mount_type',
             {EVIDENCE: SYNTHETIC, 'chainring_package_kind': SINGLE_RING, 'teeth_count': '36'},
             pending=[('required_missing', 'chainring_mount_type')]),
        ring('each_ring_owns_its_offset', {**ring_set, 'chainring_member_offsets': rows(
            {**offset, 'member_reference': 'r1'}, {**offset, 'measurement_identity': 'B', 'member_reference': 'r2', 'offset_mm': '6'})}),
        ring('offset_cannot_name_a_foreign_ring', {**ring_set, 'chainring_member_offsets': rows(
            {**offset, 'member_reference': 'foreign'})}, blocking=[('row_reference_unresolved', 'chainring_member_offsets')]),
        ring('set_cannot_inherit_one_offset', {**ring_set, 'chainring_offset_declarations': rows(offset)},
            blocking=[('field_applicability', 'chainring_offset_declarations')]),
        ring('set_cannot_inherit_one_mount_type', {**ring_set, 'chainring_mount_type': 'BCD 4 pernos'},
            blocking=[('field_applicability', 'chainring_mount_type')]),
    ]


def pending_cases():
    return [
        {'id': 'a_descriptive_list_is_not_a_mechanical_approval',
         'required_result': 'unknown_without_exact_reference',
         'reason': 'The retired platform and speed lists keep their observations '
                   'as legacy. Reading them back as an approval, or rebuilding '
                   'them as a new global list, returns the Cartesian problem '
                   'they were retired for.'},
        {'id': 'the_axle_junction_still_needs_a_directed_relation',
         'required_result': 'unknown_without_exact_reference',
         'reason': 'Two pieces whose typed junctions read alike are not thereby '
                   'compatible: matching an arm to an assembly needs a directed '
                   'model-scoped relation, not equal designation text.'},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH/'existing-crank-drive-adjudicated-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH/'existing-crank-drive-adjudicated-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'production_writes': False}))
