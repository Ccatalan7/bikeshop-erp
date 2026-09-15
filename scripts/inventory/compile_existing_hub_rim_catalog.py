#!/usr/bin/env python3
"""Compile an unpublished, source-scoped successor for the bound hubs and rims.

No DB, migration, product filling, assignment or live UI operation. A rim is
identified by its bead seat diameter, its widths and its own drilling; a hub by
its ends, its axle, its spoke anchor and its drive receiver. Wheel-build
outcomes -- dish, tension, truing -- belong to the assembled wheel and never to
the nominal specification of a hub or a rim.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column, retire
from compile_product_spec_catalog import validate_contract

FAMILIES = ('hub', 'rim')
PREIMAGE = RESEARCH / 'existing-hub-rim-preimage-2026-09-08.json'
PREIMAGE_SHA = 'd9ac12757faa468483404d46a6624d22f367db4c605979852ee2d0ee1c124dfe'
SHELDON_WHEEL = 'https://www.sheldonbrown.com/wheelbuild.html'
SHELDON_SIZE = 'https://www.sheldonbrown.com/tire-sizing.html'
PARK = 'https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection'
WEINMANN = 'https://www.weinmanntek.com/technology/6/6'
NOVATEC = ('https://www.messingschlager.com/en/products/disc-brake-hubs_t50/'
           'novatec-d042sb-rear-disc-brake-hub_a326221-S')
SYNTHETIC = 'https://example.invalid/synthetic'

EVIDENCE = 'spec_evidence_source'
LEGACY_POSITION = 'wheel_position'
POSITION = 'hub_package_position'
SET = 'Juego delantera + trasera'
OLD = 'hub_old_mm'
HOLES = 'spoke_hole_count'
DRIVE = 'rear_drive_interface'
PIECES = 'hub_package_pieces'
HEAD = 'hub_spoke_head_interface'
ROTOR_PRESENT = 'hub_rotor_mount_present'
ROTOR = 'rotor_mount_type'
FTF = 'hub_flange_to_flange_mm'
CTF_L = 'center_to_flange_left_mm'
CTF_R = 'center_to_flange_right_mm'
AXLE = 'axle_type'
THREAD = 'thru_axle_thread'

BSD = 'bead_seat_diameter_mm'
TRACK = 'brake_track'
INDICATOR = 'rim_brake_wear_indicator'
RIM_HOLE = 'rim_spoke_hole_diameter_mm'
WIDTHS = 'tire_width_range_mm'
SYMMETRY = 'rim_symmetry'
OFFSET = 'rim_asymmetric_offset_mm'

SINGLE_HUB = ['Delantera', 'Trasera', 'Universal']


def _add(definitions, template, key, label, kind, *, role='measurement',
         semantic='compatibility', unit=None, options=(), rules=None,
         allowed=ALWAYS, required=NEVER, helper=None):
    if key in definitions:
        raise ValueError('Refuse to overwrite a definition: ' + key)
    definitions[key] = new_definition(key, label, kind, (template['key'],),
                                      unit=unit, options=options, rules=rules)
    add_field(template, key, role, semantic, allowed=allowed,
              required=required, helper=helper)


def _gate(contract, key, expression, *, required=None):
    contract['allowed_when'][key] = deepcopy(expression)
    if required is not None:
        contract['required_when'][key] = deepcopy(required)


def compile_catalog():
    for path, expected in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                           (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Pinned input changed: ' + path.name)
    base = json.loads(CATALOG.read_text())
    before = json.loads(PREIMAGE.read_text())
    published = {d['key']: d for d in before['existing_definitions']}
    names = {t['key']: t['name'] for t in before['templates']}

    templates, definitions = {}, {}
    for key in FAMILIES:
        template = deepcopy(next(t for t in base['templates'] if t['key'] == key))
        template['name'] = names[key]
        templates[key] = template
        for field in template['fields']:
            definitions.setdefault(field['key'],
                                   deepcopy(base['definitions'][field['key']]))
    # Published identities stay byte-exact; only their template usage changes.
    for key, actual in published.items():
        if key not in definitions:
            continue
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
            'validation_rules')}
        definitions[key].update(origin='existing', used_by=[
            f for f in FAMILIES
            if any(x['key'] == key for x in templates[f]['fields'])])

    _correct_hub(definitions, templates['hub'])
    _correct_rim(definitions, templates['rim'])

    for key in FAMILIES:
        template = templates[key]
        keys = {f['key'] for f in template['fields']}
        validate_contract(key, template['form_contract'], definitions, keys)
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definitions in hub/rim packet')

    catalog = {**base, 'title': 'Hub and rim interfaces, ends and own geometry',
               'templates': [templates[k] for k in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'source_urls': [SHELDON_WHEEL, SHELDON_SIZE, PARK, WEINMANN,
                               NOVATEC],
               'stats': {'templates': len(FAMILIES),
                         'definitions': len(definitions),
                         'field_uses': sum(len(t['fields'])
                                           for t in templates.values())}}
    fixtures = {'cases': _cases(), 'pending_cases': _pending()}
    return catalog, fixtures


def _correct_hub(definitions, template):
    c = template['form_contract']
    # The published position vocabulary has three options and is shared with
    # four other families. A two-hub package is not one of them, so the token
    # is cloned into a hub-scoped successor instead of altering the global one.
    retire(template, [LEGACY_POSITION])
    c['semantic_roles'][LEGACY_POSITION] = 'legacy'
    _add(definitions, template, POSITION,
         'Posición de las mazas de este envase', 'single_select',
         role='primary', semantic='intrinsic', required=ALWAYS,
         options=['Delantera', 'Trasera', 'Universal', SET],
         helper='Qué trae este envase. Un juego de dos mazas no tiene una '
         'sola posición, ni un solo ancho, ni una sola perforación.')
    pair = condition(POSITION, ['Trasera', SET])
    _gate(c, DRIVE, pair, required=pair)
    single = condition(POSITION, SINGLE_HUB)
    _gate(c, OLD, single, required=single)
    _gate(c, HOLES, single, required=single)
    c['helpers'][OLD] = ('Ancho entre punteras de esta maza. Un envase de dos '
        'mazas no tiene un solo ancho: sus piezas van en su propia tabla.')
    _add(definitions, template, PIECES, 'Piezas de este envase', 'json',
         role='contents', semantic='contents',
         allowed=condition(POSITION, SET), required=condition(POSITION, SET),
         rules={'rows_schema': {'version': 1,
             'unique_by': [['piece_position']], 'columns': [
                 column('piece_position', 'Posición de esta pieza', 'token',
                        required=True, options=['Delantera', 'Trasera']),
                 column('old_mm', 'Ancho entre punteras de esta pieza',
                        'decimal', unit='mm', positive=True),
                 column('spoke_hole_count', 'Perforaciones de esta pieza',
                        'integer', positive=True),
                 column('drive_interface_present',
                        'Esta pieza recibe la transmisión', 'boolean'),
                 column('evidence_source', 'Documento o envase de esta pieza',
                        required=True),
                 column('source_url', 'URL de esa fuente, si existe', 'url'),
             ]}},
         helper='Sólo las piezas realmente incluidas en este envase. No es un '
         'catálogo de variantes OEM ni una rueda armada.')

    # Sheldon: the flange hole must pass the thread and the elbow must seat
    # against the flange. Which spoke head the flange accepts is a hub fact.
    _add(definitions, template, HEAD, 'Anclaje de rayo que admite esta maza',
         'single_select', role='primary',
         options=['J-Bend', 'Straight Pull', 'Otro anclaje OEM'],
         helper='Anclaje que aceptan las bridas. Ausente significa sin '
         'confirmar: no se deduce de la marca ni del número de rayos.')
    # Restoring the published rotor vocabulary costs nothing: the engine reads
    # 'Desconocido / sin confirmar' as an absent cell, so the token the frozen
    # base added was inert and only broke the shared-definition guard.
    _add(definitions, template, ROTOR_PRESENT,
         'Esta maza tiene anclaje para disco', 'boolean', role='primary',
         semantic='intrinsic')
    _gate(c, ROTOR, condition(ROTOR_PRESENT, True, 'boolean'))
    _add(definitions, template, FTF, 'Distancia entre bridas', 'number',
         unit='mm', rules={'positive': True},
         helper='Cota publicada entre bridas (FTF). No depende del datum: es '
         'la suma de las dos distancias al centro, no una de ellas.')
    c['helpers'][CTF_L] = ('Distancia desde el centro de la rueda hasta la '
        'brida izquierda. Una cota OEM medida desde la contratuerca se '
        'convierte antes de escribirla aquí; no se copia.')
    c['helpers'][CTF_R] = ('Distancia desde el centro de la rueda hasta la '
        'brida derecha, con el mismo datum que la izquierda.')
    for key in (HEAD, FTF, CTF_L, CTF_R, 'flange_pcd_left_mm',
                'flange_pcd_right_mm', 'spoke_hole_diameter_mm'):
        c['prerequisites'][key] = [EVIDENCE]


def _correct_rim(definitions, template):
    c = template['form_contract']
    c['helpers'][BSD] = ('Diámetro del asiento del talón en mm. Es el número '
        'que decide si un neumático entra. Los rótulos en pulgadas no se '
        'convierten solos: 26, 24 y 20 nombran varios diámetros distintos.')
    c['helpers']['rim_internal_width_mm'] = (
        'Ancho interior entre pestañas, que es el primer número ISO de la '
        'llanta. No es el ancho exterior ni el ancho del neumático montado.')
    # Weinmann publishes the nipple hole diameter per model; the wheel is built
    # against it and the spoke/nipple families own the mating part.
    _add(definitions, template, RIM_HOLE, 'Diámetro del agujero de niple',
         'number', unit='mm', rules={'positive': True},
         helper='Agujero de la llanta para el niple, publicado por el '
         'fabricante. No es el calibre del rayo ni la medida de la llave.')
    # A wear indicator exists only where there is a braking surface.
    _add(definitions, template, INDICATOR,
         'Indicador de desgaste del flanco de freno', 'text',
         allowed=condition(TRACK, True, 'boolean'),
         helper='Designación literal del fabricante para su indicador. '
         'Ausente significa sin confirmar, no ausencia de indicador.')
    for key in (RIM_HOLE, INDICATOR):
        c['prerequisites'][key] = [EVIDENCE]

    schema = definitions[WIDTHS]['validation_rules']['rows_schema']
    if definitions[WIDTHS].get('origin') != 'new':
        raise ValueError('Refuse to reshape a published definition: ' + WIDTHS)
    columns = []
    for existing in schema['columns']:
        if existing['key'] == 'source_url':
            existing = {**existing, 'label': 'URL de esa fuente, si existe'}
            existing.pop('required', None)
            columns.append(column('evidence_source',
                                  'Documento o envase de este rango',
                                  required=True))
        columns.append(existing)
    schema['columns'] = columns


def _cases():
    def hub(id_, values, **kwargs):
        return case('hu_' + id_, 'hub', values, **kwargs)

    def rim(id_, values, **kwargs):
        return case('ri_' + id_, 'rim', values, **kwargs)

    def piece(position, **extra):
        return {'piece_position': position, 'evidence_source':
                'Envase del juego', **extra}
    front = {POSITION: 'Delantera', OLD: '100', HOLES: '32',
             AXLE: 'Cierre rápido 9 mm (delantero)', EVIDENCE: SYNTHETIC}
    rear = {POSITION: 'Trasera', OLD: '135', HOLES: '36',
            AXLE: 'Cierre rápido 10 mm (trasero)', EVIDENCE: SYNTHETIC,
            DRIVE: 'Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v '
                   'sólo según filas C-731; LINKGLIDE según C-649)'}
    plain_rim = {BSD: '622', 'rim_internal_width_mm': '19', HOLES: '32',
                 EVIDENCE: SYNTHETIC}
    return [
        hub('a_front_hub_carries_its_own_ends', front),
        hub('a_hub_without_its_package_position_is_pending',
            {EVIDENCE: SYNTHETIC, 'bearing_system': 'Rodamientos sellados'},
            pending=[('required_missing', POSITION)]),
        hub('a_rear_hub_declares_its_drive_receiver', rear),
        hub('a_threaded_freewheel_hub_is_not_a_cassette_body', {
            **rear, DRIVE: 'Rueda libre roscada 1.37" x 24 tpi'}),
        hub('a_coaster_hub_declares_its_receiver', {
            **rear, DRIVE: 'Contrapedal'}),
        hub('a_pair_declares_the_receiver_of_its_rear_piece', {
            POSITION: SET, EVIDENCE: SYNTHETIC, DRIVE: 'Contrapedal',
            PIECES: rows(piece('Delantera', old_mm='100', spoke_hole_count='36',
                               drive_interface_present=False),
                         piece('Trasera', old_mm='135', spoke_hole_count='36',
                               drive_interface_present=True))}),
        hub('a_pair_cannot_carry_one_scalar_width', {
            POSITION: SET, EVIDENCE: SYNTHETIC, OLD: '100'},
            blocking=[('field_applicability', OLD)]),
        hub('a_pair_cannot_carry_one_scalar_hole_count', {
            POSITION: SET, EVIDENCE: SYNTHETIC, HOLES: '36'},
            blocking=[('field_applicability', HOLES)]),
        hub('the_same_piece_twice_blocks', {
            POSITION: SET, EVIDENCE: SYNTHETIC,
            PIECES: rows(piece('Trasera', old_mm='135'),
                         piece('Trasera', old_mm='142'))},
            blocking=[('row_shape', PIECES)]),
        hub('a_piece_without_its_evidence_is_pending', {
            POSITION: SET, EVIDENCE: SYNTHETIC, PIECES: rows(
                {'piece_position': 'Trasera', 'old_mm': '135'})},
            pending=[('row_incomplete', PIECES)]),
        hub('a_single_hub_cannot_list_package_pieces', {
            **front, PIECES: rows(piece('Delantera', old_mm='100'))},
            blocking=[('field_applicability', PIECES)]),
        hub('no_disc_anchor_forbids_a_rotor_mount', {
            **front, ROTOR_PRESENT: False, ROTOR: '6 pernos'},
            blocking=[('field_applicability', ROTOR)]),
        hub('an_undeclared_disc_anchor_leaves_the_mount_pending', {
            **front, ROTOR: 'Centerlock'},
            pending=[('field_applicability_pending', ROTOR)]),
        hub('a_quick_release_hub_has_no_thru_axle_thread', {
            **front, THREAD: 'M12 x 1.0'},
            blocking=[('field_applicability', THREAD)]),
        hub('flange_distance_and_centre_distances_coexist', {
            **rear, FTF: '58.4', CTF_L: '36.0', CTF_R: '22.4',
            'flange_pcd_left_mm': '58', 'flange_pcd_right_mm': '58',
            'spoke_hole_diameter_mm': '2.6'}, sources=[NOVATEC]),
        hub('a_spoke_anchor_without_evidence_is_pending', {
            POSITION: 'Delantera', HEAD: 'Straight Pull'},
            pending=[('prerequisite_missing', HEAD)], sources=[SHELDON_WHEEL]),
        hub('legacy_position_spacing_holes_and_driver_are_preserved', {
            **front, 'hub_spacing_mm': '100', 'spoke_holes': '32',
            'freehub_type': 'Shimano HG', LEGACY_POSITION: 'Delantera'}),
        rim('a_rim_is_identified_by_its_bead_seat_diameter', plain_rim,
            sources=[SHELDON_SIZE]),
        rim('one_bead_seat_diameter_answers_three_market_names', {
            **plain_rim, 'rim_etrto': '19-622'},
            sources=[SHELDON_SIZE, WEINMANN]),
        rim('a_braking_surface_carries_its_wear_indicator', {
            **plain_rim, TRACK: True, INDICATOR: 'Wear indicator line'},
            sources=[WEINMANN]),
        rim('a_rim_without_a_braking_surface_has_no_indicator', {
            **plain_rim, TRACK: False, INDICATOR: 'Wear indicator line'},
            blocking=[('field_applicability', INDICATOR)], sources=[WEINMANN]),
        rim('an_undeclared_braking_surface_leaves_it_pending', {
            **plain_rim, INDICATOR: 'Safety line'},
            pending=[('field_applicability_pending', INDICATOR)]),
        rim('the_offset_needs_an_asymmetric_rim', {
            **plain_rim, SYMMETRY: 'Simétrica', OFFSET: '3'},
            blocking=[('field_applicability', OFFSET)]),
        rim('an_asymmetric_rim_declares_its_offset', {
            **plain_rim, SYMMETRY: 'Asimétrica', OFFSET: '3'},
            sources=[WEINMANN]),
        rim('a_width_range_documented_by_the_package', {
            **plain_rim, WIDTHS: rows({
                'width_min_mm': '25', 'width_max_mm': '50',
                'evidence_source': 'Etiqueta del envase'})},
            sources=[SHELDON_SIZE]),
        rim('a_width_range_without_any_evidence_is_pending', {
            **plain_rim, WIDTHS: rows({
                'width_min_mm': '25', 'width_max_mm': '50'})},
            pending=[('row_incomplete', WIDTHS)]),
        rim('an_inverted_width_range_blocks', {
            **plain_rim, WIDTHS: rows({
                'width_min_mm': '50', 'width_max_mm': '25',
                'evidence_source': 'Etiqueta del envase'})},
            blocking=[('row_shape', WIDTHS)]),
        rim('the_nipple_hole_diameter_is_a_rim_fact', {
            **plain_rim, RIM_HOLE: '4.5'}, sources=[WEINMANN]),
        rim('a_nipple_hole_without_evidence_is_pending', {
            BSD: '622', RIM_HOLE: '4.5'},
            pending=[('prerequisite_missing', RIM_HOLE)], sources=[WEINMANN]),
        rim('legacy_size_valve_and_holes_are_preserved', {
            **plain_rim, 'wheel_size': '29"', 'spoke_holes': '32',
            'valve_type': 'Presta (francesa)'}),
    ]


def _pending():
    return [
        {'id': 'hub_convertible_end_caps_need_a_configuration_table',
         'required_result': 'unknown_without_configuration_table',
         'reason': 'One captured hub declares two axle configurations; a '
                   'single scalar end cannot hold both and no table exists.'},
        {'id': 'hub_locknut_referenced_flange_figures_are_not_converted',
         'required_result': 'unknown_without_arithmetic_coherence',
         'reason': 'OEM sheets publish lock-nut to flange distances; the '
                   'engine compares ordered pairs, never sums.'},
        {'id': 'rim_etrto_text_contradicting_the_bead_seat_diameter',
         'required_result': 'unknown_without_parsed_declaration',
         'reason': 'The ETRTO string is free text; nothing compares it with '
                   'the typed diameter and internal width.'},
        {'id': 'legacy_inch_size_cannot_be_converted_to_a_diameter',
         'required_result': 'identity_pending',
         'reason': 'Sheldon lists several bead seat diameters for 20, 24 and '
                   '26 inch marks; the legacy token cannot be filled '
                   'automatically.'},
        {'id': 'hub_bmx_solid_axle_diameters_are_outside_the_published_domain',
         'required_result': 'identity_pending',
         'reason': 'Two captured hubs declare 13 and 14 mm solid axles; the '
                   'published axle vocabulary stops at 3/8 inch and cloning a '
                   'second shared definition is not warranted by two rows.'},
        {'id': 'hub_and_rim_wheelbuild_requires_model_scoped_evidence',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Spoke length, dish and tension are outcomes of a built '
                   'wheel, never nominal facts of a hub or a rim.'},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-hub-rim-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-hub-rim-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'production_writes': False, 'fill': False}))
