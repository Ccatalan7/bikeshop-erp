#!/usr/bin/env python3
"""Compile an unpublished successor for hangers, pulleys and chain guides.

No DB, migration, publication, assignment or product filling. Three axes stay
apart: the physical piece or occurrence, how it mounts, and what a document
claims about a frame or a derailleur. A code shared by two parts is not an
identity, and a package of two pieces is not a guide plus a tension pulley.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition,
    remove_unpublished_field, rows)
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column, retire
from compile_product_spec_catalog import validate_contract

FAMILIES = ('derailleur_hanger', 'derailleur_pulley', 'chain_guide')
PREIMAGE = RESEARCH / 'existing-drivetrain-service-parts-preimage-2026-09-08.json'
PREIMAGE_SHA = '84cbb1c31d076cd27faa29663243f209f85a784abede0abcb4b656f21607cb3c'
SRAM = 'https://www.sram.com/en/learn/understanding-udh-and-full-mount'
PARK_RD = 'https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works'
WM25 = 'https://wheelsmfg.com/products/derailleur-hanger-25'
WM70 = 'https://wheelsmfg.com/products/derailleur-hanger-70'
ONEUP = 'https://www.oneupcomponents.com/products/bashguide-v2-iscg05'
ONEUP_FIT = ('https://eu.oneupcomponents.com/blogs/bashguides-chainguides/'
             'bashguard-chainguide-install-instructions')
SYNTHETIC = 'https://example.invalid/synthetic'
EVIDENCE = 'spec_evidence_source'
DOCUMENTED_MODEL = 'Modelo documentado'
DOCUMENTED_INTERFACE = 'Interfaz o estándar documentado'
SCOPES = [DOCUMENTED_MODEL, DOCUMENTED_INTERFACE]


def _add(definitions, template, key, label, kind, *, role='measurement',
         semantic='compatibility', unit=None, options=(), rules=None,
         allowed=ALWAYS, required=NEVER, helper=None):
    if key in definitions:
        raise ValueError('Refuse to overwrite a definition: ' + key)
    definitions[key] = new_definition(key, label, kind, (template['key'],),
                                      unit=unit, options=options, rules=rules)
    add_field(template, key, role, semantic, allowed=allowed,
              required=required, helper=helper)


def _retire(template, keys):
    retire(template, list(keys))
    for key in keys:
        template['form_contract']['semantic_roles'][key] = 'legacy'


def _drop(definitions, template, key):
    if definitions[key]['origin'] != 'new':
        raise ValueError('Cannot remove a published observation: ' + key)
    remove_unpublished_field(template, key)
    del definitions[key]


def _claim_columns(subject, *extra):
    """A documented claim: either a named model or a declared interface."""
    return [
        column('claim_identity', 'Identificación de esta declaración', required=True),
        column('scope_kind', 'Alcance de la declaración', 'token',
               required=True, options=SCOPES),
        column('brand', 'Marca ' + subject),
        column('model', 'Modelo ' + subject),
        column('generation', 'Generación o edición'),
        column('years', 'Años documentados'),
        column('declared_interface', 'Interfaz o estándar declarado'),
        *extra,
        column('conditions', 'Condiciones de la declaración'),
        column('source_document', 'Documento o envase identificado', required=True),
        column('source_url', 'URL del documento, si existe', 'url'),
    ]


def _claim_conditions():
    model = condition('scope_kind', DOCUMENTED_MODEL)
    interface = condition('scope_kind', DOCUMENTED_INTERFACE)
    return {'allowed_when': {'brand': deepcopy(model), 'model': deepcopy(model),
                             'declared_interface': deepcopy(interface)},
            'required_when': {'brand': deepcopy(model), 'model': deepcopy(model),
                              'declared_interface': deepcopy(interface)}}


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
    for key, actual in published.items():
        if key not in definitions:
            continue
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
            'validation_rules')}
        definitions[key].update(origin='existing', used_by=[
            f for f in FAMILIES
            if any(x['key'] == key for x in templates[f]['fields'])])

    _hanger(definitions, templates['derailleur_hanger'])
    _pulley(definitions, templates['derailleur_pulley'])
    _guide(definitions, templates['chain_guide'])

    for key in FAMILIES:
        template = templates[key]
        validate_contract(key, template['form_contract'], definitions,
                          {f['key'] for f in template['fields']})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definitions in drivetrain service packet')

    catalog = {**base,
               'title': 'Hanger, pulley and chain guide pieces, mounts and claims',
               'templates': [templates[k] for k in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'source_urls': [SRAM, PARK_RD, WM25, WM70, ONEUP, ONEUP_FIT],
               'stats': {'templates': len(FAMILIES),
                         'definitions': len(definitions),
                         'field_uses': sum(len(t['fields'])
                                           for t in templates.values())}}
    return catalog, {'cases': _cases(), 'pending_cases': _pending()}


def _hanger(definitions, template):
    c = template['form_contract']
    # SRAM separates the frame that accepts UDH from the hanger installed on
    # it, and a Full Mount derailleur replaces that hanger. One selector cannot
    # hold the frame end and the derailleur end at once, so it is retired.
    _retire(template, ['hanger_interface'])
    c['allowed_options'].pop('hanger_interface', None)
    _add(definitions, template, 'hanger_frame_interface',
         'Interfaz de este lado del cuadro', 'single_select', role='primary',
         required=ALWAYS, options=['Interfaz UDH del cuadro',
             'Puntera con anclaje propio del cuadro', 'Con uña / claw sobre el eje',
             'Otra interfaz OEM documentada'],
         helper='Cómo se une esta pieza al cuadro. UDH es una patilla física '
         'sobre una interfaz estandarizada; un cambio Full Mount sustituye la '
         'patilla y por eso no es una opción de esta ficha.')
    _add(definitions, template, 'hanger_derailleur_interface',
         'Interfaz de este lado del cambio', 'single_select', role='primary',
         required=ALWAYS, options=['Rosca M10 x 1', 'Enlace direct mount',
                                   'Otra interfaz OEM documentada'],
         helper='Qué recibe el cambio en esta pieza. No se deduce de la '
         'interfaz del cuadro ni del perno de sujeción.')
    # The manufacturer code is an interchange reference, not the identity of
    # the product: two codes can share a bolt and not share a fit.
    c['roles']['hanger_model_code'] = 'declaration'
    c['semantic_roles']['hanger_model_code'] = 'declaration'
    c['required_when']['hanger_model_code'] = deepcopy(NEVER)
    c['helpers']['hanger_model_code'] = (
        'Código de intercambio publicado por el fabricante para esta pieza. '
        'El modelo y el MPN del producto pertenecen a su ficha de identidad, '
        'no a este campo.')
    c['helpers']['bolt_pattern'] = (
        'Sujeción publicada, por ejemplo un perno M8. Dos patillas distintas '
        'comparten perno sin compartir código ni calce: no identifica la pieza.')
    definitions['compatible_frames']['validation_rules'] = {'rows_schema': {
        'version': 1, 'unique_by': [['claim_identity']],
        'columns': _claim_columns('del cuadro')}}
    definitions['compatible_frames']['label'] = 'Cuadros o interfaces declarados'
    c['row_conditions'] = {'version': 1,
                           'fields': {'compatible_frames': _claim_conditions()}}
    c['helpers']['compatible_frames'] = (
        'Declaraciones documentadas. Cuando la fuente no enumera modelos se '
        'declara la interfaz; no se inventa un nombre de cuadro para llenar '
        'una celda, y un año ausente en la fuente se deja ausente.')
    for key in ('hanger_frame_interface', 'hanger_derailleur_interface',
                'hanger_model_code', 'bolt_pattern'):
        c['prerequisites'][key] = [EVIDENCE]


def _pulley(definitions, template):
    c = template['form_contract']
    for key in ('pulley_position', 'pulley_bearing_type', 'pulley_width_class'):
        _drop(definitions, template, key)
    _add(definitions, template, 'pulley_package_kind',
         'Qué trae este envase', 'single_select', role='primary',
         semantic='intrinsic', required=ALWAYS,
         options=['Roldana individual', 'Par de roldanas en el mismo envase'],
         helper='Un par en el mismo envase puede ser dos piezas iguales o dos '
         'repuestos. No se deduce de él una guía superior y una tensión.')
    single = condition('pulley_package_kind', 'Roldana individual')
    pair = condition('pulley_package_kind', 'Par de roldanas en el mismo envase')
    c['allowed_when']['pulley_teeth'] = deepcopy(single)
    c['required_when']['pulley_teeth'] = deepcopy(single)
    for key, label, unit, opts, helper in (
            ('pulley_declared_position', 'Posición declarada por la fuente',
             None, ['Guía (superior)', 'Tensión (inferior)',
                    'La fuente no declara la posición'],
             'Park distingue la roldana guía superior de la de tensión '
             'inferior. Si la fuente no lo dice, se declara así y no se supone.'),
            ('pulley_bearing_construction', 'Construcción del apoyo', None,
             ['Buje', 'Rodamiento de bolas', 'Otra construcción OEM'],
             'Cómo gira la roldana. El material de los elementos es otro campo: '
             'cerámico no es una construcción alternativa a un rodamiento.'),
            ('pulley_bearing_element_material', 'Material de los elementos', None,
             ['Acero', 'Cerámico', 'Otro material OEM'],
             'Sólo cuando hay elementos rodantes documentados.'),
            ('pulley_tooth_profile', 'Perfil de dentado declarado', None,
             ['Dentado convencional', 'Narrow-wide', 'Otro perfil OEM'],
             'Perfil publicado del dentado. No se deriva del número de '
             'velocidades ni del ancho.'),
    ):
        _add(definitions, template, key, label, 'single_select', role='primary',
             semantic='intrinsic', options=opts, allowed=deepcopy(single),
             helper=helper)
    c['allowed_when']['pulley_bearing_element_material'] = {'kind': 'when', 'rows': [
        [{'field': 'pulley_package_kind', 'operator': 'eq', 'value_type': 'token',
          'value': 'Roldana individual'},
         {'field': 'pulley_bearing_construction', 'operator': 'in',
          'value_type': 'token',
          'value': ['Rodamiento de bolas', 'Otra construcción OEM']}]]}
    for key, label in (('pulley_outer_diameter_mm', 'Diámetro exterior'),
                       ('pulley_width_mm', 'Ancho de la roldana'),
                       ('pulley_bore_diameter_mm', 'Diámetro del alojamiento')):
        _add(definitions, template, key, label, 'number', unit='mm',
             rules={'positive': True}, allowed=deepcopy(single),
             helper='Cota publicada de esta pieza. El ancho no se deriva del '
             'número de velocidades.')
    _add(definitions, template, 'pulley_declared_speeds',
         'Velocidades declaradas por la fuente', 'multi_select',
         role='declaration', semantic='declaration',
         options=['1', '5', '6', '7', '8', '9', '10', '11', '12', '13'],
         helper='Rango que declara la fuente. No determina ancho, perfil ni '
         'compatibilidad con un cambio concreto.')
    _add(definitions, template, 'pulley_units',
         'Roldanas incluidas en este envase', 'json', role='contents',
         semantic='contents', allowed=deepcopy(pair), required=deepcopy(pair),
         rules={'rows_schema': {'version': 1, 'unique_by': [['unit_identity']],
             'columns': [
                 column('unit_identity', 'Identidad de esta roldana', required=True),
                 column('declared_position', 'Posición declarada', 'token',
                        options=['Guía (superior)', 'Tensión (inferior)',
                                 'La fuente no declara la posición']),
                 column('teeth', 'Dientes de esta roldana', 'integer',
                        required=True, positive=True),
                 column('bearing_construction', 'Construcción del apoyo', 'token',
                        options=['Buje', 'Rodamiento de bolas',
                                 'Otra construcción OEM']),
                 column('bearing_element_material', 'Material de los elementos',
                        'token', options=['Acero', 'Cerámico', 'Otro material OEM']),
                 column('tooth_profile', 'Perfil de dentado', 'token',
                        options=['Dentado convencional', 'Narrow-wide',
                                 'Otro perfil OEM']),
                 column('outer_diameter_mm', 'Diámetro exterior', 'decimal',
                        unit='mm', positive=True),
                 column('width_mm', 'Ancho', 'decimal', unit='mm', positive=True),
                 column('bore_diameter_mm', 'Diámetro del alojamiento', 'decimal',
                        unit='mm', positive=True),
                 column('source_document', 'Documento o envase identificado',
                        required=True),
                 column('source_url', 'URL del documento, si existe', 'url'),
             ]}},
         helper='Cada ocurrencia física con su identidad y su fuente. Dos '
         'piezas iguales son dos filas; ninguna posición se supone.')
    _add(definitions, template, 'pulley_unit_count',
         'Roldanas documentadas en este envase', 'number', role='contents',
         semantic='contents', rules={'integer': True, 'min': '2', 'max': '2'},
         allowed=deepcopy(pair), required=deepcopy(pair))
    c['row_conditions'] = {'version': 1, 'fields': {'pulley_units': {
        'allowed_when': {'bearing_element_material': {'kind': 'when', 'rows': [[
            {'field': 'bearing_construction', 'operator': 'in',
             'value_type': 'token',
             'value': ['Rodamiento de bolas', 'Otra construcción OEM']}]]}}}}}
    c['row_coherence'] = {'version': 2, 'links': [], 'cardinalities': [
        {'id': 'documented_pulleys_in_the_package', 'field': 'pulley_units',
         'total_field': 'pulley_unit_count'}]}
    definitions['compatible_derailleur_models']['validation_rules'] = {
        'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
                        'columns': _claim_columns('del cambio')}}
    definitions['compatible_derailleur_models']['label'] = (
        'Cambios o interfaces declarados')
    c['row_conditions']['fields']['compatible_derailleur_models'] = _claim_conditions()
    for key in ('pulley_declared_speeds', 'pulley_declared_position',
                'pulley_tooth_profile'):
        c['prerequisites'][key] = [EVIDENCE]


def _guide(definitions, template):
    c = template['form_contract']
    # A published two-value selector cannot hold a guide that documents two
    # mounting standards, and its domain has no ISCG-03. Mounts become
    # occurrences; the old reading is preserved as legacy.
    _retire(template, ['chain_guide_mount_type'])
    _drop(definitions, template, 'chain_speeds_supported')
    _add(definitions, template, 'chain_guide_mount_options',
         'Montajes documentados de esta guía', 'json', role='primary',
         semantic='compatibility', required=ALWAYS,
         rules={'rows_schema': {'version': 1, 'unique_by': [['option_identity']],
             'columns': [
                 column('option_identity', 'Identificación de este montaje',
                        required=True),
                 column('mount_standard', 'Estándar de montaje declarado',
                        required=True),
                 column('hardware_included', 'Trae su herrajería', 'boolean'),
                 column('source_document', 'Documento o envase identificado',
                        required=True),
                 column('source_url', 'URL del documento, si existe', 'url'),
             ]}},
         helper='Un SKU puede documentar más de un estándar. Tener los '
         'anclajes no certifica un cuadro: las exclusiones van aparte.')
    _add(definitions, template, 'chain_guide_included_parts',
         'Piezas incluidas en este envase', 'json', role='contents',
         semantic='contents',
         rules={'rows_schema': {'version': 1, 'unique_by': [['part_identity']],
             'ordered_pairs': [['chainring_teeth_min', 'chainring_teeth_max']],
             'columns': [
                 column('part_identity', 'Identidad de esta pieza', required=True),
                 column('part_role', 'Función de esta pieza', 'token',
                        required=True,
                        options=['Placa protectora', 'Guía superior',
                                 'Guía o rodillo inferior', 'Herrajes y separadores',
                                 'Otra pieza OEM']),
                 column('chainring_teeth_min', 'Plato mínimo de esta pieza',
                        'integer', unit='T', positive=True),
                 column('chainring_teeth_max', 'Plato máximo de esta pieza',
                        'integer', unit='T', positive=True),
                 column('installed_from_factory', 'Viene instalada de fábrica',
                        'boolean', required=True),
                 column('weight_g', 'Peso publicado de esta configuración',
                        'decimal', unit='g', positive=True),
                 column('source_document', 'Documento o envase identificado',
                        required=True),
                 column('source_url', 'URL del documento, si existe', 'url'),
             ]}},
         helper='Componentes realmente incluidos y cuál viene montado. Un '
         'rango total de platos no vuelve intercambiables sus placas.')
    _add(definitions, template, 'chain_guide_frame_exclusions',
         'Exclusiones documentadas de cuadro', 'json', role='declaration',
         semantic='declaration',
         rules={'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
             'columns': _claim_columns('del cuadro')}},
         helper='Incompatibilidades que publica la fuente, por modelo y '
         'generación o por clase de cuadro.')
    _add(definitions, template, 'chain_guide_chainline_adjustment_mm',
         'Recorrido de ajuste de línea de cadena', 'number', unit='mm',
         rules={'positive': True},
         helper='Recorrido que permite el ajuste, no una línea de cadena. Una '
         'ficha que rotula «Chainline: 7,5 mm de ajuste» declara recorrido.')
    _add(definitions, template, 'chain_guide_chainline_datum',
         'Datum de la línea de cadena declarada', 'text',
         helper='Desde qué referencia mide la fuente la línea de cadena '
         'instalada. Sin datum, la cifra no se compara con otra ficha.')
    c['prerequisites']['chainline_mm'] = ['chain_guide_chainline_datum', EVIDENCE]
    c['helpers']['chainline_mm'] = (
        'Línea de cadena instalada según la fuente y su datum. No recibe el '
        'recorrido de ajuste, que tiene su propio campo.')
    c['helpers']['chainring_teeth_min'] = (
        'Capacidad total declarada del SKU. Es la unión de sus piezas '
        'incluidas, no una garantía de que cualquiera de ellas sirva.')
    c['row_conditions'] = {'version': 1, 'fields': {
        'chain_guide_frame_exclusions': _claim_conditions()}}
    for key in ('chain_guide_chainline_adjustment_mm', 'chain_guide_chainline_datum',
                'chainring_teeth_min', 'chainring_teeth_max'):
        c['prerequisites'][key] = [EVIDENCE]


def _claim(identity, scope, **extra):
    return {'claim_identity': identity, 'scope_kind': scope,
            'source_document': 'Publicación del fabricante identificada', **extra}


def _cases():
    def build(prefix, family, i, v, forbidden=(), **k):
        result = case(prefix + i, family, v, **k)
        if forbidden:
            result['forbidden_issue_fields'] = list(forbidden)
        return result

    def hg(i, v, **k): return build('hg_', 'derailleur_hanger', i, v, **k)
    def pu(i, v, **k): return build('pu_', 'derailleur_pulley', i, v, **k)
    def cg(i, v, **k): return build('cg_', 'chain_guide', i, v, **k)

    def unit(identity, teeth, **extra):
        return {'unit_identity': identity, 'teeth': teeth,
                'declared_position': 'La fuente no declara la posición',
                'source_document': 'Envase identificado', **extra}
    ends = {'spec_evidence_source': SYNTHETIC,
            'hanger_frame_interface': 'Puntera con anclaje propio del cuadro',
            'hanger_derailleur_interface': 'Rosca M10 x 1'}
    single = {'pulley_package_kind': 'Roldana individual',
              'spec_evidence_source': SYNTHETIC, 'pulley_teeth': '11'}
    pair = {'pulley_package_kind': 'Par de roldanas en el mismo envase',
            'spec_evidence_source': SYNTHETIC, 'pulley_unit_count': '2'}
    mount = {'option_identity': 'ISCG-05', 'mount_standard': 'ISCG-05',
             'source_document': 'Envase identificado'}
    guide = {'spec_evidence_source': SYNTHETIC,
             'chain_guide_mount_options': rows(mount)}
    return [
        hg('a_hanger_names_both_of_its_ends', ends),
        hg('a_udh_frame_interface_still_needs_its_derailleur_end', {
            **ends, 'hanger_frame_interface': 'Interfaz UDH del cuadro'},
           sources=[SRAM]),
        hg('a_hanger_without_its_ends_is_pending', {'spec_evidence_source': SYNTHETIC},
           pending=[('required_missing', 'hanger_frame_interface'),
                    ('required_missing', 'hanger_derailleur_interface')]),
        hg('the_interchange_code_is_not_required', ends,
           forbidden=['hanger_model_code'], sources=[WM25, WM70]),
        hg('two_codes_share_a_bolt_without_sharing_identity', {
            **ends, 'hanger_model_code': 'DROPOUT-25',
            'bolt_pattern': 'Un perno M8'}, sources=[WM25, WM70]),
        hg('a_claim_by_frame_model_names_its_model', {**ends,
            'compatible_frames': rows(_claim('c1', DOCUMENTED_MODEL,
                brand='Marca sintética', model='Modelo sintético',
                years='2019-2021'))}),
        hg('a_claim_by_interface_needs_no_frame_name', {**ends,
            'compatible_frames': rows(_claim('c1', DOCUMENTED_INTERFACE,
                declared_interface='Interfaz UDH'))}, sources=[SRAM]),
        hg('a_model_claim_cannot_hide_behind_an_interface', {**ends,
            'compatible_frames': rows(_claim('c1', DOCUMENTED_MODEL,
                brand='Marca', model='Modelo', declared_interface='Interfaz UDH'))},
           blocking=[('row_field_applicability', 'compatible_frames')]),
        hg('an_interface_claim_cannot_invent_a_frame', {**ends,
            'compatible_frames': rows(_claim('c1', DOCUMENTED_INTERFACE,
                declared_interface='Interfaz UDH', brand='Marca inventada'))},
           blocking=[('row_field_applicability', 'compatible_frames')]),
        hg('the_same_claim_twice_blocks', {**ends, 'compatible_frames': rows(
            _claim('c1', DOCUMENTED_INTERFACE, declared_interface='UDH'),
            _claim('c1', DOCUMENTED_INTERFACE, declared_interface='UDH'))},
           blocking=[('row_shape', 'compatible_frames')]),
        hg('a_claim_without_its_document_is_pending', {**ends,
            'compatible_frames': {'schema_version': 1, 'rows': [{'id': 'r1',
                'values': {'claim_identity': 'c1', 'scope_kind': DOCUMENTED_INTERFACE,
                           'declared_interface': 'UDH'}, 'sources': []}]}},
           pending=[('row_incomplete', 'compatible_frames')]),
        hg('a_missing_year_is_left_missing', {**ends, 'compatible_frames': rows(
            _claim('c1', DOCUMENTED_MODEL, brand='Marca', model='Modelo'))},
           sources=[WM25]),
        hg('legacy_interface_and_mount_are_preserved', {**ends,
            'hanger_interface': 'UDH', 'rear_derailleur_mount_type': 'Direct mount',
            'compatible_frame_hint': 'Lectura histórica'}),
        pu('a_single_pulley_declares_its_teeth', single),
        pu('a_single_pulley_keeps_its_own_dimensions', {
            **single, 'pulley_outer_diameter_mm': '32.4',
            'pulley_width_mm': '6.5', 'pulley_bore_diameter_mm': '5',
            'pulley_declared_speeds': ['11'], 'pulley_tooth_profile': 'Narrow-wide'}),
        pu('a_bushing_has_no_element_material', {
            **single, 'pulley_bearing_construction': 'Buje',
            'pulley_bearing_element_material': 'Cerámico'},
           blocking=[('field_applicability', 'pulley_bearing_element_material')]),
        pu('a_ceramic_element_needs_a_rolling_construction', {
            **single, 'pulley_bearing_construction': 'Rodamiento de bolas',
            'pulley_bearing_element_material': 'Cerámico'}),
        pu('a_pair_cannot_carry_one_scalar_teeth', {**pair, 'pulley_teeth': '11'},
           blocking=[('field_applicability', 'pulley_teeth')]),
        pu('a_pair_cannot_carry_one_scalar_profile', {
            **pair, 'pulley_tooth_profile': 'Narrow-wide'},
           blocking=[('field_applicability', 'pulley_tooth_profile')]),
        pu('two_identical_units_are_not_a_guide_and_a_tension', {**pair,
            'pulley_units': rows(unit('Roldana A', '11'), unit('Roldana B', '11'))},
           sources=[PARK_RD]),
        pu('a_declared_pair_of_positions_is_kept_as_declared', {**pair,
            'pulley_units': rows(
                unit('Superior', '11', declared_position='Guía (superior)'),
                unit('Inferior', '11', declared_position='Tensión (inferior)'))},
           sources=[PARK_RD]),
        pu('a_pair_with_one_documented_unit_stays_pending', {**pair,
            'pulley_units': rows(unit('Roldana A', '11'))},
           pending=[('row_cardinality_pending', 'pulley_units')]),
        pu('the_same_unit_twice_blocks', {**pair, 'pulley_units': rows(
            unit('Roldana A', '11'), unit('Roldana A', '13'))},
           blocking=[('row_shape', 'pulley_units')]),
        pu('a_bushing_row_has_no_element_material', {**pair, 'pulley_units': rows(
            unit('Roldana A', '11', bearing_construction='Buje',
                 bearing_element_material='Cerámico'), unit('Roldana B', '11'))},
           blocking=[('row_field_applicability', 'pulley_units')]),
        pu('a_unit_without_its_document_is_pending', {**pair, 'pulley_units': {
            'schema_version': 1, 'rows': [{'id': 'r1', 'values': {
                'unit_identity': 'Roldana A', 'teeth': '11'}, 'sources': []},
                {'id': 'r2', 'values': {'unit_identity': 'Roldana B',
                 'teeth': '11', 'source_document': 'Envase'}, 'sources': []}]}},
           pending=[('row_incomplete', 'pulley_units')]),
        pu('a_claim_by_derailleur_model', {**single,
            'compatible_derailleur_models': rows(_claim('c1', DOCUMENTED_MODEL,
                brand='Marca sintética', model='Modelo sintético'))}),
        pu('a_claim_by_declared_interface', {**single,
            'compatible_derailleur_models': rows(_claim('c1', DOCUMENTED_INTERFACE,
                declared_interface='Jaula sintética de 11v'))}),
        pu('the_cage_length_declaration_is_preserved', {
            **single, 'derailleur_cage_length': 'GS / media'}),
        cg('a_guide_documents_two_mount_standards', {**guide,
            'chain_guide_mount_options': rows(
                {'option_identity': 'ISCG-03', 'mount_standard': 'ISCG-03',
                 'source_document': 'Envase identificado'}, mount)}),
        cg('a_guide_without_its_mounts_is_pending', {'spec_evidence_source': SYNTHETIC},
           pending=[('required_missing', 'chain_guide_mount_options')]),
        cg('the_same_mount_option_twice_blocks', {**guide,
            'chain_guide_mount_options': rows(mount, mount)},
           blocking=[('row_shape', 'chain_guide_mount_options')]),
        cg('included_plates_keep_their_own_ranges', {**guide,
            'chainring_teeth_min': '28', 'chainring_teeth_max': '36',
            'chain_guide_included_parts': rows(
                {'part_identity': 'Placa 28-30T', 'part_role': 'Placa protectora',
                 'chainring_teeth_min': '28', 'chainring_teeth_max': '30',
                 'installed_from_factory': False, 'weight_g': '90',
                 'source_document': 'Instrucciones identificadas'},
                {'part_identity': 'Placa 32-34T', 'part_role': 'Placa protectora',
                 'chainring_teeth_min': '32', 'chainring_teeth_max': '34',
                 'installed_from_factory': True, 'weight_g': '105',
                 'source_document': 'Instrucciones identificadas'},
                {'part_identity': 'Placa 36T', 'part_role': 'Placa protectora',
                 'chainring_teeth_min': '36', 'chainring_teeth_max': '36',
                 'installed_from_factory': False, 'weight_g': '110',
                 'source_document': 'Instrucciones identificadas'})},
           sources=[ONEUP, ONEUP_FIT]),
        cg('an_inverted_plate_range_blocks', {**guide,
            'chain_guide_included_parts': rows(
                {'part_identity': 'Placa', 'part_role': 'Placa protectora',
                 'chainring_teeth_min': '36', 'chainring_teeth_max': '28',
                 'installed_from_factory': True,
                 'source_document': 'Instrucciones identificadas'})},
           blocking=[('row_shape', 'chain_guide_included_parts')]),
        cg('an_inverted_declared_capacity_blocks', {**guide,
            'chainring_teeth_min': '36', 'chainring_teeth_max': '28'},
           blocking=[('range_order', 'chainring_teeth_min'),
                     ('range_order', 'chainring_teeth_max')]),
        cg('the_adjustment_travel_is_not_a_chainline', {**guide,
            'chain_guide_chainline_adjustment_mm': '7.5'},
           forbidden=['chainline_mm'], sources=[ONEUP]),
        cg('a_chainline_without_its_datum_is_pending', {**guide,
            'chainline_mm': '52'},
           pending=[('prerequisite', 'chainline_mm')]),
        cg('a_chainline_with_its_datum_is_complete', {**guide,
            'chainline_mm': '52',
            'chain_guide_chainline_datum': 'Eje del pedalier al centro del plato'}),
        cg('an_exclusion_by_frame_class', {**guide,
            'chain_guide_frame_exclusions': rows(_claim('e1', DOCUMENTED_INTERFACE,
                declared_interface='Cuadros de pivote alto',
                conditions='La fuente ofrece otra referencia para esa clase'))},
           sources=[ONEUP]),
        cg('an_exclusion_by_model_and_generation', {**guide,
            'chain_guide_frame_exclusions': rows(_claim('e1', DOCUMENTED_MODEL,
                brand='Marca sintética', model='Modelo sintético',
                generation='Generación 5 y 6'))}, sources=[ONEUP]),
        cg('legacy_mount_and_teeth_are_preserved', {**guide,
            'chain_guide_mount_type': 'ISCG 05', 'chainring_teeth': '32-38T'}),
    ]


def _pending():
    return [
        {'id': 'hanger_extender_titles_await_assignment_review',
         'required_result': 'assignment_review_required',
         'reason': 'Three of the 23 titles bound to this family read as hanger '
                   'extenders and two of them state a sprocket capacity. The '
                   'derailleur_hanger_extender family already exists; the move '
                   'needs the assignment queue and product evidence, not a title.'},
        {'id': 'hanger_and_pulley_identity_codes_belong_to_the_product',
         'required_result': 'identity_pending',
         'reason': 'Titles carry manufacturer codes while model and '
                   'manufacturer_sku are empty in all 33 records. Identity is '
                   'resolved in the product, never in a second store here.'},
        {'id': 'full_mount_derailleur_is_not_a_hanger_variant',
         'required_result': 'outside_this_family',
         'reason': 'SRAM documents that a Full Mount derailleur replaces the '
                   'hanger and mounts to the frame; it is not an option of a '
                   'hanger sheet.'},
        {'id': 'pulley_rotation_and_profile_need_the_exact_manual',
         'required_result': 'unknown_without_model_scoped_manual',
         'reason': 'The Shimano service manual cited in the source notes could '
                   'not be opened in this round; no orientation, torque or '
                   'tooth profile is extrapolated to generic inventory.'},
        {'id': 'chain_guide_line_wide_interchange_is_not_a_sku_fact',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'The manufacturer states plates and top guides interchange '
                   'across its own line; that is a cross-product claim and does '
                   'not describe the contents of one package.'},
        {'id': 'oem_relation_and_editor_validation_pending',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Directed OEM relations and the real editor round are not '
                   'exercised by this packet.'},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-drivetrain-service-parts-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-drivetrain-service-parts-cases-2026-09-08.json',
               fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'production_writes': False, 'fill': False}))
