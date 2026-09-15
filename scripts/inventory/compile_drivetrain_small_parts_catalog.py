#!/usr/bin/env python3
"""Compile four drivetrain small-part templates. No product or database writes.

A row copies what the manufacturer declares for a named target. Clearance for a
larger cog is not capacity, a bolt circle is not a mount standard, and a pitch
is never derived from the nominal diameter.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_wheel_small_parts_catalog import column, retire, table
from compile_product_spec_catalog import validate_contract

FAMILIES = ('derailleur_hanger_extender', 'cassette_lockring',
            'chainring_guard', 'fastener')
ALWAYS, NEVER = {'kind': 'always'}, {'kind': 'never'}
# Wolf Tooth: the link repositions the derailleur for clearance with a larger
# cog and does NOT increase capacity, which stays a property of the derailleur.
WOLF_LINK = 'https://www.wolftoothcomponents.com/pages/roadlink-tech-page'
# Park Tool documents designations that pair a millimetre diameter with a
# threads-per-inch pitch, so neither unit implies the other.
PARK_THREADS = 'https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts'
SHELDON_L = 'https://www.sheldonbrown.com/gloss_l.html'
ONEUP_BASH = 'https://int.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions'

THREAD, SPLINE, LITERAL = 'Rosca', 'Estriado o ranura', 'Designación OEM'
MM, IN, TPI = 'mm', 'in', 'tpi'


def thread_columns():
    """The corrected shape: the diameter unit never implies the pitch unit."""
    return [
        column('scope', 'Pieza o cara declarada', required=True),
        column('interface_kind', 'Forma de la interfaz', 'token', required=True,
               options=[THREAD, SPLINE, LITERAL]),
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
        column('thread_hand', 'Sentido de rosca', 'token',
               options=['Derecha', 'Izquierda']),
        column('designation', 'Designación publicada sin descomponer'),
        column('conditions', 'Modelo, generación y condiciones'),
        column('source_url', 'Fuente', 'url'),
    ]


def thread_conditions():
    threaded_or_spline = condition('interface_kind', [THREAD, SPLINE])
    result = {
        'diameter_unit': deepcopy(threaded_or_spline),
        'pitch_unit': condition('interface_kind', THREAD),
        'diameter_mm': condition('diameter_unit', MM),
        'diameter_in': condition('diameter_unit', IN),
        'pitch_mm': condition('pitch_unit', MM),
        'pitch_tpi': condition('pitch_unit', TPI),
        'designation': condition('interface_kind', LITERAL),
        'thread_hand': condition('interface_kind', THREAD),
    }
    for key in ('diameter_mm', 'diameter_in'):
        result[key]['rows'][0].extend(deepcopy(threaded_or_spline)['rows'][0])
    for key in ('pitch_mm', 'pitch_tpi'):
        result[key]['rows'][0].extend(condition('interface_kind', THREAD)['rows'][0])
    return result


def integrate_root_boundaries(templates, definitions, fixtures):
    # A successor schema can retire a *use* without touching a shared global
    # definition. Old observations remain legacy; explicit unit columns in a
    # fixture translate without guessing a unit from a nominal designation.
    fastener = templates['fastener']
    old, members = 'fastener_kit_members', 'fastener_component_configurations'
    table(definitions, templates, members, 'Piezas y medidas del kit de fijación', ['fastener'], [
        column('member_role', 'Pieza o función', required=True),
        column('quantity', 'Cantidad de esta pieza', 'integer', required=True, positive=True),
        column('member_kind', 'Clase de pieza declarada'),
        column('interface_kind', 'Interfaz de esta pieza', 'token', required=True,
               options=['Rosca', 'Sin rosca', 'Designación OEM']),
        column('thread_nominal', 'Nominal de rosca publicado, sin inferir paso'),
        column('pitch_unit', 'Unidad publicada del paso', 'token', options=['mm', 'tpi']),
        column('pitch_value', 'Paso publicado', 'decimal', positive=True),
        column('thread_hand', 'Sentido de rosca', 'token', options=['Derecha', 'Izquierda']),
        column('interface_designation', 'Designación de interfaz sin descomponer'),
        column('length_mm', 'Largo publicado', 'decimal', unit='mm', positive=True),
        column('length_datum', 'Referencia del largo'),
        column('drive_designation', 'Accionamiento publicado sin descomponer'),
        column('inner_diameter_mm', 'Diámetro interior físico', 'decimal', unit='mm', positive=True),
        column('outer_diameter_mm', 'Diámetro exterior físico', 'decimal', unit='mm', positive=True),
        column('thickness_mm', 'Espesor', 'decimal', unit='mm', positive=True),
        column('conditions', 'Configuración y condiciones'),
        column('source_url', 'Fuente', 'url'),
    ], ordered=[['inner_diameter_mm', 'outer_diameter_mm']],
        conditions={'thread_nominal': condition('interface_kind', THREAD),
                    'pitch_unit': condition('interface_kind', THREAD),
                    'pitch_value': condition('pitch_unit', ['mm', 'tpi']),
                    'thread_hand': condition('interface_kind', THREAD),
                    'interface_designation': condition('interface_kind', LITERAL)},
        helper='Una fila por pieza. Un solo valor de paso conserva su unidad '
               'explícita; diámetro nominal y unidad de paso son independientes. '
               'La ficha no convierte un M8 en M8 × 0,75 por su uso.')
    fc = fastener['form_contract']
    fc['allowed_when'][members] = condition('fastener_kind', 'Kit')
    fc['required_when'][members] = condition('fastener_kind', 'Kit')
    rc = fc['row_conditions']['fields'][members]
    rc['required_when'].pop('thread_hand')
    for bucket in ['allowed_when', 'required_when']:
        rc[bucket]['pitch_value']['rows'][0].extend(condition('interface_kind', THREAD)['rows'][0])
    retire(fastener, [old])
    fc['allowed_when']['head_drive'] = condition('fastener_kind', ['Perno', 'Tornillo', 'Tuerca', 'Otro'])
    for key in ['head_drive_size_mm', 'torx_size']:
        fc['allowed_when'][key]['rows'][0].extend(
            condition('fastener_kind', ['Perno', 'Tornillo', 'Tuerca', 'Otro'])['rows'][0])
    # These are local representation fixtures, never a product backfill.
    for c in fixtures['cases']:
        if c['template'] != 'fastener' or old not in c['values']:
            continue
        translated = deepcopy(c['values'][old])
        for row in translated['rows']:
            v = row['values']
            if 'thread_nominal' in v:
                v['interface_kind'] = THREAD
            for prior, unit in [('thread_pitch_mm', 'mm'), ('thread_tpi', 'tpi')]:
                if prior in v:
                    if 'pitch_value' in v:
                        raise ValueError('Fixture carries two pitches; must adjudicate explicitly')
                    v['pitch_unit'], v['pitch_value'] = unit, v.pop(prior)
            if 'head_drive' in v:
                v['drive_designation'] = v.pop('head_drive')
        c['values'][members] = translated
        c['values'].pop(old)
        if c.get('field') == old:
            c['field'] = members
        c['successor_translation'] = 'Column units retained explicitly; no inference from diameter'

    # The OEM distinguishes discrete cassette pairs and statuses, even when the
    # biggest cog matches. A scalar maximum cannot carry those distinctions.
    extender = templates['derailleur_hanger_extender']
    claims = 'hanger_extender_claims'
    schema = definitions[claims]['validation_rules']['rows_schema']
    schema['columns'] = [c for c in schema['columns'] if c['key'] != 'claimed_max_cog_teeth']
    schema['columns'][0:0] = [column('extender_model', 'Modelo y versión del extensor', required=True)]
    schema['columns'].extend([
        column('declaration_kind', 'Alcance de la cifra', 'token', required=True,
               options=['Combinación de cassette', 'Piñón máximo']),
        column('smallest_cog_teeth', 'Piñón menor del cassette', 'integer', unit='T', positive=True),
        column('largest_cog_teeth', 'Piñón mayor del cassette o máximo', 'integer', unit='T', positive=True),
        column('status', 'Valoración publicada', 'token', required=True,
               options=['Recomendado', 'Aceptable', 'No compatible', 'No requerido', 'Condicional']),
        column('target_hanger', 'Patilla o montaje objetivo'),
        column('capacity_conditions', 'Capacidad y combinación de platos requeridas'),
    ])
    schema['ordered_pairs'] = [['smallest_cog_teeth', 'largest_cog_teeth']]
    erc = {
        'allowed_when': {'smallest_cog_teeth': condition('declaration_kind', 'Combinación de cassette')},
        'required_when': {
            'smallest_cog_teeth': condition('declaration_kind', 'Combinación de cassette'),
            'largest_cog_teeth': condition('declaration_kind', ['Combinación de cassette', 'Piñón máximo']),
            'conditions': condition('status', 'Condicional')},
    }
    extender['form_contract'].setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][claims] = erc
    for c in fixtures['cases']:
        if c['template'] == 'derailleur_hanger_extender' and claims in c['values']:
            for row in c['values'][claims]['rows']:
                v = row['values']; v['largest_cog_teeth'] = v.pop('claimed_max_cog_teeth')
                v.update(extender_model='Extensor sintético', declaration_kind='Piñón máximo', status='Condicional')

    # A replaceable bash plate has a different tooth range from the other plate
    # in the same kit. Link each plate/configuration to its real mounting row.
    guard = templates['chainring_guard']
    mounts, covers = 'chainring_guard_mounts', 'chainring_guard_configurations'
    table(definitions, templates, covers, 'Guardas incluidas y cobertura por configuración', ['chainring_guard'], [
        column('component', 'Guarda y modelo o presentación', required=True),
        column('mount_row_id', 'Montaje correspondiente', required=True),
        column('quantity', 'Cantidad incluida', 'integer', positive=True),
        column('installed', 'Instalada en la presentación', 'boolean'),
        column('size_form', 'Forma publicada de cobertura', 'token', required=True,
               options=['Valor exacto', 'Intervalo', 'Designación literal']),
        column('teeth', 'Tamaño de plato', 'integer', unit='T', positive=True),
        column('min_teeth', 'Plato mínimo', 'integer', unit='T', positive=True),
        column('max_teeth', 'Plato máximo', 'integer', unit='T', positive=True),
        column('designation', 'Cobertura publicada sin descomponer'),
        column('conditions', 'Condiciones publicadas'),
        column('source_url', 'Fuente', 'url'),
    ], required=True, ordered=[['min_teeth', 'max_teeth']], conditions={
        'teeth': condition('size_form', 'Valor exacto'),
        'min_teeth': condition('size_form', 'Intervalo'),
        'max_teeth': condition('size_form', 'Intervalo'),
        'designation': condition('size_form', 'Designación literal')})
    retire(guard, ['covers_teeth_min', 'covers_teeth_max'])
    guard['form_contract'].pop('scalar_ordered_pairs', None)
    guard['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'guard_configuration_mount', 'field': covers, 'column': 'mount_row_id',
        'target_field': mounts, 'label_columns': ['mount_kind', 'target_component']} ]}

    # A lockring is not its target freehub/cog. Keep each interface's owner,
    # generation and outer-sprocket condition together in the declaration.
    lockring = templates['cassette_lockring']
    lockring['name'] = 'Anillo de bloqueo de transmisión'
    threads = 'lockring_thread_interfaces'
    lc = lockring['form_contract']
    ls = definitions[threads]['validation_rules']['rows_schema']
    ls['columns'][0:0] = [
        column('owner_role', 'A qué pertenece la interfaz', 'token', required=True,
               options=['Anillo de bloqueo', 'Componente objetivo', 'Herramienta']),
        column('application', 'Sistema objetivo', 'token', required=True,
               options=['Cassette', 'Piñón fijo', 'Otro']),
        column('target_model', 'Modelo o familia exacta declarada', required=True),
        column('target_edition', 'Generación o edición de la fuente'),
        column('smallest_cog_form', 'Condición del piñón exterior', 'token',
               options=['Valor exacto', 'Intervalo', 'Designación literal']),
        column('smallest_cog_teeth', 'Piñón exterior', 'integer', unit='T', positive=True),
        column('smallest_cog_min', 'Piñón exterior mínimo', 'integer', unit='T', positive=True),
        column('smallest_cog_max', 'Piñón exterior máximo', 'integer', unit='T', positive=True),
        column('smallest_cog_designation', 'Condición literal del piñón exterior'),
    ]
    ls['ordered_pairs'] = [['smallest_cog_min', 'smallest_cog_max']]
    lrc = lc['row_conditions']['fields'][threads]
    cog_conditions = {
        'smallest_cog_form': condition('application', 'Cassette'),
        'smallest_cog_teeth': condition('smallest_cog_form', 'Valor exacto'),
        'smallest_cog_min': condition('smallest_cog_form', 'Intervalo'),
        'smallest_cog_max': condition('smallest_cog_form', 'Intervalo'),
        'smallest_cog_designation': condition('smallest_cog_form', 'Designación literal'),
    }
    for key in list(cog_conditions)[1:]:
        cog_conditions[key]['rows'][0].extend(condition('application', 'Cassette')['rows'][0])
    lrc['allowed_when'].update(deepcopy(cog_conditions))
    lrc['required_when'].update(deepcopy(cog_conditions))
    fixed_hand = condition('application', 'Piñón fijo')
    fixed_hand['rows'][0].extend(condition('owner_role', 'Anillo de bloqueo')['rows'][0])
    fixed_hand['rows'][0].extend(condition('interface_kind', THREAD)['rows'][0])
    lrc['value_when'] = {'thread_hand': [{'when': fixed_hand,
                                       'expected': {'value_type': 'token', 'value': 'Izquierda'}}]}
    retire(lockring, ['target_rear_drive_interface', 'smallest_cog_fit'])
    lc['helpers'][threads] = ('Rosca propia, interfaz objetivo y herramienta '
        'conservan dueños distintos. Generación y piñón exterior pertenecen a '
        'la misma declaración; la rosca sola no acredita intercambiabilidad.')
    for c in fixtures['cases']:
        if c['id'] == 'ds_lockring_two_threads':
            for row in c['values'][threads]['rows']:
                v = row['values']
                v.update(application='Piñón fijo', target_model='Sistema inglés tradicional',
                         owner_role='Anillo de bloqueo' if v['scope']=='Contratuerca' else 'Componente objetivo')
            c['note'] = 'Dos dueños en el conjunto: el piñón no es una segunda rosca propia de la contratuerca.'
        elif c['id'] == 'ds_lockring_metric_diameter_tpi_pitch':
            v = c['values'][threads]['rows'][0]['values']
            v.update(owner_role='Anillo de bloqueo', application='Cassette',
                     target_model='Shimano Hyperglide, ejemplo de Sheldon',
                     pitch_tpi='24', thread_hand='Derecha',
                     smallest_cog_form='Designación literal',
                     smallest_cog_designation='Diámetro exterior distinto para 11T o piñones mayores',
                     conditions='Diámetro de rosca aproximado en la fuente; no dimensión medida de un SKU')
            c['source_urls'] = [SHELDON_L]

    fixtures['cases'].extend([
        case('ds_root_no_thread_pitch_on_plain_member', 'fastener', {
            'fastener_kind': 'Kit', members: rows({'member_role': 'Golilla', 'quantity': '1',
                'interface_kind': 'Sin rosca', 'pitch_unit': 'mm', 'pitch_value': '1'})},
             blocking=[('row_field_applicability', members)]),
        case('ds_root_pitch_unit_missing', 'fastener', {'fastener_kind': 'Kit', members: rows({
            'member_role': 'Perno', 'quantity': '1', 'interface_kind': THREAD,
            'thread_nominal': 'M8', 'pitch_value': '0.75'})}, pending=[('row_prerequisite', members)]),
        case('ds_root_washer_cannot_receive_torx', 'fastener', {
            'fastener_kind': 'Golilla / espaciador', 'head_drive': 'Torx', 'torx_size': 'T25'},
             blocking=[('field_applicability', 'head_drive'), ('field_applicability', 'torx_size')]),
        case('ds_root_roadlink_dm_cassette_pair', 'derailleur_hanger_extender', {claims: rows(*[
            {'extender_model': 'Wolf Tooth RoadLink DM', 'target_derailleur': 'Shimano Ultegra R8000',
             'target_speeds': '11', 'declaration_kind': 'Combinación de cassette',
             'smallest_cog_teeth': str(small), 'largest_cog_teeth': '42', 'status': status,
             'target_hanger': 'Patilla estándar; no patilla Direct Mount',
             'capacity_conditions': 'Respetar capacidad publicada del cambio y su jaula', 'source_url': WOLF_LINK}
            for small,status in [(11,'Aceptable'),(10,'No compatible')]])}, sources=[WOLF_LINK]),
        case('ds_root_cassette_pair_reversed', 'derailleur_hanger_extender', {claims: rows({
            'extender_model': 'Sintético', 'target_derailleur': 'Sintético',
            'declaration_kind': 'Combinación de cassette', 'smallest_cog_teeth': '42',
            'largest_cog_teeth': '11', 'status': 'Aceptable'})}, blocking=[('row_shape', claims)]),
        case('ds_root_bash_plates_keep_distinct_ranges', 'chainring_guard', {
            mounts: rows({'mount_kind': 'ISCG05', 'interface_designation': 'ISCG05'}),
            covers: rows({'component': 'OneUp V2 32–34T', 'mount_row_id': 'r1', 'installed': True,
                          'size_form': 'Intervalo', 'min_teeth': '32', 'max_teeth': '34', 'source_url': ONEUP_BASH},
                         {'component': 'OneUp V2 36T', 'mount_row_id': 'r1',
                          'size_form': 'Valor exacto', 'teeth': '36', 'source_url': ONEUP_BASH})}, sources=[ONEUP_BASH]),
        case('ds_root_guard_unresolved_mount', 'chainring_guard', {
            mounts: rows({'mount_kind': 'ISCG05', 'interface_designation': 'ISCG05'}),
            covers: rows({'component': 'Sintético', 'mount_row_id': 'missing',
                          'size_form': 'Valor exacto', 'teeth': '36'})},
             blocking=[('row_reference_unresolved', covers)]),
        case('ds_root_track_lockring_right_hand_conflict', 'cassette_lockring', {threads: rows({
            'scope': 'Rosca propia', 'owner_role': 'Anillo de bloqueo', 'application': 'Piñón fijo',
            'target_model': 'Inglés tradicional', 'interface_kind': THREAD,
            'diameter_unit': 'in', 'diameter_in': '1.29', 'pitch_unit': 'tpi',
            'pitch_tpi': '24', 'thread_hand': 'Derecha'})},
             blocking=[('row_value_conflict', threads)], sources=[SHELDON_L]),
        case('ds_root_campagnolo_generation_scoped', 'cassette_lockring', {threads: rows({
            'scope': 'Rosca propia', 'owner_role': 'Anillo de bloqueo', 'application': 'Cassette',
            'target_model': 'Campagnolo 9/10 velocidades', 'target_edition': '1996–1999',
            'interface_kind': THREAD, 'diameter_unit': 'mm', 'diameter_mm': '26',
            'pitch_unit': 'mm', 'pitch_mm': '1', 'smallest_cog_form': 'Valor exacto',
            'smallest_cog_teeth': '11', 'conditions': 'No extrapolar a generación 2000+; exterior distinto 11T/12–14T',
            'source_url': SHELDON_L})}, sources=[SHELDON_L]),
        case('ds_root_track_cannot_claim_cassette_outer_cog', 'cassette_lockring', {threads: rows({
            'scope': 'Rosca propia', 'owner_role': 'Anillo de bloqueo', 'application': 'Piñón fijo',
            'target_model': 'Sintético', 'interface_kind': LITERAL, 'designation': 'OEM',
            'smallest_cog_form': 'Valor exacto', 'smallest_cog_teeth': '11'})},
             blocking=[('row_field_applicability', threads)]),
    ])


def integrate_review_findings(templates, definitions, fixtures):
    """DT-1/DT-2: scoped identifiers and typed geometry, without parsing prose."""
    members = 'fastener_component_configurations'
    t = templates['fastener']
    schema = definitions[members]['validation_rules']['rows_schema']
    schema['columns'] = [c for c in schema['columns'] if c['key'] != 'thread_nominal']
    schema['columns'].extend([
        column('diameter_value', 'Diámetro nominal publicado', 'decimal', positive=True),
        column('diameter_unit', 'Unidad del diámetro nominal', 'token', options=[MM, IN]),
    ])
    rc = t['form_contract']['row_conditions']['fields'][members]
    for bucket in ('allowed_when', 'required_when'):
        rc[bucket].pop('thread_nominal', None)
        for key in ('diameter_unit', 'diameter_value'):
            rc[bucket][key] = condition('interface_kind', THREAD)
    # This finite mapping translates the explicitly named synthetic fixtures
    # only. It is NOT an importer or a parser of product names/designations.
    fixture_diameters = {'M5': ('5', MM), 'M8': ('8', MM),
                         '9 mm': ('9', MM), '10 mm': ('10', MM),
                         '3/8"': ('0.375', IN)}
    for c in fixtures['cases']:
        for row in c['values'].get(members, {}).get('rows', []):
            v = row['values']
            if 'thread_nominal' in v:
                value, unit = fixture_diameters[v.pop('thread_nominal')]
                v.update(diameter_value=value, diameter_unit=unit)
    t['form_contract']['helpers'][members] += (
        ' La designación OEM completa va sola, sin diámetro o paso descompuestos. '
        'Un diámetro numérico no admite texto como M8 × 1,25.')

    # Distinguish the physical setup and the scope of an OEM statement before
    # deciding whether two rows make opposite claims about the same thing.
    # Missing identity members remain incomplete; unique_by never invents them.
    claims = 'hanger_extender_claims'
    es = definitions[claims]['validation_rules']['rows_schema']
    es['columns'].extend([
        column('configuration', 'Configuración de bicicleta declarada', required=True),
        column('source_scope', 'Apartado o alcance de la declaración', required=True),
    ])
    for column_ in es['columns']:
        if column_['key'] in ('target_cage', 'target_speeds'):
            column_['required'] = True
    es['unique_by'] = [['extender_model', 'target_derailleur', 'target_cage',
                        'target_speeds', 'configuration', 'source_scope',
                        'smallest_cog_teeth', 'largest_cog_teeth']]
    # A maximum-only statement needs a different natural key: its absent lower
    # cog cannot participate in a uniqueness key. Split that declaration into a
    # sibling table instead of introducing zero/sentinel cogs or hidden parsing.
    limits = 'hanger_extender_limit_claims'
    limit_columns = [deepcopy(c) for c in es['columns']
                     if c['key'] not in ('smallest_cog_teeth', 'declaration_kind')]
    table(definitions, templates, limits, 'Límite de piñón declarado por configuración',
          ('derailleur_hanger_extender',), limit_columns,
          helper='Una declaración de máximo conserva modelo, jaula y configuración; no inventa un piñón menor.')
    ls = definitions[limits]['validation_rules']['rows_schema']
    ls['unique_by'] = [['extender_model', 'target_derailleur', 'target_cage',
                        'target_speeds', 'configuration', 'source_scope']]
    next(c for c in ls['columns'] if c['key'] == 'largest_cog_teeth')['required'] = True
    et = templates['derailleur_hanger_extender']['form_contract']
    et['row_conditions']['fields'][limits] = {
        'allowed_when': {}, 'required_when': {'conditions': condition('status', 'Condicional')}}
    form = 'extender_declaration_form'
    form_options = ['Combinaciones de cassette', 'Límites de piñón', 'Ambos alcances documentados']
    definitions[form] = new_definition(form, 'Alcance documentado del extensor',
                                      'single_select', ['derailleur_hanger_extender'],
                                      options=form_options)
    add_field(templates['derailleur_hanger_extender'], form, 'primary', 'intrinsic',
              required=ALWAYS, helper='Selecciona el alcance que publica la fuente para abrir sus declaraciones.')
    for field, option in ((claims, form_options[0]), (limits, form_options[1])):
        for bucket in ('allowed_when', 'required_when'):
            et[bucket][field] = condition(form, [option, form_options[2]])
    es['columns'] = [c for c in es['columns'] if c['key'] != 'declaration_kind']
    et['row_conditions']['fields'][claims]['allowed_when'] = {}
    et['row_conditions']['fields'][claims]['required_when'].update({
        'smallest_cog_teeth': deepcopy(ALWAYS), 'largest_cog_teeth': deepcopy(ALWAYS)})
    et['helpers'][claims] += ' Un solo veredicto por configuración y apartado de fuente; el límite sin cassette tiene su propia tabla.'

    covers = 'chainring_guard_configurations'
    cs = definitions[covers]['validation_rules']['rows_schema']
    cs['columns'].append(column('configuration', 'Presentación o montaje declarado', required=True))
    cs['unique_by'] = [['component', 'mount_row_id', 'configuration']]
    threads = 'lockring_thread_interfaces'
    ts = definitions[threads]['validation_rules']['rows_schema']
    ts['columns'].append(column('configuration', 'Configuración de la interfaz', required=True))
    next(c for c in ts['columns'] if c['key'] == 'target_edition')['required'] = True
    ts['unique_by'] = [['scope', 'owner_role', 'application', 'target_model',
                        'target_edition', 'configuration']]

    for c in fixtures['cases']:
        v = c['values']
        if claims in v:
            full, maximum = [], []
            for row in v[claims]['rows']:
                kind = row['values'].pop('declaration_kind')
                (maximum if kind == 'Piñón máximo' else full).append(row)
            if maximum:
                v[limits] = {'schema_version': 1, 'rows': maximum}
            if full:
                v[claims]['rows'] = full
            else:
                v.pop(claims)
        if c['id'] == 'ds_extender_claim_absent':
            for bucket in ('expected_issue_subset', 'expected_sql_issue_subset'):
                c[bucket] = [{'code': 'required_missing', 'field': form, 'blocking': False}]
        if c['id'] == 'ds_root_roadlink_dm_cassette_pair':
            for row in v[claims]['rows']:
                row['values']['source_scope'] = 'RoadLink DM: 11s Cassette Compatibility'
                if row['values']['smallest_cog_teeth'] == '10':
                    row['values']['conditions'] = ('Lista OEM: Not Supported. Otro apartado declara mejora '
                                                   'parcial sin rendimiento de fábrica; no es aprobación.')

    fast = {'member_role': 'Prueba', 'quantity': '1', 'interface_kind': THREAD,
            'diameter_value': '8', 'diameter_unit': MM, 'pitch_value': '26', 'pitch_unit': TPI}
    target = {'extender_model': 'Extensor de prueba', 'target_derailleur': 'Cambio de prueba',
              'target_cage': 'Jaula A', 'target_speeds': '11',
              'configuration': 'Montaje A', 'source_scope': 'Lista de compatibilidad',
              'smallest_cog_teeth': '11', 'largest_cog_teeth': '42', 'status': 'Recomendado'}
    maximum = {k: val for k, val in target.items() if k != 'smallest_cog_teeth'}
    guard = {'component': 'Placa de prueba', 'mount_row_id': 'r1', 'configuration': 'Presentación A',
             'size_form': 'Valor exacto', 'teeth': '32', 'installed': True}
    mount = rows({'mount_kind': 'ISCG05', 'interface_designation': 'ISCG05'})
    ring = {'scope': 'Rosca propia', 'owner_role': 'Anillo de bloqueo', 'application': 'Cassette',
            'target_model': 'Anillo de prueba', 'target_edition': 'Edición A', 'configuration': 'Rosca A',
            'interface_kind': THREAD, 'diameter_unit': MM, 'diameter_mm': '30',
            'pitch_unit': TPI, 'pitch_tpi': '24'}
    fixtures['cases'].extend([
        case('ds_review_diameter_cannot_embed_pitch_text', 'fastener',
             {'fastener_kind': 'Kit', members: rows({**fast, 'diameter_value': 'M8 x 1.25'})},
             blocking=[('row_shape', members)]),
        case('ds_review_literal_cannot_have_a_second_pitch', 'fastener',
             {'fastener_kind': 'Kit', members: rows({'member_role': 'Pieza', 'quantity': '1',
              'interface_kind': LITERAL, 'interface_designation': 'M8 x 1.25',
              'pitch_value': '26'})}, blocking=[('row_field_applicability', members)]),
        case('ds_review_literal_uncommon_thread_preserved', 'fastener',
             {'fastener_kind': 'Kit', members: rows({'member_role': 'Pieza', 'quantity': '1',
              'interface_kind': LITERAL, 'interface_designation': 'Designación OEM no descompuesta'})}),
        case('ds_review_same_cassette_cannot_have_opposite_statuses', 'derailleur_hanger_extender',
             {claims: rows(target, {**target, 'status': 'No compatible'})}, blocking=[('row_shape', claims)]),
        case('ds_review_different_cage_keeps_own_status', 'derailleur_hanger_extender',
             {claims: rows(target, {**target, 'target_cage': 'Jaula B', 'status': 'No compatible'})}),
        case('ds_review_different_cassette_keeps_own_status', 'derailleur_hanger_extender',
             {claims: rows(target, {**target, 'smallest_cog_teeth': '10', 'status': 'No compatible'})}),
        case('ds_review_maximum_only_cannot_have_two_limits', 'derailleur_hanger_extender',
             {limits: rows(maximum, {**maximum, 'largest_cog_teeth': '46'})}, blocking=[('row_shape', limits)]),
        case('ds_review_maximum_only_has_no_lower_cog', 'derailleur_hanger_extender',
             {limits: rows(target)}, blocking=[('row_shape', limits)]),
        case('ds_review_same_plate_cannot_be_installed_and_uninstalled', 'chainring_guard',
             {'chainring_guard_mounts': mount, covers: rows(guard, {**guard, 'installed': False})},
             blocking=[('row_shape', covers)]),
        case('ds_review_other_presentation_can_change_installed_plate', 'chainring_guard',
             {'chainring_guard_mounts': mount, covers: rows(guard, {**guard, 'installed': False,
                                                       'configuration': 'Presentación B'})}),
        case('ds_review_same_lockring_interface_cannot_have_two_diameters', 'cassette_lockring',
             {threads: rows(ring, {**ring, 'diameter_mm': '41'})}, blocking=[('row_shape', threads)]),
        case('ds_review_other_lockring_interface_not_collapsed', 'cassette_lockring',
             {threads: rows(ring, {**ring, 'configuration': 'Rosca B', 'scope': 'Rosca del objetivo',
                                   'owner_role': 'Componente objetivo', 'diameter_mm': '41'})}),
    ])
    for c in fixtures['cases']:
        if c['template'] != 'derailleur_hanger_extender':
            continue
        v = c['values']
        if claims in v or limits in v:
            v[form] = form_options[2] if claims in v and limits in v else (
                form_options[0] if claims in v else form_options[1])
    fixtures['cases'].append(case(
        'ds_review_initial_scope_gates_maximum_table', 'derailleur_hanger_extender',
        {form: form_options[0], limits: rows(maximum)},
        blocking=[('field_applicability', limits)]))


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

    # Initial contributor helper. Root's successor below replaces the kit use
    # with one explicit pitch value/unit, keeping the old observation legacy.
    members = 'fastener_kit_members'
    templates['fastener']['form_contract'].setdefault('helpers', {})[members] = (
        'Una fila por pieza del kit, con la medida que el fabricante publica '
        'para ESA pieza. El paso no se deduce del nominal: se copia en la forma '
        'publicada, milímetros o hilos por pulgada, y nunca las dos a la vez.')

    # DS-2. A bolt circle is one mounting standard among several. Requiring a
    # BCD and a bolt count left an ISCG05 or a proprietary direct mount with no
    # truthful entry.
    guard = templates['chainring_guard']
    mounts = 'chainring_guard_mounts'
    bcd, iscg05, iscg, direct, other = (
        'Círculo de pernos (BCD)', 'ISCG05', 'ISCG (antiguo)',
        'Montaje directo declarado', 'Otro')
    table(definitions, templates, mounts, 'Montajes declarados de la guarda',
          ('chainring_guard',), [
              column('mount_kind', 'Norma de montaje', 'token', required=True,
                     options=[bcd, iscg05, iscg, direct, other]),
              column('bcd_mm', 'Diámetro del círculo de pernos', 'decimal',
                     unit='mm', positive=True),
              column('bolt_count', 'Cantidad de pernos', 'integer',
                     positive=True),
              column('interface_designation', 'Designación publicada del montaje'),
              column('target_component', 'Componente o cuadro declarado'),
              column('conditions', 'Condiciones declaradas'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          conditions={'bcd_mm': condition('mount_kind', bcd),
                      'bolt_count': condition('mount_kind', bcd),
                      'interface_designation': condition('mount_kind', [iscg05, iscg, direct, other])},
          helper=('La norma con que se fija, declarada por el fabricante. Un '
                  'círculo de pernos no describe un ISCG ni un montaje '
                  'propietario, y la marca no implica un BCD.'))
    retire(guard, ['chainring_bcd_mm', 'bolt_count'])

    # DS-3. The lockring's own thread lived as prose inside an enum label: one
    # token even names two threads, the cog's and the left-hand lockring's.
    lockring = templates['cassette_lockring']
    threads = 'lockring_thread_interfaces'
    table(definitions, templates, threads,
          'Interfaces declaradas del anillo de bloqueo', ('cassette_lockring',),
          thread_columns(), required=True, conditions=thread_conditions(),
          helper=('Copia la designación publicada. El diámetro y el paso se '
                  'declaran cada uno en su unidad, y una pieza con dos roscas '
                  'ocupa dos filas.'))

    # DS-4. Wolf Tooth publishes the reachable cog per derailleur and states
    # that the link does not increase capacity. A bare number carried neither
    # the target nor that limit.
    extender = templates['derailleur_hanger_extender']
    claims = 'hanger_extender_claims'
    table(definitions, templates, claims,
          'Alcance declarado por modelo de cambio', ('derailleur_hanger_extender',),
          [
              column('target_derailleur', 'Cambio trasero declarado', required=True),
              column('target_speeds', 'Velocidades declaradas'),
              column('target_cage', 'Jaula declarada'),
              column('claimed_max_cog_teeth', 'Piñón mayor alcanzable declarado',
                     'integer', unit='T', positive=True),
              column('conditions', 'Condiciones declaradas'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          helper=('El piñón mayor que el fabricante declara alcanzable con ESE '
                  'cambio. Alcance y capacidad son magnitudes distintas: '
                  'RoadLink declara que no aumenta capacidad. Para otro modelo '
                  'conserva sus condiciones OEM, sin heredar esa declaración.'))
    retire(extender, ['claimed_max_cog_teeth'])

    kit = {'fastener_kind': 'Kit'}
    fixtures['cases'].extend([
        # One kit, two members published in different pitch systems.
        case('ds_kit_two_pitch_systems', 'fastener', {**kit, members: rows(
            {'member_role': 'Perno de plato', 'thread_nominal': 'M8',
             'thread_pitch_mm': '0.75', 'quantity': '5'},
            {'member_role': 'Perno de patilla', 'thread_nominal': '3/8"',
             'thread_tpi': '26', 'quantity': '1'})},
             sources=[PARK_THREADS]),
        case('ds_kit_metric_nominal_tpi_pitch', 'fastener', {**kit, members: rows(
            {'member_role': 'Eje', 'thread_nominal': '10 mm',
             'thread_tpi': '26', 'quantity': '1'})},
             sources=[PARK_THREADS]),
        # A guard on frame tabs has no bolt circle to declare.
        case('ds_guard_iscg05', 'chainring_guard', {mounts: rows(
            {'mount_kind': iscg05, 'interface_designation': 'ISCG05',
             'target_component': 'Cuadro sintético'})}),
        case('ds_guard_bolt_circle', 'chainring_guard', {mounts: rows(
            {'mount_kind': bcd, 'bcd_mm': '104', 'bolt_count': '4'})}),
        case('ds_guard_iscg_has_no_bcd', 'chainring_guard', {mounts: rows(
            {'mount_kind': iscg05, 'bcd_mm': '104'})},
             blocking=[('row_field_applicability', mounts)]),
        case('ds_guard_mount_absent', 'chainring_guard', {'material': 'Aluminio'},
             pending=[('required_missing', mounts)]),
        # The fixed-cog token names two threads; they become two rows, and the
        # left-hand one keeps its hand.
        case('ds_lockring_two_threads', 'cassette_lockring', {threads: rows(
            {'scope': 'Rosca del piñón', 'interface_kind': THREAD,
             'diameter_unit': IN, 'diameter_in': '1.37', 'pitch_unit': TPI,
             'pitch_tpi': '24', 'thread_hand': 'Derecha'},
            {'scope': 'Contratuerca', 'interface_kind': THREAD,
             'diameter_unit': IN, 'diameter_in': '1.29', 'pitch_unit': TPI,
             'pitch_tpi': '24', 'thread_hand': 'Izquierda'})},
             sources=[SHELDON_L]),
        case('ds_lockring_metric_diameter_tpi_pitch', 'cassette_lockring', {threads: rows(
            {'scope': 'Rosca', 'interface_kind': THREAD, 'diameter_unit': MM,
             'diameter_mm': '30', 'pitch_unit': TPI, 'pitch_tpi': '26'})},
             sources=[PARK_THREADS]),
        case('ds_lockring_two_pitch_units', 'cassette_lockring', {threads: rows(
            {'scope': 'Rosca', 'interface_kind': THREAD, 'diameter_unit': MM,
             'diameter_mm': '30', 'pitch_unit': MM, 'pitch_mm': '1',
             'pitch_tpi': '26'})},
             blocking=[('row_field_applicability', threads)]),
        case('ds_lockring_spline_has_no_pitch', 'cassette_lockring', {threads: rows(
            {'scope': 'Estriado', 'interface_kind': SPLINE, 'diameter_unit': MM,
             'diameter_mm': '34', 'pitch_mm': '1'})},
             blocking=[('row_field_applicability', threads)]),
        case('ds_lockring_thread_absent', 'cassette_lockring',
             {'smallest_cog_fit': '11T'},
             pending=[('required_missing', threads)]),
        # The reachable cog belongs to a named derailleur, and never to capacity.
        case('ds_extender_scoped_claim', 'derailleur_hanger_extender', {claims: rows(
            {'target_derailleur': 'Cambio sintético de referencia',
             'target_speeds': '11', 'target_cage': 'Corta',
             'claimed_max_cog_teeth': '40',
             'conditions': 'El fabricante declara alcance, no capacidad'})},
             sources=[WOLF_LINK]),
        case('ds_extender_two_derailleurs', 'derailleur_hanger_extender', {claims: rows(
            {'target_derailleur': 'Cambio A', 'claimed_max_cog_teeth': '40'},
            {'target_derailleur': 'Cambio B', 'claimed_max_cog_teeth': '36'})}),
        case('ds_extender_claim_absent', 'derailleur_hanger_extender',
             {'hanger_interface': 'Patilla estándar (M10x1)'},
             pending=[('required_missing', claims)]),
    ])

    integrate_root_boundaries(templates, definitions, fixtures)
    integrate_review_findings(templates, definitions, fixtures)
    # Dart's harness compares a set; SQL keeps one issue per invalid cell.
    # These two fixtures deliberately populate two forbidden cells.
    for c in fixtures['cases']:
        if c['id'] in ['ds_root_no_thread_pitch_on_plain_member',
                       'ds_root_track_cannot_claim_cassette_outer_cog']:
            c['expected_sql_blocking'] = deepcopy(c['expected_blocking']) * 2
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Drivetrain small parts reviewed successor',
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
    path = RESEARCH / 'drivetrain-small-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'drivetrain-small-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
