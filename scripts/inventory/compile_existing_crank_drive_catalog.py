#!/usr/bin/env python3
"""Compile an unpublished successor for crankset, crank_arm and chainring.

No DB, migration, publication, assignment or product filling. The shell, the
spindle and the crank seat are three different questions; a package of two arms
or of several chainrings is not one piece; construction in one, two or three
pieces is not the number of chainrings; and a bolt circle is not a pattern. An
OEM pairing between chainrings, and the bottom bracket a crankset needs, keep
every documented combination with its own condition.
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
from compile_combined_control_catalog import both
from compile_existing_shifting_catalog import (
    DOCUMENTED_INTERFACE, DOCUMENTED_MODEL, _add, _claim_columns,
    _claim_conditions, _drop, _retire)
from compile_product_spec_catalog import validate_contract

FAMILIES = ('crankset', 'crank_arm', 'chainring')
PREIMAGE = RESEARCH / 'existing-crank-drive-preimage-2026-09-08.json'
PREIMAGE_SHA = '3b947d4d0598e8707062999ad9b03617ee75e951ee64286a9339cef204424578'
TAPER = 'https://www.sheldonbrown.com/bbtaper.html'
PARK_CRANK = ('https://www.parktool.com/en-us/blog/repair-help/'
              'how-to-remove-and-install-a-crank')
C449 = 'https://productinfo.shimano.com/en/compatibility/C-449'
EV8000 = ('https://dassets.shimano.com/content/dam/global/cg1SHICCycling/'
          'final/ev/ev/EV-FC-M8000-3849B.pdf')
SYNTHETIC = 'https://example.invalid/synthetic'
EVIDENCE = 'spec_evidence_source'

SINGLE_RING, RING_SET = 'Plato individual', 'Juego de platos en el mismo envase'
LEFT, RIGHT, PAIR = 'Izquierda', 'Derecha', 'Par'
POSITIONS = ['Exterior', 'Medio', 'Interior', 'Único']
BOLT_CIRCLES = ['BCD 4 pernos', 'BCD 5 pernos']
DIRECT_MOUNTS = ['Direct mount Shimano', 'Direct mount SRAM', 'Direct mount Cinch']
SQUARE = ['Cuadrado JIS', 'Cuadrado ISO']
GRADES = ['Misma pieza declarada', 'Usable con diferencias declaradas',
          'No intercambiable declarado']
CONSTRUCTIONS = ['Una pieza (americana / Ashtabula)',
                 'Dos piezas (eje solidario al brazo derecho)',
                 'Tres piezas (eje independiente)',
                 'Otra construcción documentada']
MOUNTINGS = ['Platos desmontables por pernos',
             'Platos remachados no desmontables',
             'Plato direct mount al brazo',
             'Otro montaje documentado']


def _source_columns():
    return [column('source_document', 'Documento o envase identificado', required=True),
            column('source_url', 'URL del documento, si existe', 'url')]


def _graded_claim_columns(subject):
    """The shared documented-claim shape plus the grade an OEM may declare."""
    columns = _claim_columns(subject)
    if columns[7]['key'] != 'conditions':
        raise ValueError('Claim column order changed; re-check the insert')
    columns.insert(7, column('declared_grade', 'Grado declarado por la fuente',
                             'token', options=GRADES))
    return columns


def _claims(definitions, template, key, label, subject, helper):
    _add(definitions, template, key, label, 'json', role='declaration',
         semantic='compatibility', helper=helper,
         rules={'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
                                'columns': _graded_claim_columns(subject)}})
    c = template['form_contract']
    c.setdefault('row_conditions', {'version': 1, 'fields': {}})
    c['row_conditions']['fields'][key] = _claim_conditions()
    c['prerequisites'][key] = [EVIDENCE]


CLAIM_HELPER = (
    'Declaraciones documentadas, una por fila, con su alcance y su fuente. El '
    'grado lo pone el documento: un fabricante puede declarar la misma pieza, '
    'una pieza usable con diferencias, o ninguna equivalencia. La ausencia de '
    'una declaración no es una equivalencia, y una marca compartida tampoco.')


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
    shells = list(published['bottom_bracket_family']['allowed_values'])

    _crankset(definitions, templates['crankset'], shells)
    _crank_arm(definitions, templates['crank_arm'])
    _chainring(definitions, templates['chainring'])

    for key in FAMILIES:
        template = templates[key]
        validate_contract(key, template['form_contract'], definitions,
                          {f['key'] for f in template['fields']})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definitions in crank drive packet')
    for key, definition in definitions.items():
        if definition['origin'] != 'existing':
            continue
        if any(definition[g] != published[key][g] for g in (
                'id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
                'validation_rules')):
            raise ValueError('Published definition was rewritten: ' + key)

    catalog = {**base,
               'title': 'Crankset, crank arm and chainring pieces, seats and pairings',
               'templates': [templates[k] for k in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'source_urls': [TAPER, PARK_CRANK, C449, EV8000],
               'stats': {'templates': len(FAMILIES),
                         'definitions': len(definitions),
                         'field_uses': sum(len(t['fields'])
                                           for t in templates.values())}}
    return catalog, {'cases': _cases(), 'pending_cases': _pending()}


def _crankset(definitions, template, shells):
    c = template['form_contract']
    # Park separates one piece of steel that runs through the shell from the
    # three-piece set with its own axle and from the two-piece set whose
    # spindle is part of the right arm. None of that is the number of rings.
    _add(definitions, template, 'crankset_construction',
         'Construcción de este conjunto', 'single_select', role='primary',
         semantic='intrinsic', options=CONSTRUCTIONS, required=ALWAYS,
         helper='Cuántas piezas forman el conjunto. Una pieza es la biela '
         'americana que atraviesa la caja; dos piezas lleva el eje solidario '
         'al brazo derecho; tres piezas usa un eje independiente. No se '
         'confunde con cuántos platos trae.')
    c['helpers']['spindle_interface'] = (
        'Qué recibe el eje en este conjunto, o qué eje trae. En una biela de '
        'una pieza el eje es la propia biela.')
    c['helpers']['spindle_taper_standard'] = (
        'Cuál de los dos cuadrados declara el documento. JIS e ISO comparten '
        'el ángulo de 2°; el ISO es más largo y termina más fino, así que la '
        'misma biela se asienta unos 4,5 mm más afuera sobre un eje JIS. Eso '
        'mueve la línea de cadena, y no es una incompatibilidad física '
        'universal: la fuente habla de elegir el largo de eje que da la línea '
        'buscada. No se deduce de la marca.')
    # A crankset that carries its own spindle publishes its own chain line;
    # when the spindle is a separate bottom bracket, the line belongs to the
    # combination and is declared row by row.
    with_spindle = condition('spindle_included', True, 'boolean')
    c['allowed_when']['chainline_mm'] = deepcopy(with_spindle)
    c['helpers']['chainline_mm'] = (
        'Línea de cadena que publica el fabricante para este conjunto con su '
        'propio eje. Si el eje va aparte, la línea depende del pedalier y del '
        'largo de eje elegidos y se declara en cada combinación.')
    # C-449 lists one crankset line against several bottom bracket models, and
    # the code of the configuration carries the chain line. 122.5 belongs to a
    # code of one line, not to every crankset.
    definitions['bottom_bracket_required']['label'] = (
        'Pedalier requerido, combinación por combinación')
    definitions['bottom_bracket_required']['validation_rules'] = {'rows_schema': {
        'version': 1, 'unique_by': [['requirement_identity']], 'columns': [
            column('requirement_identity', 'Identificación de esta combinación',
                   required=True),
            column('bb_shell_interface', 'Caja del cuadro', 'token',
                   required=True, options=shells),
            column('bb_shell_width_mm', 'Ancho de caja', 'decimal', unit='mm',
                   positive=True),
            column('bb_model_code', 'Pedalier documentado para esta combinación'),
            column('spindle_length_mm', 'Largo de eje', 'decimal', unit='mm',
                   positive=True),
            column('resulting_chainline_mm', 'Línea de cadena de esta combinación',
                   'decimal', unit='mm', positive=True),
            column('configuration_code', 'Código de la configuración'),
            column('conditions', 'Condiciones de la fuente'), *_source_columns()]}}
    c['helpers']['bottom_bracket_required'] = (
        'Una fila por combinación documentada: caja, pedalier, largo de eje, '
        'línea de cadena resultante y su condición. Un mismo conjunto admite '
        'varios pedalieres con líneas distintas; una cifra de una fila no vale '
        'para las demás ni para otros modelos.')
    c['prerequisites']['bottom_bracket_required'] = [EVIDENCE]
    supplied = 'bottom_bracket_included'
    _add(definitions, template, supplied, 'El envase trae el pedalier',
         'boolean', role='primary', semantic='contents', required=ALWAYS,
         helper='Que el conjunto necesite una caja determinada y que el envase '
         'traiga el pedalier son dos respuestas distintas.')
    _add(definitions, template, 'crankset_bottom_bracket_supplied',
         'Pedalier que viene en el envase', 'json', role='primary',
         semantic='contents', allowed=condition(supplied, True, 'boolean'),
         required=condition(supplied, True, 'boolean'),
         helper='Lo que trae la caja, identificado. Sin pedalier incluido no '
         'hay contenido que declarar.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['supplied_identity']], 'columns': [
                 column('supplied_identity', 'Identificación de esta pieza',
                        required=True),
                 column('bb_model_code', 'Pedalier documentado'),
                 column('shell_interface', 'Caja para la que sirve', 'token',
                        options=shells),
                 column('shell_width_mm', 'Ancho de caja', 'decimal', unit='mm',
                        positive=True),
                 column('spindle_length_mm', 'Largo de eje', 'decimal',
                        unit='mm', positive=True), *_source_columns()]}})
    # The exploded view of one crankset states two bolt circles at once, one
    # for the outer and middle rings and another for the inner ring, so the
    # circle belongs to each ring and not to the set.
    _retire(template, ['chainring_bcd_mm', 'chainring_count',
                       'front_chainring_count', 'chainring_teeth',
                       'bottom_bracket_family', 'drivetrain_speeds',
                       'chain_profile_family', 'kit_members'])
    definitions['chainring_teeth_rows']['label'] = 'Platos que trae el envase'
    definitions['chainring_teeth_rows']['validation_rules'] = {'rows_schema': {
        'version': 1, 'unique_by': [['ring_identity'], ['position']],
        'columns': [
            column('ring_identity', 'Identificación de este plato', required=True),
            column('position', 'Posición de este plato', 'token', required=True,
                   options=POSITIONS),
            column('teeth', 'Dientes', 'integer', required=True, unit='T',
                   positive=True),
            column('bcd_mm', 'Círculo de pernos de este plato', 'decimal',
                   unit='mm', positive=True),
            column('bolt_count', 'Pernos de este plato', 'integer', positive=True),
            column('removable', 'Se puede desmontar', 'boolean'),
            column('member_designation', 'Designación del plato en el documento'),
            *_source_columns()]}}
    c['helpers']['chainring_teeth_rows'] = (
        'Un plato por fila, con su posición y su propio círculo de pernos. Un '
        'triple puede llevar dos círculos distintos en el mismo conjunto: el '
        'exterior y el medio en uno, el interior en otro.')
    c['prerequisites']['chainring_teeth_rows'] = [EVIDENCE]
    rings_present = condition('included_chainring_count', '0', 'decimal')
    rings_present['rows'][0][0]['operator'] = 'gt'
    _add(definitions, template, 'chainring_mounting',
         'Cómo van montados los platos', 'single_select', role='primary',
         semantic='intrinsic', options=MOUNTINGS,
         allowed=deepcopy(rings_present), required=deepcopy(rings_present),
         helper='Si los platos se sacan con pernos, si van remachados y no se '
         'desmontan, o si el plato va direct mount al brazo. Un conjunto sin '
         'platos incluidos no responde esto.')
    _add(definitions, template, 'crankset_chain_guard_included',
         'El envase trae cubrecadena', 'boolean', role='measurement',
         semantic='contents',
         helper='Contenido del envase, no una compatibilidad.')
    _add(definitions, template, 'crank_fixing_bolt_included',
         'El envase trae el perno de fijación', 'boolean', role='measurement',
         semantic='contents',
         helper='Contenido del envase. Su presencia no dice qué eje recibe.')
    _claims(definitions, template, 'crankset_compatibility_claims',
            'Pedalieres, transmisiones o piezas declaradas', 'del destino',
            CLAIM_HELPER)
    for key in ('crank_arm_length_mm', 'pedal_thread', 'chainring_mount_type',
                'spindle_interface', 'spindle_taper_standard', 'chainline_mm',
                'compatible_rear_speeds', 'chainring_mounting'):
        c['prerequisites'][key] = [EVIDENCE]


def _crank_arm(definitions, template):
    c = template['form_contract']
    individual = condition('crank_side', [LEFT, RIGHT])
    pair = condition('crank_side', PAIR)
    c['helpers']['crank_side'] = (
        'Qué trae este envase: un brazo de un lado o el par completo. Con el '
        'par, cada brazo declara lo suyo en su fila, porque el izquierdo y el '
        'derecho no comparten rosca de pedal ni llevan lo mismo.')
    for key in ('crank_arm_length_mm', 'pedal_thread', 'crank_bolt_thread'):
        c['allowed_when'][key] = deepcopy(individual)
        c['required_when'][key] = (deepcopy(individual)
                                   if key == 'crank_arm_length_mm' else NEVER)
    _add(definitions, template, 'crank_arm_carries_chainring_mount',
         'Este brazo lleva el asiento de los platos', 'boolean', role='primary',
         semantic='intrinsic', allowed=deepcopy(individual),
         helper='La araña o el asiento direct mount va en un solo brazo. Que '
         'lo lleve no dice qué plato recibe.')
    _add(definitions, template, 'crank_arm_unit_count',
         'Cuántos brazos trae el envase', 'number', role='primary',
         semantic='contents', rules={'integer': True, 'min': 2},
         allowed=deepcopy(pair), required=deepcopy(pair),
         helper='Se cuenta lo que trae el envase.')
    _add(definitions, template, 'crank_arm_units', 'Brazos que trae el envase',
         'json', role='primary', semantic='contents',
         allowed=deepcopy(pair), required=deepcopy(pair),
         helper='Un brazo por fila. La rosca del pedal izquierdo no es la del '
         'derecho y sólo uno de los dos lleva el asiento de los platos, así '
         'que un escalar no puede responder por los dos.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['unit_side']], 'columns': [
                 column('unit_identity', 'Identificación de este brazo', required=True),
                 column('unit_side', 'Lado', 'token', required=True,
                        options=[LEFT, RIGHT]),
                 column('length_mm', 'Largo', 'decimal', unit='mm', positive=True),
                 column('pedal_thread', 'Rosca de pedal de este brazo'),
                 column('carries_chainring_mount', 'Lleva el asiento de los platos',
                        'boolean'),
                 *_source_columns()]}})
    c['row_coherence'] = {'version': 2, 'links': [], 'cardinalities': [
        {'id': 'documented_arms_in_the_package', 'field': 'crank_arm_units',
         'total_field': 'crank_arm_unit_count'}]}
    # The published spindle domain has fourteen real interfaces and no token
    # for an unlisted one, so the manufacturer designation is written down and
    # the missing token is reported, never guessed.
    _add(definitions, template, 'crank_arm_spindle_designation',
         'Designación del eje según el documento', 'text', role='declaration',
         semantic='declaration',
         helper='Cómo nombra el fabricante el eje que recibe este brazo. Se '
         'usa cuando el dominio publicado no tiene un término para esa '
         'interfaz; no reemplaza a la interfaz ni la deduce.')
    _add(definitions, template, 'crank_arm_system_construction',
         'Construcción del sistema al que pertenece', 'single_select',
         role='declaration', semantic='compatibility', options=CONSTRUCTIONS,
         helper='Un brazo izquierdo de un sistema de dos piezas no sirve en '
         'uno de tres piezas aunque comparta largo y rosca de pedal.')
    c['helpers']['spindle_taper_standard'] = (
        'Cuál de los dos cuadrados declara el documento. El ISO es más largo '
        'y más fino en la punta, así que la misma biela se asienta unos '
        '4,5 mm más afuera sobre un eje JIS: cambia la línea de cadena. No se '
        'deduce de la marca ni se declara incompatibilidad física por ello.')
    _claims(definitions, template, 'crank_arm_compatibility_claims',
            'Ejes, sistemas o piezas declaradas', 'del destino', CLAIM_HELPER)
    for key in ('crank_arm_length_mm', 'pedal_thread', 'crank_bolt_thread',
                'spindle_interface', 'spindle_taper_standard', 'crank_arm_units',
                'crank_arm_spindle_designation', 'crank_arm_system_construction',
                'crank_arm_carries_chainring_mount'):
        c['prerequisites'][key] = [EVIDENCE]


def _chainring(definitions, template):
    c = template['form_contract']
    individual = condition('chainring_package_kind', SINGLE_RING)
    ring_set = condition('chainring_package_kind', RING_SET)
    _add(definitions, template, 'chainring_package_kind',
         'Qué trae este envase', 'single_select', role='primary',
         semantic='intrinsic', options=[SINGLE_RING, RING_SET], required=ALWAYS,
         helper='Un plato suelto o un juego de platos en el mismo envase. Un '
         'juego doble o triple no es un plato con varias medidas: cada plato '
         'tiene sus dientes, su posición y su propio círculo de pernos.')
    for key in ('teeth_count', 'chainring_position', 'narrow_wide'):
        c['allowed_when'][key] = deepcopy(individual)
    c['required_when']['teeth_count'] = deepcopy(individual)
    c['allowed_when']['chainring_bcd_mm'] = both(
        deepcopy(individual), condition('chainring_mount_type', BOLT_CIRCLES))
    c['required_when']['chainring_bcd_mm'] = both(
        deepcopy(individual), condition('chainring_mount_type', BOLT_CIRCLES))
    # A shared bolt circle is not a shared pattern: the same 96 mm circle is
    # published both as a symmetric and as an asymmetric drilling.
    c['allowed_when']['chainring_bolt_pattern_symmetric'] = both(
        deepcopy(individual), condition('chainring_mount_type', BOLT_CIRCLES))
    c['helpers']['chainring_bolt_pattern_symmetric'] = (
        'Si los pernos están repartidos en ángulos iguales. Dos platos del '
        'mismo diámetro de círculo pueden tener repartos distintos, así que un '
        'BCD igual no prueba que el plato calce.')
    c['helpers']['chainring_bcd_mm'] = (
        'Diámetro del círculo de pernos de este plato. No dice cuántos pernos '
        'hay ni cómo están repartidos, y un conjunto puede llevar dos círculos.')
    _add(definitions, template, 'chainring_set_member_count',
         'Cuántos platos trae el envase', 'number', role='primary',
         semantic='contents', rules={'integer': True, 'min': 2},
         allowed=deepcopy(ring_set), required=deepcopy(ring_set),
         helper='Se cuenta lo que trae el envase, no los dientes.')
    _add(definitions, template, 'chainring_set_members',
         'Platos que trae el juego', 'json', role='primary', semantic='contents',
         allowed=deepcopy(ring_set), required=deepcopy(ring_set),
         helper='Un plato por fila, con su posición, sus dientes y su propio '
         'círculo de pernos. Un juego triple documentado lleva dos círculos '
         'distintos, así que el juego no responde con una sola medida.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['member_identity'], ['position']],
             'columns': [
                 column('member_identity', 'Identificación de este plato', required=True),
                 column('position', 'Posición', 'token', required=True,
                        options=POSITIONS),
                 column('teeth', 'Dientes', 'integer', required=True, unit='T',
                        positive=True),
                 column('bcd_mm', 'Círculo de pernos', 'decimal', unit='mm',
                        positive=True),
                 column('bolt_count', 'Pernos', 'integer', positive=True),
                 column('pattern_symmetric', 'Reparto simétrico', 'boolean'),
                 column('member_designation', 'Designación en el documento'),
                 *_source_columns()]}})
    c['row_coherence'] = {'version': 2, 'links': [], 'cardinalities': [
        {'id': 'documented_rings_in_the_package', 'field': 'chainring_set_members',
         'total_field': 'chainring_set_member_count'}]}
    _add(definitions, template, 'chainring_direct_mount_generation',
         'Direct mount documentado', 'text', role='primary',
         semantic='compatibility',
         allowed=condition('chainring_mount_type', DIRECT_MOUNTS),
         required=condition('chainring_mount_type', DIRECT_MOUNTS),
         helper='Qué asiento direct mount exacto declara el documento, con su '
         'generación. Decir «direct mount» no basta: el mismo fabricante '
         'publica asientos distintos que no se intercambian.')
    # An offset without its datum is not a measurement, and the chain line of
    # an assembled crankset is a different number with a different owner.
    _retire(template, ['chainring_offset_mm', 'chainring_teeth',
                       'chainring_bolt_count', 'drivetrain_speeds',
                       'chain_profile_family'])
    _add(definitions, template, 'chainring_offset_declarations',
         'Desplazamiento declarado, con su referencia', 'json',
         role='measurement', semantic='measurement',
         helper='Un desplazamiento sin decir desde dónde se mide no es una '
         'cota. Esto no es la línea de cadena del conjunto armado, que '
         'pertenece a la ficha del volante.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['measurement_identity']], 'columns': [
                 column('measurement_identity', 'Identificación de esta cota',
                        required=True),
                 column('offset_mm', 'Desplazamiento', 'decimal', required=True,
                        unit='mm'),
                 column('datum', 'Desde dónde se mide', required=True),
                 column('declared_for', 'Plato al que corresponde'),
                 *_source_columns()]}})
    c['prerequisites']['chainring_offset_declarations'] = [EVIDENCE]
    # The exploded view names each ring for the combination it belongs to, and
    # gives that combination its own fixing bolts.
    _add(definitions, template, 'chainring_oem_pairing_declarations',
         'Emparejado documentado por el fabricante', 'json', role='declaration',
         semantic='compatibility',
         helper='El fabricante publica el plato dentro de una combinación y le '
         'da su propia designación y sus propios pernos. Los mismos dientes en '
         'otra combinación son otra pieza, así que un número de dientes no '
         'identifica el plato.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['pairing_identity']], 'columns': [
                 column('pairing_identity', 'Identificación de este emparejado',
                        required=True),
                 column('declared_combination', 'Combinación documentada',
                        required=True),
                 column('member_designation', 'Designación de este plato'),
                 column('fixing_bolt_designation', 'Pernos documentados'),
                 column('conditions', 'Condiciones de la fuente'),
                 *_source_columns()]}})
    c['prerequisites']['chainring_oem_pairing_declarations'] = [EVIDENCE]
    _claims(definitions, template, 'chainring_compatibility_claims',
            'Pedivelas o transmisiones declaradas', 'del destino', CLAIM_HELPER)
    for key in ('teeth_count', 'chainring_mount_type', 'chainring_bcd_mm',
                'chainring_bolt_pattern_symmetric', 'chainring_position',
                'narrow_wide', 'chain_width_family', 'compatible_rear_speeds',
                'chainring_set_members', 'chainring_direct_mount_generation'):
        c['prerequisites'][key] = [EVIDENCE]


def _cases():
    def build(prefix, family, i, v, forbidden=(), **k):
        result = case(prefix + i, family, v, **k)
        if forbidden:
            result['forbidden_issue_fields'] = list(forbidden)
        return result

    def ck(i, v, **k): return build('ck_', 'crankset', i, v, **k)
    def ca(i, v, **k): return build('ca_', 'crank_arm', i, v, **k)
    def cr(i, v, **k): return build('cr_', 'chainring', i, v, **k)

    def ring(identity, position, teeth, bcd=None, **extra):
        row = {'ring_identity': identity, 'position': position, 'teeth': teeth,
               'source_document': 'Vista despiezada identificada', **extra}
        if bcd:
            row['bcd_mm'] = bcd
        return row

    def member(identity, position, teeth, bcd=None, **extra):
        row = {'member_identity': identity, 'position': position, 'teeth': teeth,
               'source_document': 'Envase identificado', **extra}
        if bcd:
            row['bcd_mm'] = bcd
        return row

    def claim(identity, scope, **extra):
        return {'claim_identity': identity, 'scope_kind': scope,
                'source_document': 'Documento identificado', **extra}

    model_claim = claim('Modelo declarado', DOCUMENTED_MODEL,
                        brand='Marca declarada', model='Modelo declarado',
                        declared_grade='Usable con diferencias declaradas')
    bad_claim = claim('Interfaz con modelo', DOCUMENTED_INTERFACE,
                      declared_interface='Interfaz declarada', model='Modelo')
    triple = [ring('Exterior 42T', 'Exterior', '42', '104'),
              ring('Medio 34T', 'Medio', '34', '104'),
              ring('Interior 24T', 'Interior', '24', '64')]
    crank = {'crankset_construction': 'Tres piezas (eje independiente)',
             'spindle_interface': 'Cuadrado JIS', 'spindle_taper_standard': 'JIS',
             'spindle_included': False, 'bottom_bracket_included': False,
             'included_chainring_count': '3',
             'chainring_mounting': 'Platos desmontables por pernos',
             'chainring_teeth_rows': rows(*triple), EVIDENCE: SYNTHETIC}
    bare = {**crank, 'included_chainring_count': '0'}
    bare.pop('chainring_teeth_rows'); bare.pop('chainring_mounting')
    combination = {'requirement_identity': 'D-NL', 'bb_shell_interface': 'BSA roscado',
                   'bb_shell_width_mm': '68', 'bb_model_code': 'Pedalier documentado',
                   'spindle_length_mm': '122.5', 'resulting_chainline_mm': '47.5',
                   'configuration_code': 'D-NL',
                   'source_document': 'Tabla de compatibilidad identificada',
                   'source_url': C449}
    other_combination = {**combination, 'requirement_identity': 'D-EL',
                         'configuration_code': 'D-EL',
                         'bb_model_code': 'Otro pedalier documentado',
                         'spindle_length_mm': '127.5',
                         'resulting_chainline_mm': '50'}
    supplied = {'supplied_identity': 'Pedalier del envase',
                'bb_model_code': 'Pedalier documentado',
                'shell_interface': 'BSA roscado', 'shell_width_mm': '68',
                'source_document': 'Envase identificado'}
    arm = {'crank_side': LEFT, 'spindle_interface': 'Cuadrado JIS',
           'crank_arm_length_mm': '170', 'pedal_thread': '9/16',
           EVIDENCE: SYNTHETIC}
    def unit(side, **extra):
        return {'unit_identity': 'Brazo ' + side, 'unit_side': side,
                'length_mm': '170', 'source_document': 'Envase identificado',
                **extra}
    pair_arms = {'crank_side': PAIR, 'spindle_interface': 'Cuadrado JIS',
                 EVIDENCE: SYNTHETIC, 'crank_arm_unit_count': '2',
                 'crank_arm_units': rows(
                     unit(LEFT, pedal_thread='9/16 rosca izquierda',
                          carries_chainring_mount=False),
                     unit(RIGHT, pedal_thread='9/16', carries_chainring_mount=True))}
    single = {'chainring_package_kind': SINGLE_RING,
              'chainring_mount_type': 'BCD 4 pernos', 'chainring_bcd_mm': '104',
              'teeth_count': '36', EVIDENCE: SYNTHETIC}
    set_members = [member('Exterior 44T', 'Exterior', '44', '104'),
                   member('Medio 32T', 'Medio', '32', '104'),
                   member('Interior 22T', 'Interior', '22', '64')]
    ring_set = {'chainring_package_kind': RING_SET,
                'chainring_mount_type': 'BCD 4 pernos', EVIDENCE: SYNTHETIC,
                'chainring_set_member_count': '3',
                'chainring_set_members': rows(*set_members)}
    pairing = {'pairing_identity': 'Combinación documentada',
               'declared_combination': '40-30-22T',
               'member_designation': '22T-BA',
               'fixing_bolt_designation': 'Perno documentado de esta combinación',
               'source_document': 'Vista despiezada identificada',
               'source_url': EV8000}
    return [
        # The crankset answers for the assembly, ring by ring and shell by shell.
        ck('a_triple_lists_two_bolt_circles', crank, sources=[EV8000]),
        ck('the_same_ring_position_twice_blocks',
           {**crank, 'chainring_teeth_rows': rows(
               triple[0], {**triple[1], 'position': 'Exterior'}, triple[2])},
           blocking=[('row_shape', 'chainring_teeth_rows')]),
        ck('a_ring_without_its_position_is_incomplete',
           {**crank, 'chainring_teeth_rows': rows(
               {k: v for k, v in triple[0].items() if k != 'position'})},
           pending=[('row_incomplete', 'chainring_teeth_rows')]),
        ck('a_bare_crankset_cannot_list_rings',
           {**bare, 'chainring_teeth_rows': rows(*triple)},
           blocking=[('field_applicability', 'chainring_teeth_rows')]),
        ck('the_ring_count_must_match_the_rows',
           {**crank, 'included_chainring_count': '2'},
           blocking=[('row_cardinality_conflict', 'chainring_teeth_rows')]),
        ck('a_crankset_without_its_own_spindle_has_no_chain_line',
           {**crank, 'chainline_mm': '122.5'},
           blocking=[('field_applicability', 'chainline_mm')], sources=[TAPER]),
        ck('a_crankset_with_its_own_spindle_publishes_its_chain_line',
           {**{k: v for k, v in crank.items() if k != 'spindle_taper_standard'},
            'spindle_included': True, 'spindle_interface': 'Hollowtech / 24mm',
            'chainline_mm': '50'}, sources=[TAPER]),
        ck('each_bottom_bracket_combination_keeps_its_own_line',
           {**crank, 'bottom_bracket_required': rows(combination, other_combination)},
           sources=[C449]),
        ck('the_same_combination_twice_blocks',
           {**crank, 'bottom_bracket_required': rows(combination, dict(combination))},
           blocking=[('row_shape', 'bottom_bracket_required')]),
        ck('a_combination_without_its_shell_is_incomplete',
           {**crank, 'bottom_bracket_required': rows(
               {k: v for k, v in combination.items() if k != 'bb_shell_interface'})},
           pending=[('row_incomplete', 'bottom_bracket_required')]),
        ck('a_supplied_bottom_bracket_needs_its_contents',
           {**crank, 'bottom_bracket_included': True},
           pending=[('required_missing', 'crankset_bottom_bracket_supplied')]),
        ck('without_a_supplied_bottom_bracket_there_is_no_content',
           {**crank, 'crankset_bottom_bracket_supplied': rows(supplied)},
           blocking=[('field_applicability', 'crankset_bottom_bracket_supplied')]),
        ck('the_retired_single_bolt_circle_no_longer_answers',
           {**crank, 'chainring_bcd_mm': '104'},
           forbidden=['chainring_bcd_mm']),
        ck('a_one_piece_crank_is_not_a_ring_count',
           {**{k: v for k, v in crank.items() if k != 'spindle_taper_standard'},
            'crankset_construction': 'Una pieza (americana / Ashtabula)',
            'spindle_interface': 'One-piece / americano', 'spindle_included': True,
            'included_chainring_count': '1',
            'chainring_teeth_rows': rows(ring('Único 44T', 'Único', '44'))},
           forbidden=['crankset_construction'], sources=[PARK_CRANK]),
        ck('a_documented_grade_travels_with_its_claim',
           {**crank, 'crankset_compatibility_claims': rows(model_claim)},
           sources=[EV8000]),
        ck('an_interface_claim_cannot_name_a_model',
           {**crank, 'crankset_compatibility_claims': rows(bad_claim)},
           blocking=[('row_field_applicability', 'crankset_compatibility_claims')]),
        # The arm answers for one side, or the package lists both.
        ca('a_left_arm_names_its_length_and_thread', arm),
        ca('a_pair_cannot_carry_one_scalar_length',
           {**pair_arms, 'crank_arm_length_mm': '170'},
           blocking=[('field_applicability', 'crank_arm_length_mm')]),
        ca('a_pair_lists_its_two_arms', pair_arms, sources=[PARK_CRANK]),
        ca('the_same_arm_side_twice_blocks',
           {**pair_arms, 'crank_arm_units': rows(unit(LEFT), unit(LEFT))},
           blocking=[('row_shape', 'crank_arm_units')]),
        ca('a_pair_without_its_count_is_pending',
           {k: v for k, v in pair_arms.items() if k != 'crank_arm_unit_count'},
           pending=[('row_cardinality_pending', 'crank_arm_units')]),
        ca('an_individual_arm_cannot_list_package_arms',
           {**arm, 'crank_arm_units': rows(unit(LEFT), unit(RIGHT))},
           blocking=[('field_applicability', 'crank_arm_units')]),
        ca('an_individual_arm_without_its_length_is_pending',
           {k: v for k, v in arm.items() if k != 'crank_arm_length_mm'},
           pending=[('required_missing', 'crank_arm_length_mm')]),
        ca('the_documented_designation_does_not_replace_the_interface',
           {**arm, 'crank_arm_spindle_designation': 'Eje documentado del fabricante'},
           forbidden=['spindle_interface']),
        ca('a_square_arm_declares_which_standard',
           {**arm, 'spindle_taper_standard': 'JIS'}, sources=[TAPER]),
        ca('a_non_square_arm_has_no_taper_standard',
           {**arm, 'spindle_interface': 'Hollowtech / 24mm',
            'spindle_taper_standard': 'JIS'},
           blocking=[('field_applicability', 'spindle_taper_standard')],
           sources=[TAPER]),
        # The ring answers for one piece, or the package lists the set.
        cr('a_single_ring_names_its_teeth_and_circle',
           {**single, 'chainring_bolt_pattern_symmetric': True}),
        cr('a_set_cannot_carry_one_scalar_teeth_count',
           {**ring_set, 'teeth_count': '36'},
           blocking=[('field_applicability', 'teeth_count')]),
        cr('a_set_cannot_carry_one_scalar_bolt_circle',
           {**ring_set, 'chainring_bcd_mm': '104'},
           blocking=[('field_applicability', 'chainring_bcd_mm')]),
        cr('a_triple_set_lists_two_bolt_circles', ring_set, sources=[EV8000]),
        cr('the_same_member_position_twice_blocks',
           {**ring_set, 'chainring_set_members': rows(
               set_members[0], {**set_members[1], 'position': 'Exterior'},
               set_members[2])},
           blocking=[('row_shape', 'chainring_set_members')]),
        cr('a_member_without_its_teeth_is_incomplete',
           {**ring_set, 'chainring_set_member_count': '2',
            'chainring_set_members': rows(
                set_members[0],
                {k: v for k, v in set_members[1].items() if k != 'teeth'})},
           pending=[('row_incomplete', 'chainring_set_members')]),
        cr('the_set_count_must_match_its_members',
           {**ring_set, 'chainring_set_member_count': '2'},
           blocking=[('row_cardinality_conflict', 'chainring_set_members')]),
        cr('an_individual_ring_cannot_list_set_members',
           {**single, 'chainring_set_members': rows(*set_members)},
           blocking=[('field_applicability', 'chainring_set_members')]),
        cr('a_direct_mount_ring_names_its_generation',
           {'chainring_package_kind': SINGLE_RING, EVIDENCE: SYNTHETIC,
            'chainring_mount_type': 'Direct mount Shimano', 'teeth_count': '32',
            'chainring_direct_mount_generation': 'Asiento documentado y su generación'},
           sources=[EV8000]),
        cr('a_direct_mount_ring_without_its_generation_is_pending',
           {'chainring_package_kind': SINGLE_RING, EVIDENCE: SYNTHETIC,
            'chainring_mount_type': 'Direct mount Shimano', 'teeth_count': '32'},
           pending=[('required_missing', 'chainring_direct_mount_generation')]),
        cr('a_bolt_circle_ring_has_no_direct_mount_generation',
           {**single, 'chainring_direct_mount_generation': 'Asiento documentado'},
           blocking=[('field_applicability', 'chainring_direct_mount_generation')]),
        cr('the_same_circle_can_be_drilled_two_ways',
           {**single, 'chainring_bcd_mm': '96',
            'chainring_bolt_pattern_symmetric': False},
           forbidden=['chainring_bolt_pattern_symmetric', 'chainring_bcd_mm']),
        cr('an_offset_without_its_datum_is_incomplete',
           {**single, 'chainring_offset_declarations': rows(
               {'measurement_identity': 'Cota declarada', 'offset_mm': '5',
                'source_document': 'Documento identificado'})},
           pending=[('row_incomplete', 'chainring_offset_declarations')]),
        cr('an_offset_with_its_datum_is_a_measurement',
           {**single, 'chainring_offset_declarations': rows(
               {'measurement_identity': 'Cota declarada', 'offset_mm': '5',
                'datum': 'Desde la cara de montaje del plato',
                'source_document': 'Documento identificado'})}),
        cr('the_retired_offset_scalar_no_longer_answers',
           {**single, 'chainring_offset_mm': '5'},
           forbidden=['chainring_offset_mm']),
        cr('a_pairing_keeps_the_combination_it_belongs_to',
           {**single, 'chainring_oem_pairing_declarations': rows(pairing)},
           sources=[EV8000]),
        cr('a_pairing_without_its_combination_is_incomplete',
           {**single, 'chainring_oem_pairing_declarations': rows(
               {k: v for k, v in pairing.items() if k != 'declared_combination'})},
           pending=[('row_incomplete', 'chainring_oem_pairing_declarations')]),
        cr('an_interface_claim_cannot_name_a_model',
           {**single, 'chainring_compatibility_claims': rows(bad_claim)},
           blocking=[('row_field_applicability', 'chainring_compatibility_claims')]),
    ]


def _pending():
    return [
        {'id': 'an_integrated_motor_spindle_has_no_published_token',
         'required_result': 'published_domain_extension_pending',
         'reason': 'One arm in scope is sold for an integrated motor spindle. '
                   'The published spindle domain has fourteen real interfaces '
                   'and neither an «other» nor an «unknown» token, so the '
                   'required field cannot be answered truthfully. The '
                   'designation is written down; extending the domain belongs '
                   'to the publisher, not to this packet.'},
        {'id': 'jis_or_iso_is_not_inferred_from_the_brand',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'The source lists which brands tend to use each standard '
                   'and states the two mix in practice when the spindle length '
                   'gives the wanted chain line. A tendency is not this '
                   'product, and no physical incompatibility is declared.'},
        {'id': 'crank_and_ring_codes_belong_to_the_product',
         'required_result': 'identity_pending',
         'reason': 'Titles carry manufacturer codes while model and '
                   'manufacturer_sku are empty in all 50 records of the scope. '
                   'Identity is resolved in the product, never here.'},
        {'id': 'an_inch_length_in_a_title_is_not_a_measured_arm',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'One-piece cranks are titled in inches. The arm length in '
                   'millimetres is taken from the package or the manual, not '
                   'converted from a trade name.'},
        {'id': 'a_shell_width_in_a_title_is_not_the_supplied_contents',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Several titles name a shell width next to the word for a '
                   'bottom bracket. Whether the bottom bracket ships in the box '
                   'is a fact of the package.'},
        {'id': 'the_interchangeability_columns_were_not_mapped',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'The exploded view marks interchangeability with letters in '
                   'per-model columns. This round read the legend, not the '
                   'column alignment, so no part is declared interchangeable '
                   'with a named crankset.'},
        {'id': 'oem_relation_and_editor_validation_pending',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Directed OEM relations and the real editor round are not '
                   'exercised by this packet.'},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-crank-drive-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-crank-drive-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'production_writes': False, 'fill': False}))
