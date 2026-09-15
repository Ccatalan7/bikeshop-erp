#!/usr/bin/env python3
"""Compile three hydraulic templates. No product or database writes.

A hose is its members; an end belongs to one member; a fluid is what its
maker publishes, never what its brand suggests.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table
from compile_product_spec_catalog import validate_contract
from compile_hydraulic_parts_root import review_hydraulics

FAMILIES = ('hydraulic_hose', 'hydraulic_fitting', 'brake_fluid')

# Park sells two bleed kits that never meet. The mineral list names SRAM DB8
# and the DOT list names SRAM: the same brand sits in both classes, so a brand
# never settles which fluid a brake takes.
PARK_MINERAL = 'https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-mineral-bkm-1-2'
PARK_DOT = 'https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-dot-bkd-1-2'
# Jagwire pre-installs the caliper coupler and sells the lever adapter apart,
# and its kits ship either cut to length or as uncut bulk.
JAGWIRE_PRO = 'https://www.jagwire.com/en/article/19/pro-hydraulic-hose-kit'
JAGWIRE_SPORT = 'https://www.jagwire.com/en/article/21-174/sport-mineral-hydraulic-hose-kit'

STRUCTURED, LITERAL, NO_THREAD = 'Estructurado', 'Designación literal', 'No declarada'
MM, IN, TPI = 'mm', 'in', 'tpi'
DECLARED, TO_CUT, UNDECLARED = ('Declarado', 'A cortar por el instalador',
                                'No declarado')
LEVER, CALIPER = 'Maneta', 'Cáliper'
DOT_FLUID, MINERAL = 'Fluido DOT', 'Aceite mineral'
STANDARD, NO_STANDARD = 'Norma publicada', 'Sin norma publicada'


def both(first, second):
    """AND two single-row conditions; the six operators have no negation."""
    merged = deepcopy(first)
    merged['rows'][0].extend(deepcopy(second)['rows'][0])
    return merged


def thread_columns(prefix=''):
    """Structured figures and a literal designation never share a row cell.

    No free-text nominal sits beside the structured numbers, so a pitch cannot
    be smuggled into a name that no gate reads.
    """
    p = prefix
    return [
        column(p + 'thread_form', 'Forma de la rosca publicada', 'token',
               required=True, options=[STRUCTURED, LITERAL, NO_THREAD]),
        column(p + 'thread_diameter_unit', 'Unidad del diámetro', 'token',
               options=[MM, IN]),
        column(p + 'thread_diameter_mm', 'Diámetro', 'decimal', unit='mm',
               positive=True),
        column(p + 'thread_diameter_in', 'Diámetro en pulgadas, literal'),
        column(p + 'thread_pitch_unit', 'Forma del paso', 'token',
               options=[MM, TPI]),
        column(p + 'thread_pitch_mm', 'Paso', 'decimal', unit='mm', positive=True),
        column(p + 'thread_pitch_tpi', 'Hilos por pulgada', 'decimal', unit='tpi',
               positive=True),
        column(p + 'thread_designation', 'Designación publicada sin descomponer'),
    ]


def thread_conditions(prefix=''):
    p = prefix
    structured = condition(p + 'thread_form', STRUCTURED)
    result = {
        p + 'thread_diameter_unit': deepcopy(structured),
        p + 'thread_pitch_unit': deepcopy(structured),
        p + 'thread_diameter_mm': both(condition(p + 'thread_diameter_unit', MM), structured),
        p + 'thread_diameter_in': both(condition(p + 'thread_diameter_unit', IN), structured),
        p + 'thread_pitch_mm': both(condition(p + 'thread_pitch_unit', MM), structured),
        p + 'thread_pitch_tpi': both(condition(p + 'thread_pitch_unit', TPI), structured),
        p + 'thread_designation': condition(p + 'thread_form', LITERAL),
    }
    return result


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

    # HY-1. A hose product is not one length. Jagwire sells a kit "for a single
    # brake" and a bulk box of ten 2000 mm hoses or thirty uncut metres, so the
    # length may be declared, left for the installer to cut, or not published.
    # The three scalars move per member; their definitions and the published
    # hydraulic_disc_brake use of hose_length_mm are untouched.
    hose = templates['hydraulic_hose']
    members = 'hydraulic_hose_members'
    table(definitions, templates, members, 'Tramos declarados de la manguera',
          ('hydraulic_hose',), [
              column('member', 'Tramo o miembro declarado', required=True),
              column('quantity', 'Cantidad de este tramo', 'integer'),
              column('length_form', 'Forma del largo publicado', 'token',
                     required=True, options=[DECLARED, TO_CUT, UNDECLARED]),
              column('length_mm', 'Largo publicado', 'decimal', unit='mm',
                     positive=True),
              column('outer_diameter_mm', 'Diámetro exterior', 'decimal',
                     unit='mm', positive=True),
              column('inner_diameter_mm', 'Diámetro interior', 'decimal',
                     unit='mm', positive=True),
              column('construction', 'Construcción declarada'),
              column('conditions', 'Modelo, generación y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          conditions={'length_mm': condition('length_form', DECLARED)},
          helper=('Un tramo por fila, con el largo que el fabricante publica '
                  'para ESE tramo. Una manguera que se corta al instalar no es '
                  'una manguera sin largo conocido, y ninguno de los dos es un '
                  'largo todavía sin buscar. El exterior no determina el '
                  'interior.'))
    retire(hose, ['hose_length_mm', 'hose_outer_diameter_mm',
                  'hose_inner_diameter_mm'])

    # HY-2. The two ends of one hose are not the same kind of thing. Jagwire
    # pre-installs the caliper coupler and sells the lever adapter separately,
    # so a hose can have one end resolved and the other still open. Each end
    # belongs to one member: the link is by row id, and one member has at most
    # one lever end and one caliper end.
    ends = 'hydraulic_hose_end_configurations'
    end_conditions = thread_conditions()
    end_conditions.update({
        'olive_model': condition('termination_kind', 'Oliva + inserto'),
        'insert_model': condition('termination_kind', 'Oliva + inserto'),
    })
    table(definitions, templates, ends, 'Extremos declarados de la manguera',
          ('hydraulic_hose',), [
              column('member_row_id', 'Tramo al que pertenece este extremo'),
              column('end_role', 'Extremo', 'token', required=True,
                     options=[LEVER, CALIPER]),
              column('supply', 'Cómo se entrega este extremo', 'token',
                     required=True,
                     options=['Preinstalado en el producto', 'Incluido sin instalar',
                              'Se vende por separado', 'No declarado']),
              column('termination_kind', 'Terminación', 'token', required=True,
                     options=['Oliva + inserto', 'Banjo', 'Conector rápido',
                              'Roscado directo', 'Otra']),
              column('olive_model', 'Oliva declarada'),
              column('insert_model', 'Inserto o espiga declarada'),
              *thread_columns(),
              column('target_brand', 'Marca del freno objetivo'),
              column('target_model', 'Modelo del freno objetivo'),
              column('conditions', 'Modelo, generación y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], conditions=end_conditions,
          helper=('Un extremo por fila, atado al tramo al que pertenece. El '
                  'extremo de cáliper y el de maneta pueden entregarse de forma '
                  'distinta y proceder de piezas distintas: que uno esté '
                  'resuelto no resuelve el otro.'))
    definitions[ends]['validation_rules']['rows_schema']['unique_by'] = [
        ['member_row_id', 'end_role']]
    hose['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'hose_end_member', 'field': ends, 'column': 'member_row_id',
        'target_field': members, 'label_columns': ['member']}]}

    # HY-3. A fitting kit is several pieces, each with its own interface. The
    # insert length was a single scalar for a product that is a set.
    fitting = templates['hydraulic_fitting']
    pieces = 'hydraulic_fitting_components'
    piece_conditions = thread_conditions()
    piece_conditions['insert_length_mm'] = condition(
        'piece_kind', ['Inserto / espiga', 'Oliva + inserto'])
    table(definitions, templates, pieces, 'Piezas declaradas del conector',
          ('hydraulic_fitting',), [
              column('component', 'Pieza declarada', required=True),
              column('quantity', 'Cantidad', 'integer'),
              column('piece_kind', 'Tipo de pieza', 'token', required=True,
                     options=['Oliva', 'Inserto / espiga', 'Oliva + inserto',
                              'Perno banjo', 'Arandela', 'Conector rápido', 'Otra']),
              *thread_columns(),
              column('insert_length_mm', 'Largo del inserto', 'decimal',
                     unit='mm', positive=True),
              column('fits_hose_outer_diameter_mm', 'Diámetro exterior de manguera',
                     'decimal', unit='mm', positive=True),
              column('target_brand', 'Marca del freno objetivo'),
              column('target_model', 'Modelo del freno objetivo'),
              column('conditions', 'Modelo, generación y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, conditions=piece_conditions,
          helper=('Una fila por pieza. La rosca viaja descompuesta o como '
                  'designación publicada, nunca ambas. Un largo de inserto '
                  'describe la pieza; no acredita por sí solo un sistema.'))
    retire(fitting, ['brake_fitting_insert_length_mm'])

    # HY-4. fluid_type mixed the class with the published standard in one
    # token. They are different declarations: mineral oil has no published
    # standard, so its identity is the maker's own designation — which is why
    # "it is mineral oil" never means "it is the right mineral oil".
    fluid = templates['brake_fluid']
    declarations = 'brake_fluid_declarations'
    table(definitions, templates, declarations,
          'Declaraciones publicadas del líquido', ('brake_fluid',), [
              column('fluid_class', 'Clase de líquido', 'token', required=True,
                     options=[DOT_FLUID, MINERAL, 'Otra / no declarada']),
              column('specification_form', 'Forma de la especificación', 'token',
                     required=True, options=[STANDARD, NO_STANDARD]),
              column('specification', 'Norma publicada', 'token',
                     options=['DOT 3', 'DOT 4', 'DOT 5', 'DOT 5.1',
                              'ISO 4925 Clase 4', 'ISO 4925 Clase 6',
                              'Otra norma declarada']),
              column('oem_designation', 'Designación del fabricante'),
              # A maker who claims a whole brand must be recordable saying
              # so; Park's "most models" is why that claim is not read as
              # covering every model. Recording is not endorsing.
              column('approval_scope', 'Alcance de la aprobación declarada',
                     'token', required=True,
                     options=['Marca completa declarada', 'Modelos declarados',
                              'Sin aprobación declarada']),
              column('conditions', 'Condiciones publicadas'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          conditions={
              # A published standard belongs to the DOT class; mineral oil has
              # none, so it is identified by the maker's own designation.
              'specification': both(condition('specification_form', STANDARD),
                                    condition('fluid_class', DOT_FLUID)),
              'oem_designation': condition('fluid_class', MINERAL),
          },
          helper=('Clase, norma publicada y designación del fabricante son tres '
                  'declaraciones distintas. La marca no determina la clase: '
                  'Park separa dos kits que nunca se mezclan y nombra SRAM en '
                  'el de DOT y SRAM DB8 en el mineral. Un aceite mineral no '
                  'tiene norma publicada, así que sólo su designación lo '
                  'identifica: «es mineral» no es «es el correcto». Una '
                  'aprobación declarada para una marca completa se registra tal '
                  'cual, y no se lee como cobertura de todos sus modelos: Park '
                  'dice «most models», no todos.'))
    retire(fluid, ['fluid_type'])

    fixtures['cases'].extend(_cases(members, ends, pieces, declarations))

    review_hydraulics(definitions, templates, fixtures)

    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Hydraulic parts reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


def _cases(members, ends, pieces, declarations):
    conn = {'brake_hydraulic_connections': rows(
        {'component_role': 'Manguera', 'end_role': 'Extremo A',
         'component_brand': 'Jagwire', 'component_model': 'Pro Hydraulic Hose',
         'hose_brand': 'Jagwire', 'hose_model': 'Pro Hydraulic Hose',
         'source_url': JAGWIRE_PRO})}
    hose_code = {'hose_system_code': 'Sintético'}
    fit = {'fitting_kind': 'Oliva + inserto', 'hose_system_code': 'Sintético',
           'brake_fitting_oem_code': 'Sintético'}
    return [
        # --- HY-1: members -------------------------------------------------
        # Jagwire's bulk box: ten hoses of one published length.
        case('hy_bulk_box_ten_declared_lengths', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera suelta', 'quantity': '10',
                  'length_form': DECLARED, 'length_mm': '2000',
                  'source_url': JAGWIRE_SPORT})},
             sources=[JAGWIRE_SPORT]),
        # A hose the installer cuts is not a hose of unknown length.
        case('hy_uncut_hose_is_not_unknown_length', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera a granel', 'length_form': TO_CUT,
                  'construction': 'Trenza de Kevlar sobre forro de Tefzel',
                  'source_url': JAGWIRE_PRO})},
             sources=[JAGWIRE_PRO]),
        case('hy_uncut_hose_cannot_carry_a_length', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera a granel', 'length_form': TO_CUT,
                  'length_mm': '2000'})},
             blocking=[('row_field_applicability', members)]),
        # A kit for one brake and a kit for two are different products.
        case('hy_two_members_keep_their_own_lengths', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Delantera', 'length_form': DECLARED,
                  'length_mm': '900', 'outer_diameter_mm': '5'},
                 {'member': 'Trasera', 'length_form': DECLARED,
                  'length_mm': '1600', 'outer_diameter_mm': '5'})}),
        # --- HY-2: ends ----------------------------------------------------
        # The caliper end arrives fitted; the lever end is bought apart.
        case('hy_caliper_preinstalled_lever_sold_apart', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera', 'length_form': TO_CUT,
                  'source_url': JAGWIRE_PRO}),
              ends: rows(
                  {'member_row_id': 'r1', 'end_role': CALIPER,
                   'supply': 'Preinstalado en el producto',
                   'termination_kind': 'Conector rápido',
                   'thread_form': NO_THREAD, 'source_url': JAGWIRE_PRO},
                  {'member_row_id': 'r1', 'end_role': LEVER,
                   'supply': 'Se vende por separado',
                   'termination_kind': 'Conector rápido',
                   'thread_form': NO_THREAD, 'source_url': JAGWIRE_PRO})},
             sources=[JAGWIRE_PRO]),
        # One member has one lever end, not two.
        case('hy_one_member_has_one_lever_end', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera', 'length_form': TO_CUT}),
              ends: rows(
                  {'member_row_id': 'r1', 'end_role': LEVER,
                   'supply': 'Incluido sin instalar',
                   'termination_kind': 'Oliva + inserto', 'thread_form': NO_THREAD},
                  {'member_row_id': 'r1', 'end_role': LEVER,
                   'supply': 'Se vende por separado',
                   'termination_kind': 'Banjo', 'thread_form': NO_THREAD})},
             blocking=[('row_shape', ends)]),
        case('hy_end_cannot_point_at_an_absent_member', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera', 'length_form': TO_CUT}),
              ends: rows(
                  {'member_row_id': 'r9', 'end_role': LEVER,
                   'supply': 'Incluido sin instalar',
                   'termination_kind': 'Banjo', 'thread_form': NO_THREAD})},
             blocking=[('row_reference_unresolved', ends)]),
        # A structured thread and a literal designation never share a row.
        case('hy_end_thread_structured', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera', 'length_form': TO_CUT}),
              ends: rows(
                  {'member_row_id': 'r1', 'end_role': LEVER,
                   'supply': 'Incluido sin instalar',
                   'termination_kind': 'Roscado directo',
                   'thread_form': STRUCTURED, 'thread_diameter_unit': MM,
                   'thread_diameter_mm': '8', 'thread_pitch_unit': MM,
                   'thread_pitch_mm': '0.75'})}),
        case('hy_literal_thread_cannot_carry_a_pitch', 'hydraulic_hose',
             {**hose_code, **conn, members: rows(
                 {'member': 'Manguera', 'length_form': TO_CUT}),
              ends: rows(
                  {'member_row_id': 'r1', 'end_role': LEVER,
                   'supply': 'Incluido sin instalar',
                   'termination_kind': 'Roscado directo',
                   'thread_form': LITERAL, 'thread_designation': 'Sintética',
                   'thread_pitch_mm': '0.75'})},
             blocking=[('row_field_applicability', ends)]),
        # --- HY-3: fitting pieces ------------------------------------------
        case('hy_fitting_kit_two_pieces', 'hydraulic_fitting',
             {**fit, pieces: rows(
                 {'component': 'Oliva', 'quantity': '1', 'piece_kind': 'Oliva',
                  'thread_form': NO_THREAD, 'fits_hose_outer_diameter_mm': '5'},
                 {'component': 'Inserto', 'quantity': '1',
                  'piece_kind': 'Inserto / espiga', 'thread_form': NO_THREAD,
                  'insert_length_mm': '11.2'})}),
        # An olive is not an insert: it has no insert length.
        case('hy_olive_has_no_insert_length', 'hydraulic_fitting',
             {**fit, pieces: rows(
                 {'component': 'Oliva', 'quantity': '1', 'piece_kind': 'Oliva',
                  'thread_form': NO_THREAD, 'insert_length_mm': '11.2'})},
             blocking=[('row_field_applicability', pieces)]),
        # --- HY-4: fluid ----------------------------------------------------
        # A DOT fluid states a published standard.
        case('hy_dot_fluid_declares_its_standard', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': DOT_FLUID, 'specification_form': STANDARD,
                  'specification': 'DOT 5.1',
                  'approval_scope': 'Sin aprobación declarada'})}),
        # Mineral oil has no standard, so its maker's name is its identity.
        case('hy_mineral_oil_is_identified_by_its_designation', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': MINERAL, 'specification_form': NO_STANDARD,
                  'oem_designation': 'Designación sintética del fabricante',
                  'approval_scope': 'Modelos declarados',
                  'source_url': PARK_MINERAL})},
             sources=[PARK_MINERAL]),
        case('hy_mineral_oil_cannot_claim_a_dot_standard', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': MINERAL, 'specification_form': STANDARD,
                  'specification': 'DOT 4',
                  'approval_scope': 'Sin aprobación declarada'})},
             blocking=[('row_field_applicability', declarations)]),
        case('hy_mineral_oil_without_designation_is_pending', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': MINERAL, 'specification_form': NO_STANDARD,
                  'approval_scope': 'Sin aprobación declarada'})},
             pending=[('row_required_missing', declarations)]),
        # Park's two kits put the same brand in both classes, so the brand
        # decides nothing. Both rows are recordable and neither implies the
        # other; the ficha never derives one from the maker's name.
        case('hy_same_brand_appears_in_both_classes', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': DOT_FLUID, 'specification_form': STANDARD,
                  'specification': 'DOT 5.1', 'approval_scope': 'Modelos declarados',
                  'conditions': 'Park nombra SRAM en el kit de DOT',
                  'source_url': PARK_DOT},
                 {'fluid_class': MINERAL, 'specification_form': NO_STANDARD,
                  'oem_designation': 'Designación sintética del fabricante',
                  'approval_scope': 'Modelos declarados',
                  'conditions': 'Park nombra SRAM DB8 en el kit mineral',
                  'source_url': PARK_MINERAL})},
             sources=[PARK_DOT, PARK_MINERAL]),
        # A whole-brand claim is recordable as what it is: a claim.
        case('hy_whole_brand_claim_is_recordable', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': MINERAL, 'specification_form': NO_STANDARD,
                  'oem_designation': 'Designación sintética del fabricante',
                  'approval_scope': 'Marca completa declarada',
                  'conditions': 'Declaración comercial del fabricante; Park '
                                'documenta cobertura de la mayoría, no de todos',
                  'source_url': PARK_MINERAL})},
             sources=[PARK_MINERAL]),
        # DOT 5 keeps its own option; the ficha never treats it as DOT 5.1.
        case('hy_dot5_is_not_dot51', 'brake_fluid',
             {'volume_ml': '100', declarations: rows(
                 {'fluid_class': DOT_FLUID, 'specification_form': STANDARD,
                  'specification': 'DOT 5',
                  'approval_scope': 'Sin aprobación declarada'})}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'hydraulic-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'hydraulic-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
