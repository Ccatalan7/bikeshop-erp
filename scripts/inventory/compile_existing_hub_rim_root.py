#!/usr/bin/env python3
"""Adjudicate physical ownership in the independent hub/rim proposal, locally."""
from copy import deepcopy
import hashlib
import json

import compile_existing_hub_rim_catalog as proposal
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import ALWAYS, column, retire
from compile_non_drivetrain_publication import RESEARCH, write_json
from compile_product_spec_catalog import validate_contract

E = proposal.EVIDENCE
POSITION, SET, PIECES = proposal.POSITION, proposal.SET, proposal.PIECES
AXLE_KIND = 'hub_axle_mount_kind'
AXLE_DIAMETER = 'hub_axle_diameter_mm'
AXLE_DATUM = 'hub_axle_diameter_datum'
AXLE_KINDS = ['Cierre rápido', 'Eje pasante', 'Eje con tuercas',
              'Eje hembra con pernos', 'Otra interfaz OEM', 'Desconocido / sin confirmar']
SUPPLIED = 'hub_thru_axle_supplied'
SUPPLIED_REF = 'hub_supplied_thru_axle_reference'
DRIVE_KIND = 'hub_drive_receiver_kind'
DRIVE_REF = 'hub_drive_receiver_reference'
DRIVE_PRESENT = 'hub_drive_receiver_present'
DRIVE_KINDS = ['Núcleo estriado de cassette', 'Rosca para rueda libre',
               'Rosca para piñón fijo y contratuerca', 'Piñón retenido por anillo',
               'Driver BMX', 'Otra interfaz OEM', 'Desconocido / sin confirmar']
PROFILE = 'rim_bead_profile'
CLINCHER = ['Con gancho (hooked)', 'Sin gancho (hookless)']
RIM_TENSION = 'rim_spoke_tension_limits'
PIECE_COUNT = 'hub_package_piece_count'
TIRE_BED_HOLE = 'rim_tire_bed_access_hole_mm'
DRILLING = 'rim_drilling_patterns'
PARK_AXLE = 'https://www.parktool.com/en-us/product/thru-axle-tap-tap-20-2'
PROFILE_AXLE = 'https://www.profileracing.com/profiles-tech-tip-29-mind-the-gap-converting-your-axle-from-14mm-to-38/'
PARK_TENSION = 'https://www.parktool.com/en-us/blog/repair-help/wheel-tension-measurement'
PARK_HUB = 'https://www.parktool.com/en-us/blog/repair-help/hub-overhaul-and-adjustment'
PARK_FREEHUB = 'https://www.parktool.com/en-us/blog/repair-help/determining-cassette-freewheel-type'
PARK_SPOKES = 'https://www.parktool.com/en-us/blog/repair-help/determining-spoke-length-for-wheel-building'
SHELDON_FREEHUB = 'https://sheldonbrown.com/free-k7.html'
SHELDON_SPOKES = 'https://www.sheldonbrown.com/spoke-length.html'
RYDE = 'https://www.ryde.nl/andra-29-r/'
DT = 'https://www.dtswiss.com/en/components/rims-road/endurance/r-470'
TUFO = 'https://www.tufo.com/en/tubular/'
SYNTHETIC = proposal.SYNTHETIC


def conjunction(*expressions):
    result = [[]]
    for expression in expressions:
        if expression['kind'] != 'when':
            raise ValueError('Expected explicit predicates')
        result = [a + b for a in result for b in expression['rows']]
    return {'kind': 'when', 'rows': result}


def compile_catalog():
    catalog, fixtures = proposal.compile_catalog()
    defs = catalog['definitions']
    hub, rim = catalog['templates']
    h, r = hub['form_contract'], rim['form_contract']
    single = condition(POSITION, proposal.SINGLE_HUB)
    # A through axle's frame thread is not the hub's bore. Closed legacy
    # diameter vocabularies also cannot describe documented 14 mm hub axles.
    retire(hub, [proposal.AXLE, proposal.THREAD, proposal.DRIVE])
    for key in (proposal.AXLE, proposal.THREAD, proposal.DRIVE):
        h['semantic_roles'][key] = 'legacy'
    add = proposal._add
    add(defs, hub, AXLE_KIND, 'Sujeción del eje de esta maza', 'single_select',
        role='primary', options=AXLE_KINDS, allowed=single, required=single)
    add(defs, hub, AXLE_DATUM, 'Zona y datum del diámetro del eje', 'text', allowed=single,
        helper='Indica si la cifra es diámetro exterior del eje, paso por la maza '
        'u otra zona OEM. No confundir el perno del cierre rápido con el eje.')
    add(defs, hub, AXLE_DIAMETER, 'Diámetro documentado del eje', 'number',
        unit='mm', rules={'positive': True}, allowed=single)
    h['prerequisites'][AXLE_DIAMETER] = [AXLE_DATUM, E]
    thru = conjunction(single, condition(AXLE_KIND, 'Eje pasante'))
    add(defs, hub, SUPPLIED, 'Incluye eje pasante', 'boolean', role='contents',
        semantic='contents', allowed=thru)
    included = conjunction(thru, condition(SUPPLIED, True, 'boolean'))
    add(defs, hub, SUPPLIED_REF, 'Identidad del eje pasante incluido', 'text',
        role='contents', semantic='contents', allowed=included, required=included,
        helper='La rosca y longitud pertenecen a esa pieza identificada y a su '
        'montaje en cuadro/horquilla; no se infieren del paso por la maza.')
    rear = condition(POSITION, 'Trasera')
    add(defs, hub, DRIVE_PRESENT, 'Esta maza recibe la transmisión', 'boolean',
        role='primary', allowed=rear, required=rear,
        helper='Presencia documentada en esta pieza. La posición no sustituye '
        'la descripción del modelo ni autoriza por sí sola un montaje.')
    receiver_present = conjunction(rear, condition(DRIVE_PRESENT, True, 'boolean'))
    add(defs, hub, DRIVE_KIND, 'Construcción del receptor de transmisión',
        'single_select', role='primary', options=DRIVE_KINDS,
        allowed=receiver_present, required=receiver_present)
    add(defs, hub, DRIVE_REF, 'Referencia exacta del receptor de transmisión',
        'text', allowed=receiver_present, required=receiver_present,
        helper='Interfaz y edición OEM. Contrapedal describe un freno y no '
        'determina por sí solo la retención o rosca del piñón.')
    # Every scalar below describes one physical hub. Pair packaging must not
    # let the front and rear hubs silently share one axle, rotor or flange.
    own_scalars = [proposal.HEAD, proposal.ROTOR_PRESENT, proposal.FTF,
        proposal.CTF_L, proposal.CTF_R, 'bearing_system',
        'flange_pcd_left_mm', 'flange_pcd_right_mm', 'spoke_hole_diameter_mm']
    for key in own_scalars:
        proposal._gate(h, key, single)
    proposal._gate(h, proposal.ROTOR,
        conjunction(single, condition(proposal.ROTOR_PRESENT, True, 'boolean')))
    for key in (AXLE_KIND, AXLE_DATUM, SUPPLIED_REF, DRIVE_PRESENT, DRIVE_KIND, DRIVE_REF):
        h['prerequisites'][key] = [E]
    h['required_when'][E] = deepcopy(ALWAYS)
    pair = condition(POSITION, SET)
    add(defs, hub, PIECE_COUNT, 'Mazas del juego delantero y trasero', 'number',
        role='contents', semantic='contents', allowed=pair, required=pair,
        rules={'integer': True, 'min': '2', 'max': '2'},
        helper='Este alcance declara una maza delantera y una trasera. '
        'Confirma el contenido con la fuente; no se deduce del título comercial.')
    h['prerequisites'][PIECE_COUNT] = [E]
    h['row_coherence'] = {'version': 2, 'links': [], 'cardinalities': [
        {'id': 'documented_front_and_rear_hubs', 'field': PIECES, 'total_field': PIECE_COUNT}]}

    schema = defs[PIECES]['validation_rules']['rows_schema']
    schema['columns'] += [
        column('piece_identity', 'Identidad de esta maza incluida', required=True),
        column('axle_mount_kind', 'Sujeción de su eje', 'token', required=True, options=AXLE_KINDS),
        column('axle_diameter_mm', 'Diámetro documentado de su eje', 'decimal', unit='mm', positive=True),
        column('axle_diameter_datum', 'Zona y datum de ese diámetro'),
        column('thru_axle_supplied', 'Incluye eje pasante', 'boolean'),
        column('supplied_thru_axle_reference', 'Identidad del eje pasante incluido'),
        column('drive_receiver_kind', 'Construcción de su receptor', 'token', options=DRIVE_KINDS),
        column('drive_receiver_reference', 'Referencia OEM de su receptor'),
        column('rotor_mount_present', 'Tiene anclaje para disco', 'boolean', required=True),
        column('rotor_mount_type', 'Anclaje para disco', 'token',
               options=defs[proposal.ROTOR]['allowed_values']),
        column('spoke_head_interface', 'Anclaje de rayo admitido', 'token',
               options=defs[proposal.HEAD]['allowed_values']),
        column('bearing_system', 'Construcción de sus rodamientos', 'token',
               options=defs['bearing_system']['allowed_values']),
    ]
    for key, label in [('flange_pcd_left_mm', 'PCD de brida izquierda'),
                       ('flange_pcd_right_mm', 'PCD de brida derecha'),
                       ('center_to_flange_left_mm', 'Centro de maza a brida izquierda'),
                       ('center_to_flange_right_mm', 'Centro de maza a brida derecha'),
                       ('flange_to_flange_mm', 'Distancia entre bridas'),
                       ('spoke_hole_diameter_mm', 'Diámetro del agujero de rayo')]:
        schema['columns'].append(column(key, label, 'decimal', unit='mm', positive=True))
    for col in schema['columns']:
        if col['key'] in ('old_mm', 'spoke_hole_count'):
            col['required'] = True
    row_thru = condition('axle_mount_kind', 'Eje pasante')
    row_included = conjunction(row_thru, condition('thru_axle_supplied', True, 'boolean'))
    row_rear = condition('piece_position', 'Trasera')
    receiver = conjunction(
        row_rear, condition('drive_interface_present', True, 'boolean'))
    rotor = condition('rotor_mount_present', True, 'boolean')
    h['row_conditions'] = {'version': 1, 'fields': {PIECES: {
        'allowed_when': {'drive_interface_present': row_rear,
            'drive_receiver_kind': receiver,
            'drive_receiver_reference': receiver, 'rotor_mount_type': rotor,
            'thru_axle_supplied': row_thru, 'supplied_thru_axle_reference': row_included},
        'required_when': {'drive_interface_present': row_rear,
            'drive_receiver_kind': receiver,
            'drive_receiver_reference': receiver, 'rotor_mount_type': rotor,
            'supplied_thru_axle_reference': row_included,
            'axle_diameter_datum': {'kind': 'when', 'rows': [[{
                'field': 'axle_diameter_mm', 'operator': 'gt',
                'value_type': 'decimal', 'value': '0'}]]}},
    }}}

    # Tubular rims are glued/supported beds, not two clincher bead seats.
    clincher = condition(PROFILE, CLINCHER)
    r['required_when'][PROFILE] = deepcopy(ALWAYS)
    for key in (proposal.BSD, 'rim_internal_width_mm'):
        proposal._gate(r, key, clincher, required=clincher)
    proposal._gate(r, 'rim_tubeless_ready', clincher)
    proposal._gate(r, proposal.WIDTHS, clincher)
    r['helpers'][proposal.BSD] = ('Diámetro del asiento del talón de una llanta '
        'para cubierta con talón. Coincidir en este dato es necesario, pero '
        'no resuelve ancho, perfil, presión y método de montaje.')
    r['helpers']['rim_internal_width_mm'] = ('Ancho interno de la interfaz con '
        'talón según la fuente. No convertir una etiqueta ISO textual en una '
        'medición física sin identificar el estándar y su datum.')
    retire(rim, ['valve_hole'])
    r['semantic_roles']['valve_hole'] = 'legacy'
    add(defs, rim, 'rim_valve_bore_mm', 'Diámetro del agujero de válvula',
        'number', unit='mm', rules={'positive': True})
    add(defs, rim, TIRE_BED_HOLE, 'Agujero de acceso en el fondo del neumático',
        'number', unit='mm', rules={'positive': True},
        helper='Diámetro documentado en el fondo del neumático, distinto del '
        'agujero que asienta el niple. No se copian sus cotas entre sí.')
    zigzag = column('zigzag_mm', 'Zig-zag publicado', 'decimal', unit='mm')
    zigzag['validation'] = {'min': '0'}
    add(defs, rim, DRILLING, 'Patrones de taladrado de esta variante', 'json',
        rules={'rows_schema': {'version': 1, 'unique_by': [['pattern_identity']], 'columns': [
            column('pattern_identity', 'Patrón o zona física de esta variante', required=True),
            column('datum', 'Referencias radial/axial y convención OEM', required=True),
            column('radial_angle_deg', 'Ángulo radial publicado', 'decimal', unit='°'),
            column('axial_angle_deg', 'Ángulo axial publicado', 'decimal', unit='°'),
            zigzag,
            column('source_document', 'Documento y sección del patrón', required=True),
            column('source_url', 'URL de la fuente', 'url'),
        ]}}, helper='Sólo patrones de esta pieza, con el datum y la convención '
        'de la fuente. No convertir otros taladrados ofertados en hechos de este SKU.')
    add(defs, rim, 'rim_profile_height_mm', 'Altura del perfil de llanta',
        'number', unit='mm', rules={'positive': True})
    add(defs, rim, 'rim_joint_designation', 'Unión de la llanta declarada', 'text',
        helper='Designación de construcción OEM: no obliga a asignar un '
        'método metálico a una llanta de otra construcción.')
    add(defs, rim, 'rim_erd_datum', 'Definición y datum del ERD publicado', 'text',
        helper='Conserva qué plano o referencia usa el fabricante, incluyendo '
        'el niple/arandela si lo especifica. No equiparar ERD con BSD.')
    r['prerequisites']['rim_erd_mm'] = ['rim_erd_datum', E]
    add(defs, rim, RIM_TENSION, 'Límites de tensión declarados para la llanta',
        'json', role='declaration', semantic='declaration', rules={'rows_schema': {
            'version': 1, 'unique_by': [['configuration_identity']], 'columns': [
                column('configuration_identity', 'Configuración y condiciones OEM', required=True),
                column('maximum', 'Tensión máxima declarada', 'decimal', positive=True, required=True),
                column('unit', 'Unidad publicada', 'token', options=['N', 'kgf', 'lbf'], required=True),
                column('source_document', 'Documento y sección del límite', required=True),
                column('source_url', 'URL de la fuente', 'url'),
            ]}}, helper='Límite del componente para las condiciones documentadas, '
            'no tensión medida en una rueda ni lectura bruta del tensiómetro.')
    widths = defs[proposal.WIDTHS]['validation_rules']['rows_schema']
    widths['columns'].insert(0, column('configuration_identity',
        'Montaje, norma/edición o alcance OEM de este rango', required=True))
    widths['unique_by'] = [['configuration_identity']]
    for key in ('rim_valve_bore_mm', TIRE_BED_HOLE, 'rim_profile_height_mm',
                'rim_joint_designation', 'rim_erd_datum'):
        r['prerequisites'][key] = [E]
    r['required_when'][E] = deepcopy(ALWAYS)

    updated = deepcopy(fixtures['cases'])
    for item in updated:
        values = item['values']
        if item['id'] == 'hu_a_pair_declares_the_receiver_of_its_rear_piece':
            item['predecessor_values'] = deepcopy(values)
            # The old global receiver remains legacy. The rear occurrence
            # carries this literal synthetic declaration instead.
            values[PIECES]['rows'][1]['values'].update(
                drive_receiver_kind='Otra interfaz OEM',
                drive_receiver_reference='Receptor sintético del conjunto trasero')
        if item['id'] == 'hu_a_quick_release_hub_has_no_thru_axle_thread':
            item['predecessor_values'] = deepcopy(values)
            item['id'] = 'hu_a_quick_release_hub_cannot_supply_a_thru_axle_reference'
            values.update({AXLE_KIND: 'Cierre rápido', SUPPLIED_REF: 'Eje sintético'})
            item['expected_blocking'] = [{'code': 'field_applicability', 'field': SUPPLIED_REF}]
        if item['template'] == 'rim' and proposal.BSD in values:
            values[PROFILE] = 'Con gancho (hooked)'
    fixtures['cases'] = updated + root_cases()
    # Local SQL diagnostics confirmed the same blocking fields and messages;
    # the published validator reports these two schema errors as constraints.
    for item in fixtures['cases']:
        if item['id'] in ('ri_an_inverted_width_range_blocks',
                          'rir_a_tensiometer_scale_is_not_a_force_unit'):
            item['expected_sql_blocking'] = [
                {**issue, 'code': 'field_constraint'} for issue in item['expected_blocking']]
    fixtures['pending_cases'] = [p for p in fixtures['pending_cases']
        if p['id'] != 'hub_bmx_solid_axle_diameters_are_outside_the_published_domain']
    for t in catalog['templates']:
        keys = {f['key'] for f in t['fields']}
        validate_contract(t['key'], t['form_contract'], defs, keys)
    catalog['stats'] = {'templates': 2, 'definitions': len(defs),
                       'field_uses': sum(len(t['fields']) for t in catalog['templates'])}
    catalog['source_urls'] += [
        PARK_AXLE,
        PROFILE_AXLE,
        PARK_TENSION,
        PARK_HUB,
        PARK_FREEHUB,
        PARK_SPOKES,
        SHELDON_FREEHUB,
        SHELDON_SPOKES,
        RYDE,
        DT,
        TUFO,
    ]
    catalog['root_adjudication'] = 'Per-piece ownership, measured axle datum and rim construction precede dependent claims.'
    return catalog, fixtures


def root_cases():
    result = []
    def hub(name, values, **kwargs):
        return case('hur_' + name, 'hub', values, **kwargs)
    def rim(name, values, **kwargs):
        return case('rir_' + name, 'rim', values, **kwargs)
    for key, value in [(AXLE_KIND, 'Eje pasante'), (proposal.HEAD, 'J-Bend'),
        (proposal.ROTOR_PRESENT, True), (proposal.FTF, '58'),
        (proposal.CTF_L, '35'), (proposal.CTF_R, '23'),
        ('flange_pcd_left_mm', '58'), ('flange_pcd_right_mm', '58'),
        ('spoke_hole_diameter_mm', '2.6'), ('bearing_system', 'Bolas sueltas')]:
        result.append(hub('pair_rejects_global_' + key,
            {POSITION: SET, key: value, E: SYNTHETIC},
            blocking=[('field_applicability', key)]))
    def piece(position, **extra):
        return {'piece_position': position, 'piece_identity': 'Synthetic ' + position,
                'evidence_source': 'Synthetic package', **extra}
    result += [
        hub('front_hub_rejects_a_rear_drive_receiver', {
            POSITION: 'Delantera', DRIVE_PRESENT: True, DRIVE_KIND: 'Otra interfaz OEM',
            DRIVE_REF: 'Declaración sintética: no certifica montaje', E: SYNTHETIC},
            blocking=[('field_applicability', DRIVE_PRESENT),
                      ('field_applicability', DRIVE_KIND),
                      ('field_applicability', DRIVE_REF)]),
        hub('an_absent_receiver_blocks_its_reference_on_one_hub', {
            POSITION: 'Trasera', DRIVE_PRESENT: False,
            DRIVE_REF: 'Synthetic receiver', E: SYNTHETIC},
            blocking=[('field_applicability', DRIVE_REF)]),
        hub('an_unconfirmed_receiver_keeps_its_reference_pending', {
            POSITION: 'Trasera', DRIVE_REF: 'Synthetic receiver', E: SYNTHETIC},
            pending=[('field_applicability_pending', DRIVE_REF)]),
        hub('a_front_and_rear_package_with_one_piece_stays_pending', {
            POSITION: SET, PIECE_COUNT: '2', E: SYNTHETIC,
            PIECES: rows(piece('Trasera'))}, pending=[('row_cardinality_pending', PIECES)]),
        hub('two_unique_ends_match_the_declared_package', {
            POSITION: SET, PIECE_COUNT: '2', E: SYNTHETIC,
            PIECES: rows(piece('Delantera'), piece('Trasera'))}),
        hub('pair_preserves_two_axles_and_rotor_mounts', {POSITION: SET, E: SYNTHETIC,
            PIECES: rows(piece('Delantera', axle_mount_kind='Eje pasante',
                axle_diameter_mm='15', axle_diameter_datum='Paso declarado',
                rotor_mount_present=True, rotor_mount_type='Centerlock'),
                piece('Trasera', axle_mount_kind='Eje con tuercas',
                axle_diameter_mm='14', axle_diameter_datum='Diámetro exterior del eje',
                rotor_mount_present=False))}),
        hub('piece_without_disc_cannot_carry_its_mount', {POSITION: SET,
            PIECES: rows(piece('Delantera', rotor_mount_present=False,
                rotor_mount_type='6 pernos'))}, blocking=[('row_field_applicability', PIECES)]),
        hub('piece_without_receiver_cannot_claim_one', {POSITION: SET,
            PIECES: rows(piece('Delantera', drive_interface_present=False,
                drive_receiver_kind='Driver BMX'))}, blocking=[('row_field_applicability', PIECES)]),
        hub('front_piece_cannot_claim_a_drive_receiver', {POSITION: SET,
            PIECES: rows(piece('Delantera', drive_interface_present=True))},
            blocking=[('row_field_applicability', PIECES)]),
        hub('piece_diameter_requires_its_own_datum', {POSITION: SET,
            PIECES: rows(piece('Trasera', axle_diameter_mm='14'))},
            pending=[('row_required_missing', PIECES)]),
        hub('a_documented_14mm_axle_does_not_need_a_legacy_token', {
            POSITION: 'Trasera', AXLE_KIND: 'Eje con tuercas', AXLE_DIAMETER: '14',
            AXLE_DATUM: 'Diámetro exterior del eje', E: PROFILE_AXLE}, sources=[PROFILE_AXLE]),
        hub('a_diameter_alone_does_not_name_its_interface', {
            POSITION: 'Trasera', AXLE_DIAMETER: '13', E: SYNTHETIC},
            pending=[('prerequisite_missing', AXLE_DIAMETER)]),
        hub('an_unsupplied_thru_axle_has_no_supplied_reference', {
            POSITION: 'Delantera', AXLE_KIND: 'Eje pasante', SUPPLIED: False,
            SUPPLIED_REF: 'Synthetic axle', E: SYNTHETIC},
            blocking=[('field_applicability', SUPPLIED_REF)], sources=[PARK_AXLE]),
    ]
    for key, value in [(proposal.BSD, '622'), ('rim_internal_width_mm', '20'),
                       ('rim_tubeless_ready', True)]:
        result.append(rim('tubular_disallows_clincher_' + key,
            {PROFILE: 'Tubular / de pegar', key: value, E: TUFO},
            blocking=[('field_applicability', key)], sources=[TUFO]))
    result += [
        rim('nipple_seat_and_tire_bed_holes_have_different_owners', {
            proposal.RIM_HOLE: '5.5', TIRE_BED_HOLE: '9', E: RYDE}, sources=[RYDE]),
        rim('drilling_preserves_its_three_distinct_oem_figures', {DRILLING: rows({
            'pattern_identity': 'Patrón declarado para la variante de ejemplo',
            'datum': 'Convención Angle rad/axi y ZIG ZAG de la ficha Ryde',
            'radial_angle_deg': '8', 'axial_angle_deg': '2', 'zigzag_mm': '2',
            'source_document': 'Andra 29 R, apartado de perforación', 'source_url': RYDE})}, sources=[RYDE]),
        rim('an_angle_without_its_datum_stays_pending', {DRILLING: rows({
            'pattern_identity': 'Synthetic pattern', 'radial_angle_deg': '8',
            'source_document': 'Synthetic document'})}, pending=[('row_incomplete', DRILLING)]),
        rim('missing_bead_profile_is_pending', {E: SYNTHETIC},
            pending=[('required_missing', PROFILE)]),
        rim('one_erd_keeps_the_oem_datum', {'rim_erd_mm': '596',
            'rim_erd_datum': 'ID -2mm publicado por Ryde', E: RYDE}, sources=[RYDE]),
        rim('erd_without_its_datum_is_pending', {'rim_erd_mm': '596', E: SYNTHETIC},
            pending=[('prerequisite_missing', 'rim_erd_mm')]),
        rim('rim_limit_is_not_a_measured_wheel_tension', {RIM_TENSION: rows({
            'configuration_identity': 'Andra 29 R, alcance de la ficha OEM',
            'maximum': '1400', 'unit': 'N', 'source_document': 'MAX. SPOKE TENSION',
            'source_url': RYDE})}, sources=[PARK_TENSION, RYDE]),
        rim('a_tensiometer_scale_is_not_a_force_unit', {RIM_TENSION: rows({
            'configuration_identity': 'Synthetic limit', 'maximum': '23',
            'unit': 'Lectura TM-1', 'source_document': 'Synthetic document'})},
            blocking=[('row_shape', RIM_TENSION)]),
    ]
    return result


if __name__ == '__main__':
    catalog, cases = compile_catalog()
    path = RESEARCH / 'existing-hub-rim-catalog-2026-09-08.json'
    write_json(path, catalog)
    cases['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-hub-rim-cases-2026-09-08.json', cases)
    print(json.dumps({**catalog['stats'], 'cases': len(cases['cases']),
                      'pending_cases': len(cases['pending_cases']), 'writes': 0}))
