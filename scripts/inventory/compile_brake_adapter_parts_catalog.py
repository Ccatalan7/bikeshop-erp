#!/usr/bin/env python3
"""Compile four brake adapter/hub-brake templates. No product or database writes.

An adapter is a direction, not a dimension. A spare part is not a screw because
its neighbours are. A coaster brake is a rear hub, and it says nothing about
what the front wheel carries.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table
from compile_product_spec_catalog import validate_contract
from compile_brake_adapter_parts_root import review_brake_parts

FAMILIES = ('brake_mount_adapter', 'rotor_mount_adapter', 'brake_small_part',
            'hub_brake')

# Park names the three frame standards and says the bolt location varies with
# them. It does not state rotor-size or front/rear specificity, so nothing here
# claims that from Park.
PARK_ALIGN = 'https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment'
# Sheldon: the coaster brake is a rear hub, it is worked by back-pedalling, and
# its reaction arm is clamped to the chainstay. Read this round.
SHELDON_COASTER = 'https://www.sheldonbrown.com/coaster-brakes.html'

DECLARED, UNPUBLISHED, OEM_LITERAL = 'Declarado', 'No publicado', 'Designación OEM'
THREADED, UNTHREADED = 'Roscada', 'Sin rosca'
MM, IN, TPI = 'mm', 'in', 'tpi'
COMPATIBLE, EXCLUDED, CONDITIONAL = ('Compatible declarado', 'Excluido declarado',
                                     'Condicional')
COASTER = 'Contrapedal'
BACKPEDAL = 'Contrapedal (retropedaleo)'
REAR = 'Trasera'


def both(first, second):
    merged = deepcopy(first)
    merged['rows'][0].extend(deepcopy(second)['rows'][0])
    return merged


def thread_columns():
    """Decomposed figures or a published designation, never both."""
    return [
        column('thread_form', 'Forma de la rosca publicada', 'token',
               options=[THREADED, UNTHREADED, OEM_LITERAL]),
        column('thread_diameter_unit', 'Unidad del diámetro', 'token',
               options=[MM, IN]),
        column('thread_diameter_mm', 'Diámetro', 'decimal', unit='mm', positive=True),
        column('thread_diameter_in', 'Diámetro en pulgadas, literal'),
        column('thread_pitch_unit', 'Forma del paso', 'token', options=[MM, TPI]),
        column('thread_pitch_mm', 'Paso', 'decimal', unit='mm', positive=True),
        column('thread_pitch_tpi', 'Hilos por pulgada', 'decimal', unit='tpi',
               positive=True),
        column('thread_designation', 'Designación publicada sin descomponer'),
    ]


def thread_conditions():
    threaded = condition('thread_form', THREADED)
    return {
        'thread_diameter_unit': deepcopy(threaded),
        'thread_pitch_unit': deepcopy(threaded),
        'thread_diameter_mm': both(condition('thread_diameter_unit', MM), threaded),
        'thread_diameter_in': both(condition('thread_diameter_unit', IN), threaded),
        'thread_pitch_mm': both(condition('thread_pitch_unit', MM), threaded),
        'thread_pitch_tpi': both(condition('thread_pitch_unit', TPI), threaded),
        'thread_designation': condition('thread_form', OEM_LITERAL),
    }


def extend(definitions, key, columns, conditions=None, value_when=None,
           templates=None, family=None):
    """Add columns to a single-family table without touching shared ones."""
    definition = definitions[key]
    if definition['used_by'] != [family]:
        raise ValueError('Refusing to extend a shared definition: ' + key)
    definition['validation_rules']['rows_schema']['columns'].extend(columns)
    if conditions or value_when:
        spec = templates[family]['form_contract'].setdefault(
            'row_conditions', {'version': 1, 'fields': {}})['fields'].setdefault(key, {})
        for gate in ('allowed_when', 'required_when'):
            spec.setdefault(gate, {}).update(deepcopy(conditions or {}))
        if value_when:
            spec.setdefault('value_when', {}).update(deepcopy(value_when))


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
    # RCF38 and RCF39 predate the status column. Both assert a documented route,
    # so each row is translated to say so explicitly and nothing else changes:
    # their expected issues stay byte-identical and their purpose is untouched.
    for fixture in fixtures['cases']:
        if fixture['id'] not in ('RCF38', 'RCF39'):
            continue
        for row in fixture['values']['rotor_adapter_fitments']['rows']:
            row['values']['status'] = COMPATIBLE
        fixture['successor_translation'] = (
            'Se añade status="Compatible declarado", que la fila ya significaba. '
            'No se altera ninguna expectativa ni el propósito adjudicado.')

    # BA-1. The fitment table could only say yes. A manufacturer that documents
    # an exclusion — this adapter, but not with that rotor — had nowhere to put
    # it, so the absence of a row and a documented refusal read the same.
    # And the frame's own base size was an untyped optional figure: unpublished
    # and unasked looked identical.
    adapter = templates['brake_mount_adapter']
    fitments = 'brake_adapter_fitments'
    extend(definitions, fitments, [
        column('status', 'Estado declarado', 'token', required=True,
               options=[COMPATIBLE, EXCLUDED, CONDITIONAL]),
        column('frame_base_form', 'Forma de la base publicada', 'token',
               required=True, options=[DECLARED, UNPUBLISHED, OEM_LITERAL]),
        # A fork's native size is sometimes printed as a designation rather
        # than a number; the ficha records what the source prints.
        column('frame_base_designation', 'Base publicada sin descomponer'),
        column('edition', 'Edición o año de la fuente'),
    ], conditions={
        'frame_base_rotor_mm': condition('frame_base_form', DECLARED),
        'frame_base_designation': condition('frame_base_form', OEM_LITERAL),
    }, templates=templates, family='brake_mount_adapter')
    adapter['form_contract']['row_conditions']['fields'][fitments].setdefault(
        'required_when', {})['conditions'] = condition('status', CONDITIONAL)
    adapter['form_contract'].setdefault('helpers', {})[fitments] = (
        'Una fila por configuración completa: posición, base del cuadro u '
        'horquilla, montaje del cáliper y rotor objetivo juntos. Una exclusión '
        'publicada se registra como tal; la ausencia de fila no es un permiso. '
        'Una base no publicada queda pendiente y no se completa por costumbre.')

    # BA-2. Included hardware belonged to a single boolean shared by three
    # families. Which bolts, how many, how long and measured from where are
    # properties of a configuration, and none of them is a compatibility claim.
    hardware = 'brake_adapter_included_hardware'
    hardware_conditions = thread_conditions()
    hardware_conditions['length_mm'] = condition('length_form', DECLARED)
    hardware_conditions['length_datum'] = condition('length_form', DECLARED)
    hardware_conditions['length_designation'] = condition('length_form', OEM_LITERAL)
    table(definitions, templates, hardware, 'Herrajes incluidos declarados',
          ('brake_mount_adapter',), [
              column('piece', 'Pieza incluida', required=True),
              column('piece_kind', 'Tipo de pieza', 'token', required=True,
                     options=['Perno', 'Espaciador', 'Arandela', 'Otra']),
              column('quantity', 'Cantidad', 'integer'),
              column('configuration_row_id', 'Configuración a la que pertenece'),
              column('length_form', 'Forma del largo publicado', 'token',
                     required=True, options=[DECLARED, UNPUBLISHED, OEM_LITERAL]),
              column('length_mm', 'Largo publicado', 'decimal', unit='mm',
                     positive=True),
              column('length_datum', 'Desde qué punto se mide ese largo'),
              column('length_designation', 'Largo publicado sin descomponer'),
              *thread_columns(),
              column('conditions', 'Condiciones publicadas'),
              column('source_url', 'Fuente', 'url'),
          ], conditions=hardware_conditions,
          helper=('Lo que viene en la caja, por configuración cuando el '
                  'fabricante lo separa. Un largo sin su punto de medida no es '
                  'un largo, y ningún herraje incluido acredita que el conjunto '
                  'sirva: eso lo dice la fila de configuración, no la bolsa.'))
    adapter['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'hardware_configuration', 'field': hardware,
        'column': 'configuration_row_id', 'target_field': fitments,
        'label_columns': ['adapter_model', 'position']}]}
    retire(adapter, ['bolts_included'])

    # BA-3. The rotor adapter carried one free-text thread cell doing two jobs:
    # the thread by which the adapter fixes to the hub, and the thread of a
    # lockring that belongs to the ring itself. RCF39 exists precisely because
    # a Centerlock route may still document its ring, so the cell keeps its
    # place and an optional owner column says whose thread it is.
    rotor = templates['rotor_mount_adapter']
    rotor_fitments = 'rotor_adapter_fitments'
    extend(definitions, rotor_fitments, [
        column('status', 'Estado declarado', 'token', required=True,
               options=[COMPATIBLE, EXCLUDED, CONDITIONAL]),
        column('thread_owner', 'De quién es la rosca descrita', 'token',
               options=['Fijación a la maza', 'Anillo propio del adaptador',
                        'No declarado']),
        column('edition', 'Edición o año de la fuente'),
    ], templates=templates, family='rotor_mount_adapter')
    rotor['form_contract']['row_conditions']['fields'][rotor_fitments].setdefault(
        'required_when', {})['conditions'] = condition('status', CONDITIONAL)
    rotor['form_contract'].setdefault('helpers', {})[rotor_fitments] = (
        'La dirección importa: qué maza recibe el adaptador y qué rotor acepta '
        'después. La rosca descrita puede ser la de fijación a la maza o la del '
        'anillo propio, y no son la misma; una ruta Centerlock puede conservar '
        'los datos de su anillo. Una exclusión publicada por modelo de rotor se '
        'registra como exclusión, no como fila ausente.')

    # BA-4. Every spare took the shared thread scalar, so a return spring was
    # asked which thread it has. A brake spare is threaded, clipped or sprung,
    # and the shape of each piece belongs to the piece.
    small = templates['brake_small_part']
    definitions['brake_part_kind']['allowed_values'] = (
        definitions['brake_part_kind']['allowed_values'][:-1]
        + ['Clip / retención sin rosca', 'Otro'])
    pieces = 'brake_small_part_components'
    table(definitions, templates, pieces, 'Piezas declaradas del repuesto',
          ('brake_small_part',), [
              column('piece', 'Pieza declarada', required=True),
              column('piece_kind', 'Tipo de pieza', 'token', required=True,
                     options=['Pasador de pastilla', 'Clip de retención',
                              'Resorte', 'Perno / tornillo', 'Arandela', 'Otra']),
              column('quantity', 'Cantidad', 'integer'),
              *thread_columns(),
              column('conditions', 'Modelo, generación y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, conditions=thread_conditions(),
          helper=('Una fila por pieza, con su propia forma. Un resorte y un '
                  'clip no tienen rosca y no se les pregunta por ella; un '
                  'pasador puede llevarla o retenerse con un clip. Que una '
                  'pieza del juego sea un tornillo no convierte al resto en '
                  'tornillos.'))
    small['form_contract']['row_conditions']['fields'][pieces]['value_when'] = {
        'thread_form': [{
            'when': condition('piece_kind', ['Resorte', 'Clip de retención']),
            'expected': {'value_type': 'token', 'value': UNTHREADED}}]}
    retire(small, ['thread'])

    # BA-5. The hub brake mixed the mechanism with the assembly it arrives in
    # and with how it is actually worked. Sheldon settles the coaster: it is a
    # rear hub, worked by back-pedalling, with a reaction arm clamped to the
    # chainstay. Nothing there says anything about the front wheel, and no rule
    # here invents one.
    hub = templates['hub_brake']
    configs = 'hub_brake_configurations'
    table(definitions, templates, configs, 'Configuraciones declaradas del freno de maza',
          ('hub_brake',), [
              column('configuration', 'Configuración declarada', required=True),
              column('mechanism', 'Mecanismo', 'token', required=True,
                     options=['Banda', 'Tambor', 'Rodillo (roller)', COASTER, 'Otro']),
              column('product_scope', 'Qué es el producto', 'token', required=True,
                     options=['Freno integrado en la maza',
                              'Maza con freno y cambio interno',
                              'Pieza de freno para montar en una maza', 'Otro']),
              column('position', 'Rueda declarada', 'token', required=True,
                     options=['Delantera', REAR, 'No declarada']),
              column('actuation', 'Accionamiento real', 'token', required=True,
                     options=['Cable', 'Varilla', BACKPEDAL, 'Otro']),
              column('reaction_arm_required', 'Requiere brazo de reacción', 'token',
                     options=['Sí', 'No', 'No declarado']),
              column('reaction_arm_fixing', 'Dónde se fija el brazo de reacción'),
              column('drum_form', 'Forma del diámetro publicado', 'token',
                     required=True, options=[DECLARED, UNPUBLISHED, OEM_LITERAL]),
              column('drum_diameter_mm', 'Diámetro del tambor', 'decimal',
                     unit='mm', positive=True),
              column('drum_designation', 'Diámetro publicado sin descomponer'),
              column('axle_fit', 'Eje y anchura declarados'),
              column('conditions', 'Modelo, edición y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True,
          conditions={
              'drum_diameter_mm': condition('drum_form', DECLARED),
              'drum_designation': condition('drum_form', OEM_LITERAL),
              'reaction_arm_fixing': condition('reaction_arm_required', 'Sí'),
          },
          helper=('El mecanismo, el conjunto en que llega y cómo se acciona son '
                  'tres cosas distintas. Un contrapedal es una maza trasera '
                  'accionada al pedalear hacia atrás y su brazo de reacción se '
                  'sujeta a la vaina. Nada de eso dice qué freno lleva la rueda '
                  'delantera, y esta ficha no lo deduce.'))
    hub['form_contract']['row_conditions']['fields'][configs]['value_when'] = {
        'actuation': [{'when': condition('mechanism', COASTER),
                       'expected': {'value_type': 'token', 'value': BACKPEDAL}}],
        'position': [{'when': condition('mechanism', COASTER),
                      'expected': {'value_type': 'token', 'value': REAR}}],
        'reaction_arm_required': [{'when': condition('mechanism', COASTER),
                                   'expected': {'value_type': 'token', 'value': 'Sí'}}],
    }
    retire(hub, ['drum_diameter_mm', 'axle_fit', 'reaction_arm_mount',
                 'brake_actuation'])

    fixtures['cases'].extend(_cases(fitments, hardware, rotor_fitments, pieces, configs))

    review_brake_parts(definitions, templates, fixtures)

    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Brake adapter and hub brake reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


def _cases(fitments, hardware, rotor_fitments, pieces, configs):
    fit = lambda **kw: dict({
        'position': 'Delantero', 'frame_mount': 'Post Mount',
        'caliper_mount': 'Post Mount', 'rotor_diameter_mm': '180',
        'adapter_model': 'Sintético', 'status': COMPATIBLE,
        'frame_base_form': UNPUBLISHED,
        'source_url': PARK_ALIGN}, **kw)
    rot = lambda **kw: dict({
        'hub_mount': 'Centerlock', 'rotor_mount': '6 pernos',
        'status': COMPATIBLE, 'source_url': 'https://example.com/synthetic-rotor-adapter'}, **kw)
    coaster = lambda **kw: dict({
        'configuration': 'Sintética', 'mechanism': COASTER,
        'product_scope': 'Freno integrado en la maza', 'position': REAR,
        'actuation': BACKPEDAL, 'reaction_arm_required': 'Sí',
        'reaction_arm_fixing': 'Vaina', 'drum_form': UNPUBLISHED,
        'source_url': SHELDON_COASTER}, **kw)
    return [
        # --- BA-1 / BA-2: mount adapter -------------------------------------
        # A documented exclusion is a row, not an absence.
        case('ba_documented_exclusion_is_recordable', 'brake_mount_adapter',
             {fitments: rows(fit(status=EXCLUDED, caliper_brand='Sintética',
                                 caliper_model='Sintético'))}),
        case('ba_conditional_fitment_needs_its_condition', 'brake_mount_adapter',
             {fitments: rows(fit(status=CONDITIONAL))},
             pending=[('row_required_missing', fitments)]),
        # An unpublished frame base stays pending; it is never filled in.
        case('ba_unpublished_base_cannot_carry_a_figure', 'brake_mount_adapter',
             {fitments: rows(fit(frame_base_form=UNPUBLISHED,
                                 frame_base_rotor_mm='160'))},
             blocking=[('row_field_applicability', fitments)]),
        case('ba_declared_base_and_target_travel_together', 'brake_mount_adapter',
             {fitments: rows(fit(frame_base_form=DECLARED,
                                 frame_base_rotor_mm='160',
                                 rotor_diameter_mm='180'))}),
        case('ba_base_published_as_a_designation', 'brake_mount_adapter',
             {fitments: rows(fit(frame_base_form=OEM_LITERAL,
                                 frame_base_designation='Designación sintética'))}),
        case('ba_designated_base_cannot_carry_a_figure', 'brake_mount_adapter',
             {fitments: rows(fit(frame_base_form=OEM_LITERAL,
                                 frame_base_designation='Designación sintética',
                                 frame_base_rotor_mm='160'))},
             blocking=[('row_field_applicability', fitments)]),
        # Included hardware belongs to a configuration and is not a claim.
        case('ba_hardware_belongs_to_a_configuration', 'brake_mount_adapter',
             {fitments: rows(fit()), hardware: rows(
                 {'piece': 'Perno de cáliper', 'piece_kind': 'Perno',
                  'quantity': '2', 'configuration_row_id': 'r1',
                  'length_form': DECLARED, 'length_mm': '18',
                  'length_datum': 'Bajo cabeza', 'thread_form': THREADED,
                  'thread_diameter_unit': MM, 'thread_diameter_mm': '6',
                  'thread_pitch_unit': MM, 'thread_pitch_mm': '1'})}),
        case('ba_hardware_cannot_point_at_absent_configuration', 'brake_mount_adapter',
             {fitments: rows(fit()), hardware: rows(
                 {'piece': 'Perno', 'piece_kind': 'Perno', 'configuration_row_id': 'r9',
                  'length_form': UNPUBLISHED, 'thread_form': UNTHREADED})},
             blocking=[('row_reference_unresolved', hardware)]),
        case('ba_length_without_datum_is_pending', 'brake_mount_adapter',
             {fitments: rows(fit()), hardware: rows(
                 {'piece': 'Perno', 'piece_kind': 'Perno', 'length_form': DECLARED,
                  'length_mm': '18', 'thread_form': UNTHREADED})},
             pending=[('row_required_missing', hardware)]),
        # A spacer carries no thread and is not asked for one.
        case('ba_spacer_is_not_threaded', 'brake_mount_adapter',
             {fitments: rows(fit()), hardware: rows(
                 {'piece': 'Espaciador', 'piece_kind': 'Espaciador',
                  'length_form': UNPUBLISHED, 'thread_form': UNTHREADED,
                  'thread_pitch_mm': '1'})},
             blocking=[('row_field_applicability', hardware)]),
        # --- BA-3: rotor adapter --------------------------------------------
        # A Centerlock route keeps its ring detail; that is RCF39's whole point.
        case('ba_centerlock_route_keeps_its_ring_thread', 'rotor_mount_adapter',
             {rotor_fitments: rows(rot(
                 hub_thread_spec='Información sintética del anillo',
                 thread_owner='Anillo propio del adaptador'))}),
        # A thread that fixes the adapter to the hub is the other owner.
        case('ba_hub_fixing_thread_declares_its_owner', 'rotor_mount_adapter',
             {rotor_fitments: rows(rot(
                 hub_mount='Rosca especificada', rotor_mount='6 pernos',
                 hub_thread_spec='Rosca sintética de fijación',
                 thread_owner='Fijación a la maza'))}),
        # A rotor excluded by the adapter's own documentation is recordable.
        case('ba_rotor_exclusion_by_model_is_recordable', 'rotor_mount_adapter',
             {rotor_fitments: rows(rot(status=EXCLUDED, rotor_model='Sintético',
                                       conditions='Excluido por su fuente'))}),
        # --- BA-4: brake spares ---------------------------------------------
        case('ba_spring_is_never_threaded', 'brake_small_part',
             {'brake_part_kind': 'Resorte de retorno (freno de llanta)',
              pieces: rows({'piece': 'Resorte', 'piece_kind': 'Resorte',
                            'thread_form': THREADED})},
             blocking=[('row_value_conflict', pieces)]),
        case('ba_clip_is_never_threaded', 'brake_small_part',
             {'brake_part_kind': 'Clip / retención sin rosca',
              pieces: rows({'piece': 'Clip', 'piece_kind': 'Clip de retención',
                            'thread_form': UNTHREADED})}),
        # One kit, a threaded pin and an unthreaded clip side by side.
        case('ba_pin_and_clip_keep_their_own_shapes', 'brake_small_part',
             {'brake_part_kind': 'Pasador / pin de pastilla', pieces: rows(
                 {'piece': 'Pasador', 'piece_kind': 'Pasador de pastilla',
                  'quantity': '1', 'thread_form': THREADED,
                  'thread_diameter_unit': MM, 'thread_diameter_mm': '4',
                  'thread_pitch_unit': MM, 'thread_pitch_mm': '0.7'},
                 {'piece': 'Clip de seguridad', 'piece_kind': 'Clip de retención',
                  'quantity': '1', 'thread_form': UNTHREADED})}),
        case('ba_unthreaded_piece_cannot_carry_a_pitch', 'brake_small_part',
             {'brake_part_kind': 'Otro', pieces: rows(
                 {'piece': 'Clip', 'piece_kind': 'Clip de retención',
                  'thread_form': UNTHREADED, 'thread_pitch_mm': '0.7'})},
             blocking=[('row_field_applicability', pieces)]),
        # --- BA-5: hub brake -------------------------------------------------
        case('ba_coaster_is_a_rear_hub_worked_by_backpedalling', 'hub_brake',
             {'hub_brake_kind': COASTER, configs: rows(coaster())},
             sources=[SHELDON_COASTER]),
        case('ba_coaster_cannot_be_cable_actuated', 'hub_brake',
             {'hub_brake_kind': COASTER, configs: rows(coaster(actuation='Cable'))},
             blocking=[('row_value_conflict', configs)],
             sources=[SHELDON_COASTER]),
        case('ba_coaster_cannot_be_declared_front', 'hub_brake',
             {'hub_brake_kind': COASTER,
              configs: rows(coaster(position='Delantera'))},
             blocking=[('row_value_conflict', configs)],
             sources=[SHELDON_COASTER]),
        # A drum brake on the front wheel is ordinary and stays recordable.
        case('ba_front_drum_is_ordinary', 'hub_brake',
             {'hub_brake_kind': 'Tambor', configs: rows(
                 {'configuration': 'Sintética', 'mechanism': 'Tambor',
                  'product_scope': 'Freno integrado en la maza',
                  'position': 'Delantera', 'actuation': 'Cable',
                  'reaction_arm_required': 'Sí', 'reaction_arm_fixing': 'Horquilla',
                  'drum_form': UNPUBLISHED})}),
        # The mechanism and the assembly it arrives in are separate answers.
        case('ba_brake_with_internal_gears_is_one_assembly', 'hub_brake',
             {'hub_brake_kind': 'Tambor', configs: rows(
                 {'configuration': 'Sintética', 'mechanism': 'Tambor',
                  'product_scope': 'Maza con freno y cambio interno',
                  'position': REAR, 'actuation': 'Cable',
                  'reaction_arm_required': 'Sí', 'reaction_arm_fixing': 'Vaina',
                  'drum_form': UNPUBLISHED})}),
        case('ba_unpublished_drum_cannot_carry_a_figure', 'hub_brake',
             {'hub_brake_kind': 'Tambor', configs: rows(
                 {'configuration': 'Sintética', 'mechanism': 'Tambor',
                  'product_scope': 'Freno integrado en la maza', 'position': REAR,
                  'actuation': 'Cable', 'drum_form': UNPUBLISHED,
                  'drum_diameter_mm': '90'})},
             blocking=[('row_field_applicability', configs)]),
        # A reaction arm that is not required has no fixing point to declare.
        case('ba_no_reaction_arm_has_no_fixing', 'hub_brake',
             {'hub_brake_kind': 'Rodillo (roller)', configs: rows(
                 {'configuration': 'Sintética', 'mechanism': 'Rodillo (roller)',
                  'product_scope': 'Freno integrado en la maza', 'position': REAR,
                  'actuation': 'Cable', 'reaction_arm_required': 'No',
                  'reaction_arm_fixing': 'Vaina', 'drum_form': UNPUBLISHED})},
             blocking=[('row_field_applicability', configs)]),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'brake-adapter-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'brake-adapter-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
