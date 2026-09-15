#!/usr/bin/env python3
"""Compile an unpublished, source-scoped successor for the 48 bound spokes.

No DB, migration, product filling, assignment or live UI operation. Physical
wire sections belong to this SKU. OEM ranges of offered lengths do not. Gauge
labels, rolled threads, nipple tool drives and wheel assembly are separate axes.
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

FAMILIES = ('spoke',)
PREIMAGE = RESEARCH / 'existing-spoke-preimage-2026-09-08.json'
PREIMAGE_SHA = '629a9a36ad0afc052db5f69c59a9e64bc2f24f0359c8b84d4221d545ba3a8d94'
SHELDON = 'https://www.sheldonbrown.com/wheelbuild.html'
PARK = 'https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection'
CN = 'https://cnspoke.com/wp-content/uploads/cnSPOKE_Catalogue_v24_web.pdf'
SYNTHETIC = 'https://example.invalid/synthetic'
UNKNOWN = 'Desconocido / sin confirmar'
HEAD = 'spoke_head_interface'
THREAD = 'spoke_nipple_thread_present'
SECTIONS = 'spoke_wire_sections'
INCLUDED = 'nipples_included'
NIPPLES = 'spoke_supplied_nipples'
EVIDENCE = 'spec_evidence_source'
GAUGE = 'spoke_gauge_designation'
STANDARD = 'spoke_thread_standard'
MAJOR = 'spoke_thread_major_diameter_mm'
NOMINAL = 'spoke_thread_nominal_mm'
THREAD_LENGTH = 'spoke_thread_length_mm'
ELBOW = 'spoke_head_elbow_angle_deg'
LENGTH = 'spoke_length_mm'


def _add(definitions, template, key, label, kind, *, role='measurement',
         semantic='compatibility', unit=None, options=(), rules=None,
         allowed=ALWAYS, required=NEVER, helper=None):
    if key in definitions:
        raise ValueError('Refuse to overwrite a definition: ' + key)
    definitions[key] = new_definition(key, label, kind, FAMILIES, unit=unit,
                                     options=options, rules=rules)
    add_field(template, key, role, semantic, allowed=allowed, required=required,
              helper=helper)


def _drop_unpublished(definitions, template, key):
    if definitions[key]['origin'] != 'new':
        raise ValueError('Cannot remove a published observation: ' + key)
    template['fields'] = [f for f in template['fields'] if f['key'] != key]
    for section in ('roles', 'semantic_roles', 'labels', 'allowed_when',
                    'required_when', 'allowed_options', 'prerequisites',
                    'helpers', 'evidence_requirements'):
        template['form_contract'].get(section, {}).pop(key, None)
    del definitions[key]


def compile_catalog():
    for path, expected in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                           (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Pinned input changed: ' + path.name)
    base = json.loads(CATALOG.read_text())
    before = json.loads(PREIMAGE.read_text())
    template = deepcopy(next(t for t in base['templates'] if t['key'] == 'spoke'))
    template['name'] = before['templates'][0]['name']
    definitions = {f['key']: deepcopy(base['definitions'][f['key']])
                   for f in template['fields']}
    for actual in before['existing_definitions']:
        key = actual['key']
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
            'validation_rules')}
        definitions[key].update(origin='existing', used_by=list(FAMILIES))

    # The old enumerated gauge merges a label and a sequence of dimensions, and
    # the two-value head vocabulary cannot represent unknown or proprietary
    # anchors. Keep all published readings; neither drives a new dependency.
    retire(template, ['spoke_gauge', 'spoke_bend_type'])
    c = template['form_contract']
    for key in ('spoke_gauge', 'spoke_bend_type'):
        c['semantic_roles'][key] = 'legacy'
    _drop_unpublished(definitions, template, 'spoke_thread_diameter_mm')
    _drop_unpublished(definitions, template, 'spoke_material')

    _add(definitions, template, HEAD, 'Anclaje de este rayo en la maza',
         'single_select', role='primary', required=ALWAYS,
         options=['J-Bend', 'Straight Pull', 'Otro anclaje OEM', UNKNOWN],
         helper='Anclaje físico del rayo. La marca no determina qué maza lo '
                'admite; las dimensiones y la aprobación pertenecen al modelo.')
    _add(definitions, template, 'spoke_head_oem_designation',
         'Referencia OEM del anclaje', 'text',
         required=condition(HEAD, 'Otro anclaje OEM'),
         helper='Designación literal del fabricante, incluida la edición. '
                'No sustituye una relación de compatibilidad con una maza.')
    _add(definitions, template, ELBOW, 'Ángulo de codo publicado por el fabricante',
         'number', unit='°', rules={'positive': True, 'max': '180'},
         allowed=condition(HEAD, ['J-Bend', 'Otro anclaje OEM']),
         helper='Ángulo y convención del dibujo del modelo. No se fuerza a '
                '90° ni se deduce de la palabra J-Bend; no aprueba una maza.')
    _add(definitions, template, 'spoke_hub_hole_class_declared',
         'Clase de anclaje de maza declarada por el fabricante', 'text',
         role='declaration', helper='Transcripción de la clase OEM, por ejemplo '
         'REGULAR en su propio catálogo. No es un estándar universal ni '
         'certifica una maza por compartir ese nombre.')
    _add(definitions, template, GAUGE, 'Calibre escrito por el fabricante',
         'text', role='declaration', semantic='intrinsic',
         helper='Etiqueta documental. No se convierte a milímetros, rosca '
                'ni medida de llave. Las secciones físicas se declaran aparte.')
    _add(definitions, template, 'spoke_material_declared',
         'Material declarado del rayo', 'text', role='primary',
         semantic='intrinsic', helper='Material según fabricante; el acabado '
         'superficial tiene su propio campo.')
    _add(definitions, template, 'spoke_finish_declared', 'Acabado del rayo',
         'text', role='primary', semantic='intrinsic')

    # A single SKU can have several differently sized sections. Every row has
    # its own physical position. The table is not an OEM model variant list.
    schema = {'version': 1, 'unique_by': [['position']], 'columns': [
        column('position', 'Orden desde la maza hacia el niple', 'integer',
               required=True, positive=True),
        column('section_identity', 'Zona identificada por el fabricante',
               required=True),
        column('shape', 'Forma de esta sección', 'token', required=True,
               options=['Redonda', 'Plana / aero', 'Elíptica / ovalada', 'Otra', UNKNOWN]),
        column('diameter_mm', 'Diámetro del alambre', 'decimal', unit='mm', positive=True),
        column('width_mm', 'Ancho declarado', 'decimal', unit='mm', positive=True),
        column('thickness_mm', 'Espesor declarado', 'decimal', unit='mm', positive=True),
        column('other_geometry', 'Geometría OEM de esta sección'),
        column('source_document', 'Documento, dibujo o envase identificado', required=True),
        column('source_url', 'URL del documento, si existe', 'url'),
    ]}
    _add(definitions, template, SECTIONS, 'Secciones de este rayo', 'json',
         rules={'rows_schema': schema}, required=ALWAYS,
         helper='Todas las filas pertenecen a esta variante. No añadas aquí '
         'otros modelos o largos ofertados. Diámetro del alambre y diámetro '
         'mayor de su rosca laminada no son la misma medida.')
    geometry = {'diameter_mm': condition('shape', 'Redonda'),
                'width_mm': condition('shape', ['Plana / aero', 'Elíptica / ovalada']),
                'thickness_mm': condition('shape', ['Plana / aero', 'Elíptica / ovalada']),
                'other_geometry': condition('shape', 'Otra')}
    c['row_conditions'] = {'version': 1, 'fields': {SECTIONS: {
        'allowed_when': deepcopy(geometry), 'required_when': deepcopy(geometry)}}}

    _add(definitions, template, THREAD, 'Este rayo tiene rosca para niple',
         'boolean', role='primary', required=ALWAYS)
    thread_present = condition(THREAD, True, 'boolean')
    c['allowed_when'][STANDARD] = deepcopy(thread_present)
    # Some OEM tables publish nominal diameter and length without naming a
    # thread standard. Preserve the documented data without inventing a name;
    # mating approval still requires a model-scoped source.
    c['required_when'][STANDARD] = deepcopy(NEVER)
    c['helpers'][STANDARD] = ('Designación OEM de esta rosca; no se deduce del '
        'calibre. Igual designación no certifica el montaje completo.')
    _add(definitions, template, MAJOR, 'Diámetro mayor de la rosca', 'number',
         unit='mm', rules={'positive': True}, allowed=thread_present,
         helper='Sólo el diámetro mayor explícitamente identificado. No copies '
         'aquí el diámetro del alambre ni una cota OEM de significado incierto.')
    _add(definitions, template, NOMINAL, 'Nominal OEM del extremo roscado',
         'number', unit='mm', rules={'positive': True}, allowed=thread_present,
         helper='Cota nominal declarada del extremo (ØT en cnSPOKE). Conservar '
         'esa convención: no es el diámetro mayor medido ni determina el paso.')
    _add(definitions, template, THREAD_LENGTH, 'Largo roscado declarado',
         'number', unit='mm', rules={'positive': True}, allowed=thread_present,
         helper='Cota T del modelo y edición. No se supone a partir del niple '
         'ni se asigna 9,5 mm a todos los rayos por un ejemplo del catálogo.')

    # Included nipples are physical contents. Their source/model identifies
    # the component; the nipple family owns its full interface specification.
    c['required_when'][INCLUDED] = deepcopy(ALWAYS)
    c['required_when']['pack_quantity'] = deepcopy(ALWAYS)
    _add(definitions, template, NIPPLES, 'Niples incluidos en este envase',
         'json', role='contents', semantic='contents',
         allowed=condition(INCLUDED, True, 'boolean'),
         required=condition(INCLUDED, True, 'boolean'), rules={'rows_schema': {
             'version': 1, 'unique_by': [['component_identity']], 'columns': [
                 column('component_identity', 'Identidad o referencia del niple', required=True),
                 column('quantity', 'Cantidad de este niple', 'integer', positive=True, required=True),
                 column('source_document', 'Documento o envase identificado', required=True),
                 column('source_url', 'URL del documento, si existe', 'url'),
             ]}}, helper='Componentes realmente incluidos; pueden existir '
         'repuestos adicionales. Su cantidad no se fuerza a igualar los rayos. '
         'La ficha del niple conserva rosca y herramienta; no se deducen aquí.')
    c['labels'][LENGTH] = 'Largo nominal de esta variante de rayo'
    c['helpers'][LENGTH] = ('Largo del producto según su referencia y datum OEM. '
        'El cálculo para una rueda depende de maza, llanta y patrón de radiado; '
        'no es una propiedad universal de un rayo de esta longitud.')
    c['required_when'][EVIDENCE] = deepcopy(ALWAYS)
    for key in (HEAD, GAUGE, STANDARD, MAJOR, LENGTH, NOMINAL, THREAD_LENGTH,
                ELBOW, 'spoke_head_oem_designation', 'spoke_hub_hole_class_declared'):
        c['prerequisites'][key] = [EVIDENCE]

    keys = {f['key'] for f in template['fields']}
    if set(definitions) != keys:
        raise ValueError('Unowned definitions in spoke packet')
    validate_contract('spoke', c, definitions, keys)
    catalog = {**base, 'title': 'Spoke physical interfaces and included contents',
               'templates': [template], 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'source_urls': [SHELDON, PARK, CN],
               'stats': {'templates': 1, 'definitions': len(definitions),
                         'field_uses': len(template['fields'])}}
    fixtures = {'cases': _cases(), 'pending_cases': [
        {'id': 'spoke_hub_nipple_assembly_requires_exact_relation',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'No wheel compatibility inference from gauge, length or brand.'},
        {'id': 'cn_STD14_product_name_is_not_verified_STD14C_model',
         'required_result': 'identity_pending',
         'reason': 'The read OEM v24 page names STD14C and J-Bend. Product model and anchor both require identity research; MPN/model remain owned by the product.'}
    ]}
    return catalog, fixtures


def _cases():
    def sample(id_, values, **kwargs):
        # Fixtures identify their documents explicitly. This is not a default
        # inserted into the product editor or a product-source conversion.
        for key in (SECTIONS, NIPPLES):
            for row in values.get(key, {}).get('rows', []):
                row['values'].setdefault('source_document', 'Synthetic source document')
        result = case('sp_' + id_, 'spoke', values, **kwargs)
        # These are the published SQL validator's error names, not different
        # mechanical outcomes. Both cases block on the same field in Dart/SQL.
        if id_ in ('same_included_component_twice_blocks', 'fractional_pack_count_blocks'):
            result['expected_sql_blocking'] = [
                {**issue, 'code': 'field_constraint'}
                for issue in result['expected_blocking']]
        result['expected_sql_blocking'] = sorted(
            result.get('expected_sql_blocking', result['expected_blocking']),
            key=lambda item: (item['code'], item['field']))
        if id_ == 'oem_nominal_does_not_require_an_unpublished_thread_name':
            result['forbidden_issue_fields'] = [STANDARD]
        return result
    def section(position=1, shape='Redonda', **extra):
        return {'position': str(position), 'section_identity': 'Sección ' + str(position),
                'shape': shape, 'source_url': SYNTHETIC, **extra}
    plain = section(diameter_mm='2.0')
    aero = section(shape='Plana / aero', width_mm='2.3', thickness_mm='0.9')
    return [
        sample('missing_evidence_is_pending', {HEAD: 'J-Bend'},
               pending=[('prerequisite_missing', HEAD)]),
        sample('round_wire', {SECTIONS: rows(plain)}),
        sample('aero_wire', {SECTIONS: rows(aero)}),
        sample('elliptical_wire_is_not_forced_to_be_flat', {SECTIONS: rows(
            section(shape='Elíptica / ovalada', width_mm='1.8', thickness_mm='1.2'))},
               sources=[SHELDON]),
        sample('identified_package_without_public_url', {SECTIONS: rows({
            **{k: v for k, v in plain.items() if k != 'source_url'},
            'source_document': 'Envase identificado: evidencia adjunta'})}),
        sample('package_content_without_public_url', {INCLUDED: True, NIPPLES: rows({
            'component_identity': 'Synthetic nipple A', 'quantity': '32',
            'source_document': 'Foto del envase, evidencia adjunta'})}),
        sample('a_url_is_still_a_url', {SECTIONS: rows({**plain, 'source_url': 'Envase sin URL'})},
               blocking=[('row_shape', SECTIONS)]),
        sample('oem_elbow_is_not_forced_to_ninety', {
            HEAD: 'J-Bend', ELBOW: '95', EVIDENCE: CN}, sources=[CN]),
        sample('another_oem_elbow_angle', {
            HEAD: 'J-Bend', ELBOW: '100', EVIDENCE: CN}, sources=[CN]),
        sample('straight_pull_cannot_claim_an_elbow', {
            HEAD: 'Straight Pull', ELBOW: '95', EVIDENCE: SYNTHETIC},
               blocking=[('field_applicability', ELBOW)]),
        sample('thread_nominal_and_length_have_their_own_meaning', {
            THREAD: True, NOMINAL: '2.0', THREAD_LENGTH: '9.5',
            MAJOR: '2.3', EVIDENCE: SYNTHETIC}),
        sample('oem_nominal_does_not_require_an_unpublished_thread_name', {
            THREAD: True, NOMINAL: '2.0', THREAD_LENGTH: '9.5', EVIDENCE: CN},
               sources=[CN]),
        sample('no_thread_disallows_nominal_and_length', {
            THREAD: False, NOMINAL: '2.0', THREAD_LENGTH: '9.5', EVIDENCE: SYNTHETIC},
               blocking=[('field_applicability', NOMINAL), ('field_applicability', THREAD_LENGTH)]),
        sample('length_keeps_its_provenance_pending', {LENGTH: '295'},
               pending=[('prerequisite_missing', LENGTH)]),
        sample('internal_label_can_cite_internal_evidence', {
            GAUGE: '14G', EVIDENCE: 'Lectura histórica conservada; origen interno, sin validación OEM'}),
        sample('butted_sections_keep_their_positions', {SECTIONS: rows(
            plain, section(2, diameter_mm='1.8'), section(3, diameter_mm='2.0'))}),
        sample('same_position_twice_blocks', {SECTIONS: rows(plain, plain)},
               blocking=[('row_shape', SECTIONS)]),
        sample('aero_cannot_claim_round_diameter', {SECTIONS: rows({**aero, 'diameter_mm': '2'})},
               blocking=[('row_field_applicability', SECTIONS)]),
        sample('round_cannot_claim_blade_width', {SECTIONS: rows({**plain, 'width_mm': '2.3'})},
               blocking=[('row_field_applicability', SECTIONS)]),
        sample('unknown_section_is_pending', {SECTIONS: rows(section(shape=UNKNOWN, diameter_mm='2'))},
               pending=[('row_prerequisite', SECTIONS)]),
        sample('negative_section_dimension_blocks', {SECTIONS: rows(section(diameter_mm='-2'))},
               blocking=[('row_shape', SECTIONS)]),
        sample('gauge_and_major_thread_are_not_equalities', {
            EVIDENCE: SYNTHETIC, GAUGE: '14G', THREAD: True, STANDARD: 'OEM synthetic',
            SECTIONS: rows(plain), MAJOR: '2.3'}),
        sample('no_thread_cannot_have_thread_major_diameter', {
            EVIDENCE: SYNTHETIC, THREAD: False, MAJOR: '2.3'},
               blocking=[('field_applicability', MAJOR)]),
        sample('no_thread_cannot_have_thread_standard', {
            EVIDENCE: SYNTHETIC, THREAD: False, STANDARD: 'OEM synthetic'},
               blocking=[('field_applicability', STANDARD)]),
        sample('unknown_thread_is_pending', {EVIDENCE: SYNTHETIC, MAJOR: '2.3'},
               pending=[('field_applicability_pending', MAJOR)]),
        sample('nipples_absent_disallow_their_rows', {INCLUDED: False, NIPPLES: rows({
            'component_identity': 'Synthetic nipple A', 'quantity': '32', 'source_url': SYNTHETIC})},
               blocking=[('field_applicability', NIPPLES)]),
        sample('spare_nipples_are_possible', {INCLUDED: True, 'pack_quantity': '32', NIPPLES: rows({
            'component_identity': 'Synthetic nipple A', 'quantity': '34', 'source_url': SYNTHETIC})}),
        sample('same_included_component_twice_blocks', {INCLUDED: True, NIPPLES: rows(
            {'component_identity': 'Synthetic nipple A', 'quantity': '32', 'source_url': SYNTHETIC},
            {'component_identity': 'Synthetic nipple A', 'quantity': '2', 'source_url': SYNTHETIC})},
               blocking=[('row_shape', NIPPLES)]),
        sample('pack_count_is_not_length', {'pack_quantity': '144', LENGTH: '295'}),
        sample('fractional_pack_count_blocks', {'pack_quantity': '1.5'},
               blocking=[('integer', 'pack_quantity')]),
        sample('old_gauge_and_anchor_preserved', {'spoke_gauge': '14/15G',
            'spoke_bend_type': 'J-Bend'}, sources=[SHELDON]),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-spoke-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-spoke-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'production_writes': False, 'fill': False}))
