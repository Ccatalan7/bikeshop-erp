#!/usr/bin/env python3
"""Compile four cable/control templates. No product or database writes.

A row copies a manufacturer declaration for a named scope. The diameter unit
never implies the pitch unit, and two members of one set are not a permission
to combine any member with any other.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table
from compile_product_spec_catalog import validate_contract

FAMILIES = ('control_cable', 'control_housing', 'control_small_part',
            'bmx_cable_detangler')
# Park Tool documents designations pairing a millimetre diameter with a
# threads-per-inch pitch, so neither unit implies the other.
PARK_THREADS = 'https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts'
# Sheldon Brown names the two brake fittings by the lever each serves, names
# the shifter fitting separately, and states that a double-ended inner wire
# must be cut before use: two heads are alternatives, not a pair in service.
SHELDON_CABLES = 'https://www.sheldonbrown.com/cables.html'
# Odyssey's own store publishes a length for the upper cable of each kit and
# none for the lower, which it sells as fitting most systems: inside one kit,
# one member carries a figure and another does not.
ODYSSEY_GYROS = 'https://shop.odysseybmx.com/collections/odyssey-gyros'
# Jagwire's KEB Slick-Lube is a 5 mm compressionless housing built for braking
# by adding a Kevlar weave. Reinforcement, not the absence of coil, is what
# separates it from the shift housing Sheldon warned against putting on brakes.
JAGWIRE_KEB = 'https://www.jagwire.com/en/article/154-585/brake-housing-5mm-keb-slick-lube'

DECLARED, UNDECLARED = 'Declarado', 'No publicado'
LITERAL_LENGTH = 'Designación OEM'
JAGWIRE_XL = 'https://jagwire.com/products/diy-cable-kits/universal-sport-xl-brake-kit'
JAGWIRE_LINK = 'https://jagwire.com/products/diy-cable-kits/2017mountain-elite-link-brake-kit'
ODYSSEY_M2 = ('https://shop.odysseybmx.com/collections/odyssey-gyros/'
              'products/odyssey-m2-dual-upper-cable-black')


def run_columns(member_label, extra=()):
    """A run of a cable set: its length is declared or explicitly is not."""
    return [
        column('member', member_label, required=True),
        *extra,
        column('length_form', 'Forma del largo publicado', 'token',
               required=True, options=[DECLARED, UNDECLARED, LITERAL_LENGTH]),
        column('length', 'Largo publicado', 'decimal', positive=True),
        column('length_unit', 'Unidad del largo', 'token', options=[MM, IN]),
        column('length_datum', 'Entre qué puntos se mide ese largo'),
        column('length_designation', 'Designación publicada del largo'),
        column('conditions', 'Modelo, generación y condiciones'),
        column('source_url', 'Fuente', 'url'),
    ]


def run_conditions():
    return {**{k: condition('length_form', DECLARED)
               for k in ('length', 'length_unit', 'length_datum')},
            'length_designation': condition('length_form', LITERAL_LENGTH)}

THREAD, LITERAL = 'Rosca', 'Designación OEM'
MM, IN, TPI = 'mm', 'in', 'tpi'
UPPER, LOWER, OTHER_END = 'Superior', 'Inferior', 'Otro tramo'


def adjuster_conditions():
    """Every decomposed cell also carries the gate of the interface it decomposes."""
    result = {
        'diameter_unit': condition('interface_kind', THREAD),
        'pitch_unit': condition('interface_kind', THREAD),
        'diameter_mm': condition('diameter_unit', MM),
        'diameter_in': condition('diameter_unit', IN),
        'pitch_mm': condition('pitch_unit', MM),
        'pitch_tpi': condition('pitch_unit', TPI),
        'designation': condition('interface_kind', LITERAL),
    }
    for key in ('diameter_mm', 'diameter_in', 'pitch_mm', 'pitch_tpi'):
        result[key]['rows'][0].extend(condition('interface_kind', THREAD)['rows'][0])
    return result


def integrate_root_scope(definitions, templates, fixtures):
    """Own the declaration at its component; no scalar or motor exceptions."""
    cable = templates['control_cable']
    cable_runs, ends = 'control_cable_runs', 'control_cable_end_options'
    # Purpose belongs to the chosen termination. Do not keep a competing
    # whole-kit purpose, diameter, or head summary that can contradict it.
    retire(cable, ['cable_purpose', 'cable_diameter_mm', 'cable_head'])
    run_schema = definitions[cable_runs]['validation_rules']['rows_schema']
    run_schema['columns'] = [c for c in run_schema['columns'] if c['key'] != 'purpose']
    run_schema['columns'].extend([
        column('configuration', 'Conjunto o variante declarada'),
        column('diameter_mm', 'Diámetro publicado del alambre', 'decimal', unit='mm', positive=True),
        column('quantity', 'Cantidad de tramos iguales', 'integer', positive=True),
    ])
    # A published length rarely names its measurement datum. Do not demand an
    # invented datum before retaining the OEM number; an explicit datum stays
    # possible and conditional on the presence of a declared numeric length.
    for t, field in ((cable, cable_runs),
                     (templates['bmx_cable_detangler'], 'detangler_cable_configurations')):
        t['form_contract']['row_conditions']['fields'][field]['required_when'].pop('length_datum', None)
    cable['form_contract']['helpers'][cable_runs] = (
        'Largo y diámetro pertenecen a cada tramo. La función y la cabeza se '
        'declaran en sus extremos enlazados. No publicado describe la falta de '
        'cifra en la fuente; la palabra universal no implica esa ausencia ni '
        'compatibilidad. Cantidad cuenta tramos iguales, no los accesorios del kit.')
    cable['form_contract']['helpers']['pack_quantity'] = (
        'Unidades comerciales del envase; no cuenta extremos, alternativas, '
        'terminales ni filas de configuraciones.')

    end_schema = definitions[ends]['validation_rules']['rows_schema']
    next(c for c in end_schema['columns'] if c['key'] == 'run_row_id')['required'] = True
    head_kinds = ['Freno: barril transversal', 'Freno: pera de ruta',
                  'Cambio: cilíndrico longitudinal', 'Sin cabeza', 'Designación OEM']
    end_schema['columns'].extend([
        column('head_kind', 'Clase de terminación', 'token', required=True, options=head_kinds),
        column('alternative_group', 'Grupo de extremos alternativos que requiere corte'),
    ])
    first_columns = ['end_id', 'run_row_id', 'head_kind', 'purpose', 'head_profile']
    end_schema['columns'].sort(key=lambda c: first_columns.index(c['key'])
                               if c['key'] in first_columns else len(first_columns))
    # The referenced collection precedes the editor that must choose from it.
    run_field = next(f for f in cable['fields'] if f['key'] == cable_runs)
    end_field = next(f for f in cable['fields'] if f['key'] == ends)
    run_field['sort_order'], end_field['sort_order'] = end_field['sort_order'], run_field['sort_order']
    head_when = condition('head_kind', head_kinds[:2])
    end_conditions = {'allowed_when': {}, 'required_when': {}, 'value_when': {
        'purpose': [
            {'when': head_when, 'expected': {'value_type': 'token', 'value': 'Freno'}},
            {'when': condition('head_kind', head_kinds[2]),
             'expected': {'value_type': 'token', 'value': 'Cambio'}},
        ]}}
    cable['form_contract']['row_conditions']['fields'][ends] = end_conditions
    # A gyro cable also owns end interfaces. This copy gets its own identity;
    # the control_cable definition is neither broadened nor cross-family linked.
    detangler = templates['bmx_cable_detangler']
    gyro_runs, gyro_ends = 'detangler_cable_configurations', 'detangler_cable_ends'
    table(definitions, templates, gyro_ends, 'Extremos declarados del antienredos',
          ('bmx_cable_detangler',), deepcopy(end_schema['columns']),
          helper='Cada extremo apunta al ID de su tramo; no al nombre visible de otro conjunto.')
    with_cables = condition('detangler_kind', ['Gyro completo con cables', 'Cables de gyro'])
    detangler['form_contract']['allowed_when'][gyro_ends] = deepcopy(with_cables)
    detangler['form_contract']['required_when'][gyro_ends] = deepcopy(with_cables)
    detangler['form_contract']['row_conditions']['fields'][gyro_ends] = deepcopy(end_conditions)
    detangler['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'gyro_end_run', 'field': gyro_ends, 'column': 'run_row_id',
        'target_field': gyro_runs, 'label_columns': ['configuration', 'member']}]}
    definitions['detangler_kind']['allowed_values'].append('Rotor sin cables')
    mounted = condition('detangler_kind', ['Gyro completo con cables', 'Placa / tab', 'Rotor sin cables'])
    for bucket in ('allowed_when', 'required_when'):
        detangler['form_contract'][bucket]['steerer_fit'] = deepcopy(mounted)
    detangler['form_contract']['helpers'][gyro_runs] = (
        'Cada tramo mantiene su conjunto, posición y largo publicado. Universal '
        'es una designación OEM, no una medida ni una aprobación universal. '
        'Los extremos se enlazan por ID; dos superiores del mismo conjunto '
        'no son necesariamente duplicados.')

    # V-1 needs no new operator: turn a cross-scalar claim into the scoped row
    # it should have been. Retaining a documented incompatibility is legitimate;
    # marking the same forbidden construction compatible/conditional is not.
    housing = templates['control_housing']
    hf = 'control_housing_configurations'
    construction = ['Espiral', 'Hilos longitudinales con refuerzo',
                    'Hilos longitudinales sin refuerzo', 'Segmentada', 'Otra']
    statuses = ['Compatible declarado', 'Incompatible declarado', 'Condicional']
    h_conditions = run_conditions()
    h_conditions.update({
        'outer_diameter_mm': condition('diameter_form', DECLARED),
        'inner_diameter_mm': condition('diameter_form', DECLARED),
        'diameter_designation': condition('diameter_form', LITERAL_LENGTH),
        'liner_length_mm': condition('lined', True, 'boolean'),
        'conditions': condition('status', 'Condicional'),
    })
    table(definitions, templates, hf, 'Configuraciones declaradas de funda',
          ('control_housing',), run_columns('Miembro o tramo de funda', extra=[
              column('configuration', 'Conjunto o variante declarada', required=True),
              column('construction', 'Construcción de este tramo', 'token', required=True, options=construction),
              column('application', 'Uso evaluado', 'token', required=True,
                     options=['Freno', 'Cambio', 'Tija telescópica', 'Bloqueo de suspensión', 'Otro']),
              column('status', 'Compatibilidad declarada para ese uso', 'token', required=True, options=statuses),
              column('diameter_form', 'Forma del diámetro publicado', 'token', required=True,
                     options=[DECLARED, UNDECLARED, LITERAL_LENGTH]),
              column('outer_diameter_mm', 'Diámetro exterior', 'decimal', unit='mm', positive=True),
              column('inner_diameter_mm', 'Diámetro interior, si se publica', 'decimal', unit='mm', positive=True),
              column('diameter_designation', 'Designación OEM sin convertir'),
              column('lined', 'Incluye forro interior', 'boolean'),
              column('liner_length_mm', 'Largo del forro interior', 'decimal', unit='mm', positive=True),
              column('quantity', 'Cantidad de tramos iguales', 'integer', positive=True),
          ]), required=True, conditions=h_conditions,
          ordered=[['inner_diameter_mm', 'outer_diameter_mm']],
          helper=('La construcción, medida y compatibilidad se declaran por '
                  'tramo y por uso. La funda longitudinal sin refuerzo de cambio '
                  'no admite aprobación para freno. KEB con Kevlar y las fundas '
                  'segmentadas son construcciones distintas. Una medida '
                  'desconocida queda pendiente; no se completa por costumbre.'))
    hc = housing['form_contract']['row_conditions']['fields'][hf]
    # Optional OEM data stays optional. A forro may be longer than its metal
    # segments (Jagwire Elite Link), so never impose equality between lengths.
    for optional in ('length_datum', 'inner_diameter_mm', 'liner_length_mm'):
        hc['required_when'].pop(optional, None)
    hc['allowed_when'].pop('conditions')
    unsafe = condition('application', 'Freno')
    unsafe['rows'][0].extend(condition('construction', construction[2])['rows'][0])
    hc['value_when'] = {'status': [{'when': unsafe, 'expected': {
        'value_type': 'token', 'value': 'Incompatible declarado'}}]}
    next(c for c in definitions[hf]['validation_rules']['rows_schema']['columns']
         if c['key'] == 'source_url')['required'] = True
    retire(housing, ['housing_outer_diameter_mm', 'housing_length_m', 'lined',
                     'housing_application', 'housing_construction'])

    # Translate only local representation fixtures; there are no saved products.
    # Source citations are about geometry, never invented fixture dimensions.
    for c in fixtures['cases']:
        v = c['values']
        if c['template'] == 'control_cable':
            for k in ('cable_purpose', 'cable_head', 'cable_diameter_mm'):
                v.pop(k, None)
            for row in v.get(cable_runs, {}).get('rows', []):
                row['values'].pop('purpose', None)
                if row['values'].get('source_url') in (SHELDON_CABLES, ODYSSEY_GYROS):
                    row['values'].pop('source_url')
            for row in v.get(ends, {}).get('rows', []):
                value = row['values']; value['head_kind'] = 'Designación OEM'
            if c['id'] == 'cc_shift_cable_cannot_use_cable_head':
                v[ends]['rows'][0]['values']['head_kind'] = head_kinds[0]
                c['expected_blocking'] = [{'code': 'row_value_conflict', 'field': ends}]
            if c['id'] == 'cc_double_ended_wire_is_one_run_two_ends':
                for row in v[ends]['rows']:
                    row['values']['alternative_group'] = 'Cortar el extremo no usado'
        if c['id'] == 'cc_reinforced_compressionless_brake_housing':
            c['values'] = {hf: rows({
                'member': 'KEB Slick-Lube', 'configuration': 'ZHB905',
                'construction': construction[1], 'application': 'Freno',
                'status': statuses[0], 'diameter_form': DECLARED,
                'outer_diameter_mm': '5', 'length_form': DECLARED,
                'length': '10000', 'length_unit': MM, 'lined': True,
                'source_url': JAGWIRE_KEB})}
        if c['id'] == 'cc_gyro_upper_lengths_differ_by_kit':
            for row in v[gyro_runs]['rows']:
                value = row['values']
                if value['run_position'] == LOWER:
                    value['length_form'] = LITERAL_LENGTH
                    value['length_designation'] = 'Universal'

    jag_runs = rows({'member': 'Cable delantero', 'configuration': 'UCK800',
                     'length_form': DECLARED, 'length': '2000', 'length_unit': MM,
                     'quantity': '1', 'source_url': JAGWIRE_XL},
                    {'member': 'Cable trasero', 'configuration': 'UCK800',
                     'length_form': DECLARED, 'length': '2500', 'length_unit': MM,
                     'quantity': '1', 'source_url': JAGWIRE_XL})
    hbase = {'member': 'Funda', 'configuration': 'Caso de construcción',
             'construction': construction[2], 'application': 'Freno',
             'status': statuses[0], 'diameter_form': UNDECLARED,
             'length_form': UNDECLARED, 'source_url': SHELDON_CABLES}
    gyro_value = {'configuration': 'M2', 'member': 'Superior doble',
                  'run_position': UPPER, 'length_form': DECLARED,
                  'length': '440', 'length_unit': MM, 'source_url': ODYSSEY_M2}
    end_value = {'end_id': 'Terminal', 'purpose': 'Freno',
                 'head_kind': 'Designación OEM', 'lever_model': 'Odyssey M2',
                 'run_row_id': 'r1', 'source_url': ODYSSEY_M2}
    fixtures['cases'].extend([
        case('cc_root_oem_uck800_member_lengths', 'control_cable',
             {cable_runs: jag_runs}, sources=[JAGWIRE_XL]),
        case('cc_root_legacy_head_cannot_override_end_conflict', 'control_cable',
             {cable_runs: jag_runs, 'cable_head': 'Doble cabeza (universal)',
              ends: rows({'end_id': 'Prueba', 'purpose': 'Cambio',
                          'head_kind': head_kinds[0], 'head_profile': 'Barril',
                          'run_row_id': 'r1', 'source_url': SHELDON_CABLES})},
             blocking=[('row_value_conflict', ends)]),
        case('cc_root_unreinforced_brake_cannot_be_approved', 'control_housing',
             {hf: rows(hbase)}, blocking=[('row_value_conflict', hf)], sources=[SHELDON_CABLES]),
        case('cc_root_unreinforced_brake_cannot_be_conditional', 'control_housing',
             {hf: rows({**hbase, 'status': 'Condicional', 'conditions': 'Declaración contradictoria'})},
             blocking=[('row_value_conflict', hf)], sources=[SHELDON_CABLES]),
        case('cc_root_unreinforced_brake_records_rejection', 'control_housing',
             {hf: rows({**hbase, 'status': statuses[1]})}, sources=[SHELDON_CABLES]),
        case('cc_root_unreinforced_shift_not_prohibited', 'control_housing',
             {hf: rows({**hbase, 'application': 'Cambio'})}, sources=[SHELDON_CABLES]),
        case('cc_root_segmented_brake_liner_not_segment_length', 'control_housing',
             {hf: rows({**hbase, 'configuration': 'Mountain Elite Link 2017',
                        'construction': 'Segmentada', 'diameter_form': DECLARED,
                        'outer_diameter_mm': '5', 'length_form': DECLARED,
                        'length': '450', 'length_unit': MM, 'lined': True,
                        'liner_length_mm': '2000', 'source_url': JAGWIRE_LINK})},
             sources=[JAGWIRE_LINK]),
        case('cc_root_liner_length_needs_liner', 'control_housing',
             {hf: rows({**hbase, 'application': 'Cambio', 'lined': False, 'liner_length_mm': '2000'})},
             blocking=[('row_field_applicability', hf)]),
        case('cc_root_housing_inner_outer_order', 'control_housing',
             {hf: rows({**hbase, 'application': 'Cambio', 'diameter_form': DECLARED,
                        'outer_diameter_mm': '4', 'inner_diameter_mm': '5'})},
             blocking=[('row_shape', hf)]),
        case('cc_root_housing_measurement_unknown_stays_open', 'control_housing',
             {hf: rows({**hbase, 'application': 'Cambio', 'diameter_form': DECLARED})},
             pending=[('row_required_missing', hf)]),
        case('cc_root_unknown_housing_not_approved', 'control_housing',
             {hf: rows({k: val for k, val in hbase.items() if k != 'status'})},
             pending=[('row_incomplete', hf)]),
        case('cc_root_gyro_m2_ends_resolve_own_run', 'bmx_cable_detangler',
             {'detangler_kind': 'Cables de gyro', gyro_runs: rows(gyro_value),
              gyro_ends: rows(end_value)}, sources=[ODYSSEY_M2]),
        case('cc_root_gyro_end_cannot_link_display_label', 'bmx_cable_detangler',
             {'detangler_kind': 'Cables de gyro', gyro_runs: rows(gyro_value),
              gyro_ends: rows({**end_value, 'run_row_id': 'Superior doble'})},
             blocking=[('row_reference_unresolved', gyro_ends)]),
        case('cc_root_cable_spare_does_not_have_steerer_mount', 'bmx_cable_detangler',
             {'detangler_kind': 'Cables de gyro', 'steerer_fit': '1 1/8" (28.6 mm)'},
             blocking=[('field_applicability', 'steerer_fit')]),
        case('cc_root_bare_rotor_has_no_cable_runs', 'bmx_cable_detangler',
             {'detangler_kind': 'Rotor sin cables'}),
    ])


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift')
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t)
                 for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]

    # CC-1. The template already says, in its own helper on
    # compatible_brake_models, that a nominal without a pitch does not identify
    # an adjuster; yet adjuster_thread was required for exactly that part and
    # offered only M6, M10 and the unknown. The answer it demanded could not
    # identify the part it described.
    small = templates['control_small_part']
    adjuster = 'control_adjuster_threads'
    table(definitions, templates, adjuster,
          'Rosca declarada del regulador', ('control_small_part',), [
              column('scope', 'Pieza o cara declarada', required=True),
              column('interface_kind', 'Forma de la interfaz', 'token',
                     required=True, options=[THREAD, LITERAL]),
              column('diameter_unit', 'Unidad publicada del diámetro', 'token',
                     options=[MM, IN]),
              column('pitch_unit', 'Forma publicada del paso', 'token',
                     options=[MM, TPI]),
              column('diameter_mm', 'Diámetro nominal', 'decimal', unit='mm',
                     positive=True),
              column('diameter_in', 'Diámetro nominal en pulgadas, literal'),
              column('pitch_mm', 'Paso', 'decimal', unit='mm', positive=True),
              column('pitch_tpi', 'Hilos por pulgada', 'decimal', unit='tpi',
                     positive=True),
              column('designation', 'Designación publicada sin descomponer'),
              column('conditions', 'Modelo, generación y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ],
          conditions=adjuster_conditions(),
          helper=('La rosca publicada del regulador, con el diámetro y el paso '
                  'cada uno en su unidad. Un nominal sin paso no identifica el '
                  'regulador, y el paso no se deduce del nominal.'))
    # The table replaces the required scalar only where the scalar applied; the
    # rest of the family keeps its conditioning untouched.
    small['form_contract']['required_when'][adjuster] = condition(
        'control_part_kind', 'Regulador de tensión (barril)')
    small['form_contract']['allowed_when'][adjuster] = condition(
        'control_part_kind', 'Regulador de tensión (barril)')
    retire(small, ['adjuster_thread'])

    # CC-2. A gyro cable set is an upper and a lower run. Odyssey publishes an
    # upper length per kit — 425 mm for the G3, 475 mm for the GTX-S Pro — and
    # no length for the lower, which it sells as fitting most systems. So one
    # set holds members that differ, and a member may have no published length
    # at all: absence must be recordable as such, not left blank and guessed.
    # kit_members is a published definition shared by 23 families whose
    # positions are front/rear/left/right; it cannot say upper or lower and is
    # not edited here. The configuration column is what keeps two sets from
    # reading as one interchangeable pool.
    detangler = templates['bmx_cable_detangler']
    runs = 'detangler_cable_configurations'
    with_cables = condition('detangler_kind',
                            ['Gyro completo con cables', 'Cables de gyro'])
    table(definitions, templates, runs,
          'Tramos declarados del sistema antienredos', ('bmx_cable_detangler',),
          run_columns('Tramo declarado', extra=[
              column('configuration', 'Conjunto declarado', required=True),
              column('run_position', 'Posición del tramo', 'token',
                     required=True, options=[UPPER, LOWER, OTHER_END]),
              column('housing_note', 'Funda o forro declarado'),
          ]), required=False, conditions=run_conditions(),
          helper=('Una fila por tramo y por conjunto declarado. El superior y '
                  'el inferior no se miden entre los mismos puntos, así que el '
                  'largo viaja con su referencia, y un tramo universal declara '
                  'que no publica largo en vez de dejarlo en blanco. Dos '
                  'conjuntos no autorizan a combinar el superior de uno con el '
                  'inferior del otro. Un conjunto puede llevar más de un tramo '
                  'en la misma posición: Odyssey vende un superior doble.'))
    detangler['form_contract']['allowed_when'][runs] = deepcopy(with_cables)
    detangler['form_contract']['required_when'][runs] = deepcopy(with_cables)

    # CC-3. A cable set is several runs and a double-ended wire is one run with
    # two alternative ends. control_cable had a single always-required
    # cable_length_mm, so a set could not carry a length per member. Retiring
    # that use is local to this template: the definition and its other owner,
    # the published lock template, are untouched. Ends then link to the run
    # they belong to by row id, so a kit cannot cross one member's length with
    # another member's terminations.
    cable = templates['control_cable']
    cable_runs = 'control_cable_runs'
    table(definitions, templates, cable_runs,
          'Tramos declarados del cable', ('control_cable',),
          run_columns('Tramo o miembro declarado', extra=[
              column('purpose', 'Uso declarado del tramo', 'token',
                     options=['Freno', 'Cambio']),
          ]), required=True, conditions=run_conditions(),
          helper=('Un tramo por fila. Un cable suelto tiene uno; un juego tiene '
                  'uno por miembro y cada uno lleva su propio largo, o declara '
                  'que no publica ninguno. Los extremos se enlazan al tramo al '
                  'que pertenecen: no se cruzan el largo de un miembro con las '
                  'terminaciones de otro.'))
    retire(cable, ['cable_length_mm'])

    # The link column carries a row id, so it takes no vocabulary of its own.
    ends = 'control_cable_end_options'
    definitions[ends]['validation_rules']['rows_schema']['columns'].append(
        column('run_row_id', 'Tramo al que pertenece este extremo'))
    cable['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'cable_end_run', 'field': ends, 'column': 'run_row_id',
        'target_field': cable_runs, 'label_columns': ['member']}]}

    plate = {'detangler_kind': 'Placa / tab'}
    gyro = {'detangler_kind': 'Gyro completo con cables'}
    barrel = {'control_part_kind': 'Regulador de tensión (barril)'}
    fixtures['cases'].extend([
        # --- CC-1: the adjuster thread ---------------------------------------
        case('cc_adjuster_metric_thread', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5', adjuster: rows(
                 {'scope': 'Cuerpo del regulador', 'interface_kind': THREAD,
                  'diameter_unit': MM, 'diameter_mm': '6',
                  'pitch_unit': MM, 'pitch_mm': '1'})}),
        # The mixed designation Park documents, which no nominal token carries.
        case('cc_adjuster_metric_diameter_tpi_pitch', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5', adjuster: rows(
                 {'scope': 'Cuerpo del regulador', 'interface_kind': THREAD,
                  'diameter_unit': MM, 'diameter_mm': '10',
                  'pitch_unit': TPI, 'pitch_tpi': '26'})},
             sources=[PARK_THREADS]),
        case('cc_adjuster_two_pitch_units', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5', adjuster: rows(
                 {'scope': 'Cuerpo del regulador', 'interface_kind': THREAD,
                  'diameter_unit': MM, 'diameter_mm': '6', 'pitch_unit': MM,
                  'pitch_mm': '1', 'pitch_tpi': '26'})},
             blocking=[('row_field_applicability', adjuster)]),
        case('cc_adjuster_literal_has_no_pitch', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5', adjuster: rows(
                 {'scope': 'Cuerpo del regulador', 'interface_kind': LITERAL,
                  'designation': 'Designación sintética', 'pitch_unit': MM})},
             blocking=[('row_field_applicability', adjuster)]),
        # A literal designation cannot carry a decomposed figure even when the
        # unit cell is left empty: the interface gate travels with it.
        case('cc_adjuster_literal_cannot_carry_a_pitch_figure', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5', adjuster: rows(
                 {'scope': 'Cuerpo del regulador', 'interface_kind': LITERAL,
                  'designation': 'Designación sintética', 'pitch_mm': '1'})},
             blocking=[('row_field_applicability', adjuster)]),
        case('cc_adjuster_thread_absent', 'control_small_part',
             {**barrel, 'fits_housing_diameter_mm': '5'},
             pending=[('required_missing', adjuster)]),
        case('cc_boot_is_not_an_adjuster', 'control_small_part',
             {'control_part_kind': 'Fuelle / goma protectora'}),

        # --- CC-3: runs, ends and the link between them ----------------------
        # A single wire: one run, and two ends that are alternatives. Sheldon
        # publishes both brake fittings and says the double-ended wire must be
        # cut before use, so the two heads never serve at once.
        case('cc_double_ended_wire_is_one_run_two_ends', 'control_cable',
             {'cable_purpose': 'Freno', 'cable_head': 'Doble cabeza (universal)',
              cable_runs: rows(
                  {'member': 'Cable único', 'purpose': 'Freno',
                   'length_form': DECLARED, 'length': '1700',
                   'length_unit': MM, 'length_datum': 'Cabeza a punta',
                   'source_url': SHELDON_CABLES}),
              ends: rows(
                  {'end_id': 'e1', 'purpose': 'Freno', 'run_row_id': 'r1',
                   'head_profile': 'Barril, maneta de manubrio plano',
                   'source_url': SHELDON_CABLES},
                  {'end_id': 'e2', 'purpose': 'Freno', 'run_row_id': 'r1',
                   'head_profile': 'Pera, maneta de manubrio de ruta',
                   'source_url': SHELDON_CABLES})},
             sources=[SHELDON_CABLES]),
        # A set: each member keeps its own length and its own terminations.
        case('cc_kit_members_keep_their_own_lengths', 'control_cable',
             {'cable_purpose': 'Freno', cable_runs: rows(
                 {'member': 'Delantero', 'purpose': 'Freno',
                  'length_form': DECLARED, 'length': '800', 'length_unit': MM,
                  'length_datum': 'Cabeza a punta'},
                 {'member': 'Trasero', 'purpose': 'Freno',
                  'length_form': DECLARED, 'length': '1700', 'length_unit': MM,
                  'length_datum': 'Cabeza a punta'}),
              ends: rows(
                  {'end_id': 'e1', 'purpose': 'Freno', 'run_row_id': 'r1',
                   'head_profile': 'Barril', 'source_url': SHELDON_CABLES},
                  {'end_id': 'e2', 'purpose': 'Freno', 'run_row_id': 'r2',
                   'head_profile': 'Pera', 'source_url': SHELDON_CABLES})}),
        # The link is by row id; an end pointing nowhere is caught.
        case('cc_end_cannot_point_at_an_absent_run', 'control_cable',
             {'cable_purpose': 'Freno', cable_runs: rows(
                 {'member': 'Cable único', 'length_form': DECLARED,
                  'length': '1700', 'length_unit': MM}),
              ends: rows(
                  {'end_id': 'e1', 'purpose': 'Freno', 'run_row_id': 'r9',
                   'head_profile': 'Barril', 'source_url': SHELDON_CABLES})},
             blocking=[('row_reference_unresolved', ends)]),
        # A member sold as universal declares that it publishes no length,
        # which is not the same as nobody having looked it up yet.
        case('cc_universal_member_declares_no_length', 'control_cable',
             {'cable_purpose': 'Cambio', cable_runs: rows(
                 {'member': 'Cable universal', 'purpose': 'Cambio',
                  'length_form': UNDECLARED, 'source_url': ODYSSEY_GYROS}),
              ends: rows(
                  {'end_id': 'e1', 'purpose': 'Cambio', 'run_row_id': 'r1',
                   'head_profile': 'Cilíndrico pequeño, eje paralelo al alambre',
                   'source_url': SHELDON_CABLES})},
             sources=[ODYSSEY_GYROS]),
        case('cc_declared_length_needs_its_unit', 'control_cable',
             {'cable_purpose': 'Freno', cable_runs: rows(
                 {'member': 'Cable único', 'length_form': DECLARED,
                  'length': '1700'})},
             pending=[('row_required_missing', cable_runs)]),
        case('cc_undeclared_member_cannot_carry_a_length', 'control_cable',
             {'cable_purpose': 'Freno', cable_runs: rows(
                 {'member': 'Cable universal', 'length_form': UNDECLARED,
                  'length': '1700', 'length_unit': MM})},
             blocking=[('row_field_applicability', cable_runs)]),
        # Brake and shift are different fittings; cable_head stays scoped to
        # brake while every concrete end lives in its own row.
        case('cc_shift_cable_cannot_use_cable_head', 'control_cable',
             {'cable_purpose': 'Cambio',
              'cable_head': 'Barril (MTB / manetas planas)',
              cable_runs: rows(
                  {'member': 'Cable único', 'purpose': 'Cambio',
                   'length_form': DECLARED, 'length': '2100', 'length_unit': MM}),
              ends: rows(
                  {'end_id': 'e1', 'purpose': 'Cambio', 'run_row_id': 'r1',
                   'head_profile': 'Cilíndrico pequeño, eje paralelo al alambre',
                   'source_url': SHELDON_CABLES})},
             blocking=[('field_applicability', 'cable_head')],
             sources=[SHELDON_CABLES]),

        # --- control_housing --------------------------------------------------
        # Jagwire builds a 5 mm compressionless housing for braking by adding a
        # Kevlar weave. Reinforced longitudinal strand declared for brake use is
        # a real product and must be recordable.
        case('cc_reinforced_compressionless_brake_housing', 'control_housing',
             {'housing_application': 'Freno', 'housing_outer_diameter_mm': '5',
              'housing_construction': 'Hilos longitudinales con refuerzo',
              'lined': True},
             sources=[JAGWIRE_KEB]),

        # --- CC-2: detangler runs --------------------------------------------
        # Odyssey publishes 425 mm for the G3 upper and 475 mm for the GTX-S
        # Pro upper, and no length for the lower. Two kits, two figures, and a
        # member that declares no length at all.
        case('cc_gyro_upper_lengths_differ_by_kit', 'bmx_cable_detangler', {**gyro,
            'steerer_fit': '1 1/8" (28.6 mm)', runs: rows(
                {'configuration': 'Gyro G3 Kit', 'run_position': UPPER,
                 'member': 'Superior', 'length_form': DECLARED, 'length': '425',
                 'length_unit': MM, 'source_url': ODYSSEY_GYROS},
                {'configuration': 'Gyro G3 Kit', 'run_position': LOWER,
                 'member': 'Inferior', 'length_form': UNDECLARED,
                 'source_url': ODYSSEY_GYROS},
                {'configuration': 'Gyro GTX-S Pro Kit', 'run_position': UPPER,
                 'member': 'Superior', 'length_form': DECLARED, 'length': '475',
                 'length_unit': MM, 'source_url': ODYSSEY_GYROS},
                {'configuration': 'Gyro GTX-S Pro Kit', 'run_position': LOWER,
                 'member': 'Inferior', 'length_form': UNDECLARED,
                 'source_url': ODYSSEY_GYROS})},
             sources=[ODYSSEY_GYROS]),
        # Odyssey sells a dual upper cable, so one set may carry two runs in
        # the same position. This must not be rejected as a duplicate.
        case('cc_gyro_dual_upper_is_two_runs_same_position', 'bmx_cable_detangler',
             {**gyro, 'steerer_fit': '1 1/8" (28.6 mm)', runs: rows(
                 {'configuration': 'Conjunto con superior doble',
                  'run_position': UPPER, 'member': 'Superior izquierdo',
                  'length_form': UNDECLARED, 'source_url': ODYSSEY_GYROS},
                 {'configuration': 'Conjunto con superior doble',
                  'run_position': UPPER, 'member': 'Superior derecho',
                  'length_form': UNDECLARED, 'source_url': ODYSSEY_GYROS})},
             sources=[ODYSSEY_GYROS]),
        case('cc_gyro_run_without_position', 'bmx_cable_detangler', {**gyro,
            'steerer_fit': '1 1/8" (28.6 mm)', runs: rows(
                {'configuration': 'Conjunto sintético', 'member': 'Superior',
                 'length_form': UNDECLARED})},
             pending=[('row_incomplete', runs)]),
        case('cc_gyro_runs_absent', 'bmx_cable_detangler',
             {**gyro, 'steerer_fit': '1 1/8" (28.6 mm)'},
             pending=[('required_missing', runs)]),
        case('cc_plate_has_no_runs', 'bmx_cable_detangler',
             {**plate, 'steerer_fit': '1 1/8" (28.6 mm)'}),
        case('cc_plate_cannot_declare_runs', 'bmx_cable_detangler', {**plate,
            'steerer_fit': '1 1/8" (28.6 mm)', runs: rows(
                {'configuration': 'Conjunto sintético', 'run_position': UPPER,
                 'member': 'Superior', 'length_form': UNDECLARED})},
             blocking=[('field_applicability', runs)]),
    ])

    integrate_root_scope(definitions, templates, fixtures)
    for c in fixtures['cases']:
        if c['id'] == 'cc_undeclared_member_cannot_carry_a_length':
            # SQL retains one issue for each of the two forbidden cells;
            # Dart's assertion compares their code/field set.
            c['expected_sql_blocking'] = deepcopy(c['expected_blocking']) * 2
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Control cable parts reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'control-cable-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'control-cable-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
