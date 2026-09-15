#!/usr/bin/env python3
"""Compile four suspension/headset templates. No product or database writes.

Every table row is a scoped declaration copied from the manufacturer, never a
mechanical approval. A published figure keeps the unit it was published in: no
conversion, and no typical clearance turned into a universal rule.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_wheel_small_parts_catalog import column, retire, table
from compile_wheel_small_parts_catalog import compile_catalog as wheel_catalog
from compile_product_spec_catalog import validate_contract

FAMILIES = ('fork', 'rear_shock', 'spacer', 'headset_small_part')
ALWAYS, NEVER = {'kind': 'always'}, {'kind': 'never'}
# FOX documents FLOAT DPS / FLOAT X in inches (7.875 x 2.00, 8.50 x 2.50) while
# current shocks are metric. Both notations are live, so the unit travels with
# the figure instead of being decided once for the family.
FOX_SPEC = 'https://ridefox.com/products/fox-float-dps-performance'
WOLF_PLUG = 'https://www.wolftoothcomponents.com/products/compression-plug'
WOLF_SPACERS = 'https://www.wolftoothcomponents.com/collections/misc-components/products/wolf-tooth-headset-spacers'
PARK_STAR = 'https://www.parktool.com/en-us/blog/repair-help/star-fangled-nut-and-expansion-plug-installation'
CERVELO_FORK = 'https://cervelo.cdn.prismic.io/cervelo/ffe12d7a-81fc-499c-981e-65904298ad93_fork_owners_manualv3.pdf'


def integrate_root_boundaries(templates, definitions, fixtures):
    """Close source-backed cardinality and prerequisite gaps before publishing."""
    fork = templates['fork']
    reviewed_wheel, _ = wheel_catalog()
    interface = 'wheel_part_interfaces'
    # This definition is now published. Reuse its exact shape, including the
    # independence of diameter and pitch; never add an option to a shared enum.
    definitions[interface] = deepcopy(reviewed_wheel['definitions'][interface])
    add_field(fork, interface, 'declaration', 'compatibility',
              helper='Interfaz real de retención declarada por el fabricante; '
                     'no se deduce la rosca del diámetro del eje.')
    wheel_t = next(t for t in reviewed_wheel['templates'] if t['key'] == 'hub_axle')
    fork['form_contract'].setdefault('row_conditions', {'version': 1, 'fields': {}})[
        'fields'][interface] = deepcopy(wheel_t['form_contract']['row_conditions']['fields'][interface])
    retire(fork, ['thru_axle_thread'])

    # An end belongs to one size/configuration. Stable IDs prevent crossing the
    # mounting hardware of different configurations with the same end label.
    shock = templates['rear_shock']
    ends, size = 'shock_end_configurations', 'shock_size_declarations'
    schema = definitions[ends]['validation_rules']['rows_schema']
    schema['columns'].insert(0, column('size_row_id', 'Configuración del amortiguador', required=True))
    schema['unique_by'] = [['size_row_id', 'end_position']]
    shock['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'shock_end_size', 'field': ends, 'column': 'size_row_id',
        'target_field': size, 'label_columns': ['configuration']} ]}
    # Preserve the prior end fixtures' assertion, adapting only their row
    # ownership to the successor schema. No source value is manufactured.
    for c in fixtures['cases']:
        if c['template'] == 'rear_shock' and ends in c['values']:
            for row in c['values'][ends]['rows']:
                row['values']['size_row_id'] = 'r1'

    spacer = templates['spacer']
    members = 'spacer_components'
    table(definitions, templates, members, 'Separadores incluidos y sus medidas',
          ['spacer'], [
              column('component', 'Pieza o presentación', required=True),
              column('quantity', 'Cantidad de esta pieza', 'integer', required=True, positive=True),
              column('system', 'Sistema o posición de uso declarada', required=True),
              column('thickness_mm', 'Espesor de esta pieza', 'decimal', unit='mm', required=True, positive=True),
              column('geometry_kind', 'Geometría de la pieza', 'token', required=True,
                     options=['Anillo circular', 'Geometría propietaria', 'Designación sin descomponer']),
              column('interface_designation', 'Interfaz objetivo o geometría publicada'),
              column('inner_diameter_mm', 'Diámetro interior físico', 'decimal', unit='mm', positive=True),
              column('outer_diameter_mm', 'Diámetro exterior físico', 'decimal', unit='mm', positive=True),
              column('conditions', 'Configuración y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, ordered=[['inner_diameter_mm', 'outer_diameter_mm']],
          conditions={
              'interface_designation': condition('geometry_kind', ['Designación sin descomponer', 'Geometría propietaria']),
              'inner_diameter_mm': condition('geometry_kind', 'Anillo circular'),
              'outer_diameter_mm': condition('geometry_kind', 'Anillo circular')},
          helper='Una fila por pieza distinta del conjunto. La interfaz nominal '
                 'de espiga o eje no es una medición del agujero; no se convierten '
                 'unidades ni se suman espesores para declarar compatibilidad.')
    spacer_rc = spacer['form_contract']['row_conditions']['fields'][members]
    spacer_rc['required_when'].pop('outer_diameter_mm')
    spacer_rc['required_when'].pop('inner_diameter_mm')
    spacer_rc['allowed_when'].pop('interface_designation')
    retire(spacer, ['spacer_system', 'inner_diameter_mm', 'outer_diameter_mm', 'thickness_mm'])

    headset = templates['headset_small_part']
    claims = 'headset_component_fitments'
    table(definitions, templates, claims, 'Uso declarado por pieza de dirección',
          ['headset_small_part'], [
              column('component', 'Pieza y modelo exacto', required=True),
              column('component_kind', 'Tipo de pieza', 'token', required=True,
                     options=['Araña', 'Expansor', 'Tapa o perno', 'Otro']),
              column('target_steerer_material', 'Material de espiga objetivo', 'token', required=True,
                     options=['Carbono', 'Aluminio', 'Acero', 'Otro']),
              column('anchor_contact', 'Superficie donde ancla la araña', 'token',
                     options=['Carbono directo', 'Metal de espiga', 'Inserto de aleación OEM', 'Otro']),
              column('insert_model', 'Inserto y configuración OEM declarados'),
              column('status', 'Declaración', 'token', required=True,
                     options=['Compatible declarado', 'Incompatible declarado', 'Condicional']),
              column('target_model', 'Modelo de espiga u horquilla objetivo'),
              column('conditions', 'Condiciones publicadas'),
              column('source_url', 'Fuente', 'url'),
          ], helper='Una declaración por componente y objetivo. Una tapa de kit '
                    'no hereda las restricciones de una araña. La ausencia de '
                    'declaración no equivale a aprobación para carbono.',
          conditions={'conditions': condition('status', 'Condicional'),
                      'anchor_contact': condition('component_kind', 'Araña'),
                      'insert_model': condition('anchor_contact', 'Inserto de aleación OEM')})
    rc = headset['form_contract']['row_conditions']['fields'][claims]
    rc['allowed_when'].pop('conditions')
    rc['required_when']['conditions']['rows'].extend(
        condition('anchor_contact', 'Inserto de aleación OEM')['rows'])
    for bucket in ['allowed_when', 'required_when']:
        rc[bucket]['insert_model']['rows'][0].extend(condition('component_kind', 'Araña')['rows'][0])
    rc['required_when']['target_model'] = condition('anchor_contact', 'Inserto de aleación OEM')
    rc['required_when']['source_url'] = condition('anchor_contact', 'Inserto de aleación OEM')
    star_carbon = condition('component_kind', 'Araña')
    star_carbon['rows'][0].extend(condition('anchor_contact', 'Carbono directo')['rows'][0])
    rc['value_when'] = {'status': [{'when': star_carbon,
                                 'expected': {'value_type': 'token', 'value': 'Incompatible declarado'}}]}
    retire(headset, ['carbon_safe', 'steerer_fit'])

    pair = {'configuration': 'Configuración sintética', 'length': '210',
            'length_unit': 'mm', 'length_datum': 'Centros de montaje',
            'stroke': '55', 'stroke_unit': 'mm'}
    member = {'component': 'Separador 3 mm', 'quantity': '1', 'system': 'Dirección',
              'thickness_mm': '3', 'geometry_kind': 'Anillo circular',
              'interface_designation': 'Espiga superior 1 1/8 in',
              'conditions': 'Wolf Tooth SPACER-BLK-KIT1', 'source_url': WOLF_SPACERS}
    star_claim = {'component': 'Araña de precarga', 'component_kind': 'Araña',
                  'target_steerer_material': 'Carbono', 'status': 'Incompatible declarado',
                  'anchor_contact': 'Carbono directo',
                  'source_url': WOLF_PLUG}
    fit = 'headset_part_interfaces'
    fixtures['cases'].extend([
        case('sh_root_shock_pair_cannot_omit_stroke', 'rear_shock',
             {size: rows({k:v for k,v in pair.items() if k != 'stroke'})},
             pending=[('row_incomplete', size)]),
        case('sh_root_two_sizes_keep_their_ends', 'rear_shock', {
            size: rows(pair, {**pair, 'configuration': 'Segunda configuración', 'length': '230', 'stroke': '65'}),
            ends: rows({'size_row_id': 'r1', 'end_position': 'Cuerpo', 'mount_kind': 'Trunnion'},
                       {'size_row_id': 'r2', 'end_position': 'Cuerpo', 'mount_kind': 'Ojal estándar'})}),
        case('sh_root_shock_end_orphan', 'rear_shock', {
            size: rows(pair), ends: rows({'size_row_id': 'missing', 'end_position': 'Cuerpo', 'mount_kind': 'Trunnion'})},
             blocking=[('row_reference_unresolved', ends)]),
        case('sh_root_fork_decimal_pitch', 'fork', {interface: rows({
            'scope': 'Retención sintética', 'interface_kind': 'Rosca',
            'diameter_unit': 'mm', 'diameter_mm': '12', 'pitch_unit': 'mm', 'pitch_mm': '1.25'})}),
        case('sh_root_spacer_varied_kit', 'spacer', {members: rows(*[
            {**member, 'component': f'Separador {v} mm', 'thickness_mm': str(v)} for v in (3,5,10,15)])}, sources=[WOLF_SPACERS]),
        case('sh_root_spacer_quantity_integer', 'spacer', {members: rows({**member, 'quantity': '1.5'})},
             blocking=[('row_shape', members)]),
        case('sh_root_spacer_diameter_order', 'spacer', {members: rows({
            'component': 'Anillo sintético', 'quantity': '1', 'system': 'Otro', 'thickness_mm': '2',
            'geometry_kind': 'Anillo circular', 'inner_diameter_mm': '35', 'outer_diameter_mm': '30'})},
             blocking=[('row_shape', members)]),
        case('sh_root_spacer_literal_is_not_measured_bore', 'spacer', {members: rows({**member,
            'geometry_kind': 'Designación sin descomponer', 'inner_diameter_mm': '28.6'})},
             blocking=[('row_field_applicability', members)]),
        case('sh_root_spacer_target_and_measurement_coexist', 'spacer', {members: rows({
            **{k:v for k,v in member.items() if k != 'source_url'},
            'component': 'Separador sintético', 'inner_diameter_mm': '28.7',
            'conditions': 'Medición sintética; no se deduce del nominal ni prueba calce'})}),
        case('sh_root_headset_exact_diameter', 'headset_small_part', {fit: rows({
            'scope': 'Interfaz sintética', 'fit_kind': 'Interior de espiga',
            'diameter_form': 'Valor nominal', 'diameter_mm': '23.5'})}),
        case('sh_root_headset_literal_size', 'headset_small_part', {fit: rows({
            'scope': 'Tapa', 'fit_kind': 'Exterior de espiga',
            'diameter_form': 'Designación literal', 'designation': '1 1/8 in'})}),
        case('sh_root_star_carbon_rejected', 'headset_small_part', {claims: rows({**star_claim, 'status': 'Compatible declarado'})},
             blocking=[('row_value_conflict', claims)], sources=[PARK_STAR, WOLF_PLUG]),
        case('sh_root_star_carbon_exclusion', 'headset_small_part', {claims: rows(star_claim)}, sources=[PARK_STAR, WOLF_PLUG]),
        case('sh_root_cap_does_not_inherit_star_rule', 'headset_small_part', {claims: rows({
            **{k:v for k,v in star_claim.items() if k not in ['anchor_contact', 'source_url']},
            'component': 'Tapa sintética', 'component_kind': 'Tapa o perno', 'status': 'Compatible declarado'})}),
        case('sh_root_cervelo_bonded_insert', 'headset_small_part', {claims: rows({
            'component': 'Araña preinstalada en inserto suministrado', 'component_kind': 'Araña',
            'target_steerer_material': 'Carbono', 'anchor_contact': 'Inserto de aleación OEM',
            'insert_model': 'Inserto de 75 mm suministrado; Fork Owners Manual v3',
            'target_model': 'Horquilla Cervélo cubierta por ese manual',
            'status': 'Condicional', 'conditions': 'Inserto adherido y curado según procedimiento OEM',
            'source_url': CERVELO_FORK})}, sources=[CERVELO_FORK]),
        case('sh_root_carbon_contact_unknown', 'headset_small_part', {claims: rows({
            **{k:v for k,v in star_claim.items() if k not in ['anchor_contact', 'source_url']},
            'status': 'Condicional', 'conditions': 'Anclaje por confirmar'})},
             pending=[('row_required_missing', claims)]),
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

    # SH-1. Root already adjudicated that the tyre envelope is one row per bead
    # seat and that a bare maximum does not identify it (WSS-W07). The two
    # scalars held the same pair outside any envelope, so a fork admitting two
    # wheel sizes could only state one. The rows become the single owner.
    clearance = 'fork_tire_clearance_configurations'
    fork = templates['fork']
    retire(fork, ['bead_seat_diameter_mm', 'max_tire_width_mm'])
    fork['form_contract']['required_when'][clearance] = deepcopy(ALWAYS)
    fork['form_contract'].setdefault('helpers', {})[clearance] = (
        'Una envolvente por asiento de talón, copiada del fabricante. Un ancho '
        'máximo sin su rueda no describe la envolvente, y una holgura habitual '
        'no autoriza otro tamaño.')

    # SH-2. The mount kind moved into shock_end_configurations, which names the
    # body and shaft ends separately. The scalar stayed legacy while still
    # declaring required_when always: a rule the engine never reaches, because a
    # legacy field is dropped before validation.
    shock = templates['rear_shock']
    retire(shock, ['shock_mount_kind'])

    # SH-3. Eye-to-eye and stroke were millimetre-only numbers.
    size = 'shock_size_declarations'
    quantity, unit_kind = 'quantity_kind', 'unit'
    table(definitions, templates, size, 'Medidas declaradas del amortiguador',
          ('rear_shock',), [
              column('configuration', 'Modelo y presentación', required=True),
              column('length', 'Longitud de montaje publicada', 'decimal',
                     required=True, positive=True),
              column('length_unit', 'Unidad de longitud', 'token', required=True,
                     options=['mm', 'in']),
              column('length_datum', 'Referencia de la longitud', required=True),
              column('stroke', 'Recorrido publicado', 'decimal', required=True,
                     positive=True),
              column('stroke_unit', 'Unidad de recorrido', 'token', required=True,
                     options=['mm', 'in']),
              column('conditions', 'Condiciones declaradas'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          helper=('Copia el valor y la unidad tal como los publica el '
                  'fabricante. No conviertas pulgadas a milímetros ni al '
                  'revés: son dos lecturas distintas si el fabricante publica '
                  'ambas. Longitud y recorrido pertenecen a la misma '
                  'configuración; la referencia distingue ojales y trunnion.'))
    retire(shock, ['eye_to_eye_mm', 'stroke_mm'])

    # SH-5. An expander plug is specified by the steerer bore it clamps, which
    # is a range, plus its insertion depth; the template held a single number.
    headset = templates['headset_small_part']
    fit = 'headset_part_interfaces'
    bore, outside, other = 'Interior de espiga', 'Exterior de espiga', 'Otra'
    table(definitions, templates, fit, 'Interfaces declaradas de la pieza de dirección',
          ('headset_small_part',), [
              column('scope', 'Pieza o zona declarada', required=True),
              column('fit_kind', 'Superficie de calce', 'token', required=True,
                     options=[bore, outside, other]),
              column('diameter_form', 'Forma publicada del diámetro', 'token', required=True,
                     options=['Valor nominal', 'Intervalo', 'Designación literal']),
              column('diameter_mm', 'Diámetro publicado', 'decimal', unit='mm', positive=True),
              column('diameter_min_mm', 'Diámetro mínimo publicado',
                     'decimal', unit='mm', positive=True),
              column('diameter_max_mm', 'Diámetro máximo publicado',
                     'decimal', unit='mm', positive=True),
              column('insertion_depth_mm', 'Profundidad de inserción declarada',
                     'decimal', unit='mm', positive=True),
              column('designation', 'Designación publicada sin descomponer'),
              column('conditions', 'Modelo, material de espiga y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          ordered=[['diameter_min_mm', 'diameter_max_mm']],
          conditions={'diameter_mm': condition('diameter_form', 'Valor nominal'),
                      'diameter_min_mm': condition('diameter_form', 'Intervalo'),
                      'diameter_max_mm': condition('diameter_form', 'Intervalo'),
                      'designation': condition('diameter_form', 'Designación literal')},
          helper=('El rango de espiga que el fabricante declara para esta '
                  'pieza. No se deduce del tamaño nominal exterior ni de un '
                  'espesor de pared habitual.'))
    # Two different fasteners carry two different figures on the same plug, and
    # a range is not a nominal value. Same shape already accepted for grips.
    torque = 'headset_torque_specifications'
    nominal, interval, maximum = 'Par nominal', 'Rango de apriete', 'Máximo de apriete'
    table(definitions, templates, torque, 'Apriete declarado de la pieza de dirección',
          ('headset_small_part',), [
              column('fastener', 'Tornillo o elemento', required=True),
              column(quantity, 'Forma de la cifra', 'token', required=True,
                     options=[nominal, interval, maximum]),
              column('value', 'Valor publicado', 'decimal', positive=True),
              column('minimum', 'Mínimo publicado', 'decimal', positive=True),
              column('maximum', 'Máximo publicado', 'decimal', positive=True),
              column(unit_kind, 'Unidad publicada', 'token', required=True,
                     options=['Nm', 'in-lb', 'ft-lb']),
              column('conditions', 'Condiciones declaradas'),
              column('source_url', 'Fuente', 'url'),
          ], ordered=[['minimum', 'maximum']],
          conditions={'value': condition(quantity, [nominal, maximum]),
                      'minimum': condition(quantity, interval),
                      'maximum': condition(quantity, interval)},
          helper=('Una fila por tornillo y por unidad publicada. No se '
                  'convierte entre unidades ni se aplica el apriete de un '
                  'tornillo al otro.'))
    retire(headset, ['steerer_inner_diameter_mm'])

    envelope = [{'bead_seat_diameter_mm': '622', 'max_tire_width_mm': '61',
                 'measurement_method': 'Declaración sintética'}]
    plug = {'scope': 'Cuerpo expansor', 'fit_kind': bore,
        'diameter_form': 'Intervalo',
        'diameter_min_mm': '23.5', 'diameter_max_mm': '24.5',
        'insertion_depth_mm': '28',
        'conditions': 'CPLUG-STEM5MM-BLK: rango declarado para espiga metálica',
        'source_url': WOLF_PLUG}
    star = {'scope': 'Araña', 'fit_kind': bore,
            'diameter_form': 'Designación literal',
            'designation': 'Interfaz de araña sintética; sin calce certificado'}
    fixtures['cases'].extend([
        # Two published sizes of one shock family, each in the unit FOX prints.
        case('sh_fox_imperial_sizing', 'rear_shock', {size: rows(
            {'length': '7.875', 'length_unit': 'in',
             'length_datum': 'Distancia entre centros de ojales',
             'stroke': '2', 'stroke_unit': 'in',
             'configuration': 'FOX FLOAT DPS PERFORMANCE 972-01-490',
             'source_url': FOX_SPEC})},
             sources=[FOX_SPEC]),
        case('sh_metric_sizing', 'rear_shock', {size: rows(
            {'length': '210', 'length_unit': 'mm', 'stroke': '55',
             'stroke_unit': 'mm', 'length_datum': 'Centros de montaje',
             'configuration': 'Amortiguador sintético métrico'})}),
        case('sh_shock_size_without_unit', 'rear_shock', {size: rows(
            {'stroke': '55',
             'configuration': 'Amortiguador sintético'})},
             pending=[('row_incomplete', size)]),
        case('sh_shock_size_absent', 'rear_shock', {'spring_kind': 'Aire'},
             pending=[('required_missing', size)]),
        # A plug clamps a bore range; a star nut is another scope of the same
        # part family and keeps its own row.
        case('sh_expander_bore_range', 'headset_small_part',
             {fit: rows(plug), 'headset_part_kind': 'Expansor'},
             sources=[WOLF_PLUG]),
        case('sh_headset_two_scopes', 'headset_small_part',
             {fit: rows(plug, star), 'headset_part_kind': 'Otro'}),
        case('sh_headset_bore_reversed', 'headset_small_part', {fit: rows(
            {**plug, 'diameter_min_mm': '24.5',
             'diameter_max_mm': '23.5'})},
             blocking=[('row_shape', fit)]),
        case('sh_headset_nominal_rejects_range_cell', 'headset_small_part', {fit: rows(
            {'scope': 'Tapa', 'fit_kind': outside,
             'diameter_form': 'Valor nominal',
             'diameter_min_mm': '23.5'})},
             blocking=[('row_field_applicability', fit)]),
        case('sh_headset_fit_absent', 'headset_small_part',
             {'headset_part_kind': 'Araña (star nut)'},
             pending=[('required_missing', fit)]),
        # Two fasteners of one plug, each with its own published figure.
        case('sh_headset_two_fasteners', 'headset_small_part', {fit: rows(plug),
            torque: rows(
                {'fastener': 'Tornillo de la tapa', 'quantity_kind': interval,
                 'minimum': '2', 'maximum': '3', 'unit': 'Nm',
                 'conditions': 'CPLUG-STEM5MM-BLK: grasa ligera sólo en roscas',
                 'source_url': WOLF_PLUG},
                {'fastener': 'Tornillo de expansión', 'quantity_kind': interval,
                 'minimum': '5', 'maximum': '7', 'unit': 'Nm',
                 'conditions': 'CPLUG-STEM5MM-BLK', 'source_url': WOLF_PLUG})},
             sources=[WOLF_PLUG]),
        case('sh_headset_nominal_is_not_range', 'headset_small_part',
             {fit: rows(plug), torque: rows(
                 {'fastener': 'Tornillo de expansión', 'quantity_kind': nominal,
                  'value': '5', 'minimum': '4', 'unit': 'Nm'})},
             blocking=[('row_field_applicability', torque)]),
        case('sh_headset_torque_reversed', 'headset_small_part',
             {fit: rows(plug), torque: rows(
                 {'fastener': 'Tornillo de expansión', 'quantity_kind': interval,
                  'minimum': '7', 'maximum': '5', 'unit': 'Nm'})},
             blocking=[('row_shape', torque)]),
        # The envelope is the only owner of wheel size and width now.
        case('sh_fork_envelope', 'fork', {clearance: rows(*envelope)}),
        case('sh_fork_two_wheel_sizes', 'fork', {clearance: rows(
            *envelope, {'bead_seat_diameter_mm': '584',
                        'max_tire_width_mm': '76',
                        'measurement_method': 'Declaración sintética'})}),
        # unique_by surfaces through the row schema, so the engine reports the
        # same row_shape it uses for a reversed pair, not a code of its own.
        case('sh_fork_duplicate_bead_seat', 'fork', {clearance: rows(
            *envelope, {'bead_seat_diameter_mm': '622', 'max_tire_width_mm': '55',
                        'measurement_method': 'Declaración sintética'})},
             blocking=[('row_shape', clearance)]),
        case('sh_fork_envelope_absent', 'fork', {'fork_kind': 'Rígida'},
             pending=[('required_missing', clearance)]),
    ])

    integrate_root_boundaries(templates, definitions, fixtures)
    # SQL reports row_shape through the coherence path; a table without a
    # coherence/conditions owner still reports field_constraint. Same blocking
    # boundary, verified through the actual deployed validator entry point.
    for c in fixtures['cases']:
        if c['id'] == 'wss_shock_two_rows_same_end':
            c['expected_sql_blocking'] = deepcopy(c['expected_blocking'])
        elif c['id'] == 'sh_fork_duplicate_bead_seat':
            c['expected_sql_blocking'] = [{'code': 'field_constraint',
                                         'field': 'fork_tire_clearance_configurations'}]
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Suspension and headset parts reviewed successor',
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
    path = RESEARCH / 'suspension-headset-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'suspension-headset-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
